#!/usr/bin/env python
"""
Clear all Qdrant collections - use with caution!
This will delete ALL collections from your Qdrant instance.
"""
import sys
from pathlib import Path

# Add repo root to path for module imports
repo_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo_root))

from backend.clients import get_qdrant

def clear_all_collections():
    """Delete all collections from Qdrant."""
    try:
        qclient = get_qdrant()
        
        # Get all collections
        collections = qclient.get_collections()
        collection_names = [c.name for c in collections.collections]
        
        if not collection_names:
            print("No collections found in Qdrant. Nothing to delete.")
            return
        
        print(f"Found {len(collection_names)} collections in Qdrant:")
        for name in sorted(collection_names):
            try:
                info = qclient.get_collection(name)
                print(f"  - {name} ({info.points_count} points)")
            except:
                print(f"  - {name}")
        
        print(f"\n[WARNING] This will DELETE ALL {len(collection_names)} collections!")
        print("   This action cannot be undone.")
        
        # Check if --force flag is provided for non-interactive mode
        force = '--force' in sys.argv
        if not force:
            response = input("   Type 'DELETE ALL' to confirm: ")
        else:
            response = 'DELETE ALL'
            print("   Running in --force mode, skipping confirmation...")
        
        if response == 'DELETE ALL':
            deleted_count = 0
            for name in collection_names:
                try:
                    qclient.delete_collection(collection_name=name)
                    print(f"[OK] Deleted collection: {name}")
                    deleted_count += 1
                except Exception as e:
                    print(f"[ERROR] Failed to delete {name}: {e}")
            
            print(f"\n[SUCCESS] Deleted {deleted_count}/{len(collection_names)} collections")
        else:
            print("Cancelled.")
            
    except Exception as e:
        print(f"[ERROR] Failed to clear Qdrant: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    # Configure stdout for UTF-8 to handle any special characters
    if sys.stdout.encoding != 'utf-8':
        try:
            sys.stdout.reconfigure(encoding='utf-8')
        except:
            pass
    clear_all_collections()

