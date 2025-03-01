import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
// Only import dart:io for non-web platforms
import 'package:flutter/services.dart';
// Import dart:js_util only for web
import 'dart:js_util' if (dart.library.io) 'package:otto/config/js_util_stub.dart';

// Import dart:io only for non-web platforms
import 'dart:io' if (dart.library.js) 'package:otto/config/platform_stub.dart';

class EnvConfig {
  static final EnvConfig _instance = EnvConfig._internal();
  factory EnvConfig() => _instance;
  EnvConfig._internal();

  static const MethodChannel _channel = MethodChannel('com.example.aithena_chat/config');
  static String? _androidBaseUrl;
  static Map<String, dynamic>? _webConfig;
  
  // Getter for baseUrl that checks for platform-specific values first
  static String get backendUrl {
    // On web, we use the web configuration
    if (kIsWeb) {
      if (_webConfig != null && _webConfig!.containsKey('apiUrl')) {
        return _webConfig!['apiUrl'] as String;
      }
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:4000';
    }
    
    // If we're on Android and have a specific Android BASE_URL set, use that
    if (!kIsWeb) {
      bool isAndroid = false;
      try {
        isAndroid = Platform.isAndroid;
      } catch (e) {
        // Ignore platform errors
      }
      
      if (isAndroid && _androidBaseUrl != null) {
        return _androidBaseUrl!;
      }
    }
    
    // Otherwise fallback to the .env value or default
    return dotenv.env['BACKEND_URL'] ?? 'http://localhost:4000';
  }
  
  static bool get debugMode {
    if (kIsWeb && _webConfig != null && _webConfig!.containsKey('debugMode')) {
      return _webConfig!['debugMode'] as bool;
    }
    return (dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true') || false;
  }

  // Method to set the Android-specific BASE_URL (called from native code)
  static void setAndroidBaseUrl(String url) {
    _androidBaseUrl = url;
  }

  static Future<void> load() async {
    // Try to load .env file (might fail on web)
    try {
      await dotenv.load().catchError((e) {
        debugPrint('Warning: Could not load .env file: $e');
      });
    } catch (e) {
      debugPrint('Error loading .env file: $e');
    }
    
    // On web, try to load configuration from the JavaScript context
    if (kIsWeb) {
      try {
        // Try to call the JavaScript function defined in index.html
        final jsConfig = await promiseToFuture(callMethod(globalThis, 'getWebConfig', []));
        if (jsConfig != null) {
          _webConfig = Map<String, dynamic>.from(jsConfig);
          debugPrint('Loaded web configuration: $_webConfig');
        }
      } catch (e) {
        debugPrint('Could not load web configuration: $e');
      }
    }
    
    // If we're on Android (not on web), try to get the BASE_URL from the native side
    if (!kIsWeb) {
      bool isAndroid = false;
      try {
        isAndroid = Platform.isAndroid;
      } catch (e) {
        // Ignore platform errors
      }
      
      if (isAndroid) {
        try {
          final String url = await _channel.invokeMethod('getBaseUrl');
          setAndroidBaseUrl(url);
          print('Loaded Android BASE_URL: $url');
        } catch (e) {
          print('Failed to load Android BASE_URL: $e');
        }
      }
    }
  }

  @override
  String toString() => 'EnvConfig(backendUrl: $backendUrl, debugMode: $debugMode)';
} 