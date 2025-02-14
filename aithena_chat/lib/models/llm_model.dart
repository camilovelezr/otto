class LLMModel {
  final String name;
  final String platform;
  final String? description;

  LLMModel({
    required this.name,
    required this.platform,
    this.description,
  });

  factory LLMModel.fromName(String name, {String? platform, String? description}) {
    if (platform != null) {
      return LLMModel(
        name: name,
        platform: platform,
        description: description,
      );
    }

    // If no platform is provided, use a default of 'unknown'
    return LLMModel(
      name: name,
      platform: 'unknown',
      description: description,
    );
  }
} 