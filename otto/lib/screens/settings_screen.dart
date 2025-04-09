import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/chat_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isSavingName = false;
  bool _isSavingPassword = false;
  bool _isDeletingConversations = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers if needed, e.g., with current user name
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _nameController.text = authProvider.currentUser?.name ?? '';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  // --- Helper Methods for Actions ---

  Future<void> _updateName() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSavingName = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updateName(_nameController.text.trim());
    setState(() => _isSavingName = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Name updated successfully!' : 'Failed to update name: ${authProvider.error ?? 'Unknown error'}'),
          backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_currentPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Current password is required.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (_newPasswordController.text.isEmpty || _newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('New password must be at least 8 characters long.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSavingPassword = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updatePassword(
      _currentPasswordController.text,
      _newPasswordController.text,
    );
    setState(() => _isSavingPassword = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Password updated successfully!' : 'Failed to update password: ${authProvider.error ?? 'Unknown error'}'),
          backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
        ),
      );
      if (success) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
      }
    }
  }

  Future<void> _deleteAllConversations() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Conversations?'),
        content: const Text('This action cannot be undone. All your conversation history will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeletingConversations = true);
      final success = await chatProvider.deleteAllConversations();
      setState(() => _isDeletingConversations = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'All conversations deleted.' : 'Failed to delete conversations: ${chatProvider.error ?? 'Unknown error'}'),
            backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- User Settings Section ---
              Text('User Settings', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Username'),
                subtitle: Text(authProvider.currentUser?.username ?? 'N/A'),
              ),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: _isSavingName
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.save_outlined),
                          tooltip: 'Save Name',
                          onPressed: _isSavingName ? null : _updateName,
                        ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name cannot be empty';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentPasswordController,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  hintText: 'Enter your current password',
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Current password is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newPasswordController,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  hintText: 'Enter new password (min 8 chars)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: _isSavingPassword
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.save_outlined),
                          tooltip: 'Save Password',
                          onPressed: _isSavingPassword ? null : _updatePassword,
                        ),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'New password is required';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // --- Conversations Management Section ---
              Text('Conversations Management', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Total Conversations'),
                subtitle: Text('${chatProvider.conversationList.length}'),
              ),
              const SizedBox(height: 8),
              Center(
                child: _isDeletingConversations
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Delete All Conversations'),
                        onPressed: _isDeletingConversations ? null : _deleteAllConversations,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.errorContainer,
                          foregroundColor: theme.colorScheme.onErrorContainer,
                        ),
                      ),
              ),

              // --- Placeholder Sections (as requested) ---
              // const SizedBox(height: 24),
              // const Divider(),
              // const SizedBox(height: 16),
              // Text('Account Security', style: theme.textTheme.titleLarge),
              // const ListTile(
              //   leading: Icon(Icons.security_outlined),
              //   title: Text('Manage account security settings'),
              //   subtitle: Text('(Coming Soon)'),
              // ),

              // const SizedBox(height: 24),
              // const Divider(),
              // const SizedBox(height: 16),
              // Text('Debug Information', style: theme.textTheme.titleLarge),
              // const ListTile(
              //   leading: Icon(Icons.bug_report_outlined),
              //   title: Text('View debug info and test buttons'),
              //    subtitle: Text('(Coming Soon)'),
              // ),

              // const SizedBox(height: 24),
              // const Divider(),
              // const SizedBox(height: 16),
              // Text('Advanced Settings', style: theme.textTheme.titleLarge),
              // const ListTile(
              //   leading: Icon(Icons.settings_ethernet_outlined),
              //   title: Text('Change API Endpoint URL'),
              //   subtitle: Text('(Coming Soon - Requires App Restart)'),
              // ),

            ],
          ),
        ),
      ),
    );
  }
}
