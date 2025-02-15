import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/llm_model.dart';

class ModelSelector extends StatefulWidget {
  final List<LLMModel> models;
  final LLMModel selectedModel;
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

class _ModelSelectorState extends State<ModelSelector> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _selectorFocusNode = FocusNode();
  List<LLMModel> _filteredModels = [];
  int _selectedIndex = -1;
  bool _isExpanded = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _filteredModels = _sortModels(widget.models);
    _selectorFocusNode.addListener(_handleSelectorFocus);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.dispose();
    _searchFocusNode.dispose();
    _selectorFocusNode.removeListener(_handleSelectorFocus);
    _selectorFocusNode.dispose();
    super.dispose();
  }

  void _handleSelectorFocus() {
    if (_selectorFocusNode.hasFocus && !_isExpanded) {
      setState(() {
        _isExpanded = true;
        _controller.clear();
        _filteredModels = _sortModels(widget.models);
        _selectedIndex = -1;
        _showOverlay(context);
      });
    }
  }

  List<LLMModel> _sortModels(List<LLMModel> models) {
    return models.toList()
      ..sort((a, b) {
        // Define platform priority
        const platformPriority = {
          'ollama': 1,
          'groq': 2,
          'openai': 3,
        };
        
        final priorityA = platformPriority[a.platform] ?? 999;
        final priorityB = platformPriority[b.platform] ?? 999;
        
        return priorityA.compareTo(priorityB);
      });
  }

  void _filterModels(String query) {
    setState(() {
      _filteredModels = _sortModels(widget.models
          .where((model) => 
              model.name.toLowerCase().contains(query.toLowerCase()) ||
              model.platform.toLowerCase().contains(query.toLowerCase()))
          .toList());
      _selectedIndex = -1;
      _overlayEntry?.markNeedsBuild();
    });
  }

  void _hideOverlay() {
    setState(() {
      _isExpanded = false;
      _controller.clear();
      _filteredModels = _sortModels(widget.models);
      _selectedIndex = -1;
    });
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectModel(LLMModel model) {
    widget.onModelSelected(model);
    _hideOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Focus(
        onKeyEvent: (node, event) {
          // Only handle key events when not expanded
          if (!_isExpanded && event is KeyDownEvent) {
            final character = event.character;
            if (character != null && character.trim().isNotEmpty) {
              setState(() {
                _isExpanded = true;
                _controller.text = character;
                _controller.selection = TextSelection.collapsed(offset: character.length);
                _filterModels(character);
                _showOverlay(context);
              });
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
              if (_isExpanded) {
                _controller.clear();
                _filteredModels = _sortModels(widget.models);
                _selectedIndex = -1;
                _showOverlay(context);
                // Ensure focus is requested within the widget's context
                _searchFocusNode.requestFocus();
              } else {
                _hideOverlay();
              }
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.selectedModel.name,
                            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.selectedModel.platform.toUpperCase(),
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          GestureDetector(
            onTap: _hideOverlay,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Positioned(
            top: offset.dy + size.height + 8,
            left: offset.dx,
            width: size.width,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Container(
                color: theme.colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                              setState(() {
                                _selectedIndex = (_selectedIndex + 1) % _filteredModels.length;
                                _overlayEntry?.markNeedsBuild();
                              });
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() {
                                _selectedIndex = _selectedIndex <= 0
                                    ? _filteredModels.length - 1
                                    : _selectedIndex - 1;
                                _overlayEntry?.markNeedsBuild();
                              });
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                              if (_selectedIndex >= 0 &&
                                  _selectedIndex < _filteredModels.length) {
                                _selectModel(_filteredModels[_selectedIndex]);
                              }
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                              _hideOverlay();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search models...',
                            prefixIcon: Icon(
                              Icons.search,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outline.withOpacity(0.1),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outline.withOpacity(0.1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.colorScheme.primary.withOpacity(0.5),
                              ),
                            ),
                          ),
                          onChanged: _filterModels,
                          autofocus: true,
                        ),
                      ),
                    ),
                    if (_filteredModels.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          shrinkWrap: true,
                          itemCount: _filteredModels.length,
                          itemBuilder: (context, index) {
                            final model = _filteredModels[index];
                            final isSelected = index == _selectedIndex;
                            final isCurrentModel = model == widget.selectedModel;

                            return InkWell(
                              onTap: () => _selectModel(model),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.smart_toy_outlined,
                                      color: theme.colorScheme.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              model.name,
                                              style: theme.textTheme.bodyLarge!.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              model.platform.toUpperCase(),
                                              style: theme.textTheme.bodySmall!.copyWith(
                                                color: theme.colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isCurrentModel) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
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
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }
} 