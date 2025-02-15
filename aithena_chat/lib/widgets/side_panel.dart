import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme_toggle.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Text(
            'Aithena Chat',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: theme.colorScheme.onBackground.withOpacity(0.9),
            ),
          ),
          const Spacer(),
          const ThemeToggle(),
        ],
      ),
    );
  }
} 