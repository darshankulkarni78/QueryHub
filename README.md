# QueryHub

QueryHub is a RAG (Retrieval Augmented Generation) workspace that allows you to upload documents and have intelligent conversations about their content. It features a hierarchical document-chat structure where each document acts as a folder containing multiple chat sessions, ensuring clear context isolation and preventing document mixing.

## Features

- **📁 Hierarchical Document-Chat Structure**: Documents are organized as expandable folders, with chat sessions nested inside each document
- **🔍 Document-Specific Search**: Each document has its own vector space in Qdrant, ensuring queries only search within the selected document's context
- **💬 Persistent Chat Sessions**: Multiple chat sessions per document with full message history
- **📄 Multi-Format Support**: Upload PDFs, DOCX, and text files
- **🤖 AI-Powered Q&A**: Ask questions about your documents using Groq's LLM (free tier)
- **⚡ Real-Time Processing**: Background document indexing with progress tracking
- **🗑️ Complete Deletion**: Deleting a document removes all associated chats, embeddings, and storage files

## Architecture

```
┌─────────────┐
│   Flutter   │  ← Frontend (Web/Desktop)
│   Frontend  │
└──────┬──────┘
       │ HTTP/REST
       ▼
┌─────────────┐
│   FastAPI   │  ← Backend API
│   Backend   │
└──────┬──────┘
       │
       ├──► Supabase Storage (File Storage)
       ├──► SQLite/PostgreSQL (Metadata & Chats)
       ├──► Qdrant (Vector Database)
       └──► Groq API (LLM)
```

## Tech Stack

### Backend
- **FastAPI** - Modern Python web framework
- **SQLAlchemy** - ORM for database operations
- **SQLite/PostgreSQL** - Database for documents, chunks, jobs, and chat sessions
- **Qdrant** - Vector database for embeddings (per-document collections)
- **Sentence Transformers** - Embedding generation
- **Groq** - LLM provider (free tier, fast inference)
- **Supabase** - File storage

### Frontend
- **Flutter** - Cross-platform UI framework
- **Provider** - State management
- **HTTP** - API communication
- **File Picker** - Document upload

## Quick Start

