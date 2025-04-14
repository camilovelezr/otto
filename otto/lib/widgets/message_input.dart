import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';
import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle;

// Custom formatter to handle Enter key
class EnterKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove any standalone newline characters that aren't preceded by Shift
    if (newValue.text.endsWith('\n') && 
        !oldValue.text.endsWith('\n') &&
        newValue.text.length == oldValue.text.length + 1) {
      // If a newline was just added (and not from a paste operation)
      return oldValue;
    }
    return newValue;
  }
}

class MessageInput extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isLoading;
  final FocusNode? focusNode;

  const MessageInput({
    Key? key,
    required this.onSubmit,
    this.isLoading = false,
    this.focusNode,
  }) : super(key: key);

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    // Delay focus request to ensure proper initialization
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    debugPrint('Submitting message: ${text.substring(0, text.length > 20 ? 20 : text.length)}...');
    
    try {
      widget.onSubmit(text);
      // Clear the text field completely by replacing its value
      // This approach ensures a clean slate without any hidden newlines
      _controller.value = TextEditingValue.empty;
      
      // Make sure we have focus after sending
      _focusNode.requestFocus();
      debugPrint('Message submitted successfully');
    } catch (e) {
      debugPrint('Error sending message: $e');
      // Show a snackbar to inform the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // final isDarkMode = theme.brightness == Brightness.dark; // Not needed if using ColorScheme correctly

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.inlineSpacing * 1.5), // Use AppSpacing
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant, // Use themed surface variant
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusXLarge), // Use AppSpacing
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.5), // Use themed outline
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            // Apply TextSelectionTheme globally in MaterialApp or use TextField properties
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 6,
              minLines: 1,
              textInputAction: TextInputAction.newline, // Allow multiline input
              keyboardType: TextInputType.multiline,
              // No need for EnterKeyFormatter if textInputAction is newline
              // inputFormatters: [EnterKeyFormatter()], 
              onChanged: (text) {
                setState(() {});
              },
              onTapOutside: (event) => _focusNode.unfocus(),
              autofocus: false,
              cursorColor: colorScheme.primary, // Use themed cursor color
              cursorWidth: 1.5,
              cursorRadius: const Radius.circular(1),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                height: 1.5,
                letterSpacing: 0.15,
                color: colorScheme.onSurfaceVariant, // Use themed text color
              ),
              decoration: InputDecoration(
                hintText: 'Message Otto',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5), // Themed hint color
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14.0, // Adjust padding
                  horizontal: 4.0,
                ),
                isDense: true,
              ),
              // Handle Shift+Enter for newline, Enter for submit
              onSubmitted: (value) => _handleSubmit(), // Still allow submit on Enter from software keyboard
              onEditingComplete: () {}, // Prevent default behavior which might submit
            ),
          ),
          SizedBox(width: AppSpacing.inlineSpacingSmall), // Use AppSpacing
          IconButton(
            onPressed: widget.isLoading || _controller.text.trim().isEmpty ? null : _handleSubmit,
            icon: widget.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary.withOpacity(0.8), // Use themed primary color
                      ),
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: colorScheme.primary, // Use themed primary color
                    size: 20,
                  ),
            padding: const EdgeInsets.all(12),
            visualDensity: VisualDensity.compact,
            tooltip: 'Send message',
          ),
        ],
      ),
    );
  }
} 