import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/chat_models.dart';

/// Simple API client for the QueryHub backend.
class ApiClient {
  /// Base URL is chosen based on platform so Android emulators can reach
  /// the host machine.
  ///
  /// - Flutter web / desktop / iOS simulator: http://localhost:8000
  /// - Android emulator: http://10.0.2.2:8000
  /// - Physical devices: replace with your LAN IP, e.g. http://192.168.1.10:8000
  String get _baseUrl {
    String url;
    if (kIsWeb) {
      url = 'http://localhost:8000';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          // Android emulator special loopback to host
          url = 'http://10.0.2.2:8000';
          break;
        default:
          url = 'http://localhost:8000';
      }
    }
    print('🌐 API Base URL: $url (Platform: ${defaultTargetPlatform})');
    return url;
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<List<DocumentModel>> fetchDocuments() async {
    final resp = await http.get(_uri('/documents'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch documents: ${resp.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(resp.body) as List<dynamic>;
    return jsonList.map((j) {
      final m = j as Map<String, dynamic>;
      return DocumentModel(
        id: m['id'] as String,
        filename: m['filename'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        status: m['status'] as String,
      );
    }).toList();
  }

  Future<DocumentModel> uploadDocument({
    required String filename,
    required Uint8List bytes,
  }) async {
    final url = _uri('/upload');
    print('📤 Uploading to: $url');
    print('📄 Filename: $filename, Size: ${bytes.length} bytes');
    
    try {
      final request = http.MultipartRequest('POST', url);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

      print('⏳ Sending request...');
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      
      print('📥 Response status: ${resp.statusCode}');
      print('📥 Response body: ${resp.body}');
      
      if (resp.statusCode != 200) {
        throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
      }
      
      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      print('✅ Upload successful: ${data['document_id']}');
      
      return DocumentModel(
        id: data['document_id'] as String,
        filename: data['filename'] as String,
        createdAt: DateTime.parse(data['created_at'] as String),
        status: data['status'] as String? ?? 'processing',
      );
    } catch (e) {
      print('❌ Upload error: $e');
      rethrow;
    }
  }

  Future<void> deleteDocument(String id) async {
    final resp = await http.delete(_uri('/documents/$id'));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('Delete failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<(String, List<ContextChunk>)> askQuestion(
    String query, {
    String? documentId,
  }) async {
    final body = <String, dynamic>{'query': query};
    if (documentId != null) {
      body['document_id'] = documentId;
    }
    
    final resp = await http.post(
      _uri('/ask'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Ask failed: ${resp.statusCode} ${resp.body}');
    }
    final Map<String, dynamic> data =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final String answer = data['answer'] as String? ?? '';
    final List<dynamic> ctxJson = data['contexts'] as List<dynamic>? ?? [];
    final List<ContextChunk> contexts = ctxJson.map((e) {
      final m = e as Map<String, dynamic>;
      return ContextChunk(
        score: (m['score'] as num?)?.toDouble() ?? 0.0,
        text: m['text'] as String? ?? '',
        payload: (m['payload'] as Map<String, dynamic>?) ?? {},
      );
    }).toList();
    return (answer, contexts);
  }

  // ===== CHAT SESSION METHODS =====

  Future<ChatSession> createChatSession({
    required String title,
    String? documentId,
  }) async {
    final resp = await http.post(
      _uri('/chats'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        if (documentId != null) 'document_id': documentId,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Create chat failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ChatSession.fromJson(data);
  }

  Future<List<ChatSession>> fetchChatSessions({String? documentId}) async {
    final uri = documentId != null
        ? _uri('/chats?document_id=$documentId')
        : _uri('/chats');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Fetch chats failed: ${resp.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(resp.body) as List<dynamic>;
    return jsonList
        .map((j) => ChatSession.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> fetchChatMessages(String sessionId) async {
    final resp = await http.get(_uri('/chats/$sessionId/messages'));
    if (resp.statusCode != 200) {
      throw Exception('Fetch messages failed: ${resp.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(resp.body) as List<dynamic>;
    return jsonList
        .map((j) => Message.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Message> addMessageToSession({
    required String sessionId,
    required String role,
    required String content,
    List<ContextChunk> contexts = const [],
  }) async {
    final resp = await http.post(
      _uri('/chats/$sessionId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'role': role,
        'content': content,
        'contexts': contexts.map((c) => c.toJson()).toList(),
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Add message failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  Future<void> deleteChatSession(String sessionId) async {
    final resp = await http.delete(_uri('/chats/$sessionId'));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('Delete chat failed: ${resp.statusCode} ${resp.body}');
    }
  }
}


