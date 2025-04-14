import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

class ThemeToggle extends StatelessWidget {
  final bool showLabel;
  
  const ThemeToggle({
    Key? key,
    this.showLabel = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Define a minimum width required to show the label comfortably
    const double minWidthForLabel = 70.0; 

    // Use LayoutBuilder to get constraints from the parent
    return LayoutBuilder(
      builder: (context, constraints) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            final icon = Icon(
              themeProvider.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              key: ValueKey(themeProvider.isDarkMode),
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            );

            // Decide whether to show the label based on the flag AND available width
            final bool shouldShowLabel = showLabel && constraints.maxWidth >= minWidthForLabel;

            if (!shouldShowLabel) { // Show only IconButton if showLabel is false OR width is too small
              return IconButton(
                onPressed: themeProvider.toggleTheme,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: icon,
                ),
                tooltip: themeProvider.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                  maxWidth: 24,
                  maxHeight: 24,
                ),
              );
            }
            
            // Otherwise, show the InkWell with the Row containing icon and label
            return InkWell(
              onTap: themeProvider.toggleTheme,
              borderRadius: BorderRadius.circular(4), // Add border radius for better ink splash
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        themeProvider.isDarkMode ? 'Dark Mode' : 'Light Mode',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
} 