import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/recipes/screens/ingredient_checklist_screen.dart';
import '../features/recipes/screens/recipe_create_screen.dart';
import '../features/recipes/screens/recipe_detail_screen.dart';
import '../features/recipes/screens/recipe_list_screen.dart';
import '../features/scan/screens/home_screen.dart';
import '../features/scan/screens/scan_screen.dart';
import '../features/scan/screens/ingredient_review_screen.dart';
import '../features/suggestions/screens/suggestions_screen.dart';
import '../features/live_session/screens/live_session_screen.dart';
import '../features/live_session/screens/session_setup_screen.dart';
import '../features/vision_guide/screens/vision_guide_screen.dart';
import '../features/live_session/screens/cook_now_screen.dart';
import '../features/post_session/screens/post_session_screen.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String scan = '/scan';
  static const String scanReview = '/scan/review';
  static const String scanSuggestions = '/scan/suggestions';
  static const String recipes = '/recipes';
  static const String recipeDetail = '/recipes/:id';
  static const String recipeCreate = '/recipes/create';
  static const String ingredientChecklist = '/recipes/:id/checklist';
  static const String cookNow = '/cook-now';
  static const String suggestions = '/suggestions';
  static const String sessionSetup = '/session/:id/setup';
  static const String session = '/session/:id';
  static const String visionGuide = '/vision-guide/:id';
  static const String postSession = '/post-session/:id';

  /// Build a recipe detail path with the given [id].
  static String recipeDetailPath(String id) => '/recipes/$id';

  /// Build an ingredient checklist path with the given [id].
  static String ingredientChecklistPath(String id) => '/recipes/$id/checklist';

  /// Build a session path with the given [id].
  static String sessionSetupPath(String id) => '/session/$id/setup';
  static String sessionPath(String id) => '/session/$id';

  /// Build a vision guide path with the given [id].
  static String visionGuidePath(String id) => '/vision-guide/$id';

  /// Build a post-session path with the given [id].
  static String postSessionPath(String id) => '/post-session/$id';
}

/// Top-level router configuration for the app.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  debugLogDiagnostics: true,
  routes: [
    // Home entry screen
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),

    // Scan / pantry capture flow
    GoRoute(
      path: AppRoutes.scan,
      name: 'scan',
      builder: (context, state) => const ScanScreen(),
    ),

    // Ingredient review (after detection)
    GoRoute(
      path: AppRoutes.scanReview,
      name: 'scanReview',
      builder: (context, state) => const IngredientReviewScreen(),
    ),

    // Suggestions from scan (dual-lane)
    GoRoute(
      path: AppRoutes.scanSuggestions,
      name: 'scanSuggestions',
      builder: (context, state) => const SuggestionsScreen(),
    ),

    // Recipe library
    GoRoute(
      path: AppRoutes.recipes,
      name: 'recipes',
      builder: (context, state) => const RecipeListScreen(),
    ),

    // Create recipe (must be before :id to avoid conflict)
    GoRoute(
      path: AppRoutes.recipeCreate,
      name: 'recipeCreate',
      builder: (context, state) => const RecipeCreateScreen(),
    ),

    // Recipe detail
    GoRoute(
      path: AppRoutes.recipeDetail,
      name: 'recipeDetail',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return RecipeDetailScreen(recipeId: id);
      },
    ),

    // Ingredient checklist gate
    GoRoute(
      path: AppRoutes.ingredientChecklist,
      name: 'ingredientChecklist',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return IngredientChecklistScreen(recipeId: id);
      },
    ),

    // Cook Now — zero-setup freestyle entry
    GoRoute(
      path: AppRoutes.cookNow,
      name: 'cookNow',
      builder: (context, state) => const CookNowScreen(),
    ),

    // Recipe suggestions (dual-lane)
    GoRoute(
      path: AppRoutes.suggestions,
      name: 'suggestions',
      builder: (context, state) => const SuggestionsScreen(),
    ),

    // Session setup (before live session)
    GoRoute(
      path: AppRoutes.sessionSetup,
      name: 'sessionSetup',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final title = state.uri.queryParameters['title'];
        return SessionSetupScreen(sessionId: id, recipeTitle: title);
      },
    ),

    // Live cooking session
    GoRoute(
      path: AppRoutes.session,
      name: 'session',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return LiveSessionScreen(sessionId: id);
      },
    ),

    // Side-by-side visual guide
    GoRoute(
      path: AppRoutes.visionGuide,
      name: 'visionGuide',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return VisionGuideScreen(sessionId: id);
      },
    ),

    // Post-session completion
    GoRoute(
      path: AppRoutes.postSession,
      name: 'postSession',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return PostSessionScreen(sessionId: id);
      },
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Page not found',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            state.uri.toString(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go(AppRoutes.recipes),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);
