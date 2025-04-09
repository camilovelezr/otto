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
  late AnimationController _panelAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  bool _isDebugInfoExpanded = false; // State for debug section expansion
  int? _hoveredIndex; // State to track hovered conversation index

  @override
  void initState() {
    super.initState();
    // Create dedicated controller for panel animations
    _panelAnimationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    
    // Create slide and opacity animations
    _slideAnimation = Tween<double>(
      begin: -0.3,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _panelAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _panelAnimationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void didUpdateWidget(SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Animate panel controller when isExpanded changes
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        _panelAnimationController.forward();
      } else {
        _panelAnimationController.reverse();
      }
    }
  }
  
  @override
  void dispose() {
    _panelAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = math.min(screenWidth * 0.85, 280.0); // Use math.min
    final chatProvider = context.watch<ChatProvider>(); // Watch ChatProvider for updates
    
    return AnimatedBuilder(
      animation: _panelAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(panelWidth * _slideAnimation.value, 0),
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.75) : Colors.white.withOpacity(0.75),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withOpacity(0.15 * _opacityAnimation.value),
                    blurRadius: 15 * _opacityAnimation.value,
                    offset: const Offset(2, 0),
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: (isDark 
                        ? Colors.black.withOpacity(0.65) 
                        : Colors.white.withOpacity(0.65)),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.1 * _opacityAnimation.value),
                          blurRadius: 30 * _opacityAnimation.value,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.08 * _opacityAnimation.value),
                          theme.colorScheme.secondary.withOpacity(0.08 * _opacityAnimation.value),
                        ],
                        stops: const [0.2, 0.8],
                      ),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.1 * _opacityAnimation.value),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(theme),
                        _buildNewConversationButton(theme, chatProvider), // Add New Conversation Button
                        const SizedBox(height: 16), // Increased spacing after button
                        // --- Conversation List (No explicit title) ---
                        Expanded(
                          child: _buildConversationList(theme, chatProvider), // Title row removed
                        ),
                        // --- End Conversation List ---
                        const Divider(height: 1, indent: 24, endIndent: 24),
                        _buildKeyManagementButtons(theme), // Add Key Management Buttons
                        const Divider(height: 1, indent: 24, endIndent: 24),
                        _buildDebugInfoSection(theme, chatProvider), // Add Debug Info Section
                        const Spacer(), // Pushes content below to the bottom
                        const Divider(height: 1, indent: 24, endIndent: 24),
                        _buildSignOutButton(theme), // Moved Sign Out Button
                        const SizedBox(height: 16), // Padding at the bottom
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- New Widget: Conversation List ---
  Widget _buildConversationList(ThemeData theme, ChatProvider chatProvider) {
    if (chatProvider.isLoadingConversations) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (chatProvider.conversationList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No conversations yet.\nStart chatting!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chatProvider.conversationList.length,
      itemBuilder: (context, index) {
        final conversation = chatProvider.conversationList[index];
        final isSelected = chatProvider.conversationId == conversation.id;
        final isHovered = _hoveredIndex == index;
        final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

        Widget? trailingWidget;
        if (isMobile) {
          // Always show menu on mobile
          trailingWidget = _buildConversationMenu(context, theme, chatProvider, conversation);
        } else if (isHovered) {
          // Show menu on hover for desktop/web
          trailingWidget = _buildConversationMenu(context, theme, chatProvider, conversation);
        }

        Widget listTile = ListTile(
              dense: true,
              title: Text(
              conversation.title ?? 'New Conversation',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: trailingWidget, // Use the determined trailing widget
            // subtitle: Text( // Optional: Show last updated time
            //   'Updated: ${conversation.updatedAt.toLocal()}',
            //   style: theme.textTheme.bodySmall?.copyWith(
            //     color: theme.colorScheme.onSurface.withOpacity(0.5),
            //   ),
            // ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            selected: isSelected,
            selectedTileColor: theme.colorScheme.primary.withOpacity(0.1),
            // Restore ListTile onTap
            onTap: () {
              if (!isSelected) {
                HapticFeedback.lightImpact();
                chatProvider.loadConversation(conversation.id);
                // Optionally close the panel on selection if desired
                // widget.onToggle();
              }
            },
          ); // ListTile close

        // Restore MouseRegion wrapper for non-mobile platforms
        if (isMobile) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: listTile,
          );
        } else {
          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = index),
            onExit: (_) => setState(() => _hoveredIndex = null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: listTile,
            ),
          );
        }
    }, // itemBuilder close
  ); // ListView.builder close
  }
  // --- End New Widget ---

  // --- New Widget: Conversation Item Menu ---
  Widget _buildConversationMenu(BuildContext context, ThemeData theme, ChatProvider chatProvider, ConversationSummary conversation) {
    // Use a local variable for context to avoid potential shadowing issues inside callbacks
    final BuildContext menuContext = context;
    // Create a GlobalKey to access the button's position
    final GlobalKey popupKey = GlobalKey();

    // Define the menu items builder function separately
    List<PopupMenuEntry<String>> itemBuilder(BuildContext context) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'rename',
        child: Text('Rename', style: theme.textTheme.bodyMedium),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        child: Text('Delete', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
      ),
    ];

    // Define the onSelected logic separately
    void handleSelection(String result) {
      debugPrint('[SidePanel] PopupMenuButton onSelected triggered with result: $result');
      switch (result) {
        case 'rename':
          debugPrint('[SidePanel] Rename selected for conversation: ${conversation.id}');
          _showRenameDialog(menuContext, chatProvider, conversation); // Use menuContext
          break;
        case 'delete':
          debugPrint('[SidePanel] Delete selected for conversation: ${conversation.id}');
          _showDeleteConfirmationDialog(menuContext, chatProvider, conversation); // Use menuContext
          break;
        default:
          debugPrint('[SidePanel] Unknown menu item selected: $result');
      }
    }

    // Wrap the Icon itself (the visible part of the button) in a GestureDetector
    return GestureDetector(
      key: popupKey, // Assign the key here
      behavior: HitTestBehavior.opaque, // Ensure it captures taps within its bounds
      child: Padding( // Add some padding to make the tap target slightly larger
        padding: const EdgeInsets.all(8.0), // Adjust padding as needed
        child: Icon(Icons.more_horiz, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.4)),
      ),
      onTap: () {
        debugPrint('[SidePanel] GestureDetector tapped for menu on conversation: ${conversation.id}');
        // Find the RenderBox of the GestureDetector
        final RenderBox renderBox = popupKey.currentContext!.findRenderObject() as RenderBox;
        // Get the position relative to the overlay
        final Offset offset = renderBox.localToGlobal(Offset.zero);
        // Show the menu manually
        showMenu<String>(
          context: menuContext,
          position: RelativeRect.fromLTRB(
            offset.dx, // Left
            offset.dy, // Top
            offset.dx + renderBox.size.width, // Right
            offset.dy + renderBox.size.height, // Bottom
          ),
          items: itemBuilder(menuContext), // Pass the items builder
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: theme.colorScheme.surface,
        ).then((String? result) {
          // Handle selection if a value is returned (user tapped an item)
          if (result != null) {
            handleSelection(result);
          } else {
             debugPrint('[SidePanel] Menu dismissed without selection.');
          }
        });
      },
    );

    /* // Original PopupMenuButton code (commented out)
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.4)),
      tooltip: 'Conversation Options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      enabled: true, // Explicitly enable the button
      onSelected: (String result) {
        // Add debug print here
        debugPrint('[SidePanel] PopupMenuButton onSelected triggered with result: $result');
        switch (result) {
          case 'rename':
             // Add debug print here
            debugPrint('[SidePanel] Rename selected for conversation: ${conversation.id}');
            _showRenameDialog(menuContext, chatProvider, conversation); // Use menuContext
            break;
          case 'delete':
             // Add debug print here
            debugPrint('[SidePanel] Delete selected for conversation: ${conversation.id}');
            _showDeleteConfirmationDialog(menuContext, chatProvider, conversation); // Use menuContext
            break;
          default:
             debugPrint('[SidePanel] Unknown menu item selected: $result');
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          child: Text('Rename', style: theme.textTheme.bodyMedium),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: theme.colorScheme.surface,
      elevation: 4,
    );
    */
  }
  // --- End New Widget ---

  // --- Placeholder for Delete Confirmation ---
  Future<void> _showDeleteConfirmationDialog(BuildContext context, ChatProvider chatProvider, ConversationSummary conversation) async {
     final theme = Theme.of(context);
     return showDialog<void>(
        context: context,
        barrierDismissible: false, // User must tap button!
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Delete Conversation?'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text('Are you sure you want to delete "${conversation.title ?? 'this conversation'}"?'),
                  const Text('This action cannot be undone.'),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
              TextButton(
                child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            onPressed: () async { // Make async
              Navigator.of(dialogContext).pop(); // Close dialog first
              try {
                await chatProvider.deleteConversation(conversation.id);
                HapticFeedback.mediumImpact();
              } catch (e) {
                // Show error if deletion fails
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete conversation: $e')),
                );
              }
                },
              ),
            ],
          );
        },
      );
  }
  // --- End Placeholder ---

  // --- New Widget: Rename Dialog ---
  Future<void> _showRenameDialog(BuildContext context, ChatProvider chatProvider, ConversationSummary conversation) async {
    final theme = Theme.of(context);
    final TextEditingController renameController = TextEditingController(text: conversation.title);
    final formKey = GlobalKey<FormState>(); // Add form key for validation

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename Conversation'),
          content: Form( // Wrap with Form
            key: formKey,
            child: TextFormField( // Use TextFormField for validation
              controller: renameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter new title'),
              validator: (value) { // Add validator
                if (value == null || value.trim().isEmpty) {
                  return 'Title cannot be empty';
                }
                return null;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Rename'),
              onPressed: () async { // Make async
                if (formKey.currentState!.validate()) { // Validate before proceeding
                  final newTitle = renameController.text.trim();
                  Navigator.of(dialogContext).pop(); // Close dialog first
                  try {
                    await chatProvider.renameConversation(conversation.id, newTitle);
                    HapticFeedback.lightImpact();
                  } catch (e) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Failed to rename conversation: $e')),
                     );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
  // --- End New Widget ---

  // --- New Widget: New Conversation Button ---
  Widget _buildNewConversationButton(ThemeData theme, ChatProvider chatProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('New Conversation'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size(double.infinity, 44), // Ensure consistent height
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          chatProvider.requestNewConversation(); // Use the new method
          
          // Call the onNewChat callback if provided
          if (widget.onNewChat != null) {
            widget.onNewChat!();
          }
        },
      ),
    );
  }
  // --- End New Widget ---

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        // Use MediaQuery for safe area but with minimum padding
        top: math.max(MediaQuery.of(context).padding.top, 16), // Use math.max
        bottom: 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Otto',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: theme.colorScheme.onBackground.withOpacity(0.9),
            ),
          ),
          const ThemeToggle(),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return MouseRegion(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _showSignOutConfirmation(context);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sign Out',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugInfoSection(ThemeData theme, ChatProvider chatProvider) {
    final isDark = theme.brightness == Brightness.dark;
    // Removed currencyFormat as cost info is removed

    // Determine API Status
    String apiStatus;
    Color statusColor;
    if (chatProvider.isLoadingModels) {
      apiStatus = 'Loading Models...';
      statusColor = theme.colorScheme.primary;
    } else if (chatProvider.error != null && chatProvider.error!.contains('Could not load models')) {
      apiStatus = 'Connection Error';
      statusColor = theme.colorScheme.error;
    } else if (chatProvider.error != null) {
      apiStatus = 'Error';
      statusColor = theme.colorScheme.error;
    } else if (chatProvider.availableModels.isEmpty) {
      apiStatus = 'No Models Found';
      statusColor = theme.colorScheme.error;
    }
     else {
      apiStatus = 'Connected';
      statusColor = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: ExpansionTile(
        key: const ValueKey('debugInfoExpansionTile'), // Add key for stability
        initiallyExpanded: _isDebugInfoExpanded,
        onExpansionChanged: (bool expanded) {
          setState(() {
            _isDebugInfoExpanded = expanded;
          });
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Remove default border
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Remove default border when collapsed
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          'Debug Information',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        trailing: Icon(
          _isDebugInfoExpanded ? Icons.expand_less : Icons.expand_more,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDebugInfoRow(theme, 'API Status:', apiStatus, valueColor: statusColor),
                const SizedBox(height: 8),
                _buildDebugInfoRow(theme, 'User ID:', chatProvider.currentUserId ?? 'N/A'),
                _buildDebugInfoRow(theme, 'Username:', chatProvider.currentUserName ?? 'N/A'),
                _buildDebugInfoRow(theme, 'Conversation ID:', chatProvider.conversationId ?? 'N/A'),
                const SizedBox(height: 8),
                _buildDebugInfoRow(theme, 'Input Tokens:', '${chatProvider.totalInputTokens}'),
                _buildDebugInfoRow(theme, 'Output Tokens:', '${chatProvider.totalOutputTokens}'),
                // Removed Total Cost row
                const SizedBox(height: 16),
                Center(
                  child: chatProvider.isLoadingModels
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                          ),
                        )
                      : TextButton.icon(
                          icon: Icon(Icons.sync_rounded, size: 18, color: theme.colorScheme.primary),
                          label: Text(
                            'Sync Models', // Changed label
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
                            ),
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.05),
                          ),
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            await chatProvider.refreshModels();
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugInfoRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor ?? theme.colorScheme.onSurface.withOpacity(0.8),
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showSignOutConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

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

  // --- New Widget for Key Management Buttons ---
  Widget _buildKeyManagementButtons(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Make buttons fill width
        children: [
          Text(
            'Account Security',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center, // Center the title
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Import Key (Scan QR)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.secondary,
              side: BorderSide(color: theme.colorScheme.secondary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ImportKeyScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('Export Key (Show QR)'),
             style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.secondary,
              side: BorderSide(color: theme.colorScheme.secondary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () {
               Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ExportKeyScreen()),
              );
            },
          ),
          // TODO: Add button for Recovery Phrase later
        ],
      ),
    );
  }
  // --- End New Widget ---
}
