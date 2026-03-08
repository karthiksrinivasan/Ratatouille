import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/scan/screens/scan_screen.dart';
import '../features/suggestions/screens/suggestions_screen.dart';
import '../features/live_session/screens/live_session_screen.dart';
import '../features/vision_guide/screens/vision_guide_screen.dart';
import '../features/post_session/screens/post_session_screen.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  AppRoutes._();

  static const String scan = '/scan';
  static const String suggestions = '/suggestions';
  static const String session = '/session/:id';
  static const String visionGuide = '/vision-guide/:id';
  static const String postSession = '/post-session/:id';

  /// Build a session path with the given [id].
  static String sessionPath(String id) => '/session/$id';

  /// Build a vision guide path with the given [id].
  static String visionGuidePath(String id) => '/vision-guide/$id';

  /// Build a post-session path with the given [id].
  static String postSessionPath(String id) => '/post-session/$id';
}

/// Top-level router configuration for the app.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.scan,
  debugLogDiagnostics: true,
  routes: [
    // Scan / pantry capture flow (home screen)
    GoRoute(
      path: AppRoutes.scan,
      name: 'scan',
      builder: (context, state) => const ScanScreen(),
    ),

    // Recipe suggestions (dual-lane)
    GoRoute(
      path: AppRoutes.suggestions,
      name: 'suggestions',
      builder: (context, state) => const SuggestionsScreen(),
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
            onPressed: () => context.go(AppRoutes.scan),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);
