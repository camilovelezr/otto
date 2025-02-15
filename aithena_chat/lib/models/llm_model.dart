class LLMModel {
  final String name;
  final String platform;
  final String? description;

  const LLMModel({
    required this.name,
    required this.platform,
    this.description,
  });

  factory LLMModel.fromName(String name, {required String platform}) {
    String? description;
    
    // Add descriptions based on model names
    if (platform == 'openai') {
      if (name.contains('gpt-4')) {
        description = 'GPT-4 model with advanced reasoning capabilities';
      } else if (name.contains('gpt-3.5')) {
        description = 'GPT-3.5 model optimized for performance and efficiency';
      }
    } else if (platform == 'ollama') {
      if (name.contains('llama')) {
        description = 'Llama model for general-purpose text generation';
      } else if (name.contains('mistral')) {
        description = 'Mistral model with strong performance on various tasks';
      }
    } else if (platform == 'groq') {
      if (name.contains('mixtral')) {
        description = 'Mixtral model with fast inference on Groq platform';
      }
    }

    return LLMModel(
      name: name,
      platform: platform,
      description: description,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LLMModel && 
      other.name == name && 
      other.platform == platform;
  }

  @override
  int get hashCode => name.hashCode ^ platform.hashCode;
} 