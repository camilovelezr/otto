import 'package:flutter/material.dart';
// Removed flutter_highlight imports as GptMarkdown does not expose a codeBlockBuilder
// import 'package:flutter/services.dart'; // Needed for Clipboard (Removed as copy button is removed)
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:gpt_markdown/gpt_markdown.dart' show HighlightTheme; // Import the typedef
import 'package:otto/models/chat_message.dart' as model; // Use alias to avoid name clash
import 'package:otto/theme/app_colors.dart';
import 'package:otto/theme/app_spacing.dart';

class ChatMessageWidget extends StatelessWidget {
  final model.ChatMessage message; // Use the aliased model

  const ChatMessageWidget({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final bool isUserMessage = message.isUser; // Use the getter from the model

    // Get highlight theme based on current brightness
    final HighlightTheme codeHighlightTheme = isDarkMode ? atomOneDarkTheme : atomOneLightTheme;

    // Use ColorScheme for backgrounds
    final backgroundColor = isUserMessage
        ? theme.colorScheme.primaryContainer // Use primaryContainer for user
        : theme.colorScheme.surfaceVariant; // Use surfaceVariant for assistant

    // Use ColorScheme for text colors
    final textColor = isUserMessage
        ? theme.colorScheme.onPrimaryContainer // Use onPrimaryContainer for user
        : theme.colorScheme.onSurfaceVariant; // Use onSurfaceVariant for assistant

    final baseTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: textColor,
      height: 1.5,
      letterSpacing: 0.15,
    ) ?? TextStyle(color: textColor); // Fallback

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.verticalPaddingSmall), // Use AppSpacing
      child: Column(
        crossAxisAlignment: isUserMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.inlineSpacing * 2.5, // Use AppSpacing
              vertical: AppSpacing.inlineSpacing * 1.5, // Use AppSpacing
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppSpacing.borderRadiusMedium), // Use AppSpacing
                topRight: Radius.circular(AppSpacing.borderRadiusMedium),
                bottomLeft: Radius.circular(isUserMessage ? AppSpacing.borderRadiusMedium : AppSpacing.borderRadiusSmall / 2),
                bottomRight: Radius.circular(isUserMessage ? AppSpacing.borderRadiusSmall / 2 : AppSpacing.borderRadiusMedium),
              ),
              // Apply border consistently, but change color based on theme
              border: Border.all(
                color: isDarkMode 
                    ? Colors.transparent // Transparent border in dark mode
                    : theme.colorScheme.outline.withOpacity(0.5), // Visible border in light mode
                width: 0.5, // Consistent width
              ),
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GptMarkdown(
                    message.content ?? "[Content Unavailable]",
                    style: baseTextStyle,
                    highlightTheme: codeHighlightTheme,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
