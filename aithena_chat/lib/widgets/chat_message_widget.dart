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

  Widget _buildCodeBlock(ThemeData theme, String code, String? language) {
    final isDark = theme.brightness == Brightness.dark;
    final headerBgColor = isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
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
                        // Clean up any potential extraneous characters in line breaks
                        final cleanCode = code.replaceAll(RegExp(r'\r\n|\r'), '\n')
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
            child: Stack(
              children: [
                HighlightView(
                  code.replaceAll(RegExp(r'\r\n|\r'), '\n')
                      .replaceAll(RegExp(r'\n\s*\n'), '\n\n'),
                  language: language ?? 'plaintext',
                  theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                  textStyle: GoogleFonts.firaCode(
                    fontSize: 14,
                    height: 1.5,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Positioned.fill(
                  child: SelectableText(
                    code.replaceAll(RegExp(r'\r\n|\r'), '\n')
                        .replaceAll(RegExp(r'\n\s*\n'), '\n\n'),
                    style: GoogleFonts.firaCode(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
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

  Widget _buildMessageContent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    if (widget.message.isUser) {
      return SelectableText(
        widget.message.content,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: isDark 
              ? Colors.white
              : theme.colorScheme.onSurface,
          height: 1.5,
          shadows: isDark ? [
            const Shadow(
              color: Colors.black26,
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ] : null,
        ),
      );
    }

    // For assistant messages, preserve XML tags by wrapping them in code blocks
    String content = widget.isStreaming ? widget.streamedContent : widget.message.content;
    
    // Replace XML tags with code-wrapped versions
    content = content.replaceAllMapped(
      RegExp(r'<[^>]+>'),
      (match) => '`${match.group(0)}`'
    );

    // Clean up line endings for consistent display
    content = content.replaceAll(RegExp(r'\r\n|\r'), '\n');
    
    // Ensure proper spacing between paragraphs without adding extraneous characters
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    if (widget.isStreaming) {
      // Handle code blocks with proper spacing
      final codeBlockRegex = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
      content = content.replaceAllMapped(codeBlockRegex, (match) {
        final language = match.group(1) ?? '';
        final code = match.group(2) ?? '';
        return '\n```$language\n${code.trim()}\n```\n';
      });

      // Handle inline code
      content = content.replaceAllMapped(
        RegExp(r'`([^`]+)`'),
        (match) => '`${match.group(1)?.trim() ?? ''}`'
      );

      // Handle headers
      content = content.replaceAllMapped(
        RegExp(r'^(#{1,6})\s*(.+)$', multiLine: true),
        (match) => '\n${match.group(1)} ${match.group(2)?.trim()}\n'
      );

      // Handle lists
      content = content.replaceAllMapped(
        RegExp(r'^(\s*[-*+])\s*(.+)$', multiLine: true),
        (match) => '${match.group(1)} ${match.group(2)?.trim()}\n'
      );

      // Ensure content ends with newline
      if (!content.endsWith('\n')) {
        content = '$content\n';
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          constraints: BoxConstraints(
            minHeight: 24.0,
            maxWidth: constraints.maxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...MarkdownContentBuilder(theme, isDark).buildContent(content),
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
    final isUser = widget.message.isUser;
    final isDark = theme.brightness == Brightness.dark;

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
                vertical: 2,
              ),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                      (isDark
                                          ? theme.colorScheme.primary.withOpacity(0.25)
                                          : theme.colorScheme.primary.withOpacity(0.1)),
                                      (isDark
                                          ? theme.colorScheme.secondary.withOpacity(0.2)
                                          : theme.colorScheme.secondary.withOpacity(0.1)),
                                    ]
                                  : [
                                      (isDark
                                          ? theme.colorScheme.surface.darken(0.1)
                                          : theme.colorScheme.surface),
                                      (isDark
                                          ? theme.colorScheme.surface.darken(0.05).withOpacity(0.9)
                                          : theme.colorScheme.surface.withOpacity(0.9)),
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
                                color: isDark
                                    ? theme.shadowColor.withOpacity(0.2)
                                    : theme.shadowColor.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: _buildMessageContent(theme),
                        ),
                      ),
                    ],
                  ),
                  if (!isUser && !widget.isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: IconButton(
                        icon: const Icon(Icons.content_copy_rounded, size: 20),
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: widget.message.content),
                        ),
                        tooltip: 'Copy message',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? theme.colorScheme.surface.darken(0.1).withOpacity(0.8)
                              : theme.colorScheme.surface.withOpacity(0.8),
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(32, 32),
                        ),
                      ),
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

class CustomParagraphBuilder extends MarkdownElementBuilder {
  final TextStyle? textStyle;

  CustomParagraphBuilder({this.textStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return SelectableText(
      element.textContent,
      style: textStyle ?? preferredStyle,
    );
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

    final isInline = element.tag == 'code' && !element.attributes.containsKey('class');

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
            backgroundColor: theme.colorScheme.surface.withOpacity(0.7),
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

// Simplify content processor to only handle code blocks
String _processContent(String content) {
  final lines = content.split('\n');
  final processedLines = <String>[];
  bool insideCodeBlock = false;

  for (var line in lines) {
    if (line.startsWith('```')) {
      insideCodeBlock = !insideCodeBlock;
    }
    // Preserve all content exactly as is
    processedLines.add(line);
  }

  // Ensure code blocks are properly closed
  if (insideCodeBlock) {
    processedLines.add('```');
  }

  return processedLines.join('\n');
}

class MarkdownContentBuilder {
  final ThemeData theme;
  final bool isDark;

  MarkdownContentBuilder(this.theme, this.isDark);

  Widget _buildCodeBlock(ThemeData theme, String code, String? language) {
    final headerBgColor = isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
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
                        final cleanCode = code.replaceAll(RegExp(r'\r\n|\r'), '\n')
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
            child: Stack(
              children: [
                HighlightView(
                  code.replaceAll(RegExp(r'\r\n|\r'), '\n')
                      .replaceAll(RegExp(r'\n\s*\n'), '\n\n'),
                  language: language ?? 'plaintext',
                  theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                  textStyle: GoogleFonts.firaCode(
                    fontSize: 14,
                    height: 1.5,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Positioned.fill(
                  child: SelectableText(
                    code.replaceAll(RegExp(r'\r\n|\r'), '\n')
                        .replaceAll(RegExp(r'\n\s*\n'), '\n\n'),
                    style: GoogleFonts.firaCode(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> buildContent(String content) {
    final List<Widget> widgets = [];
    final paragraphs = content.split(RegExp(r'\n{2,}'));

    for (var paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;

      if (paragraph.startsWith('```')) {
        // Handle code blocks
        final match = RegExp(r'```(\w*)\n([\s\S]*?)```').firstMatch(paragraph);
        if (match != null) {
          final language = match.group(1) ?? '';
          final code = match.group(2) ?? '';
          widgets.add(_buildCodeBlock(theme, code.trim(), language));
          widgets.add(const SizedBox(height: 8));
          continue;
        }
      }

      if (paragraph.startsWith('#')) {
        // Handle headers
        final level = paragraph.indexOf(' ');
        if (level > 0 && level <= 6) {
          final text = paragraph.substring(level + 1).trim();
          widgets.add(_buildHeader(text, level));
          widgets.add(const SizedBox(height: 8));
          continue;
        }
      }

      if (paragraph.trim().startsWith(RegExp(r'[-*+]'))) {
        // Handle lists
        final items = paragraph.split('\n');
        widgets.add(_buildList(items));
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // Handle regular paragraphs and inline elements
      widgets.add(_buildParagraph(paragraph));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  Widget _buildParagraph(String text) {
    // Handle inline code and other inline elements
    final spans = <InlineSpan>[];
    final parts = text.split(RegExp(r'(`[^`]+`)|(<[^>]+>)'));
    
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;

      if (parts[i].startsWith('`') && parts[i].endsWith('`')) {
        // Inline code
        spans.add(TextSpan(
          text: parts[i].substring(1, parts[i].length - 1),
          style: GoogleFonts.firaCode(
            fontSize: theme.textTheme.bodyMedium!.fontSize,
            color: isDark ? Colors.white.withOpacity(0.9) : theme.colorScheme.primary,
            backgroundColor: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
            height: 1.5,
            letterSpacing: 0,
          ),
        ));
      } else if (parts[i].startsWith('<') && parts[i].endsWith('>')) {
        // XML tags
        spans.add(TextSpan(
          text: parts[i],
          style: theme.textTheme.bodyLarge!.copyWith(
            color: isDark ? Colors.white.withOpacity(0.9) : theme.colorScheme.onSurface.withOpacity(0.9),
            height: 1.5,
          ),
        ));
      } else {
        // Regular text
        spans.add(TextSpan(
          text: parts[i],
          style: theme.textTheme.bodyLarge!.copyWith(
            color: isDark ? Colors.white : theme.colorScheme.onSurface,
            height: 1.5,
          ),
        ));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  Widget _buildHeader(String text, int level) {
    TextStyle style;
    switch (level) {
      case 1:
        style = theme.textTheme.headlineMedium!;
        break;
      case 2:
        style = theme.textTheme.headlineSmall!;
        break;
      case 3:
        style = theme.textTheme.titleLarge!;
        break;
      default:
        style = theme.textTheme.titleMedium!;
    }

    return SelectableText(
      text,
      style: style.copyWith(
        color: isDark ? Colors.white : theme.colorScheme.onSurface,
        height: 1.5,
      ),
    );
  }

  Widget _buildList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final match = RegExp(r'^(\s*[-*+])\s*(.+)$').firstMatch(item);
        if (match == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '•',
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  height: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  match.group(2)?.trim() ?? '',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
} 