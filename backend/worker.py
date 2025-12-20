import threading
import uuid
import os
from .db import SessionLocal
from .models import Document, Chunk, Embedding, Job
from .utils import save_upload_to_tmp, extract_text_from_file, chunk_text
from .config import CHUNK_SIZE, CHUNK_OVERLAP, EMBEDDING_MODEL
from sentence_transformers import SentenceTransformer
from qdrant_client.http import models as qmodels
from qdrant_client.http.models import VectorParams, Distance
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
        print(f"[INFO] Processing document {document_id}... (job_id: {job.job_id})")

        text = extract_text_from_file(local_path)
        chunks = chunk_text(text, CHUNK_SIZE, CHUNK_OVERLAP)
        print(f"  [OK] Extracted {len(chunks)} chunks from {local_path}")
        
        model = get_embedding_model()

        # Try to upload to Qdrant, but continue if it fails
        to_upsert = []
        total_chunks = len(chunks)
        print(f"  [INFO] Processing {total_chunks} chunks...")
        
        for idx, c in enumerate(chunks):
            if idx % 10 == 0 or idx == total_chunks - 1:
                progress = int((idx + 1) / total_chunks * 90)  # 0-90% for chunking/embedding
                job.progress = progress
                db.add(job)
                db.commit()
                print(f"  [PROGRESS] {progress}% ({idx + 1}/{total_chunks} chunks)")
            
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
                print(f"[WARN] Warning encoding chunk {idx}: {e}")

            emb_row = Embedding(chunk_id=chunk_obj.id)
            db.add(emb_row)
            db.commit()

        # Upload to Qdrant if available (using document-specific collection)
        if to_upsert:
            print(f"  [INFO] Uploading {len(to_upsert)} embeddings to Qdrant...")
            try:
                qclient = get_qdrant()
                # Use document-specific collection name
                collection_name = f"doc-{document_id}"
                
                # Get vector size from first embedding
                vector_size = len(to_upsert[0].vector) if to_upsert else 384
                
                # Ensure collection exists with retry logic
                collection_exists = False
                max_retries = 3
                for attempt in range(max_retries):
                    try:
                        # Try to get collection info - if it exists, this will succeed
                        try:
                            qclient.get_collection(collection_name)
                            collection_exists = True
                            print(f"  [OK] Collection already exists: {collection_name}")
                            break
                        except Exception:
                            # Collection doesn't exist, create it
                            pass
                        
                        # Create collection
                        qclient.create_collection(
                            collection_name=collection_name,
                            vectors_config=VectorParams(
                                size=vector_size,
                                distance=Distance.COSINE
                            )
                        )
                        collection_exists = True
                        print(f"  [OK] Created Qdrant collection: {collection_name}")
                        break
                    except Exception as coll_err:
                        if attempt < max_retries - 1:
                            print(f"  [WARN] Attempt {attempt + 1}/{max_retries} failed to create collection, retrying...")
                            import time
                            time.sleep(1)  # Wait 1 second before retry
                        else:
                            print(f"  [WARN] Could not ensure collection exists after {max_retries} attempts: {coll_err}")
                            raise
                
                if collection_exists:
                    # Upload embeddings to document-specific collection
                    qclient.upsert(
                        collection_name=collection_name,
                        points=to_upsert
                    )
                    print(f"  [OK] Uploaded {len(to_upsert)} embeddings to Qdrant collection: {collection_name}")
                else:
                    print(f"  [WARN] Skipping Qdrant upload - collection not created")
            except Exception as e:
                print(f"[WARN] Qdrant unavailable: {e}")
                print(f"  Chunks stored in database but not indexed for search")

        try:
            upload_file_to_supabase(local_path, os.path.basename(local_path))
        except Exception as e:
            print(f"[WARN] Supabase upload failed: {e}")

        # Update job status to done
        print(f"  [INFO] Updating job status to 'done'...")
        job.status = "done"
        job.progress = 100
        db.add(job)
        db.commit()
        db.refresh(job)  # Ensure it's persisted
        print(f"[OK] Document {document_id} processed successfully (job status: {job.status})")

    except Exception as e:
        print(f"[ERROR] Error processing document {document_id}: {e}")
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
                print(f"  [WARN] Job status updated to 'failed'")
            except Exception as db_err:
                print(f"  [ERROR] Failed to update job status: {db_err}")

    finally:
        db.close()
        try:
            os.remove(local_path)
        except Exception:
            pass