import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import '../services/api_client.dart';

class AppState extends ChangeNotifier {
  final ApiClient api;

  AppState({required this.api});

  final List<ChatSession> _sessions = [];
  final List<DocumentModel> _documents = [];
  String? _activeSessionId;
  String? _selectedDocumentId; // Track selected document for hierarchical navigation
  bool _isAsking = false;
  Timer? _pollTimer;

  List<ChatSession> get sessions =>
      List.unmodifiable(_sessions.reversed); // newest first
  
  // Get sessions for a specific document
  List<ChatSession> getSessionsForDocument(String? documentId) {
    if (documentId == null) return [];
    return _sessions.where((s) => s.documentId == documentId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // newest first
  }
  
  List<DocumentModel> get documents =>
      List.unmodifiable(_documents); // as returned

  String? get selectedDocumentId => _selectedDocumentId;
  
  DocumentModel? get selectedDocument {
    if (_selectedDocumentId == null) return null;
    try {
      return _documents.firstWhere((d) => d.id == _selectedDocumentId);
    } catch (_) {
      return null;
    }
  }

  ChatSession? get activeSession {
    if (_activeSessionId == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == _activeSessionId);
    } catch (_) {
      return null;
    }
  }

  bool get hasReadyDocuments =>
      _documents.any((d) => d.isReady); // enable chat when true

  bool get isAsking => _isAsking;
  
  bool get hasProcessingDocuments =>
      _documents.any((d) => d.status == 'processing');

  Future<void> loadDocuments() async {
    try {
      final docs = await api.fetchDocuments();
      final previousSelectedId = _selectedDocumentId;
      _documents
        ..clear()
        ..addAll(docs);
      
      // If selected document was deleted, clear selection
      if (_selectedDocumentId != null) {
        final stillExists = docs.any((d) => d.id == _selectedDocumentId);
        if (!stillExists) {
          _selectedDocumentId = null;
          _activeSessionId = null;
        }
      }
      
      // Auto-select first ready document if none selected
      if (_selectedDocumentId == null) {
        final readyDocs = docs.where((d) => d.isReady).toList();
        if (readyDocs.isNotEmpty) {
          _selectedDocumentId = readyDocs.first.id;
          // Load chats for the newly selected document
          await loadChatSessions(documentId: _selectedDocumentId);
        }
      } else if (previousSelectedId != _selectedDocumentId) {
        // Document selection changed, reload chats
        await loadChatSessions(documentId: _selectedDocumentId);
      }
      
      notifyListeners();
      
      // Start polling if there are processing documents
      _managePolling();
    } catch (e) {
      print('❌ Failed to load documents: $e');
    }
  }

  Future<void> loadChatSessions({String? documentId}) async {
    try {
      final sessions = await api.fetchChatSessions(documentId: documentId);
      // Merge with existing sessions instead of clearing
      for (final session in sessions) {
        final existingIndex = _sessions.indexWhere((s) => s.id == session.id);
        if (existingIndex != -1) {
          _sessions[existingIndex] = session;
        } else {
          _sessions.add(session);
        }
      }
      notifyListeners();
    } catch (e) {
      print('❌ Failed to load chat sessions: $e');
    }
  }
  
  void selectDocument(String? documentId) {
    _selectedDocumentId = documentId;
    // Load chats for this document
    if (documentId != null) {
      loadChatSessions(documentId: documentId);
    }
    // Clear active session when switching documents
    _activeSessionId = null;
    notifyListeners();
  }

