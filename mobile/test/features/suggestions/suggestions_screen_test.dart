import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/scan/models/scan_models.dart';
import 'package:ratatouille/features/scan/providers/scan_provider.dart';
import 'package:ratatouille/features/suggestions/screens/suggestions_screen.dart';

void main() {
  late ScanProvider provider;

  setUp(() {
    final mockClient = http_testing.MockClient((request) async {
      return http.Response('{}', 200);
    });
    final apiClient = ApiClient(
      httpClient: mockClient,
      baseUrl: 'http://localhost',
      tokenProvider: () async => 'test-token',
    );
    provider = ScanProvider(apiClient: apiClient);
  });

  Widget buildWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<ScanProvider>.value(
        value: provider,
        child: const SuggestionsScreen(),
      ),
    );
  }

  group('SuggestionsScreen', () {
    testWidgets('shows empty state when no suggestions', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('No suggestions available. Go back and scan your ingredients.'),
          findsOneWidget);
    });

    testWidgets('shows lane headers when suggestions loaded', (tester) async {
      // Pre-populate suggestions via reflection-safe approach
      provider.setSuggestionsForTest(SuggestionsResponse(
        scanId: 'scan-1',
        fromSaved: [
          RecipeSuggestion(
            suggestionId: 's1',
            sourceType: 'saved_recipe',
            title: 'Pasta Carbonara',
            matchScore: 0.85,
            sourceLabel: 'Saved',
            estimatedTimeMin: 30,
            difficulty: 'Medium',
          ),
        ],
        buddyRecipes: [
          RecipeSuggestion(
            suggestionId: 's2',
            sourceType: 'buddy_generated',
            title: 'Quick Stir Fry',
            matchScore: 0.72,
            sourceLabel: 'Buddy',
          ),
        ],
        totalSuggestions: 2,
      ));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('From Your Saved Recipes'), findsOneWidget);
      expect(find.text('AI Buddy Recipes'), findsOneWidget);
      expect(find.text('Pasta Carbonara'), findsOneWidget);
      expect(find.text('Quick Stir Fry'), findsOneWidget);
    });

    testWidgets('shows match percentage and metadata', (tester) async {
      provider.setSuggestionsForTest(SuggestionsResponse(
        scanId: 'scan-1',
        fromSaved: [
          RecipeSuggestion(
            suggestionId: 's1',
            sourceType: 'saved_recipe',
            title: 'Test Recipe',
            matchScore: 0.92,
            sourceLabel: 'Saved',
            estimatedTimeMin: 45,
            difficulty: 'Easy',
            missingIngredients: ['butter'],
          ),
        ],
        buddyRecipes: [],
        totalSuggestions: 1,
      ));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('92% match'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('1 missing'), findsOneWidget);
    });

    testWidgets('shows "Why this recipe?" button', (tester) async {
      provider.setSuggestionsForTest(SuggestionsResponse(
        scanId: 'scan-1',
        fromSaved: [
          RecipeSuggestion(
            suggestionId: 's1',
            sourceType: 'saved_recipe',
            title: 'Test',
            matchScore: 0.8,
            sourceLabel: 'Saved',
          ),
        ],
        buddyRecipes: [],
        totalSuggestions: 1,
      ));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Why this recipe?'), findsOneWidget);
    });

    testWidgets('shows Start Cooking button', (tester) async {
      provider.setSuggestionsForTest(SuggestionsResponse(
        scanId: 'scan-1',
        fromSaved: [],
        buddyRecipes: [
          RecipeSuggestion(
            suggestionId: 's1',
            sourceType: 'buddy_generated',
            title: 'Test',
            matchScore: 0.7,
            sourceLabel: 'Buddy',
          ),
        ],
        totalSuggestions: 1,
      ));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Start Cooking'), findsOneWidget);
    });
  });
}
