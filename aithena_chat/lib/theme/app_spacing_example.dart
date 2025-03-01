import 'package:flutter/material.dart';
import 'app_spacing.dart';

/// This is an example component that demonstrates how to use the AppSpacing utility
/// throughout your application to maintain consistent spacing.
class SpacingExampleScreen extends StatelessWidget {
  const SpacingExampleScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spacing System'),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.screenInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Primary Spacing Constants'),
            AppSpacing.headerSpacer,
            _buildSpacingShowcase(),
            
            AppSpacing.blockSpacer,
            _buildSectionHeader('Example UI Components'),
            AppSpacing.headerSpacer,
            _buildExampleCard(context),
            
            AppSpacing.blockSpacer,
            _buildSectionHeader('Form Elements'),
            AppSpacing.headerSpacer,
            _buildFormExample(),
            
            AppSpacing.blockSpacer,
            _buildSectionHeader('List Example'),
            AppSpacing.headerSpacer,
            _buildListExample(),
            
            AppSpacing.blockSpacer,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSpacingShowcase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpacingItem('Block Spacing (16px)', AppSpacing.blockSpacing),
        _buildSpacingItem('Header Bottom Spacing (12px)', AppSpacing.headerBottomSpacing),
        _buildSpacingItem('Paragraph Spacing (10px)', AppSpacing.paragraphSpacing),
        _buildSpacingItem('Inline Spacing (8px)', AppSpacing.inlineSpacing),
        _buildSpacingItem('List Item Spacing (4px)', AppSpacing.listItemSpacing),
      ],
    );
  }

  Widget _buildSpacingItem(String label, double value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.paragraphSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            height: value,
            color: Colors.blue.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.paragraphSpacing),
      child: Padding(
        padding: AppSpacing.cardInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Card Title',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: AppSpacing.paragraphSpacing),
            Text(
              'This card uses standardized padding from our spacing system. '
              'The space between elements is consistent with our app design guidelines.',
            ),
            SizedBox(height: AppSpacing.paragraphSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {},
                  child: const Text('CANCEL'),
                ),
                SizedBox(width: AppSpacing.inlineSpacing),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('CONFIRM'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.formFieldInsets,
          child: TextFormField(
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter your full name',
            ),
          ),
        ),
        Padding(
          padding: AppSpacing.formFieldInsets,
          child: TextFormField(
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'Enter your email address',
            ),
          ),
        ),
        Padding(
          padding: AppSpacing.formFieldInsets,
          child: TextFormField(
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListExample() {
    final items = List.generate(5, (index) => 'List Item ${index + 1}');
    
    return Column(
      children: items.map((item) {
        return Padding(
          padding: AppSpacing.listItemInsets,
          child: Row(
            children: [
              const Icon(Icons.circle, size: 8),
              SizedBox(width: AppSpacing.inlineSpacing),
              Text(item),
            ],
          ),
        );
      }).toList(),
    );
  }
} 