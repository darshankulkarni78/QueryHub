from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from .config import FRONTEND_URL, OPENROUTER_API_KEY, QDRANT_COLLECTION, EMBEDDING_MODEL
from .db import Base, engine, SessionLocal
from .models import Document, Chunk, Embedding, Job
from .worker import start_indexing_thread
from .clients import upload_file_to_supabase, get_qdrant
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

app = FastAPI(title="QueryHub - Backend", debug=True)

@app.middleware("http")
async def debug_exceptions(request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise

origins = [FRONTEND_URL] if FRONTEND_URL else []

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
        hits = qclient.search(collection_name=QDRANT_COLLECTION, query_vector=qv, limit=k)

        contexts = []
        for h in hits:
            payload = h.payload or {}
            text = payload.get("chunk_text") or ""
            contexts.append({"score": h.score, "payload": payload, "text": text})

        return contexts

    except Exception as e:
        print("Qdrant search failure:")
        traceback.print_exc()
        return []


async def generate_answer(prompt: str, context_texts: list):
    system_prompt = "You answer strictly using provided context chunks."
    augmented = f"{system_prompt}\n\nCONTEXT:\n" + "\n---\n".join(context_texts) + f"\n\nQUESTION:\n{prompt}"

    url = "https://172.64.155.202/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Host": "api.openrouter.ai"
    }
    data = {
        "model": "neta-llama/llama-3.3-8b",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": augmented}
        ],
        "max_tokens": 512,
        "temperature": 0.2
    }

    async with httpx.AsyncClient(verify=False, timeout=60, trust_env=False) as client:
        resp = await client.post(url, json=data, headers=headers)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]



@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.post("/ask")
async def ask_question(payload: dict):
    print("ASK STARTED")
    try:
        query = payload.get("query")
        if not query:
            raise HTTPException(status_code=400, detail="Query field is required")

        contexts = retrieve_top_k(query, k=4)
        print("CONTEXTS:", contexts)
        context_texts = [c["text"] for c in contexts] if contexts else []
        print("TEXTS:", context_texts)

        if not context_texts:
            return {"answer": "No relevant context. Upload documents first.", "contexts": []}
        
        print("CALLING MODEL")
        answer = await generate_answer(query, context_texts)

        return {"answer": answer, "contexts": context_texts}

    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Internal error during ask")