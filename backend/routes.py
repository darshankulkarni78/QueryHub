from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from sqlalchemy.sql import func

from .config import FRONTEND_URL, GROQ_API_KEY, QDRANT_COLLECTION, EMBEDDING_MODEL
from .db import Base, engine, SessionLocal
from .models import Document, Job, Chunk, ChatSession, Message
from .worker import start_indexing_thread
from .clients import upload_file_to_supabase, get_qdrant
from qdrant_client.http import models as qmodels
import uuid
import tempfile
import os
from sentence_transformers import SentenceTransformer
import httpx
import traceback
import sys

def unhandled(exc_type, exc, tb):
    traceback.print_exception(exc_type, exc, tb)

sys.excepthook = unhandled


class AskRequest(BaseModel):
    query: str
    document_id: Optional[str] = None  # Optional: search only this document's collection


class ContextChunk(BaseModel):
    score: float
    text: str
    payload: Dict[str, Any]


class AskResponse(BaseModel):
    answer: str
    contexts: List[ContextChunk]


class DocumentStatus(BaseModel):
    id: str
    filename: str
    created_at: datetime
    status: str


class CreateChatRequest(BaseModel):
    title: str
    document_id: Optional[str] = None  # Optional: link to specific document


class ChatSessionResponse(BaseModel):
    id: str
    title: str
    document_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    message_count: int = 0


class MessageResponse(BaseModel):
    id: str
    session_id: str
    role: str
    content: str
    contexts: List[ContextChunk] = []
    created_at: datetime


class AddMessageRequest(BaseModel):
    role: str  # 'user' or 'assistant'
    content: str
    contexts: List[ContextChunk] = []


app = FastAPI(title="QueryHub - Backend", debug=True)

