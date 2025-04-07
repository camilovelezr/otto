import 'package:uuid/uuid.dart';
import 'llm_model.dart';

class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  // final String? content; // Removed plain content field
  final LLMModel? model;
  final DateTime timestamp; // Keep for backward compatibility
  final DateTime createdAt; // Add this to match backend API
  final int? tokenCount;
  // final bool isEncrypted; // Removed, always encrypted now
  final String? content; // Renamed from encryptedContent, holds encrypted data
  final String? encryptedKey; // New field for E2EE key
  final String? iv; // New field for E2EE IV
  final String? tag; // New field for E2EE tag

  ChatMessage({
    String? id,
    required this.role,
    // this.content, // Removed plain content parameter
    this.model,
    DateTime? timestamp,
    DateTime? createdAt,
    this.tokenCount,
    // this.isEncrypted = false, // Removed isEncrypted parameter
    this.content, // Renamed from encryptedContent
    this.encryptedKey, // Optional key
    this.iv, // Optional IV
    this.tag, // Optional tag
  }) :
    id = id ?? const Uuid().v4(),
    timestamp = timestamp ?? DateTime.now(),
    // assert(isEncrypted || content != null, 'Content cannot be null for unencrypted messages'), // Removed assertion
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

    // Determine encryption status and content - Simplified as always encrypted
    // final bool isEncrypted = json['is_encrypted'] as bool? ?? false; // Removed
    // String? plainContent = json['content'] as String?; // Removed plain content parsing
    final String? content = json['content'] as String?; // Renamed from encrypted_content
    final String? encryptedKey = json['encrypted_key'] as String?; // Parse key
    final String? iv = json['iv'] as String?; // Parse IV
    final String? tag = json['tag'] as String?; // Parse tag

    // Logic based on isEncrypted removed. Assume 'content' field from API is the encrypted data.
    // Decryption happens elsewhere.

    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      // content: plainContent, // Removed plain content
      // isEncrypted: isEncrypted, // Removed
      content: content, // Use renamed field
      encryptedKey: encryptedKey, // Pass parsed key
      iv: iv, // Pass parsed IV
      tag: tag, // Pass parsed tag
      model: json['model_id'] != null
          ? LLMModel(
              modelId: json['model_id'], // Use model_id directly
              displayName: json['model_id'] as String? ?? 'Unknown Model', // Use model_id for display name too
              provider: 'Backend', // Assuming backend provides models via LiteLLM proxy
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
      // 'content': content, // Removed plain content field
      'content': content, // Renamed from encrypted_content
      'encrypted_key': encryptedKey, // Include key
      'iv': iv, // Include IV
      'tag': tag, // Include tag
      // 'is_encrypted': isEncrypted, // Removed
      'model_id': model?.modelId,
      'created_at': createdAt.toIso8601String(),
      'timestamp': timestamp.toIso8601String(), // Keep for compatibility if needed
      'token_count': tokenCount,
    };
  }

  @override
  String toString() {
    // Always display as encrypted now
    final displayContent = '[Encrypted]'; // content field holds encrypted data
    // Removed isEncrypted from output string
    return 'ChatMessage(id: $id, role: $role, content: $displayContent, createdAt: $createdAt)';
  }
  // Helper getter to check if the message is from the user
  bool get isUser => role == 'user';

  // copyWith method
  ChatMessage copyWith({
    String? id,
    String? role,
    // String? content, // Removed plain content parameter
    LLMModel? model,
    DateTime? timestamp,
    DateTime? createdAt,
    int? tokenCount,
    // bool? isEncrypted, // Removed isEncrypted parameter
    String? content, // Renamed from encryptedContent
    String? encryptedKey,
    String? iv,
    String? tag,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      // content: content ?? this.content, // Removed plain content logic
      model: model ?? this.model,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      tokenCount: tokenCount ?? this.tokenCount,
      // isEncrypted: isEncrypted ?? this.isEncrypted, // Removed
      content: content ?? this.content, // Use renamed field
      encryptedKey: encryptedKey ?? this.encryptedKey,
      iv: iv ?? this.iv,
      tag: tag ?? this.tag,
    );
  }
}
