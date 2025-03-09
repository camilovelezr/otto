import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide TextSelectionHandleType;
import 'package:flutter/services.dart';
import 'dart:ui';  // For FontFeature
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/chat_message.dart';
import '../theme/theme_provider.dart';

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
  bool canSelectAll(TextSelectionDelegate delegate) {
    // Always allow "Select All" functionality
    return true;
  }
  
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textHeight, [VoidCallback? onTap]) {
    // Make the selection handles slightly larger for better usability
    final Widget handle = SizedBox(
      width: 22.0,
      height: 22.0,
      child: CustomPaint(
        painter: _HandlePainter(
          color: Theme.of(context).textSelectionTheme.selectionHandleColor ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    // Forward taps to the given callback
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: handle,
      );
    }
    
    return handle;
  }
  
  // Override this to ensure cursor is never drawn
  @override
  Widget buildCursor(BuildContext context, Rect cursorRect, TextSelectionDelegate delegate) {
    // Return an empty container instead of a cursor
    return Container();
  }
}

// Custom painter for selection handles
class _HandlePainter extends CustomPainter {
  final Color color;
  
  _HandlePainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final radius = size.width / 2;
    
    // Draw a circle for the handle
    canvas.drawCircle(Offset(radius, radius), radius, paint);
  }
  
  @override
  bool shouldRepaint(_HandlePainter oldDelegate) => color != oldDelegate.color;
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

    // Convert nullable String? to non-nullable String
    final String displayLanguage = language ?? '';
    final bool isEmptyLanguage = displayLanguage.isEmpty;
    
    // Clean the code for display
    final String cleanCode = code
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'\n\s*\n'), '\n\n');

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
                    isEmptyLanguage ? 'code' : displayLanguage,
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
              code: cleanCode,
              language: isEmptyLanguage ? null : displayLanguage,
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
                                            String content;
                                            
                                            if (widget.isStreaming) {
                                              // When streaming, only use the streamed content
                                              content = widget.streamedContent;
                                            } else {
                                              // When not streaming, only use the message's content
                                              content = widget.message.content;
                                            }
                                            
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

/// Renders markdown text with proper formatting and selection support.
/// This implementation handles lists, headers, code blocks, and other markdown elements correctly.
/// It ensures continuous text selection across elements while preserving proper styling.
class SelectableMarkdown extends StatefulWidget {
  final String data;
  final TextStyle? baseStyle;
  final bool isDark;
  final bool isStreaming;
  final EdgeInsets contentPadding;
  final ScrollPhysics physics;
  final bool enableInteractiveSelection;

  // Spacing constants for better visual hierarchy
  static const double _blockSpacing = 12.0; // Reduced from 16.0
  static const double _listItemSpacing = 3.0; // Reduced from 4.0
  static const double _paragraphSpacing = 6.0; // Reduced from 8.0
  static const double _headerBottomSpacing = 10.0; // Reduced from 12.0
  
  const SelectableMarkdown({
    Key? key,
    required this.data,
    this.baseStyle,
    required this.isDark,
    this.isStreaming = false,
    this.contentPadding = EdgeInsets.zero,
    this.physics = const ClampingScrollPhysics(),
    this.enableInteractiveSelection = true,
  }) : super(key: key);
  
  @override
  State<SelectableMarkdown> createState() => _SelectableMarkdownState();
}

class _SelectableMarkdownState extends State<SelectableMarkdown> {
  // Handle code block rendering with state tracking
  // Map to keep track of selection state for each code block
  final Map<String, TextSelection?> _codeSelections = {};
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = widget.baseStyle ?? theme.textTheme.bodyLarge!.copyWith(
      color: widget.isDark ? Colors.white : theme.colorScheme.onSurface,
      height: 1.5,
    );
    
    // Process the markdown content
    final processedContent = _preprocessMarkdown(widget.data);
    
