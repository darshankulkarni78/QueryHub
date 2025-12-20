import 'package:intl/intl.dart';

enum MessageRole { user, assistant }

class Message {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ContextChunk> contexts;

  Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.contexts = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
      contexts: (json['contexts'] as List<dynamic>?)
              ?.map((c) => ContextChunk.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role == MessageRole.user ? 'user' : 'assistant',
      'content': content,
      'contexts': contexts.map((c) => c.toJson()).toList(),
    };
  }
}

class ChatSession {
  final String id;
  final String title;
  final String? documentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final List<Message> messages;

  ChatSession({
    required this.id,
    required this.title,
    this.documentId,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.messages = const [],
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      documentId: json['document_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messageCount: json['message_count'] as int? ?? 0,
      messages: const [],
    );
  }

  ChatSession copyWith({
    String? id,
    String? title,
    String? documentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    List<Message>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      documentId: documentId ?? this.documentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      messages: messages ?? this.messages,
    );
  }

  String get humanCreatedAt {
    return DateFormat('MMM d, HH:mm').format(createdAt);
  }

  String get humanUpdatedAt {
    return DateFormat('MMM d, HH:mm').format(updatedAt);
  }
}

class DocumentModel {
  final String id;
  final String filename;
  final DateTime createdAt;
  final String status; // uploading | processing | done | failed | uploaded

  const DocumentModel({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.status,
  });

  bool get isReady => status == 'done';
}

class ContextChunk {
  final double score;
  final String text;
  final Map<String, dynamic> payload;

  const ContextChunk({
    required this.score,
    required this.text,
    required this.payload,
  });

  factory ContextChunk.fromJson(Map<String, dynamic> json) {
    return ContextChunk(
      score: (json['score'] as num).toDouble(),
      text: json['text'] as String,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'text': text,
      'payload': payload,
    };
  }
}


