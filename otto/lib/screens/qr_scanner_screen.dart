import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:cryptography/cryptography.dart' as crypto; // For HMAC
import 'package:convert/convert.dart'; // For hex
import 'package:bip39/bip39.dart' as bip39; // For mnemonic validation

import '../services/encryption_service.dart';
import '../services/auth_provider.dart';

// Screen that handles QR code scanning for identity import
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    // Facing back camera is usually preferred
    facing: CameraFacing.back,
    // Faster detection might be useful for animated QR
    // detectionSpeed: DetectionSpeed.normal,
    // detectionTimeoutMs: 500, // Optional timeout between detections
  );
  bool _isProcessing = false;
  String? _statusMessage;
  final Map<int, String> _receivedFrames =
      {}; // Stores frame content (words or checksum)
  String? _expectedChecksum;
  int _totalFrames = 3; // Expected number of frames
  bool _scanComplete = false; // Flag to stop processing after success/failure

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _processQrFrame(String data) {
    if (_isProcessing || _scanComplete) return; // Don't process if busy or done

    const prefix = 'otp-e2ee-seed:';
    if (!data.startsWith(prefix)) {
      setState(() {
        _statusMessage = 'Invalid QR code format (prefix mismatch)';
      });
      return;
    }

    final parts = data.substring(prefix.length).split(':');
    if (parts.length != 2) {
      setState(() {
        _statusMessage = 'Invalid QR code format (structure error)';
      });
      return;
    }

    final frameInfo = parts[0]; // e.g., "1/3"
    final frameData = parts[1]; // e.g., "word1 word2..." or "check:checksum"

    final frameParts = frameInfo.split('/');
    if (frameParts.length != 2) {
      setState(() {
        _statusMessage = 'Invalid QR code format (frame info error)';
      });
      return;
    }

    final frameNum = int.tryParse(frameParts[0]);
    final totalFrames = int.tryParse(frameParts[1]);

    if (frameNum == null ||
        totalFrames == null ||
        totalFrames != _totalFrames ||
        frameNum < 1 ||
        frameNum > _totalFrames) {
      setState(() {
        _statusMessage = 'Invalid QR code format (invalid frame number)';
      });
      return;
    }

    // Store frame data if not already received
    if (!_receivedFrames.containsKey(frameNum)) {
      if (frameNum == 3) {
        // Checksum frame
        if (!frameData.startsWith('check:')) {
          setState(() {
            _statusMessage = 'Invalid QR code format (checksum marker missing)';
          });
          return;
        }
        _expectedChecksum = frameData.substring('check:'.length);
        _receivedFrames[frameNum] = _expectedChecksum!; // Store checksum
        debugPrint('[QRScan] Received checksum frame: $_expectedChecksum');
      } else {
        // Mnemonic word frame
        _receivedFrames[frameNum] = frameData;
        debugPrint('[QRScan] Received frame $frameNum data.');
      }

      setState(() {
        _statusMessage = 'Frame $frameNum of $_totalFrames received...';
      });

      // Check if all frames are received
      if (_receivedFrames.length == _totalFrames) {
        debugPrint('[QRScan] All frames received. Starting validation...');
        _validateAndImport();
      }
    }
  }

  Future<void> _validateAndImport() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Validating data...';
    });

    // Ensure all parts are present (should be guaranteed by check above, but safety first)
    if (_receivedFrames[1] == null ||
        _receivedFrames[2] == null ||
        _expectedChecksum == null) {
      setState(() {
        _statusMessage = 'Error: Missing data frames or checksum.';
        _isProcessing = false;
        _scanComplete = true; // Stop further scanning
      });
      return;
    }

    // 1. Reconstruct Mnemonic
    final mnemonicPhrase = '${_receivedFrames[1]} ${_receivedFrames[2]}'.trim();
    final words = mnemonicPhrase.split(' ');
    if (words.length != 24) {
      setState(() {
        _statusMessage =
            'Error: Invalid mnemonic word count (${words.length}).';
        _isProcessing = false;
        _scanComplete = true;
      });
      return;
    }
    if (!bip39.validateMnemonic(mnemonicPhrase)) {
      setState(() {
        _statusMessage = 'Error: Invalid mnemonic phrase.';
        _isProcessing = false;
        _scanComplete = true;
      });
      return;
    }
    debugPrint('[QRScan] Mnemonic reconstructed and validated.');

    try {
      final encryptionService = context.read<EncryptionService>();
      final authProvider = context.read<AuthProvider>();

      // 2. Derive Seed
      setState(() {
        _statusMessage = 'Deriving identity seed...';
      });
      final seed = encryptionService.getSeedFromMnemonic(mnemonicPhrase);
      debugPrint('[QRScan] Seed derived from mnemonic.');

      // 3. Calculate Checksum
      setState(() {
        _statusMessage = 'Calculating checksum...';
      });
      final calculatedChecksumHex = await _calculateQrChecksum(seed);
      debugPrint('[QRScan] Calculated checksum: $calculatedChecksumHex');

      // 4. Compare Checksums
      if (calculatedChecksumHex != _expectedChecksum) {
        setState(() {
          _statusMessage =
              'Error: Checksum mismatch! QR data may be corrupted or invalid.';
          _isProcessing = false;
          _scanComplete = true;
        });
        _receivedFrames
            .clear(); // Clear frames on checksum mismatch to allow retry
        _expectedChecksum = null;
        setState(() {
          _scanComplete = false; // Allow retry scan
        });
        debugPrint(
            '[QRScan] Checksum mismatch. Expected: $_expectedChecksum, Got: $calculatedChecksumHex');
        return;
      }
      debugPrint('[QRScan] Checksum validation successful.');

      // 5. Import Seed and Notify AuthProvider
      setState(() {
        _statusMessage = 'Importing identity...';
      });
      await encryptionService.importIdentitySeed(seed);
      debugPrint('[QRScan] Seed imported successfully.');

      authProvider.completeKeyImport();
      debugPrint('[QRScan] AuthProvider notified.');

      setState(() {
        _statusMessage = 'Identity imported successfully!';
        _isProcessing = false;
        _scanComplete = true;
      });

      // Pop back to previous screen after a short delay
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop(true); // Indicate success
      }
    } catch (e) {
      debugPrint('[QRScan] Error during validation/import: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error importing identity: ${e.toString()}';
          _isProcessing = false;
          _scanComplete = true; // Stop on error
          _receivedFrames.clear(); // Clear frames on error to allow retry
          _expectedChecksum = null;
          _scanComplete = false; // Allow retry scan
        });
      }
    }
  }

  // Calculates the HMAC checksum for the QR code (matches ExportIdentityScreen)
  Future<String> _calculateQrChecksum(Uint8List seed) async {
    final hmacAlgo = crypto.Hmac(crypto.Sha256());
    final hkdfAlgo = crypto.Hkdf(hmac: hmacAlgo, outputLength: 32);

    // Use the exact same derivation parameters as in export
    final hmacKey = await hkdfAlgo.deriveKey(
      secretKey: crypto.SecretKey(seed),
      info: utf8.encode("otto-qr-checksum-key"),
    );

    final mac = await hmacAlgo.calculateMac(seed, secretKey: hmacKey);
    // Truncate to 8 bytes (16 hex chars) to match export
    return mac.bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Identity QR Code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isProcessing || _scanComplete)
                return; // Prevent multiple detections while processing/done

              final List<Barcode> barcodes = capture.barcodes;
              String? foundData;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null &&
                    barcode.rawValue!.startsWith('otp-e2ee-seed:')) {
                  foundData = barcode.rawValue;
                  break; // Process the first valid QR found
                }
              }
              if (foundData != null) {
                // Debounce or prevent rapid re-scanning of the same frame?
                // For now, _isProcessing flag handles blocking during validation.
                // If a frame is scanned again before validation starts, _receivedFrames check prevents redundant processing.
                _processQrFrame(foundData);
              }
            },
          ),
          // --- UI Overlay ---
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent overlay
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Optional: Add a viewfinder square
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.greenAccent, width: 2),
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(height: 20),
                  // Status Message Area
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30.0, vertical: 15.0),
                      child: Text(
                        _statusMessage!,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Loading Indicator
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  // Frames received indicator (optional visual)
                  Padding(
                    padding: const EdgeInsets.only(top: 15.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          _totalFrames,
                          (index) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5.0),
                                child: Icon(
                                  _receivedFrames.containsKey(index + 1)
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: _receivedFrames.containsKey(index + 1)
                                      ? Colors.greenAccent
                                      : Colors.white54,
                                ),
                              )),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
