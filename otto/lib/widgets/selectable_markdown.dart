import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show AdaptiveTextSelectionToolbar;

/// A block-level markdown renderer that supports continuous selection across all elements
/// while preserving syntax highlighting and proper markdown styling.
class SelectableMarkdown extends StatelessWidget {
  final String data;
  final TextStyle? baseStyle;
  final bool isDark;
  final EdgeInsets contentPadding;
  final bool enableSelectionToolbar;
  final bool enableInteractiveSelection;
  final int? maxLines;
  final TextOverflow overflow;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final EdgeInsets textSelectionPadding;

  const SelectableMarkdown({
    Key? key,
    required this.data,
    this.baseStyle,
    required this.isDark,
    this.contentPadding = EdgeInsets.zero,
    this.enableSelectionToolbar = true,
    this.enableInteractiveSelection = true,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.focusNode,
    this.scrollController,
    this.textSelectionPadding = const EdgeInsets.symmetric(horizontal: 8.0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Parse markdown into text and widget blocks
    return _buildMarkdownContent(context);
  }

  Widget _buildMarkdownContent(BuildContext context) {
    final theme = Theme.of(context);
    final processedData = _preprocessContent(data);
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    
    // Extract code blocks for separate rendering
    final codeBlocks = <Map<String, dynamic>>[];
    final processedNodes = _preprocessNodes(document.parse(processedData), codeBlocks);
    
    // Build the content using SelectableText.rich for better selection
    return Padding(
      padding: contentPadding,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          overscroll: false,
          physics: const ClampingScrollPhysics(),
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: MaterialTextSelectionControls(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main text content
              SelectableText.rich(
                TextSpan(
                  children: _buildTextSpans(processedNodes, context, theme),
                  style: baseStyle ?? theme.textTheme.bodyLarge!.copyWith(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
              // Add code blocks as separate widgets
              ...codeBlocks.map((block) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildCodeBlock(context, block['code'], block['language']),
              )),
            ],
          ),
        ),
      ),
    );
  }

  String _preprocessContent(String content) {
    // Normalize line endings
    String processed = content.replaceAll('\r\n', '\n');
    
    // Replace multiple newlines with just two (for paragraph spacing)
    processed = processed.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    // Trim trailing whitespace from each line
    processed = processed.split('\n').map((line) => line.trimRight()).join('\n');
    
    // Remove trailing newlines
    processed = processed.trimRight();
    
    return processed;
  }

  List<md.Node> _preprocessNodes(List<md.Node> nodes, List<Map<String, dynamic>> codeBlocks) {
    final result = <md.Node>[];
    
    for (final node in nodes) {
      if (node is md.Element && node.tag == 'pre' && node.children!.isNotEmpty && node.children!.first is md.Element) {
        final codeNode = node.children!.first as md.Element;
        final language = codeNode.attributes['class']?.replaceFirst('language-', '') ?? '';
        final code = codeNode.textContent;
        
        codeBlocks.add({
          'language': language,
          'code': code,
        });
        
        // Add a placeholder with minimal spacing
        final placeholder = md.Element('p', [md.Text('\n')]);
        result.add(placeholder);
      } else {
        result.add(node);
      }
    }
    
    return result;
  }

  List<InlineSpan> _buildTextSpans(List<md.Node> nodes, BuildContext context, ThemeData theme) {
    final spans = <InlineSpan>[];
    
    for (final node in nodes) {
      if (node is md.Element) {
        switch (node.tag) {
          case 'h1':
            spans.add(_buildHeadingSpan(node.textContent, 1, context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'h2':
            spans.add(_buildHeadingSpan(node.textContent, 2, context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'h3':
            spans.add(_buildHeadingSpan(node.textContent, 3, context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'p':
            spans.addAll(_processInlineElements(node.children!, context, theme, parentTag: node.tag));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'ul':
          case 'ol':
            spans.addAll(_buildListSpans(node, context, theme));
            spans.add(const TextSpan(text: '\n'));
            break;
          case 'li':
            final isOrdered = node.tag == 'ol';
            final index = int.tryParse(node.attributes['index'] ?? '') ?? 1;
            spans.add(TextSpan(text: isOrdered ? '$index. ' : '• '));
            spans.addAll(_processInlineElements(node.children!, context, theme, parentTag: node.tag));
            spans.add(const TextSpan(text: '\n'));
            break;
          case 'code':
            if (node.tag != 'pre') {
              spans.add(_buildInlineCodeSpan(node.textContent, context, theme));
            }
            break;
          case 'a':
            spans.add(_buildLinkSpan(node.textContent, node.attributes['href'] ?? '', context, theme));
            break;
          case 'strong':
            spans.add(TextSpan(
              text: node.textContent,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ));
            break;
          case 'em':
            spans.add(TextSpan(
              text: node.textContent,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ));
            break;
          case 'blockquote':
            spans.add(_buildBlockquoteSpan(node, context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'hr':
            spans.add(_buildHorizontalRuleSpan(context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          default:
            spans.addAll(_processInlineElements(node.children ?? [], context, theme, parentTag: node.tag));
            break;
        }
      } else if (node is md.Text) {
        spans.add(TextSpan(text: node.text));
      }
    }
    
    return spans;
  }

  List<InlineSpan> _processInlineElements(List<md.Node> nodes, BuildContext context, ThemeData theme, {String? parentTag}) {
    final spans = <InlineSpan>[];
    
    for (final node in nodes) {
      if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
            spans.add(TextSpan(
              text: node.textContent,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ));
            break;
          case 'em':
            spans.add(TextSpan(
              text: node.textContent,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ));
            break;
          case 'code':
            if (parentTag != 'pre') {
              spans.add(_buildInlineCodeSpan(node.textContent, context, theme));
            }
            break;
          case 'a':
            spans.add(_buildLinkSpan(node.textContent, node.attributes['href'] ?? '', context, theme));
            break;
          case 'br':
            spans.add(const TextSpan(text: '\n'));
            break;
          default:
            if (node.children != null) {
              spans.addAll(_processInlineElements(node.children!, context, theme, parentTag: node.tag));
            } else {
              spans.add(TextSpan(text: node.textContent));
            }
            break;
        }
      } else if (node is md.Text) {
        spans.add(TextSpan(text: node.text));
      }
    }
    
    return spans;
  }

  TextSpan _buildHeadingSpan(String text, int level, BuildContext context, ThemeData theme) {
    double fontSize;
    FontWeight fontWeight;
    
    switch (level) {
      case 1:
        fontSize = 24.0;
        fontWeight = FontWeight.bold;
        break;
      case 2:
        fontSize = 20.0;
        fontWeight = FontWeight.bold;
        break;
      case 3:
        fontSize = 18.0;
        fontWeight = FontWeight.bold;
        break;
      default:
        fontSize = 16.0;
        fontWeight = FontWeight.bold;
    }
    
    return TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.4,
      ),
    );
  }

  TextSpan _buildInlineCodeSpan(String text, BuildContext context, ThemeData theme) {
    return TextSpan(
      text: text,
      style: GoogleFonts.firaCode(
        fontSize: theme.textTheme.bodyMedium!.fontSize,
        color: isDark ? Colors.pink[100] : theme.colorScheme.primary,
        backgroundColor: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
        height: 1.5,
      ),
    );
  }

  TextSpan _buildLinkSpan(String text, String url, BuildContext context, ThemeData theme) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
        },
    );
  }

  List<InlineSpan> _buildListSpans(md.Element list, BuildContext context, ThemeData theme) {
    final spans = <InlineSpan>[];
    final isOrdered = list.tag == 'ol';
    int index = 1;
    
    for (final child in list.children!) {
      if (child is md.Element && child.tag == 'li') {
        spans.add(TextSpan(text: isOrdered ? '${index++}. ' : '• '));
        spans.addAll(_processInlineElements(child.children!, context, theme, parentTag: child.tag));
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return spans;
  }

  TextSpan _buildBlockquoteSpan(md.Element blockquote, BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return TextSpan(
      children: [
        TextSpan(
          children: _processInlineElements(blockquote.children!, context, theme),
          style: TextStyle(
            color: isDark ? Colors.grey[300] : Colors.grey[800],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
      style: TextStyle(
        background: Paint()
          ..color = isDark 
              ? Colors.grey[900]!.withOpacity(0.18) 
              : Colors.grey[300]!.withOpacity(0.18)
          ..style = PaintingStyle.fill,
      ),
    );
  }

  TextSpan _buildHorizontalRuleSpan(BuildContext context, ThemeData theme) {
    return const TextSpan(
      text: '───────────────────────────────────',
      style: TextStyle(
        color: Colors.grey,
        fontWeight: FontWeight.w200,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String language) {
    final theme = Theme.of(context);
    final containerColor = isDark ? const Color(0xFF282C34) : const Color(0xFFF6F8FA);
    final headerBgColor = isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFF6F8FA);
    
    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code block header with language and copy button
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
                  language.isEmpty ? 'plain text' : language,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: isDark ? const Color(0xFF9DA5B4) : const Color(0xFF383A42),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Keyboard shortcut hint
                    if (language.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Ctrl+C to copy',
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: isDark ? const Color(0xFF9DA5B4).withOpacity(0.7) : const Color(0xFF383A42).withOpacity(0.7),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    // Copy button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: code));
                        },
                        child: Icon(
                          Icons.content_copy_rounded,
                          size: 16,
                          color: isDark ? const Color(0xFF9DA5B4) : const Color(0xFF383A42),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Code content with syntax highlighting and selection overlay
          Material(
            color: contentBgColor,
            child: Stack(
              children: [
                // Visual syntax highlighting (VISIBLE)
                HighlightView(
                  code,
                  language: language.isEmpty ? 'plaintext' : language,
                  theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                  textStyle: GoogleFonts.firaCode(
                    fontSize: theme.textTheme.bodyMedium!.fontSize,
                    height: 1.5,
                  ),
                  padding: const EdgeInsets.all(16),
                ),
                // Transparent overlay for selection - using SelectableText directly
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.transparent,
                    child: SelectableText(
                      code,
                      style: GoogleFonts.firaCode(
                        fontSize: theme.textTheme.bodyMedium!.fontSize,
                        height: 1.5,
                        color: Colors.transparent, // Make text transparent
                      ),
                      enableInteractiveSelection: true,
                      showCursor: true,
                      cursorWidth: 1.5,
                      cursorColor: isDark ? Colors.white70 : Colors.black54,
                      contextMenuBuilder: (context, editableTextState) {
                        return AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: editableTextState,
                        );
                      },
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
}
