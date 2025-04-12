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
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.inputBorder.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextSelectionTheme(
              data: TextSelectionThemeData(
                selectionColor: AppColors.selection,
                cursorColor: AppColors.primary,
                selectionHandleColor: AppColors.selectionHandle,
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && 
                      event.logicalKey == LogicalKeyboardKey.enter && 
                      !(HardwareKeyboard.instance.isShiftPressed)) {
                    _handleSubmit();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 6,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  keyboardType: TextInputType.multiline,
                  onChanged: (text) {
                    setState(() {});
                  },
                  onSubmitted: (text) => _handleSubmit(),
                  onEditingComplete: _handleSubmit,
                  onTapOutside: (event) => _focusNode.unfocus(),
                  autofocus: false,
                  cursorWidth: 2,
                  cursorRadius: const Radius.circular(2),
                  cursorHeight: 22,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 1.5,
                    letterSpacing: 0.15,
                    color: AppColors.onSurface,
                  ),
                  inputFormatters: [EnterKeyFormatter()],
                  decoration: InputDecoration(
                    hintText: 'Message Otto',
                    hintStyle: TextStyle(
                      color: AppColors.inputPlaceholder,
                      fontSize: 15,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16.0,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: widget.isLoading ? null : _handleSubmit,
            icon: widget.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary.withOpacity(0.8),
                      ),
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: AppColors.primary.withOpacity(0.8),
                    size: 20,
                  ),
            padding: const EdgeInsets.all(12),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
} 