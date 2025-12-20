# QueryHub UI Improvements

## Summary of Changes

### 1. **Responsive Layout**
- Added breakpoints for different screen sizes:
  - **Desktop (Wide)**: ≥1024px - Side-by-side layout with 320px sidebar
  - **Tablet (Medium)**: 768px-1023px - Side-by-side layout with 280px sidebar
  - **Mobile**: <768px - Stacked layout with collapsible sidebar

### 2. **Document Status Tracking**
- Added automatic polling for processing documents (every 3 seconds)
- Enhanced status chips with icons and better visual feedback:
  - ✅ **Ready** (green) - Document is indexed and ready for queries
  - ⏳ **Processing** (orange) - Document is being chunked and embedded
  - ☁️ **Uploading** (blue) - File is being uploaded to storage
  - ⚠️ **Failed** (red) - Processing failed
  - ⏸️ **Queued** (amber) - Uploaded but not yet processing

### 3. **Improved Empty States**
- Better onboarding when no documents are uploaded
- Processing indicator when documents are being indexed
- Clear call-to-action buttons

### 4. **Enhanced Source Display**
- Improved modal bottom sheet for viewing source contexts
- Shows relevance scores as percentages
- Better formatting for readability
- Numbered chunks for easy reference

### 5. **Better Theme**
- Modern color scheme with Material 3
- Improved button styles and padding
- Better input field styling
- Consistent border radius throughout

### 6. **Backend Integration**
- Proper CORS configuration (allows all origins for development)
- Automatic base URL detection for web vs mobile
- Error handling with user-friendly messages
- Real-time document status updates

## API Endpoints Used

- `GET /health` - Health check
- `GET /documents` - List all documents with status
- `POST /upload` - Upload new document
- `DELETE /documents/{id}` - Delete document
- `POST /ask` - Ask question and get AI response with sources

## Features

### Document Management
- Upload PDF, DOCX, or TXT files
- View processing status in real-time
- Delete documents (removes from storage and vector index)
- Automatic status polling while processing

### Chat Interface
- Multiple chat sessions
- Message history per session
- View source contexts for each answer
- Relevance scores for retrieved chunks

### Responsive Design
- Works on desktop, tablet, and mobile
- Adaptive sidebar width
- Flexible document list
- Scrollable chat area

## Running the App

### Backend
```bash
cd backend
python main.py
```
Backend runs on http://localhost:8000

### Frontend
```bash
cd queryhub_frontend
flutter run -d chrome
```

## Configuration

### Backend (.env)
```env
OPENROUTER_API_KEY=your_key
SUPABASE_URL=your_url
SUPABASE_SERVICE_KEY=your_key
SUPABASE_BUCKET=your_bucket
QDRANT_API_KEY=your_key
QDRANT_URL=your_url
QDRANT_COLLECTION=your_collection
DATABASE_URL=sqlite:///./dev.db
FRONTEND_URL=http://localhost:3000
```

### Frontend (api_client.dart)
- Automatically detects platform
- Uses `http://localhost:8000` for web/desktop
- Uses `http://10.0.2.2:8000` for Android emulator

## Known Issues & Solutions

### CORS Errors
- Backend is configured to allow all origins (`allow_origins=["*"]`)
- If you still see CORS errors, restart the backend

### Layout Overflow
- Fixed with `SingleChildScrollView` in empty states
- Used `Flexible` widgets for dynamic sizing

### Document Status Not Updating
- Automatic polling is enabled when documents are processing
- Stops polling when all documents are ready or failed

## Next Steps

1. Add user authentication
2. Implement document preview
3. Add export chat history
4. Improve error messages
5. Add dark mode toggle
6. Implement search in chat history

