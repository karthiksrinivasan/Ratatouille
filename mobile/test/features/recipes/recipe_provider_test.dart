import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/recipes/models/recipe_model.dart';
import 'package:ratatouille/features/recipes/providers/recipe_provider.dart';

void main() {
  final sampleRecipes = [
    {
      'recipe_id': 'r1',
      'title': 'Quick Salad',
      'uid': 'u1',
      'total_time_minutes': 10,
      'difficulty': 'easy',
      'updated_at': '2025-06-01T00:00:00',
    },
    {
      'recipe_id': 'demo-aglio',
      'title': 'Pasta Demo',
      'uid': 'u1',
      'total_time_minutes': 25,
      'difficulty': 'medium',
      'updated_at': '2025-05-01T00:00:00',
    },
    {
      'recipe_id': 'r2',
      'title': 'Beef Stew',
      'uid': 'u1',
      'total_time_minutes': 120,
      'difficulty': 'hard',
      'updated_at': '2025-04-01T00:00:00',
    },
  ];

  RecipeProvider createProvider(http_testing.MockClient client) {
    final api = ApiClient(
      tokenProvider: () async => 'test-token',
      httpClient: client,
      baseUrl: 'https://api.test.com',
    );
    return RecipeProvider(apiClient: api);
  }

  group('RecipeProvider', () {
    test('loadRecipes populates state', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(jsonEncode(sampleRecipes), 200);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();

      expect(provider.recipes.length, 3);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('separates user and demo recipes', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(jsonEncode(sampleRecipes), 200);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();

      expect(provider.userRecipes.length, 2);
      expect(provider.demoRecipes.length, 1);
      expect(provider.demoRecipes.first.recipeId, 'demo-aglio');
    });

    test('sorts by fastest', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(jsonEncode(sampleRecipes), 200);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();
      provider.setSortOption(RecipeSortOption.fastest);

      final times = provider.recipes
          .map((r) => r.totalTimeMinutes ?? 999)
          .toList();
      expect(times, [10, 25, 120]);
    });

    test('sorts by difficulty', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(jsonEncode(sampleRecipes), 200);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();
      provider.setSortOption(RecipeSortOption.difficulty);

      final diffs = provider.recipes.map((r) => r.difficulty).toList();
      expect(diffs, ['easy', 'medium', 'hard']);
    });

    test('loadRecipes handles error', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(
            jsonEncode({'detail': 'Server error'}), 500);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();

      expect(provider.error, 'Server error');
      expect(provider.isEmpty, true);
    });

    test('deleteRecipe removes recipe from list', () async {
      final client = http_testing.MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(sampleRecipes), 200);
        }
        if (request.method == 'DELETE') {
          return http.Response(jsonEncode({}), 200);
        }
        return http.Response('', 404);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();
      expect(provider.recipes.length, 3);

      final ok = await provider.deleteRecipe('r1');
      expect(ok, true);
      expect(provider.recipes.length, 2);
    });

    test('createRecipe adds to list', () async {
      final client = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'recipe_id': 'new-1',
              'title': 'New',
              'uid': 'u1',
            }),
            201,
          );
        }
        return http.Response(jsonEncode([]), 200);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();
      expect(provider.recipes.length, 0);

      final recipe = await provider.createRecipe(RecipeCreateRequest(
        title: 'New',
        ingredients: [const Ingredient(name: 'Salt')],
        steps: [const RecipeStep(stepNumber: 1, instruction: 'Do it')],
      ));

      expect(recipe, isNotNull);
      expect(provider.recipes.length, 1);
    });

    test('clearError resets error state', () async {
      final client = http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Oops'}), 500);
      });

      final provider = createProvider(client);
      await provider.loadRecipes();
      expect(provider.error, isNotNull);

      provider.clearError();
      expect(provider.error, isNull);
    });

    test('importFromUrl adds recipe on success', () async {
      final client = http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'recipe_id': 'url-1',
              'title': 'Imported',
              'uid': 'u1',
              'source_type': 'url_parsed',
            }),
            201,
          );
        }
        return http.Response(jsonEncode([]), 200);
      });

      final provider = createProvider(client);
      final recipe = await provider.importFromUrl('https://example.com/recipe');

      expect(recipe, isNotNull);
      expect(recipe!.sourceType, 'url_parsed');
      expect(provider.recipes.length, 1);
    });
  });
}
