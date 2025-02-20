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

  /// Renders the main message content.
  /// For non-user messages, markdown is rendered (which may include code blocks).
  Widget _buildMessageContent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (widget.message.isUser) {
      return SelectableText(
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
    }

    String content =
        widget.isStreaming ? widget.streamedContent : widget.message.content;

    // Wrap XML tags with inline code formatting.
    content = content.replaceAllMapped(
      RegExp(r'<[^>]+>'),
      (match) => '`${match.group(0)}`',
    );

    content = content.replaceAll(RegExp(r'\r\n|\r'), '\n');
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          constraints: BoxConstraints(
            minHeight: 24.0,
            maxWidth: constraints.maxWidth,
          ),
          child: SelectableMarkdown(
            data: content,
            isDark: isDark,
            baseStyle: theme.textTheme.bodyLarge!.copyWith(
              color: isDark ? Colors.white : theme.colorScheme.onSurface,
              height: 1.5,
            ),
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
              // Wrap the entire message in a GestureDetector to clear inner focus on tap.
              child: GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
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
                                    : [
                                        (isDark
                                            ? theme.colorScheme.surface.darken(0.1)
                                            : theme.colorScheme.surface),
                                        (isDark
                                            ? theme.colorScheme.surface
                                                .darken(0.05)
                                                .withOpacity(0.9)
                                            : theme.colorScheme.surface
                                                .withOpacity(0.9)),
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
                          icon: const Icon(
                            Icons.content_copy_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: widget.message.content));
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Return the content directly without wrapping it in global Shortcuts/Actions.
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

  Widget _buildCodeContent(
      String code, String language, ThemeData theme) {
    return CodeContentWidget(
      code: code,
      language: language,
      theme: theme,
      isDark: isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<InlineSpan> buildFormattedContent() {
      final List<InlineSpan> spans = [];
      final document = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      final nodes = document.parse(data);

      void processNode(md.Node node,
          {TextStyle? currentStyle, int listLevel = 0}) {
        if (node is md.Text) {
          spans.add(TextSpan(
            text: node.text,
            style: currentStyle ?? baseStyle,
          ));
        } else if (node is md.Element) {
          TextStyle? newStyle;
          String? prefix;
          String? suffix;
          switch (node.tag) {
            case 'h1':
              newStyle = theme.textTheme.headlineMedium!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                height: 1.5,
              );
              suffix = '\n\n';
              break;
            case 'h2':
              newStyle = theme.textTheme.headlineSmall!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                height: 1.5,
              );
              suffix = '\n\n';
              break;
            case 'h3':
              newStyle = theme.textTheme.titleLarge!.copyWith(
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
                height: 1.5,
              );
              suffix = '\n\n';
              break;
            case 'p':
              if (node != nodes.last) {
                suffix = '\n\n';
              }
              break;
            case 'strong':
              newStyle =
                  (currentStyle ?? baseStyle)?.copyWith(fontWeight: FontWeight.bold);
              break;
            case 'em':
              newStyle =
                  (currentStyle ?? baseStyle)?.copyWith(fontStyle: FontStyle.italic);
              break;
            case 'code':
              if (node.textContent.startsWith('<') &&
                  node.textContent.endsWith('>')) {
                newStyle = theme.textTheme.bodyLarge!.copyWith(
                  color: isDark
                      ? Colors.white.withOpacity(0.9)
                      : theme.colorScheme.onSurface.withOpacity(0.9),
                  height: 1.5,
                );
              } else {
                newStyle = GoogleFonts.firaCode(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  color: isDark
                      ? Colors.white.withOpacity(0.9)
                      : theme.colorScheme.primary,
                  backgroundColor: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
                  height: 1.5,
                );
              }
              break;
            case 'pre':
              if (node.children?.first is md.Element &&
                  (node.children?.first as md.Element).tag == 'code') {
                final codeNode = node.children!.first as md.Element;
                final language = codeNode.attributes['class']?.substring(9) ?? '';
                final code = codeNode.textContent;
                final contentBgColor = isDark
                    ? const Color(0xFF282C34)
                    : const Color(0xFFFAFAFA);
                spans.add(WidgetSpan(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4, bottom: 0),
                    decoration: BoxDecoration(
                      color: contentBgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCodeBlockHeader(context, language, code),
                        _buildCodeContent(code, language, theme),
                      ],
                    ),
                  ),
                ));
                spans.add(const TextSpan(text: '\n'));
                return;
              }
              break;
            case 'li':
              final bullet = listLevel > 0
                  ? '  ' * (listLevel - 1) + '• '
                  : '• ';
              prefix = bullet;
              suffix = '\n';
              break;
            case 'ul':
              for (final child in node.children!) {
                processNode(child,
                    currentStyle: currentStyle, listLevel: listLevel + 1);
              }
              if (listLevel == 0 && node != nodes.last) {
                spans.add(TextSpan(text: '\n'));
              }
              return;
            case 'ol':
              int index = 1;
              for (final child in node.children!) {
                if (child is md.Element && child.tag == 'li') {
                  spans.add(TextSpan(
                    text: '  ' * listLevel + '$index. ',
                    style: currentStyle ?? baseStyle,
                  ));
                  processNode(child,
                      currentStyle: currentStyle, listLevel: listLevel + 1);
                  index++;
                }
              }
              if (listLevel == 0 && node != nodes.last) {
                spans.add(TextSpan(text: '\n'));
              }
              return;
            case 'a':
              final url = node.attributes['href'] ?? '';
              newStyle = (currentStyle ?? baseStyle)?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              );
              break;
          }
          if (prefix != null) {
            spans.add(TextSpan(
              text: prefix,
              style: currentStyle ?? baseStyle,
            ));
          }
          for (final child in node.children!) {
            processNode(child, currentStyle: newStyle ?? currentStyle);
          }
          if (suffix != null) {
            spans.add(TextSpan(
              text: suffix,
              style: currentStyle ?? baseStyle,
            ));
          }
        }
      }
      for (final node in nodes) {
        processNode(node);
      }
      return spans;
    }
    return SelectableText.rich(
      TextSpan(
        children: buildFormattedContent(),
      ),
      style: baseStyle,
    );
  }
}

/// ---------------------------------------------------------------------------
///
/// CodeContentWidget
///
/// A simple widget that displays highlighted code.
/// It is used in code blocks within the message and in the markdown renderer.
/// Updated to include a transparent selectable overlay wrapped in a Focus widget
/// to allow code selection via keyboard shortcuts.
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // Visual layer with syntax highlighting.
          HighlightView(
            code,
            language: language.isEmpty ? 'plaintext' : language,
            theme: isDarkTheme ? atomOneDarkTheme : atomOneLightTheme,
            textStyle: GoogleFonts.firaCode(
              fontSize: theme.textTheme.bodyMedium!.fontSize,
              height: 1.5,
            ),
            padding: EdgeInsets.zero,
          ),
          // Transparent selectable layer overlay wrapped in Focus.
          Positioned.fill(
            child: Focus(
              child: SelectableText(
                code,
                style: GoogleFonts.firaCode(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  height: 1.5,
                  color: Colors.transparent, // Invisible but selectable.
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
