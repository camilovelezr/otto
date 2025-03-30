import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import 'theme_toggle.dart';
import 'dart:math' as math; // Use math prefix
import '../services/auth_provider.dart';
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
  late AnimationController _clearButtonController;
  late Animation<double> _clearButtonAnimation;
  late AnimationController _panelAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  bool _isDebugInfoExpanded = false; // State for debug section expansion

  @override
  void initState() {
    super.initState();
    _clearButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _clearButtonAnimation = CurvedAnimation(
      parent: _clearButtonController,
      curve: Curves.easeOutCubic,
    );
    
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
    _clearButtonController.dispose();
    _panelAnimationController.dispose();
    super.dispose();
  }

  Future<void> _showClearConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
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
            'Clear All Messages',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to clear all messages? This action cannot be undone.',
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
              onPressed: () {
                context.read<ChatProvider>().clearChat();
                Navigator.of(context).pop();
                HapticFeedback.mediumImpact();
              },
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Clear All',
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

  Widget _buildClearButton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => _clearButtonController.forward(),
      onExit: (_) => _clearButtonController.reverse(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _showClearConfirmation(context);
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedBuilder(
              animation: _clearButtonAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Colors.transparent,
                      theme.colorScheme.error.withOpacity(0.1),
                      _clearButtonAnimation.value,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Color.lerp(
                          theme.colorScheme.error.withOpacity(0.5),
                          theme.colorScheme.error,
                          _clearButtonAnimation.value,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Clear Messages',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Color.lerp(
                            theme.colorScheme.error.withOpacity(0.5),
                            theme.colorScheme.error,
                            _clearButtonAnimation.value,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
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
                        _buildClearButton(theme),
                        _buildSignOutButton(theme),
                        _buildDebugInfoSection(theme, chatProvider), // Add Debug Info Section
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                // Add your side panel content here
                              ],
                            ),
                          ),
                        ),
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
}
