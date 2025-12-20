# 💬 Chat System - Full Persistence Implementation

## 🎉 What Changed

Your chat system has been **completely rebuilt** with persistent storage! Chats are now saved to the backend database and will survive app restarts.

### Before vs After

| Feature | Before | After |
|---------|--------|-------|
| **Storage** | Frontend memory only | Backend SQLite database |
| **Persistence** | ❌ Lost on app close | ✅ Saved permanently |
| **Document Linking** | ❌ Not supported | ✅ Link chats to specific documents |
| **Multi-session** | ❌ Single chat per session | ✅ Multiple chats per document |
| **Resume Chats** | ❌ Can't resume | ✅ Resume any previous chat |
| **Message History** | ❌ Lost on refresh | ✅ Full history preserved |

---

## 🗄️ Database Schema

### New Tables

#### `chat_sessions`
```sql
- id: UUID (primary key)
- title: String
- document_id: UUID (nullable, foreign key to documents)
- created_at: DateTime
- updated_at: DateTime (auto-updated on message add)
```

#### `messages`
```sql
- id: UUID (primary key)
- session_id: UUID (foreign key to chat_sessions)
- role: String ('user' or 'assistant')
- content: Text
- contexts: Text (JSON string of context chunks)
- created_at: DateTime
```

### Relationships
- `chat_sessions.document_id` → `documents.id` (CASCADE delete)
- `messages.session_id` → `chat_sessions.id` (CASCADE delete)

**When you delete a document**: All linked chat sessions are automatically deleted.
**When you delete a chat session**: All its messages are automatically deleted.

---

## 🚀 New API Endpoints

### 1. Create Chat Session
```http
POST /chats
Content-Type: application/json

{
  "title": "Chat 1",
  "document_id": "uuid-here" // Optional
}

Response: ChatSessionResponse
```

### 2. List Chat Sessions
```http
GET /chats
GET /chats?document_id=uuid-here  // Filter by document

Response: List[ChatSessionResponse]
```

### 3. Get Chat Messages
```http
GET /chats/{session_id}/messages

Response: List[MessageResponse]
```

### 4. Add Message to Session
```http
POST /chats/{session_id}/messages
Content-Type: application/json

{
  "role": "user",
  "content": "Hello!",
  "contexts": []  // Optional
}

Response: MessageResponse
```

### 5. Delete Chat Session
```http
DELETE /chats/{session_id}

Response: {"status": "deleted", "session_id": "..."}
```

---

## 💻 Frontend Changes

### Updated Models

#### `ChatSession`
```dart
class ChatSession {
  final String id;
  final String title;
  final String? documentId;        // NEW: Link to document
  final DateTime createdAt;
  final DateTime updatedAt;        // NEW: Last activity time
  final int messageCount;          // NEW: Number of messages
  final List<Message> messages;    // Loaded on demand
}
```

#### `Message`
```dart
class Message {
  final String id;
  final String sessionId;          // NEW: Link to session
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ContextChunk> contexts;
}
```

### Updated AppState Methods

All chat methods are now **async** and sync with the backend:

```dart
// Create new chat (with optional document linking)
await app.createNewChat(documentId: 'uuid');

// Load all chat sessions
await app.loadChatSessions();

// Load chat sessions for a specific document
await app.loadChatSessions(documentId: 'uuid');

// Select and load messages for a chat
await app.selectChat(sessionId);

// Delete a chat session
await app.deleteChat(sessionId);

// Send message (auto-saves to backend)
await app.sendMessage('Hello!');
```

---

## 🎨 UI Enhancements

### Chat List Now Shows:
1. **📄 Document Icon** - If chat is linked to a document, shows document name
2. **💬 Message Count** - Number of messages in the chat
3. **🕐 Last Updated** - When the chat was last active (instead of created time)
4. **✏️ Chat Title** - Descriptive title for each session

### Example Chat Item:
```
💬 Chat 1
📄 resume.pdf • 💬 5 • Dec 20, 15:30
```

---

## 📖 How to Use

### Basic Chat Flow

1. **Upload a Document**
   ```dart
   await app.uploadDocument(filename: 'doc.pdf', bytes: bytes);
   ```

2. **Wait for Processing**
   - UI shows "processing" status
   - Auto-refreshes every 3 seconds
   - Becomes "done" when ready

3. **Create a Chat Session**
   - Click "New Chat" button
   - OR system auto-creates when you send first message
   - Chat is **NOT** linked to a specific document by default

4. **Send Messages**
   - Type in input field
   - Press send or Enter
   - Message and response are **saved to backend automatically**

5. **Switch Between Chats**
   - Click any chat in the sidebar
   - Messages load automatically
   - Continue from where you left off!

