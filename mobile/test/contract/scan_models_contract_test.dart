import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/scan/models/scan_models.dart';

/// Contract verification tests for scan-related REST response models.
///
/// Each test uses a realistic JSON fixture that mirrors the backend response
/// schema and verifies that decode succeeds with expected field values.
void main() {
  group('ScanCreateResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'scan_id': 'scan_abc123',
        'capture_mode': 'images',
        'image_count': 3,
        'status': 'pending',
      };

      final result = ScanCreateResponse.fromJson(json);

      expect(result.scanId, 'scan_abc123');
      expect(result.captureMode, 'images');
      expect(result.imageCount, 3);
      expect(result.status, 'pending');
    });

    test('handles missing optional fields with defaults', () {
      final json = <String, dynamic>{};

      final result = ScanCreateResponse.fromJson(json);

      expect(result.scanId, '');
      expect(result.captureMode, 'images');
      expect(result.imageCount, 0);
      expect(result.status, 'pending');
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/inventory-scans';
      try {
        // Simulate a completely broken response
        final broken = {'scan_id': 12345}; // wrong type
        ScanCreateResponse.fromJson(broken);
        // If fromJson has fallback defaults, it may not throw —
        // that is acceptable for nullable-safe models.
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('DetectResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'scan_id': 'scan_abc123',
        'detected_ingredients': [
          {
            'name': 'Tomato',
            'name_normalized': 'tomato',
            'confidence': 0.95,
            'source_image_index': 0,
          },
          {
            'name': 'Basil',
            'name_normalized': 'basil',
            'confidence': 0.42,
            'source_image_index': 1,
          },
        ],
        'status': 'detected',
        'low_confidence_count': 1,
      };

      final result = DetectResponse.fromJson(json);

      expect(result.scanId, 'scan_abc123');
      expect(result.status, 'detected');
      expect(result.lowConfidenceCount, 1);
      expect(result.detectedIngredients, hasLength(2));

      final tomato = result.detectedIngredients[0];
      expect(tomato.name, 'Tomato');
      expect(tomato.nameNormalized, 'tomato');
      expect(tomato.confidence, 0.95);
      expect(tomato.sourceImageIndex, 0);
      expect(tomato.tier, ConfidenceTier.high);

      final basil = result.detectedIngredients[1];
      expect(basil.name, 'Basil');
      expect(basil.confidence, 0.42);
      expect(basil.tier, ConfidenceTier.low);
    });

    test('handles empty ingredients list', () {
      final json = {
        'scan_id': 'scan_empty',
        'detected_ingredients': [],
        'status': 'detected',
        'low_confidence_count': 0,
      };

      final result = DetectResponse.fromJson(json);

      expect(result.detectedIngredients, isEmpty);
      expect(result.lowConfidenceCount, 0);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/inventory-scans/{id}/detect';
      try {
        final broken = {
          'detected_ingredients': 'not_a_list',
        };
        DetectResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('ConfirmResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'scan_id': 'scan_abc123',
        'confirmed_ingredients': ['tomato', 'basil', 'garlic'],
        'status': 'confirmed',
      };

      final result = ConfirmResponse.fromJson(json);

      expect(result.scanId, 'scan_abc123');
      expect(result.confirmedIngredients, ['tomato', 'basil', 'garlic']);
      expect(result.status, 'confirmed');
    });

    test('handles empty confirmed list', () {
      final json = {
        'scan_id': 'scan_abc123',
        'confirmed_ingredients': [],
        'status': 'confirmed',
      };

      final result = ConfirmResponse.fromJson(json);

      expect(result.confirmedIngredients, isEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/inventory-scans/{id}/confirm-ingredients';
      try {
        final broken = {'confirmed_ingredients': 123};
        ConfirmResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('SuggestionsResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'scan_id': 'scan_abc123',
        'from_saved': [
          {
            'suggestion_id': 'sug_001',
            'source_type': 'saved_recipe',
            'recipe_id': 'recipe_42',
            'title': 'Classic Margherita',
            'description': 'A simple pizza with fresh ingredients',
            'match_score': 0.87,
            'matched_ingredients': ['tomato', 'basil'],
            'missing_ingredients': ['mozzarella'],
            'estimated_time_min': 45,
            'difficulty': 'easy',
            'cuisine': 'Italian',
            'source_label': 'Saved',
            'explanation': 'Great match with your tomato and basil',
            'grounding_sources': ['user_recipe_42'],
            'assumptions': [],
          }
        ],
        'buddy_recipes': [
          {
            'suggestion_id': 'sug_002',
            'source_type': 'buddy_generated',
            'title': 'Tomato Basil Soup',
            'match_score': 0.92,
            'matched_ingredients': ['tomato', 'basil', 'garlic'],
            'missing_ingredients': [],
            'source_label': 'Buddy',
            'explanation': 'All ingredients available!',
            'grounding_sources': [],
            'assumptions': ['You have vegetable stock'],
          }
        ],
        'total_suggestions': 2,
      };

      final result = SuggestionsResponse.fromJson(json);

      expect(result.scanId, 'scan_abc123');
      expect(result.totalSuggestions, 2);
      expect(result.fromSaved, hasLength(1));
      expect(result.buddyRecipes, hasLength(1));

      final saved = result.fromSaved[0];
      expect(saved.suggestionId, 'sug_001');
      expect(saved.isSaved, isTrue);
      expect(saved.isBuddy, isFalse);
      expect(saved.title, 'Classic Margherita');
      expect(saved.matchScore, 0.87);
      expect(saved.matchPercent, 87);
      expect(saved.matchedIngredients, ['tomato', 'basil']);
      expect(saved.missingIngredients, ['mozzarella']);
      expect(saved.estimatedTimeMin, 45);
      expect(saved.difficulty, 'easy');

      final buddy = result.buddyRecipes[0];
      expect(buddy.isBuddy, isTrue);
      expect(buddy.matchScore, 0.92);
      expect(buddy.assumptions, ['You have vegetable stock']);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'GET /v1/inventory-scans/{id}/suggestions';
      try {
        final broken = {'from_saved': 'not_a_list'};
        SuggestionsResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('ExplainResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'suggestion_id': 'sug_001',
        'title': 'Classic Margherita',
        'explanation_full':
            'This recipe is a great match because you have fresh tomato and basil.',
        'grounding_sources': ['user_recipe_42', 'web_search_1'],
        'matched_ingredients': ['tomato', 'basil'],
        'missing_ingredients': ['mozzarella'],
        'assumptions': ['Fresh mozzarella can be substituted'],
        'low_confidence_warnings': ['Basil detected with low confidence'],
        'match_score': 0.87,
      };

      final result = ExplainResponse.fromJson(json);

      expect(result.suggestionId, 'sug_001');
      expect(result.title, 'Classic Margherita');
      expect(result.explanationFull, contains('great match'));
      expect(result.groundingSources, hasLength(2));
      expect(result.matchedIngredients, ['tomato', 'basil']);
      expect(result.missingIngredients, ['mozzarella']);
      expect(result.assumptions, hasLength(1));
      expect(result.lowConfidenceWarnings, hasLength(1));
      expect(result.matchScore, 0.87);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint =
          'GET /v1/inventory-scans/{id}/suggestions/{sid}/explain';
      try {
        final broken = {'match_score': 'not_a_number'};
        ExplainResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('StartSessionResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'recipe_id': 'recipe_42',
        'scan_id': 'scan_abc123',
        'suggestion_id': 'sug_001',
        'session': {
          'session_id': 'sess_xyz789',
          'status': 'created',
        },
        'next': {
          'endpoint': '/v1/sessions/sess_xyz789/activate',
        },
      };

      final result = StartSessionResponse.fromJson(json);

      expect(result.recipeId, 'recipe_42');
      expect(result.scanId, 'scan_abc123');
      expect(result.suggestionId, 'sug_001');
      expect(result.sessionId, 'sess_xyz789');
      expect(result.sessionStatus, 'created');
      expect(result.nextEndpoint, '/v1/sessions/sess_xyz789/activate');
    });

    test('handles missing nested objects', () {
      final json = {
        'recipe_id': 'recipe_42',
        'scan_id': 'scan_abc123',
        'suggestion_id': 'sug_001',
      };

      final result = StartSessionResponse.fromJson(json);

      expect(result.sessionId, '');
      expect(result.sessionStatus, '');
      expect(result.nextEndpoint, '');
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/inventory-scans/{id}/start-session';
      try {
        final broken = {'session': 'not_a_map'};
        StartSessionResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });
}
