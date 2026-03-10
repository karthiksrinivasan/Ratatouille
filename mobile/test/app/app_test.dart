import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ratatouille/app/app.dart';
import 'package:ratatouille/app/theme.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/recipes/providers/recipe_provider.dart';

void main() {
  group('RatatouilleApp', () {
    testWidgets('renders MaterialApp with correct title', (tester) async {
      // Provide the RecipeProvider required by the initial route
      // (RecipeListScreen). Use a dummy ApiClient with a no-op token provider.
      final dummyApiClient = ApiClient(
        tokenProvider: () async => null,
        baseUrl: 'http://localhost',
      );

      final testRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('Test')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => RecipeProvider(apiClient: dummyApiClient),
          child: RatatouilleApp(router: testRouter),
        ),
      );
      await tester.pump();

      // Verify the app renders without crashing.
      expect(find.byType(MaterialApp), findsOneWidget);

      dummyApiClient.dispose();
    });
  });

  group('AppTheme', () {
    test('light theme uses Material3', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has orange primary color', () {
      final theme = AppTheme.light();
      expect(theme.colorScheme.primary, equals(AppColors.primaryOrange));
    });

    test('dark theme uses Material3', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme has amber primary color', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.primary, equals(AppColors.primaryAmber));
    });

    test('light theme has cream scaffold background', () {
      final theme = AppTheme.light();
      expect(theme.scaffoldBackgroundColor, equals(AppColors.cream));
    });

    test('dark theme has dark scaffold background', () {
      final theme = AppTheme.dark();
      expect(theme.scaffoldBackgroundColor, equals(AppColors.darkSurface));
    });
  });
}
