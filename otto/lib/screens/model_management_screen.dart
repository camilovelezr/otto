import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/llm_model.dart';
import '../services/model_service.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({Key? key}) : super(key: key);

  @override
  _ModelManagementScreenState createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  final ModelService _modelService = ModelService();
  List<LLMModel> _models = [];
  bool _isLoading = true;
  String? _error;
  String? _filterProvider;
  
  @override
  void initState() {
    super.initState();
    _loadModels();
  }
  
  @override
  void dispose() {
    _modelService.dispose();
    super.dispose();
  }
  
  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final models = await _modelService.getModels(provider: _filterProvider);
      setState(() {
        _models = models;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }
  
  Future<void> _refreshModels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      // Fetch models from the /models/list endpoint
      final models = await _modelService.getModels(provider: _filterProvider);
      setState(() {
        _models = models;
        _isLoading = false;
      });
      
      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully loaded ${models.length} models'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      
      // Show error snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load models: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _editModel(LLMModel model) async {
    final result = await showDialog<LLMModel>(
      context: context,
      builder: (context) => ModelEditDialog(model: model),
    );
    
    if (result != null) {
      try {
        await _modelService.updateModel(result);
        _loadModels();
        
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating model: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Management'),
        actions: [
          // Provider filter
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter by Provider',
            onSelected: (provider) {
              setState(() {
                _filterProvider = provider;
              });
              _loadModels();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('All Providers'),
              ),
              ...['OpenAI', 'Anthropic', 'Ollama', 'Groq', 'Meta']
                .map((p) => PopupMenuItem(
                  value: p,
                  child: Text(p),
                ))
                .toList(),
            ],
          ),
          
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadModels,
            tooltip: 'Refresh',
          ),
          
          // Get Models button (renamed from Sync)
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _refreshModels,
            tooltip: 'Get Models from Server',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadModels,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _models.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No models found'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refreshModels,
                            child: const Text('Load Models'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _models.length,
                      itemBuilder: (context, index) {
                        final model = _models[index];
                        return ModelCard(
                          model: model,
                          onEdit: () => _editModel(model),
                        );
                      },
                    ),
    );
  }
}

// Model Card Widget
class ModelCard extends StatelessWidget {
  final LLMModel model;
  final VoidCallback onEdit;
  
  const ModelCard({
    Key? key, 
    required this.model, 
    required this.onEdit
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        leading: Icon(
          model.getProviderIcon(),
          color: model.getProviderColor(),
        ),
        title: Text(model.displayName),
        subtitle: Text(model.provider),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Token information
          InfoRow(
            icon: Icons.token,
            label: 'Context Window',
            value: '${model.maxInputTokens} tokens',
          ),
          InfoRow(
            icon: Icons.arrow_forward,
            label: 'Input Tokens',
            value: '${model.maxInputTokens} tokens',
          ),
          InfoRow(
            icon: Icons.arrow_back,
            label: 'Output Tokens',
            value: '${model.maxOutputTokens} tokens',
          ),
          
          const Divider(),
          
          // Pricing information
          InfoRow(
            icon: Icons.attach_money,
            label: 'Input Price',
            value: '\$${model.inputPricePerToken.toStringAsFixed(7)}/token',
          ),
          InfoRow(
            icon: Icons.attach_money,
            label: 'Output Price',
            value: '\$${model.outputPricePerToken.toStringAsFixed(7)}/token',
          ),
          
          const Divider(),
          
          // Capabilities
          const Text('Capabilities', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          CapabilitiesChipGroup(capabilities: model.capabilities),
          
          const SizedBox(height: 16),
          
          // Edit button
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
            ),
          ),
        ],
      ),
    );
  }
}

// Model Edit Dialog
class ModelEditDialog extends StatefulWidget {
  final LLMModel model;
  
  const ModelEditDialog({Key? key, required this.model}) : super(key: key);
  
  @override
  _ModelEditDialogState createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<ModelEditDialog> {
  late TextEditingController _maxInputTokensController;
  late TextEditingController _maxOutputTokensController;
  late TextEditingController _inputPriceController;
  late TextEditingController _outputPriceController;
  
  @override
  void initState() {
    super.initState();
    _maxInputTokensController = TextEditingController(text: widget.model.maxInputTokens.toString());
    _maxOutputTokensController = TextEditingController(text: widget.model.maxOutputTokens.toString());
    _inputPriceController = TextEditingController(text: widget.model.inputPricePerToken.toString());
    _outputPriceController = TextEditingController(text: widget.model.outputPricePerToken.toString());
  }
  
  @override
  void dispose() {
    _maxInputTokensController.dispose();
    _maxOutputTokensController.dispose();
    _inputPriceController.dispose();
    _outputPriceController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.model.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provider: ${widget.model.provider}', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            
            // Token limits
            const Text('Token Limits', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _maxInputTokensController,
              decoration: const InputDecoration(
                labelText: 'Max Input Tokens (Context Window)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _maxOutputTokensController,
              decoration: const InputDecoration(
                labelText: 'Max Output Tokens',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            
            const SizedBox(height: 16),
            
            // Pricing
            const Text('Pricing (USD per token)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _inputPriceController,
              decoration: const InputDecoration(
                labelText: 'Input Price',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _outputPriceController,
              decoration: const InputDecoration(
                labelText: 'Output Price',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            
            const SizedBox(height: 16),
            
            // Capabilities (read-only)
            const Text('Capabilities', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            CapabilitiesChipGroup(capabilities: widget.model.capabilities),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            // Create updated model
            final updatedModel = widget.model.copyWith(
              maxInputTokens: int.tryParse(_maxInputTokensController.text) ?? widget.model.maxInputTokens,
              maxOutputTokens: int.tryParse(_maxOutputTokensController.text) ?? widget.model.maxOutputTokens,
              inputPricePerToken: double.tryParse(_inputPriceController.text) ?? widget.model.inputPricePerToken,
              outputPricePerToken: double.tryParse(_outputPriceController.text) ?? widget.model.outputPricePerToken,
            );
            
            Navigator.of(context).pop(updatedModel);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Helper widgets
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  
  const InfoRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value),
        ],
      ),
    );
  }
}

class CapabilitiesChipGroup extends StatelessWidget {
  final ModelCapabilities capabilities;
  
  const CapabilitiesChipGroup({Key? key, required this.capabilities}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (capabilities.supportsSystemMessages)
          _buildChip('System Messages', Colors.blue),
        if (capabilities.supportsVision)
          _buildChip('Vision', Colors.purple),
        if (capabilities.supportsFunctionCalling)
          _buildChip('Function Calling', Colors.orange),
        if (capabilities.supportsToolChoice)
          _buildChip('Tool Choice', Colors.amber),
        if (capabilities.supportsStreaming)
          _buildChip('Streaming', Colors.green),
        if (capabilities.supportsResponseFormat)
          _buildChip('Response Format', Colors.teal),
      ],
    );
  }
  
  Widget _buildChip(String label, Color color) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withOpacity(0.2),
      side: BorderSide(color: color.withOpacity(0.5)),
      labelStyle: TextStyle(color: Color.lerp(color, Colors.black, 0.5)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
} 