import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../models/recipe_model.dart';
import '../providers/recipe_provider.dart';

/// Screen for creating a new recipe with validation.
class RecipeCreateScreen extends StatefulWidget {
  const RecipeCreateScreen({super.key});

  @override
  State<RecipeCreateScreen> createState() => _RecipeCreateScreenState();
}

class _RecipeCreateScreenState extends State<RecipeCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _servingsController = TextEditingController();
  final _timeController = TextEditingController();
  final _cuisineController = TextEditingController();
  String? _difficulty;
  String? _inlineError;

  final List<_IngredientEntry> _ingredients = [_IngredientEntry()];
  final List<_StepEntry> _steps = [_StepEntry()];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _servingsController.dispose();
    _timeController.dispose();
    _cuisineController.dispose();
    for (final i in _ingredients) {
      i.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<RecipeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Recipe'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // Metadata row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _servingsController,
                    decoration: const InputDecoration(labelText: 'Servings'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _timeController,
                    decoration: const InputDecoration(labelText: 'Time (min)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _difficulty,
                    decoration: const InputDecoration(labelText: 'Difficulty'),
                    items: ['easy', 'medium', 'hard']
                        .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d[0].toUpperCase() + d.substring(1))))
                        .toList(),
                    onChanged: (v) => setState(() => _difficulty = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cuisineController,
                    decoration: const InputDecoration(labelText: 'Cuisine'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Ingredients
            _buildSectionHeader(theme, 'Ingredients *', onAdd: _addIngredient),
            ..._ingredients.asMap().entries.map(
                  (entry) => _IngredientField(
                    entry: entry.value,
                    index: entry.key,
                    onRemove: _ingredients.length > 1
                        ? () => _removeIngredient(entry.key)
                        : null,
                  ),
                ),
            const SizedBox(height: 24),

            // Steps
            _buildSectionHeader(theme, 'Steps *', onAdd: _addStep),
            ..._steps.asMap().entries.map(
                  (entry) => _StepField(
                    entry: entry.value,
                    index: entry.key,
                    onRemove: _steps.length > 1
                        ? () => _removeStep(entry.key)
                        : null,
                  ),
                ),

            // Inline error
            if (_inlineError != null) ...[
              const SizedBox(height: 12),
              Text(
                _inlineError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Submit
            ElevatedButton(
              onPressed: provider.isLoading ? null : _submit,
              child: provider.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Recipe'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title, {
    required VoidCallback onAdd,
  }) {
    return Row(
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onAdd,
          tooltip: 'Add',
        ),
      ],
    );
  }

  void _addIngredient() {
    setState(() => _ingredients.add(_IngredientEntry()));
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients[index].dispose();
      _ingredients.removeAt(index);
    });
  }

  void _addStep() {
    setState(() => _steps.add(_StepEntry()));
  }

  void _removeStep(int index) {
    setState(() {
      _steps[index].dispose();
      _steps.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Build request
    final ingredients = _ingredients
        .map((e) => Ingredient(
              name: e.nameController.text.trim(),
              nameNormalized: e.nameController.text.trim().toLowerCase(),
              quantity: e.quantityController.text.trim().isEmpty
                  ? null
                  : e.quantityController.text.trim(),
              unit: e.unitController.text.trim().isEmpty
                  ? null
                  : e.unitController.text.trim(),
            ))
        .toList();

    final steps = _steps
        .asMap()
        .entries
        .map((entry) => RecipeStep(
              stepNumber: entry.key + 1,
              instruction: entry.value.instructionController.text.trim(),
            ))
        .toList();

    final request = RecipeCreateRequest(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      servings: int.tryParse(_servingsController.text.trim()),
      totalTimeMinutes: int.tryParse(_timeController.text.trim()),
      difficulty: _difficulty,
      cuisine: _cuisineController.text.trim().isEmpty
          ? null
          : _cuisineController.text.trim(),
      ingredients: ingredients,
      steps: steps,
    );

    // Validate
    final error = request.validate();
    if (error != null) {
      setState(() => _inlineError = error);
      return;
    }

    setState(() => _inlineError = null);

    final provider = context.read<RecipeProvider>();
    final recipe = await provider.createRecipe(request);

    if (!mounted) return;

    if (recipe != null) {
      context.go(AppRoutes.recipeDetailPath(recipe.recipeId));
    } else if (provider.error != null) {
      setState(() => _inlineError = provider.error);
    }
  }
}

// ---------------------------------------------------------------------------
// Entry helper classes for dynamic form fields
// ---------------------------------------------------------------------------

class _IngredientEntry {
  final nameController = TextEditingController();
  final quantityController = TextEditingController();
  final unitController = TextEditingController();

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
  }
}

class _StepEntry {
  final instructionController = TextEditingController();

  void dispose() {
    instructionController.dispose();
  }
}

class _IngredientField extends StatelessWidget {
  final _IngredientEntry entry;
  final int index;
  final VoidCallback? onRemove;

  const _IngredientField({
    required this.entry,
    required this.index,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: entry.nameController,
              decoration: InputDecoration(
                labelText: 'Ingredient ${index + 1} *',
                isDense: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextFormField(
              controller: entry.quantityController,
              decoration: const InputDecoration(
                labelText: 'Qty',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextFormField(
              controller: entry.unitController,
              decoration: const InputDecoration(
                labelText: 'Unit',
                isDense: true,
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: onRemove,
              color: Theme.of(context).colorScheme.error,
            ),
        ],
      ),
    );
  }
}

class _StepField extends StatelessWidget {
  final _StepEntry entry;
  final int index;
  final VoidCallback? onRemove;

  const _StepField({
    required this.entry,
    required this.index,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: entry.instructionController,
              decoration: InputDecoration(
                labelText: 'Step ${index + 1} *',
                isDense: true,
              ),
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: onRemove,
              color: Theme.of(context).colorScheme.error,
            ),
        ],
      ),
    );
  }
}
