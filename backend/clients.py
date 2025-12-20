from qdrant_client import QdrantClient
from supabase import create_client
from .config import QDRANT_URL, QDRANT_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_BUCKET

_qdrant = None
_supabase = None

def get_qdrant():
    global _qdrant
    if _qdrant is None:
        _qdrant = QdrantClient(
            url=QDRANT_URL,
            api_key=QDRANT_API_KEY,
            prefer_grpc=False,
            timeout=30.0  # 30 second timeout for slow connections
        )
    return _qdrant

def get_supabase():
    global _supabase
    if _supabase is None:
        _supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    return _supabase

def upload_file_to_supabase(local_path: str, filename: str):
    supabase = get_supabase()
    with open(local_path, "rb") as f:
        supabase.storage.from_(SUPABASE_BUCKET).upload(filename, f)
    return supabase.storage.from_(SUPABASE_BUCKET).get_public_url(filename)

def delete_file_from_supabase(s3_key: str):
    """Delete a file from Supabase storage"""
    supabase = get_supabase()
    # The s3_key is like "uploads/uuid_filename.pdf", but storage.remove expects just the path
    supabase.storage.from_(SUPABASE_BUCKET).remove([s3_key])