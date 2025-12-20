"""
Script to initialize/recreate the database with all tables including new chat tables.
Run this from the backend directory: python init_db.py
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
repo_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo_root))

from backend.db import Base, engine
from backend.models import Document, Job, Chunk, Embedding, ChatSession, Message

def init_database():
    """Create all tables in the database"""
    print("Creating database tables...")
    print(f"Database URL: {engine.url}")
    
    # Drop all tables first (optional - comment out if you want to keep existing data)
    # Base.metadata.drop_all(bind=engine)
    # print("Dropped existing tables")
    
    # Create all tables
    Base.metadata.create_all(bind=engine)
    
    # List all created tables
    tables = list(Base.metadata.tables.keys())
    print(f"Created {len(tables)} tables:")
    for table in tables:
        print(f"  - {table}")
    
    print("\n[SUCCESS] Database initialization complete!")

if __name__ == "__main__":
    init_database()

