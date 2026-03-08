import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';
import '../models/recipe_model.dart';
import '../services/recipe_service.dart';

/// Sort options for the recipe library.
enum RecipeSortOption { recentlyUsed, fastest, difficulty }

/// State management for the recipe library.
class RecipeProvider extends ChangeNotifier {
  final RecipeService _service;

  RecipeProvider({required ApiClient apiClient})
      : _service = RecipeService(api: apiClient);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<Recipe> _recipes = [];
  bool _isLoading = false;
  String? _error;
  RecipeSortOption _sortOption = RecipeSortOption.recentlyUsed;

  List<Recipe> get recipes => _sortedRecipes();
  List<Recipe> get userRecipes =>
      recipes.where((r) => !r.isDemo).toList();
  List<Recipe> get demoRecipes =>
      recipes.where((r) => r.isDemo).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _recipes.isEmpty;
  RecipeSortOption get sortOption => _sortOption;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Load all recipes from the backend.
  Future<void> loadRecipes() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _recipes = await _service.listRecipes();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Failed to load recipes. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch a single recipe (for detail view).
  Future<Recipe?> getRecipe(String recipeId) async {
    try {
      return await _service.getRecipe(recipeId);
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to load recipe.';
      notifyListeners();
      return null;
    }
  }

  /// Create a new recipe.
  Future<Recipe?> createRecipe(RecipeCreateRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final recipe = await _service.createRecipe(request);
      _recipes.add(recipe);
      _isLoading = false;
      notifyListeners();
      return recipe;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to create recipe.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Import a recipe from a URL.
  Future<Recipe?> importFromUrl(String url) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final recipe = await _service.createFromUrl(url);
      _recipes.add(recipe);
      _isLoading = false;
      notifyListeners();
      return recipe;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to import recipe from URL.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Delete a recipe.
  Future<bool> deleteRecipe(String recipeId) async {
    try {
      await _service.deleteRecipe(recipeId);
      _recipes.removeWhere((r) => r.recipeId == recipeId);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to delete recipe.';
      notifyListeners();
      return false;
    }
  }

  /// Change sort option.
  void setSortOption(RecipeSortOption option) {
    _sortOption = option;
    notifyListeners();
  }

  /// Clear any error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  List<Recipe> _sortedRecipes() {
    final sorted = List<Recipe>.from(_recipes);
    switch (_sortOption) {
      case RecipeSortOption.recentlyUsed:
        sorted.sort((a, b) {
          final aDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          final bDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });
      case RecipeSortOption.fastest:
        sorted.sort((a, b) {
          final aTime = a.totalTimeMinutes ?? 999;
          final bTime = b.totalTimeMinutes ?? 999;
          return aTime.compareTo(bTime);
        });
      case RecipeSortOption.difficulty:
        const order = {'easy': 0, 'medium': 1, 'hard': 2};
        sorted.sort((a, b) {
          final aOrd = order[a.difficulty] ?? 1;
          final bOrd = order[b.difficulty] ?? 1;
          return aOrd.compareTo(bOrd);
        });
    }
    return sorted;
  }
}
