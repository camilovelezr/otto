// Dart imports
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:developer' as developer; // Keep developer for potential future use
import 'package:flutter/foundation.dart'; // Import debugPrint

// Flutter packages
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Third-party packages
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:asn1lib/asn1lib.dart';
import 'package:rsa_pkcs/rsa_pkcs.dart' as rsa_parser;

// PointyCastle imports
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithRandom, AsymmetricKeyPair, PublicKey, PrivateKey, SecureRandom, CipherParameters, PrivateKeyParameter, PublicKeyParameter, AsymmetricBlockCipher, Digest;
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey, RSAPrivateKey;
import 'package:pointycastle/key_generators/api.dart' show RSAKeyGeneratorParameters;
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/digests/sha256.dart';

// Project imports
import '../config/env_config.dart'; // <-- Import EnvConfig

// Define storage keys again for local storage
const String _privateKeyStorageKey = 'device_private_key_pem';
const String _publicKeyStorageKey = 'device_public_key_pem';

// Storage key for server's public key
const String _serverPublicKeyStorageKey = 'server_public_key_pem';

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

  RSAPrivateKey? _privateKey;
  RSAPublicKey? _publicKey;
  bool _keysInitialized = false;

  // Cache for conversation symmetric keys
  final Map<String, encrypt_lib.Key> _conversationKeys = {};

  // Server's public key for encrypting messages
  RSAPublicKey? _serverPublicKey;

  // Constructor now calls initialization
  EncryptionService() {
    debugPrint('[EncryptionService] constructor called');
    initializeKeys();
  }

  Future<void> _secureWrite(String key, String value) async {
    try {
      if (_useMemoryStorage) {
        _memoryStorage[key] = value;
      } else {
        await _secureStorage.write(key: key, value: value);
      }
    } catch (e) {
      debugPrint('[EncryptionService] Error writing to secure storage, falling back to memory storage: $e');
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
      debugPrint('[EncryptionService] Error reading from secure storage, falling back to memory storage: $e');
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
      debugPrint('[EncryptionService] Error deleting from secure storage, falling back to memory storage: $e');
      _useMemoryStorage = true;
      _memoryStorage.remove(key);
    }
  }

  // --- Key Initialization (Load or Generate) ---

  /// Initializes keys by loading from secure storage or generating a new pair.
  Future<void> initializeKeys() async {
    debugPrint('[EncryptionService] initializeKeys called, current status: initialized=${_keysInitialized}, hasPrivateKey=${_privateKey != null}, hasPublicKey=${_publicKey != null}');
    
    if (_keysInitialized) {
      debugPrint('[EncryptionService] Keys already initialized, skipping');
      return;
    }

    String? finalPublicKeyPem; // To store the key PEM for logging

    try {
      debugPrint('[EncryptionService] Attempting to read keys from storage...');
      final privateKeyPem = await _secureRead(_privateKeyStorageKey);
      final publicKeyPem = await _secureRead(_publicKeyStorageKey);

      debugPrint('[EncryptionService] Storage read results - privateKey: ${privateKeyPem != null ? "present" : "missing"}, publicKey: ${publicKeyPem != null ? "present" : "missing"}');

      if (privateKeyPem != null && publicKeyPem != null) {
        debugPrint('[EncryptionService] Found existing keys in storage, attempting to parse...');
        try {
          _privateKey = _parsePrivateKeyFromPem(privateKeyPem);
          _publicKey = _parsePublicKeyFromPem(publicKeyPem);
          _keysInitialized = true;
          finalPublicKeyPem = publicKeyPem; // Store for logging
          debugPrint('[EncryptionService] Successfully loaded and parsed existing keys from storage');
        } catch (parseError) {
          debugPrint('[EncryptionService] Failed to parse stored keys: $parseError');
          // Clear invalid keys from storage
          await _secureDelete(_privateKeyStorageKey);
          await _secureDelete(_publicKeyStorageKey);
          throw parseError; // Rethrow to trigger key generation
        }
      } else {
        debugPrint('[EncryptionService] No existing keys found in storage, will generate new pair');
        throw Exception('No keys in storage'); // Trigger key generation
      }
    } catch (e) {
      debugPrint('[EncryptionService] Error during key initialization: $e, attempting key generation...');
      try {
        await _generateAndStoreDeviceKeyPair();
        finalPublicKeyPem = await getPublicKeyPem(); // Get the newly generated key PEM
        debugPrint('[EncryptionService] Successfully generated and stored new key pair');
      } catch (genError) {
        debugPrint('[EncryptionService] FATAL: Failed to generate new keys: $genError');
        _keysInitialized = false;
        _privateKey = null;
        _publicKey = null;
        throw Exception('Failed to generate encryption keys: $genError');
      }
    }

    // Log the final public key being used
    if (finalPublicKeyPem != null) {
       debugPrint('[EncryptionService] Using Public Key PEM: $finalPublicKeyPem');
    } else {
       debugPrint('[EncryptionService] WARNING: Could not determine final public key PEM.');
    }

    // Attempt to load the server key after initializing device keys
    try {
       await _loadServerPublicKey(); // Attempt to load/fetch server key
    } catch (e) {
       debugPrint('[EncryptionService] Error loading server key during initialization: $e');
       // Proceed, hoping fetch works later if needed (e.g., during encryptMessage)
    }
  }

  /// Ensures keys are initialized before use, generating if necessary.
  Future<void> _ensureKeysInitialized() async {
     if (!_keysInitialized || _privateKey == null || _publicKey == null) {
       debugPrint('[EncryptionService] Keys not initialized, attempting initialization/generation...');
       await initializeKeys(); // Try loading again or generate
       if (!_keysInitialized) { // Check again after attempt
         // Throw a more informative error if keys couldn't be loaded or generated
         throw Exception("Encryption keys are not available and could not be generated.");
       }
     }
  }

  // --- Key Generation and Management ---

  Future<void> _generateAndStoreDeviceKeyPair() async {
    debugPrint('[EncryptionService] Starting key pair generation...');
    try {
      debugPrint('[EncryptionService] Generating RSA key pair...');
      final keyPair = _generateRsaKeyPair();
      debugPrint('[EncryptionService] RSA key pair generated successfully');

      _privateKey = keyPair.privateKey as RSAPrivateKey;
      _publicKey = keyPair.publicKey as RSAPublicKey;

      debugPrint('[EncryptionService] Converting keys to PEM format...');
      final privateKeyPem = _encodePrivateKeyToPem(_privateKey!);
      final publicKeyPem = _encodePublicKeyToPem(_publicKey!);
      debugPrint('[EncryptionService] Keys converted to PEM format successfully');

      debugPrint('[EncryptionService] Storing keys in secure storage...');
      await _secureWrite(_privateKeyStorageKey, privateKeyPem);
      await _secureWrite(_publicKeyStorageKey, publicKeyPem);
      debugPrint('[EncryptionService] Keys stored successfully');

      _keysInitialized = true;
    } catch (e) {
      debugPrint('[EncryptionService] Error in _generateAndStoreDeviceKeyPair: $e');
      throw Exception('Failed to generate and store key pair: $e');
    }
  }

  // Helper function to create a secure random generator
  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seeds[i] = seedSource.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seeds));
    return secureRandom;
  }

  // RSA key pair generation utility - Corrected
  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair({int bitLength = 2048}) {
    debugPrint('[EncryptionService] Starting RSA key pair generation with bitLength=$bitLength');
    try {
      final secureRandom = _getSecureRandom();
      debugPrint('[EncryptionService] Secure random generator initialized');

      final params = RSAKeyGeneratorParameters(BigInt.parse('65537'), bitLength, 64);
      debugPrint('[EncryptionService] RSA parameters created');

      final paramsWithRandom = ParametersWithRandom<CipherParameters>(params as CipherParameters, secureRandom);
      debugPrint('[EncryptionService] Parameters with random created');

      final keyGen = RSAKeyGenerator();
      keyGen.init(paramsWithRandom);
      debugPrint('[EncryptionService] Key generator initialized');

      final keyPair = keyGen.generateKeyPair();
      debugPrint('[EncryptionService] Key pair generated successfully');

      return keyPair;
    } catch (e) {
      debugPrint('[EncryptionService] Error in _generateRsaKeyPair: $e');
      throw Exception('Failed to generate RSA key pair: $e');
    }
  }

  // --- Key Import (From QR Code / Recovery) ---

  /// Imports keys from PEM strings, saves them to secure storage (overwriting existing),
  /// and loads them into memory.
  Future<void> importAndSaveKeysFromPem({required String privateKeyPem, required String publicKeyPem}) async {
    debugPrint('[EncryptionService] Attempting to import and save keys from PEM...');
    try {
      // 1. Parse the keys first using rsa_pkcs to ensure they are valid before overwriting
      final parsedPrivateKey = _parsePrivateKeyFromPem(privateKeyPem);
      final parsedPublicKey = _parsePublicKeyFromPem(publicKeyPem);
      debugPrint('[EncryptionService] Provided PEM keys parsed successfully.');

      // 2. Write the validated PEM strings to secure storage
      await _secureWrite(_privateKeyStorageKey, privateKeyPem);
      await _secureWrite(_publicKeyStorageKey, publicKeyPem);
      debugPrint('[EncryptionService] Imported keys saved to secure storage.');

      // 3. Update the in-memory keys and status
      _privateKey = parsedPrivateKey;
      _publicKey = parsedPublicKey;
      _keysInitialized = true; // Mark as initialized with the new keys
      _conversationKeys.clear(); // Clear old conversation keys as they belong to the old key pair
      debugPrint('[EncryptionService] Imported keys loaded into memory.');

    } catch (e) {
      _keysInitialized = false; // Ensure flag is false on error during import
      _privateKey = null;
      _publicKey = null;
      debugPrint('[EncryptionService] Error importing and saving keys from PEM: $e');
      // Rethrow a more specific error for the UI
      if (e is FormatException || e.toString().contains('FormatException')) { // Check for FormatException
        throw Exception("Failed to parse imported keys: Invalid PEM format.");
      } else {
        throw Exception("Failed to import keys: $e");
      }
    }
  }


  // --- PEM Encoding/Decoding ---

  String _encodePublicKeyToPemPlaceholder(RSAPublicKey key) {
    debugPrint('[EncryptionService] Encoding public key to PEM format...');
    try {
      return _encodePublicKeyToPem(key);
    } catch (e) {
      debugPrint('[EncryptionService] Error encoding public key to PEM: $e');
      throw FormatException("Failed to encode public key to PEM: $e");
    }
  }

  String _encodePrivateKeyToPemPlaceholder(RSAPrivateKey key) {
    debugPrint('[EncryptionService] Encoding private key to PEM format...');
    try {
      return _encodePrivateKeyToPem(key);
    } catch (e) {
      debugPrint('[EncryptionService] Error encoding private key to PEM: $e');
      throw FormatException("Failed to encode private key to PEM: $e");
    }
  }

  // Helper method to convert BigInt to bytes
  Uint8List _bigIntToBytes(BigInt number) {
    // Handle negative numbers
    final negative = number.isNegative;
    if (negative) {
      number = -number;
    }

    // Convert to bytes
    var hexString = number.toRadixString(16);
    if (hexString.length % 2 != 0) {
      hexString = '0$hexString';
    }

    // Add leading zero byte for positive numbers to ensure correct ASN.1 encoding
    if (!negative && int.parse(hexString[0], radix: 16) >= 8) {
      hexString = '00$hexString';
    }

    var bytes = Uint8List((hexString.length + 1) ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final byteIndex = i * 2;
      if (byteIndex < hexString.length) {
        final hexByte = hexString.substring(
          byteIndex,
          min(byteIndex + 2, hexString.length),
        );
        bytes[i] = int.parse(hexByte, radix: 16);
      }
    }

    return bytes;
  }

  // Use rsa_pkcs for parsing
  RSAPublicKey _parsePublicKeyFromPem(String pem) {
    try {
      final parser = rsa_parser.RSAPKCSParser();
      final keyPair = parser.parsePEM(pem);
      if (keyPair.public == null) {
        throw const FormatException("PEM did not contain a public key.");
      }
      // Convert rsa_pkcs RSAPublicKey to PointyCastle RSAPublicKey
      final rsaPubKey = keyPair.public!;
      return RSAPublicKey(
        BigInt.parse(rsaPubKey.modulus.toString()),
        BigInt.parse(rsaPubKey.publicExponent.toString())
      );
    } catch (e) {
      debugPrint('[EncryptionService] Failed to parse Public Key PEM: $e');
      throw FormatException("Could not parse public key PEM: $e");
    }
  }

  RSAPrivateKey _parsePrivateKeyFromPem(String pem) {
    try {
      final parser = rsa_parser.RSAPKCSParser();
      final keyPair = parser.parsePEM(pem);
      if (keyPair.private == null) {
        throw const FormatException("PEM did not contain a private key.");
      }
      // Convert rsa_pkcs RSAPrivateKey to PointyCastle RSAPrivateKey
      final rsaPrivKey = keyPair.private!;
      return RSAPrivateKey(
        BigInt.parse(rsaPrivKey.modulus.toString()),
        BigInt.parse(rsaPrivKey.privateExponent.toString()),
        BigInt.parse(rsaPrivKey.prime1?.toString() ?? '0'),
        BigInt.parse(rsaPrivKey.prime2?.toString() ?? '0')
      );
    } catch (e) {
      debugPrint('[EncryptionService] Failed to parse Private Key PEM: $e');
      throw FormatException("Could not parse private key PEM: $e");
    }
  }


  // --- Symmetric Key Management ---

  Future<encrypt_lib.Key> getOrGenerateConversationKey(String conversationId) async {
     await _ensureKeysInitialized(); // Ensure RSA keys are ready if needed for exchange

    if (_conversationKeys.containsKey(conversationId)) {
      return _conversationKeys[conversationId]!;
    }

    // TODO: Implement secure key exchange with backend if key not found locally
    // For now, generate a new key (this needs refinement for multi-device sync)
    final newKey = encrypt_lib.Key.fromSecureRandom(32); // AES-256
    _conversationKeys[conversationId] = newKey;
    debugPrint('[EncryptionService] Generated new symmetric key for conversation $conversationId');
    return newKey;
  }

  // --- Encryption/Decryption ---

  Future<Map<String, String>> encryptMessage(String plainText) async {
    await _ensureKeysInitialized(); // Ensure keys are ready
    
    // First ensure we have the server's public key - this will throw if not available
    final serverKey = await _ensureServerPublicKey();

    try {
      // Generate a random AES key for this message
      final aesKey = encrypt_lib.Key.fromSecureRandom(32); // 256-bit AES key
      final iv = encrypt_lib.IV.fromSecureRandom(16);
      
      // Encrypt the message with AES key
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(aesKey, mode: encrypt_lib.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      
      // Get the authentication tag
      final tag = encrypted.bytes.sublist(encrypted.bytes.length - 16);
      final ciphertext = encrypted.bytes.sublist(0, encrypted.bytes.length - 16);
      
      // Encrypt the AES key with server's public key
      final encryptedKey = _encryptWithRSA(serverKey, aesKey.bytes);
      
      return {
        'encrypted_content': base64Encode(ciphertext),
        'encrypted_key': base64Encode(encryptedKey),
        'iv': base64Encode(iv.bytes),
        'tag': base64Encode(tag),
        'is_encrypted': 'true'
      };
    } catch (e) {
      debugPrint('[EncryptionService] Error encrypting message: $e');
      throw Exception('Failed to encrypt message: $e');
    }
  }

  Future<String> decryptMessage(Map<String, String> encryptedData) async {
    await _ensureKeysInitialized(); // Ensure keys are ready
    Uint8List ciphertext;
    Uint8List encryptedKey;
    Uint8List iv;
    Uint8List tag;

    // Keep minimal start log
    // debugPrint('[EncryptionService decryptMessage] Starting decryption...'); 
    // debugPrint('[EncryptionService decryptMessage] Received encryptedData keys: ${encryptedData.keys.join(', ')}'); // Removed

    try {
      if (_privateKey == null) throw Exception('Private key not available');
      // debugPrint('[EncryptionService decryptMessage] Private key is available.'); // Removed

      // Decode base64 components with error handling and null checks
      try {
        // debugPrint('[EncryptionService decryptMessage] Decoding base64 components...'); // Removed
        
        // Check and decode each component individually
        final contentB64 = encryptedData['content'];
        if (contentB64 == null) throw FormatException("Missing 'content' in encryptedData");
        ciphertext = base64Decode(contentB64);

        final encryptedKeyB64 = encryptedData['encrypted_key'];
        if (encryptedKeyB64 == null) throw FormatException("Missing 'encrypted_key' in encryptedData");
        encryptedKey = base64Decode(encryptedKeyB64);

        final ivB64 = encryptedData['iv'];
        if (ivB64 == null) throw FormatException("Missing 'iv' in encryptedData");
        iv = base64Decode(ivB64);

        final tagB64 = encryptedData['tag'];
        if (tagB64 == null) throw FormatException("Missing 'tag' in encryptedData");
        tag = base64Decode(tagB64);

        // debugPrint('[EncryptionService decryptMessage] Base64 decoding successful.'); // Removed
        // debugPrint('[EncryptionService decryptMessage] Decoded lengths - ciphertext: ${ciphertext.length}, encryptedKey: ${encryptedKey.length}, iv: ${iv.length}, tag: ${tag.length}'); // Removed
      } on FormatException catch (e) {
        // Keep detailed error logging
        debugPrint('[EncryptionService decryptMessage] Base64 decoding/check failed: $e'); 
        debugPrint('[EncryptionService decryptMessage] Received data map: $encryptedData'); 
        throw Exception('Failed to decode/validate base64 data: $e');
      }
      
      // Decrypt the AES key with our private key
      // debugPrint('[EncryptionService decryptMessage] Attempting RSA decryption of AES key...'); // Removed
      final aesKeyBytes = _decryptWithRSA(_privateKey!, encryptedKey);
      // debugPrint('[EncryptionService decryptMessage] RSA decryption successful. Decrypted AES key length: ${aesKeyBytes.length}'); // Removed
      final aesKey = encrypt_lib.Key(aesKeyBytes);
      
      // Combine ciphertext and tag
      // debugPrint('[EncryptionService decryptMessage] Combining ciphertext and tag...'); // Removed
      final fullCiphertext = Uint8List(ciphertext.length + tag.length)
        ..setAll(0, ciphertext)
        ..setAll(ciphertext.length, tag);
      
      // Decrypt the message with the AES key
      // debugPrint('[EncryptionService decryptMessage] Attempting AES-GCM decryption...'); // Removed
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(aesKey, mode: encrypt_lib.AESMode.gcm));
      String decrypted;
      try {
        decrypted = encrypter.decrypt(
          encrypt_lib.Encrypted(fullCiphertext),
          iv: encrypt_lib.IV(iv)
        );
        // Keep minimal success log
        // debugPrint('[EncryptionService decryptMessage] AES-GCM decryption successful.'); 
      } catch (aesError) {
         // Keep detailed error logging
         debugPrint('[EncryptionService decryptMessage] AES-GCM decryption FAILED: $aesError');
         throw Exception('AES-GCM decryption failed: $aesError');
      }
      
      return decrypted;
    } catch (e) {
      // Log the specific error type and message
      debugPrint('[EncryptionService decryptMessage] Decryption process FAILED: (${e.runtimeType}) $e'); 
      // Rethrowing the specific error might be more helpful than a generic message
      throw Exception('Failed to decrypt message: $e');
    }
  }

  // Helper method to encrypt with RSA
  Uint8List _encryptWithRSA(RSAPublicKey publicKey, Uint8List data) {
    try {
      // Use static method to ensure SHA256 is used for both digests
      final engine = OAEPEncoding.withSHA256(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey)); // true=encrypt
      
      return _processInBlocks(engine, data);
    } catch (e) {
      debugPrint('[EncryptionService] RSA encryption failed: $e');
      throw Exception('Failed to encrypt RSA data: $e');
    }
  }

  // Helper method to decrypt with RSA
  Uint8List _decryptWithRSA(RSAPrivateKey privateKey, Uint8List data) {
    try {
      // Use static method to ensure SHA256 is used for both digests
      final engine = OAEPEncoding.withSHA256(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey)); // false=decrypt
      
      return _processInBlocks(engine, data);
    } catch (e) {
      debugPrint('[EncryptionService] RSA decryption failed: $e');
      throw Exception('Failed to decrypt RSA data: $e');
    }
  }

  // Helper method to process data in blocks for RSA
  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List data) {
    try {
      return engine.process(data);
    } catch (e) {
      debugPrint('[EncryptionService] Error processing RSA data: $e');
      throw Exception('Failed to process RSA data: $e');
    }
  }

  // --- Public Key Access (For Export / QR Code) ---
  Future<String?> getPublicKeyPem() async {
    await _ensureKeysInitialized();
    if (_publicKey != null) {
      // Use placeholder encoding
      return _encodePublicKeyToPemPlaceholder(_publicKey!);
    }
    return null;
  }

  // --- Private Key / Recovery Phrase Access (For Export / QR Code) ---
  Future<String?> getPrivateKeyPemForExport() async {
     await _ensureKeysInitialized();
     if (_privateKey != null) {
       // IMPORTANT: This should ONLY be called when the user explicitly wants to export/sync.
       // Use placeholder encoding
       return _encodePrivateKeyToPemPlaceholder(_privateKey!);
     }
     return null;
  }

  // TODO: Implement Mnemonic (Seed Phrase) generation from private key entropy
  // Future<String> generateMnemonic() async { ... }

  // TODO: Implement key regeneration from Mnemonic
  // Future<void> loadKeysFromMnemonic(String mnemonic) async { ... }

  // TODO: Add methods for signing/verifying messages if needed for specific protocols

  // TODO: Implement secure conversation key exchange mechanism with the backend
  //       (e.g., using RSA public key to encrypt symmetric key for backend/other devices)

  String _encodePublicKeyToPem(RSAPublicKey publicKey) {
    debugPrint('[EncryptionService] Encoding public key to PEM format...');
    try {
      // Create ASN1 sequence for SubjectPublicKeyInfo structure
      var topLevelSeq = ASN1Sequence();
      
      // Add algorithm identifier sequence
      var algorithmSeq = ASN1Sequence();
      // RSA encryption OID: 1.2.840.113549.1.1.1
      algorithmSeq.add(ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]));
      algorithmSeq.add(ASN1Null()); // Parameters
      
      // Create the public key bit string
      var publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus!));
      publicKeySeq.add(ASN1Integer(publicKey.exponent!));
      
      // Add the algorithm sequence and public key bitstring to the top level sequence
      topLevelSeq.add(algorithmSeq);
      topLevelSeq.add(ASN1BitString(publicKeySeq.encodedBytes));
      
      // Encode the sequence
      var dataBase64 = base64.encode(topLevelSeq.encodedBytes);
      
      // Format as PEM with line wrapping
      var pem = '-----BEGIN PUBLIC KEY-----\n';
      for (var i = 0; i < dataBase64.length; i += 64) {
        pem += dataBase64.substring(i, min(i + 64, dataBase64.length)) + '\n';
      }
      pem += '-----END PUBLIC KEY-----';
      
      debugPrint('[EncryptionService] Successfully encoded public key to PEM');
      return pem;
    } catch (e) {
      debugPrint('[EncryptionService] Error encoding public key to PEM: $e');
      throw FormatException('Failed to encode public key to PEM: $e');
    }
  }

  String _encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    debugPrint('[EncryptionService] Encoding private key to PEM format...');
    try {
      // Create ASN1 sequence for PKCS#8 PrivateKeyInfo structure
      var topLevelSeq = ASN1Sequence();
      
      // Add version
      topLevelSeq.add(ASN1Integer(BigInt.from(0))); // Version 0
      
      // Add algorithm identifier sequence
      var algorithmSeq = ASN1Sequence();
      // RSA encryption OID: 1.2.840.113549.1.1.1
      algorithmSeq.add(ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]));
      algorithmSeq.add(ASN1Null()); // Parameters
      
      // Create the private key sequence (PKCS#1 RSAPrivateKey)
      var privateKeySeq = ASN1Sequence();
      privateKeySeq.add(ASN1Integer(BigInt.from(0))); // Version
      privateKeySeq.add(ASN1Integer(privateKey.modulus!));
      privateKeySeq.add(ASN1Integer(privateKey.publicExponent ?? BigInt.parse('65537')));
      privateKeySeq.add(ASN1Integer(privateKey.privateExponent!));
      privateKeySeq.add(ASN1Integer(privateKey.p ?? BigInt.zero));
      privateKeySeq.add(ASN1Integer(privateKey.q ?? BigInt.zero));
      // Add CRT components if available
      if (privateKey.p != null && privateKey.q != null) {
        var dp = privateKey.privateExponent! % (privateKey.p! - BigInt.one);
        var dq = privateKey.privateExponent! % (privateKey.q! - BigInt.one);
        var qInv = privateKey.q!.modInverse(privateKey.p!);
        privateKeySeq.add(ASN1Integer(dp));
        privateKeySeq.add(ASN1Integer(dq));
        privateKeySeq.add(ASN1Integer(qInv));
      }
      
      // Add algorithm and private key to top level sequence
      topLevelSeq.add(algorithmSeq);
      topLevelSeq.add(ASN1OctetString(privateKeySeq.encodedBytes));
      
      // Encode the sequence
      var dataBase64 = base64.encode(topLevelSeq.encodedBytes);
      
      // Format as PEM with line wrapping
      var pem = '-----BEGIN PRIVATE KEY-----\n';
      for (var i = 0; i < dataBase64.length; i += 64) {
        pem += dataBase64.substring(i, min(i + 64, dataBase64.length)) + '\n';
      }
      pem += '-----END PRIVATE KEY-----';
      
      debugPrint('[EncryptionService] Successfully encoded private key to PEM');
      return pem;
    } catch (e) {
      debugPrint('[EncryptionService] Error encoding private key to PEM: $e');
      throw FormatException('Failed to encode private key to PEM: $e');
    }
  }

  // --- RSA Decryption ---
  Future<Uint8List> decryptRSA(Uint8List encryptedData) async {
    await _ensureKeysInitialized();
    if (_privateKey == null) {
      throw Exception('Private key not available for RSA decryption');
    }

    try {
      // Create RSA engine with PKCS1 padding
      final engine = RSAEngine();
      final params = PrivateKeyParameter<RSAPrivateKey>(_privateKey!);
      engine.init(false, params);  // false for decryption

      // Process the data
      return _processInBlocks(engine, encryptedData);
    } catch (e) {
      debugPrint('[EncryptionService] RSA decryption failed: $e');
      throw Exception('Failed to decrypt RSA data: $e');
    }
  }

  // --- AES Decryption with Provided Key ---
  Future<String> decryptWithKey(Uint8List encryptedData, Uint8List key) async {
    try {
      // Extract IV (first 12 bytes) and tag (last 16 bytes)
      final iv = encryptedData.sublist(0, 12);
      final tag = encryptedData.sublist(encryptedData.length - 16);
      final ciphertext = encryptedData.sublist(12, encryptedData.length - 16);

      // Create AES-GCM cipher
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(
        encrypt_lib.Key(key),
        mode: encrypt_lib.AESMode.gcm,
      ));

      // Decrypt
      final decrypted = encrypter.decrypt(
        encrypt_lib.Encrypted(ciphertext),
        iv: encrypt_lib.IV(iv),
      );

      return decrypted;
    } catch (e) {
      debugPrint('[EncryptionService] AES decryption with key failed: $e');
      throw Exception('Failed to decrypt AES data: $e');
    }
  }

  // --- Server Public Key Management ---
  Future<void> fetchAndStoreServerPublicKey(String baseUrl) async {
    debugPrint('[EncryptionService] Fetching server public key...');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/server-public-key'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        debugPrint('[EncryptionService] Failed to fetch server public key: ${response.statusCode}');
        throw Exception('Failed to fetch server public key: ${response.statusCode} - ${response.body}');
      }

      final data = json.decode(response.body);
      if (!data.containsKey('public_key')) {
        debugPrint('[EncryptionService] Server response missing public key field');
        throw Exception('Server response missing public key field');
      }

      final publicKeyPem = data['public_key'] as String;
      
      // Validate the key format
      if (!publicKeyPem.contains('-----BEGIN PUBLIC KEY-----') || 
          !publicKeyPem.contains('-----END PUBLIC KEY-----')) {
        throw Exception('Invalid public key format: Missing PEM headers');
      }

      // Parse and validate the key
      try {
        _serverPublicKey = _parsePublicKeyFromPem(publicKeyPem);
        if (_serverPublicKey == null || 
            _serverPublicKey!.modulus == null || 
            _serverPublicKey!.exponent == null) {
          throw Exception('Invalid public key structure');
        }
      } catch (e) {
        debugPrint('[EncryptionService] Failed to parse server public key: $e');
        throw Exception('Invalid server public key format: $e');
      }

      // Store the validated key
      await _secureWrite(_serverPublicKeyStorageKey, publicKeyPem);
      debugPrint('[EncryptionService] Server public key fetched, validated, and stored successfully');
    } catch (e) {
      debugPrint('[EncryptionService] Error fetching server public key: $e');
      // Clear any potentially invalid stored key
      await _secureDelete(_serverPublicKeyStorageKey);
      _serverPublicKey = null;
      throw Exception('Failed to fetch and store server public key: $e');
    }
  }

  Future<void> _loadServerPublicKey() async {
    debugPrint('[EncryptionService] Loading server public key from storage...');
    try {
      final storedKey = await _secureRead(_serverPublicKeyStorageKey);
      if (storedKey != null) {
        try {
          _serverPublicKey = _parsePublicKeyFromPem(storedKey);
          // Validate the loaded key
          if (_serverPublicKey?.modulus == null || _serverPublicKey?.exponent == null) {
            throw Exception('Invalid stored public key format');
          }
          debugPrint('[EncryptionService] Server public key loaded from storage successfully');
        } catch (e) {
          debugPrint('[EncryptionService] Failed to parse stored server public key, will need to fetch again: $e');
          await _secureDelete(_serverPublicKeyStorageKey);
          _serverPublicKey = null;
        }
      } else {
        debugPrint('[EncryptionService] No server public key found in storage');
        // Attempt to fetch if not found in storage
        debugPrint('[EncryptionService] Attempting to fetch server public key as it was not found in storage...');
        // Assuming EnvConfig is available or passed appropriately
        await fetchAndStoreServerPublicKey(EnvConfig.backendUrl); 
      }
    } catch (e) {
      debugPrint('[EncryptionService] Error loading server public key: $e');
      await _secureDelete(_serverPublicKeyStorageKey);
      _serverPublicKey = null;
    }
  }

  // Helper method to ensure server public key is available
  Future<RSAPublicKey> _ensureServerPublicKey() async {
    if (_serverPublicKey == null) {
       debugPrint('[EncryptionService] Server public key is null, attempting to load/fetch...');
       await _loadServerPublicKey(); // Try loading/fetching
       if (_serverPublicKey == null) { // Check again after attempt
         throw Exception('Server public key not available and could not be fetched.');
       }
    }
    return _serverPublicKey!;
  }
}
