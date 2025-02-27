import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter/cupertino.dart' show AdaptiveTextSelectionToolbar;

/// A block-level markdown renderer that supports continuous selection across all elements
/// while preserving syntax highlighting and proper markdown styling.
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

  @override
  Widget build(BuildContext context) {
    // Parse markdown into text and widget blocks
    return SelectableRegion(
      focusNode: FocusNode(),
      selectionControls: MaterialTextSelectionControls(),
      child: _buildMarkdownContent(context),
    );
  }

  Widget _buildMarkdownContent(BuildContext context) {
    final theme = Theme.of(context);
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    final nodes = document.parse(data);

    // Extract code blocks for separate rendering
    final codeBlocks = <Map<String, dynamic>>[];
    final processedNodes = _preprocessNodes(nodes, codeBlocks);
    
    // Build rich text with text spans for inline styling
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: _buildTextSpans(processedNodes, context, theme),
            style: baseStyle ?? theme.textTheme.bodyLarge!.copyWith(
              color: isDark ? Colors.white : theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),
          softWrap: true,
        ),
        // Add code blocks as separate widgets
        ...codeBlocks.map((block) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _buildCodeBlock(context, block['code'], block['language']),
        )),
      ],
    );
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
        
        // Add a placeholder node
        final placeholder = md.Element('p', [md.Text('\n\n')]);
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
            spans.addAll(_processInlineElements(node.children!, context, theme));
            spans.add(const TextSpan(text: '\n\n'));
            break;
          case 'ul':
          case 'ol':
            spans.addAll(_buildListSpans(node, context, theme));
            spans.add(const TextSpan(text: '\n'));
            break;
          case 'li':
            final isOrdered = node.parent?.tag == 'ol';
            final index = int.tryParse(node.attributes['index'] ?? '') ?? 1;
            spans.add(TextSpan(text: isOrdered ? '$index. ' : '• '));
            spans.addAll(_processInlineElements(node.children!, context, theme));
            spans.add(const TextSpan(text: '\n'));
            break;
          case 'code':
            if (node.parent?.tag != 'pre') {
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
          default:
            spans.addAll(_processInlineElements(node.children ?? [], context, theme));
            break;
        }
      } else if (node is md.Text) {
        spans.add(TextSpan(text: node.text));
      }
    }
    
    return spans;
  }

  List<InlineSpan> _processInlineElements(List<md.Node> nodes, BuildContext context, ThemeData theme) {
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
            spans.add(_buildInlineCodeSpan(node.textContent, context, theme));
            break;
          case 'a':
            spans.add(_buildLinkSpan(node.textContent, node.attributes['href'] ?? '', context, theme));
            break;
          default:
            if (node.children != null) {
              spans.addAll(_processInlineElements(node.children!, context, theme));
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
    final fontSize = switch (level) {
      1 => 24.0,
      2 => 20.0,
      3 => 18.0,
      _ => 16.0,
    };
    
    return TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : theme.colorScheme.onSurface,
        height: 1.5,
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
      recognizer: null, // We don't add gesture recognizer as it interferes with selection
    );
  }

  List<InlineSpan> _buildListSpans(md.Element listElement, BuildContext context, ThemeData theme) {
    final spans = <InlineSpan>[];
    final isOrdered = listElement.tag == 'ol';
    var index = 1;
    
    for (final child in listElement.children!) {
      if (child is md.Element && child.tag == 'li') {
        spans.add(TextSpan(text: isOrdered ? '${index++}. ' : '• '));
        spans.addAll(_processInlineElements(child.children!, context, theme));
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return spans;
  }

  Widget _buildCodeBlock(BuildContext context, String code, String language) {
    final theme = Theme.of(context);
    final headerBgColor = isDark ? const Color(0xFF21252B) : const Color(0xFFF0F0F0);
    final contentBgColor = isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA);
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: contentBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Code block header
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
                          final cleanCode = code
                              .replaceAll(RegExp(r'\r\n|\r'), '\n')
                              .replaceAll(RegExp(r'\n\s*\n'), '\n\n');
                          Clipboard.setData(ClipboardData(text: cleanCode));
                          
                          // Show feedback if we can access the scaffold
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Code copied to clipboard'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              width: 200,
                            ),
                          );
                        },
                        child: Icon(
                          Icons.content_copy_rounded,
                          size: 18,
                          color: isDark ? const Color(0xFF9DA5B4) : const Color(0xFF383A42),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Code content with proper syntax highlighting
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
                          color: Colors.transparent, // Make text transparent
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
                      ),
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
