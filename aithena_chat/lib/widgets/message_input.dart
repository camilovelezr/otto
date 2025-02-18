import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle;

class MessageInput extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isLoading;

  const MessageInput({
    Key? key,
    required this.onSubmit,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Delay focus request to ensure proper initialization
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    widget.onSubmit(text);
    _controller.clear();
    // Reset to single line after clearing
    setState(() {});
    
    // Delay focus request to ensure proper state update
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
        // Ensure the text field is empty and reset
        _controller.value = TextEditingValue.empty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextSelectionTheme(
              data: TextSelectionThemeData(
                selectionColor: theme.colorScheme.primary.withOpacity(0.2),
                cursorColor: theme.colorScheme.primary,
                selectionHandleColor: theme.colorScheme.primary,
              ),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    final bool isEnterPressed = event.logicalKey == LogicalKeyboardKey.enter;
                    final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

                    if (isEnterPressed && !isShiftPressed) {
                      _handleSubmit();
                    }
                  }
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 6,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _handleSubmit(),
                  onChanged: (text) {
                    // Only rebuild if text is not empty (avoid empty line height)
                    if (text.isNotEmpty) {
                      setState(() {});
                    }
                  },
                  onEditingComplete: () {
                    // Prevent default Enter behavior
                  },
                  keyboardType: TextInputType.multiline,
                  onTapOutside: (event) => _focusNode.unfocus(),
                  autofocus: false,
                  cursorWidth: 2.5,
                  cursorRadius: const Radius.circular(2),
                  cursorHeight: 20,
                  cursorColor: theme.colorScheme.primary.withOpacity(0.8),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                  ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    isDense: true,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                  showCursor: true,
                  mouseCursor: SystemMouseCursors.text,
                  enableInteractiveSelection: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
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
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.isLoading ? null : _handleSubmit,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
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