    // Parse the markdown
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: [
        // Add custom inline syntaxes for better rendering of combined styles
        md.StrikethroughSyntax(),
      ],
    );
    
    final nodes = document.parse(processedContent);
    
    // Build spans with proper structure
    return Padding(
      padding: widget.contentPadding,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          overscroll: false,
          physics: widget.physics,
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SelectableRegion(
          focusNode: AlwaysDisabledFocusNode(),
          selectionControls: MaterialTextSelectionControls(),
          child: SelectableText.rich(
            TextSpan(
              children: _buildSpans(nodes, context, theme, defaultStyle),
              style: defaultStyle,
            ),
            selectionControls: MaterialTextSelectionControls(),
            enableInteractiveSelection: widget.enableInteractiveSelection,
          ),
        ),
      ),
    );
  }
  
  // Preprocess markdown for better rendering
  String _preprocessMarkdown(String content) {
    // Normalize line endings
    String processed = content.replaceAll('\r\n', '\n');
    
    // Replace multiple newlines with just two for proper paragraph separation
    processed = processed.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    // Fix common issues with nested styles (like *text **bold** text*)
    // Ensure proper nesting of strong/em tags for the parser
    processed = processed.replaceAll(RegExp(r'(\*\*\*|\*\*\_|\_\*\*)'), '**_');
    processed = processed.replaceAll(RegExp(r'(\_\_\*|\_\*\*|\*\_\_)'), '**_');
    
    // Special handling for code blocks - PRESERVE EXACT INDENTATION
    // DO NOT modify any whitespace inside code blocks
    final List<String> lines = processed.split('\n');
    bool inCodeBlock = false;
    List<String> processedLines = [];
    List<String> currentCodeBlock = [];
    
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      
      // Check if this line starts or ends a code block
      if (line.trimLeft().startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        
        // If starting a code block, add the opening fence and continue
        if (inCodeBlock) {
          processedLines.add(line);
          currentCodeBlock = [];
        } else {
          // If ending a code block, add ALL the code lines with EXACT indentation
          processedLines.addAll(currentCodeBlock);
          
          // Add the closing fence
          processedLines.add(line);
        }
      } else if (inCodeBlock) {
        // Inside a code block, collect the line with EXACT indentation and formatting
        // Only handle tabs consistently (convert to spaces)
        currentCodeBlock.add(line.replaceAll('\t', '    '));
      } else {
        // Outside a code block, process normally
        processedLines.add(line.trimRight());
      }
    }
    
    // In case we ended with an open code block
    if (inCodeBlock) {
      // Add ALL code block lines without modification to their indentation
      processedLines.addAll(currentCodeBlock);
      processedLines.add('```'); // Close the code block
    }
    
    // Join all lines back and return the processed content
    processed = processedLines.join('\n').trimRight();
    
    return processed;
  }

  // Main method to build all spans for the markdown content
  List<InlineSpan> _buildSpans(List<md.Node> nodes, BuildContext context, ThemeData theme, TextStyle defaultStyle) {
    final spans = <InlineSpan>[];
    
    // Process each node
    for (final node in nodes) {
      spans.addAll(_processNode(node, context, theme, defaultStyle));
    }
    
    // Add streaming cursor if needed
    if (widget.isStreaming) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: StreamingCursorInline(isDark: widget.isDark, theme: theme),
      ));
    }
    
    return spans;
  }

  // Process a single node and convert it to spans
  List<InlineSpan> _processNode(md.Node node, BuildContext context, ThemeData theme, TextStyle style, {int listLevel = 0}) {
    final spans = <InlineSpan>[];
    
    if (node is md.Element) {
      switch (node.tag) {
        case 'p':
          // Process paragraph content
          spans.addAll(_processInlineElements(node.children!, context, theme, style));
          spans.add(const TextSpan(text: '\n')); // Single newline for paragraphs
          break;
          
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          // Process header content with appropriate styling and proper visual distinction
          final level = int.parse(node.tag.substring(1));
          final headerStyle = _getHeaderStyle(level, theme, style);
          
          // Add spacing before the header
          if (level <= 2) {
            // More space before major headings
            spans.add(const TextSpan(text: '\n\n'));
          } else {
            spans.add(const TextSpan(text: '\n'));
          }
          
          // Add the header text with proper styling
          spans.add(TextSpan(
            text: node.textContent,
            style: headerStyle,
          ));
          
          // Add proper spacing after headers
          spans.add(const TextSpan(text: '\n'));
          break;
          
        case 'ul':
        case 'ol':
          // Process list with proper indentation
          spans.addAll(_buildListSpans(node, context, theme, style, listLevel));
          if (listLevel == 0) {
            spans.add(const TextSpan(text: '\n'));
          }
          break;
          
        case 'li':
          // Should be handled in _buildListSpans
          break;
          
        case 'pre':
          // Handle code blocks - this case handles fenced code blocks with triple backticks
          if (node.children != null && node.children!.isNotEmpty) {
            md.Element? codeNode;
            
            // Find the code node within the pre element
            for (final child in node.children!) {
              if (child is md.Element && child.tag == 'code') {
                codeNode = child;
                break;
              }
            }
            
            if (codeNode != null) {
              // Extract language from the class attribute if it exists
              String language = '';
              if (codeNode.attributes.containsKey('class')) {
                final String langClass = codeNode.attributes['class'] as String;
                if (langClass.startsWith('language-')) {
                  language = langClass.substring(9);
                }
              }
              
              // If we don't have a language from the class attribute, try to detect it from the first line
              if (language.isEmpty && codeNode.textContent.trim().isNotEmpty) {
                final content = codeNode.textContent;
                final firstLine = content.split('\n').first.trim();
                
                // Check if the first line might indicate the language (common pattern in markdown)
                if (firstLine.startsWith('```')) {
                  // Extract language - make sure to get the whole language identifier
                  language = firstLine.substring(3).trim();
                  
                  // If language is empty, plaintext, or text, set it to null
                  if (language.isEmpty || language.toLowerCase() == 'plaintext' || language.toLowerCase() == 'text' || language.toLowerCase() == 'markdown') {
                    language = '';
                  }
                  
                  // Remove the language indicator line from the code completely
                  List<String> contentLines = content.split('\n');
                  if (contentLines.length > 1) {
                    final newContent = contentLines.sublist(1).join('\n').trimLeft();
                    // Monkey patch the code node's content
                    codeNode = md.Element('code', [md.Text(newContent)]);
                    if (language.isNotEmpty) {
                      codeNode.attributes['class'] = 'language-$language';
                    }
                  }
                }
              }
              
              // Normalize language identifier (handle potential Unicode issues)
              if (language.isNotEmpty) {
                language = language.toLowerCase().trim();
                if (language.startsWith('pyth') || language == 'py') {
                  // Treat all variations of Python as standard python
                  language = 'python';
                } else if (language.startsWith('js')) {
                  language = 'javascript';
                } else if (language == 'ts') {
                  language = 'typescript';
                }
              }
              
              // Ensure there's proper spacing before the code block
              // Don't add a newline right before the code block - this is causing the 'n' character
              // spans.add(const TextSpan(text: '\n'));
              
              // Pass null for language if it's empty
              final String? languageToUse = (language == null || language.isEmpty) ? null : language;
              
              // Check if we need to add a newline character before the code block
              // Only add a newline if the previous span isn't already a newline
              if (spans.isNotEmpty) {
                final lastSpan = spans.last;
                if (lastSpan is TextSpan && lastSpan.text != null && !lastSpan.text!.endsWith('\n')) {
                  spans.add(const TextSpan(text: '\n'));
                }
              }
              
              spans.add(WidgetSpan(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0), // Reduce top padding
                  child: _buildCodeBlockWidget(context, codeNode.textContent, languageToUse),
                ),
              ));
              
              // Add spacing after the code block
              spans.add(const TextSpan(text: '\n')); // Reduced from '\n\n'
            }
          }
          break;
          
        case 'code':
          // This is for inline code, not code blocks (pre > code)
          // We need to check if this code element is within a pre element
          // Since we don't have access to parent, we'll use a flag passed from the calling function
          if (!_isCodeWithinPre(node)) {
            spans.add(TextSpan(
              text: node.textContent,
              style: GoogleFonts.firaCode(
                fontSize: style.fontSize,
                color: widget.isDark ? const Color(0xFFD0BCFF) : theme.colorScheme.primary,
                backgroundColor: widget.isDark 
                    ? Colors.black.withOpacity(0.3) 
                    : theme.colorScheme.primary.withOpacity(0.08),
                height: 1.4,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w500,
              ),
            ));
          }
          break;
          
        case 'blockquote':
          // Process blockquote content using text spans instead of widgets
          // This improves selection behavior across blockquotes
          spans.add(TextSpan(
            children: _processInlineElements(node.children!, context, theme, 
              style.copyWith(
                fontStyle: FontStyle.italic,
                color: widget.isDark 
                    ? Colors.white70 
                    : theme.colorScheme.onSurface.withOpacity(0.8),
                background: Paint()
                  ..color = widget.isDark 
                      ? theme.colorScheme.primary.withOpacity(0.06)
                      : theme.colorScheme.primary.withOpacity(0.04)
                  ..style = PaintingStyle.fill,
              )
            ),
            style: TextStyle(
              // Add left border effect using decoration
              decoration: TextDecoration.lineThrough,
              decorationColor: widget.isDark 
                  ? theme.colorScheme.primary.withOpacity(0.6)
                  : theme.colorScheme.primary.withOpacity(0.5),
              decorationThickness: 4.0,
              // Hide the actual line-through by making it transparent
              decorationStyle: TextDecorationStyle.solid,
              background: Paint()
                ..color = widget.isDark 
                    ? theme.colorScheme.primary.withOpacity(0.06)
                    : theme.colorScheme.primary.withOpacity(0.04)
                ..style = PaintingStyle.fill,
            ),
          ));
          spans.add(const TextSpan(text: '\n\n'));
          break;
          
        case 'hr':
          // Horizontal rule as text span for better selection
          spans.add(const TextSpan(text: '\n'));
          spans.add(WidgetSpan(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              height: 1.0,
              color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
            ),
          ));
          spans.add(const TextSpan(text: '\n')); // Space after horizontal rule
          break;
          
        case 'table':
          // Handle tables
          spans.add(WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0), // Reduced from 8.0
              child: _buildTableWidget(node, context, theme, style),
            ),
          ));
          spans.add(const TextSpan(text: '\n')); // Reduced from '\n\n'
          break;
          
        default:
          // Process other elements' children
          if (node.children != null) {
            spans.addAll(_processInlineElements(node.children!, context, theme, style));
          }
          break;
      }
    } else if (node is md.Text) {
      // Handle plain text
      spans.add(TextSpan(text: node.text, style: style));
    }
    
    return spans;
  }

  // Helper method to check if a code element is inside a pre element
  bool _isCodeWithinPre(md.Element codeNode) {
    // Since we don't have parent access, we can use a heuristic:
    // If this is a code block, it will likely have a class attribute with language-*
    if (codeNode.attributes.containsKey('class')) {
      final classAttr = codeNode.attributes['class'] as String;
      if (classAttr.startsWith('language-')) {
        return true;
      }
    }
    
    // If no class attribute, check content - code blocks tend to be multi-line
    final content = codeNode.textContent;
    if (content.contains('\n')) {
      return true;
    }
    
    // Assume it's an inline code if we get here
    return false;
  }

  // Process inline elements like bold, italic, code, links
  List<InlineSpan> _processInlineElements(List<md.Node> nodes, BuildContext context, ThemeData theme, TextStyle style) {
    final spans = <InlineSpan>[];
    
    for (final node in nodes) {
      if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
          case 'b':
            // Bold text - process children to handle nested styles
            if (node.children != null && node.children!.isNotEmpty) {
              // Create a style with bold that can combine with other styles
              final boldStyle = style.copyWith(
                fontWeight: FontWeight.bold,
              );
              
              spans.addAll(_processInlineElements(
                node.children!, 
                context, 
                theme, 
                boldStyle,
              ));
            } else {
              spans.add(TextSpan(
                text: node.textContent,
                style: style.copyWith(fontWeight: FontWeight.bold),
              ));
            }
            break;
            
          case 'em':
          case 'i':
            // Italic text - process children to handle nested styles
            if (node.children != null && node.children!.isNotEmpty) {
              // Create a style with italic that can combine with other styles
              final italicStyle = style.copyWith(
                fontStyle: FontStyle.italic,
              );
              
              spans.addAll(_processInlineElements(
                node.children!, 
                context, 
                theme, 
                italicStyle,
              ));
            } else {
              spans.add(TextSpan(
                text: node.textContent,
                style: style.copyWith(fontStyle: FontStyle.italic),
              ));
            }
            break;
            
          case 'code':
            // Inline code - only if it's not inside a pre tag (code block)
            if (!_isCodeWithinPre(node)) {
              spans.add(TextSpan(
                text: node.textContent,
                style: GoogleFonts.firaCode(
                  fontSize: style.fontSize,
                  color: widget.isDark ? const Color(0xFFD0BCFF) : theme.colorScheme.primary,
                  backgroundColor: widget.isDark 
                      ? Colors.black.withOpacity(0.3) 
                      : theme.colorScheme.primary.withOpacity(0.08),
                  height: 1.4,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w500,
                ),
              ));
            }
            break;
            
          case 'a':
            // Links - process children to handle styled links
            final url = node.attributes['href'] ?? '';
            if (node.children != null && node.children!.isNotEmpty) {
              spans.add(TextSpan(
                children: _processInlineElements(
                  node.children!, 
                  context, 
                  theme, 
                  style.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary.withOpacity(0.4),
                    decorationThickness: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    _handleMarkdownLinkTap(context, url);
                  },
              ));
            } else {
              spans.add(TextSpan(
                text: node.textContent,
                style: style.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary.withOpacity(0.4),
                  decorationThickness: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    _handleMarkdownLinkTap(context, url);
                  },
              ));
            }
            break;
            
          case 'br':
            // Line break
            spans.add(const TextSpan(text: '\n'));
            break;
            
          case 'img':
            // Images
            final src = node.attributes['src'] ?? '';
            final alt = node.attributes['alt'] ?? 'Image';
            spans.add(WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildImageWidget(src, alt, context, theme),
              ),
            ));
            break;
            
          case 'del':
          case 's':
            // Strikethrough text - process children to handle nested styles
            if (node.children != null && node.children!.isNotEmpty) {
              // Create a new style with strikethrough that can be combined with other styles
              final strikeThroughStyle = style.copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: widget.isDark 
                    ? Colors.white70 
                    : theme.colorScheme.onSurface.withOpacity(0.7),
                decorationThickness: 1.5, // Make it slightly thicker for better visibility
                color: widget.isDark 
                    ? Colors.white60
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              );
              
              spans.addAll(_processInlineElements(
                node.children!, 
                context, 
                theme, 
                strikeThroughStyle,
              ));
            } else {
              spans.add(TextSpan(
                text: node.textContent,
                style: style.copyWith(
                  decoration: TextDecoration.lineThrough,
                  decorationColor: widget.isDark 
                      ? Colors.white70 
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                  decorationThickness: 1.5, // Make it slightly thicker for better visibility
                  color: widget.isDark 
                      ? Colors.white60
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ));
            }
            break;
            
          default:
            // Process other elements' children
            if (node.children != null && node.children!.isNotEmpty) {
              spans.addAll(_processInlineElements(node.children!, context, theme, style));
            } else if (node.textContent.isNotEmpty) {
              spans.add(TextSpan(text: node.textContent, style: style));
            }
            break;
        }
      } else if (node is md.Text) {
        // Handle plain text
        spans.add(TextSpan(text: node.text, style: style));
      }
    }
    
    return spans;
  }

  // Build list spans with proper indentation and bullets
  List<InlineSpan> _buildListSpans(md.Element listNode, BuildContext context, ThemeData theme, TextStyle style, int level) {
    final spans = <InlineSpan>[];
    final isOrdered = listNode.tag == 'ol';
    int index = 1;
    
    // For top-level lists (level == 0), ensure there's spacing before the list
    if (level == 0) {
      spans.add(const TextSpan(text: '\n'));
    }
    
    // Process each list item
    for (final child in listNode.children!) {
      if (child is md.Element && child.tag == 'li') {
        // Add indentation for list items based on level
        if (level > 0) {
          // Consistent indentation for nested lists (4 spaces per level)
          spans.add(TextSpan(text: ' ' * (4 * level)));
        }
        
        // Add item marker (bullet or number) with proper styling
        final bulletText = isOrdered ? '$index. ' : _getBulletForLevel(level);
        spans.add(TextSpan(
          text: bulletText,
          style: style.copyWith(
            color: _getBulletColor(theme, level),
            fontWeight: FontWeight.bold,
          ),
        ));
        
        // Check if item contains a nested list
        bool hasNestedList = false;
        List<md.Node> contentNodes = [];
        List<md.Element> nestedLists = [];
        
        if (child.children != null) {
          for (final itemChild in child.children!) {
            if (itemChild is md.Element && (itemChild.tag == 'ul' || itemChild.tag == 'ol')) {
              hasNestedList = true;
              nestedLists.add(itemChild);
            } else {
              contentNodes.add(itemChild);
            }
          }
        }
        
        // Process item's content
        if (contentNodes.isNotEmpty) {
          spans.addAll(_processInlineElements(contentNodes, context, theme, style));
        }
        
        // Process nested lists with proper spacing
        if (hasNestedList) {
          // Add space after item content before nested list
          spans.add(const TextSpan(text: '\n'));
          
          // Process nested lists
          for (final nestedList in nestedLists) {
            spans.addAll(_buildListSpans(nestedList, context, theme, style, level + 1));
          }
        } else {
          // Add line break after item
          spans.add(const TextSpan(text: '\n'));
        }
        
        index++;
      }
    }
    
    // For top-level lists, add a little space at the end
    if (level == 0) {
      spans.add(const TextSpan(text: '\n'));
    }
    
    return spans;
  }

  // Get the appropriate bullet character for the list level
  String _getBulletForLevel(int level) {
    switch (level % 3) {
      case 0: return '• '; // Filled circle for top level
      case 1: return '◦ '; // Open circle for second level
      case 2: return '▪ '; // Filled square for third level
      default: return '• ';
    }
  }

  // Add color variation for different list levels
  Color _getBulletColor(ThemeData theme, int level) {
    switch (level % 3) {
      case 0:
        return theme.colorScheme.primary;
      case 1:
        return widget.isDark
            ? theme.colorScheme.primary.withOpacity(0.8)
            : theme.colorScheme.primary.withOpacity(0.7);
      case 2:
        return widget.isDark
            ? theme.colorScheme.secondary
            : theme.colorScheme.secondary;
      default:
        return theme.colorScheme.primary;
    }
  }

  // Get header style based on level
  TextStyle _getHeaderStyle(int level, ThemeData theme, TextStyle baseStyle) {
    late double fontSize;
    late FontWeight fontWeight;
    late Color color;
    
    // Define header sizes and styles based on level
    switch (level) {
      case 1:
        fontSize = theme.textTheme.headlineLarge!.fontSize!;
        fontWeight = FontWeight.w700;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      case 2:
        fontSize = theme.textTheme.headlineMedium!.fontSize!;
        fontWeight = FontWeight.w600;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      case 3:
        fontSize = theme.textTheme.headlineSmall!.fontSize!;
        fontWeight = FontWeight.w600;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      case 4:
        fontSize = theme.textTheme.titleLarge!.fontSize!;
        fontWeight = FontWeight.w600;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      case 5:
        fontSize = theme.textTheme.titleMedium!.fontSize!;
        fontWeight = FontWeight.w500;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      case 6:
        fontSize = theme.textTheme.titleMedium!.fontSize!;
        fontWeight = FontWeight.w500;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
        break;
      default:
        fontSize = theme.textTheme.titleMedium!.fontSize!;
        fontWeight = FontWeight.w600;
        color = widget.isDark ? Colors.white : theme.colorScheme.onSurface;
    }
    
    return baseStyle.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.2,  // Slightly tighter line height for headings
      color: color,
    );
  }

  // Build code block widget with improved syntax highlighting and selection handling
  Widget _buildCodeBlockWidget(BuildContext context, String code, String? language) {
    final theme = Theme.of(context);
    final headerBgColor = widget.isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = widget.isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
    // Generate a unique key for this code block
    final String codeKey = '${language ?? "code"}_${code.hashCode}';
    
    // Clean and normalize code: preserve ALL indentation but normalize line endings
    String normalizedCode = code
        .replaceAll(RegExp(r'\r\n|\r'), '\n') // Normalize line endings only
        .trimRight(); // Only trim trailing whitespace, preserve ALL leading whitespace for indentation
        
    // Ensure no leading empty line
    if (normalizedCode.startsWith('\n')) {
      normalizedCode = normalizedCode.substring(1);
    }
        
    // Determine appropriate tab size based on language
    final int tabSpaces = _getTabSizeForLanguage(language);
    
    // Replace tabs with the appropriate number of spaces for the language
    normalizedCode = normalizedCode.replaceAll('\t', ' ' * tabSpaces);
        
    // Make sure code doesn't start with a single 'n' character (which might happen due to newline issues)
    if (normalizedCode.startsWith('n') && (normalizedCode.length == 1 || normalizedCode[1] == '\n')) {
      normalizedCode = normalizedCode.substring(1);
    }
    
    // Split the code into lines for processing
    final List<String> lines = normalizedCode.split('\n');
    
    // Remove any leading blank lines which could cause issues
    int startIndex = 0;
    while (startIndex < lines.length && lines[startIndex].trim().isEmpty) {
      startIndex++;
    }
    
    // If entire block is empty, handle it
    if (startIndex >= lines.length) {
      return Container(
        decoration: BoxDecoration(
          color: contentBgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          '(empty code block)',
          style: GoogleFonts.firaCode(
            fontSize: theme.textTheme.bodyMedium!.fontSize,
            color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    // IMPORTANT: PRESERVE EXACT INDENTATION - don't calculate minimum indent
    // Just remove leading empty lines and join back
    if (startIndex > 0) {
      normalizedCode = lines.sublist(startIndex).join('\n');
    }
    
    // Fix any issues with remaining code fence or language identifiers
    if (normalizedCode.startsWith('```')) {
      final fenceLines = normalizedCode.split('\n');
      if (fenceLines.length > 1) {
        // Remove the first line if it's a code fence
        normalizedCode = fenceLines.sublist(1).join('\n');
      } else {
        // If there's only one line, remove the code fence markers
        normalizedCode = normalizedCode.replaceAll('```', '').trim();
      }
    }
    
    // Handle empty code blocks
    if (normalizedCode.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: contentBgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          '(empty code block)',
          style: GoogleFonts.firaCode(
            fontSize: theme.textTheme.bodyMedium!.fontSize,
            color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    // Comprehensive language mapping
    final languageMap = {
      'py': 'python',
      'python': 'python',
      'js': 'javascript',
      'ts': 'typescript',
      'jsx': 'javascript',
      'tsx': 'typescript',
      'c++': 'cpp',
      'cpp': 'cpp',
      'sh': 'bash',
      'shell': 'bash',
      'json': 'json',
      'html': 'html',
      'css': 'css',
      'java': 'java',
      'kotlin': 'kotlin',
      'swift': 'swift',
      'ruby': 'ruby',
      'go': 'go',
      'rust': 'rust',
      'dart': 'dart',
      'sql': 'sql',
      'xml': 'xml',
      'yaml': 'yaml',
      'yml': 'yaml',
    };
    
    // Check if language is specified and not empty
    final String normalizedLanguage = language?.trim().toLowerCase() ?? '';
    
    // If language is empty or not in our known languages, don't specify a language
    String? highlightLanguage;
    String displayLanguage = 'code';
    
    if (normalizedLanguage.isNotEmpty) {
      // Check if the language is in our mapping
      if (languageMap.containsKey(normalizedLanguage)) {
        highlightLanguage = languageMap[normalizedLanguage];
        displayLanguage = highlightLanguage!;
      } else {
        // If not in our mapping but not empty, use the provided language
        highlightLanguage = normalizedLanguage;
        displayLanguage = normalizedLanguage;
      }
    }
    
    // Choose appropriate theme based on dark/light mode
    final codeTheme = widget.isDark ? atomOneDarkTheme : atomOneLightTheme;
    
    // Helper function for clipboard operations
    void copyToClipboard(String text, String message) {
      Clipboard.setData(ClipboardData(text: text));
      _showGlobalToast(context, message);
    }
    
    // Function to handle copy action
    void handleCopy() {
      final selection = _codeSelections[codeKey];
      if (selection != null && !selection.isCollapsed) {
        // Copy selected text
        final selectedText = normalizedCode.substring(
          selection.start,
          selection.end,
        );
        copyToClipboard(selectedText, 'Selection copied to clipboard');
      } else {
        // Copy entire code
        copyToClipboard(normalizedCode, 'Code copied to clipboard');
      }
    }
    
    // Create a focus node for keyboard shortcuts
    final focusNode = FocusNode();
    
    return RepaintBoundary(
      child: Material(
        color: contentBgColor,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with language display and copy button
            Material(
              color: headerBgColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayLanguage,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: widget.isDark
                            ? const Color(0xFF9DA5B4)
                            : const Color(0xFF383A42),
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => copyToClipboard(normalizedCode, 'Code copied to clipboard'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.isDark 
                                ? Colors.white.withOpacity(0.06) 
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_copy_rounded,
                                size: 16,
                                color: widget.isDark
                                    ? const Color(0xFF9DA5B4)
                                    : const Color(0xFF383A42),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Code content with syntax highlighting and selection capability
            Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: EdgeInsets.zero, // Use zero padding here since CodeContentWidget has its own padding
              decoration: BoxDecoration(
                color: contentBgColor,
                border: Border(
                  top: BorderSide(
                    color: widget.isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              // Handle keyboard shortcuts
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyC, control: true): handleCopy,
                  const SingleActivator(LogicalKeyboardKey.keyC, meta: true): handleCopy,
                },
                child: Focus(
                  focusNode: focusNode,
                  onFocusChange: (focused) {
                    // This ensures the focus node is properly managed
                    if (focused) {
                      FocusScope.of(context).requestFocus(focusNode);
                    }
                  },
                  // Use our fixed CodeContentWidget which preserves indentation correctly
                  child: CodeContentWidget(
                    code: normalizedCode,
                    language: highlightLanguage,
                    isDark: widget.isDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build table widget
  Widget _buildTableWidget(md.Element tableNode, BuildContext context, ThemeData theme, TextStyle style) {
    final List<TableRow> tableRows = [];
    bool hasHeader = false;
    final List<TableColumnWidth> columnWidths = [];
    final List<TextAlign> alignments = [];
    int columnCount = 0;
    
    // First pass: determine column count and alignments
    if (tableNode.children != null) {
      // Look for header and separator row to determine alignments
      md.Element? separatorRow;
      
      for (int i = 0; i < tableNode.children!.length; i++) {
        final child = tableNode.children![i];
        
        if (child is md.Element && child.tag == 'thead') {
          hasHeader = true;
          
          // Process header row to determine column count
          if (child.children != null && child.children!.isNotEmpty) {
            for (final headRow in child.children!) {
              if (headRow is md.Element && headRow.tag == 'tr' && headRow.children != null) {
                columnCount = headRow.children!.length;
                break;
              }
            }
          }
          
          // Look for alignment info in thead
          if (child.children != null && child.children!.length > 1) {
            final possibleSeparator = child.children![1];
            if (possibleSeparator is md.Element && possibleSeparator.tag == 'tr') {
              separatorRow = possibleSeparator;
            }
          }
        } else if (child is md.Element && child.tag == 'tr' && child.children != null) {
          // Handle direct tr elements
          columnCount = math.max(columnCount, child.children!.length);
        }
      }
      
      // Initialize alignments based on separator row if available
      for (int i = 0; i < columnCount; i++) {
        TextAlign align = TextAlign.left; // Default alignment
        
        // Try to determine alignment from separator row
        if (separatorRow != null && separatorRow.children != null && i < separatorRow.children!.length) {
          final separatorCell = separatorRow.children![i];
          if (separatorCell is md.Element && separatorCell.tag == 'td') {
            final content = separatorCell.textContent.trim();
            
            if (content.startsWith(':') && content.endsWith(':')) {
              align = TextAlign.center;
            } else if (content.endsWith(':')) {
              align = TextAlign.right;
            } else {
              align = TextAlign.left;
            }
          }
        }
        
        alignments.add(align);
        columnWidths.add(const FlexColumnWidth());
      }
    }
    
    // If no alignments determined, use defaults
    if (alignments.isEmpty) {
      for (int i = 0; i < math.max(columnCount, 1); i++) {
        alignments.add(TextAlign.left);
        columnWidths.add(const FlexColumnWidth());
      }
    }
    
    // Second pass: build rows
    if (tableNode.children != null) {
      for (int i = 0; i < tableNode.children!.length; i++) {
        final child = tableNode.children![i];
        
        if (child is md.Element && child.tag == 'thead') {
          // Process header row
          hasHeader = true;
          if (child.children != null && child.children!.isNotEmpty) {
            // Only process the first row as header (skip separator row if it exists)
            if (child.children!.isNotEmpty) {
              final headRow = child.children!.first;
              if (headRow is md.Element && headRow.tag == 'tr') {
                tableRows.add(_buildTableRowWidget(headRow, context, theme, style, isHeader: true, alignments: alignments, columnCount: columnCount));
              }
            }
          }
        } else if (child is md.Element && child.tag == 'tbody') {
          // Process body rows
          if (child.children != null) {
            for (final bodyRow in child.children!) {
              if (bodyRow is md.Element && bodyRow.tag == 'tr') {
                // Skip separator rows (used for alignment)
                if (!_isSeparatorRow(bodyRow)) {
                  tableRows.add(_buildTableRowWidget(bodyRow, context, theme, style, isHeader: false, alignments: alignments, columnCount: columnCount));
                }
              }
            }
          }
        } else if (child is md.Element && child.tag == 'tr') {
          // Handle direct tr elements but skip separator rows
          if (!_isSeparatorRow(child)) {
            final isHeaderRow = i == 0 && !hasHeader;
            tableRows.add(_buildTableRowWidget(child, context, theme, style, isHeader: isHeaderRow, alignments: alignments, columnCount: columnCount));
          }
        }
      }
    }
    
    // If no rows were built (unusual case), return a placeholder
    if (tableRows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text("Empty table"),
        ),
      );
    }
    
    // Build the table with proper styling
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: widget.isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(vertical: 12),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            verticalInside: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            top: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            bottom: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            left: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            right: BorderSide(
              color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
          defaultColumnWidth: const FlexColumnWidth(),
          columnWidths: Map.fromEntries(
            columnWidths.asMap().entries.map((e) => MapEntry(e.key, e.value))
          ),
          children: tableRows,
        ),
      ),
    );
  }

  // Check if a row is a separator row (used for alignment)
  bool _isSeparatorRow(md.Element row) {
    if (row.children == null || row.children!.isEmpty) return false;
    
    // Check if this row only contains separator cells (like |:---:|:---:|)
    bool isSeparator = true;
    for (final cell in row.children!) {
      if (cell is md.Element && (cell.tag == 'td' || cell.tag == 'th')) {
        final content = cell.textContent.trim();
        // If it doesn't match the separator pattern, it's not a separator row
        if (!RegExp(r'^:?-+:?$').hasMatch(content)) {
          isSeparator = false;
          break;
        }
      } else {
        isSeparator = false;
        break;
      }
    }
    
    return isSeparator;
  }

  // Build a table row widget with proper cell alignment and styling
  TableRow _buildTableRowWidget(md.Element rowNode, BuildContext context, ThemeData theme, TextStyle style, {
    required bool isHeader,
    required List<TextAlign> alignments,
    required int columnCount,
  }) {
    final cells = <Widget>[];
    
    // Process the cells in this row
    if (rowNode.children != null) {
      for (int i = 0; i < columnCount; i++) {
        // Get cell data if it exists
        md.Element? cell;
        if (i < rowNode.children!.length) {
          final node = rowNode.children![i];
          if (node is md.Element && (node.tag == 'td' || node.tag == 'th')) {
            cell = node;
          }
        }
        
        // Determine text alignment for this cell
        final alignment = i < alignments.length ? alignments[i] : TextAlign.left;
        
        cells.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isHeader 
                ? (widget.isDark ? const Color(0xFF2C3240) : const Color(0xFFF5F7FA))
                : (widget.isDark ? const Color(0xFF1E2634).withOpacity(0.4) : Colors.white),
            child: cell == null
                ? const SizedBox()
                : SelectableText.rich(
                    TextSpan(
                      children: _processInlineElements(
                        cell.children ?? [], 
                        context, 
                        theme,
                        isHeader
                            ? style.copyWith(
                                fontWeight: FontWeight.bold,
                                color: widget.isDark 
                                    ? Colors.white 
                                    : theme.colorScheme.onSurface,
                              )
                            : style,
                      ),
                    ),
                    textAlign: alignment,
                  ),
          ),
        );
      }
    }
    
    return TableRow(
      decoration: const BoxDecoration(),
      children: cells,
    );
  }

  // Build image widget
  Widget _buildImageWidget(String src, String alt, BuildContext context, ThemeData theme) {
    if (src.startsWith('http')) {
      // Network image
      return Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
          maxHeight: 300,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: widget.isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                src,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 200,
                    height: 150,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / 
                                (loadingProgress.expectedTotalBytes ?? 1)
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, color: widget.isDark ? Colors.grey[400] : Colors.grey[700]),
                        const SizedBox(height: 8),
                        Text('Failed to load image', style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                        )),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (alt.isNotEmpty && alt != 'Image')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  alt,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    } else {
      // Local image or invalid image
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: widget.isDark ? Colors.grey[400] : Colors.grey[700]),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                alt.isNotEmpty ? alt : 'Image',
                style: TextStyle(
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  // Helper method to determine tab size based on language
  int _getTabSizeForLanguage(String? language) {
    if (language == null) return 2;  // Default to 2 spaces for unknown languages
    
    final String lang = language.toLowerCase();
    
    // Languages that commonly use 4 spaces
    if (lang == 'python' || lang == 'py' || 
        lang == 'rust' || lang == 'rs' ||
        lang == 'swift' ||
        lang == 'kotlin' ||
        lang == 'scala') {
      return 4;
    }
    
    // Languages that commonly use 2 spaces
    if (lang == 'javascript' || lang == 'js' ||
        lang == 'typescript' || lang == 'ts' ||
        lang == 'json' ||
        lang == 'yaml' || lang == 'yml' ||
        lang == 'ruby' || lang == 'rb' ||
        lang == 'css' ||
        lang == 'html' ||
        lang == 'jsx' ||
        lang == 'tsx' ||
        lang == 'dart') {
      return 2;
    }
    
    // Default to 2 spaces for all other languages
    return 2;
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
  final String? language;
  final bool isDark;

  const CodeContentWidget({
    super.key,
    required this.code,
    this.language,
    required this.isDark,
  });

  @override
  State<CodeContentWidget> createState() => _CodeContentWidgetState();
}

class _CodeContentWidgetState extends State<CodeContentWidget> {
  final FocusNode _focusNode = FocusNode();
  TextSelection? _lastSelection;
  final MaterialTextSelectionControls _cursorlessControls = CursorlessSelectionControls();
  
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
  
  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _showCopyToast(context, message);
  }

  void _handleCopy() {
    if (_lastSelection != null && !_lastSelection!.isCollapsed) {
      // Copy selected text
      final selectedText = widget.code.substring(
        _lastSelection!.start,
        _lastSelection!.end,
      );
      _copyToClipboard(selectedText, 'Selection copied to clipboard');
    } else {
      // Copy entire code
      _copyToClipboard(widget.code, 'Code copied to clipboard');
    }
  }
  
  // Get appropriate tab size based on language
  int _getLanguageTabSize() {
    final String? language = widget.language?.toLowerCase();
    return _getTabSizeForLanguage(language);
  }

  // Helper method to determine tab size based on language
  int _getTabSizeForLanguage(String? language) {
    if (language == null) return 2;  // Default to 2 spaces for unknown languages
    
    final String lang = language.toLowerCase();
    
    // Languages that commonly use 4 spaces
    if (lang == 'python' || lang == 'py' || 
        lang == 'rust' || lang == 'rs' ||
        lang == 'swift' ||
        lang == 'kotlin' ||
        lang == 'scala') {
      return 4;
    }
    
    // Languages that commonly use 2 spaces
    if (lang == 'javascript' || lang == 'js' ||
        lang == 'typescript' || lang == 'ts' ||
        lang == 'json' ||
        lang == 'yaml' || lang == 'yml' ||
        lang == 'ruby' || lang == 'rb' ||
        lang == 'css' ||
        lang == 'html' ||
        lang == 'jsx' ||
        lang == 'tsx' ||
        lang == 'dart') {
      return 2;
    }
    
    // Default to 2 spaces for all other languages
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Normalize code and remove empty line at top ONLY
    String normalizedCode = widget.code
        .replaceAll(RegExp(r'\r\n|\r'), '\n'); // Normalize line endings only
    
    // Remove ONLY the empty line at the top if present, preserve all other formatting
    if (normalizedCode.startsWith('\n')) {
      normalizedCode = normalizedCode.substring(1);
    }
    
    // Trim only trailing whitespace
    normalizedCode = normalizedCode.trimRight();
    
    // Convert tabs to spaces for consistent display
    final int tabSpaces = _getLanguageTabSize();
    normalizedCode = normalizedCode.replaceAll('\t', ' ' * tabSpaces);
    
    final codeTheme = widget.isDark ? atomOneDarkTheme : atomOneLightTheme;
    final contentBgColor = widget.isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
    return Container(
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
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => _handleCopy(),
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () => _handleCopy(),
        },
        child: Focus(
          focusNode: _focusNode,
          child: SelectableCodeView(
            code: normalizedCode,
            language: widget.language ?? 'text',
            theme: codeTheme,
            isDark: widget.isDark,
            onSelectionChanged: (selection) {
              setState(() {
                _lastSelection = selection;
              });
            },
          ),
        ),
      ),
    );
  }
  
  // Helper method to show a toast instead of a snackbar
  void _showCopyToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final theme = Theme.of(context); // Get theme from context
    
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy - 40, // Position above the element
        left: position.dx + renderBox.size.width / 2 - 75, // Center horizontally
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.grey[800] : Colors.white,
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
                  color: theme.colorScheme.primary,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
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

/// A custom widget that combines syntax highlighting with text selection
class SelectableCodeView extends StatefulWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final bool isDark;
  final Function(TextSelection)? onSelectionChanged;

  const SelectableCodeView({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.isDark,
    this.onSelectionChanged,
  });

  @override
  State<SelectableCodeView> createState() => _SelectableCodeViewState();
}

class _SelectableCodeViewState extends State<SelectableCodeView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Ensure code has no empty line at the top and preserve exact indentation
    final String processedCode = _preprocessCode(widget.code);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // The visible highlighted code with exact indentation
            Container(
              width: constraints.maxWidth,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: IntrinsicWidth(
                  child: HighlightView(
                    processedCode,
                    language: widget.language,
                    theme: widget.theme,
                    textStyle: GoogleFonts.firaCode(
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: -0.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            
            // The invisible but selectable text that precisely matches the highlighted code
            Container(
              width: constraints.maxWidth,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: IntrinsicWidth(
                  child: Theme(
                    data: theme.copyWith(
                      textSelectionTheme: TextSelectionThemeData(
                        selectionColor: widget.isDark
                          ? Colors.white.withOpacity(0.3)
                          : theme.colorScheme.primary.withOpacity(0.2),
                        selectionHandleColor: widget.isDark
                          ? Colors.white.withOpacity(0.7)
                          : theme.colorScheme.primary,
                      ),
                    ),
                    child: PreText(
                      processedCode,
                      style: GoogleFonts.firaCode(
                        fontSize: 14,
                        height: 1.5,
                        letterSpacing: -0.2,
                        color: Colors.transparent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      selectionControls: CursorlessSelectionControls(),
                      onSelectionChanged: widget.onSelectionChanged,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  // Preprocess code to ensure proper display
  String _preprocessCode(String code) {
    // 1. Normalize line endings
    String result = code.replaceAll(RegExp(r'\r\n|\r'), '\n');
    
    // 2. Remove empty line at the top if present
    if (result.startsWith('\n')) {
      result = result.substring(1);
    }
    
    // 3. Trim only trailing whitespace, not leading
    result = result.trimRight();
    
    return result;
  }
}

/// A pre-formatted text widget that preserves whitespace and handles selection
class PreText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextSelectionControls? selectionControls;
  final Function(TextSelection)? onSelectionChanged;

  const PreText(
    this.text, {
    super.key,
    required this.style,
    this.selectionControls,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Make sure to use a style with proper monospace features
    final textStyle = style.copyWith(
      // FiraCode from GoogleFonts is already monospace, just need tabular figures
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    
    // Use RawScrollbar to give proper horizontal scrolling behavior if needed
    return SelectableText.rich(
      TextSpan(
        text: text,
        style: textStyle,
      ),
      showCursor: false,
      strutStyle: StrutStyle(
        fontSize: style.fontSize,
        height: style.height,
        forceStrutHeight: true,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      // These layout settings ensure proper handling of whitespace
      textWidthBasis: TextWidthBasis.longestLine,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      // Don't constrain vertical size
      maxLines: null,
      minLines: null,
      // Ensure proper scrolling behavior
      scrollPhysics: const NeverScrollableScrollPhysics(),
      selectionControls: selectionControls,
      onSelectionChanged: (selection, _) {
        if (onSelectionChanged != null) {
          onSelectionChanged!(selection);
        }
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
    );
  }
}

class NoisePainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double density;
  final math.Random random = math.Random(42); // Fixed seed for consistent pattern

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
    // Show a temporary small indicator that the link is being processed
    final OverlayEntry loadingEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 20,
        right: 20,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Opening link...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // Show the loading indicator
    if (context.mounted) {
      Overlay.of(context).insert(loadingEntry);
    }
    
    // Check if we can launch the URL
    final canLaunch = await url_launcher.canLaunchUrl(uri);
    
    // Remove the loading indicator
    loadingEntry.remove();
    
    if (canLaunch) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    } else {
      // Show a toast notification if the URL can't be launched
      if (context.mounted) {
        _showGlobalToast(context, 'Could not open $href', isError: true);
      }
    }
  } catch (e) {
    // Show error in toast notification
    if (context.mounted) {
      _showGlobalToast(context, 'Error opening link: $e', isError: true);
    }
  }
}

// Helper function to show a global toast notification
void _showGlobalToast(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.of(context);
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  
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
            color: isDark ? Colors.grey[850] : Colors.white,
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
                isError ? Icons.error_outline : Icons.info_outline,
                color: isError ? theme.colorScheme.error : theme.colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
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
    final primaryColor = widget.theme.colorScheme.primary;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.only(left: 2.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Shadow/glow effect
              Transform.scale(
                scale: _pulseAnimation.value * 1.2,
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(_opacityAnimation.value * 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              // Main cursor dot
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor,
                        primaryColor.withOpacity(0.8),
                      ],
                    ),
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
            ],
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

// Create a custom HighlightView wrapper that preserves whitespace exactly
class PreservedWhitespaceHighlightView extends StatelessWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final TextStyle textStyle;
  final EdgeInsets padding;

  const PreservedWhitespaceHighlightView({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.textStyle, // This should be GoogleFonts.firaCode which is already monospace
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    // We use firaCode which is a monospace font perfect for code. The fontFeatures.tabularFigures() 
    // ensures all characters take up exactly the same width, preserving code indentation.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: IntrinsicWidth(
            child: HighlightView(
              code,
              language: language,
              theme: theme,
              textStyle: textStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              padding: padding,
            ),
          ),
        );
      },
    );
  }
}
