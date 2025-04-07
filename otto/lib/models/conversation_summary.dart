import 'package:flutter/foundation.dart';

@immutable
class ConversationSummary {
  final String id;
  final String? title; // Nullable, as it might not be generated yet
  final DateTime updatedAt; // To sort the list

  const ConversationSummary({
    required this.id,
    this.title,
    required this.updatedAt,
  });

  // Factory constructor for creating from JSON (e.g., from API response)
  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String?,
      // Ensure updatedAt is parsed correctly
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  // Method to create a copy with updated values
  ConversationSummary copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
  }) {
    return ConversationSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSummary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ updatedAt.hashCode;
}
