class User {
  final dynamic id; // Using dynamic to handle different ID types
  final String username;
  final String name;
  final String password; // This will be [REDACTED]
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hasPublicKey;
  final int keyVersion;
  final String? authToken;  // Made optional

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.password,
    required this.createdAt,
    required this.updatedAt,
    required this.hasPublicKey,
    required this.keyVersion,
    this.authToken,  // Optional parameter
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '', // Handle potential null id
      username: json['username'] as String,
      name: json['name'] as String,
      password: json['password'] as String? ?? '[REDACTED]',
      createdAt: json.containsKey('created_at') 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json.containsKey('updated_at')
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      hasPublicKey: json['has_public_key'] as bool? ?? false,
      keyVersion: json['key_version'] as int? ?? 1,
      authToken: json['auth_token'] as String?,  // Optional field
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'password': '[REDACTED]', // Never store actual password
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'has_public_key': hasPublicKey,
      'key_version': keyVersion,
      'auth_token': authToken,
    };
  }

  User copyWith({
    dynamic id,
    String? username,
    String? name,
    String? password,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hasPublicKey,
    int? keyVersion,
    String? authToken,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hasPublicKey: hasPublicKey ?? this.hasPublicKey,
      keyVersion: keyVersion ?? this.keyVersion,
      authToken: authToken ?? this.authToken,
    );
  }
} 