import 'package:flutter/material.dart';
import '../models/llm_model.dart';

class TokenWindowVisualization extends StatelessWidget {
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final LLMModel? model;
  final double totalCost;
  
  const TokenWindowVisualization({
    Key? key,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    this.model,
    required this.totalCost,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTokens = model?.maxInputTokens ?? 200000;
    final usagePercentage = (totalTokens / maxTokens).clamp(0.0, 1.0);
    
    // Determine color based on usage
    Color barColor;
    if (usagePercentage < 0.7) {
      barColor = Colors.green;
    } else if (usagePercentage < 0.9) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Token Usage',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${totalTokens.toStringAsFixed(0)} / ${maxTokens.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usagePercentage,
                backgroundColor: theme.colorScheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTokenDetail(
                  context, 
                  'Input', 
                  inputTokens, 
                  Colors.blue,
                ),
                _buildTokenDetail(
                  context, 
                  'Output', 
                  outputTokens, 
                  Colors.purple,
                ),
                _buildCostDetail(context),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTokenDetail(BuildContext context, String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $count',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
  
  Widget _buildCostDetail(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.attach_money,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Text(
          'Cost: \$${totalCost.toStringAsFixed(4)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
} 