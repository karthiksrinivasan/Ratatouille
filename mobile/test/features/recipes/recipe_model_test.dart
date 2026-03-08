import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/recipes/models/recipe_model.dart';

void main() {
  group('Ingredient', () {
    test('fromJson parses all fields', () {
      final json = {
        'name': 'Red Onion',
        'name_normalized': 'red onion',
        'quantity': '2',
        'unit': 'medium',
        'preparation': 'diced',
        'category': 'vegetable',
      };

      final ingredient = Ingredient.fromJson(json);

      expect(ingredient.name, 'Red Onion');
      expect(ingredient.nameNormalized, 'red onion');
      expect(ingredient.quantity, '2');
      expect(ingredient.unit, 'medium');
      expect(ingredient.preparation, 'diced');
      expect(ingredient.category, 'vegetable');
    });

    test('displayText combines parts correctly', () {
      const ing = Ingredient(
        name: 'Onion',
        quantity: '2',
        unit: 'cups',
        preparation: 'diced',
      );

      expect(ing.displayText, '2 cups Onion (diced)');
    });

    test('displayText handles minimal ingredient', () {
      const ing = Ingredient(name: 'Salt');
      expect(ing.displayText, 'Salt');
    });

    test('toJson round-trips correctly', () {
      const ing = Ingredient(
        name: 'Garlic',
        nameNormalized: 'garlic',
        quantity: '3',
        unit: 'cloves',
      );

      final json = ing.toJson();
      final restored = Ingredient.fromJson(json);

      expect(restored.name, 'Garlic');
      expect(restored.nameNormalized, 'garlic');
      expect(restored.quantity, '3');
      expect(restored.unit, 'cloves');
    });
  });

  group('RecipeStep', () {
    test('fromJson parses all fields', () {
      final json = {
        'step_number': 1,
        'instruction': 'Boil water',
        'technique_tags': ['boil'],
        'duration_minutes': 8.0,
        'is_parallel': false,
        'guide_image_prompt': 'Boiling water in pot',
      };

      final step = RecipeStep.fromJson(json);

      expect(step.stepNumber, 1);
      expect(step.instruction, 'Boil water');
      expect(step.techniqueTags, ['boil']);
      expect(step.durationMinutes, 8.0);
      expect(step.isParallel, false);
      expect(step.guideImagePrompt, 'Boiling water in pot');
    });

    test('defaults for optional fields', () {
      final step = RecipeStep.fromJson({
        'step_number': 1,
        'instruction': 'Do something',
      });

      expect(step.techniqueTags, isEmpty);
      expect(step.durationMinutes, isNull);
      expect(step.isParallel, false);
    });
  });

  group('Recipe', () {
    test('fromJson parses full recipe', () {
      final json = {
        'recipe_id': 'demo-aglio-e-olio',
        'uid': 'user-1',
        'title': 'Pasta Aglio e Olio',
        'description': 'Classic Roman pasta',
        'source_type': 'manual',
        'servings': 2,
        'total_time_minutes': 25,
        'difficulty': 'medium',
        'cuisine': 'Italian',
        'ingredients': [
          {'name': 'Spaghetti', 'name_normalized': 'spaghetti', 'quantity': '200', 'unit': 'g'},
        ],
        'steps': [
          {'step_number': 1, 'instruction': 'Boil water', 'technique_tags': ['boil']},
        ],
        'technique_tags': ['boil'],
        'ingredients_normalized': ['spaghetti'],
        'created_at': '2025-01-01T00:00:00',
        'updated_at': '2025-01-01T00:00:00',
      };

      final recipe = Recipe.fromJson(json);

      expect(recipe.recipeId, 'demo-aglio-e-olio');
      expect(recipe.title, 'Pasta Aglio e Olio');
      expect(recipe.servings, 2);
      expect(recipe.difficulty, 'medium');
      expect(recipe.ingredients.length, 1);
      expect(recipe.steps.length, 1);
      expect(recipe.techniqueTags, ['boil']);
      expect(recipe.isDemo, true);
    });

    test('isDemo returns false for non-demo recipes', () {
      final recipe = Recipe.fromJson({
        'recipe_id': 'abc-123',
        'title': 'My Recipe',
      });
      expect(recipe.isDemo, false);
    });

    test('handles missing optional fields gracefully', () {
      final recipe = Recipe.fromJson({
        'recipe_id': 'r1',
        'title': 'Simple',
      });

      expect(recipe.description, isNull);
      expect(recipe.servings, isNull);
      expect(recipe.ingredients, isEmpty);
      expect(recipe.steps, isEmpty);
    });
  });

  group('RecipeCreateRequest', () {
    test('validate returns null for valid request', () {
      const request = RecipeCreateRequest(
        title: 'Test Recipe',
        ingredients: [Ingredient(name: 'Salt')],
        steps: [RecipeStep(stepNumber: 1, instruction: 'Do stuff')],
      );

      expect(request.validate(), isNull);
    });

    test('validate returns error for empty title', () {
      const request = RecipeCreateRequest(
        title: '',
        ingredients: [Ingredient(name: 'Salt')],
        steps: [RecipeStep(stepNumber: 1, instruction: 'Do stuff')],
      );

      expect(request.validate(), 'Title is required');
    });

    test('validate returns error for no ingredients', () {
      const request = RecipeCreateRequest(
        title: 'Test',
        ingredients: [],
        steps: [RecipeStep(stepNumber: 1, instruction: 'Do stuff')],
      );

      expect(request.validate(), 'At least one ingredient is required');
    });

    test('validate returns error for no steps', () {
      const request = RecipeCreateRequest(
        title: 'Test',
        ingredients: [Ingredient(name: 'Salt')],
        steps: [],
      );

      expect(request.validate(), 'At least one step is required');
    });

    test('validate returns error for empty ingredient name', () {
      const request = RecipeCreateRequest(
        title: 'Test',
        ingredients: [Ingredient(name: '')],
        steps: [RecipeStep(stepNumber: 1, instruction: 'Do stuff')],
      );

      expect(request.validate(), 'Ingredient 1 needs a name');
    });

    test('validate returns error for empty step instruction', () {
      const request = RecipeCreateRequest(
        title: 'Test',
        ingredients: [Ingredient(name: 'Salt')],
        steps: [RecipeStep(stepNumber: 1, instruction: '')],
      );

      expect(request.validate(), 'Step 1 needs an instruction');
    });

    test('toJson includes all fields', () {
      const request = RecipeCreateRequest(
        title: 'Test',
        description: 'A test recipe',
        servings: 4,
        totalTimeMinutes: 30,
        difficulty: 'easy',
        cuisine: 'Italian',
        ingredients: [Ingredient(name: 'Salt', nameNormalized: 'salt')],
        steps: [RecipeStep(stepNumber: 1, instruction: 'Season')],
      );

      final json = request.toJson();

      expect(json['title'], 'Test');
      expect(json['description'], 'A test recipe');
      expect(json['servings'], 4);
      expect(json['total_time_minutes'], 30);
      expect(json['difficulty'], 'easy');
      expect(json['cuisine'], 'Italian');
      expect((json['ingredients'] as List).length, 1);
      expect((json['steps'] as List).length, 1);
    });
  });

  group('IngredientCheck', () {
    test('defaults to not having ingredient', () {
      final check = IngredientCheck(ingredient: 'Salt');
      expect(check.hasIt, false);
    });

    test('toJson works', () {
      final check = IngredientCheck(ingredient: 'Salt', hasIt: true);
      final json = check.toJson();
      expect(json['ingredient'], 'Salt');
      expect(json['has_it'], true);
    });
  });
}
