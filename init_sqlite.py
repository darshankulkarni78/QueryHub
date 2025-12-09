#!/usr/bin/env python
"""Initialize SQLite database with all required tables."""
import sys
import os

# Add repo to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backend.db import engine, Base
from backend.models import Document, Chunk, Embedding, Job

def init_db():
    """Create all tables in SQLite."""
    try:
        # This will create all tables based on the models
        Base.metadata.create_all(bind=engine)
        print("✓ SQLite database initialized successfully!")
        print("  Tables created:")
        print("    - documents")
        print("    - chunks")
        print("    - embeddings")
        print("    - jobs")
        return True
    except Exception as e:
        print(f"✗ Error initializing database: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = init_db()
    sys.exit(0 if success else 1)
