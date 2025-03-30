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
    final alignment = isUserMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    // Determine the highlight theme based on dark mode
    final HighlightTheme codeHighlightTheme = isDarkMode ? atomOneDarkTheme : atomOneLightTheme;

    // Use existing AppColors, considering dark mode
    final color = isUserMessage 
        ? AppColors.primary // User message background
        : isDarkMode ? AppColors.surfaceDark : AppColors.surfaceVariant; // Assistant message background
    
    final textColor = isUserMessage 
        ? AppColors.onPrimary // User message text
        : isDarkMode ? AppColors.onSurfaceDark : AppColors.onSurface; // Assistant message text

    // Define a base text style for Markdown content
    final baseTextStyle = theme.textTheme.bodyMedium?.copyWith(color: textColor) ?? TextStyle(color: textColor);

    return Container(
      // Use existing AppSpacing values
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.listItemSpacing), 
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            // Use existing AppSpacing values
            padding: const EdgeInsets.all(AppSpacing.inlineSpacing), 
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75, // Limit message width
            ),
            decoration: BoxDecoration(
              color: color,
              // Use existing AppSpacing values
              borderRadius: BorderRadius.circular(AppSpacing.inlineSpacing), 
            ),
            child: SelectionArea( // Make the content selectable
              child: GptMarkdown(
                message.content,
                // Apply the base text style. GptMarkdown will handle specific element styling internally.
                style: baseTextStyle,
                // Removed codeBlockBuilder as it's not supported by GptMarkdown.
                // Code block styling is handled internally by the package.
                // You might be able to apply a general code style via the main 'style'
                // Pass the selected highlight theme
                highlightTheme: codeHighlightTheme,

                // You can customize other markdown elements further if needed
                // headingStyle: {
                //   1: baseTextStyle.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
                //   2: baseTextStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
                // },
                // codeStyle: baseTextStyle.copyWith(fontFamily: 'monospace', backgroundColor: Colors.grey.shade800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
