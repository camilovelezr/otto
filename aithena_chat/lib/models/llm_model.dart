class LLMModel {
  final String name;

  const LLMModel({
    required this.name,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LLMModel && 
      other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
} 