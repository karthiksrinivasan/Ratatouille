import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../models/recipe_model.dart';
import '../providers/recipe_provider.dart';

/// Ingredient checklist gate — user marks which ingredients they have
/// before starting a cooking session.
class IngredientChecklistScreen extends StatefulWidget {
  final String recipeId;
  const IngredientChecklistScreen({super.key, required this.recipeId});

  @override
  State<IngredientChecklistScreen> createState() =>
      _IngredientChecklistScreenState();
}

class _IngredientChecklistScreenState extends State<IngredientChecklistScreen> {
  Recipe? _recipe;
  List<IngredientCheck> _checks = [];
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

    final recipe =
        await context.read<RecipeProvider>().getRecipe(widget.recipeId);
    if (!mounted) return;

    if (recipe != null) {
      setState(() {
        _recipe = recipe;
        _checks = recipe.ingredients
            .map((i) => IngredientCheck(ingredient: i.displayText))
            .toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = 'Could not load recipe.';
        _isLoading = false;
      });
    }
  }

  bool get _allChecked => _checks.isNotEmpty && _checks.every((c) => c.hasIt);
  List<IngredientCheck> get _missing =>
      _checks.where((c) => !c.hasIt).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingredient Check'),
      ),
      body: _buildBody(theme),
      bottomNavigationBar: _recipe != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_allChecked && _checks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${_missing.length} ingredient${_missing.length == 1 ? '' : 's'} missing',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _checks.isEmpty ? null : _startSession,
                      icon: const Icon(Icons.local_fire_department),
                      label: Text(_allChecked
                          ? 'Start Cooking'
                          : 'Start Anyway'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: _allChecked
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const LoadingIndicator(message: 'Loading ingredients...');
    }

    if (_error != null) {
      return ErrorDisplay(message: _error!, onRetry: _loadRecipe);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'Check off the ingredients you have ready.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ..._checks.asMap().entries.map(
              (entry) => _ChecklistTile(
                check: entry.value,
                onChanged: (value) {
                  setState(() {
                    _checks[entry.key].hasIt = value;
                  });
                },
                theme: theme,
              ),
            ),
      ],
    );
  }

  void _startSession() {
    // Navigate to session setup.
    // The session creation endpoint will be in Epic 4; for now navigate
    // forward with recipe context preserved.
    if (!_allChecked) {
      _showMissingSummary();
    } else {
      _proceedToSession();
    }
  }

  void _showMissingSummary() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Missing ingredients'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are missing:'),
            const SizedBox(height: 8),
            ..._missing.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.ingredient)),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            const Text('Continue anyway?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _proceedToSession();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _proceedToSession() {
    // For now, show a snackbar indicating session handoff.
    // Session creation (Epic 4) will handle POST /v1/sessions.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting cooking session...'),
        duration: Duration(seconds: 2),
      ),
    );
    // TODO(epic-4): Navigate to live session screen after session creation.
  }
}

class _ChecklistTile extends StatelessWidget {
  final IngredientCheck check;
  final ValueChanged<bool> onChanged;
  final ThemeData theme;

  const _ChecklistTile({
    required this.check,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Checkbox(
          value: check.hasIt,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: theme.colorScheme.primary,
        ),
        title: Text(
          check.ingredient,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: check.hasIt ? TextDecoration.lineThrough : null,
            color: check.hasIt
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
        trailing: TextButton(
          onPressed: () => onChanged(!check.hasIt),
          child: Text(check.hasIt ? 'Have it' : 'Need it'),
        ),
      ),
    );
  }
}
