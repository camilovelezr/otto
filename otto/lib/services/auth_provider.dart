import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'auth_service.dart';
import 'model_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ModelService _modelService = ModelService();
  
  bool _isLoading = false;
  String? _error;
  
  // Getters
  User? get currentUser => _authService.currentUser;
  bool get isLoggedIn => _authService.isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Alias for isLoggedIn with clearer semantics
  bool get isAuthenticated => isLoggedIn;
  
  // Constructor
  AuthProvider() {
    _initialize();
  }
  
  // Initialize auth state
  Future<void> _initialize() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _authService.init();
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
  
  // Login with username and password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      await _authService.login(username, password);
      _isLoading = false;
      notifyListeners();
      
      // After successful login, trigger model sync if we have a user ID
      if (currentUser != null && currentUser!.id != null) {
        debugPrint('Login successful, syncing models for user: ${currentUser!.id}');
        // Run model sync in the background to not block the UI
        _syncModelsAfterLogin();
      }
      
      return true;
    } catch (e) {
      _isLoading = false;
      _setError(e);
      notifyListeners();
      return false;
    }
  }
  
  // Sync models in the background after login
  Future<void> _syncModelsAfterLogin() async {
    try {
      if (currentUser != null) {
        // Pass both ID and username for more reliable authentication
        await _modelService.syncModels(
          userId: currentUser!.id?.toString() ?? '',
          username: currentUser!.username,
        );
        debugPrint('Synced models using username: ${currentUser!.username}');
      }
    } catch (e) {
      debugPrint('Error syncing models after login: $e');
      // Don't show the error to the user as this is a background operation
    }
  }
  
  // Register a new user
  Future<bool> register(String username, String password, String displayName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      await _authService.register(username, password, displayName);
      _isLoading = false;
      notifyListeners();
      
      // After successful registration, trigger model sync if we have a user ID
      if (currentUser != null && currentUser!.id != null) {
        debugPrint('Registration successful, syncing models for user: ${currentUser!.id}');
        // Run model sync in the background to not block the UI
        _syncModelsAfterLogin();
      }
      
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
    } catch (e) {
      _setError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Clear any error messages
  void clearError() {
    _error = null;
    notifyListeners();
  }
} 