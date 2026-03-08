import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/recipe_model.dart';
import '../providers/recipe_provider.dart';

/// Recipe detail view showing header, ingredients, steps, and cook CTA.
class RecipeDetailScreen extends StatefulWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Recipe? _recipe;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecipe();
  }

  Future<void> _loadRecipe() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final recipe = await context.read<RecipeProvider>().getRecipe(widget.recipeId);
    if (!mounted) return;

    setState(() {
      _recipe = recipe;
      _isLoading = false;
      _error = recipe == null ? 'Recipe not found' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_recipe?.title ?? 'Recipe'),
        actions: [
          if (_recipe != null && !_recipe!.isDemo)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete recipe',
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: _buildBody(theme),
      bottomNavigationBar: _recipe != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () => context.go(
                    AppRoutes.ingredientChecklistPath(widget.recipeId),
                  ),
                  icon: const Icon(Icons.local_fire_department),
                  label: const Text('Cook this now'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const LoadingIndicator(message: 'Loading recipe...');
    }

    if (_error != null) {
      return ErrorDisplay(
        message: _error!,
        onRetry: _loadRecipe,
      );
    }

    final recipe = _recipe!;

    return RefreshIndicator(
      onRefresh: _loadRecipe,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          _HeaderCard(recipe: recipe, theme: theme),
          const SizedBox(height: 16),

          // Ingredients
          _SectionTitle(title: 'Ingredients', theme: theme),
          const SizedBox(height: 8),
          ...recipe.ingredients.map(
            (ing) => _IngredientRow(ingredient: ing, theme: theme),
          ),
          const SizedBox(height: 24),

          // Steps
          _SectionTitle(title: 'Steps', theme: theme),
          const SizedBox(height: 8),
          ...recipe.steps.map(
            (step) => _StepCard(step: step, theme: theme),
          ),
          const SizedBox(height: 80), // room for bottom bar
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok =
          await context.read<RecipeProvider>().deleteRecipe(widget.recipeId);
      if (ok && mounted) {
        context.go(AppRoutes.recipes);
      }
    }
  }
}

class _HeaderCard extends StatelessWidget {
  final Recipe recipe;
  final ThemeData theme;
  const _HeaderCard({required this.recipe, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recipe.description != null) ...[
              Text(recipe.description!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (recipe.totalTimeMinutes != null)
                  _InfoPill(
                    icon: Icons.timer_outlined,
                    label: '${recipe.totalTimeMinutes} min',
                    theme: theme,
                  ),
                if (recipe.difficulty != null)
                  _InfoPill(
                    icon: Icons.signal_cellular_alt,
                    label: recipe.difficulty!,
                    theme: theme,
                  ),
                if (recipe.servings != null)
                  _InfoPill(
                    icon: Icons.people_outline,
                    label: '${recipe.servings} servings',
                    theme: theme,
                  ),
                if (recipe.cuisine != null)
                  _InfoPill(
                    icon: Icons.restaurant,
                    label: recipe.cuisine!,
                    theme: theme,
                  ),
              ],
            ),
            if (recipe.techniqueTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: recipe.techniqueTags
                    .map((tag) => Chip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                          labelStyle: theme.textTheme.bodySmall,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  const _InfoPill(
      {required this.icon, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;
  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: theme.textTheme.headlineMedium);
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final ThemeData theme;
  const _IngredientRow({required this.ingredient, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ingredient.displayText,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final RecipeStep step;
  final ThemeData theme;
  const _StepCard({required this.step, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step number badge
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                '${step.stepNumber}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.instruction, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (step.durationMinutes != null)
                        _SmallChip(
                          label: '${step.durationMinutes} min',
                          color: theme.colorScheme.tertiaryContainer,
                        ),
                      if (step.isParallel)
                        _SmallChip(
                          label: 'parallel',
                          color: theme.colorScheme.secondaryContainer,
                        ),
                      ...step.techniqueTags.map((tag) => _SmallChip(
                            label: tag,
                            color: theme.colorScheme.surfaceContainerHighest,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
