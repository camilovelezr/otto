import 'dart:async'; // Needed for Debouncer

import 'package:collection/collection.dart'; // Import for groupBy
import 'package:flutter/material.dart';
import 'package:otto/models/llm_model.dart'; // Corrected import path
import 'package:otto/theme/app_spacing.dart';
import 'package:provider/provider.dart';
import 'package:otto/services/chat_provider.dart'; // To potentially access provider info if needed

// Debouncer utility class
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  dispose() {
    _timer?.cancel();
  }
}

class ModelSelectorButton extends StatefulWidget {
  final LLMModel? selectedModel;
  final List<LLMModel> availableModels;

  const ModelSelectorButton({
    Key? key,
    required this.selectedModel,
    required this.availableModels,
  }) : super(key: key);

  @override
  State<ModelSelectorButton> createState() => _ModelSelectorButtonState();
}

class _ModelSelectorButtonState extends State<ModelSelectorButton> {
  String _searchQuery = '';
  late final TextEditingController _searchController;
  final Debouncer _debouncer = Debouncer(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    // Ensure listener updates the state correctly
    _searchController.addListener(() {
       _debouncer.run(() {
         if (mounted && _searchController.text != _searchQuery) {
           setState(() {
             _searchQuery = _searchController.text;
           });
         }
       });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  // Get filtered and grouped models
  Map<String, List<LLMModel>> _getFilteredAndGroupedModels() {
    List<LLMModel> filteredModels;
    if (_searchQuery.isEmpty) {
      filteredModels = widget.availableModels;
    } else {
      final query = _searchQuery.toLowerCase();
      filteredModels = widget.availableModels.where((model) {
        return model.displayName.toLowerCase().contains(query) ||
               model.modelId.toLowerCase().contains(query) ||
               model.provider.toLowerCase().contains(query);
      }).toList();
    }
    // Group by provider
    return groupBy(filteredModels, (LLMModel model) => model.provider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool hasModels = widget.availableModels.isNotEmpty;
    final bool modelSelected = widget.selectedModel != null;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    String buttonText = 'Select Model';
    IconData leadingIcon = Icons.settings_input_component_outlined; // Default icon
    Color buttonColor = colorScheme.surfaceVariant; // Default background
    Color textColor = colorScheme.onSurfaceVariant.withOpacity(0.7);
    Color iconColor = colorScheme.onSurfaceVariant.withOpacity(0.7);
    BorderSide borderSide = BorderSide(color: colorScheme.outline.withOpacity(0.5), width: 1);

    if (!hasModels) {
      buttonText = 'No Models Available';
      buttonColor = colorScheme.errorContainer.withOpacity(0.5);
      textColor = colorScheme.onErrorContainer;
      iconColor = colorScheme.onErrorContainer;
      leadingIcon = Icons.error_outline;
      borderSide = BorderSide(color: colorScheme.error.withOpacity(0.3), width: 1);
    } else if (modelSelected) {
      buttonText = widget.selectedModel!.displayName;
      buttonColor = colorScheme.primary.withOpacity(0.1);
      textColor = colorScheme.primary;
      iconColor = colorScheme.primary;
      leadingIcon = Icons.model_training_outlined; // Icon indicating model is active
      borderSide = BorderSide(color: colorScheme.primary.withOpacity(0.4), width: 1);
    }

    // The visual representation of the button (the chip)
    final Widget buttonContent = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.inlineSpacing * 1.5,
        vertical: AppSpacing.inlineSpacing * 0.75,
      ),
      decoration: BoxDecoration(
        color: buttonColor,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        border: Border.fromBorderSide(borderSide),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(leadingIcon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.inlineSpacingSmall),
          Flexible(
            child: Text(
              buttonText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: modelSelected ? FontWeight.w500 : FontWeight.normal,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );

    // If no models, return the disabled-looking button content directly
    if (!hasModels) {
      return buttonContent;
    }

    return PopupMenuButton<LLMModel>(
      tooltip: 'Select LLM Model',
      onOpened: () {
        // Ensure focus is requested when menu opens, needed after selection/cancel sometimes
        FocusScope.of(context).requestFocus(FocusNode()); // Temporary node to shift focus
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Find the TextField node if possible, otherwise just ensure keyboard is up
          // (Directly focusing the TextField within PopupMenuItem is complex)
        });
      },
      onSelected: (LLMModel result) {
        _searchController.clear();
        FocusScope.of(context).unfocus();
        chatProvider.setSelectedModel(result);
        // No need to explicitly setState for _searchQuery here, listener handles it.
      },
      onCanceled: () {
         _searchController.clear();
         FocusScope.of(context).unfocus();
         // No need to explicitly setState for _searchQuery here, listener handles it.
      },
      itemBuilder: (BuildContext context) {
        final groupedModels = _getFilteredAndGroupedModels();
        final sortedProviders = groupedModels.keys.toList()..sort();

        final List<PopupMenuEntry<LLMModel>> menuItems = [];

        // 1. Add Search Bar
        menuItems.add(
          PopupMenuItem(
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            value: null,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search models...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainer,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(), // Controller listener handles state
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                      )
                    : null,
              ),
              // onChanged handled by controller listener
            ),
          ),
        );
        menuItems.add(const PopupMenuDivider(height: 1));

        // 2. Add Grouped Models
        if (groupedModels.isEmpty && _searchQuery.isNotEmpty) {
          menuItems.add(
            const PopupMenuItem(
              enabled: false,
              value: null,
              child: Center(child: Text('No models found')),
            ),
          );
        } else {
          for (final provider in sortedProviders) {
            final modelsInGroup = groupedModels[provider]!;
            
            // Add Provider Header (using a disabled menu item)
            menuItems.add(
              PopupMenuItem(
                enabled: false,
                value: null,
                height: 30, // Adjust height for header
                padding: const EdgeInsets.symmetric(horizontal: 16),
                 child: Text(
                  provider.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );

            // Add Models in this group
            for (final model in modelsInGroup) {
              final bool isCurrentlySelected = widget.selectedModel?.modelId == model.modelId;
              menuItems.add(
                PopupMenuItem<LLMModel>(
                  value: model,
                  child: Row(
                    children: [
                      // Selection Indicator
                      SizedBox(
                        width: 24,
                        child: isCurrentlySelected
                            ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                            : null,
                      ),
                      // Provider Icon
                      Icon(model.getProviderIcon(), size: 18, color: model.getProviderColor().withOpacity(0.9)),
                      const SizedBox(width: 12),
                      // Model Info (Display Name + Provider)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                             Text(
                               model.displayName,
                               style: theme.textTheme.bodyMedium?.copyWith(
                                 fontWeight: isCurrentlySelected ? FontWeight.bold : FontWeight.normal,
                               ),
                               overflow: TextOverflow.ellipsis,
                               maxLines: 1,
                             ),
                             Text(
                              model.provider, // Provider as smaller text
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
             // Optional: Add divider between groups if needed
             if (provider != sortedProviders.last) {
                menuItems.add(const PopupMenuDivider(height: 1));
             }
          }
        }

        return menuItems;
      },
      child: buttonContent,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      color: colorScheme.surfaceContainerHighest,
      elevation: 3,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 400), // Slightly wider
    );
  }
}
