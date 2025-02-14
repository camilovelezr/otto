import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../services/chat_provider.dart';
import '../widgets/chat_message_widget.dart';
import '../widgets/model_selector.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';  // Add this import for ImageFilter
import 'dart:math';  // Add this import for min function

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isInputFocused = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _focusNode.addListener(() {
      setState(() {
        _isInputFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _loadModels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadModels();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSubmit(String text) {
    if (text.trim().isEmpty) return;

    _messageController.clear();
    context.read<ChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  void _handleKeyPress(RawKeyEvent event, TextEditingController controller) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter && event.isShiftPressed) {
        final text = controller.text;
        final selection = controller.selection;
        final newText = text.replaceRange(
          selection.start,
          selection.end,
          '\n',
        );
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: selection.start + 1,
          ),
        );
      }
    }
  }

  Widget _buildModelSelector(ChatProvider chatProvider, ThemeData theme) {
    if (chatProvider.isLoading) {
      return Row(
        children: [
          Expanded(
            child: ModelSelector(
              models: chatProvider.availableModels,
              selectedModel: chatProvider.selectedModel,
              onModelSelected: chatProvider.selectModel,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.1),
                  theme.colorScheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking...',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (chatProvider.error.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.error.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: ${chatProvider.error}',
              style: GoogleFonts.inter(
                color: theme.colorScheme.error,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadModels,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (chatProvider.availableModels.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No models available',
              style: GoogleFonts.inter(
                color: theme.colorScheme.secondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadModels,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ModelSelector(
      models: chatProvider.availableModels,
      selectedModel: chatProvider.selectedModel,
      onModelSelected: chatProvider.selectModel,
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.messages;

    if (chatProvider.isLoading) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isLastMessage = index == messages.length - 1;
                        final isStreaming = isLastMessage && chatProvider.isLoading;
                        
                        return ChatMessageWidget(
                          key: ValueKey(message.id),
                          message: message,
                          isStreaming: isStreaming,
                          streamedContent: chatProvider.currentStreamedResponse,
                        );
                      },
                    ),
            ),
            _buildInputArea(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                return _buildModelSelector(chatProvider, theme);
              },
            ),
          ),
          if (context.watch<ChatProvider>().messages.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: IconButton(
                icon: Icon(Icons.delete_outline, 
                  size: 18, 
                  color: theme.colorScheme.primary,
                ),
                onPressed: () => context.read<ChatProvider>().clearChat(),
                tooltip: 'Clear chat',
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.05),
            offset: const Offset(0, -1),
            blurRadius: 5,
          ),
        ],
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: _calculateInputHeight(),
        constraints: const BoxConstraints(
          minHeight: 56.0,
          maxHeight: 120.0,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isInputFocused 
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isInputFocused 
                  ? theme.colorScheme.primary.withOpacity(0.1)
                  : theme.colorScheme.primary.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RawKeyboardListener(
                  focusNode: FocusNode(),
                  onKey: (event) {
                    if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        final text = _messageController.text;
                        final selection = _messageController.selection;
                        final newText = text.replaceRange(
                          selection.start,
                          selection.end,
                          '\n',
                        );
                        _messageController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                            offset: selection.start + 1,
                          ),
                        );
                      } else {
                        final text = _messageController.text.trim();
                        if (text.isNotEmpty) {
                          _handleSubmit(text);
                        }
                      }
                    }
                  },
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: TextSelectionThemeData(
                        selectionColor: theme.colorScheme.primary.withOpacity(0.2),
                        cursorColor: theme.colorScheme.primary,
                        selectionHandleColor: theme.colorScheme.primary,
                      ),
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 6,
                          cursorWidth: 2,
                          cursorRadius: const Radius.circular(2),
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          onSubmitted: (text) {
                            if (text.trim().isNotEmpty) {
                              _handleSubmit(text);
                            }
                          },
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                              height: 1.5,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.transparent,
                          ),
                          onChanged: (text) {
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _messageController.text.trim().isNotEmpty
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _handleSubmit(_messageController.text),
                    child: Center(
                      child: Icon(
                        Icons.send_rounded,
                        size: 16,
                        color: _messageController.text.trim().isNotEmpty
                            ? Colors.white
                            : theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateInputHeight() {
    final text = _messageController.text;
    if (text.isEmpty) return 40.0;
    
    final lines = text.split('\n').length;
    return min(40.0 + (lines - 1) * 2.0, 120.0);
  }
} 