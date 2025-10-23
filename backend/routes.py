from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from .config import FRONTEND_URL, OPENROUTER_API_KEY, QDRANT_COLLECTION, EMBEDDING_MODEL
from .db import Base, engine, SessionLocal
from .models import Document
from .worker import start_indexing_thread
from .clients import upload_file_to_supabase, get_qdrant
import uuid
from sentence_transformers import SentenceTransformer
import httpx

app = FastAPI(title="QueryHub - Backend")

origins = [FRONTEND_URL] if FRONTEND_URL else []

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename")

    tmp_path = f"/tmp/{uuid.uuid4()}_{file.filename}"
    with open(tmp_path, "wb") as f:
        f.write(await file.read())

    s3_key = f"uploads/{uuid.uuid4()}_{file.filename}"
    public_url = upload_file_to_supabase(tmp_path, s3_key)

    db = SessionLocal()
    try:
        doc = Document(
            filename=file.filename,
            s3_key=s3_key,
            content_type=file.content_type
        )
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

_model = None

def get_embedding_model():
    global _model
    if _model is None:
        _model = SentenceTransformer(EMBEDDING_MODEL)
    return _model

def retrieve_top_k(query: str, k: int = 4):
    model = get_embedding_model()
    qclient = get_qdrant()
    qv = model.encode(query).tolist()
    hits = qclient.search(collection_name=QDRANT_COLLECTION, query_vector=qv, limit=k)
    contexts = []
    for h in hits:
        payload = h.payload or {}
        text = payload.get("text") or payload.get("chunk_text") or ""
        contexts.append({"score": h.score, "payload": payload, "text": text})
    return contexts

async def generate_answer(prompt: str, context_texts: list) -> str:
    system_prompt = "You are an assistant that answers using supplied context. Cite chunk provenance if relevant."
    augmented_prompt = f"{system_prompt}\n\nCONTEXT:\n" + "\n\n---\n\n".join(context_texts) + f"\n\nQUESTION:\n{prompt}"

    url = "https://api.openrouter.ai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {OPENROUTER_API_KEY}"}
    data = {
        "model": "neta-llama/llama-3.3-8b",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": augmented_prompt}
        ],
        "max_tokens": 512,
        "temperature": 0.2
    }

    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(url, json=data, headers=headers)
        resp.raise_for_status()
        result = resp.json()
    return result["choices"][0]["message"]["content"]

@app.post("/ask")
async def ask_question(payload: dict):
    query = payload.get("query")
    if not query:
        raise HTTPException(status_code=400, detail="Query field is required")

    contexts = retrieve_top_k(query, k=4)
    context_texts = [c["text"] for c in contexts]

    try:
        answer = await generate_answer(query, context_texts)
    except httpx.HTTPError as e:
        raise HTTPException(status_code=500, detail=f"OpenRouter API error: {str(e)}")

    return {"answer": answer, "contexts": context_texts}