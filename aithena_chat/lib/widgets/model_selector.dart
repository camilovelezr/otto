import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/llm_model.dart';

class ModelSelector extends StatefulWidget {
  final List<LLMModel> models;
  final LLMModel selectedModel;
  final Function(LLMModel) onModelSelected;
  final ScrollController? scrollController;

  const ModelSelector({
    Key? key,
    required this.models,
    required this.selectedModel,
    required this.onModelSelected,
    this.scrollController,
  }) : super(key: key);

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _selectorFocusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  List<LLMModel> _filteredModels = [];
  int _selectedIndex = -1;
  bool _isExpanded = false;
  bool _isHovered = false;
  bool _isVisible = true;
  double _lastScrollOffset = 0;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _filteredModels = _sortModels(widget.models);
    _selectorFocusNode.addListener(_handleSelectorFocus);
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );

    widget.scrollController?.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.dispose();
    _searchFocusNode.dispose();
    _selectorFocusNode.removeListener(_handleSelectorFocus);
    _selectorFocusNode.dispose();
    _animationController.dispose();
    widget.scrollController?.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    if (widget.scrollController == null) return;
    
    final currentOffset = widget.scrollController!.offset;
    final isScrollingDown = currentOffset > _lastScrollOffset;
    final isAtTop = currentOffset <= 0;
    
    setState(() {
      if (isAtTop) {
        _isVisible = true;
      } else if (isScrollingDown) {
        _isVisible = false;
      } else {
        // Scrolling up
        _isVisible = true;
      }
    });

    _lastScrollOffset = currentOffset;
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
    _animationController.reverse().then((_) {
      setState(() {
        _isExpanded = false;
        _controller.clear();
        _filteredModels = _sortModels(widget.models);
        _selectedIndex = -1;
      });
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _selectModel(LLMModel model) {
    widget.onModelSelected(model);
    _hideOverlay();
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'openai':
        return const Color(0xFF10A37F); // OpenAI green
      case 'anthropic':
        return const Color(0xFF7B61FF); // Anthropic purple
      case 'groq':
        return const Color(0xFF1A73E8); // Groq blue
      case 'ollama':
        return const Color(0xFFFF5F1F); // Ollama orange
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _buildModelIcon(String platform) {
    IconData iconData = Icons.smart_toy_outlined;
    switch (platform.toLowerCase()) {
      case 'openai':
        iconData = Icons.auto_awesome;
        break;
      case 'anthropic':
        iconData = Icons.psychology;
        break;
      case 'groq':
        iconData = Icons.bolt;
        break;
      case 'ollama':
        iconData = Icons.terminal;
        break;
    }
    final platformColor = _getPlatformColor(platform);
    return Icon(
      iconData,
      size: 18,
      color: platformColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platformColor = _getPlatformColor(widget.selectedModel.platform);
    
    Widget content = Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
            if (_isExpanded) {
              _controller.clear();
              _filteredModels = _sortModels(widget.models);
              _selectedIndex = -1;
              _showOverlay(context);
              _searchFocusNode.requestFocus();
            } else {
              _hideOverlay();
            }
          });
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: platformColor.withOpacity(_isHovered ? 0.3 : 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: platformColor.withOpacity(0.05),
                    blurRadius: _isHovered ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModelIcon(widget.selectedModel.platform),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.selectedModel.name,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _isHovered || _isExpanded
                              ? Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: platformColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    widget.selectedModel.platform.toUpperCase(),
                                    style: theme.textTheme.labelSmall!.copyWith(
                                      color: platformColor,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more_rounded,
                          color: platformColor.withOpacity(_isHovered ? 1 : 0.5),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return content;
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
            top: offset.dy + size.height + 4,
            left: offset.dx,
            child: AnimatedBuilder(
              animation: _expandAnimation,
              builder: (context, child) => Transform.scale(
                scale: _expandAnimation.value,
                alignment: Alignment.topCenter,
                child: child,
              ),
              child: Container(
                width: 280, // Fixed width for better consistency
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  color: theme.colorScheme.surface.withOpacity(0.98),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
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
                            autofocus: true,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search models...',
                              hintStyle: theme.textTheme.bodyMedium!.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: _filterModels,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _filteredModels.length,
                          itemBuilder: (context, index) {
                            final model = _filteredModels[index];
                            final isSelected = index == _selectedIndex;
                            final platformColor = _getPlatformColor(model.platform);
                            
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? platformColor.withOpacity(0.1)
                                      : Colors.transparent,
                                  border: Border(
                                    left: BorderSide(
                                      color: isSelected ? platformColor : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _selectModel(model),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          _buildModelIcon(model.platform),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  model.name,
                                                  style: theme.textTheme.bodyMedium!.copyWith(
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                    color: theme.colorScheme.onSurface,
                                                  ),
                                                ),
                                                if (model.description?.isNotEmpty ?? false)
                                                  Text(
                                                    model.description!,
                                                    style: theme.textTheme.bodySmall!.copyWith(
                                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: platformColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              model.platform.toUpperCase(),
                                              style: theme.textTheme.labelSmall!.copyWith(
                                                color: platformColor,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
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

    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
  }
} 