import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'dart:convert'; // For jsonDecode
import 'dart:math'; // Import for min function
import '../services/encryption_service.dart'; // Assuming EncryptionService is in services
import '../services/auth_provider.dart'; // To potentially trigger re-auth or state update

class ImportKeyScreen extends StatefulWidget {
  const ImportKeyScreen({Key? key}) : super(key: key);

  @override
  State<ImportKeyScreen> createState() => _ImportKeyScreenState();
}

class _ImportKeyScreenState extends State<ImportKeyScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    // Optional: Configure scanner settings like facing direction, formats
    // facing: CameraFacing.back,
    // formats: [BarcodeFormat.qrCode],
    // detectionSpeed: DetectionSpeed.normal, // or .noDuplicates
  );
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetection(BarcodeCapture capture) async {
    if (_isProcessing) return; // Prevent multiple simultaneous processing

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) {
      return; // No valid barcode detected
    }

    final String rawValue = barcodes.first.rawValue!;
    debugPrint('QR Code detected: ${rawValue.substring(0, min(rawValue.length, 100))}...'); // Log truncated value

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // 1. Decode the JSON data from the QR code
      final Map<String, dynamic> keyData = jsonDecode(rawValue);

      // 2. Validate the data structure (basic check)
      if (keyData['type'] != 'otto_e2ee_keypair' ||
          keyData['private_key_pem'] == null ||
          keyData['public_key_pem'] == null) {
        throw const FormatException("Invalid QR code format or missing key data.");
      }

      final String privateKeyPem = keyData['private_key_pem'];
      final String publicKeyPem = keyData['public_key_pem'];

      // 3. Load the keys using EncryptionService
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);
      // IMPORTANT: Importing keys here will overwrite any existing keys on this device.
      // Consider adding a confirmation dialog before proceeding.
      await encryptionService.importAndSaveKeysFromPem( // Use the new method
        privateKeyPem: privateKeyPem,
        publicKeyPem: publicKeyPem,
      );
      // No separate save needed, importAndSaveKeysFromPem handles it.

      // 5. Provide feedback and navigate back or to the main screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account keys imported successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      // Pop the screen after successful import
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }

    } on FormatException catch (e) {
       debugPrint('QR Code Format Error: $e');
       setState(() {
         _errorMessage = "Invalid QR Code: $e";
         _isProcessing = false;
       });
       _showErrorDialog("Invalid QR Code", "The scanned QR code does not contain valid key data. Please try again with the correct code.");
    } catch (e) {
      debugPrint('Error processing QR Code: $e');
      setState(() {
        _errorMessage = "Error importing keys: $e";
        _isProcessing = false;
      });
       _showErrorDialog("Import Failed", "An error occurred while importing the keys: $e");
    }
    // Add a small delay before allowing another scan attempt after error
    await Future.delayed(const Duration(seconds: 2));
     if (mounted) {
       setState(() { _isProcessing = false; });
     }
  }

  void _showErrorDialog(String title, String content) {
     if (!mounted) return;
     showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Account Key QR Code'),
        actions: [
          // IconButton for Torch - Using static icon
          IconButton(
            icon: const Icon(Icons.flash_on), // Static icon
            tooltip: 'Toggle Flash',
            onPressed: () => _scannerController.toggleTorch(),
          ),
          // IconButton for Camera Facing - Using static icon
          IconButton(
            icon: const Icon(Icons.cameraswitch), // Static icon
            tooltip: 'Switch Camera',
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcodeDetection,
            // Fit the scanner view to the parent container
            fit: BoxFit.cover,
            // You can customize the overlay here
            // overlay: QRScannerOverlay(overlayColour: Colors.black.withOpacity(0.5)),
          ),
          // Optional: Add a visual overlay or instructions
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.withOpacity(0.7), width: 4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Loading/Processing Indicator
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     CircularProgressIndicator(),
                     SizedBox(height: 16),
                     Text('Processing Key...', style: TextStyle(color: Colors.white)),
                   ]
                ),
              ),
            ),
        ],
      ),
    );
  }
}
