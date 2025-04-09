import 'package:flutter/material.dart';
import 'dart:async';  // Add this for unawaited
import '../models/user_model.dart';
import 'auth_service.dart';
import 'model_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/env_config.dart';
import 'encryption_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final ModelService _modelService;
  late final EncryptionService _encryptionService;
  bool _isLoading = true;
  String? _error;
  
  // Getters
  User? get currentUser => _authService.currentUser;
  bool get isLoggedIn => _authService.isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Alias for isLoggedIn with clearer semantics
  bool get isAuthenticated => isLoggedIn;

  // Constructor - Dependencies removed
  AuthProvider({
    AuthService? authService,
    ModelService? modelService,
  }) : _authService = authService ?? AuthService(),
       _modelService = modelService ?? ModelService() {
    _encryptionService = EncryptionService();
    _init();
  }

  // Initialize auth state
  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _encryptionService.initializeKeys();
      await _authService.init();
      if (currentUser != null) {
        // Ensure we have the server's public key
        await _encryptionService.fetchAndStoreServerPublicKey(EnvConfig.backendUrl);
      }
    } catch (e) {
      _setError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Helper method to sanitize error messages
  void _setError(dynamic exception) {
    String errorMessage = exception.toString();
    
    // Remove Exception: prefix
    errorMessage = errorMessage.replaceAll(RegExp(r'^Exception: '), '');
    
    // Sanitize any potentially exposed passwords or tokens
    errorMessage = errorMessage.replaceAll(RegExp(r'"password":"[^"]*"'), '"password":"[REDACTED]"');
    errorMessage = errorMessage.replaceAll(RegExp(r'"token":"[^"]*"'), '"token":"[REDACTED]"');
    
    // Clean up common error messages for better user experience
    if (errorMessage.contains('Username already exists')) {
      errorMessage = 'Username already exists. Please choose a different one.';
    } else if (errorMessage.contains('Registration failed')) {
      errorMessage = 'Unable to create account. Please try again.';
    } else if (errorMessage.contains('Login failed')) {
      errorMessage = 'Sign in failed. Please check your credentials.';
    } else if (errorMessage.contains('User not found')) {
      errorMessage = 'Account not found. Please check your username.';
    } else if (errorMessage.contains('Invalid password')) {
      errorMessage = 'Incorrect password. Please try again.';
    } else if (errorMessage.contains('Field required')) {
      errorMessage = 'Please fill in all required fields.';
    }
    
    _error = errorMessage;
  }
  
  // Load models after login (renamed from _syncModelsAfterLogin)
  Future<void> _loadModelsAfterLogin() async {
    try {
      if (currentUser != null) {
        // Only use the /models/list endpoint to fetch models
        final models = await _modelService.getModels();
        
        if (models.isNotEmpty) {
          debugPrint('Successfully fetched ${models.length} models after login');
        } else {
          // If first attempt returns no models, try once more after a short delay
          await Future.delayed(Duration(milliseconds: 500));
          final retryModels = await _modelService.getModels();
          
          if (retryModels.isNotEmpty) {
            debugPrint('Successfully fetched ${retryModels.length} models on retry after login');
          } else {
            debugPrint('No models available after login attempts');
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading models after login: $e');
      // Don't show the error to the user as this is a background operation
    }
  }
  
  // Login with username and password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;  // Clear any previous errors
    notifyListeners();
    
    try {
      // Initialize encryption and fetch server public key first
      await _encryptionService.initializeKeys();
      await _encryptionService.fetchAndStoreServerPublicKey(EnvConfig.backendUrl);

      await _authService.login(username, password);
      
      // After successful login, load models
      if (currentUser != null) {
        debugPrint('Login successful, loading models for user: ${currentUser!.id}');
        // Run model loading in the background to not block the UI
        unawaited(_loadModelsAfterLogin());  // Use unawaited to not block
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _setError(e);
      notifyListeners();
      return false;
    }
  }
  
  // Register a new user
  Future<bool> register(String username, String password, String displayName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Initialize encryption and fetch server public key first
      await _encryptionService.initializeKeys();
      await _encryptionService.fetchAndStoreServerPublicKey(EnvConfig.backendUrl);

      await _authService.register(username, password, displayName);
      _isLoading = false;
      notifyListeners();

      // After successful registration, load models
      if (currentUser != null) {
        debugPrint('Registration successful, loading models for user: ${currentUser!.id}');
        // Run model loading in the background to not block the UI
        _loadModelsAfterLogin();
      }
      // Key fetching logic removed

      return true;
    } catch (e) {
      _isLoading = false;
      _setError(e);
      notifyListeners();
      return false;
    }
  }
  
  // Logout the current user
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _authService.logout();
      // Key clearing logic removed
    } catch (e) {
      _setError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user's display name
  Future<bool> updateName(String newName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _authService.updateName(newName);
      // No need to update _currentUser locally as AuthService handles it and saves to storage.
      // We rely on the next app load or a manual refresh to get the updated user data.
      // Alternatively, could fetch user data again here, but might be overkill.
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _setError(e);
      notifyListeners();
      return false;
    }
  }

  // Update user's password
  Future<bool> updatePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _authService.updatePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _setError(e);
      notifyListeners();
      return false;
    }
  }
  
  // Clear any error messages
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
