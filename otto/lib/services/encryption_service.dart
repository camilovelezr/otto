// Dart imports
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:developer' as developer; // Keep developer for potential future use
import 'package:flutter/foundation.dart'; // Import debugPrint
import 'dart:async'; // <-- Added for unawaited

// Flutter packages
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Third-party packages
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:asn1lib/asn1lib.dart';
import 'package:rsa_pkcs/rsa_pkcs.dart' as rsa_parser;
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:convert/convert.dart'; // For hex encoding

// PointyCastle imports
import 'package:pointycastle/api.dart'
    show
        KeyParameter,
        ParametersWithRandom,
        AsymmetricKeyPair,
        PublicKey,
        PrivateKey,
        SecureRandom,
        CipherParameters,
        PrivateKeyParameter,
        PublicKeyParameter,
        AsymmetricBlockCipher,
        Digest;
import 'package:pointycastle/asymmetric/api.dart'
    show RSAPublicKey, RSAPrivateKey;
import 'package:pointycastle/key_generators/api.dart'
    show RSAKeyGeneratorParameters;
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/digests/sha256.dart';

// Project imports
import '../config/env_config.dart'; // <-- Import EnvConfig
import 'auth_service.dart'; // Add import

// Define storage keys
const String _privateKeyStorageKey =
    'device_private_key_pem'; // Keep for cleanup
const String _publicKeyStorageKey = 'device_public_key_pem'; // Keep for cleanup
const String _serverPublicKeyStorageKey =
    'server_public_key_pem'; // Keep for cleanup
const String _seedStorageKey = 'device_identity_seed_hex'; // Current key
// const String _userPublicKeyStorageKey = 'otto_user_public_key_pem'; // Removed, not needed for Ed25519 directly

