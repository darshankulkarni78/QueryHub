import os
from dotenv import load_dotenv
from pathlib import Path

env_path = Path(__file__).parent / "backend" / ".env"
load_dotenv(dotenv_path=env_path)

def required_env(key: str) -> str:
	"""Return the value of an environment variable or raise a clear error."""
	val = os.getenv(key)
	if not val:
		raise RuntimeError(f"Required environment variable '{key}' is not set. Please add it to backend/.env or the environment.")
	return val

# OpenRouter
OPENROUTER_API_KEY = required_env("OPENROUTER_API_KEY")

# Supabase storage
SUPABASE_URL = required_env("SUPABASE_URL")
SUPABASE_SERVICE_KEY = required_env("SUPABASE_SERVICE_KEY")
SUPABASE_BUCKET = required_env("SUPABASE_BUCKET")

# Qdrant
QDRANT_API_KEY = required_env("QDRANT_API_KEY")
QDRANT_URL = required_env("QDRANT_URL")
QDRANT_COLLECTION = required_env("QDRANT_COLLECTION")

# Database
DATABASE_URL = required_env("DATABASE_URL")

# Embeddings / chunking
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "2000"))       
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))

# Frontend origin for CORS
FRONTEND_URL = required_env("FRONTEND_URL")