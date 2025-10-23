from .config import OPENROUTER_API_KEY, QDRANT_COLLECTION, EMBEDDING_MODEL
from sentence_transformers import SentenceTransformer
from .clients import get_qdrant
import requests

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

def generate_answer(prompt: str, context_texts: list) -> str:
    system_prompt = "You are an assistant that answers using supplied context. Cite chunk provenance if relevant."
    augmented_prompt = f"{system_prompt}\n\nCONTEXT:\n" + "\n\n---\n\n".join(context_texts) + f"\n\nQUESTION:\n{prompt}"
    url = "https://api.openrouter.ai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {OPENROUTER_API_KEY}"}
    data = {
        "model": "neta-llama/llama-3.3-8b",
        "messages": [{"role":"system","content":system_prompt},{"role":"user","content":augmented_prompt}],
        "max_tokens": 512,
        "temperature": 0.2
    }
    resp = requests.post(url, json=data, headers=headers, timeout=60)
    resp.raise_for_status()
    result = resp.json()
    content = result["choices"][0]["message"]["content"]
    return content
