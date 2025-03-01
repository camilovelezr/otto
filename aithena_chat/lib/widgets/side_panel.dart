import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import 'theme_toggle.dart';
import 'dart:math';

class SidePanel extends StatefulWidget {
  final bool isExpanded;
  final Duration animationDuration;
  final VoidCallback onToggle;

  const SidePanel({
    Key? key,
    required this.isExpanded,
    required this.onToggle,
    this.animationDuration = const Duration(milliseconds: 250),
  }) : super(key: key);

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> with SingleTickerProviderStateMixin {
  late AnimationController _clearButtonController;
  late Animation<double> _clearButtonAnimation;

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
  }

  @override
  void dispose() {
    _clearButtonController.dispose();
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

    return AnimatedContainer(
      duration: widget.animationDuration,
      curve: Curves.easeOutExpo,
      width: widget.isExpanded ? 280 : 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark 
                ? Colors.black.withOpacity(0.65) 
                : Colors.white.withOpacity(0.65)),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 4),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.08),
                  theme.colorScheme.secondary.withOpacity(0.08),
                ],
                stops: const [0.2, 0.8],
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.1),
                width: 0.5,
              ),
            ),
            child: OverflowBox(
              maxWidth: 280,
              child: AnimatedOpacity(
                duration: widget.animationDuration,
                curve: Curves.easeOutExpo,
                opacity: widget.isExpanded ? 1.0 : 0.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(theme),
                    _buildClearButton(theme),
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
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        // Use MediaQuery for safe area but with minimum padding
        top: max(MediaQuery.of(context).padding.top, 16),
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
} 