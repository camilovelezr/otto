import 'package:flutter/material.dart';

class ModelCapabilities {
  final bool supportsSystemMessages;
  final bool supportsVision;
  final bool supportsFunctionCalling;
  final bool supportsToolChoice;
  final bool supportsStreaming;
  final bool supportsResponseFormat;
  
  ModelCapabilities({
    this.supportsSystemMessages = false,
    this.supportsVision = false,
    this.supportsFunctionCalling = false,
    this.supportsToolChoice = false,
    this.supportsStreaming = true,
    this.supportsResponseFormat = false,
  });
  
  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsSystemMessages: json['supports_system_messages'] ?? false,
      supportsVision: json['supports_vision'] ?? false,
      supportsFunctionCalling: json['supports_function_calling'] ?? false,
      supportsToolChoice: json['supports_tool_choice'] ?? false,
      supportsStreaming: json['supports_streaming'] ?? true,
      supportsResponseFormat: json['supports_response_format'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'supports_system_messages': supportsSystemMessages,
    'supports_vision': supportsVision,
    'supports_function_calling': supportsFunctionCalling,
    'supports_tool_choice': supportsToolChoice,
    'supports_streaming': supportsStreaming,
    'supports_response_format': supportsResponseFormat,
  };
}

class LLMModel {
  final String modelId;
  final String displayName;
  final String provider;
  final int maxInputTokens;
  final int maxOutputTokens;
  final int maxTotalTokens;
  final double inputPricePerToken;
  final double outputPricePerToken;
  final ModelCapabilities capabilities;
  final DateTime lastSynced;
  
  LLMModel({
    required this.modelId,
    required this.displayName,
    required this.provider,
    this.maxInputTokens = 4096,
    this.maxOutputTokens = 4096,
    this.maxTotalTokens = 8192,
    this.inputPricePerToken = 0.0,
    this.outputPricePerToken = 0.0,
    ModelCapabilities? capabilities,
    DateTime? lastSynced,
  }) : 
    capabilities = capabilities ?? ModelCapabilities(),
    lastSynced = lastSynced ?? DateTime.now();
  
  factory LLMModel.fromJson(Map<String, dynamic> json) {
    return LLMModel(
      modelId: json['model_id'],
      displayName: json['display_name'],
      provider: json['provider'],
      maxInputTokens: json['max_input_tokens'] ?? 4096,
      maxOutputTokens: json['max_output_tokens'] ?? 4096,
      maxTotalTokens: json['max_total_tokens'] ?? 8192,
      inputPricePerToken: json['input_price_per_token']?.toDouble() ?? 0.0,
      outputPricePerToken: json['output_price_per_token']?.toDouble() ?? 0.0,
      capabilities: json['capabilities'] != null 
          ? ModelCapabilities.fromJson(json['capabilities'])
          : null,
      lastSynced: json['last_synced'] != null
          ? DateTime.parse(json['last_synced'])
          : null,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'model_id': modelId,
    'display_name': displayName,
    'provider': provider,
    'max_input_tokens': maxInputTokens,
    'max_output_tokens': maxOutputTokens,
    'max_total_tokens': maxTotalTokens,
    'input_price_per_token': inputPricePerToken,
    'output_price_per_token': outputPricePerToken,
    'capabilities': capabilities.toJson(),
    'last_synced': lastSynced.toIso8601String(),
  };
  
  // Create a copy with updated fields
  LLMModel copyWith({
    String? modelId,
    String? displayName,
    String? provider,
    int? maxInputTokens,
    int? maxOutputTokens,
    int? maxTotalTokens,
    double? inputPricePerToken,
    double? outputPricePerToken,
    ModelCapabilities? capabilities,
    DateTime? lastSynced,
  }) {
    return LLMModel(
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      provider: provider ?? this.provider,
      maxInputTokens: maxInputTokens ?? this.maxInputTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      maxTotalTokens: maxTotalTokens ?? this.maxTotalTokens,
      inputPricePerToken: inputPricePerToken ?? this.inputPricePerToken,
      outputPricePerToken: outputPricePerToken ?? this.outputPricePerToken,
      capabilities: capabilities ?? this.capabilities,
      lastSynced: lastSynced ?? this.lastSynced,
    );
  }

  // Calculate the cost for a specific number of tokens
  double calculateInputCost(int tokens) {
    return tokens * inputPricePerToken;
  }

  double calculateOutputCost(int tokens) {
    return tokens * outputPricePerToken;
  }

  double calculateTotalCost(int inputTokens, int outputTokens) {
    return calculateInputCost(inputTokens) + calculateOutputCost(outputTokens);
  }

  // Format the cost as a user-friendly string
  static String formatCost(double cost) {
    if (cost < 0.01) {
      return '\$${(cost * 1000).toStringAsFixed(2)}m'; // millicents
    } else {
      return '\$${cost.toStringAsFixed(4)}';
    }
  }

  // Get color for provider
  Color getProviderColor() {
    switch (provider.toLowerCase()) {
      case 'openai':
        return Colors.green;
      case 'anthropic':
        return Colors.purple;
      case 'ollama':
        return Colors.orange;
      case 'groq':
        return Colors.blue;
      case 'meta':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  // Get icon for provider
  IconData getProviderIcon() {
    switch (provider.toLowerCase()) {
      case 'openai':
        return Icons.auto_awesome;
      case 'anthropic':
        return Icons.psychology;
      case 'ollama':
        return Icons.computer;
      case 'groq':
        return Icons.bolt;
      case 'meta':
        return Icons.facebook;
      default:
        return Icons.smart_toy;
    }
  }
} 