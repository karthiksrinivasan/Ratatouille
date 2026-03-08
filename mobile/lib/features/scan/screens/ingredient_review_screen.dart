import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/error_display.dart';
import '../models/scan_models.dart';
import '../providers/scan_provider.dart';

/// Ingredient review screen with confidence-coded chips.
///
/// Users can add/remove/edit detected ingredients before confirming.
/// Sticky "Confirm Ingredients" CTA at the bottom.
class IngredientReviewScreen extends StatefulWidget {
  const IngredientReviewScreen({super.key});

  @override
  State<IngredientReviewScreen> createState() => _IngredientReviewScreenState();
}

class _IngredientReviewScreenState extends State<IngredientReviewScreen> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _addIngredient(ScanProvider provider) {
    final text = _addController.text.trim();
    if (text.isNotEmpty) {
      provider.addManualIngredient(text);
      _addController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<ScanProvider>(
      builder: (context, provider, _) {
        // Navigate to suggestions when done
        if (provider.phase == ScanPhase.done && provider.suggestions != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/scan/suggestions');
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Review Ingredients'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                provider.reset();
                context.go('/scan');
              },
            ),
          ),
          body: provider.isLoading
              ? _buildLoadingState(theme)
              : provider.error != null
                  ? ErrorDisplay(
                      message: provider.error!,
                      onRetry: () => provider.clearError(),
                    )
                  : _buildReviewContent(provider, theme),
          bottomNavigationBar: provider.isLoading
              ? null
              : _buildBottomBar(provider, theme),
        );
      },
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text('Getting recipe suggestions...',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Matching your ingredients with recipes',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewContent(ScanProvider provider, ThemeData theme) {
    final detected = provider.detected;
    final confirmed = provider.confirmed;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary card
          if (detected.isNotEmpty) ...[
            _buildSummaryCard(provider, theme),
            const SizedBox(height: 16),
          ],

          // Low confidence warning
          if (provider.lowConfidenceCount > 0) ...[
            _buildLowConfidenceWarning(provider, theme),
            const SizedBox(height: 16),
          ],

          // Ingredient chips
          Text('Detected Ingredients', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (detected.isNotEmpty)
            _buildDetectedChips(provider, theme)
          else
            Text(
              'No ingredients detected. Add them manually below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

          const SizedBox(height: 20),

          // Confirmed list
          if (confirmed.isNotEmpty) ...[
            Text(
              'Your Ingredient List (${confirmed.length})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: confirmed.map((name) {
                return Chip(
                  label: Text(name),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => provider.removeIngredient(name),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Manual add field
          _buildAddField(provider, theme),
          const SizedBox(height: 80), // Space for bottom bar
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ScanProvider provider, ThemeData theme) {
    final high = provider.detected
        .where((d) => d.tier == ConfidenceTier.high)
        .length;
    final med = provider.detected
        .where((d) => d.tier == ConfidenceTier.medium)
        .length;
    final low = provider.detected
        .where((d) => d.tier == ConfidenceTier.low)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Found ${provider.detected.length} ingredients: '
                '$high certain, $med likely, $low uncertain',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowConfidenceWarning(ScanProvider provider, ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${provider.lowConfidenceCount} items have low confidence — '
                'please verify them below.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedChips(ScanProvider provider, ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: provider.detected.map((ingredient) {
        final isSelected = provider.confirmed.contains(
          ingredient.nameNormalized,
        );
        final color = _chipColor(ingredient.tier, theme);

        return FilterChip(
          label: Text(ingredient.name),
          selected: isSelected,
          onSelected: (_) => provider.toggleIngredient(
            ingredient.nameNormalized,
          ),
          avatar: _confidenceIcon(ingredient.tier, theme),
          backgroundColor: color.withValues(alpha: 0.1),
          selectedColor: color.withValues(alpha: 0.25),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          tooltip: '${(ingredient.confidence * 100).round()}% confidence',
        );
      }).toList(),
    );
  }

  Color _chipColor(ConfidenceTier tier, ThemeData theme) {
    switch (tier) {
      case ConfidenceTier.high:
        return Colors.green;
      case ConfidenceTier.medium:
        return Colors.orange;
      case ConfidenceTier.low:
        return Colors.red;
    }
  }

  Widget _confidenceIcon(ConfidenceTier tier, ThemeData theme) {
    switch (tier) {
      case ConfidenceTier.high:
        return const Icon(Icons.check_circle, size: 16, color: Colors.green);
      case ConfidenceTier.medium:
        return const Icon(Icons.help, size: 16, color: Colors.orange);
      case ConfidenceTier.low:
        return const Icon(Icons.warning, size: 16, color: Colors.red);
    }
  }

  Widget _buildAddField(ScanProvider provider, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _addController,
            decoration: const InputDecoration(
              hintText: 'Add an ingredient...',
              prefixIcon: Icon(Icons.add),
              isDense: true,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addIngredient(provider),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () => _addIngredient(provider),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ScanProvider provider, ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: provider.confirmed.isNotEmpty
              ? () => provider.confirmAndGetSuggestions()
              : null,
          icon: const Icon(Icons.restaurant_menu),
          label: Text(
            provider.confirmed.isEmpty
                ? 'Select ingredients to continue'
                : 'Confirm ${provider.confirmed.length} Ingredients',
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
      ),
    );
  }
}
