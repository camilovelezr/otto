import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../config/env_config.dart';
import 'encryption_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  
  // This would be your API base URL
  final String _baseUrl = EnvConfig.backendUrl;
  
  // Cache the current user
  User? _currentUser;
  String? _token;
  
  // Instance of encryption service
  final EncryptionService _encryptionService = EncryptionService();
  
  // Get the current logged in user
  User? get currentUser => _currentUser;
  
  // Check if user is logged in
  bool get isLoggedIn => _token != null && _currentUser != null;
  
  // Initialize the auth service (call on app startup)
  Future<void> init() async {
    try {
      debugPrint('Starting auth service initialization...');
      
      // First load user from storage
      await _loadUserFromStorage();
      debugPrint('User loaded from storage: ${_currentUser?.username ?? "none"}');
      
      // Initialize encryption service
      debugPrint('Initializing encryption service...');
      await _encryptionService.initializeKeys();
      debugPrint('Encryption service initialized');
      
      // Fetch server's public key with retries
      debugPrint('Fetching server public key...');
      bool keyFetched = false;
      int maxRetries = 3;
      int currentRetry = 0;
      
      while (!keyFetched && currentRetry < maxRetries) {
        try {
          await _encryptionService.fetchAndStoreServerPublicKey(_baseUrl);
          debugPrint('Server public key fetched and stored successfully');
          keyFetched = true;
        } catch (e) {
          currentRetry++;
          debugPrint('Failed to fetch server public key (attempt $currentRetry/$maxRetries): $e');
          if (currentRetry < maxRetries) {
            await Future.delayed(Duration(seconds: 2 * currentRetry)); // Exponential backoff
          }
        }
      }
      
      if (!keyFetched) {
        throw Exception('Failed to fetch server public key after $maxRetries attempts');
      }
      
      debugPrint('Auth service initialization completed successfully');
    } catch (e) {
      debugPrint('Error during auth service initialization: $e');
      throw Exception('Auth service initialization failed: $e');
    }
  }
  
  // Helper method to ensure we have server public key
  Future<void> _ensureServerPublicKey() async {
    try {
      // Try to fetch server public key if we don't have it
      await _encryptionService.fetchAndStoreServerPublicKey(_baseUrl);
      debugPrint('Server public key fetched and stored successfully');
    } catch (e) {
      debugPrint('Failed to fetch server public key: $e');
      throw Exception('Failed to fetch server public key: $e');
    }
  }
  
  // Login with username and password
  Future<User> login(String username, String password) async {
    try {
      debugPrint('Starting login process for user: $username');

      // First, ensure encryption service is initialized
      debugPrint('Initializing encryption service...');
      try {
        await _encryptionService.initializeKeys();
        debugPrint('Encryption service initialized successfully');
      } catch (e) {
        debugPrint('Failed to initialize encryption service: $e');
        throw Exception('Failed to initialize encryption: $e');
      }

      // Ensure we have server's public key
      await _ensureServerPublicKey();

      // Send login request
      debugPrint('Sending login request...');
      final response = await http.post(
        Uri.parse('$_baseUrl/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      debugPrint('Login response status: ${response.statusCode}');

      switch (response.statusCode) {
        case 200:
          final data = json.decode(response.body);
          _token = data['auth_token'];

          // Create user object from response data
          _currentUser = User(
            id: data['id'] ?? '',
            username: data['username'],
            name: data['name'],
            password: '[REDACTED]',
            createdAt: DateTime.parse(data['created_at']),
            updatedAt: DateTime.parse(data['updated_at']),
            hasPublicKey: data['has_public_key'] ?? false,
            keyVersion: data['key_version'] ?? 1,
            authToken: _token,
          );

          // Save to local storage
          await _saveUserToStorage(_token!, _currentUser!);

          return _currentUser!;

        case 401:
          throw Exception('Invalid username or password');

        default:
          debugPrint('Login failed with response: ${response.body}');
          _throwFormattedError(response, 'Login failed');
          throw Exception('Login failed: Unknown error');
      }
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }
  
  // Helper method to handle API errors safely
  Never _throwFormattedError(http.Response response, String defaultMessage) {
    try {
      final errorData = json.decode(response.body);
      if (errorData['detail'] != null) {
        throw Exception('$defaultMessage: ${errorData['detail']}');
      }
    } catch (_) {
      // If we can't parse the error, use the default message
    }
    throw Exception('$defaultMessage (${response.statusCode})');
  }
  
  // Get user data by username
  Future<User> _getUserData(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/users/$username'),
        headers: {'Accept': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        
        // Debug print the response structure
        debugPrint('User data response: ${response.body}');
        
        // Handle id field that might be a Map or empty object
        if (userData.containsKey('id') && userData['id'] is Map && (userData['id'] as Map).isEmpty) {
          // Replace empty object with a simple string ID or null
          userData['id'] = null;
        }
        
        // Ensure password is never stored in the model
        if (userData.containsKey('password')) {
          userData['password'] = '[REDACTED]';
        }
        
        return User.fromJson(userData);
      } else {
        _throwFormattedError(response, 'Failed to get user data');
        // This line will never be reached but is needed for null safety
        throw Exception('Failed to get user data: Unknown error');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Error fetching user data: $e');
    }
  }
  
  // Register a new user
  Future<User> register(String username, String password, String displayName) async {
    try {
      debugPrint('Starting registration process for user: $username');
      
      // First, ensure encryption service is initialized
      debugPrint('Initializing encryption service...');
      try {
        await _encryptionService.initializeKeys();
        debugPrint('Encryption service initialized successfully');
      } catch (e) {
        debugPrint('Failed to initialize encryption service: $e');
        throw Exception('Failed to initialize encryption: $e');
      }

      // Fetch server's public key
      debugPrint('Fetching server public key...');
      try {
        await _encryptionService.fetchAndStoreServerPublicKey(_baseUrl);
        debugPrint('Server public key fetched and stored successfully');
      } catch (e) {
        debugPrint('Failed to fetch server public key: $e');
        throw Exception('Failed to fetch server public key: $e');
      }

      // Generate new key pair for the user
      debugPrint('Requesting public key from encryption service...');
      String? publicKeyPem;
      try {
        publicKeyPem = await _encryptionService.getPublicKeyPem();
        if (publicKeyPem == null) {
          debugPrint('Failed to get public key - returned null');
          throw Exception('Failed to get public key from encryption service');
        }
        debugPrint('Successfully retrieved public key');
      } catch (e) {
        debugPrint('Error getting public key: $e');
        throw Exception('Failed to get public key: $e');
      }

      // Register user with the server
      debugPrint('Sending registration request to server...');
      final response = await http.post(
        Uri.parse('$_baseUrl/users/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'name': displayName,
        }),
      );
      
      debugPrint('Registration response status: ${response.statusCode}');
      debugPrint('Registration response body: ${response.body}');
      
      switch (response.statusCode) {
        case 200:
        case 201:
          final data = json.decode(response.body);
          _token = data['auth_token'];
          
          if (_token == null) {
            throw Exception('Server did not return an auth token');
          }
          
          // Create user object from response data
          _currentUser = User(
            id: data['id'],
            username: data['username'],
            name: data['name'],
            password: '[REDACTED]',
            createdAt: DateTime.parse(data['created_at']),
            updatedAt: DateTime.parse(data['updated_at']),
            hasPublicKey: false, // Will be updated after key upload
            keyVersion: 1,
            authToken: _token,
          );
          
          // Upload public key
          try {
            final keyResponse = await http.post(
              Uri.parse('$_baseUrl/users/me/public-key'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-Username': _currentUser!.username,
              },
              body: json.encode({
                'public_key_pem': publicKeyPem,
              }),
            );

            if (keyResponse.statusCode != 200) {
              debugPrint('Failed to upload public key: ${keyResponse.body}');
              // Don't throw, just log the error as this is not critical
            } else {
              debugPrint('Public key uploaded successfully');
              // Update the user object with the new key status
              final keyData = json.decode(keyResponse.body);
              _currentUser = _currentUser!.copyWith(
                hasPublicKey: true,
                keyVersion: keyData['key_version'] as int? ?? 1,
              );
            }
          } catch (e) {
            debugPrint('Error uploading public key: $e');
            // Don't throw, just log the error as this is not critical
          }

          // Save to local storage
          await _saveUserToStorage(_token!, _currentUser!);
          
          return _currentUser!;
          
        case 400:
          _throwFormattedError(response, 'Registration failed');
          throw Exception('Registration failed: Bad request');
          
        default:
          _throwFormattedError(response, 'Registration failed');
          throw Exception('Registration failed: Unknown error');
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      rethrow;
    }
  }
  
  // Format validation errors in a user-friendly way
  String _formatValidationError(Map<String, dynamic> errorData) {
    if (errorData['detail'] != null) {
      final detail = errorData['detail'];
      
      // If it's a list of validation errors
      if (detail is List) {
        final List errors = detail;
        
        // Extract field names with errors
        final List<String> fieldErrors = [];
        for (var error in errors) {
          if (error is Map && error.containsKey('loc')) {
            final loc = error['loc'];
            if (loc is List && loc.length > 1) {
              // The second item in loc is usually the field name
              fieldErrors.add(loc[1].toString());
            }
          }
        }
        
        if (fieldErrors.isNotEmpty) {
          return 'Please check these fields: ${fieldErrors.join(", ")}';
        }
      }
      
      // Simple string detail
      if (detail is String) {
        return detail;
      }
    }
    
    return 'Invalid input data';
  }
  
  // Logout the current user
  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // Update user's display name
  Future<User> updateName(String newName) async {
    if (!isLoggedIn || _currentUser == null) {
      throw Exception('Not authenticated');
    }
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/users/me/name'),
        headers: authHeaders, // Use existing authHeaders getter
        body: json.encode({'name': newName}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Update current user object
        _currentUser = _currentUser!.copyWith(
          name: data['name'],
          updatedAt: DateTime.parse(data['updated_at']),
        );
        // Re-save updated user data to storage
        await _saveUserToStorage(_token!, _currentUser!);
        return _currentUser!;
      } else {
        _throwFormattedError(response, 'Failed to update name');
        throw Exception('Failed to update name: Unknown error'); // Should not be reached
      }
    } catch (e) {
      debugPrint('Error updating name: $e');
      rethrow;
    }
  }

  // Update user's password
  Future<void> updatePassword(String currentPassword, String newPassword) async {
    try {
      debugPrint('Starting password update process...');
      
      if (_currentUser == null || _token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/users/me/password'),
        headers: {
          'Content-Type': 'application/json',
          'X-Username': _currentUser!.username,
        },
        body: json.encode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Password updated successfully');
      } else {
        _throwFormattedError(response, 'Failed to update password');
      }
    } catch (e) {
      debugPrint('Error updating password: $e');
      rethrow;
    }
  }
  
  // Save user data to storage
  Future<void> _saveUserToStorage(String token, User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    
    // Create a sanitized version of user data for storage
    final Map<String, dynamic> userData = user.toJson();
    if (userData.containsKey('password')) {
      userData['password'] = '[REDACTED]';
    }
    
    await prefs.setString(_userKey, json.encode(userData));
  }
  
  // Load user data from storage
  Future<void> _loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    
    final storedToken = prefs.getString(_tokenKey);
    final storedUserJson = prefs.getString(_userKey);
    
    if (storedToken != null && storedUserJson != null) {
      try {
        final userData = json.decode(storedUserJson);
        
        // Handle id field that might be a Map or empty object
        if (userData.containsKey('id') && userData['id'] is Map && (userData['id'] as Map).isEmpty) {
          // Replace empty object with a simple string ID or null
          userData['id'] = null;
        }
        
        _token = storedToken;
        _currentUser = User.fromJson(userData);
      } catch (e) {
        debugPrint('Error parsing stored user data: $e');
        // Clear invalid data
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      }
    }
  }
  
  // Get auth headers for authenticated requests
  Map<String, String> get authHeaders {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    // Use X-Username header instead of Bearer token for now
    if (_currentUser?.username == null) {
       throw Exception('Not authenticated or username missing');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Username': _currentUser!.username,
    };
  }
}
