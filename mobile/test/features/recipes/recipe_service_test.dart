import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/recipes/models/recipe_model.dart';
import 'package:ratatouille/features/recipes/services/recipe_service.dart';

void main() {
  ApiClient createApi(http_testing.MockClient client) {
    return ApiClient(
      tokenProvider: () async => 'test-token',
      httpClient: client,
      baseUrl: 'https://api.test.com',
    );
  }

  group('RecipeService', () {
    test('listRecipes parses array response', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.url.path, '/v1/recipes');
        return http.Response(
          jsonEncode([
            {'recipe_id': 'r1', 'title': 'Recipe 1', 'uid': 'u1'},
            {'recipe_id': 'r2', 'title': 'Recipe 2', 'uid': 'u1'},
          ]),
          200,
        );
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      final recipes = await service.listRecipes();
      expect(recipes.length, 2);
      expect(recipes[0].title, 'Recipe 1');
      expect(recipes[1].recipeId, 'r2');

      api.dispose();
    });

    test('getRecipe fetches single recipe', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.url.path, '/v1/recipes/r1');
        return http.Response(
          jsonEncode({
            'recipe_id': 'r1',
            'title': 'Test Recipe',
            'uid': 'u1',
          }),
          200,
        );
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      final recipe = await service.getRecipe('r1');
      expect(recipe.title, 'Test Recipe');
      expect(recipe.recipeId, 'r1');

      api.dispose();
    });

    test('createRecipe sends correct body', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'New Recipe');
        expect((body['ingredients'] as List).length, 1);

        return http.Response(
          jsonEncode({
            'recipe_id': 'new-r1',
            'title': 'New Recipe',
            'uid': 'u1',
          }),
          201,
        );
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      final recipe = await service.createRecipe(RecipeCreateRequest(
        title: 'New Recipe',
        ingredients: [const Ingredient(name: 'Salt', nameNormalized: 'salt')],
        steps: [const RecipeStep(stepNumber: 1, instruction: 'Season')],
      ));

      expect(recipe.recipeId, 'new-r1');
      api.dispose();
    });

    test('deleteRecipe calls DELETE endpoint', () async {
      bool deleteCalled = false;
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/recipes/r1');
        deleteCalled = true;
        return http.Response(jsonEncode({}), 200);
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      await service.deleteRecipe('r1');
      expect(deleteCalled, true);
      api.dispose();
    });

    test('createFromUrl sends url in body', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/recipes/from-url');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['url'], 'https://example.com/recipe');

        return http.Response(
          jsonEncode({
            'recipe_id': 'parsed-1',
            'title': 'Parsed Recipe',
            'source_type': 'url_parsed',
          }),
          201,
        );
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      final recipe = await service.createFromUrl('https://example.com/recipe');
      expect(recipe.sourceType, 'url_parsed');
      api.dispose();
    });

    test('listRecipes handles empty response', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      final recipes = await service.listRecipes();
      expect(recipes, isEmpty);
      api.dispose();
    });

    test('listRecipes throws on error', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
            jsonEncode({'detail': 'Unauthorized'}), 401);
      });

      final api = createApi(mockClient);
      final service = RecipeService(api: api);

      expect(
        () => service.listRecipes(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );

      api.dispose();
    });
  });
}
