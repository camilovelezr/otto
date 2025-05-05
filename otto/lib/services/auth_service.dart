import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../config/env_config.dart';
import 'encryption_service.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:convert/convert.dart'; // For hex

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  // This would be your API base URL
  final String _baseUrl = EnvConfig.backendUrl;

  // Cache the current user
  User? _currentUser;
  String? _token;

  // Instance of encryption service - pass 'this' AuthService instance
  late final EncryptionService _encryptionService;

  final FlutterSecureStorage _storage;
  http.Client _client;

  AuthService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client() {
    // Initialize EncryptionService here, passing the created AuthService instance
    _encryptionService = EncryptionService(this);
    debugPrint(
        '[AuthService] Instance created and EncryptionService initialized.');
  }

  // Get the current logged in user
  User? get currentUser => _currentUser;

  // Check if user is logged in
  bool get isLoggedIn => _token != null && _currentUser != null;

  // Method to get Authentication Headers
  Future<Map<String, String>> getAuthHeaders() async {
    // Ensure token is loaded if not already in memory
    if (_token == null) {
      await _loadSession(); // This method loads the token too
    }
    if (_token == null) {
      throw Exception('Not authenticated: Token not available.');
    }
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json', // Often needed
      'Accept': 'application/json', // Good practice
    };
  }

  // Initialize the auth service (call on app startup)
  Future<void> init() async {
    await _loadSession();
    if (isLoggedIn) {
      // Initialize encryption keys only if logged in
      // Let AuthProvider handle calling initializeKeys on login/register now
      // try {
      //   await _encryptionService.initializeKeys();
      //   debugPrint('[AuthService] Encryption keys initialized during AuthService init.');
      // } catch (e) {
      //   debugPrint('[AuthService] Failed to initialize encryption keys during init: $e');
      //   // Might want to clear session if keys are crucial and fail to load?
      //   // await _clearSession();
      // }
    } else {
      debugPrint('[AuthService] No session found during init.');
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

          // ---> CHECK FOR KEY MISMATCH <---
          final bool userShouldHaveKey =
              _currentUser!.hasPublicKey && (_currentUser!.keyVersion ?? 0) > 0;
          final bool keysWereNewlyGenerated =
              _encryptionService.keysWereJustGenerated;

          if (userShouldHaveKey && keysWereNewlyGenerated) {
            // Key mismatch detected!
            debugPrint(
                '[AuthService.login] Key mismatch: Server expects key, but local keys were just generated.');
            // Throw a specific exception that the AuthProvider can catch
            throw KeyImportRequiredException(_currentUser!);
          }
          // ---> END CHECK <---

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
        if (userData.containsKey('id') &&
            userData['id'] is Map &&
            (userData['id'] as Map).isEmpty) {
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
  Future<User> register(
      String username, String password, String displayName) async {
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
      String? publicKeyBase64;
      try {
        publicKeyBase64 = await _encryptionService.getUserPublicKeyBase64();
        if (publicKeyBase64 == null || publicKeyBase64.isEmpty) {
          debugPrint('Failed to get public key - returned null or empty');
          throw Exception(
              'Failed to get public key base64 from encryption service');
        }
        debugPrint('Successfully retrieved public key base64');
      } catch (e) {
        debugPrint('Error getting public key base64: $e');
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
                'public_key_base64': publicKeyBase64,
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
        throw Exception(
            'Failed to update name: Unknown error'); // Should not be reached
      }
    } catch (e) {
      debugPrint('Error updating name: $e');
      rethrow;
    }
  }

  // Update user's password
  Future<void> updatePassword(
      String currentPassword, String newPassword) async {
    if (!isLoggedIn) throw Exception('User not logged in');

    final url = Uri.parse('${EnvConfig.backendUrl}/auth/update-password');
    final headers = await getAuthHeaders()
      ..['Content-Type'] = 'application/json';
    final body = jsonEncode({
      'current_password': currentPassword,
      'new_password': newPassword,
    });

    debugPrint('[AuthService] Attempting password update...');
    final response = await _client.put(url, headers: headers, body: body);

    if (response.statusCode != 200) {
      debugPrint(
          '[AuthService] Password update failed: ${response.statusCode} ${response.body}');
      throw Exception('Failed to update password: ${response.body}');
    }
    debugPrint('[AuthService] Password updated successfully.');
    // Password updated on backend, no local state change needed unless
    // we re-authenticate or require password for local operations.
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
        if (userData.containsKey('id') &&
            userData['id'] is Map &&
            (userData['id'] as Map).isEmpty) {
          // Replace empty object with a simple string ID or null
          userData['id'] = null;
        }

        _token = storedToken;
        _currentUser = User.fromJson(userData);

        // Attach the loaded token to the user model if it wasn't stored there
        if (_currentUser != null && _token != null) {
          _currentUser = _currentUser!.copyWith(authToken: _token);
        }
      } catch (e) {
        debugPrint('Failed to parse stored user data: $e');
        // Clear potentially corrupted data
        await prefs.remove(_userKey);
        _currentUser = null;
      }
    } else {
      _currentUser = null;
    }

    if (_token == null) {
      // If token is missing, ensure user is also null
      _currentUser = null;
    }
    debugPrint(
        'Loaded token from storage: ${_token != null ? "Present" : "Missing"}');
    debugPrint('Loaded user from storage: ${_currentUser?.username}');
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

  // Method to check if the public key exists on the server and upload if not
  Future<void> checkAndUploadPublicKey() async {
    if (!isLoggedIn) return; // Should not happen if called after login

    debugPrint('[AuthService] Checking if public key needs to be uploaded...');
    final url = Uri.parse('${EnvConfig.backendUrl}/auth/check-public-key');
    final headers = await getAuthHeaders();

    try {
      final response = await _client.get(url, headers: headers);
      debugPrint(
          '[AuthService] Check public key response: ${response.statusCode}');

      if (response.statusCode == 404) {
        // Key not found on server, need to upload
        debugPrint(
            '[AuthService] Public key not found on server. Uploading...');
        // Corrected: Use getUserPublicKeyBase64()
        final publicKeyBase64 =
            await _encryptionService.getUserPublicKeyBase64();
        if (publicKeyBase64.isNotEmpty) {
          // Check if key generation was successful
          await _uploadPublicKey(publicKeyBase64);
        } else {
          debugPrint('[AuthService] Failed to get user public key for upload.');
        }
      } else if (response.statusCode == 200) {
        // Key already exists
        debugPrint('[AuthService] Public key already exists on server.');
      } else {
        // Handle other potential errors
        debugPrint(
            '[AuthService] Error checking public key: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[AuthService] Failed to check/upload public key: $e');
    }
  }

  // Helper method to upload the public key
  Future<void> _uploadPublicKey(String publicKeyBase64) async {
    final url = Uri.parse('${EnvConfig.backendUrl}/auth/upload-public-key');
    final headers = await getAuthHeaders()
      ..['Content-Type'] = 'application/json';
    final body = jsonEncode({'public_key': publicKeyBase64});

    try {
      final response = await _client.post(url, headers: headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[AuthService] Public key uploaded successfully.');
      } else {
        debugPrint(
            '[AuthService] Failed to upload public key: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[AuthService] Error uploading public key: $e');
    }
  }

  /// Downloads the user's encrypted seed backup and decrypts it using the provided passphrase.
  Future<Uint8List> downloadAndDecryptSeedBackup(
      String username, String passphrase) async {
    debugPrint('[AuthService] Attempting to download backup for $username');
    final url = Uri.parse('${EnvConfig.backendUrl}/auth/seed-backup/$username');
    final headers = await getAuthHeaders(); // Need auth to access backup

    try {
      final response = await _client.get(url, headers: headers);

      debugPrint(
          '[AuthService] Download backup response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final encryptedSeedB64 = data['encrypted_seed_b64'] as String?;
        final kdfParams = data['kdf_params'] as Map<String, dynamic>?;

        if (encryptedSeedB64 == null || kdfParams == null) {
          throw Exception('Invalid backup data received from server.');
        }

        // --- Decryption Logic ---
        try {
          debugPrint(
              '[AuthService] Backup data received, starting decryption...');
          // 1. Parse KDF parameters
          final saltB64 = kdfParams['salt'] as String?;
          final iterations = kdfParams['iterations'] as int?;
          final memory = kdfParams['memory'] as int?;
          final parallelism = kdfParams['parallelism'] as int?;
          final hashLength = kdfParams['hashLength'] as int?;
          final nonceLength = kdfParams['nonceLength'] as int?;
          final macLength = kdfParams['macLength'] as int?;

          if (saltB64 == null ||
              iterations == null ||
              memory == null ||
              parallelism == null ||
              hashLength == null ||
              nonceLength == null ||
              macLength == null) {
            throw Exception('Missing KDF parameters in backup data.');
          }

          final salt = base64Decode(saltB64);
          final encryptedSeedBytes = base64Decode(encryptedSeedB64);

          // 2. Derive AES key using Argon2id
          debugPrint('[AuthService] Deriving key with Argon2id...');
          final argon2 = crypto.Argon2id(
            parallelism: parallelism,
            memory: memory,
            iterations: iterations,
            hashLength: hashLength,
          );
          final derivedKey = await argon2.deriveKeyFromPassword(
            password: passphrase,
            nonce: salt, // Argon2 uses nonce for the salt parameter
          );
          final aesEncryptionKey =
              await derivedKey.extract(); // Get SecretKeyData
          debugPrint('[AuthService] AES key derived.');

          // 3. Reconstruct SecretBox and Decrypt using AES-GCM
          debugPrint('[AuthService] Reconstructing SecretBox...');
          final secretBox = crypto.SecretBox.fromConcatenation(
            encryptedSeedBytes,
            nonceLength: nonceLength,
            macLength: macLength,
          );
          debugPrint('[AuthService] SecretBox reconstructed, decrypting...');

          final aesGcm = crypto.AesGcm.with256bits();
          final decryptedSeed = await aesGcm.decrypt(
            secretBox,
            secretKey: aesEncryptionKey,
          );
          debugPrint('[AuthService] Seed decrypted successfully!');
          return Uint8List.fromList(decryptedSeed); // Return as Uint8List
        } on crypto.SecretBoxAuthenticationError {
          debugPrint(
              '[AuthService] Decryption failed: MAC validation failed (likely wrong passphrase).');
          throw DecryptionFailedException(
              'Decryption failed: Invalid passphrase or corrupted data.');
        } catch (e) {
          debugPrint('[AuthService] Error during decryption: $e');
          throw DecryptionFailedException(
              'Failed to decrypt backup: ${e.toString()}');
        }
      } else if (response.statusCode == 404) {
        debugPrint('[AuthService] Backup not found for user $username.');
        throw BackupNotFoundException(username);
      } else if (response.statusCode == 401) {
        debugPrint('[AuthService] Unauthorized to access backup.');
        throw Exception('Unauthorized. Please log in again.');
      } else {
        debugPrint(
            '[AuthService] Failed to download backup: ${response.statusCode} ${response.body}');
        throw Exception('Failed to download backup (${response.statusCode}).');
      }
    } catch (e) {
      // Catch network errors or exceptions from above
      debugPrint('[AuthService] Error in downloadAndDecryptSeedBackup: $e');
      // Rethrow specific exceptions or a generic one
      if (e is BackupNotFoundException || e is DecryptionFailedException) {
        rethrow;
      }
      throw Exception('Could not retrieve or decrypt backup: ${e.toString()}');
    }
  }

  // Helper to set user and save session
  Future<void> _setUserAndSession(User user, String token) async {
    _currentUser = user;
    _token = token;
    await _saveSession();
  }

  // Load session from storage
  Future<void> _loadSession() async {
    try {
      _token = await _storage.read(key: 'auth_token');
      final userJson = await _storage.read(key: 'current_user');
      if (_token != null && userJson != null) {
        _currentUser = User.fromJson(jsonDecode(userJson));
        debugPrint(
            '[AuthService] Session loaded for user: ${_currentUser?.username}');
      } else {
        debugPrint('[AuthService] No session data found in storage.');
        _token = null;
        _currentUser = null;
      }
    } catch (e) {
      debugPrint('[AuthService] Failed to load session: $e');
      // Ensure clean state on error
      _token = null;
      _currentUser = null;
    }
  }

  // Save session to storage
  Future<void> _saveSession() async {
    try {
      if (_token != null && _currentUser != null) {
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(
            key: 'current_user', value: jsonEncode(_currentUser!.toJson()));
        debugPrint(
            '[AuthService] Session saved for user: ${_currentUser?.username}');
      } else {
        // If logging out or session invalid, clear storage
        await _clearSession();
      }
    } catch (e) {
      debugPrint('[AuthService] Failed to save session: $e');
      // Consider what to do on save failure - maybe alert user?
    }
  }

  // Clear session from storage
  Future<void> _clearSession() async {
    try {
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'current_user');
      debugPrint('[AuthService] Session cleared from storage.');
    } catch (e) {
      debugPrint('[AuthService] Failed to clear session: $e');
    }
    // Clear in-memory state too
    _token = null;
    _currentUser = null;
  }
}

// Define custom exception for key import requirement
class KeyImportRequiredException implements Exception {
  final User user;
  KeyImportRequiredException(this.user);

  @override
  String toString() =>
      'KeyImportRequiredException: Key import needed for user ${user.username}';
}

// Custom Exception for Passphrase Backup Not Found
class BackupNotFoundException implements Exception {
  final String username;
  BackupNotFoundException(this.username);
  @override
  String toString() =>
      'BackupNotFoundException: No passphrase backup found for user $username';
}

// Custom Exception for Passphrase Backup Decryption Failure
class DecryptionFailedException implements Exception {
  final String message;
  DecryptionFailedException(this.message);
  @override
  String toString() => 'DecryptionFailedException: $message';
}
