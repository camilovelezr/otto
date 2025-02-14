import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';  // Add this import for ImageFilter
import '../models/llm_model.dart';

class ModelSelector extends StatefulWidget {
  final List<LLMModel> models;
  final LLMModel? selectedModel;
  final Function(LLMModel) onModelSelected;

  const ModelSelector({
    Key? key,
    required this.models,
    required this.selectedModel,
    required this.onModelSelected,
  }) : super(key: key);

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<LLMModel>> _filteredModelsNotifier = ValueNotifier([]);
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;
  int _focusedIndex = -1;
  
  @override
  void initState() {
    super.initState();
    _filteredModelsNotifier.value = widget.models;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5)
        .animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_isOpen) {
        _showOverlay();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    _animationController.dispose();
    _filteredModelsNotifier.dispose();
    _scrollController.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _scrollToFocusedItem() {
    if (_focusedIndex < 0) return;
    
    final itemHeight = 44.0; // Approximate height of each item
    final scrollPosition = _focusedIndex * itemHeight;
    
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _filterModels(String query) {
    _filteredModelsNotifier.value = widget.models
        .where((model) =>
            model.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    _focusedIndex = -1;
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'ollama':
        return const Color(0xFF10B981); // Emerald green
      case 'openai':
        return const Color(0xFF6366F1); // Indigo
      case 'groq':
        return const Color(0xFF3B82F6); // Blue
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'ollama':
        return Icons.terminal_outlined;
      case 'openai':
        return Icons.psychology_outlined;
      case 'groq':
        return Icons.bolt_outlined;
      default:
        return Icons.question_mark_outlined;
    }
  }

  void _showOverlay() {
    _isOpen = true;
    _filteredModelsNotifier.value = widget.models;
    _animationController.forward();
    _overlayEntry?.remove();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {});
  }

  void _hideOverlay() {
    _isOpen = false;
    _filteredModelsNotifier.value = widget.models;
    _animationController.reverse();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _searchController.clear();
    setState(() {});
  }

  void _updateOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    final theme = Theme.of(context);

    return OverlayEntry(
      maintainState: true,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideOverlay,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0.0, size.height + 4.0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                    minWidth: size.width,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: RawKeyboardListener(
                          focusNode: FocusNode(),
                          onKey: (event) {
                            if (event is RawKeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                setState(() {
                                  _focusedIndex = (_focusedIndex + 1) % _filteredModelsNotifier.value.length;
                                  _scrollToFocusedItem();
                                });
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                setState(() {
                                  _focusedIndex = _focusedIndex <= 0 
                                      ? _filteredModelsNotifier.value.length - 1 
                                      : _focusedIndex - 1;
                                  _scrollToFocusedItem();
                                });
                              }
                            }
                          },
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: _filterModels,
                            focusNode: _focusNode,
                            onSubmitted: (value) {
                              if (_focusedIndex >= 0) {
                                _handleModelSelection(_filteredModelsNotifier.value[_focusedIndex]);
                              }
                            },
                            onEditingComplete: () {
                              if (_focusedIndex >= 0) {
                                _handleModelSelection(_filteredModelsNotifier.value[_focusedIndex]);
                              }
                            },
                            textInputAction: TextInputAction.done,
                            keyboardType: TextInputType.text,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              hintText: 'Search models...',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      Flexible(
                        child: ValueListenableBuilder<List<LLMModel>>(
                          valueListenable: _filteredModelsNotifier,
                          builder: (context, filteredModels, _) {
                            if (filteredModels.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No models found',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            return Flexible(
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                shrinkWrap: true,
                                itemCount: filteredModels.length,
                                itemBuilder: (context, index) {
                                  final model = filteredModels[index];
                                  final isSelected = model.name == widget.selectedModel?.name;
                                  final isFocused = index == _focusedIndex;
                                  
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _handleModelSelection(model),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected || isFocused
                                              ? theme.colorScheme.primary.withOpacity(0.1)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _getPlatformIcon(model.platform),
                                              size: 16,
                                              color: _getPlatformColor(model.platform),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                model.name,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  color: theme.colorScheme.onSurface,
                                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                            if (isSelected) ...[
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.check,
                                                size: 16,
                                                color: theme.colorScheme.primary,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
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
      ),
    );
  }

  void _handleModelSelection(LLMModel model) async {
    widget.onModelSelected(model);
    _hideOverlay();
    _searchController.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (_isOpen) {
                _hideOverlay();
              } else {
                _showOverlay();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _getPlatformIcon(widget.selectedModel?.platform ?? ''),
                    size: 16,
                    color: _getPlatformColor(widget.selectedModel?.platform ?? ''),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.selectedModel?.name ?? 'Select a model',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RotationTransition(
                    turns: _rotationAnimation,
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF9D5CFF).withOpacity(0.1),
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
              valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF9D5CFF)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Thinking...',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF9D5CFF),
            ),
          ),
        ],
      ),
    );
  }
} 