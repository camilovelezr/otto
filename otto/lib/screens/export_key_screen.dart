import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert'; // For jsonEncode
import '../services/encryption_service.dart'; // Assuming EncryptionService is in services

class ExportKeyScreen extends StatefulWidget {
  const ExportKeyScreen({Key? key}) : super(key: key);

  @override
  State<ExportKeyScreen> createState() => _ExportKeyScreenState();
}

class _ExportKeyScreenState extends State<ExportKeyScreen> {
  String? _keyDataJson;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadKeyData();
  }

  Future<void> _loadKeyData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);
      // Ensure keys are initialized before trying to export
      await encryptionService.initializeKeys();

      final privateKeyPem = await encryptionService.getPrivateKeyPemForExport();
      final publicKeyPem = await encryptionService.getPublicKeyPem(); // Get public key too

      if (privateKeyPem != null && publicKeyPem != null) {
        // Structure the data for the QR code
        final keyData = {
          'version': 1, // Add a version for future format changes
          'type': 'otto_e2ee_keypair',
          'private_key_pem': privateKeyPem,
          'public_key_pem': publicKeyPem, // Include public key for potential verification on import
        };
        setState(() {
          _keyDataJson = jsonEncode(keyData);
          _isLoading = false;
        });
      } else {
        throw Exception("Could not retrieve keys for export.");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = "Error loading keys: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Account Key'),
         elevation: 1,
       ),
       // Remove Center, allow Padding and SingleChildScrollView to manage scrolling
       body: Padding(
         padding: const EdgeInsets.all(24.0),
         child: _buildContent(),
        ),
      // Removed extra closing parenthesis here
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const CircularProgressIndicator();
    } else if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
          const SizedBox(height: 16),
          Text(
            'Failed to load key',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: _loadKeyData,
          ),
        ],
      );
    } else if (_keyDataJson != null) {
      // Wrap the Column in a Center within the SingleChildScrollView
      return SingleChildScrollView(
        child: Center( // Center the content vertically if space allows
          child: Column(
            // Keep mainAxisSize default (max)
            children: [
              Text(
                'Scan this QR code with your new device',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white, // Ensure white background for QR code
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: QrImageView(
                data: _keyDataJson!,
                version: QrVersions.auto, // Adjust version automatically
                size: 250.0, // Adjust size as needed
                gapless: false, // Keep gaps for better scanning
                errorStateBuilder: (cxt, err) {
                  return const Center(
                    child: Text(
                      'Uh oh! Something went wrong generating the QR code.',
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.warning_amber_rounded, size: 32),
            const SizedBox(height: 8),
            Text(
              'Treat this QR code like a password. Anyone who scans it can access your encrypted messages.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
       ),
      );
    } else {
      // Should not happen if no error and not loading
      return const Text('An unexpected error occurred.');
    }
  }
}
