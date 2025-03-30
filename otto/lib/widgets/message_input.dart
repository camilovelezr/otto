import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import '../theme/app_spacing.dart';
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
    final themeProvider = context.watch<ThemeProvider>();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.blockSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextSelectionTheme(
              data: TextSelectionThemeData(
                selectionColor: theme.colorScheme.primary.withOpacity(0.2),
                cursorColor: theme.colorScheme.primary,
                selectionHandleColor: theme.colorScheme.primary,
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
                  onSubmitted: (text) {
                    // This is triggered when the user presses Enter in single line mode
                    // or when TextInputAction.send is triggered
                    debugPrint('TextField onSubmitted triggered');
                    _handleSubmit();
                  },
                  onEditingComplete: () {
                    // This can help with handling Enter key on some platforms
                    _handleSubmit();
                  },
                  onTapOutside: (event) => _focusNode.unfocus(),
                  autofocus: false,
                  cursorWidth: 2.5,
                  cursorRadius: const Radius.circular(2),
                  cursorHeight: 20,
                  cursorColor: theme.colorScheme.primary.withOpacity(0.8),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.3,
                    fontSize: 16,
                  ),
                  // Simplified input formatters to avoid potential issues
                  inputFormatters: [
                    // This prevents standalone Enter keys from adding newlines
                    // but still allows Shift+Enter and pasted text with newlines
                    EnterKeyFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.inlineSpacing * 2,
                      vertical: 14.0,
                    ),
                    isDense: true,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    // Add alignment to improve text positioning
                    alignLabelWithHint: true,
                  ),
                  showCursor: true,
                  mouseCursor: SystemMouseCursors.text,
                  enableInteractiveSelection: true,
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.inlineSpacing * 0.8),
          GestureDetector(
            onTap: widget.isLoading ? null : _handleSubmit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    Color.lerp(
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                      0.3,
                    )!,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isLoading ? null : _handleSubmit,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: widget.isLoading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 