import 'package:flutter/material.dart';
import 'theme_toggle.dart';

class SidePanel extends StatelessWidget {
  final bool isExpanded;
  final Duration animationDuration;

  const SidePanel({
    Key? key,
    required this.isExpanded,
    this.animationDuration = const Duration(milliseconds: 175), // 30% faster than 250ms
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: animationDuration,
      width: isExpanded ? 280 : 0,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.primary.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: OverflowBox(
        maxWidth: 280,
        child: AnimatedOpacity(
          duration: animationDuration,
          opacity: isExpanded ? 1.0 : 0.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Aithena Chat',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const ThemeToggle(),
                  ],
                ),
              ),
              Expanded(child: Container()),
            ],
          ),
        ),
      ),
    );
  }
} 