@app.middleware("http")
async def debug_exceptions(request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise

# For local development and multi-platform frontends (web, mobile, desktop)
# we allow all origins. If you want to restrict this, change to a list of
# specific frontend URLs in production.
origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def init_db():
    try:
        # Ensure all models are imported before creating tables
        from .models import Document, Job, Chunk, Embedding, ChatSession, Message
        Base.metadata.create_all(bind=engine)
        print("[OK] Database tables initialized")
        print(f"  Tables: {list(Base.metadata.tables.keys())}")
    except Exception as e:
        print(f"[WARN] DB init failed: {e}")

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename")

    tmp_dir = tempfile.gettempdir()
    tmp_path = os.path.join(tmp_dir, f"{uuid.uuid4()}_{file.filename}")

    try:
        with open(tmp_path, "wb") as f:
            f.write(await file.read())

        s3_key = f"uploads/{uuid.uuid4()}_{file.filename}"

        try:
            public_url = upload_file_to_supabase(tmp_path, s3_key)
        except Exception:
            public_url = f"s3://{s3_key}"

        db = SessionLocal()
        try:
            doc = Document(filename=file.filename, s3_key=s3_key, content_type=file.content_type)
            db.add(doc)
            db.commit()
            db.refresh(doc)
            start_indexing_thread(doc.id, tmp_path)

            return {
                "document_id": doc.id,
                "s3_key": s3_key,
                "public_url": public_url,
                # from the frontend perspective, the document immediately
                # moves from "uploading" to "processing"
                "status": "processing",
                "filename": doc.filename,
                "created_at": doc.created_at.isoformat() if doc.created_at else None,
                "message": "File uploaded successfully"
            }
        finally:
            db.close()

    except Exception as e:
        print(e)
        raise HTTPException(status_code=500, detail=str(e))


_model = None

def get_embedding_model():
    global _model
    if _model is None:
        _model = SentenceTransformer(EMBEDDING_MODEL)
    return _model


def get_document_collection_name(document_id: str) -> str:
    """Get the Qdrant collection name for a specific document."""
    return f"doc-{document_id}"


def ensure_collection_exists(qclient, collection_name: str, vector_size: int = 384):
    """Ensure a Qdrant collection exists, create it if it doesn't."""
    max_retries = 3
    for attempt in range(max_retries):
        try:
            # Try to get collection info - if it exists, this will succeed
            try:
                qclient.get_collection(collection_name)
                return  # Collection exists, we're done
            except Exception:
                # Collection doesn't exist, create it
                pass
            
            # Create collection
            qclient.create_collection(
                collection_name=collection_name,
                vectors_config=qmodels.VectorParams(
                    size=vector_size,
                    distance=qmodels.Distance.COSINE
                )
            )
            print(f"  [OK] Created Qdrant collection: {collection_name}")
            return
        except Exception as e:
            if attempt < max_retries - 1:
                import time
                time.sleep(1)  # Wait 1 second before retry
                print(f"  [WARN] Attempt {attempt + 1}/{max_retries} failed, retrying...")
            else:
                print(f"  [WARN] Could not ensure collection exists after {max_retries} attempts: {e}")
                raise


def retrieve_top_k(query: str, k: int = 4, document_id: Optional[str] = None):
    """
    Retrieve top k relevant chunks. If document_id is provided, search only that document's collection.
    """
    model = get_embedding_model()
    qv = model.encode(query).tolist()
    vector_size = len(qv)

    try:
        qclient = get_qdrant()
        
        if document_id:
            # Search only this document's collection
            collection_name = get_document_collection_name(document_id)
            ensure_collection_exists(qclient, collection_name, vector_size)
        else:
            # If no document_id provided, return empty (user should specify which document to search)
            print(f"[WARN] No document_id provided for search, returning empty results")
            return []
        
        # Get more results to deduplicate
        hits = qclient.search(collection_name=collection_name, query_vector=qv, limit=k * 2)

        contexts = []
        seen_texts = set()  # Deduplicate by text content
        
        for h in hits:
            payload = h.payload or {}
            text = payload.get("chunk_text") or ""
            
            # Skip if we've already seen this exact text (duplicate chunks)
            text_hash = text[:200]  # Use first 200 chars as fingerprint
            if text_hash in seen_texts:
                continue
            seen_texts.add(text_hash)
            
            # Truncate very long chunks to avoid huge context
            if len(text) > 1000:
                text = text[:1000] + "..."
            
            contexts.append({"score": h.score, "payload": payload, "text": text})
            
            # Stop once we have enough unique contexts
            if len(contexts) >= k:
                break

        return contexts

    except Exception as e:
        error_type = type(e).__name__
        error_msg = str(e)[:200] if str(e) else "Unknown error"
        print(f"[WARN] Qdrant search failed ({error_type}): {error_msg}")
        return []


async def generate_answer(prompt: str, context_texts: list):
    system_prompt = "You are a helpful assistant. Answer the question concisely using only the provided context. Keep your answer brief and to the point (2-4 sentences). If the context doesn't contain the answer, say so."
    
    # Limit context to avoid huge prompts
    limited_contexts = context_texts[:3]  # Use top 3 most relevant chunks
    context_str = "\n---\n".join(limited_contexts)
    augmented = f"CONTEXT:\n{context_str}\n\nQUESTION:\n{prompt}"

    # Use Groq API (free tier, reliable DNS)
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json",
    }
    data = {
        "model": "llama-3.1-8b-instant",  # Fast, free model from Groq
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": augmented}
        ],
        "max_tokens": 256,  # Reduced for more concise answers
        "temperature": 0.3,
    }

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json=data, headers=headers)
            resp.raise_for_status()
            result = resp.json()
            return result["choices"][0]["message"]["content"]
    except httpx.ConnectError as e:
        print(f"[ERROR] Connection error to Groq: {e}")
        raise Exception("Failed to connect to AI service. Please check your internet connection.")
    except httpx.HTTPStatusError as e:
        print(f"[ERROR] HTTP error from Groq: {e.response.status_code} - {e.response.text[:200]}")
        raise Exception(f"AI service error: {e.response.status_code}")
    except Exception as e:
        print(f"[ERROR] Unexpected error calling Groq: {e}")
        raise Exception(f"Error generating answer: {str(e)}")



@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.get("/documents/{document_id}/status")
def get_document_status(document_id: str):
    """Debug endpoint to check document processing status."""
    db = SessionLocal()
    try:
        doc = db.query(Document).filter(Document.id == document_id).first()
        if not doc:
            raise HTTPException(status_code=404, detail="Document not found")
        
        job = db.query(Job).filter(Job.document_id == document_id).order_by(Job.created_at.desc()).first()
        
        return {
            "document_id": str(doc.id),
            "filename": doc.filename,
            "job": {
                "job_id": str(job.job_id) if job else None,
                "status": job.status if job else "no_job",
                "progress": job.progress if job else 0,
                "error": job.error if job else None,
                "created_at": job.created_at.isoformat() if job and job.created_at else None,
            } if job else None,
        }
    finally:
        db.close()


