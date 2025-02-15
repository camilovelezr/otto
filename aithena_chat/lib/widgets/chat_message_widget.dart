import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../theme/theme_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class ChatMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final bool isStreaming;
  final String streamedContent;

  const ChatMessageWidget({
    Key? key,
    required this.message,
    this.isStreaming = false,
    this.streamedContent = '',
  }) : super(key: key);

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  String _processedContent = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
    _updateProcessedContent();
  }

  @override
  void didUpdateWidget(ChatMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamedContent != widget.streamedContent ||
        oldWidget.message.content != widget.message.content) {
      _updateProcessedContent();
    }
  }

  Future<void> _updateProcessedContent() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final content = widget.isStreaming ? widget.streamedContent : widget.message.content;
      
      if (content.isEmpty) {
        setState(() {
          _processedContent = '';
          _isProcessing = false;
        });
        return;
      }

      // Skip processing for streaming content that contains JSON chunks
      if (widget.isStreaming && (content.trim().startsWith('{') || content.trim().startsWith('['))) {
        setState(() {
          _processedContent = content;
          _isProcessing = false;
        });
        return;
      }

      // Process content in a separate isolate to avoid UI blocking
      final processed = await compute<String, String>(_processContent, content);
      
      if (mounted) {
        setState(() {
          _processedContent = processed;
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('Error processing content: $e');
      // Fallback to raw content if processing fails
      if (mounted) {
        setState(() {
          _processedContent = widget.isStreaming ? widget.streamedContent : widget.message.content;
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildMessageContent(ThemeData theme) {
    final content = widget.isStreaming ? widget.streamedContent : widget.message.content;
    
    // For user messages, show as plain text
    if (widget.message.isUser) {
      return SelectableText(
        content,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.5,
        ),
      );
    }

    // For streaming JSON content, show as plain text
    if (widget.isStreaming && (content.trim().startsWith('{') || content.trim().startsWith('['))) {
      return SelectableText(
        content,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.5,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarkdownBody(
                data: _processedContent.isEmpty ? content : _processedContent,
                selectable: true,
                softLineBreak: true,
                fitContent: true,
                shrinkWrap: true,
                onTapLink: (_, href, __) {
                  debugPrint('Link tapped: $href');
                },
                builders: {
                  'code': CodeElementBuilder(
                    theme,
                    context,
                    maxWidth: constraints.maxWidth,
                  ),
                },
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.5,
                  ),
                  code: theme.textTheme.bodyMedium!.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                  ),
                  codeblockPadding: EdgeInsets.zero,
                  blockquote: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                    height: 1.5,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.5),
                        width: 4,
                      ),
                    ),
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  blockquotePadding: const EdgeInsets.all(16),
                  listBullet: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  textScaleFactor: MediaQuery.textScaleFactorOf(context),
                  textAlign: WrapAlignment.start,
                  h1: theme.textTheme.headlineMedium!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  h2: theme.textTheme.headlineSmall!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  h3: theme.textTheme.titleLarge!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  h4: theme.textTheme.titleMedium!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  h5: theme.textTheme.titleSmall!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  h6: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  em: const TextStyle(fontStyle: FontStyle.italic),
                  strong: const TextStyle(fontWeight: FontWeight.bold),
                  del: const TextStyle(decoration: TextDecoration.lineThrough),
                ),
                key: ValueKey('markdown-${widget.message.id}'),
              ),
              if (widget.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildTypingIndicator(theme),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isUser = widget.message.isUser;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                mainAxisAlignment:
                    isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser) _buildAvatar(theme),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isUser
                              ? [
                                  theme.colorScheme.primary.withOpacity(0.1),
                                  theme.colorScheme.secondary.withOpacity(0.1),
                                ]
                              : [
                                  theme.colorScheme.surface,
                                  theme.colorScheme.surface,
                                ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(isUser ? 20 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMessageContent(theme),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isUser) _buildAvatar(theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: widget.message.isUser
            ? context.read<ThemeProvider>().primaryGradient
            : context.read<ThemeProvider>().secondaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          widget.message.isUser
              ? Icons.person_rounded
              : Icons.smart_toy_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            gradient: context.read<ThemeProvider>().primaryGradient,
            borderRadius: BorderRadius.circular(4),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 600 + (index * 200)),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.5 + (value * 0.5),
                child: Container(),
              );
            },
          ),
        );
      }),
    );
  }
}

// Isolate-compatible content processor
String _processContent(String content) {
  final lines = content.split('\n');
  final processedLines = <String>[];
  bool insideCodeBlock = false;

  for (var line in lines) {
    if (line.startsWith('```')) {
      insideCodeBlock = !insideCodeBlock;
      processedLines.add(line);
    } else if (insideCodeBlock) {
      // Inside code block - preserve content exactly as is
      processedLines.add(line);
    } else {
      // Regular text - preserve as is
      processedLines.add(line);
    }
  }

  // Ensure code blocks are properly closed
  if (insideCodeBlock) {
    processedLines.add('```');
  }

  return processedLines.join('\n');
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  final BuildContext context;
  final double maxWidth;

  CodeElementBuilder(this.theme, this.context, {required this.maxWidth});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code' && element.tag != 'pre') return null;

    try {
      if (element.tag == 'pre') {
        // Get the code element (should be the first child of pre)
        final children = element.children;
        if (children == null || children.isEmpty) {
          debugPrint('Pre element has no children');
          return const SizedBox.shrink();
        }

        // Find the code element
        md.Element? codeElement;
        for (final child in children) {
          if (child is md.Element && child.tag == 'code') {
            codeElement = child;
            break;
          }
        }

        // Extract language and content
        String language = '';
        String codeContent = '';

        if (codeElement != null) {
          // Get language from class attribute
          final classAttr = codeElement.attributes?['class'] as String?;
          if (classAttr != null && classAttr.startsWith('language-')) {
            language = classAttr.substring(9);
          }

          // Get content safely
          codeContent = codeElement.textContent ?? '';
        } else {
          // Fallback to getting content from pre element
          codeContent = children.map((child) => child.textContent ?? '').join('\n');
        }

        codeContent = codeContent.trim();
        if (codeContent.isEmpty) {
          debugPrint('Empty code block content');
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (language.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        language.toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: codeContent));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied to clipboard'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    minWidth: maxWidth * 0.6,
                  ),
                  child: SelectableText(
                    codeContent,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (element.tag == 'code') {
        // Handle inline code
        final textContent = element.textContent?.trim();
        if (textContent == null || textContent.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            textContent,
            style: preferredStyle?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.primary,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error in CodeElementBuilder: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    return null;
  }
} 