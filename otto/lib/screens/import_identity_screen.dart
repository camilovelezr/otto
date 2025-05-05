import 'package:flutter/material.dart';
import 'package:bip39/bip39.dart' as bip39; // For mnemonic validation
import 'package:provider/provider.dart';
import 'dart:typed_data'; // <-- Added for Uint8List

import '../services/encryption_service.dart';
import '../services/auth_provider.dart';
import '../services/auth_service.dart'; // <-- Added for AuthService and Exceptions
import 'qr_scanner_screen.dart'; // Import the scanner screen

class ImportIdentityScreen extends StatefulWidget {
  const ImportIdentityScreen({super.key});

  @override
  State<ImportIdentityScreen> createState() => _ImportIdentityScreenState();
}

class _ImportIdentityScreenState extends State<ImportIdentityScreen> {
  // Controllers for the 24 mnemonic words
  late List<TextEditingController> _mnemonicControllers;
  bool _isLoading = false; // Combined loading state (maybe separate later?)
  String? _errorMessage; // Combined error message (maybe separate later?)

  // --- Passphrase Import State ---
  final _usernameController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _isPassphraseLoading = false;
  String? _passphraseError;

  @override
  void initState() {
    super.initState();
    // Initialize 24 controllers
    _mnemonicControllers =
        List.generate(24, (_) => TextEditingController(), growable: false);
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var controller in _mnemonicControllers) {
      controller.dispose();
    }
    _usernameController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Identity'),
        // Add leading back button if needed, depends on navigation flow
        // leading: IconButton(
        //   icon: const Icon(Icons.arrow_back),
        //   onPressed: () => Navigator.of(context).pop(),
        // ),
      ),
      body: _buildBody(context), // Pass context
    );
  }

  // Helper to build section headers
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(
          top: 16.0, bottom: 8.0), // Add padding above header
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Use theme for consistent styling
    final theme = Theme.of(context);
    final secondaryTextColor = theme.textTheme.bodySmall?.color;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      children: [
        // --- Section 1: Import via Recovery Phrase ---
        _buildSectionHeader(context, 'Import via Recovery Phrase'),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the 24-word recovery phrase you saved previously.',
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
                const SizedBox(height: 16),
                // --- Mnemonic Input Grid ---
                GridView.builder(
                  shrinkWrap: true, // Important for ListView
                  physics:
                      const NeverScrollableScrollPhysics(), // Disable grid scrolling
                  itemCount: 24,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // 3 columns
                    childAspectRatio: 2.5 / 1, // Adjust aspect ratio as needed
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    return TextField(
                      controller: _mnemonicControllers[index],
                      decoration: InputDecoration(
                        labelText: '${index + 1}',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8), // Adjust padding
                      ),
                      style: const TextStyle(fontSize: 14), // Smaller font size
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      // TODO: Add validation / focus change logic?
                    );
                  },
                ),
                // --- End Mnemonic Input Grid ---
                const SizedBox(height: 12),
                // --- Display Error Message ---
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      _errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // --- End Error Message ---
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: _isLoading
                        ? Container(
                            width: 18,
                            height: 18,
                            padding: const EdgeInsets.all(2.0),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white, // Or theme color
                            ),
                          )
                        : const Icon(Icons.import_export),
                    label: Text(
                        _isLoading ? 'Importing...' : 'Import from Phrase'),
                    onPressed: _isLoading ? null : _importFromMnemonic,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // --- Section 2: Import via QR Code ---
        _buildSectionHeader(context, 'Import via QR Code'),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan the animated QR code displayed on your other device.',
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
                const SizedBox(height: 16),
                // Placeholder for QR scanner trigger
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Identity QR Code'),
                    onPressed: () {
                      _navigateToQrScanner();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // --- Section 3: Import via Passphrase Backup ---
        _buildSectionHeader(context, 'Import via Passphrase Backup'),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your username/ID and the passphrase you used to create the server-side backup.',
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
                const SizedBox(height: 16),
                // --- Username/ID Input ---
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username or User ID',
                    hintText: 'Enter your username or ID',
                    border: OutlineInputBorder(),
                    // prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enabled: !_isPassphraseLoading, // Disable when loading
                ),
                const SizedBox(height: 12),
                // --- Passphrase Input ---
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup Passphrase',
                    hintText: 'Enter your backup passphrase',
                    border: OutlineInputBorder(),
                    // prefixIcon: Icon(Icons.password_rounded),
                  ),
                  enabled: !_isPassphraseLoading, // Disable when loading
                ),
                const SizedBox(height: 16),
                // --- Passphrase Error Message ---
                if (_passphraseError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      _passphraseError!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // --- End Passphrase Error Message ---
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: _isPassphraseLoading
                        ? Container(
                            width: 18,
                            height: 18,
                            padding: const EdgeInsets.all(2.0),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white, // Or theme color
                            ),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                    label: Text(_isPassphraseLoading
                        ? 'Importing...'
                        : 'Import from Backup'),
                    onPressed:
                        _isPassphraseLoading ? null : _importFromPassphrase,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30), // Bottom padding
      ],
    );
  }

  // --- Import Logic ---
  Future<void> _importFromMnemonic() async {
    // Clear previous error
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final mnemonicPhrase = _mnemonicControllers
        .map((controller) => controller.text.trim().toLowerCase())
        .where((word) => word.isNotEmpty)
        .join(' ');

    if (mnemonicPhrase.split(' ').length != 24) {
      setState(() {
        _errorMessage = 'Please enter all 24 recovery words.';
        _isLoading = false;
      });
      return;
    }

    // 1. Validate mnemonic phrase
    if (!bip39.validateMnemonic(mnemonicPhrase)) {
      setState(() {
        _errorMessage =
            'Invalid recovery phrase. Please double-check the words.';
        _isLoading = false;
      });
      return;
    }

    try {
      final encryptionService = context.read<EncryptionService>();
      final authProvider = context.read<AuthProvider>();

      // 2. Derive seed from mnemonic
      debugPrint('[ImportIdentity] Deriving seed from mnemonic...');
      final seed = encryptionService.getSeedFromMnemonic(mnemonicPhrase);
      debugPrint('[ImportIdentity] Seed derived.');

      // 3. Store seed using the new import method
      debugPrint('[ImportIdentity] Importing and storing identity seed...');
      await encryptionService.importIdentitySeed(seed);
      debugPrint('[ImportIdentity] Seed imported and stored.');

      // 4. Notify AuthProvider about successful import
      // This will trigger AuthWrapper to rebuild and potentially navigate away
      debugPrint(
          '[ImportIdentity] Notifying AuthProvider of key import completion...');
      authProvider.completeKeyImport();
      debugPrint('[ImportIdentity] AuthProvider notified.');

      // If we reach here, import was successful
      // The AuthWrapper should handle navigation, but we can stop loading.
      // No need to call setState here as the AuthProvider change will rebuild.
      // Consider adding a success message if navigation doesn't happen immediately
      // setState(() { _isLoading = false; }); // Usually not needed if AuthWrapper handles it
    } catch (e) {
      debugPrint('[ImportIdentity] Error during mnemonic import: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error importing identity: ${e.toString()}';
        _isLoading = false;
      });
    }
    // Note: No final setState({_isLoading = false}) here because
    // successful import relies on AuthProvider state change triggering rebuild.
    // If the import fails, the catch block sets isLoading to false.
  }

  // --- Navigation to QR Scanner ---
  Future<void> _navigateToQrScanner() async {
    // Stop any ongoing mnemonic processing if user switches to QR
    if (_isLoading) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    }

    // Navigate and wait for result
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    // No need to explicitly handle success here, as the QrScannerScreen
    // calls authProvider.completeKeyImport() which triggers AuthWrapper
    // to navigate away automatically on success.
    // If result is null or false, it means the user backed out or scan failed/was cancelled.
    if (result == true) {
      debugPrint('[ImportIdentity] QR Scan successful (navigated back).');
      // AuthWrapper should handle the rest.
    } else {
      debugPrint('[ImportIdentity] QR Scan cancelled or failed.');
      // Optionally show a message if needed
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('QR Scan cancelled or failed.')),
      // );
    }
  }

  // --- Import via Passphrase ---
  Future<void> _importFromPassphrase() async {
    // Clear previous error and set loading
    setState(() {
      _passphraseError = null;
      _isPassphraseLoading = true;
      _errorMessage = null; // Clear other section's error
    });

    final username = _usernameController.text.trim();
    final passphrase = _passphraseController.text; // Keep original casing?

    if (username.isEmpty || passphrase.isEmpty) {
      setState(() {
        _passphraseError = 'Please enter both username/ID and passphrase.';
        _isPassphraseLoading = false;
      });
      return;
    }

    try {
      // 1. Get Services
      // Ensure these are provided higher up in the widget tree
      final authService = context.read<AuthService>();
      final encryptionService = context.read<EncryptionService>();
      final authProvider = context.read<AuthProvider>(); // No listen needed

      debugPrint(
          '[ImportIdentity] Calling downloadAndDecryptSeedBackup for $username');

      // 2. Call AuthService to download and decrypt
      // This assumes downloadAndDecryptSeedBackup throws specific exceptions on failure
      final Uint8List decryptedSeed =
          await authService.downloadAndDecryptSeedBackup(username, passphrase);
      debugPrint(
          '[ImportIdentity] Seed backup downloaded and decrypted successfully.');

      // 3. Import the decrypted seed
      setState(() {
        _passphraseError = 'Importing identity...';
      }); // Use error field for status temporarily
      await encryptionService.importIdentitySeed(decryptedSeed);
      debugPrint(
          '[ImportIdentity] Decrypted seed imported via EncryptionService.');

      // 4. Notify AuthProvider
      authProvider.completeKeyImport();
      debugPrint(
          '[ImportIdentity] AuthProvider notified of key import completion.');

      // Success! AuthWrapper will handle navigation.
      // No need for setState({_isPassphraseLoading = false}) here as AuthProvider change triggers rebuild.
      // We can clear the fields though.
      if (mounted) {
        debugPrint(
            '[ImportIdentity] Passphrase import successful. Clearing fields.');
        _usernameController.clear();
        _passphraseController.clear();
        // Optionally reset loading/error state here if navigation doesn't happen instantly
        // setState(() {
        //   _isPassphraseLoading = false;
        //   _passphraseError = null;
        // });
      }
    } on BackupNotFoundException catch (e) {
      debugPrint('[ImportIdentity] Passphrase import error: $e');
      if (mounted) {
        setState(() {
          _passphraseError = 'No backup found for this username.';
          _isPassphraseLoading = false;
        });
      }
    } on DecryptionFailedException catch (e) {
      debugPrint('[ImportIdentity] Passphrase import error: $e');
      if (mounted) {
        setState(() {
          _passphraseError = 'Decryption failed. Check your passphrase.';
          _isPassphraseLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ImportIdentity] Generic passphrase import error: $e');
      if (mounted) {
        setState(() {
          _passphraseError = 'An error occurred: ${e.toString()}';
          _isPassphraseLoading = false;
        });
      }
    }
    // No final setState here, handled by success navigation or error catches.
  }
}
