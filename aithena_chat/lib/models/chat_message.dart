import 'package:uuid/uuid.dart';
import 'llm_model.dart';

class ChatMessage {
  final String id;
  final String content;
  final String role;
  final DateTime timestamp;
  final LLMModel? model;

  ChatMessage({
    String? id,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.model,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      role: json['role'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      model: json['model'] != null 
        ? LLMModel.fromName(
            json['model']['name'] as String,
            platform: json['model']['platform'] as String,
          )
        : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'role': role,
    'timestamp': timestamp.toIso8601String(),
    'model': model != null ? {
      'name': model!.name,
      'platform': model!.platform,
    } : null,
  };
} 