@app.get("/documents", response_model=List[DocumentStatus])
def list_documents():
    """
    Lightweight endpoint for frontends (React, Flutter, etc.) to show
    uploaded documents and their ingestion status.
    """
    db = SessionLocal()
    try:
        docs = db.query(Document).all()
        if not docs:
            return []

        doc_ids = [d.id for d in docs]

        # fetch latest job per document (if any)
        jobs = (
            db.query(Job)
            .filter(Job.document_id.in_(doc_ids))
            .order_by(Job.document_id, Job.created_at.desc())
            .all()
        )

        latest_job_by_doc: Dict[str, Job] = {}
        for job in jobs:
            # first job per document in this ordered list is the latest
            if job.document_id not in latest_job_by_doc:
                latest_job_by_doc[job.document_id] = job

        results: List[DocumentStatus] = []
        for d in docs:
            job = latest_job_by_doc.get(d.id)
            status = job.status if job else "uploaded"
            results.append(
                DocumentStatus(
                    id=str(d.id),
                    filename=d.filename,
                    created_at=d.created_at,
                    status=status,
                )
            )

        return results
    finally:
        db.close()


@app.delete("/documents/{document_id}")
def delete_document(document_id: str):
    """
    Delete a document and its associated chunks/embeddings/jobs/chat_sessions.
    Chat sessions and their messages are cascade deleted automatically.
    Best-effort delete in Qdrant as well; failures there don't block DB cleanup.
    Also deletes the file from Supabase storage.
    """
    db = SessionLocal()
    try:
        doc = db.query(Document).filter(Document.id == document_id).first()
        if not doc:
            raise HTTPException(status_code=404, detail="Document not found")

        # Count chat sessions that will be deleted (for logging)
        chat_count = db.query(ChatSession).filter(ChatSession.document_id == document_id).count()
        if chat_count > 0:
            print(f"  [INFO] Will delete {chat_count} chat session(s) and their messages (CASCADE)")

        # Delete the entire document's collection from Qdrant
        try:
            qclient = get_qdrant()
            collection_name = get_document_collection_name(document_id)
            try:
                # Try to delete the entire collection (most efficient)
                qclient.delete_collection(collection_name=collection_name)
                print(f"  [OK] Deleted Qdrant collection: {collection_name}")
            except Exception as coll_err:
                # If collection doesn't exist or deletion fails, try deleting individual points
                print(f"  [WARN] Could not delete collection, trying individual points: {coll_err}")
                chunks = db.query(Chunk).filter(Chunk.document_id == document_id).all()
                if chunks:
                    point_ids = [str(chunk.id) for chunk in chunks]
                    try:
                        qclient.delete(
                            collection_name=collection_name,
                            points_selector=qmodels.PointIdsList(points=point_ids),
                        )
                        print(f"  [OK] Deleted {len(point_ids)} points from Qdrant")
                    except Exception:
                        # Also try the old collection name for backward compatibility
                        try:
                            qclient.delete(
                                collection_name=QDRANT_COLLECTION,
                                points_selector=qmodels.PointIdsList(points=point_ids),
                            )
                            print(f"  [OK] Deleted {len(point_ids)} points from legacy collection")
                        except Exception:
                            pass
        except Exception as e:
            print(f"  [WARN] Qdrant deletion failed: {e}")
            # Continue anyway - DB deletion will still work

        # Delete from Supabase storage
        try:
            from .clients import delete_file_from_supabase
            if doc.s3_key:
                delete_file_from_supabase(doc.s3_key)
                print(f"  [OK] Deleted file from Supabase storage: {doc.s3_key}")
        except Exception as e:
            print(f"  [WARN] Failed to delete from Supabase storage: {e}")
            # Continue anyway - at least we'll clean up the database

        db.delete(doc)
        db.commit()
        return {"status": "deleted", "document_id": document_id}
    finally:
        db.close()


@app.post("/ask", response_model=AskResponse)
async def ask_question(payload: AskRequest):
    print("ASK STARTED")
    try:
        query = payload.query
        document_id = payload.document_id

        contexts = retrieve_top_k(query, k=4, document_id=document_id)
        print(f"CONTEXTS: Found {len(contexts)} context chunks")
        context_texts = [c["text"] for c in contexts] if contexts else []
        print(f"TEXTS: Extracted {len(context_texts)} text chunks")

        if not context_texts:
            # no usable context yet (likely no documents uploaded / processed)
            return AskResponse(
                answer="No relevant context. Upload documents first.",
                contexts=[],
            )
        
        print("CALLING MODEL")
        answer = await generate_answer(query, context_texts)

        # include full context objects so frontends can show "Sources" UI
        api_contexts: List[ContextChunk] = []
        for c in contexts:
            api_contexts.append(
                ContextChunk(
                    score=float(c.get("score", 0.0)),
                    text=c.get("text") or "",
                    payload=c.get("payload") or {},
                )
            )

        return AskResponse(answer=answer, contexts=api_contexts)

    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Internal error during ask")


