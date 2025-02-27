import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static final EnvConfig _instance = EnvConfig._internal();
  factory EnvConfig() => _instance;
  EnvConfig._internal();

  static String get backendUrl => dotenv.env['BACKEND_URL'] ?? 'http://localhost:4000';
  static bool get debugMode => (dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true') || false;

  static Future<void> load() async {
    await dotenv.load();
  }

  @override
  String toString() => 'EnvConfig(backendUrl: $backendUrl, debugMode: $debugMode)';
} 