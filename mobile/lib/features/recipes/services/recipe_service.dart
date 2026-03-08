import '../../../core/api_client.dart';
import '../models/recipe_model.dart';

/// Service layer for recipe API calls.
class RecipeService {
  final ApiClient _api;

  RecipeService({required ApiClient api}) : _api = api;

  /// Fetch all recipes for the current user.
  Future<List<Recipe>> listRecipes() async {
    final data = await _api.getList('/v1/recipes');
    return data
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single recipe by ID.
  Future<Recipe> getRecipe(String recipeId) async {
    final data = await _api.get('/v1/recipes/$recipeId');
    return Recipe.fromJson(data);
  }

  /// Create a new recipe.
  Future<Recipe> createRecipe(RecipeCreateRequest request) async {
    final data = await _api.post('/v1/recipes', body: request.toJson());
    return Recipe.fromJson(data);
  }

  /// Update an existing recipe.
  Future<Recipe> updateRecipe(
      String recipeId, RecipeCreateRequest request) async {
    final data =
        await _api.put('/v1/recipes/$recipeId', body: request.toJson());
    return Recipe.fromJson(data);
  }

  /// Delete a recipe.
  Future<void> deleteRecipe(String recipeId) async {
    await _api.delete('/v1/recipes/$recipeId');
  }

  /// Parse a recipe from a URL.
  Future<Recipe> createFromUrl(String url) async {
    final data = await _api.post('/v1/recipes/from-url', body: {'url': url});
    return Recipe.fromJson(data);
  }
}