# ===== CHAT SESSION ENDPOINTS =====

@app.post("/chats", response_model=ChatSessionResponse)
def create_chat_session(payload: CreateChatRequest):
    """Create a new chat session, optionally linked to a document"""
    db = SessionLocal()
    try:
        # Validate document_id if provided
        if payload.document_id:
            doc = db.query(Document).filter(Document.id == payload.document_id).first()
            if not doc:
                raise HTTPException(status_code=404, detail="Document not found")
        
        session = ChatSession(
            title=payload.title,
            document_id=payload.document_id
        )
        db.add(session)
        db.commit()
        db.refresh(session)
        
        return ChatSessionResponse(
            id=str(session.id),
            title=session.title,
            document_id=str(session.document_id) if session.document_id else None,
            created_at=session.created_at,
            updated_at=session.updated_at,
            message_count=0
        )
    finally:
        db.close()


@app.get("/chats", response_model=List[ChatSessionResponse])
def list_chat_sessions(document_id: str = None):
    """List all chat sessions, optionally filtered by document_id"""
    db = SessionLocal()
    try:
        query = db.query(ChatSession)
        if document_id:
            query = query.filter(ChatSession.document_id == document_id)
        
        sessions = query.order_by(ChatSession.updated_at.desc()).all()
        
        result = []
        for session in sessions:
            message_count = db.query(Message).filter(Message.session_id == session.id).count()
            result.append(ChatSessionResponse(
                id=str(session.id),
                title=session.title,
                document_id=str(session.document_id) if session.document_id else None,
                created_at=session.created_at,
                updated_at=session.updated_at,
                message_count=message_count
            ))
        
        return result
    finally:
        db.close()


@app.get("/chats/{session_id}/messages", response_model=List[MessageResponse])
def get_chat_messages(session_id: str):
    """Get all messages for a chat session"""
    db = SessionLocal()
    try:
        session = db.query(ChatSession).filter(ChatSession.id == session_id).first()
        if not session:
            raise HTTPException(status_code=404, detail="Chat session not found")
        
        messages = db.query(Message).filter(Message.session_id == session_id).order_by(Message.created_at).all()
        
        result = []
        for msg in messages:
            # Parse contexts if stored as JSON
            contexts = []
            if msg.contexts:
                import json
                try:
                    contexts_data = json.loads(msg.contexts)
                    contexts = [ContextChunk(**c) for c in contexts_data]
                except:
                    pass
            
            result.append(MessageResponse(
                id=msg.id,
                session_id=msg.session_id,
                role=msg.role,
                content=msg.content,
                contexts=contexts,
                created_at=msg.created_at
            ))
        
        return result
    finally:
        db.close()


@app.post("/chats/{session_id}/messages", response_model=MessageResponse)
def add_message_to_session(session_id: str, payload: AddMessageRequest):
    """Add a message to a chat session"""
    db = SessionLocal()
    try:
        session = db.query(ChatSession).filter(ChatSession.id == session_id).first()
        if not session:
            raise HTTPException(status_code=404, detail="Chat session not found")
        
        # Store contexts as JSON string
        import json
        contexts_json = None
        if payload.contexts:
            contexts_json = json.dumps([c.dict() for c in payload.contexts])
        
        message = Message(
            session_id=session_id,
            role=payload.role,
            content=payload.content,
            contexts=contexts_json
        )
        db.add(message)
        
        # Update session updated_at timestamp
        session.updated_at = datetime.now(timezone.utc)
        db.add(session)
        
        db.commit()
        db.refresh(message)
        
        return MessageResponse(
            id=message.id,
            session_id=message.session_id,
            role=message.role,
            content=message.content,
            contexts=payload.contexts,
            created_at=message.created_at
        )
    finally:
        db.close()


@app.delete("/chats/{session_id}")
def delete_chat_session(session_id: str):
    """Delete a chat session and all its messages"""
    db = SessionLocal()
    try:
        session = db.query(ChatSession).filter(ChatSession.id == session_id).first()
        if not session:
            raise HTTPException(status_code=404, detail="Chat session not found")
        
        # Messages will be cascade deleted due to ondelete="CASCADE" in the model
        db.delete(session)
        db.commit()
        
        return {"status": "deleted", "session_id": session_id}
    finally:
        db.close()