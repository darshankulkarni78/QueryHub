import threading
import uuid
import os
from .db import SessionLocal
from .models import Document, Chunk, Embedding, Job
from .utils import save_upload_to_tmp, extract_text_from_file, chunk_text
from .config import CHUNK_SIZE, CHUNK_OVERLAP, QDRANT_COLLECTION, EMBEDDING_MODEL
from sentence_transformers import SentenceTransformer
from qdrant_client.http import models as qmodels
from .clients import get_qdrant, upload_file_to_supabase

_model = None

def get_embedding_model():
    global _model
    if _model is None:
        _model = SentenceTransformer(EMBEDDING_MODEL)
    return _model

def start_indexing_thread(document_id: str, local_path: str):
    t = threading.Thread(target=process_document, args=(document_id, local_path), daemon=True)
    t.start()

def process_document(document_id: str, local_path: str):
    db = SessionLocal()
    try:
        job = Job(document_id=document_id, status="processing")
        db.add(job); db.commit()

        text = extract_text_from_file(local_path)
        chunks = chunk_text(text, CHUNK_SIZE, CHUNK_OVERLAP)
        model = get_embedding_model()
        qclient = get_qdrant()

        qclient.recreate_collection(
            collection_name=QDRANT_COLLECTION,
            vectors_config=qmodels.VectorParams(size=model.get_sentence_embedding_dimension(), distance=qmodels.Distance.COSINE)
        )

        to_upsert = []
        for idx, c in enumerate(chunks):
            chunk_obj = Chunk(document_id=document_id, chunk_index=idx, text=c, token_count=len(c))
            db.add(chunk_obj); db.commit(); db.refresh(chunk_obj)

            emb = model.encode(c).tolist()
            point = qmodels.PointStruct(
                id=chunk_obj.id,
                vector=emb,
                payload={"document_id": document_id, "chunk_index": idx, "chunk_text": c}
            )
            to_upsert.append(point)

            emb_row = Embedding(chunk_id=chunk_obj.id)
            db.add(emb_row); db.commit()

        if to_upsert:
            qclient.upsert(collection_name=QDRANT_COLLECTION, points=to_upsert)

        upload_file_to_supabase(local_path, os.path.basename(local_path))

        job.status = "done"
        job.progress = 100
        db.add(job); db.commit()

    except Exception as e:
        job.status = "failed"
        job.error = str(e)
        db.add(job); db.commit()

    finally:
        db.close()
        try:
            os.remove(local_path)
        except Exception:
            pass