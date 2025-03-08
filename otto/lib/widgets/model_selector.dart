import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/llm_model.dart';

class ModelSelector extends StatefulWidget {
  final List<LLMModel> availableModels;
  final LLMModel? selectedModel;
  final Function(LLMModel) onModelSelected;
  final bool isExpanded;
  final Function(bool) onExpand;

  const ModelSelector({
    Key? key,
    required this.availableModels,
    required this.selectedModel,
    required this.onModelSelected,
    required this.isExpanded,
    required this.onExpand,
  }) : super(key: key);

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  late TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isExpanded
        ? _buildExpandedSelector()
        : _buildCollapsedSelector();
  }

  Widget _buildCollapsedSelector() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.selectedModel?.displayName ?? 'Select Model',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedSelector() {
    final theme = Theme.of(context);
    final filteredModels = _filterModels();
    
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(8.0),
            height: 60, // Fixed height for search bar
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search models...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          
          // Models list
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: filteredModels.length,
              itemBuilder: (context, index) {
                final model = filteredModels[index];
                final isSelected = widget.selectedModel?.modelId == model.modelId;
                
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  title: Text(
                    model.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  subtitle: Text(
                    '${model.provider} • ${model.maxInputTokens} tokens',
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () {
                    widget.onModelSelected(model);
                    widget.onExpand(false);
                  },
                );
              },
            ),
          ),
          
          // Close button
          Container(
            height: 40, // Fixed height for close button
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextButton(
              onPressed: () => widget.onExpand(false),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  List<LLMModel> _filterModels() {
    if (_searchQuery.isEmpty) {
      return widget.availableModels;
    }
    
    final query = _searchQuery.toLowerCase();
    return widget.availableModels.where((model) {
      return model.displayName.toLowerCase().contains(query) ||
             model.modelId.toLowerCase().contains(query) ||
             model.provider.toLowerCase().contains(query);
    }).toList();
  }
} 