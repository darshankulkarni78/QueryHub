#!/usr/bin/env python
"""
Migration utility to clean up legacy Qdrant collections and ensure
all documents use per-document collections.

This script:
1. Lists all documents in the database
2. Checks if they have chunks
3. Verifies their Qdrant collections exist
4. Optionally deletes the legacy shared collection
"""
import sys
from pathlib import Path

# Add repo root to path for module imports
repo_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo_root))

from backend.db import SessionLocal
from backend.models import Document, Chunk
from backend.clients import get_qdrant
from backend.config import QDRANT_COLLECTION
from backend.routes import get_document_collection_name

def check_document_collections():
    """Check status of document collections in Qdrant."""
    db = SessionLocal()
    try:
        documents = db.query(Document).all()
        print(f"Found {len(documents)} documents in database")
        
        qclient = get_qdrant()
        
        # Get all collections
        try:
            collections = qclient.get_collections()
            collection_names = [c.name for c in collections.collections]
            print(f"\nFound {len(collection_names)} collections in Qdrant:")
            for name in sorted(collection_names):
                print(f"  - {name}")
        except Exception as e:
            print(f"[WARN] Could not list collections: {e}")
            return
        
        # Check each document
        print(f"\nChecking document collections:")
        for doc in documents:
            doc_id = str(doc.id)
            expected_collection = get_document_collection_name(doc_id)
            chunks = db.query(Chunk).filter(Chunk.document_id == doc_id).count()
            
            has_collection = expected_collection in collection_names
            in_legacy = QDRANT_COLLECTION in collection_names
            
            status = "[OK]" if has_collection else "[MISSING]"
            legacy_status = " (also in legacy)" if in_legacy else ""
            
            print(f"  {status} {doc.filename[:50]:<50} | Chunks: {chunks:>3} | Collection: {expected_collection}{legacy_status}")
        
        # Check legacy collection
        if QDRANT_COLLECTION in collection_names:
            try:
                legacy_info = qclient.get_collection(QDRANT_COLLECTION)
                print(f"\n[INFO] Legacy collection '{QDRANT_COLLECTION}' exists with {legacy_info.points_count} points")
                print(f"  You can delete it after verifying all documents have their own collections.")
            except Exception as e:
                print(f"\n[WARN] Could not get legacy collection info: {e}")
        
        print(f"\n[INFO] Qdrant is now empty - ready for fresh start!")
        
    finally:
        db.close()

def delete_legacy_collection():
    """Delete the legacy shared collection (use with caution!)."""
    qclient = get_qdrant()
    try:
        collections = qclient.get_collections()
        collection_names = [c.name for c in collections.collections]
        
        if QDRANT_COLLECTION not in collection_names:
            print(f"Legacy collection '{QDRANT_COLLECTION}' does not exist.")
            return
        
        print(f"⚠️  WARNING: This will delete the legacy collection '{QDRANT_COLLECTION}'")
        print("   Make sure all documents have been migrated to per-document collections!")
        response = input("   Type 'DELETE' to confirm: ")
        
        if response == 'DELETE':
            qclient.delete_collection(collection_name=QDRANT_COLLECTION)
            print(f"✓ Deleted legacy collection '{QDRANT_COLLECTION}'")
        else:
            print("Cancelled.")
    except Exception as e:
        print(f"[ERROR] Failed to delete legacy collection: {e}")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "--delete-legacy":
        delete_legacy_collection()
    else:
        check_document_collections()
        print("\n" + "="*70)
        print("To delete the legacy collection, run:")
        print("  python migrate_collections.py --delete-legacy")
        print("="*70)

