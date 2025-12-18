import 'package:intl/intl.dart';

enum MessageRole { user, assistant }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ContextChunk> contexts;

  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.contexts = const [],
  });
}

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<Message> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    this.messages = const [],
  });

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    List<Message>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      messages: messages ?? this.messages,
    );
  }

  String get humanCreatedAt {
    return DateFormat('MMM d, HH:mm').format(createdAt);
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
}


