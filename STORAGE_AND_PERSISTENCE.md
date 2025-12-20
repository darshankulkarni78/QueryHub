# Storage and Persistence in QueryHub

## 📄 Document Storage

### What happens when you upload a document:
1. ✅ **File uploaded to Supabase Storage** (in the `uploads` bucket)
2. ✅ **Metadata saved to Database** (SQLite with filename, s3_key, etc.)
3. ✅ **Text extracted and chunked** (by worker.py)
4. ✅ **Chunks saved to Database** (with embeddings metadata)
5. ✅ **Vector embeddings uploaded to Qdrant** (for semantic search)

### What happens when you delete a document:
**BEFORE FIX:**
- ✅ Database record deleted
- ✅ Qdrant vectors deleted
- ❌ **File remained in Supabase Storage** (wasting space!)

**AFTER FIX (implemented):**
- ✅ Database record deleted
- ✅ Qdrant vectors deleted
- ✅ **File deleted from Supabase Storage**

### Locations:
- **Supabase Storage**: `https://nyodteirvxjabjxinopo.supabase.co/storage/v1/object/public/uploads/`
- **SQLite Database**: `QueryHub/backend/dev.db` (local file)
- **Qdrant Vector DB**: `https://1073db2b-07a9-4dfa-a56a-507a2e6bd0a7.europe-west3-0.gcp.cloud.qdrant.io:6333`

---

## 💬 Chat Session Storage

### Current State: **NO PERSISTENCE** ⚠️

Chat sessions are **ONLY stored in memory** in the Flutter frontend:
- Location: `AppState._sessions` (Dart List in memory)
- Lifetime: **Lost when you close/refresh the app**
- Backend: **No backend API for chats at all**

### What happens when you delete a chat:
- ✅ Removed from `_sessions` list in memory
- ✅ **Actually deleted** (but only from memory)
- ❌ No backend cleanup needed (because there's no backend storage)

### Code:
```dart
// In app_state.dart
void deleteChat(String sessionId) {
  _sessions.removeWhere((s) => s.id == sessionId);
  if (_activeSessionId == sessionId) {
    _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
  }
  notifyListeners();
}
```

---

## 🔧 How to Add Chat Persistence (Future Enhancement)

If you want chats to persist, you need to:

### Option 1: Backend Database (Recommended)
1. Add `chat_sessions` and `messages` tables to backend database
2. Create API endpoints:
   - `POST /chats` - Create new chat
   - `GET /chats` - List all chats
   - `GET /chats/{id}` - Get chat with messages
   - `POST /chats/{id}/messages` - Add message
   - `DELETE /chats/{id}` - Delete chat
3. Update Flutter `AppState` to sync with backend

### Option 2: Local Storage (Simple)
1. Use `shared_preferences` package in Flutter
2. Serialize chat sessions to JSON
3. Save/load from local storage
4. **Limitation**: Only works on same device

---

## 📊 Current Architecture

```
Flutter Frontend (Memory)
├── Chat Sessions (in AppState._sessions)
│   └── Messages (in ChatSession.messages)
│   └── [LOST ON APP CLOSE] ⚠️
│
└── Documents (loaded from backend)

FastAPI Backend (SQLite Database)
├── documents table
├── chunks table
├── embeddings table
└── jobs table

Supabase
└── uploads bucket (file storage)

Qdrant
└── queryhub-collection (vector embeddings)
```

---

## ✅ Summary

| Feature | Storage Location | Persisted? | Deleted Properly? |
|---------|-----------------|------------|-------------------|
| **Document Files** | Supabase Storage | ✅ Yes | ✅ **Fixed** |
| **Document Metadata** | SQLite Database | ✅ Yes | ✅ Yes |
| **Text Chunks** | SQLite Database | ✅ Yes | ✅ Yes |
| **Vector Embeddings** | Qdrant | ✅ Yes | ✅ Yes |
| **Chat Sessions** | Frontend Memory | ❌ **No** | ✅ Yes (from memory) |
| **Messages** | Frontend Memory | ❌ **No** | ✅ Yes (from memory) |

---

## 🚀 Next Steps

1. **Restart backend** to apply the Supabase deletion fix:
   ```bash
   cd QueryHub/backend
   python main.py
   ```

2. **Test document deletion**:
   - Upload a document
   - Check Supabase Storage dashboard (should see the file)
   - Delete the document from UI
   - Check Supabase Storage again (file should be gone!)

3. **For chat persistence** (optional):
   - Decide on Option 1 (backend) or Option 2 (local storage)
   - Let me know if you want me to implement it!

