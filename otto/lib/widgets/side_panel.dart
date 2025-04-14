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
  final bool isExpanded;
  final Duration animationDuration;
  final VoidCallback onToggle;
  final VoidCallback? onNewChat;

  const SidePanel({
    Key? key,
    required this.isExpanded,
    required this.onToggle,
    this.onNewChat,
    this.animationDuration = const Duration(milliseconds: 250),
  }) : super(key: key);

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  bool _isDebugInfoExpanded = false; // State for debug section expansion
  int? _hoveredIndex; // State to track hovered conversation index

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );
    
    _opacityAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = math.min(screenWidth * 0.8, 300.0);
    final chatProvider = context.watch<ChatProvider>();
    
    return SizedBox(
      width: screenWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              final slideValue = _slideAnimation.value;
              
              return Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset((slideValue - 1) * panelWidth, 0),
                  child: Container(
                    width: panelWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(2, 0),
                        ),
                      ],
                      border: Border(
                        right: BorderSide(color: colorScheme.outline.withOpacity(0.3), width: 1),
                      ),
                    ),
                    child: FadeTransition(
                      opacity: _opacityAnimation,
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(theme, panelWidth),
                            const SizedBox(height: AppSpacing.inlineSpacing),
                            _buildNewConversationButton(theme, chatProvider),
                            const SizedBox(height: AppSpacing.blockSpacing),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePaddingHorizontal / 2),
                              child: AnimatedSwitcher(
                                duration: Duration.zero,
                                child: _slideAnimation.value > 0.8
                                    ? Text(
                                        'Conversations',
                                        key: const ValueKey('conversations_text'),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          color: colorScheme.onSurface.withOpacity(0.6),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                      )
                                    : const SizedBox.shrink(key: ValueKey('empty_space')),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.inlineSpacingSmall),
                            Expanded(
                              child: FadeTransition(
                                opacity: _opacityAnimation,
                                child: _buildConversationList(theme, chatProvider),
                              ),
                            ),
                            const Divider(height: 1),
                            _buildFooter(theme),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, double panelWidth) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.inlineSpacing,
        right: AppSpacing.inlineSpacing,
        top: AppSpacing.inlineSpacing,
        bottom: 0,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: const Icon(Icons.close),
          iconSize: 20,
          tooltip: 'Close panel',
          onPressed: widget.onToggle,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
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
            widget.onNewChat?.call();
            if (!kIsWeb && MediaQuery.of(context).size.width < 600) {
              widget.onToggle();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.inlineSpacing),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 50) {
                return const Icon(Icons.add_circle_outline_rounded, size: 18);
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 18),
                  if (constraints.maxWidth >= 100) ...[
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
          padding: const EdgeInsets.all(AppSpacing.blockSpacing),
          child: Text(
            'No past conversations.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.inlineSpacingSmall),
      itemCount: chatProvider.conversationList.length,
      itemBuilder: (context, index) {
        final conversation = chatProvider.conversationList[index];
        final isSelected = chatProvider.conversationId == conversation.id;
        final isHovered = _hoveredIndex == index;
        final isMobile = !kIsWeb && (Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS);

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = index),
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        conversation.title ?? 'New Conversation',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.9),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isHovered || isMobile)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: _buildConversationMenu(context, theme, chatProvider, conversation),
                      ),
                  ],
                );
              },
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium)),
            selected: isSelected,
            selectedTileColor: theme.colorScheme.primary.withOpacity(0.15),
            hoverColor: theme.colorScheme.onSurface.withOpacity(0.05),
            onTap: () {
              if (!isSelected) {
                chatProvider.loadConversation(conversation.id);
                if (!kIsWeb && MediaQuery.of(context).size.width < 600) {
                  widget.onToggle();
                }
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildConversationMenu(BuildContext context, ThemeData theme, ChatProvider chatProvider, ConversationSummary conversation) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
      tooltip: 'Conversation options',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Text('Rename', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 13, color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
      onSelected: (String result) {
        switch (result) {
          case 'rename':
            _showRenameDialog(context, theme, chatProvider, conversation);
            break;
          case 'delete':
            _showDeleteConfirmationDialog(context, theme, chatProvider, conversation);
            break;
        }
      },
    );
  }

  void _showRenameDialog(BuildContext context, ThemeData theme, ChatProvider chatProvider, ConversationSummary conversation) {
    final TextEditingController renameController = TextEditingController(text: conversation.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: renameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter new title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final newTitle = renameController.text.trim();
              if (newTitle.isNotEmpty) {
                chatProvider.renameConversation(conversation.id, newTitle);
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLarge)),
         backgroundColor: theme.colorScheme.surface,
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, ThemeData theme, ChatProvider chatProvider, ConversationSummary conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text('Are you sure you want to delete "${conversation.title ?? 'this conversation'}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              chatProvider.deleteConversation(conversation.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLarge)),
        backgroundColor: theme.colorScheme.surface,
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final displayName = authProvider.currentUser?.name ?? authProvider.currentUser?.username ?? 'User';
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.inlineSpacingSmall,
        vertical: AppSpacing.inlineSpacing,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minWidthForLabels = 70.0; // Reuse or define a suitable width

          if (constraints.maxWidth < minWidthForLabels) {
            // Narrow layout: Column with icon-only buttons
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center, // Center items in narrow mode
              children: [
                // Simplified display name (optional, maybe just icon if super narrow?)
                Icon(Icons.account_circle, size: 24, color: colorScheme.primary), 
                const SizedBox(height: AppSpacing.inlineSpacingSmall),
                const SizedBox( // Ensure ThemeToggle gets its constrained space
                  width: 24, 
                  height: 24,
                  child: ThemeToggle(), // showLabel will be false here implicitly via LayoutBuilder
                ),
                const SizedBox(height: AppSpacing.inlineSpacingSmall),
                 // Icon Button for Sign Out
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    icon: const Icon(Icons.logout, size: 18),
                    tooltip: 'Sign Out',
                    onPressed: () => _showSignOutConfirmation(context, theme, authProvider),
                    color: colorScheme.onSurface.withOpacity(0.7),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24, maxWidth: 24, maxHeight: 24),
                  ),
                ),
              ],
            );
          } else {
             // Wider narrow layout: Original Column with labels
             return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, // Original alignment
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: AppSpacing.inlineSpacingSmall),
                  // ThemeToggle will decide internally if label fits
                  const ThemeToggle(showLabel: true), 
                  const SizedBox(height: AppSpacing.inlineSpacingSmall),
                  InkWell(
                    onTap: () => _showSignOutConfirmation(context, theme, authProvider),
                    borderRadius: BorderRadius.circular(4), // Add radius
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.logout,
                            size: 18,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          // Use Flexible just in case, though width check should prevent overflow
                          Flexible( 
                            child: Text(
                              'Sign Out',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis, // Add ellipsis
                              maxLines: 1,                      // Ensure single line
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
          }
        },
      ),
    );
  }

  Future<void> _showSignOutConfirmation(BuildContext context, ThemeData theme, AuthProvider authProvider) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await authProvider.logout();
              },
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: const Text('Sign Out'),
            ),
          ],
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLarge)),
           backgroundColor: theme.colorScheme.surface,
        );
      },
    );
  }
}
