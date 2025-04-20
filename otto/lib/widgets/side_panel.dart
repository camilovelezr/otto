import 'dart:ui';
import 'package:flutter/foundation.dart'; // Import foundation for platform check
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import 'theme_toggle.dart';
import 'dart:math' as math; // Use math prefix
import '../services/auth_provider.dart';
import '../screens/export_key_screen.dart'; // Import export screen
import '../screens/import_key_screen.dart'; // Import import screen
import '../models/conversation_summary.dart'; // Import ConversationSummary
import '../theme/app_spacing.dart'; // Import AppSpacing
// Removed intl import as cost info is removed

class SidePanel extends StatefulWidget {
  final VoidCallback? onNewChat;

  const SidePanel({
    Key? key,
    this.onNewChat,
  }) : super(key: key);

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool _isDebugInfoExpanded = false; // State for debug section expansion
  int? _hoveredIndex; // State to track hovered conversation index

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
  }
  
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    
    return Container(
      color: colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.inlineSpacing),
            _buildNewConversationButton(theme, chatProvider),
            const SizedBox(height: AppSpacing.blockSpacing),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePaddingHorizontal / 2),
              child: Text(
                'Conversations',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
            const SizedBox(height: AppSpacing.inlineSpacingSmall),
            Expanded(
              child: _buildConversationList(theme, chatProvider),
            ),
            const Divider(height: 1),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildNewConversationButton(ThemeData theme, ChatProvider chatProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.inlineSpacing),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed: () {
            chatProvider.requestNewConversation();
            // Restore drawer pop
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.inlineSpacing),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'New Chat',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(ThemeData theme, ChatProvider chatProvider) {
    if (chatProvider.isLoadingConversations) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (chatProvider.conversationList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePaddingHorizontal),
          child: Text(
            'No conversations yet.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: chatProvider.conversationList.length,
      itemBuilder: (context, index) {
        final conversation = chatProvider.conversationList[index];
        final isSelected = chatProvider.conversationId == conversation.id;
        final isHovered = _hoveredIndex == index;

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = index),
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: Material(
            color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.4) : Colors.transparent,
            child: InkWell(
              onTap: () {
                chatProvider.loadConversation(conversation.id);
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePaddingHorizontal / 2,
                  vertical: AppSpacing.verticalPaddingSmall / 1.5,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        conversation.title ?? 'New Conversation',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isHovered || isSelected)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: theme.colorScheme.error.withOpacity(0.7),
                        tooltip: 'Delete Conversation',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmDeleteConversation(context, chatProvider, conversation),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Future<void> _confirmDeleteConversation(BuildContext context, ChatProvider chatProvider, ConversationSummary conversation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text('Are you sure you want to delete "${conversation.title ?? 'this conversation'}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await chatProvider.deleteConversation(conversation.id);

      if (mounted && chatProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete conversation: ${chatProvider.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        chatProvider.clearError();
      }
    }
  }

  Widget _buildFooter(ThemeData theme) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final displayName = authProvider.currentUser?.name ?? authProvider.currentUser?.username ?? 'User';
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.inlineSpacing),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(
                  authProvider.currentUser?.name.substring(0, 1).toUpperCase() ?? '?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.inlineSpacingSmall),
              Expanded(
                child: Text(
                  displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: AppSpacing.inlineSpacingSmall),
              const ThemeToggle(showLabel: true),
              const SizedBox(height: AppSpacing.inlineSpacingSmall),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  icon: const Icon(Icons.logout, size: 18),
                  tooltip: 'Sign Out',
                  onPressed: () {
                    if (Scaffold.of(context).isDrawerOpen) {
                      Navigator.of(context).pop();
                    }
                    _showSignOutConfirmation(context, theme, authProvider);
                  },
                  color: colorScheme.onSurface.withOpacity(0.7),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24, maxWidth: 24, maxHeight: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.inlineSpacingSmall),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Export Keys'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
                  textStyle: theme.textTheme.bodySmall,
                ),
                onPressed: () {
                  if (Scaffold.of(context).isDrawerOpen) {
                    Navigator.of(context).pop();
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ExportKeyScreen()),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Import Keys'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
                  textStyle: theme.textTheme.bodySmall,
                ),
                onPressed: () {
                  if (Scaffold.of(context).isDrawerOpen) {
                    Navigator.of(context).pop();
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ImportKeyScreen()),
                  );
                },
              ),
            ],
          ),
          if (kDebugMode) ...[
            const Divider(height: AppSpacing.blockSpacing),
            ExpansionTile(
              title: Text(
                'Debug Info',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _isDebugInfoExpanded,
              onExpansionChanged: (expanded) {
                setState(() => _isDebugInfoExpanded = expanded);
              },
              children: [
                _buildDebugInfoRow('Username:', authProvider.currentUser?.username ?? 'N/A'),
                _buildDebugInfoRow('Conv ID:', chatProvider.conversationId ?? 'None'),
                _buildDebugInfoRow('Messages:', chatProvider.messages.length.toString()),
                _buildDebugInfoRow('Loading Chat:', chatProvider.isLoading.toString()),
                _buildDebugInfoRow('Loading Conv List:', chatProvider.isLoadingConversations.toString()),
                _buildDebugInfoRow('Selected Model:', chatProvider.selectedModel?.modelId ?? 'None'),
                _buildDebugInfoRow('Available Models:', chatProvider.availableModels.length.toString()),
                _buildDebugInfoRow('Error:', chatProvider.error ?? 'None'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDebugInfoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ', 
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w500,
            )
          ),
          Expanded(
            child: SelectableText(
              value, 
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignOutConfirmation(BuildContext context, ThemeData theme, AuthProvider authProvider) async {
    final isDark = theme.brightness == Brightness.dark;

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark 
              ? Color.lerp(theme.colorScheme.surface, Colors.black, 0.3)
              : Color.lerp(theme.colorScheme.surface, Colors.white, 0.3),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Sign Out',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await authProvider.logout();
              },
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Sign Out',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