class EncryptionService {
  // Configure secure storage with options
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: true,
    ),
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Fallback storage for development/testing
  final Map<String, String> _memoryStorage = {};
  bool _useMemoryStorage = false;

  // --- NEW Ed25519 Key State ---
  crypto.SimpleKeyPair? _identityKeyPair;
  Uint8List? _identitySeed;

  // --- Add AuthService dependency ---
  final AuthService _authService;

  RSAPublicKey? _serverPublicKey; // Keep state for restored methods

  bool _keysInitialized = false;
  bool _keysWereGeneratedDuringInit = false;

  // Cache for conversation symmetric keys
  final Map<String, encrypt_lib.Key> _conversationKeys = {};

  // Constructor requires AuthService instance
  EncryptionService(this._authService) {
    debugPrint('[EncryptionService] constructor called');
    // Don't call initializeKeys automatically here, let AuthService manage timing
    // initializeKeys();
  }

  // Getter for the new flag
  bool get keysWereJustGenerated => _keysWereGeneratedDuringInit;

  Future<void> _secureWrite(String key, String value) async {
    try {
      if (_useMemoryStorage) {
        _memoryStorage[key] = value;
      } else {
        await _secureStorage.write(key: key, value: value);
      }
    } catch (e) {
      debugPrint(
          '[EncryptionService] Error writing to secure storage, falling back to memory storage: $e');
      _useMemoryStorage = true;
      _memoryStorage[key] = value;
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      if (_useMemoryStorage) {
        return _memoryStorage[key];
      } else {
        return await _secureStorage.read(key: key);
      }
    } catch (e) {
      debugPrint(
          '[EncryptionService] Error reading from secure storage, falling back to memory storage: $e');
      _useMemoryStorage = true;
      return _memoryStorage[key];
    }
  }

  Future<void> _secureDelete(String key) async {
    try {
      if (_useMemoryStorage) {
        _memoryStorage.remove(key);
      } else {
        await _secureStorage.delete(key: key);
      }
    } catch (e) {
      debugPrint(
          '[EncryptionService] Error deleting from secure storage, falling back to memory storage: $e');
      _useMemoryStorage = true;
      _memoryStorage.remove(key);
    }
  }

  // --- Key Initialization (Load or Generate - REFACTORED for Seed/Ed25519) ---
  Future<void> initializeKeys() async {
    debugPrint(
        '[EncryptionService] initializeKeys (Ed25519) called, current status: initialized=${_keysInitialized}, hasKeyPair=${_identityKeyPair != null}');

    if (_keysInitialized) {
      debugPrint('[EncryptionService] Keys already initialized, skipping');
      return;
    }

    _keysWereGeneratedDuringInit = false; // Reset flag

    try {
      debugPrint(
          '[EncryptionService] Attempting to read identity seed hex from storage...');
      final seedHex = await _secureRead(_seedStorageKey);

      if (seedHex != null && seedHex.isNotEmpty) {
        debugPrint(
            '[EncryptionService] Found existing seed hex in storage, attempting to load...');
        try {
          // 1. Decode Hex Seed
          if (seedHex.length != 64) {
            throw FormatException('Stored seed hex has incorrect length.');
          }
          final seedBytes = Uint8List.fromList(List<int>.generate(
              seedHex.length ~/ 2,
              (i) =>
                  int.parse(seedHex.substring(i * 2, i * 2 + 2), radix: 16)));
          _identitySeed = seedBytes; // Cache seed
          debugPrint('[EncryptionService] Seed hex decoded successfully.');

          // 2. Generate Key Pair from Seed
          final algorithm = crypto.Ed25519();
          _identityKeyPair = await algorithm.newKeyPairFromSeed(seedBytes);
          debugPrint(
              '[EncryptionService] Ed25519 key pair generated from loaded seed.');

          // 3. Mark initialized
          _keysInitialized = true;
          debugPrint(
              '[EncryptionService] Successfully loaded identity from stored seed.');
        } catch (parseOrGenError) {
          debugPrint(
              '[EncryptionService] Failed to load identity from stored seed: $parseOrGenError');
          // Clear potentially invalid seed and key state
          await _secureDelete(_seedStorageKey);
          _identitySeed = null;
          _identityKeyPair = null;
          _keysInitialized = false;
          // Throw exception to trigger generation below
          throw Exception(
              'Failed parsing stored seed or generating keys from it.');
        }
      } else {
        debugPrint(
            '[EncryptionService] No seed found in storage. Generating new seed and key pair...');
        // Generate and store new seed and key pair
        await _generateAndStoreDeviceSeedAndKeyPair();
        // _generateAndStoreDeviceSeedAndKeyPair sets _keysInitialized and _keysWereGeneratedDuringInit
      }

      // If keys were generated, check if we need to upload the public key
      if (_keysWereGeneratedDuringInit) {
        debugPrint(
            '[EncryptionService] New keys were generated during init. Checking if public key needs upload.');
        // Use unawaited as this is a background task
        unawaited(_authService.checkAndUploadPublicKey());
      }

      // Ensure server public key is loaded (can happen regardless of key generation)
      // Important: Run AFTER initializing user keys if upload might be needed
      debugPrint('[EncryptionService] Fetching/loading server public key...');
      await fetchAndStoreServerPublicKey(EnvConfig.backendUrl);
      debugPrint('[EncryptionService] Server public key fetch/load complete.');
    } catch (e) {
      _keysInitialized = false;
      _identityKeyPair = null;
      _identitySeed = null;
      debugPrint('[EncryptionService] Error during key initialization: $e');
      // Decide if we should throw or handle gracefully
      // For now, rethrowing might be best to signal critical failure
      throw Exception('Failed to initialize cryptographic keys: $e');
    }

    debugPrint('[EncryptionService] initializeKeys finished.');
  }

  /// Imports an identity seed (e.g., from mnemonic/QR), stores it securely,
  /// and re-initializes the cryptographic keys based on this new seed.
  /// This will overwrite any existing seed and keys.
  Future<void> importIdentitySeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw ArgumentError('Imported seed must be 32 bytes long.');
    }
    debugPrint('[EncryptionService] Starting seed import process...');
    try {
      // 1. Store the new seed securely (hex encoded)
      final seedHex = hex.encode(seed);
      await _secureWrite(_seedStorageKey, seedHex);
      _identitySeed = seed; // Cache the imported seed
      debugPrint('[EncryptionService] Imported seed stored securely (hex).');

      // 2. Re-initialize the key pair from the newly stored seed
      final algorithm = crypto.Ed25519();
      _identityKeyPair = await algorithm.newKeyPairFromSeed(seed);
      _keysInitialized = true;
      _keysWereGeneratedDuringInit = false; // Keys were imported, not generated
      debugPrint('[EncryptionService] Key pair derived from imported seed.');

      // 3. Clear potentially cached/stored old public key (if applicable, e.g., PEM)
      // await _secureDelete(_userPublicKeyStorageKey); // If we had a PEM storage
      // _cachedUserPublicKeyPem = null;

      debugPrint(
          '[EncryptionService] Seed import successful. Keys re-initialized.');
    } catch (e) {
      debugPrint('[EncryptionService] Error during seed import: $e');
      // Clear potentially partially stored state
      _keysInitialized = false;
      _identityKeyPair = null;
      _identitySeed = null;
      await _secureDelete(_seedStorageKey);
      // await _secureDelete(_userPublicKeyStorageKey); // Clear PEM too if exists
      throw Exception('Failed to import identity seed: ${e.toString()}');
    }
  }

  /// Generates a new Ed25519 key pair and stores the seed.
  Future<void> _generateAndStoreDeviceSeedAndKeyPair() async {
    debugPrint(
        '[EncryptionService] Generating new Ed25519 seed and key pair...');
    try {
      // 1. Generate new 32-byte seed
      final algorithm = crypto.Ed25519();
      final newKeyPair = await algorithm.newKeyPair();
      // Extract the seed (private key bytes for Ed25519 serve as the seed)
      final newSeedBytes = await newKeyPair.extractPrivateKeyBytes();
      _identitySeed = Uint8List.fromList(newSeedBytes);
      _identityKeyPair = newKeyPair;
      debugPrint('[EncryptionService] New seed and key pair generated.');

      // 2. Store seed securely (hex encoded)
      final seedHex = hex.encode(_identitySeed!);
      await _secureWrite(_seedStorageKey, seedHex);
      debugPrint('[EncryptionService] Stored seed hex securely.');

      // 3. Mark initialized and set generation flag
      _keysInitialized = true;
      _keysWereGeneratedDuringInit = true;
      debugPrint(
          '[EncryptionService] Key generation complete. Initialized=true, Generated=true');
    } catch (e) {
      _keysInitialized = false;
      _identityKeyPair = null;
      _identitySeed = null;
      _keysWereGeneratedDuringInit = false;
      debugPrint(
          '[EncryptionService] Error in _generateAndStoreDeviceSeedAndKeyPair: $e');
      throw Exception('Failed to generate and store new seed and key pair: $e');
    }
  }

  /// Generates a mnemonic phrase from a 32-byte seed.
  String generateMnemonicFromSeed(Uint8List seed) {
    if (seed.length != 32) {
      throw ArgumentError('Seed must be 32 bytes long for BIP39 mnemonic.');
    }
    return bip39.entropyToMnemonic(hex.encode(seed));
  }

  /// Derives a 32-byte seed from a valid BIP39 mnemonic phrase.
  Uint8List getSeedFromMnemonic(String mnemonic) {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw ArgumentError('Invalid mnemonic phrase.');
    }
    final entropyHex = bip39.mnemonicToEntropy(mnemonic);
    return Uint8List.fromList(hex.decode(entropyHex));
  }

  /// Retrieves the stored identity seed if available.
  Future<Uint8List?> getIdentitySeed() async {
    if (_identitySeed != null) {
      return _identitySeed;
    }
    final seedHex = await _secureRead(_seedStorageKey);
    if (seedHex != null && seedHex.isNotEmpty && seedHex.length == 64) {
      try {
        _identitySeed = Uint8List.fromList(hex.decode(seedHex));
        return _identitySeed;
      } catch (e) {
        debugPrint(
            '[EncryptionService] Failed to decode stored seed hex in getIdentitySeed: $e');
        return null;
      }
    } else {
      if (seedHex != null && seedHex.isNotEmpty) {
        debugPrint('[EncryptionService] Stored seed hex has incorrect length.');
        // Optionally delete invalid seed
        // await _secureDelete(_seedStorageKey);
      }
    }
    return null;
  }

  // --- Public Key Methods (Ed25519) ---

  /// Returns the user's public key bytes (Ed25519).
  Future<crypto.SimplePublicKey> getUserPublicKey() async {
    if (!_keysInitialized || _identityKeyPair == null) {
      await initializeKeys();
      if (!_keysInitialized || _identityKeyPair == null) {
        throw StateError(
            'Keys are not initialized after attempt. Cannot get public key.');
      }
    }
    return await _identityKeyPair!.extractPublicKey();
  }

  /// Returns the user's public key in Base64 format (suitable for API).
  Future<String> getUserPublicKeyBase64() async {
    final publicKey = await getUserPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Signs data using the user's Ed25519 private key.
  Future<crypto.Signature> signData(Uint8List data) async {
    if (!_keysInitialized || _identityKeyPair == null) {
      await initializeKeys();
      if (!_keysInitialized || _identityKeyPair == null) {
        throw StateError('Keys not initialized. Cannot sign data.');
      }
    }
    final algorithm = crypto.Ed25519();
    return await algorithm.sign(data, keyPair: _identityKeyPair!);
  }

  // --- Server Key and Encryption (Using RSA for now for compatibility) ---

  Future<void> fetchAndStoreServerPublicKey(String baseUrl) async {
    final url = Uri.parse('$baseUrl/users/server-public-key');
    try {
      debugPrint('[EncryptionService] Fetching server public key from $url...');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final keyData = jsonDecode(response.body);
        final serverKeyPem = keyData['public_key'];
        if (serverKeyPem != null) {
          _serverPublicKey = parsePublicKeyFromPem(serverKeyPem);
          await _secureWrite(_serverPublicKeyStorageKey, serverKeyPem);
          debugPrint(
              '[EncryptionService] Server public key fetched and stored successfully.');
        } else {
          debugPrint(
              '[EncryptionService] Server public key not found in response.');
          throw Exception('Server public key not found in response.');
        }
      } else {
        debugPrint(
            '[EncryptionService] Failed to fetch server public key: ${response.statusCode} ${response.body}');
        throw Exception(
            'Failed to fetch server public key: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[EncryptionService] Error fetching server public key: $e');
      // Attempt to load from storage as fallback
      await _loadServerPublicKey();
    }
  }

  Future<void> _loadServerPublicKey() async {
    try {
      final serverKeyPem = await _secureRead(_serverPublicKeyStorageKey);
      if (serverKeyPem != null) {
        _serverPublicKey = parsePublicKeyFromPem(serverKeyPem);
        debugPrint(
            '[EncryptionService] Server public key loaded from storage.');
      } else {
        debugPrint(
            '[EncryptionService] No server public key found in storage.');
      }
    } catch (e) {
      debugPrint('[EncryptionService] Error loading server public key: $e');
    }
  }

  // --- Symmetric Key Derivation (Using X25519 for ECDH) ---

  /// Derives a shared secret using X25519 (requires converting Ed25519 keys).
  Future<crypto.SecretKey> calculateSharedSecret(
      crypto.SimplePublicKey theirPublicKeyEd25519) async {
    if (!_keysInitialized ||
        _identityKeyPair == null ||
        _identitySeed == null) {
      await initializeKeys();
      if (!_keysInitialized ||
          _identityKeyPair == null ||
          _identitySeed == null) {
        throw StateError(
            'Keys not initialized. Cannot calculate shared secret.');
      }
    }

    final x25519 = crypto.X25519();

    // 1. Convert our Ed25519 private key (seed) to an X25519 key pair
    final ourKeyPairX25519 = await x25519.newKeyPairFromSeed(_identitySeed!);

    // 2. Convert their Ed25519 public key to an X25519 public key
    // Note: This conversion is standard but relies on the cryptography library implementation
    final theirPublicKeyX25519 = crypto.SimplePublicKey(
        theirPublicKeyEd25519.bytes,
        type: crypto.KeyPairType.x25519);

    // 3. Calculate the shared secret using X25519 ECDH
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: ourKeyPairX25519, // Use the derived X25519 key pair
      remotePublicKey: theirPublicKeyX25519,
    );
    return sharedSecret;
  }

  // --- LEGACY RSA Encryption/Decryption (KEEP FOR SERVER INTERACTION IF NEEDED) ---

  /// Encrypts data using the server's public RSA key.
  Future<Uint8List> encryptForServer(Uint8List data) async {
    // Ensure _serverPublicKey is loaded
    if (_serverPublicKey == null) {
      await _loadServerPublicKey();
      if (_serverPublicKey == null) {
        // Try fetching if loading failed
        await fetchAndStoreServerPublicKey(EnvConfig.backendUrl);
        if (_serverPublicKey == null) {
          throw StateError('Server public key not loaded and fetch failed.');
        }
      }
    }
    try {
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(true, PublicKeyParameter<RSAPublicKey>(_serverPublicKey!));
      return cipher.process(data);
    } catch (e) {
      debugPrint('[EncryptionService] RSA encryption failed: $e');
      throw Exception('Failed to encrypt data for server: $e');
    }
  }

  // --- Symmetric Encryption/Decryption (Example using AES-GCM) ---
  // These methods would use a derived shared secret

  Future<Map<String, dynamic>> encryptSymmetric(
      String plainText, crypto.SecretKey sharedKey) async {
    final aesGcm = crypto.AesGcm.with256bits();
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: sharedKey,
      nonce: nonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
      'nonce': base64Encode(nonce),
    };
  }

  Future<String> decryptSymmetric(
      Map<String, dynamic> encryptedData, crypto.SecretKey sharedKey) async {
    final aesGcm = crypto.AesGcm.with256bits();
    final ciphertext = base64Decode(encryptedData['ciphertext']);
    final macBytes = base64Decode(encryptedData['mac']);
    final nonce = base64Decode(encryptedData['nonce']);

    final secretBox =
        crypto.SecretBox(ciphertext, nonce: nonce, mac: crypto.Mac(macBytes));

    final decryptedBytes = await aesGcm.decrypt(
      secretBox,
      secretKey: sharedKey,
    );
    return utf8.decode(decryptedBytes);
  }

  // Utility to parse PEM encoded public key (PKCS1)
  RSAPublicKey parsePublicKeyFromPem(String pem) {
    final parser = rsa_parser.RSAPKCSParser();
    final pair = parser.parsePEM(pem);
    if (pair.public == null) {
      throw const FormatException('Could not parse public key from PEM');
    }
    if (pair.public is! RSAPublicKey) {
      throw const FormatException('Parsed key is not an RSAPublicKey');
    }
    return pair.public as RSAPublicKey;
  }

  // Utility to encode public key to PEM format (PKCS1)
  String encodePublicKeyToPem(RSAPublicKey publicKey) {
    final algorithm = ASN1Sequence();
    final algorithmIdentifier =
        ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1');
    algorithm.add(algorithmIdentifier);
    algorithm.add(ASN1Null()); // Parameters

    final publicKeySequence = ASN1Sequence();
    publicKeySequence.add(ASN1Integer(publicKey.modulus!));
    publicKeySequence.add(ASN1Integer(publicKey.exponent!));
    final publicKeyBitString = ASN1BitString(publicKeySequence.encodedBytes);

    final topLevelSequence = ASN1Sequence();
    topLevelSequence.add(algorithm);
    topLevelSequence.add(publicKeyBitString);

    final dataBase64 = base64.encode(topLevelSequence.encodedBytes);
    return "-----BEGIN PUBLIC KEY-----\n${_formatBase64(dataBase64)}\n-----END PUBLIC KEY-----";
  }

  // Helper to format Base64 string with line breaks
  String _formatBase64(String base64) {
    const lineLength = 64;
    final chunks = <String>[];
    for (int i = 0; i < base64.length; i += lineLength) {
      chunks.add(base64.substring(i, min(i + lineLength, base64.length)));
    }
    return chunks.join('\n');
  }

  // Example utility to generate a secure random for PointyCastle
  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  // DEPRECATED: Decryption should happen server-side or via shared secrets.
  // Future<Uint8List> decryptWithPrivateKey(Uint8List encryptedData) async { ... }

  // --- END KEY INITIALIZATION ---

  // --- START Method Stubs for ChatService ---
  // TODO: Implement E2EE Decryption logic
  Future<String> decryptMessage(Map<String, String> encryptedData) async {
    debugPrint("[EncryptionService] decryptMessage called (NOT IMPLEMENTED)");
    // Placeholder implementation
    return Future.value(
        "[Decryption Placeholder: ${encryptedData['encrypted_content']?.substring(0, min(encryptedData['encrypted_content']?.length ?? 0, 10))}...]");
  }

  // TODO: Implement E2EE Encryption logic
  Future<Map<String, String>> encryptMessage(String plaintext) async {
    debugPrint("[EncryptionService] encryptMessage called (NOT IMPLEMENTED)");
    // Placeholder implementation - return map similar to backend expectation
    return Future.value({
      'encrypted_content':
          base64Encode(utf8.encode("[Encrypted Placeholder: $plaintext]")),
      'encrypted_key': 'placeholder_key',
      'iv': 'placeholder_iv',
      'tag': 'placeholder_tag'
    });
  }
  // --- END Method Stubs for ChatService ---

  // --- START Method Stub for Backup Upload ---
  // TODO: Implement backup upload to backend
  Future<void> uploadEncryptedSeedBackup(
      Map<String, dynamic> kdfParams, String encryptedSeedBase64) async {
    debugPrint(
        "[EncryptionService] uploadEncryptedSeedBackup called (NOT IMPLEMENTED)");
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    // Placeholder: In a real implementation, this would make an API call
    // using the _authService to get headers and send the data.
    debugPrint("  KDF Params: $kdfParams");
    debugPrint(
        "  Encrypted Seed (base64): ${encryptedSeedBase64.substring(0, min(encryptedSeedBase64.length, 20))}...");
    // Simulate success for now
    return Future.value();
  }
  // --- END Method Stub for Backup Upload ---
}