6. **Delete a Chat**
   - Click trash icon on chat item
   - Deleted from backend permanently
   - All messages are also deleted

### Advanced: Document-Linked Chats

To create chats linked to specific documents:

```dart
// Option 1: In code
await app.createNewChat(documentId: document.id);

// Option 2: Add a button in your UI
// (You can implement this feature later)
```

**Benefits of Document-Linked Chats:**
- Organize chats by document
- Filter chats: `loadChatSessions(documentId: 'uuid')`
- Auto-delete chats when document is deleted
- Visual indicator in chat list showing which document

---

## 🧪 Testing the System

### Test 1: Basic Persistence
1. ✅ Create a new chat
2. ✅ Send a message
3. ✅ Close and restart the Flutter app
4. ✅ **Verify**: Chat still appears with all messages

### Test 2: Multiple Sessions
1. ✅ Create "Chat 1", send messages
2. ✅ Create "Chat 2", send different messages
3. ✅ Switch between chats
4. ✅ **Verify**: Each chat maintains its own conversation

### Test 3: Document Deletion Cascade
1. ✅ Create a document-linked chat
2. ✅ Delete the document from UI
3. ✅ **Verify**: Chat is also deleted automatically

### Test 4: Message Persistence
1. ✅ Ask a question with context chunks
2. ✅ Restart backend
3. ✅ **Verify**: AI response with sources still shows correctly

---

## 🔧 Technical Implementation

### Backend Flow
```
1. User sends message
   ↓
2. Frontend calls: POST /chats/{id}/messages (user message)
   ↓
3. Backend saves user message to database
   ↓
4. Frontend calls: POST /ask (get AI response)
   ↓
5. Frontend calls: POST /chats/{id}/messages (assistant message)
   ↓
6. Backend saves assistant message with contexts
   ↓
7. Frontend updates UI
```

### Frontend Flow
```
1. App starts
   ↓
2. Load documents: await app.loadDocuments()
   ↓
3. Load chat sessions: await app.loadChatSessions()
   ↓
4. User selects chat
   ↓
5. Load messages: await app.loadChatMessages(sessionId)
   ↓
6. Display conversation
```

---

## 🎯 Future Enhancements (Optional)

You could add these features later:

1. **Search Chats** - Full-text search across all messages
2. **Export Chat** - Download conversation as PDF/TXT
3. **Chat Templates** - Predefined prompts for common tasks
4. **Chat Sharing** - Share chat URL with others
5. **Chat Analytics** - Track most used documents, questions, etc.
6. **Smart Chat Titles** - Auto-generate titles from first message
7. **Chat Tags** - Add custom tags to organize chats
8. **Pin Chats** - Keep important chats at the top
9. **Archive Chats** - Hide old chats without deleting
10. **Multi-Document Chats** - Link chat to multiple documents

---

## ✅ Migration Status

- ✅ Backend database models created
- ✅ Backend API endpoints implemented
- ✅ Frontend models updated with JSON serialization
- ✅ ApiClient methods added
- ✅ AppState refactored for backend sync
- ✅ UI updated to show document links and metadata
- ✅ Auto-load on app start
- ✅ Cascade deletion implemented
- ✅ Error handling and optimistic updates

---

## 🐛 Troubleshooting

### "Chat not loading"
- Check backend is running: `python main.py`
- Check browser console for errors
- Verify API calls in Network tab

### "Messages disappear on refresh"
- Ensure backend is running
- Check `dev.db` file exists in `backend/`
- Verify `chat_sessions` and `messages` tables exist

### "Can't create new chat"
- Ensure at least one document is "done" status
- Check `hasReadyDocuments` returns true
- Look for errors in backend logs

### "Database locked" error
- Stop all Python processes
- Delete `dev.db` and restart backend (recreates tables)
- Ensure only one backend instance is running

---

## 📊 Database Inspection

To inspect your persisted chats:

```bash
cd QueryHub/backend
sqlite3 dev.db

# List all chat sessions
SELECT * FROM chat_sessions;

# List all messages
SELECT * FROM messages;

# Count messages per session
SELECT session_id, COUNT(*) as count 
FROM messages 
GROUP BY session_id;

# View recent chats
SELECT title, updated_at, document_id 
FROM chat_sessions 
ORDER BY updated_at DESC 
LIMIT 10;
```

---

## 🎊 Summary

Your QueryHub now has a **professional-grade chat system** with:
- ✅ Full persistence
- ✅ Multiple sessions per document
- ✅ Resume conversations anytime
- ✅ Backend database storage
- ✅ Automatic cleanup
- ✅ Rich UI metadata

**Try it out!** Create multiple chats, close the app, and reopen - your conversations will be waiting for you! 🚀

