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
    job = None
    try:
        job = Job(document_id=document_id, status="processing")
        db.add(job)
        db.commit()
        db.refresh(job)
        print(f"📦 Processing document {document_id}... (job_id: {job.job_id})")

        text = extract_text_from_file(local_path)
        chunks = chunk_text(text, CHUNK_SIZE, CHUNK_OVERLAP)
        print(f"  ✓ Extracted {len(chunks)} chunks from {local_path}")
        
        model = get_embedding_model()

        # Try to upload to Qdrant, but continue if it fails
        to_upsert = []
        total_chunks = len(chunks)
        print(f"  🔄 Processing {total_chunks} chunks...")
        
        for idx, c in enumerate(chunks):
            if idx % 10 == 0 or idx == total_chunks - 1:
                progress = int((idx + 1) / total_chunks * 90)  # 0-90% for chunking/embedding
                job.progress = progress
                db.add(job)
                db.commit()
                print(f"  📊 Progress: {progress}% ({idx + 1}/{total_chunks} chunks)")
            
            chunk_obj = Chunk(document_id=document_id, chunk_index=idx, text=c, token_count=len(c))
            db.add(chunk_obj)
            db.commit()
            db.refresh(chunk_obj)

            try:
                emb = model.encode(c).tolist()
                point = qmodels.PointStruct(
                    id=chunk_obj.id,
                    vector=emb,
                    payload={"document_id": document_id, "chunk_index": idx, "chunk_text": c}
                )
                to_upsert.append(point)
            except Exception as e:
                print(f"⚠ Warning encoding chunk {idx}: {e}")

            emb_row = Embedding(chunk_id=chunk_obj.id)
            db.add(emb_row)
            db.commit()

        # Upload to Qdrant if available
        if to_upsert:
            print(f"  ⬆ Uploading {len(to_upsert)} embeddings to Qdrant...")
            try:
                qclient = get_qdrant()
                qclient.upsert(
                collection_name=QDRANT_COLLECTION,
                points=to_upsert
                )
                print(f"  ✓ Uploaded {len(to_upsert)} embeddings to Qdrant")
            except Exception as e:
                print(f"⚠ Qdrant unavailable: {e}")
                print(f"  Chunks stored in database but not indexed for search")

        try:
            upload_file_to_supabase(local_path, os.path.basename(local_path))
        except Exception as e:
            print(f"⚠ Supabase upload failed: {e}")

        # Update job status to done
        print(f"  📝 Updating job status to 'done'...")
        job.status = "done"
        job.progress = 100
        db.add(job)
        db.commit()
        db.refresh(job)  # Ensure it's persisted
        print(f"✓ Document {document_id} processed successfully (job status: {job.status})")

    except Exception as e:
        print(f"✗ Error processing document {document_id}: {e}")
        import traceback
        traceback.print_exc()
        if job:
            try:
                # Refresh job to ensure we have the latest state
                db.refresh(job)
                job.status = "failed"
                job.error = str(e)
                db.add(job)
                db.commit()
                print(f"  ⚠ Job status updated to 'failed'")
            except Exception as db_err:
                print(f"  ✗ Failed to update job status: {db_err}")

    finally:
        db.close()
        try:
            os.remove(local_path)
        except Exception:
            pass