  Future<void> loadChatMessages(String sessionId) async {
    try {
      final messages = await api.fetchChatMessages(sessionId);
      final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
      if (sessionIndex != -1) {
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
          messages: messages,
        );
        notifyListeners();
      }
    } catch (e) {
      print('❌ Failed to load messages: $e');
    }
  }
  
  void _managePolling() {
    if (hasProcessingDocuments) {
      // Start polling every 3 seconds if not already polling
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _pollTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => loadDocuments(),
        );
      }
    } else {
      // Stop polling when no documents are processing
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }
  
  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> createNewChat({String? documentId}) async {
    try {
      // Use selected document if no documentId provided
      String? finalDocumentId = documentId ?? _selectedDocumentId;
      
      // If still no document, try to auto-select from ready documents
      if (finalDocumentId == null) {
        final readyDocs = _documents.where((d) => d.isReady).toList();
        if (readyDocs.length == 1) {
          finalDocumentId = readyDocs.first.id;
          // Auto-select this document
          _selectedDocumentId = finalDocumentId;
        }
      }
      
      if (finalDocumentId == null) {
        throw Exception('No document selected. Please select a document first.');
      }
      
      // Count chats for this document to generate title
      final docChats = getSessionsForDocument(finalDocumentId);
      final title = 'Chat ${docChats.length + 1}';
      
      final session = await api.createChatSession(
        title: title,
        documentId: finalDocumentId,
      );
      _sessions.insert(0, session); // Add to beginning (newest first)
      _activeSessionId = session.id;
      notifyListeners();
    } catch (e) {
      print('❌ Failed to create chat: $e');
      rethrow;
    }
  }

  Future<void> selectChat(String sessionId) async {
    _activeSessionId = sessionId;
    notifyListeners();
    
    // Load messages if not already loaded
    final session = _sessions.firstWhere((s) => s.id == sessionId);
    if (session.messages.isEmpty) {
      await loadChatMessages(sessionId);
    }
  }

  Future<void> uploadDocument({
    required String filename,
    required Uint8List bytes,
  }) async {
    // optimistic local entry with "uploading"
    final tempDoc = DocumentModel(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      filename: filename,
      createdAt: DateTime.now(),
      status: 'uploading',
    );
    _documents.add(tempDoc);
    notifyListeners();

    try {
      final remoteDoc =
          await api.uploadDocument(filename: filename, bytes: bytes);
      // replace temp doc
      _documents
        ..remove(tempDoc)
        ..add(remoteDoc);
      notifyListeners();

      // refresh list from backend to get updated statuses later on
      await loadDocuments();
      
      // Auto-select the newly uploaded document when it's ready
      // (will be selected automatically when status changes to 'done')
    } catch (e) {
      _documents.remove(tempDoc);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteChat(String sessionId) async {
    // Optimistic remove
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      // Try to select another chat from the same document
      if (_selectedDocumentId != null) {
        final docChats = getSessionsForDocument(_selectedDocumentId);
        _activeSessionId = docChats.isNotEmpty ? docChats.first.id : null;
      } else {
        _activeSessionId = null;
      }
    }
    notifyListeners();
    
    try {
      await api.deleteChatSession(sessionId);
      // Reload chats for the selected document
      if (_selectedDocumentId != null) {
        await loadChatSessions(documentId: _selectedDocumentId);
      }
    } catch (e) {
      print('❌ Failed to delete chat: $e');
      // Reload from server to restore correct state
      if (_selectedDocumentId != null) {
        await loadChatSessions(documentId: _selectedDocumentId);
      }
    }
  }

  Future<void> deleteDocument(String documentId) async {
    // optimistic remove
    _documents.removeWhere((d) => d.id == documentId);
    notifyListeners();
    try {
      await api.deleteDocument(documentId);
      await loadDocuments();
    } catch (_) {
      // reload from server to restore correct state
      await loadDocuments();
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    
    // Refresh documents to ensure we have the latest status
    await loadDocuments();
    
    if (!hasReadyDocuments) return;

    if (_activeSessionId == null) {
      // Must have a selected document to create a chat
      if (_selectedDocumentId == null) {
        final readyDocs = _documents.where((d) => d.isReady).toList();
        if (readyDocs.length == 1) {
          _selectedDocumentId = readyDocs.first.id;
          await loadChatSessions(documentId: _selectedDocumentId);
        } else {
          throw Exception('Please select a document first.');
        }
      }
      await createNewChat(documentId: _selectedDocumentId);
    }

    final sessionIndex =
        _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (sessionIndex == -1) return;

    final current = _sessions[sessionIndex];
    
    // Use session's documentId, or fall back to selected document
    String? documentId = current.documentId ?? _selectedDocumentId;
    
    if (documentId == null) {
      throw Exception('No document linked to this chat. Please select a document.');
    }
    
    _isAsking = true;
    notifyListeners();

    try {
      // Save user message to backend
      final userMsg = await api.addMessageToSession(
        sessionId: _activeSessionId!,
        role: 'user',
        content: content.trim(),
      );

      // Add to local state
      _sessions[sessionIndex] = current.copyWith(
        messages: [...current.messages, userMsg],
      );
      notifyListeners();

      // Get AI response - pass document_id if available
      final (answer, contexts) = await api.askQuestion(
        content.trim(),
        documentId: documentId,
      );

      // Save assistant message to backend
      final assistantMsg = await api.addMessageToSession(
        sessionId: _activeSessionId!,
        role: 'assistant',
        content: answer,
        contexts: contexts,
      );

      // Add to local state
      final updated = _sessions[sessionIndex];
      _sessions[sessionIndex] = updated.copyWith(
        messages: [...updated.messages, assistantMsg],
      );
    } catch (e) {
      print('❌ Error in sendMessage: $e');
      // Reload messages from server to get correct state
      if (_activeSessionId != null) {
        await loadChatMessages(_activeSessionId!);
      }
    } finally {
      _isAsking = false;
      notifyListeners();
    }
  }
}



