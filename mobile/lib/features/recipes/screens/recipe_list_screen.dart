import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/recipe_model.dart';
import '../providers/recipe_provider.dart';

/// Recipe library screen with "Your Recipes" and "Demo" sections.
class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  @override
  void initState() {
    super.initState();
    // Load recipes when screen is first shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecipeProvider>().loadRecipes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          tooltip: 'Back to Home',
          onPressed: () => context.go(AppRoutes.home),
        ),
        title: const Text('Recipes'),
        actions: [
          _SortButton(),
        ],
      ),
      body: Consumer<RecipeProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.isEmpty) {
            return const LoadingIndicator(message: 'Loading recipes...');
          }

          if (provider.error != null && provider.isEmpty) {
            return ErrorDisplay(
              message: provider.error!,
              onRetry: () => provider.loadRecipes(),
            );
          }

          if (provider.isEmpty) {
            return _EmptyState(theme: theme);
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadRecipes(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                if (provider.userRecipes.isNotEmpty) ...[
                  const _SectionHeader(title: 'Your Recipes'),
                  ...provider.userRecipes.map(
                    (r) => _RecipeCard(recipe: r),
                  ),
                ],
                if (provider.demoRecipes.isNotEmpty) ...[
                  const _SectionHeader(title: 'Demo'),
                  ...provider.demoRecipes.map(
                    (r) => _RecipeCard(recipe: r),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Recipe'),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Create recipe'),
              onTap: () {
                Navigator.pop(ctx);
                context.go(AppRoutes.recipeCreate);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Import from URL'),
              onTap: () {
                Navigator.pop(ctx);
                _showUrlImportDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showUrlImportDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/recipe',
            labelText: 'Recipe URL',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(ctx);
              final provider = context.read<RecipeProvider>();
              final recipe = await provider.importFromUrl(url);
              if (recipe != null && context.mounted) {
                context.go(AppRoutes.recipeDetailPath(recipe.recipeId));
              } else if (provider.error != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(provider.error!)),
                );
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RecipeProvider>(
      builder: (context, provider, _) => PopupMenuButton<RecipeSortOption>(
        icon: const Icon(Icons.sort),
        tooltip: 'Sort recipes',
        onSelected: provider.setSortOption,
        itemBuilder: (_) => [
          _sortItem(RecipeSortOption.recentlyUsed, 'Recently used', provider),
          _sortItem(RecipeSortOption.fastest, 'Fastest', provider),
          _sortItem(RecipeSortOption.difficulty, 'Difficulty', provider),
        ],
      ),
    );
  }

  PopupMenuItem<RecipeSortOption> _sortItem(
    RecipeSortOption option,
    String label,
    RecipeProvider provider,
  ) {
    final isSelected = provider.sortOption == option;
    return PopupMenuItem(
      value: option,
      child: Row(
        children: [
          if (isSelected) const Icon(Icons.check, size: 18),
          if (isSelected) const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  const _RecipeCard({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(AppRoutes.recipeDetailPath(recipe.recipeId)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recipe.title,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (recipe.isDemo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Demo',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              if (recipe.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  recipe.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              // Metadata chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (recipe.totalTimeMinutes != null)
                    _MetaChip(
                      icon: Icons.timer_outlined,
                      label: '${recipe.totalTimeMinutes} min',
                    ),
                  if (recipe.difficulty != null)
                    _MetaChip(
                      icon: Icons.signal_cellular_alt,
                      label: recipe.difficulty!,
                    ),
                  if (recipe.cuisine != null)
                    _MetaChip(
                      icon: Icons.restaurant,
                      label: recipe.cuisine!,
                    ),
                  if (recipe.ingredients.isNotEmpty)
                    _MetaChip(
                      icon: Icons.shopping_basket_outlined,
                      label: '${recipe.ingredients.length} ingredients',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No recipes yet',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first recipe or import one from a URL to get started.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.recipeCreate),
              icon: const Icon(Icons.add),
              label: const Text('Create Recipe'),
            ),
          ],
        ),
      ),
    );
  }
}
