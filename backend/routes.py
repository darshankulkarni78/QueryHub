from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any
from datetime import datetime

from .config import FRONTEND_URL, OPENROUTER_API_KEY, QDRANT_COLLECTION, EMBEDDING_MODEL
from .db import Base, engine, SessionLocal
from .models import Document, Job, Chunk
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
        Base.metadata.create_all(bind=engine)
        print("✓ Database tables initialized")
    except Exception as e:
        print(f"⚠ DB init failed: {e}")

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


def retrieve_top_k(query: str, k: int = 4):
    model = get_embedding_model()
    qv = model.encode(query).tolist()

    try:
        qclient = get_qdrant()
        # Get more results to deduplicate
        hits = qclient.search(collection_name=QDRANT_COLLECTION, query_vector=qv, limit=k * 2)

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
        print("Qdrant search failure:")
        traceback.print_exc()
        return []


async def generate_answer(prompt: str, context_texts: list):
    system_prompt = "You are a helpful assistant. Answer the question concisely using only the provided context. Keep your answer brief and to the point (2-4 sentences). If the context doesn't contain the answer, say so."
    
    # Limit context to avoid huge prompts
    limited_contexts = context_texts[:3]  # Use top 3 most relevant chunks
    context_str = "\n---\n".join(limited_contexts)
    augmented = f"CONTEXT:\n{context_str}\n\nQUESTION:\n{prompt}"

    # Use proper OpenRouter API URL
    url = "https://api.openrouter.ai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "http://localhost:8000",  # Optional but recommended
    }
    data = {
        "model": "neta-llama/llama-3.3-8b",
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
        print(f"❌ Connection error to OpenRouter: {e}")
        raise Exception("Failed to connect to AI service. Please check your internet connection.")
    except httpx.HTTPStatusError as e:
        print(f"❌ HTTP error from OpenRouter: {e.response.status_code} - {e.response.text}")
        raise Exception(f"AI service error: {e.response.status_code}")
    except Exception as e:
        print(f"❌ Unexpected error calling OpenRouter: {e}")
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
    Delete a document and its associated chunks/embeddings/jobs.
    Best-effort delete in Qdrant as well; failures there don't block DB cleanup.
    """
    db = SessionLocal()
    try:
        doc = db.query(Document).filter(Document.id == document_id).first()
        if not doc:
            raise HTTPException(status_code=404, detail="Document not found")

        # Best-effort vector index cleanup: get chunk IDs and delete those points
        try:
            chunks = db.query(Chunk).filter(Chunk.document_id == document_id).all()
            if chunks:
                point_ids = [str(chunk.id) for chunk in chunks]
                qclient = get_qdrant()
                qclient.delete(
                    collection_name=QDRANT_COLLECTION,
                    points_selector=qmodels.PointIdsList(
                        points=point_ids,
                    ),
                )
        except Exception as e:
            # Silently continue; DB deletion will still work
            # Orphaned vectors in Qdrant won't cause issues
            pass

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

        contexts = retrieve_top_k(query, k=4)
        print("CONTEXTS:", contexts)
        context_texts = [c["text"] for c in contexts] if contexts else []
        print("TEXTS:", context_texts)

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