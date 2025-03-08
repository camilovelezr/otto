import 'package:uuid/uuid.dart';
import 'llm_model.dart';

class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final LLMModel? model;
  final DateTime timestamp; // Keep for backward compatibility
  final DateTime createdAt; // Add this to match backend API
  final int? tokenCount;
  
  // metadata field has been removed as per backend updates

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.model,
    DateTime? timestamp,
    DateTime? createdAt,
    this.tokenCount,
  }) : 
    id = id ?? const Uuid().v4(),
    timestamp = timestamp ?? DateTime.now(),
    createdAt = createdAt ?? timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Handle different date formats from backend
    DateTime parseDateTime(String? dateString) {
      if (dateString == null) return DateTime.now();
      try {
        return DateTime.parse(dateString);
      } catch (e) {
        print('Error parsing date: $e');
        return DateTime.now();
      }
    }
    
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      model: json['model_id'] != null 
          ? LLMModel(
              modelId: json['model_id'],
              displayName: json['model_id'] ?? 'Unknown Model',
              provider: 'Backend',
            )
          : null,
      // Parse created_at from backend or fall back to timestamp
      createdAt: parseDateTime(json['created_at'] as String?),
      timestamp: json['timestamp'] != null 
          ? parseDateTime(json['timestamp'] as String) 
          : parseDateTime(json['created_at'] as String?),
      tokenCount: json['token_count'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'model_id': model?.modelId,
      'created_at': createdAt.toIso8601String(),
      'timestamp': timestamp.toIso8601String(),
      'token_count': tokenCount,
    };
  }

  @override
  String toString() {
    return 'ChatMessage(role: $role, content: $content, createdAt: $createdAt)';
  }
  
  // Helper getter to check if the message is from the user
  bool get isUser => role == 'user';
} 