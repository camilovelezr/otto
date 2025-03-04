import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../config/env_config.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  
  // This would be your API base URL
  final String _baseUrl = EnvConfig.backendUrl;
  
  // Cache the current user
  User? _currentUser;
  String? _token;
  
  // Get the current logged in user
  User? get currentUser => _currentUser;
  
  // Check if user is logged in
  bool get isLoggedIn => _token != null && _currentUser != null;
  
  // Initialize the auth service (call on app startup)
  Future<void> init() async {
    await _loadUserFromStorage();
  }
  
  // Login with username and password
  Future<User> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/$username/verify'),
        headers: {
          'Content-Type': 'text/plain',
          'Accept': 'application/json'
        },
        body: password,
      );
      
      // Handle different status codes
      switch (response.statusCode) {
        case 200:
          // Get user details after successful verification
          final userData = await _getUserData(username);
          
          // Set user and token
          _token = 'temp_token_$username';
          _currentUser = userData;
          
          // Save to local storage
          await _saveUserToStorage(_token!, _currentUser!);
          
          return _currentUser!;
          
        case 401:
          throw Exception('Invalid password');
          
        case 404:
          throw Exception('User not found');
          
        default:
          // Try to parse response body for detailed error
          _throwFormattedError(response, 'Login failed');
          // This line will never be reached due to the throw above, but is needed for null safety
          throw Exception('Login failed: Unknown error');
      }
    } catch (e) {
      // Rethrow if it's already a formatted Exception
      if (e is Exception) {
        rethrow;
      }
      // Otherwise wrap in a general login error
      throw Exception('Login error: $e');
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
      final response = await http.post(
        Uri.parse('$_baseUrl/users/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'name': displayName,
        }),
      );
      
      switch (response.statusCode) {
        case 201:
          final userData = json.decode(response.body);
          
          // Debug print the response structure
          debugPrint('Registration response: ${response.body}');
          debugPrint('Decoded userData: $userData');
          
          // Handle id field that might be a Map or empty object
          if (userData.containsKey('id') && userData['id'] is Map && (userData['id'] as Map).isEmpty) {
            // Replace empty object with a simple string ID or null
            userData['id'] = null;
          }
          
          // Ensure password is never stored in the model
          if (userData.containsKey('password')) {
            userData['password'] = '[REDACTED]';
          }
          
          // Set user and token
          _token = 'temp_token_$username';
          _currentUser = User.fromJson(userData);
          
          // Save to local storage
          await _saveUserToStorage(_token!, _currentUser!);
          
          return _currentUser!;
          
        case 400:
          throw Exception('Username already exists');
          
        case 422:
          // Validation error
          try {
            final errorData = json.decode(response.body);
            throw Exception('Registration failed: ${_formatValidationError(errorData)}');
          } catch (_) {
            throw Exception('Registration failed: Invalid input data');
          }
          
        default:
          _throwFormattedError(response, 'Registration failed');
          // This line will never be reached but is needed for null safety
          throw Exception('Registration failed: Unknown error');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Registration error: $e');
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
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };
  }
} 