### Prerequisites
- Python 3.8+
- Flutter SDK (for frontend)
- Accounts for:
  - [Groq](https://console.groq.com/) - Free API key for LLM
  - [Supabase](https://supabase.com/) - Free tier for storage
  - [Qdrant Cloud](https://cloud.qdrant.io/) - Free tier for vector database

### Backend Setup

1. **Create a virtual environment and install dependencies:**

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1  # On Windows
# source .venv/bin/activate  # On Linux/Mac
pip install -r requirements.txt
```

2. **Create `.env` file in `backend/` directory:**

```env
# LLM Provider (Groq)
GROQ_API_KEY=your_groq_api_key_here

# Supabase Storage
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_key
SUPABASE_BUCKET=uploads

# Qdrant Vector Database
QDRANT_URL=https://your-cluster.qdrant.io:6333
QDRANT_API_KEY=your_qdrant_api_key
QDRANT_COLLECTION=queryhub-collection

# Database (SQLite for local dev, PostgreSQL for production)
DATABASE_URL=sqlite:///./dev.db
# Or for PostgreSQL:
# DATABASE_URL=postgresql://user:password@host:5432/dbname

# Frontend URL (for CORS)
FRONTEND_URL=http://localhost:3000

# Embedding Configuration (optional)
EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
CHUNK_SIZE=2000
CHUNK_OVERLAP=200
```

3. **Initialize the database:**

```powershell
python init_db.py
```

4. **Start the backend server:**

```powershell
python main.py
```

The backend will run on `http://0.0.0.0:8000`

### Frontend Setup

1. **Navigate to frontend directory:**

```powershell
cd queryhub_frontend
```

2. **Install Flutter dependencies:**

```powershell
flutter pub get
```

3. **Run the Flutter app:**

```powershell
# For web
flutter run -d chrome

# For desktop
flutter run -d windows  # or linux, macos
```

The frontend will connect to the backend at `http://localhost:8000`

## Project Structure

```
QueryHub/
├── backend/                 # FastAPI backend
│   ├── main.py             # Entry point
│   ├── routes.py           # API endpoints
│   ├── models.py           # Database models
│   ├── db.py               # Database connection
│   ├── config.py           # Configuration
│   ├── clients.py          # External service clients
│   ├── worker.py           # Background document processing
│   ├── utils.py            # Utility functions
│   ├── init_db.py          # Database initialization script
│   ├── clear_qdrant.py     # Qdrant cleanup utility
│   ├── migrate_collections.py  # Collection migration utility
│   ├── requirements.txt    # Python dependencies
│   └── .env                # Environment variables (not in git)
│
└── queryhub_frontend/      # Flutter frontend
    ├── lib/
    │   ├── main.dart       # App entry point
    │   ├── screens/
    │   │   └── home_page.dart  # Main UI
    │   ├── models/
    │   │   └── chat_models.dart  # Data models
    │   ├── services/
    │   │   └── api_client.dart  # API client
    │   └── state/
    │       └── app_state.dart   # State management
    └── pubspec.yaml        # Flutter dependencies
```

## API Endpoints

### Document Management
- `GET /documents` - List all documents with status
- `POST /upload` - Upload a document (PDF, DOCX, TXT)
- `GET /documents/{document_id}/status` - Get document processing status
- `DELETE /documents/{document_id}` - Delete document and all associated chats

### Chat Sessions
- `GET /chats?document_id={id}` - List chat sessions (optionally filtered by document)
- `POST /chats` - Create a new chat session
- `GET /chats/{session_id}/messages` - Get all messages in a chat session
- `POST /chats/{session_id}/messages` - Add a message to a chat session
- `DELETE /chats/{session_id}` - Delete a chat session

### AI Query
- `POST /ask` - Ask a question about documents
  ```json
  {
    "query": "What is the main topic?",
    "document_id": "optional-document-id"
  }
  ```

### Health Check
- `GET /health` - Server health status

## Usage Guide

### 1. Upload a Document
- Click the "New" button in the Documents section
- Select a PDF, DOCX, or TXT file
- Wait for processing to complete (status will show "Ready")

### 2. View Document Chats
- Click on a document folder to expand it
- See all chat sessions for that document
- Each document maintains its own isolated chat history

### 3. Start a New Chat
- Expand a document folder
- Click the "+" button next to the document name (when ready)
- Or start typing in the input field (auto-creates chat if none exists)

### 4. Ask Questions
- Select a document and chat session
- Type your question in the input field
- The AI will search only within that document's context
- View source chunks by clicking "Sources" on assistant messages

### 5. Delete Documents/Chats
- Delete a chat: Click the trash icon on a chat item
- Delete a document: Click the trash icon on a document (removes all chats too)

## Document Processing Flow

1. **Upload**: File is uploaded to Supabase storage
2. **Extraction**: Text is extracted from the file (PDF/DOCX/TXT)
3. **Chunking**: Text is split into overlapping chunks
4. **Embedding**: Each chunk is converted to a vector embedding
5. **Indexing**: Embeddings are stored in a document-specific Qdrant collection
6. **Ready**: Document status changes to "done" and is ready for queries

## Vector Database Structure

Each document gets its own Qdrant collection named `doc-{document_id}`. This ensures:
- **Isolation**: Queries only search within the selected document
- **Clean Deletion**: Deleting a document removes its entire collection
- **No Mixing**: Different documents never interfere with each other's search results

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `GROQ_API_KEY` | Groq API key for LLM | Yes |
| `SUPABASE_URL` | Supabase project URL | Yes |
| `SUPABASE_SERVICE_KEY` | Supabase service role key | Yes |
| `SUPABASE_BUCKET` | Supabase storage bucket name | Yes |
| `QDRANT_URL` | Qdrant cluster URL | Yes |
| `QDRANT_API_KEY` | Qdrant API key | Yes |
| `QDRANT_COLLECTION` | Legacy collection name (optional) | Yes |
| `DATABASE_URL` | Database connection string | Yes |
| `FRONTEND_URL` | Frontend URL for CORS | Yes |
| `EMBEDDING_MODEL` | Sentence transformer model | No (default: all-MiniLM-L6-v2) |
| `CHUNK_SIZE` | Text chunk size | No (default: 2000) |
| `CHUNK_OVERLAP` | Chunk overlap size | No (default: 200) |

## Utilities

### Initialize Database
```powershell
python backend/init_db.py
```

### Clear All Qdrant Collections
```powershell
python backend/clear_qdrant.py --force
```

### Check Collection Status
```powershell
python backend/migrate_collections.py --check
```

## Security Notes

- **Never commit `.env` files** to version control
- Use environment variables or secrets manager in production
- The `SUPABASE_SERVICE_KEY` has admin privileges - keep it secure
- Qdrant API keys should be rotated periodically

## Development Notes

- The backend uses SQLite by default for local development
- Switch to PostgreSQL for production by updating `DATABASE_URL`
- Document processing happens in background threads
- Chat sessions are automatically linked to documents when created
- All deletions cascade (document → chats → messages)

## Troubleshooting

### Qdrant Connection Timeout
- Check your network connection
- Verify Qdrant URL and API key
- Collections will be created automatically on first document upload

### Document Not Processing
- Check backend logs for errors
- Verify all environment variables are set
- Ensure Qdrant and Supabase are accessible

### Frontend Can't Connect
- Verify backend is running on port 8000
- Check CORS settings in `backend/routes.py`
- Ensure `FRONTEND_URL` matches your frontend URL

## License

This project is provided as-is for educational and development purposes.

## Contributing

Contributions are welcome! Please ensure:
- Code follows existing style conventions
- Environment variables are documented
- Database migrations are included if schema changes
- Tests are added for new features
