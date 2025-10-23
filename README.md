# QueryHub

QueryHub is a small RAG-style document ingestion and retrieval service. It accepts file uploads, stores them in Supabase storage, extracts text and chunks documents, indexes embeddings in Qdrant, and provides a simple retrieval + generation pipeline using OpenRouter.

This repository contains the backend API (FastAPI) and a separate frontend folder. The backend expects all runtime configuration to be provided via environment variables (see `backend/.env.example`).

Features
- Upload files and store them in Supabase storage
- Extract text and chunk documents for embedding
- Compute embeddings and upsert into Qdrant
- Retrieve top-k chunks for a query and generate answers via OpenRouter

Security note
- Do NOT commit `backend/.env` or any secrets to source control. Use `.env.example` as a template and store real secrets in environment variables or a secrets manager.

Quick start (local development)

1. Create a Python virtual environment and install dependencies

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt
```

2. Create `backend/.env` from `backend/.env.example` and fill in your real credentials (Supabase, Qdrant, OpenRouter, Database URL, etc.).

3. Run the backend

```powershell
uvicorn backend.main:app --reload
```

The backend runs on http://127.0.0.1:8000 by default.

Files of interest
- `backend/` — FastAPI backend code and requirements
- `backend/.env.example` — template of required environment variables

Deploying
- This repo is structured to run with external services (Supabase storage, Qdrant cloud, and a Postgres database). Provide production credentials as environment variables or via your cloud provider secret manager.

Notes
- This repository intentionally centralizes configuration via `backend/config.py`, which reads environment variables. Ensure all services are configured via environment variables.
- The repository no longer contains a Docker Compose file by design; the stack should be wired to external managed services in production.
