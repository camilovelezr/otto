import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../theme/theme_provider.dart';
import 'package:flutter/rendering.dart' hide TextSelectionHandleType;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter/gestures.dart';
import 'dart:async';

extension ColorExtension on Color {
  Color darken([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  Color lighten([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  Color adjustSaturation([double amount = 0.1]) {
    assert(amount >= -1 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    return hsl.withSaturation((hsl.saturation + amount).clamp(0.0, 1.0)).toColor();
  }
}

/// This intent is used to copy the full message content.
class CopyAllIntent extends Intent {
  const CopyAllIntent();
}

/// Custom text selection controls that completely hide the cursor
class CursorlessSelectionControls extends MaterialTextSelectionControls {
  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    return super.buildToolbar(
      context,
      globalEditableRegion,
      textLineHeight,
      selectionMidpoint,
      endpoints,
      delegate,
      clipboardStatus,
      lastSecondaryTapDownPosition,
    );
  }
  
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textLineHeight, [VoidCallback? onTap]) {
    // We still want handles for selection
    return super.buildHandle(context, type, textLineHeight, onTap);
  }
  
  // Override this to ensure cursor is never drawn
  @override
  Widget buildCursor(BuildContext context, Rect cursorRect, TextSelectionDelegate delegate) {
    // Return an empty container instead of a cursor
    return Container();
  }
}

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
  bool _wasStreaming = false;
  bool _showStreamingCursor = false;
  bool _isWaitingForFirstToken = false;
  bool _showWaitingAnimation = false;

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

    _isWaitingForFirstToken = widget.isStreaming && widget.streamedContent.isEmpty;
    _showWaitingAnimation = _isWaitingForFirstToken;
    _showStreamingCursor = widget.isStreaming && !_isWaitingForFirstToken;
    _wasStreaming = widget.isStreaming;
    _animationController.forward();
  }
  
  @override
  void didUpdateWidget(ChatMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Only update state if there's an actual change to avoid unnecessary rebuilds
    final bool contentChanged = widget.streamedContent != oldWidget.streamedContent;
    final bool streamingChanged = widget.isStreaming != oldWidget.isStreaming;
    
    if (!contentChanged && !streamingChanged) {
      // If nothing important changed, skip the update
      return;
    }
    
    final newIsWaitingForFirstToken = widget.isStreaming && widget.streamedContent.isEmpty;
    if (_isWaitingForFirstToken != newIsWaitingForFirstToken) {
      final wasWaiting = _isWaitingForFirstToken;
      _isWaitingForFirstToken = newIsWaitingForFirstToken;
      
      // Transition from waiting to streaming with content
      if (wasWaiting && widget.isStreaming && widget.streamedContent.isNotEmpty) {
        // When we get the first token, show both animations briefly for a smooth transition
        setState(() {
          _showWaitingAnimation = true;
          _showStreamingCursor = true;
        });
        
        // Then fade out the waiting animation
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _showWaitingAnimation = false;
            });
          }
        });
      } else if (!wasWaiting && _isWaitingForFirstToken) {
        // Transition to waiting state
        setState(() {
          _showWaitingAnimation = true;
          _showStreamingCursor = false;
        });
      }
    }
    
    // Handle the streaming state change
    if (streamingChanged) {
      if (oldWidget.isStreaming && !widget.isStreaming) {
        // Keep showing the cursor briefly after streaming ends for a smoother transition
        // Use a shorter delay for faster disappearance
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            setState(() {
              _showStreamingCursor = false;
            });
          }
        });
      } else if (!oldWidget.isStreaming && widget.isStreaming && !_isWaitingForFirstToken) {
        setState(() {
          _showStreamingCursor = true;
        });
      }
    }
    
    _wasStreaming = widget.isStreaming;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Renders a code block with a header and highlighted content.
  Widget _buildCodeBlock(ThemeData theme, String code, String? language) {
    final isDark = theme.brightness == Brightness.dark;
    final headerBgColor =
        isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor =
        isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);

    return Material(
      color: contentBgColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: headerBgColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    language ?? 'plain text',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: isDark
                          ? const Color(0xFF9DA5B4)
                          : const Color(0xFF383A42),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        // Clean the code before copying.
                        final cleanCode = code
                            .replaceAll(RegExp(r'\r\n|\r'), '\n')
                            .replaceAll(RegExp(r'\n\s*\n'), '\n\n');
                        Clipboard.setData(ClipboardData(text: cleanCode));
                      },
                      child: Icon(
                        Icons.content_copy_rounded,
                        size: 18,
                        color: isDark
                            ? const Color(0xFF9DA5B4)
                            : const Color(0xFF383A42),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CodeContentWidget(
              code: code
                  .replaceAll(RegExp(r'\r\n|\r'), '\n')
                  .replaceAll(RegExp(r'\n\s*\n'), '\n\n'),
              language: language ?? 'plaintext',
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = widget.message.isUser;
    final isDark = theme.brightness == Brightness.dark;

    // If waiting for first token, show minimal loading indicator
    if (!isUser && _showWaitingAnimation && _isWaitingForFirstToken) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 24.0, top: 4.0, bottom: 4.0),
          child: WaitingForTokenAnimation(
            key: const ValueKey('waiting_animation'),
            isDark: isDark,
            theme: theme,
          ),
        ),
      );
    }

    // Helper function to create sophisticated dark mode gradients
    List<Color> createDarkModeGradient(Color surface) {
      final hsl = HSLColor.fromColor(surface);
      return [
        surface.darken(0.12).adjustSaturation(-0.08),
        surface.darken(0.10).adjustSaturation(-0.07),
        surface.darken(0.08).adjustSaturation(-0.06),
        surface.darken(0.06).adjustSaturation(-0.05),
        surface.darken(0.04).adjustSaturation(-0.04),
        surface.darken(0.02).adjustSaturation(-0.03),
        surface.adjustSaturation(-0.02),
        surface,
        surface.lighten(0.01).adjustSaturation(-0.01),
        surface.lighten(0.02).adjustSaturation(-0.02),
        surface.lighten(0.03).adjustSaturation(-0.03),
        surface.lighten(0.04).adjustSaturation(-0.04),
        surface.lighten(0.05).adjustSaturation(-0.05),
        surface.lighten(0.06).adjustSaturation(-0.06),
      ];
    }

    // Build the message content.
    Widget content = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // When tapped, unfocus to prevent cursor
                  FocusScope.of(context).unfocus();
                },
                // A single SelectableRegion at this level wraps all content
                child: SelectableRegion(
                  focusNode: AlwaysDisabledFocusNode(),
                  selectionControls: CursorlessSelectionControls(),
                  magnifierConfiguration: const TextMagnifierConfiguration(
                    shouldDisplayHandlesInMagnifier: true,
                  ),
                  onSelectionChanged: (selection) {
                    // This helps keep track of the current selection
                    if (selection != null) {
                      // Optional: Handle selection change if needed
                    }
                  },
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isUser
                                      ? [
                                          (isDark
                                              ? theme.colorScheme.primary
                                                  .withOpacity(0.25)
                                              : theme.colorScheme.primary
                                                  .withOpacity(0.1)),
                                          (isDark
                                              ? theme.colorScheme.secondary
                                                  .withOpacity(0.2)
                                              : theme.colorScheme.secondary
                                                  .withOpacity(0.1)),
                                        ]
                                      : isDark
                                          ? createDarkModeGradient(theme.colorScheme.surface)
                                          : [
                                              theme.colorScheme.surface,
                                              theme.colorScheme.surface.withOpacity(0.9),
                                            ],
                                  stops: isUser
                                      ? [0.0, 1.0]
                                      : isDark
                                          ? [0.0, 0.08, 0.16, 0.24, 0.32, 0.40, 0.48, 0.52, 0.60, 0.68, 0.76, 0.84, 0.92, 1.0]
                                          : [0.0, 1.0],
                                  tileMode: TileMode.clamp,
                                ),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                                  bottomRight: Radius.circular(isUser ? 4 : 20),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? Colors.black.withOpacity(0.2)
                                        : theme.shadowColor.withOpacity(0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                              child: RepaintBoundary(
                                child: Stack(
                                  children: [
                                    if (!isUser && isDark)
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(20),
                                            topRight: const Radius.circular(20),
                                            bottomLeft: Radius.circular(4),
                                            bottomRight: Radius.circular(20),
                                          ),
                                          child: CustomPaint(
                                            painter: NoisePainter(
                                              color: Colors.white,
                                              opacity: 0.01, // Reduced noise opacity
                                              density: 40, // Increased noise density
                                            ),
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Builder(
                                        builder: (context) {
                                          if (isUser) {
                                            // User messages just get simple text
                                            return Text(
                                              widget.message.content,
                                              style: theme.textTheme.bodyLarge!.copyWith(
                                                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                                                height: 1.5,
                                                shadows: isDark
                                                    ? [
                                                        const Shadow(
                                                          color: Colors.black26,
                                                          offset: Offset(0, 1),
                                                          blurRadius: 2,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                            );
                                          } else {
                                            // For assistant messages, we use our enhanced SelectableMarkdown
                                            String content = widget.isStreaming 
                                                ? widget.streamedContent 
                                                : widget.message.content;
                                                
                                            // Preprocess markdown content
                                            content = content.replaceAllMapped(
                                              RegExp(r'<[^>]+>'),
                                              (match) => '`${match.group(0)}`',
                                            );
                                            
                                            // Normalize line endings and reduce excessive empty lines
                                            content = content.replaceAll(RegExp(r'\r\n|\r'), '\n');
                                            content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');
                                            
                                            // Remove trailing whitespace from lines which can cause selection issues
                                            content = content.split('\n').map((line) => line.trimRight()).join('\n');
                                            
                                            return LayoutBuilder(
                                              builder: (context, constraints) {
                                                return Container(
                                                  constraints: BoxConstraints(
                                                    minHeight: 24.0,
                                                    maxWidth: constraints.maxWidth,
                                                  ),
                                                  child: SelectableMarkdown(
                                                    key: ValueKey('${widget.message.id}_md_${content.length}_${_showStreamingCursor}'),
                                                    data: content,
                                                    isDark: isDark,
                                                    isStreaming: _showStreamingCursor,
                                                    baseStyle: theme.textTheme.bodyLarge!.copyWith(
                                                      color: isDark ? Colors.white : theme.colorScheme.onSurface,
                                                      height: 1.5,
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          }
                                        }
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isUser && !widget.isStreaming)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Tooltip(
                            message: 'Copy entire message',
                            child: IconButton(
                              icon: const Icon(
                                Icons.content_copy_rounded,
                                size: 20,
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: widget.message.content));
                                // Show a toast notification instead of a snackbar
                                _showFloatingToast(context, 'Message copied to clipboard');
                              },
                              tooltip: 'Copy message',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: theme.colorScheme.onSurface,
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(32, 32),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return content;
  }

  // Helper method to show a floating toast notification that doesn't interfere with the input bar
  void _showFloatingToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    
    // Position it at the top center of the screen
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.1, // 10% from the top
        left: (MediaQuery.of(context).size.width - 200) / 2, // Centered
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[800] 
                : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
    });
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  final BuildContext context;
  final Function(String, String?, bool)? customBuilder;

  CodeElementBuilder(this.theme, this.context, {this.customBuilder});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      String lg = element.attributes['class'] as String;
      language = lg.substring(9);
    }
    final isInline =
        element.tag == 'code' && !element.attributes.containsKey('class');
    if (customBuilder != null) {
      return customBuilder!(element.textContent.trim(), language, isInline);
    }
    if (isInline) {
      return Text.rich(
        TextSpan(
          text: element.textContent.trim(),
          style: GoogleFonts.firaCode(
            fontSize: theme.textTheme.bodyMedium!.fontSize,
            color: theme.colorScheme.primary,
            backgroundColor:
                theme.colorScheme.surface.withOpacity(0.7),
            height: 1.5,
            letterSpacing: 0,
          ),
        ),
        softWrap: true,
      );
    }
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        element.textContent.trim(),
        style: preferredStyle,
      ),
    );
  }
}

String _processContent(String content) {
  final lines = content.split('\n');
  final processedLines = <String>[];
  bool insideCodeBlock = false;
  for (var line in lines) {
    if (line.startsWith('```')) {
      insideCodeBlock = !insideCodeBlock;
    }
    processedLines.add(line);
  }
  if (insideCodeBlock) {
    processedLines.add('```');
  }
  return processedLines.join('\n');
}

/// Renders markdown text. (Code blocks inside markdown are handled via WidgetSpan.)
class SelectableMarkdown extends StatelessWidget {
  final String data;
  final TextStyle? baseStyle;
  final bool isDark;
  final bool isStreaming;

  // Adjusted spacing constants for better visual hierarchy
  static const double _blockSpacing = 16.0;     // Increased for better section breaks
  static const double _inlineSpacing = 8.0;     
  static const double _listItemSpacing = 4.0;   
  static const double _headerBottomSpacing = 12.0; // Increased for better header separation
  static const double _paragraphSpacing = 10.0;  // Increased for more paragraph separation
  
  const SelectableMarkdown({
    Key? key,
    required this.data,
    this.baseStyle,
    required this.isDark,
    this.isStreaming = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Cache key to prevent unnecessary rebuilds
    final cacheKey = Object.hash(data, isStreaming, isDark);
    
    // Parse markdown content using the dart:markdown package
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    
    // Preprocess content to reduce excessive newlines and trim whitespace
    String processedData = data
        .replaceAll(RegExp(r'\r\n|\r'), '\n')          // Normalize line endings
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')         // Limit consecutive newlines
        .replaceAll(RegExp(r' +$', multiLine: true), ''); // Remove trailing whitespace
    
    final nodes = document.parse(processedData);
    
    // Function to collect textual content with spans for each style
    List<InlineSpan> buildFormattedContent() {
      final spans = <InlineSpan>[];
      
      void processNode(md.Node node, {TextStyle? currentStyle, 
          int listLevel = 0, bool isOrderedList = false, String? parentTag}) {
        if (node is md.Element) {
          TextStyle? newStyle;
          String? prefix;
          String? suffix;
          
          switch (node.tag) {
            case 'p':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Add improved paragraph spacing for better readability
                spans.add(WidgetSpan(
                  child: SizedBox(height: _paragraphSpacing),
                ));
              }
              // Add newline after paragraphs to ensure proper text flow
              suffix = '\n';
              // Use consistent text style for paragraphs
              newStyle = (baseStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                height: 1.5,
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
              );
              break;
            case 'img':
              // Handle image tags safely
              final String? src = node.attributes['src'];
              final String alt = node.attributes['alt'] ?? 'Image';
              
              if (src != null && src.isNotEmpty) {
                spans.add(WidgetSpan(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: _blockSpacing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (src.startsWith('http'))
                          Image.network(
                            src,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.broken_image, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                                    const SizedBox(height: 4),
                                    Text('Failed to load image', style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                                    )),
                                  ],
                                ),
                              );
                            },
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[850] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Unsupported image source: $alt',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                            ),
                          ),
                        if (alt.isNotEmpty && alt != 'Image')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              alt,
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ));
              } else {
                // If no source, just show alt text or placeholder
                spans.add(TextSpan(
                  text: alt.isNotEmpty ? alt : '[Image]',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ));
              }
              return;
            case 'h1':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Ensure proper vertical spacing before headers
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing * 1.2),
                ));
              }
              newStyle = theme.textTheme.headlineMedium!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                height: 1.5,
              );
              // Critical: Add explicit newline after headers
              suffix = '\n';
              // Add extra spacing after header
              spans.add(WidgetSpan(
                child: SizedBox(height: _headerBottomSpacing),
              ));
              break;
            case 'h2':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Ensure proper vertical spacing before headers
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing * 1.2),
                ));
              }
              newStyle = theme.textTheme.headlineSmall!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                height: 1.5,
              );
              // Critical: Add explicit newline after headers
              suffix = '\n';
              // Add extra spacing after header
              spans.add(WidgetSpan(
                child: SizedBox(height: _headerBottomSpacing),
              ));
              break;
            case 'h3':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Ensure proper vertical spacing before headers
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              newStyle = theme.textTheme.titleLarge!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                height: 1.5,
              );
              // Critical: Add explicit newline after headers
              suffix = '\n';
              // Add extra spacing after header
              spans.add(WidgetSpan(
                child: SizedBox(height: _headerBottomSpacing),
              ));
              break;
            case 'h4':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Ensure proper vertical spacing before headers
                spans.add(WidgetSpan(
                  child: SizedBox(height: _inlineSpacing),
                ));
                // Remove duplicate newlines
              }
              newStyle = theme.textTheme.titleMedium!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                height: 1.5,
              );
              suffix = '\n';
              // Add extra spacing after header
              spans.add(WidgetSpan(
                child: SizedBox(height: _headerBottomSpacing * 0.75),
              ));
              break;
            case 'h5':
            case 'h6':
              if (nodes.isNotEmpty && node != nodes.first) {
                // Ensure proper vertical spacing before headers
                spans.add(WidgetSpan(
                  child: SizedBox(height: _inlineSpacing),
                ));
                // Remove duplicate newlines
              }
              newStyle = theme.textTheme.titleSmall!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                height: 1.5,
              );
              suffix = '\n';
              // Add extra spacing after header
              spans.add(WidgetSpan(
                child: SizedBox(height: _headerBottomSpacing * 0.5),
              ));
              break;
            case 'pre':
              // Handle code blocks
              if (node.children != null && node.children!.isNotEmpty && 
                  node.children!.first is md.Element && 
                  (node.children!.first as md.Element).tag == 'code') {
                
                final codeElement = node.children!.first as md.Element;
                String language = '';
                
                if (codeElement.attributes['class'] != null) {
                  final String langClass = codeElement.attributes['class'] as String;
                  language = langClass.startsWith('language-') 
                      ? langClass.substring(9) 
                      : '';
                }
                
                final code = codeElement.textContent;
                
                // Add proper spacing before code blocks
                if (nodes.isNotEmpty && node != nodes.first) {
                  spans.add(WidgetSpan(
                    child: SizedBox(height: _blockSpacing * 0.8),
                  ));
                  // Remove duplicate newlines
                }
                
                // Add a placeholder for the code block with consistent spacing
                spans.add(WidgetSpan(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: _blockSpacing * 0.7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: isDark 
                              ? Colors.black.withOpacity(0.2) 
                              : Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CodeContentWidget(
                      code: code,
                      language: language,
                      isDark: isDark,
                    ),
                  ),
                ));
                
                // Add proper spacing after code blocks
                if (nodes.isNotEmpty && node != nodes.last) {
                  spans.add(WidgetSpan(
                    child: SizedBox(height: _blockSpacing * 0.8),
                  ));
                  // Remove duplicate newlines
                }
                return;
              }
              break;
            case 'blockquote':
              // Add proper spacing before blockquotes
              if (nodes.isNotEmpty && node != nodes.first) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
                // Remove duplicate newlines
              }
              
              // Create a better looking blockquote with left border
              final blockquoteStyle = theme.textTheme.bodyLarge!.copyWith(
                color: isDark 
                    ? Colors.white70 
                    : theme.colorScheme.onSurface.withOpacity(0.8),
                height: 1.5,
                fontStyle: FontStyle.italic,
              );
              
              // Build a widget-based blockquote instead of text prefixes
              if (node.children != null) {
                spans.add(WidgetSpan(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: _inlineSpacing),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: isDark 
                              ? Colors.white30 
                              : theme.colorScheme.primary.withOpacity(0.3),
                          width: 3,
                        ),
                      ),
                      color: isDark 
                          ? Colors.white.withOpacity(0.03) 
                          : theme.colorScheme.primary.withOpacity(0.03),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: node.children!.map((child) {
                        if (child is md.Element && child.tag == 'p') {
                          final textContent = StringBuffer();
                          _extractTextFromNode(child, textContent);
                          
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: child != node.children!.last ? _paragraphSpacing * 0.8 : 0,
                            ),
                            child: Text(
                              textContent.toString(),
                              style: blockquoteStyle,
                            ),
                          );
                        } else {
                          final textContent = StringBuffer();
                          _extractTextFromNode(child, textContent);
                          
                          return Text(
                            textContent.toString(),
                            style: blockquoteStyle,
                          );
                        }
                      }).toList(),
                    ),
                  ),
                ));
              }
              
              // Add proper spacing after blockquotes
              if (nodes.isNotEmpty && node != nodes.last) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              return;
            case 'ul':
              // Add proper spacing before lists
              if (nodes.isNotEmpty && node != nodes.first) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              
              // Use a more visually appealing approach for lists
              if (node.children != null) {
                for (int i = 0; i < node.children!.length; i++) {
                  final child = node.children![i];
                  if (child is md.Element && child.tag == 'li') {
                    final isLastItem = i == node.children!.length - 1;
                    
                    // For formatting the bullet with consistent indentation
                    final indent = '  ' * listLevel;
                    final bulletChar = listLevel == 0 ? '•' : '◦'; // Different bullet for nested lists
                    
                    spans.add(TextSpan(
                      text: '$indent$bulletChar ',
                      style: (currentStyle ?? baseStyle)?.copyWith(
                        color: isDark 
                            ? theme.colorScheme.primary.withOpacity(0.8) 
                            : theme.colorScheme.primary,
                        height: 1.5,
                      ),
                    ));
                    
                    // Process the list item content with proper style
                    final listItemStyle = (currentStyle ?? baseStyle)?.copyWith(
                      height: 1.5,
                    );
                    
                    // Process the list item content
                    if (child.children != null) {
                      for (final grandchild in child.children!) {
                        processNode(
                          grandchild,
                          currentStyle: listItemStyle, 
                          listLevel: listLevel + 1, 
                          parentTag: child.tag
                        );
                      }
                    }
                    
                    // Add appropriate spacing between list items
                    if (!isLastItem) {
                      spans.add(WidgetSpan(
                        child: SizedBox(height: _listItemSpacing),
                      ));
                      // Remove duplicate newlines
                    }
                  }
                }
              }
              
              // Add proper spacing after lists
              if (listLevel == 0 && nodes.isNotEmpty && node != nodes.last) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              return;
            
            case 'ol':
              // Add proper spacing before ordered lists
              if (nodes.isNotEmpty && node != nodes.first) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              
              // Use a more visually appealing approach for ordered lists
              int index = 1;
              if (node.children != null) {
                for (int i = 0; i < node.children!.length; i++) {
                  final child = node.children![i];
                  if (child is md.Element && child.tag == 'li') {
                    final isLastItem = i == node.children!.length - 1;
                    
                    // For formatting the number with consistent indentation
                    final indent = '  ' * listLevel;
                    final number = '$index.';
                    
                    spans.add(TextSpan(
                      text: '$indent$number ',
                      style: (currentStyle ?? baseStyle)?.copyWith(
                        color: isDark 
                            ? theme.colorScheme.primary.withOpacity(0.8)
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ));
                    
                    // Process the list item content with proper style
                    final listItemStyle = (currentStyle ?? baseStyle)?.copyWith(
                      height: 1.5,
                    );
                    
                    // Process the list item content
                    if (child.children != null) {
                      for (final grandchild in child.children!) {
                        processNode(
                          grandchild,
                          currentStyle: listItemStyle, 
                          listLevel: listLevel + 1, 
                          isOrderedList: true,
                          parentTag: child.tag
                        );
                      }
                    }
                    
                    index++;
                    
                    // Add appropriate spacing between list items
                    if (!isLastItem) {
                      spans.add(WidgetSpan(
                        child: SizedBox(height: _listItemSpacing),
                      ));
                      // Remove duplicate newlines
                    }
                  }
                }
              }
              
              // Add proper spacing after ordered lists
              if (listLevel == 0 && nodes.isNotEmpty && node != nodes.last) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing),
                ));
              }
              return;
            case 'li':
              if (node.children != null) {
                for (final child in node.children!) {
                  processNode(child, 
                      currentStyle: currentStyle, 
                      listLevel: listLevel, 
                      isOrderedList: isOrderedList,
                      parentTag: node.tag);
                }
              }
              return;
            case 'br':
              spans.add(const TextSpan(text: '\n'));
              return;
            case 'hr':
              // Add proper spacing before horizontal rule
              if (nodes.isNotEmpty && node != nodes.first) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing * 0.8),
                ));
                // Remove duplicate newlines
              }
              
              // Create a better looking horizontal rule with gradient
              spans.add(WidgetSpan(
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: _blockSpacing * 0.5),
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        isDark 
                            ? Colors.white.withOpacity(0.01) 
                            : theme.colorScheme.onSurface.withOpacity(0.01),
                        isDark 
                            ? Colors.white.withOpacity(0.15) 
                            : theme.colorScheme.onSurface.withOpacity(0.15),
                        isDark 
                            ? Colors.white.withOpacity(0.15) 
                            : theme.colorScheme.onSurface.withOpacity(0.15),
                        isDark 
                            ? Colors.white.withOpacity(0.01) 
                            : theme.colorScheme.onSurface.withOpacity(0.01),
                      ],
                      stops: const [0.0, 0.4, 0.6, 1.0],
                    ),
                  ),
                ),
              ));
              
              // Add proper spacing after horizontal rule
              if (nodes.isNotEmpty && node != nodes.last) {
                spans.add(WidgetSpan(
                  child: SizedBox(height: _blockSpacing * 0.8),
                ));
                // Remove duplicate newlines
              }
              return;
            case 'code':
              if (parentTag != 'pre') {
                // Enhanced inline code styling
                spans.add(TextSpan(
                  text: node.textContent,
                  style: GoogleFonts.firaCode(
                    fontSize: (baseStyle ?? theme.textTheme.bodyMedium)!.fontSize,
                    color: isDark ? const Color(0xFFD0BCFF) : theme.colorScheme.primary,
                    backgroundColor: isDark 
                        ? Colors.black.withOpacity(0.3) 
                        : theme.colorScheme.primary.withOpacity(0.08),
                    height: 1.4, // Slightly tighter line height for code
                    letterSpacing: -0.2, // Adjust letter spacing for code
                    fontWeight: FontWeight.w500, // Slightly bolder than normal text
                  ),
                ));
                return;
              }
              break;
            case 'em':
              // Enhanced italic text
              newStyle = (currentStyle ?? baseStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white.withOpacity(0.9) : null,
              );
              break;
            case 'strong':
              // Enhanced bold text
              newStyle = (currentStyle ?? baseStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark 
                    ? Colors.white 
                    : theme.colorScheme.onSurface.withOpacity(0.9),
              );
              break;
            case 'del':
              // Enhanced strikethrough text
              newStyle = (currentStyle ?? baseStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: isDark 
                    ? Colors.white70 
                    : theme.colorScheme.onSurface.withOpacity(0.7),
                color: isDark 
                    ? Colors.white70 
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              );
              break;
            case 'a':
              final url = node.attributes['href'] ?? '';
              
              // Enhanced link styling
              newStyle = (currentStyle ?? baseStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary.withOpacity(0.4),
                decorationThickness: 1.5,
                fontWeight: FontWeight.w500,
              );
              
              // Create a tappable text span for links
              if (url.isNotEmpty) {
                spans.add(TextSpan(
                  text: node.textContent,
                  style: newStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      _handleMarkdownLinkTap(context, url);
                    },
                ));
                return; // Exit after adding the link
              }
              break;
          }
          if (prefix != null) {
            spans.add(TextSpan(
              text: prefix,
              style: currentStyle ?? baseStyle,
            ));
          }
          if (node.children != null) {
            for (final child in node.children!) {
              processNode(child,
                  currentStyle: newStyle ?? currentStyle,
                  listLevel: listLevel,
                  isOrderedList: isOrderedList,
                  parentTag: node.tag);
            }
          }
          if (suffix != null) {
            spans.add(TextSpan(
              text: suffix,
              style: currentStyle ?? baseStyle,
            ));
          }
        } else if (node is md.Text) {
          spans.add(TextSpan(
            text: node.text,
            style: currentStyle ?? baseStyle,
          ));
        }
      }

      for (final node in nodes) {
        processNode(node);
      }

      // Add streaming cursor at the end if we're streaming
      if (isStreaming) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: StreamingCursorInline(isDark: isDark, theme: theme),
        ));
      }
      
      return spans;
    }

    // Use SelectableText.rich for better selection behavior with a memoized content
    return RepaintBoundary(
      key: ValueKey(cacheKey),
      child: SelectableText.rich(
        TextSpan(
          children: buildFormattedContent(),
          style: baseStyle,
        ),
        selectionControls: CursorlessSelectionControls(),
        showCursor: false,
        cursorWidth: 0,
        cursorRadius: const Radius.circular(0),
        cursorColor: Colors.transparent,
        enableInteractiveSelection: true,
        contextMenuBuilder: (BuildContext context, EditableTextState editableTextState) {
          final List<ContextMenuButtonItem> buttonItems = editableTextState.contextMenuButtonItems;
          
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: buttonItems
                .where((item) => 
                    item.type == ContextMenuButtonType.copy || 
                    item.type == ContextMenuButtonType.selectAll)
                .toList(),
          );
        },
      ),
    );
  }

  // Helper method to extract plain text from markdown nodes
  void _extractTextFromNode(md.Node node, StringBuffer buffer) {
    if (node is md.Text) {
      buffer.write(node.text);
    } else if (node is md.Element) {
      if (node.children != null) {
        for (final child in node.children!) {
          _extractTextFromNode(child, buffer);
        }
      }
    }
  }
}

