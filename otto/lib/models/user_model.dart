class User {
  final dynamic id; // Using dynamic to handle different ID types
  final String username;
  final String name;
  final String password; // This will be [REDACTED]
  final DateTime createdAt;
  final String authToken;

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.password,
    required this.createdAt,
    required this.authToken,
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
      authToken: json['auth_token'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'password': '[REDACTED]', // Never store actual password
      'created_at': createdAt.toIso8601String(),
      'auth_token': authToken,
    };
  }
} 