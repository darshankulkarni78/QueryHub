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
  bool _isAsking = false;

  List<ChatSession> get sessions =>
      List.unmodifiable(_sessions.reversed); // newest first
  List<DocumentModel> get documents =>
      List.unmodifiable(_documents); // as returned

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

  Future<void> loadDocuments() async {
    final docs = await api.fetchDocuments();
    _documents
      ..clear()
      ..addAll(docs);
    notifyListeners();
  }

  void createNewChat() {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final title = 'Chat ${_sessions.length + 1}';
    final session =
        ChatSession(id: id, title: title, createdAt: now, messages: []);
    _sessions.add(session);
    _activeSessionId = id;
    notifyListeners();
  }

  void selectChat(String sessionId) {
    _activeSessionId = sessionId;
    notifyListeners();
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
    } catch (e) {
      _documents.remove(tempDoc);
      notifyListeners();
      rethrow;
    }
  }

  void deleteChat(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    notifyListeners();
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
    if (!hasReadyDocuments) return;

    if (_activeSessionId == null) {
      createNewChat();
    }

    final sessionIndex =
        _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (sessionIndex == -1) return;

    final now = DateTime.now();
    final userMsg = Message(
      id: 'user-$now',
      role: MessageRole.user,
      content: content.trim(),
      timestamp: now,
    );

    final current = _sessions[sessionIndex];
    final updatedMessages = [...current.messages, userMsg];
    _sessions[sessionIndex] =
        current.copyWith(messages: updatedMessages);
    _isAsking = true;
    notifyListeners();

    try {
      final (answer, contexts) = await api.askQuestion(content.trim());
      final assistantMsg = Message(
        id: 'assistant-${DateTime.now()}',
        role: MessageRole.assistant,
        content: answer,
        timestamp: DateTime.now(),
        contexts: contexts,
      );

      final refreshed = _sessions[sessionIndex];
      final msgs = [...refreshed.messages, assistantMsg];
      _sessions[sessionIndex] = refreshed.copyWith(messages: msgs);
    } catch (e) {
      // Add error message to chat
      final errorMsg = Message(
        id: 'error-${DateTime.now()}',
        role: MessageRole.assistant,
        content: '❌ Error: ${e.toString()}',
        timestamp: DateTime.now(),
      );
      final refreshed = _sessions[sessionIndex];
      final msgs = [...refreshed.messages, errorMsg];
      _sessions[sessionIndex] = refreshed.copyWith(messages: msgs);
      rethrow;  // Re-throw so UI can show snackbar too
    } finally {
      _isAsking = false;
      notifyListeners();
    }
  }
}


