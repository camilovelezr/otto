import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../theme/theme_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart' show AdaptiveTextSelectionToolbar;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

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
              theme: theme,
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
                onTap: () {
                  FocusScope.of(context).unfocus();
                },
                // A single SelectableRegion at this level wraps all content
                child: SelectableRegion(
                  focusNode: FocusNode(),
                  selectionControls: MaterialTextSelectionControls(),
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
                                          
                                          content = content.replaceAll(RegExp(r'\r\n|\r'), '\n');
                                          content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');
                                          
                                          return SelectableMarkdown(
                                            data: content,
                                            isDark: isDark,
                                            baseStyle: theme.textTheme.bodyLarge!.copyWith(
                                              color: isDark ? Colors.white : theme.colorScheme.onSurface,
                                              height: 1.5,
                                            ),
                                          );
                                        }
                                      }
                                    ),
                                  ),
                                ],
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
                                // Show feedback to user
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Message copied to clipboard'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                    width: 240,
                                  ),
                                );
                              },
                              tooltip: 'Copy message',
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? theme.colorScheme.surface
                                        .darken(0.1)
                                        .withOpacity(0.8)
                                    : theme.colorScheme.surface.withOpacity(0.8),
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

  const SelectableMarkdown({
    Key? key,
    required this.data,
    this.baseStyle,
    required this.isDark,
  }) : super(key: key);

  Widget _buildCodeBlockHeader(
      BuildContext context, String language, String code) {
    final theme = Theme.of(context);
    final headerBgColor =
        isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: headerBgColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            language.isEmpty ? 'plain text' : language,
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
                final cleanCode = code
                    .replaceAll(RegExp(r'\r\n|\r'), '\n')
                    .replaceAll(RegExp(r'\n\s*\n'), '\n\n');
                Clipboard.setData(
                    ClipboardData(text: cleanCode));
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Use Flutter's built-in MarkdownBody for better rendering
    return MarkdownBody(
      data: data,
      selectable: true,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        _handleLinkTap(context, href);
      },
      styleSheet: MarkdownStyleSheet(
        p: baseStyle ?? theme.textTheme.bodyLarge!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h1: theme.textTheme.headlineMedium!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h2: theme.textTheme.headlineSmall!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h3: theme.textTheme.titleLarge!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h4: theme.textTheme.titleMedium!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h5: theme.textTheme.titleSmall!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        h6: theme.textTheme.titleSmall!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          height: 1.5,
        ),
        strong: baseStyle?.copyWith(
          fontWeight: FontWeight.bold,
        ) ?? theme.textTheme.bodyLarge!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          height: 1.5,
        ),
        em: baseStyle?.copyWith(
          fontStyle: FontStyle.italic,
        ) ?? theme.textTheme.bodyLarge!.copyWith(
          color: isDark ? Colors.white : theme.colorScheme.onSurface,
          fontStyle: FontStyle.italic,
          height: 1.5,
        ),
        code: GoogleFonts.firaCode(
          fontSize: theme.textTheme.bodyMedium!.fontSize,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.surface.withOpacity(0.7),
          height: 1.5,
        ),
        codeblockPadding: const EdgeInsets.all(0),
        codeblockDecoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(0),
        ),
        blockquote: theme.textTheme.bodyLarge!.copyWith(
          color: isDark 
              ? Colors.white70 
              : theme.colorScheme.onSurface.withOpacity(0.8),
          height: 1.5,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isDark 
                  ? Colors.white30 
                  : theme.colorScheme.onSurface.withOpacity(0.3),
              width: 4,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 16),
      ),
      builders: {
        'code': CodeElementBuilder(theme, context, customBuilder: (code, language, isInline) {
          if (isInline) {
            return Text.rich(
              TextSpan(
                text: code,
                style: GoogleFonts.firaCode(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surface.withOpacity(0.7),
                  height: 1.5,
                  letterSpacing: 0,
                ),
              ),
              softWrap: true,
            );
          } else {
            // For code blocks, use our CodeContentWidget with syntax highlighting
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCodeBlockHeader(context, language ?? '', code),
                  CodeContentWidget(
                    code: code,
                    language: language ?? 'plaintext',
                    theme: theme,
                    isDark: isDark,
                  ),
                ],
              ),
            );
          }
        }),
      },
    );
  }
  
  void _handleLinkTap(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;
    
    final Uri uri = Uri.parse(href);
    
    try {
      final canLaunch = await url_launcher.canLaunchUrl(uri);
      if (canLaunch) {
        await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
      } else {
        // Show a snackbar if the URL can't be launched
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open $href'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Show error in snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening link: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
class CodeContentWidget extends StatelessWidget {
  final String code;
  final String language;
  final ThemeData theme;
  final bool isDark;

  const CodeContentWidget({
    Key? key,
    required this.code,
    required this.language,
    required this.theme,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = isDark;
    final contentBgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: contentBgColor,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(8),
        ),
      ),
      child: Material(
        color: contentBgColor,
        child: Stack(
          children: [
            // The visible syntax-highlighted code
            Padding(
              padding: const EdgeInsets.all(16),
              child: HighlightView(
                code,
                language: language.isEmpty ? 'plaintext' : language,
                theme: isDarkTheme ? atomOneDarkTheme : atomOneLightTheme,
                textStyle: GoogleFonts.firaCode(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  height: 1.5,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
            // Transparent overlay for selection
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.transparent,
                  child: SelectableText(
                    code,
                    style: GoogleFonts.firaCode(
                      fontSize: theme.textTheme.bodyMedium!.fontSize,
                      height: 1.5,
                      color: Colors.transparent, // Invisible but selectable text
                    ),
                    enableInteractiveSelection: true,
                    showCursor: true,
                    cursorColor: isDark ? Colors.white70 : Colors.black54,
                    focusNode: FocusNode(), // Dedicated focus node for better keyboard interaction
                    contextMenuBuilder: (context, editableTextState) {
                      return AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: editableTextState,
                      );
                    },
                    // Support for keyboard shortcuts
                    onSelectionChanged: (selection, cause) {
                      // Handle copy keyboard shortcut
                      if (selection != null && 
                          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) &&
                          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.keyC)) {
                        final selectedText = code.substring(selection.start, selection.end);
                        Clipboard.setData(ClipboardData(text: selectedText));
                      }
                    },
                  ),
                ),
              ),
            ),
            
            // Sticky copy button at top right
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark 
                    ? Colors.black.withOpacity(0.5) 
                    : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      final cleanCode = code
                          .replaceAll(RegExp(r'\r\n|\r'), '\n')
                          .replaceAll(RegExp(r'\n\s*\n'), '\n\n');
                      Clipboard.setData(ClipboardData(text: cleanCode));
                      
                      // Show feedback to user
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Code copied to clipboard'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          width: 200,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(
                        Icons.content_copy_rounded,
                        size: 16,
                        color: isDark 
                          ? Colors.white.withOpacity(0.9) 
                          : Colors.black.withOpacity(0.7),
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
