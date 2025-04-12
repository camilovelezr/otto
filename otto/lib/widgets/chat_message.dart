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

    final HighlightTheme codeHighlightTheme = isDarkMode ? atomOneDarkTheme : atomOneLightTheme;

    final backgroundColor = isUserMessage
        ? isDarkMode ? AppColors.userMessageBg.withOpacity(0.3) : AppColors.userMessageBg.withOpacity(0.15)
        : isDarkMode ? AppColors.assistantMessageBg.withOpacity(0.3) : AppColors.assistantMessageBg.withOpacity(0.15);

    final textColor = isUserMessage
        ? isDarkMode ? AppColors.userMessage : AppColors.userMessage
        : isDarkMode ? AppColors.onSurfaceMedium : AppColors.onSurface;

    final baseTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: textColor,
      height: 1.5,
      letterSpacing: 0.15,
    ) ?? TextStyle(color: textColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: isUserMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isUserMessage ? 12 : 4),
                bottomRight: Radius.circular(isUserMessage ? 4 : 12),
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
