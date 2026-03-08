import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/scan/models/scan_models.dart';

void main() {
  group('DetectedIngredient', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'Red Bell Pepper',
        'name_normalized': 'red bell pepper',
        'confidence': 0.92,
        'source_image_index': 1,
      };

      final ing = DetectedIngredient.fromJson(json);
      expect(ing.name, 'Red Bell Pepper');
      expect(ing.nameNormalized, 'red bell pepper');
      expect(ing.confidence, 0.92);
      expect(ing.sourceImageIndex, 1);
    });

    test('tier returns high for >= 0.8', () {
      final ing = DetectedIngredient(
        name: 'Egg',
        nameNormalized: 'egg',
        confidence: 0.85,
      );
      expect(ing.tier, ConfidenceTier.high);
    });

    test('tier returns medium for 0.5 - 0.79', () {
      final ing = DetectedIngredient(
        name: 'Cheese',
        nameNormalized: 'cheese',
        confidence: 0.65,
      );
      expect(ing.tier, ConfidenceTier.medium);
    });

    test('tier returns low for < 0.5', () {
      final ing = DetectedIngredient(
        name: 'Mystery item',
        nameNormalized: 'mystery item',
        confidence: 0.3,
      );
      expect(ing.tier, ConfidenceTier.low);
    });

    test('fromJson handles missing fields gracefully', () {
      final ing = DetectedIngredient.fromJson({});
      expect(ing.name, '');
      expect(ing.confidence, 0.0);
      expect(ing.sourceImageIndex, 0);
    });
  });

  group('ScanCreateResponse', () {
    test('fromJson parses correctly', () {
      final json = {
        'scan_id': 'abc-123',
        'capture_mode': 'images',
        'image_count': 3,
        'status': 'pending',
      };

      final resp = ScanCreateResponse.fromJson(json);
      expect(resp.scanId, 'abc-123');
      expect(resp.captureMode, 'images');
      expect(resp.imageCount, 3);
      expect(resp.status, 'pending');
    });
  });

  group('DetectResponse', () {
    test('fromJson parses ingredients list', () {
      final json = {
        'scan_id': 'scan-1',
        'detected_ingredients': [
          {
            'name': 'Milk',
            'name_normalized': 'milk',
            'confidence': 0.9,
            'source_image_index': 0,
          },
        ],
        'status': 'detected',
        'low_confidence_count': 0,
      };

      final resp = DetectResponse.fromJson(json);
      expect(resp.detectedIngredients.length, 1);
      expect(resp.detectedIngredients.first.name, 'Milk');
      expect(resp.status, 'detected');
    });
  });

  group('RecipeSuggestion', () {
    test('fromJson parses all fields', () {
      final json = {
        'suggestion_id': 's1',
        'source_type': 'saved_recipe',
        'recipe_id': 'r1',
        'title': 'Pasta',
        'description': 'Simple pasta',
        'match_score': 0.85,
        'matched_ingredients': ['pasta', 'garlic'],
        'missing_ingredients': ['salt'],
        'estimated_time_min': 20,
        'difficulty': 'easy',
        'cuisine': 'Italian',
        'source_label': 'Saved',
        'explanation': 'You have most ingredients.',
        'grounding_sources': ['scan match'],
        'assumptions': [],
      };

      final s = RecipeSuggestion.fromJson(json);
      expect(s.title, 'Pasta');
      expect(s.isSaved, true);
      expect(s.isBuddy, false);
      expect(s.matchPercent, 85);
      expect(s.missingIngredients.length, 1);
      expect(s.explanation, 'You have most ingredients.');
    });

    test('buddy suggestion has correct flags', () {
      final s = RecipeSuggestion.fromJson({
        'source_type': 'buddy_generated',
        'title': 'AI Recipe',
        'match_score': 0.7,
        'source_label': 'Buddy',
        'assumptions': ['Assumes basic pantry staples'],
      });

      expect(s.isBuddy, true);
      expect(s.isSaved, false);
      expect(s.assumptions.length, 1);
    });
  });

  group('SuggestionsResponse', () {
    test('fromJson parses dual lanes', () {
      final json = {
        'scan_id': 'scan-1',
        'from_saved': [
          {
            'suggestion_id': 's1',
            'source_type': 'saved_recipe',
            'title': 'Saved Pasta',
            'match_score': 0.8,
            'source_label': 'Saved',
          },
        ],
        'buddy_recipes': [
          {
            'suggestion_id': 's2',
            'source_type': 'buddy_generated',
            'title': 'AI Stir Fry',
            'match_score': 0.7,
            'source_label': 'Buddy',
          },
        ],
        'total_suggestions': 2,
      };

      final resp = SuggestionsResponse.fromJson(json);
      expect(resp.fromSaved.length, 1);
      expect(resp.buddyRecipes.length, 1);
      expect(resp.totalSuggestions, 2);
    });
  });

  group('ExplainResponse', () {
    test('fromJson parses explanation', () {
      final json = {
        'suggestion_id': 's1',
        'title': 'Pasta',
        'explanation_full': 'This is from your saved recipes.',
        'grounding_sources': ['scan match'],
        'matched_ingredients': ['pasta'],
        'missing_ingredients': ['salt'],
        'assumptions': [],
        'low_confidence_warnings': ['garlic'],
        'match_score': 0.8,
      };

      final resp = ExplainResponse.fromJson(json);
      expect(resp.explanationFull, 'This is from your saved recipes.');
      expect(resp.lowConfidenceWarnings, ['garlic']);
    });
  });

  group('StartSessionResponse', () {
    test('fromJson parses nested session/next', () {
      final json = {
        'recipe_id': 'r1',
        'scan_id': 'scan-1',
        'suggestion_id': 's1',
        'session': {'session_id': 'sess-1', 'status': 'created'},
        'next': {
          'endpoint': '/v1/sessions/sess-1/activate',
          'method': 'POST',
        },
      };

      final resp = StartSessionResponse.fromJson(json);
      expect(resp.sessionId, 'sess-1');
      expect(resp.sessionStatus, 'created');
      expect(resp.nextEndpoint, '/v1/sessions/sess-1/activate');
    });
  });
}
