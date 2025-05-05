import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cryptography/cryptography.dart' as crypto; // For HMAC

import '../services/encryption_service.dart';
import '../services/auth_service.dart'; // Added for AuthService

class ExportIdentityScreen extends StatefulWidget {
  const ExportIdentityScreen({super.key});

  @override
  State<ExportIdentityScreen> createState() => _ExportIdentityScreenState();
}

class _ExportIdentityScreenState extends State<ExportIdentityScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _seed;
  String? _mnemonic;
  List<String> _qrFrames = [];
  int _currentQrFrameIndex = 0;
  Timer? _qrTimer;

  // --- Passphrase State ---
  final _passphraseController = TextEditingController();
  bool _isUploadingSeed = false;
  String? _uploadStatusMessage;
  bool _uploadSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSeedAndGenerateData();
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _passphraseController.dispose(); // Dispose controller
    super.dispose();
  }

  Future<void> _loadSeedAndGenerateData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final encryptionService = context.read<EncryptionService>();
      final seed = await encryptionService.getIdentitySeed();

      if (seed == null) {
        throw Exception("Could not retrieve identity seed.");
      }

      final mnemonic = encryptionService.generateMnemonicFromSeed(seed);
      final qrFrames =
          await _generateQrFrames(seed, mnemonic); // Pass seed for checksum

      if (!mounted) return; // Check if widget is still in the tree

      setState(() {
        _seed = seed;
        _mnemonic = mnemonic;
        _qrFrames = qrFrames;
        _isLoading = false;
      });

      _startQrAnimation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Error loading identity: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  // Generates QR frames including a checksum
  Future<List<String>> _generateQrFrames(
      Uint8List seed, String mnemonic) async {
    final words = mnemonic.split(' ');
    if (words.length != 24) {
      throw Exception("Invalid mnemonic word count");
    }

    // Frame 1: Words 1-12
    final frame1Data = "otp-e2ee-seed:1/3:${words.sublist(0, 12).join(' ')}";
    // Frame 2: Words 13-24
    final frame2Data = "otp-e2ee-seed:2/3:${words.sublist(12).join(' ')}";

    // Frame 3: Checksum (HMAC-SHA256 of the seed, truncated)
    try {
      final hmacAlgo = crypto.Hmac(crypto.Sha256());
      // final hkdfAlgo = crypto.Hkdf(hmac: hmacAlgo, outputLength: 32); // Removed HKDF

      // // Derive a key *from* the seed using HKDF // Removed HKDF
      // final derivedSecretKey = await hkdfAlgo.deriveKey(
      //   secretKey: crypto.SecretKey(seed), // Use the seed itself as the initial secret key for HKDF
      //   info: utf8.encode("otto-qr-checksum-key"),
      // );

      // // Extract the raw bytes from the derived key // Removed HKDF
      // final derivedKeyBytes = await derivedSecretKey.extractBytes();
      // // Create a new SecretKey instance from the bytes for the MAC calculation // Removed HKDF
      // final hmacKeyForMac = crypto.SecretKey(derivedKeyBytes);

      // Use the original seed directly as the HMAC key
      final hmacKey = crypto.SecretKey(seed);

      // Calculate the HMAC using the *seed* as the key
      final mac = await hmacAlgo.calculateMac(seed, secretKey: hmacKey);
      final checksumHex = mac.bytes
          .sublist(0, 8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join('');
      final frame3Data = "otp-e2ee-seed:3/3:check:$checksumHex";

      return [frame1Data, frame2Data, frame3Data];
    } catch (e) {
      debugPrint("Error generating QR checksum: $e");
      // Return frames without checksum if generation fails?
      // Or rethrow? Rethrowing for now.
      throw Exception("Failed to generate QR checksum frame: $e");
    }
  }

  void _startQrAnimation() {
    _qrTimer?.cancel(); // Cancel existing timer if any
    if (_qrFrames.length > 1) {
      _qrTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _currentQrFrameIndex = (_currentQrFrameIndex + 1) % _qrFrames.length;
        });
      });
    }
  }

  void _copyMnemonicToClipboard() {
    if (_mnemonic != null) {
      Clipboard.setData(ClipboardData(text: _mnemonic!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery Phrase copied to clipboard!')),
      );
    }
  }

  // Saves encrypted seed backup using passphrase
  Future<void> _saveEncryptedBackup() async {
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(() {
        _uploadStatusMessage = "Please enter a backup passphrase.";
        _uploadSuccess = false;
      });
      return;
    }
    if (_seed == null) {
      setState(() {
        _uploadStatusMessage = "Error: Identity seed is not available.";
        _uploadSuccess = false;
      });
      return;
    }

    setState(() {
      _isUploadingSeed = true;
      _uploadStatusMessage = "Encrypting seed...";
      _uploadSuccess = false;
    });

    try {
      // --- Argon2 Key Derivation ---
      final algorithm = crypto.Argon2id(
        parallelism: 1, // Adjust as needed
        memory: 65536, // 64 MB - Adjust as needed
        iterations: 2, // Adjust as needed
        hashLength: 32, // For AES-256 key
      );
      // Generate a random salt using dart:math Random.secure()
      final saltRandom = Random.secure();
      final salt = Uint8List.fromList(
          List<int>.generate(16, (i) => saltRandom.nextInt(256)));

      debugPrint(
          '[ExportIdentity] Deriving key from passphrase using Argon2id...');
      final derivedKey = await algorithm.deriveKeyFromPassword(
        password: passphrase, // Pass the String directly
        nonce: salt, // Use salt as nonce for Argon2
      );
      final aesEncryptionKey = await derivedKey.extract(); // Get SecretKeyData
      debugPrint('[ExportIdentity] AES key derived.');

      // --- AES Encryption ---
      setState(() {
        _uploadStatusMessage = "Encrypting seed...";
      }); // Update status
      final aesGcm = crypto.AesGcm.with256bits();
      final nonce = aesGcm.newNonce(); // Random nonce for encryption

      debugPrint('[ExportIdentity] Encrypting seed with AES-GCM...');
      final secretBox = await aesGcm.encrypt(
        _seed!,
        secretKey: aesEncryptionKey,
        nonce: nonce,
      );
      final encryptedSeedCiphertextBase64 =
          base64Encode(secretBox.concatenation());
      debugPrint(
          '[ExportIdentity] Seed encrypted. Ciphertext length (base64): ${encryptedSeedCiphertextBase64.length}');

      // --- Prepare Payload for Backend ---
      final argon2Params = {
        'type': 'argon2id', // Identify the algorithm
        'salt': base64Encode(salt),
        'iterations': algorithm.iterations,
        'memory': algorithm.memory,
        'parallelism': algorithm.parallelism,
        'hashLength': algorithm.hashLength, // Store the derived key length
        // Store nonce length and MAC length used by AES-GCM for decryption
        'nonceLength': nonce.length,
        'macLength': 16, // Standard AES-GCM MAC length
      };

      // --- Upload to Backend ---
      setState(() {
        _uploadStatusMessage = "Uploading backup...";
      });
      // Use Provider to get EncryptionService instead of AuthService
      final encryptionService = context.read<EncryptionService>();

      debugPrint(
          '[ExportIdentity] Calling encryptionService.uploadEncryptedSeedBackup...');
      // Call the method on EncryptionService
      await encryptionService.uploadEncryptedSeedBackup(
          argon2Params, encryptedSeedCiphertextBase64);

      // --- Success ---
      if (!mounted) return;
      setState(() {
        _uploadStatusMessage = "Encrypted backup saved successfully!";
        _uploadSuccess = true;
        _isUploadingSeed = false;
        _passphraseController.clear(); // Clear passphrase on success
      });
      debugPrint('[ExportIdentity] Backup upload successful.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadStatusMessage = "Failed to save backup: ${e.toString()}";
        _uploadSuccess = false;
        _isUploadingSeed = false;
      });
      debugPrint('[ExportIdentity] Backup upload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Identity'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Use theme colors
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    final primaryColor = theme.colorScheme.primary;
    final onPrimaryColor = theme.colorScheme.onPrimary;
    final secondaryTextColor = theme.textTheme.bodySmall?.color;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0), // Increased padding
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: errorColor, size: 48), // Error icon
              const SizedBox(height: 16),
              Text(
                'Error Loading Identity',
                style:
                    theme.textTheme.headlineSmall?.copyWith(color: errorColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(color: errorColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadSeedAndGenerateData,
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: onPrimaryColor), // Style button
              )
            ],
          ),
        ),
      );
    }
    if (_mnemonic == null || _qrFrames.isEmpty) {
      return const Center(child: Text('Could not load identity data.'));
    }

    final mnemonicWords = _mnemonic!.split(' ');

    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: 16.0, vertical: 24.0), // Adjusted padding
      children: [
        _buildSectionHeader('Identity QR Code'),
        const SizedBox(height: 8),
        Text(
          'Scan this animated QR code with another device during login to transfer your identity. Ensure the other device\'s scanner supports multi-frame codes.',
          style: TextStyle(
              fontSize: 14, color: secondaryTextColor), // Use theme color
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            // Add border/padding around QR
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              width: 250,
              height: 250,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_qrFrames.isNotEmpty &&
                        _currentQrFrameIndex < _qrFrames.length)
                    ? QrImageView(
                        key: ValueKey<int>(_currentQrFrameIndex),
                        data: _qrFrames[_currentQrFrameIndex],
                        version: QrVersions.auto,
                        gapless: false,
                        eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: primaryColor), // Style QR
                        dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: theme.colorScheme.onSurface), // Style QR
                        errorStateBuilder: (cxt, err) {
                          return const Center(
                              child: Text("QR Error.",
                                  textAlign: TextAlign.center));
                        },
                      )
                    : const Center(child: Text("Generating QR...")),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_qrFrames.isNotEmpty)
          Center(
              child: Text(
                  'Frame ${_currentQrFrameIndex + 1} of ${_qrFrames.length}',
                  style: theme.textTheme.bodySmall)), // Style frame text
        const SizedBox(height: 24),

        _buildSectionHeader('Recovery Phrase (Mnemonic)'),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)), // Rounded corners
          clipBehavior: Clip.antiAlias, // Clip content
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  // Icon and Warning Text
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: errorColor, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Store this phrase securely offline. Anyone with this phrase can access your account and encrypted messages. Do NOT share it or store it digitally insecurely.',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            height: 1.4), // Adjusted style
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mnemonicWords.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // Increased cross axis count
                    childAspectRatio: 4.0 / 1, // Adjusted ratio for compactness
                    crossAxisSpacing: 8, // Reduced spacing
                    mainAxisSpacing: 4, // Reduced spacing
                  ),
                  itemBuilder: (context, index) {
                    return SelectionArea(
                      child: Text(
                        '${index + 1}. ${mnemonicWords[index]}',
                        style: const TextStyle(
                            fontSize: 14, // Reduced font size
                            fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Full Phrase'),
                    onPressed: _copyMnemonicToClipboard,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _buildSectionHeader('Passphrase Backup (Fallback)'),
        const SizedBox(height: 8),
        Text(
          'Create an encrypted backup of your identity seed protected by a strong passphrase. This backup will be stored on the server, but only you can decrypt it with your passphrase.',
          style: TextStyle(fontSize: 14, color: secondaryTextColor),
        ),
        const SizedBox(height: 16),
        // --- Passphrase UI ---
        TextField(
          controller: _passphraseController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Create Backup Passphrase',
            hintText: 'Enter a strong passphrase',
            border: OutlineInputBorder(),
            // prefixIcon: Icon(Icons.password_rounded), // Optional icon
          ),
          enabled: !_isUploadingSeed,
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: _isUploadingSeed
              ? Container(
                  width: 18,
                  height: 18,
                  padding: const EdgeInsets.all(2.0),
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onPrimaryColor)) // Adjusted padding/color
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(_isUploadingSeed
              ? 'Saving Backup...'
              : 'Save Encrypted Backup to Server'),
          onPressed:
              (_isUploadingSeed || _seed == null) ? null : _saveEncryptedBackup,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: onPrimaryColor,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12), // Button padding
            textStyle: theme.textTheme.labelLarge, // Button text style
          ),
        ),
        // Display status message
        if (_uploadStatusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text(
              _uploadStatusMessage!,
              style: TextStyle(
                  color: _uploadSuccess ? Colors.green.shade600 : errorColor,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 30), // Bottom padding
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0), // Add padding below header
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