/// ---------------------------------------------------------------------------
///
/// CodeContentWidget
///
/// A simple widget that displays highlighted code.
/// It is used in code blocks within the message and in the markdown renderer.
/// Updated to allow for continuous text selection across the entire message.
/// Updated to allow for keyboard shortcuts
///
class CodeContentWidget extends StatefulWidget {
  final String code;
  final String language;
  final bool isDark;

  const CodeContentWidget({
    super.key,
    required this.code,
    required this.language,
    required this.isDark,
  });

  @override
  State<CodeContentWidget> createState() => _CodeContentWidgetState();
}

class _CodeContentWidgetState extends State<CodeContentWidget> {
  final FocusNode _focusNode = FocusNode();
  TextSelection? _lastSelection;
  // Add a custom selection controller that doesn't show cursor
  final MaterialTextSelectionControls _cursorlessControls = CursorlessSelectionControls();
  
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
  
  // Helper method to copy text to clipboard
  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _showCopyToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBgColor = widget.isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = widget.isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    final codeTheme = widget.isDark ? atomOneDarkTheme : atomOneLightTheme;
    
    // Normalize code to ensure consistent selection behavior
    final normalizedCode = widget.code
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'\n\s*\n'), '\n\n')
        .replaceAll(RegExp(r' +$', multiLine: true), '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Single header for code blocks
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: headerBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.language.isEmpty ? 'plain text' : widget.language,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: widget.isDark
                      ? const Color(0xFF9DA5B4)
                      : const Color(0xFF383A42),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _copyToClipboard(normalizedCode, 'Code copied to clipboard');
                  },
                  child: Icon(
                    Icons.content_copy_rounded,
                    size: 18,
                    color: widget.isDark
                        ? const Color(0xFF9DA5B4)
                        : const Color(0xFF383A42),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Simple container with SelectableText for code
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: contentBgColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
                if (_lastSelection != null && !_lastSelection!.isCollapsed) {
                  // Copy selected text
                  final selectedText = normalizedCode.substring(
                    _lastSelection!.start,
                    _lastSelection!.end,
                  );
                  _copyToClipboard(selectedText, 'Selection copied to clipboard');
                } else {
                  // Copy entire code
                  _copyToClipboard(normalizedCode, 'Code copied to clipboard');
                }
              },
              const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
                if (_lastSelection != null && !_lastSelection!.isCollapsed) {
                  // Copy selected text
                  final selectedText = normalizedCode.substring(
                    _lastSelection!.start,
                    _lastSelection!.end,
                  );
                  _copyToClipboard(selectedText, 'Selection copied to clipboard');
                } else {
                  // Copy entire code
                  _copyToClipboard(normalizedCode, 'Code copied to clipboard');
                }
              },
            },
            child: Focus(
              focusNode: _focusNode,
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  children: [
                    // Visible highlighted code
                    HighlightView(
                      normalizedCode,
                      language: widget.language,
                      theme: codeTheme,
                      textStyle: GoogleFonts.firaCode(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    // Invisible selectable text
                    Theme(
                      // Use a theme to customize selection appearance
                      data: theme.copyWith(
                        textSelectionTheme: TextSelectionThemeData(
                          selectionColor: widget.isDark
                            ? Colors.white.withOpacity(0.3)
                            : theme.colorScheme.primary.withOpacity(0.2),
                          selectionHandleColor: widget.isDark
                            ? Colors.white.withOpacity(0.7)
                            : theme.colorScheme.primary,
                          cursorColor: Colors.transparent,
                        ),
                      ),
                      child: SelectableText(
                        normalizedCode,
                        style: GoogleFonts.firaCode(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.transparent,
                        ),
                        // Explicitly disable cursor visibility
                        showCursor: false,
                        // Use our custom selection controls without cursor
                        selectionControls: _cursorlessControls,
                        // Don't move cursor when tapped
                        onTap: () {},
                        onSelectionChanged: (selection, _) {
                          setState(() {
                            _lastSelection = selection;
                          });
                        },
                        contextMenuBuilder: (context, editableTextState) {
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editableTextState.contextMenuAnchors,
                            buttonItems: editableTextState.contextMenuButtonItems
                                .where((item) => 
                                    item.type == ContextMenuButtonType.copy || 
                                    item.type == ContextMenuButtonType.selectAll)
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  // Helper method to show a toast instead of a snackbar
  void _showCopyToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy - 40, // Position above the element
        left: position.dx + renderBox.size.width / 2 - 75, // Center horizontally
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black87,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
    });
  }
}

class NoisePainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double density;
  final Random random = Random(42); // Fixed seed for consistent pattern

  NoisePainter({
    required this.color,
    this.opacity = 0.1,
    this.density = 20,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.5;

    for (var i = 0; i < size.width * size.height / density; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawPoints(
        ui.PointMode.points,
        [Offset(x, y)],
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(NoisePainter oldDelegate) => false;
}

// Add the link handling function
void _handleMarkdownLinkTap(BuildContext context, String? href) async {
  if (href == null || href.isEmpty) return;
  
  final Uri uri = Uri.parse(href);
  
  try {
    final canLaunch = await url_launcher.canLaunchUrl(uri);
    if (canLaunch) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    } else {
      // Show a toast notification if the URL can't be launched
      if (context.mounted) {
        _showGlobalToast(context, 'Could not open $href');
      }
    }
  } catch (e) {
    // Show error in toast notification
    if (context.mounted) {
      _showGlobalToast(context, 'Error opening link: $e');
    }
  }
}

// Helper function to show a global toast notification
void _showGlobalToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  
  // Position it at the top center of the screen
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).size.height * 0.1, // 10% from the top
      left: (MediaQuery.of(context).size.width - 280) / 2, // Centered
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.grey[800] 
              : Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    entry.remove();
  });
}

/// A waiting animation that shows while waiting for the first token
class WaitingForTokenAnimation extends StatefulWidget {
  final bool isDark;
  final ThemeData theme;

  const WaitingForTokenAnimation({
    Key? key,
    required this.isDark,
    required this.theme,
  }) : super(key: key);

  @override
  State<WaitingForTokenAnimation> createState() => _WaitingForTokenAnimationState();
}

class _WaitingForTokenAnimationState extends State<WaitingForTokenAnimation> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _ripple1Animation;
  late Animation<double> _ripple1OpacityAnimation;
  late Animation<double> _ripple2Animation;
  late Animation<double> _ripple2OpacityAnimation;
  late Animation<double> _ripple3Animation;
  late Animation<double> _ripple3OpacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Main dot pulse animation
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );
    
    // First ripple effect (quick and subtle)
    _ripple1Animation = Tween<double>(begin: 1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.5, curve: Curves.easeOut),
      ),
    );
    
    _ripple1OpacityAnimation = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.5, curve: Curves.easeOut),
      ),
    );
    
    // Second ripple effect (delayed and larger)
    _ripple2Animation = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );
    
    _ripple2OpacityAnimation = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );
    
    // Third ripple effect (most delayed and largest)
    _ripple3Animation = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _ripple3OpacityAnimation = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final gradient = themeProvider.primaryGradient;
    final primaryColor = widget.theme.colorScheme.primary;
    
    return SizedBox(
      height: 30,
      width: 30,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Third ripple (largest)
              Opacity(
                opacity: _ripple3OpacityAnimation.value,
                child: Transform.scale(
                  scale: _ripple3Animation.value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.2),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Second ripple
              Opacity(
                opacity: _ripple2OpacityAnimation.value,
                child: Transform.scale(
                  scale: _ripple2Animation.value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.25),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // First ripple
              Opacity(
                opacity: _ripple1OpacityAnimation.value,
                child: Transform.scale(
                  scale: _ripple1Animation.value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Main dot
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: gradient,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A streaming cursor widget that animates inline with the text
class StreamingCursorInline extends StatefulWidget {
  final bool isDark;
  final ThemeData theme;

  const StreamingCursorInline({
    Key? key,
    required this.isDark,
    required this.theme,
  }) : super(key: key);

  @override
  State<StreamingCursorInline> createState() => _StreamingCursorInlineState();
}

class _StreamingCursorInlineState extends State<StreamingCursorInline> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Slightly faster animation
    )..repeat(reverse: true);

    // Create a more fluid curve for the main pulse
    final Curve customPulseCurve = Interval(0.0, 1.0, curve: Curves.easeInOutCubic);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: customPulseCurve,
      ),
    );
    
    _opacityAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final gradient = themeProvider.primaryGradient;
    final primaryColor = widget.theme.colorScheme.primary;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.only(left: 2.0),
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              height: 8, // Larger dot
              width: 8, // Larger dot
              margin: const EdgeInsets.only(bottom: 2.0, top: 2.0), // Better vertical alignment
              decoration: BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: _opacityAnimation.value,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A focus node that's always disabled to prevent cursor
class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
  
  @override
  bool canRequestFocus = false;
}
