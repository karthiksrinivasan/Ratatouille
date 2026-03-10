import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/session_api.dart';

/// D8.18: Fixture-driven contract tests for all session API response models.
///
/// Each test loads a JSON fixture file and verifies that the corresponding
/// Dart model can decode it without errors and produces expected values.
/// This catches schema drift between backend and mobile early.
void main() {
  /// Helper to load a fixture file from test/fixtures/.
  Map<String, dynamic> loadFixture(String name) {
    final file = File('test/fixtures/$name');
    if (!file.existsSync()) {
      fail('Fixture file not found: test/fixtures/$name');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  group('Fixture-driven contract tests', () {
    test('ActivateResponse decodes from fixture', () {
      final json = loadFixture('activate_response.json');
      final result = ActivateResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.status, 'active');
      expect(result.wsEndpoint, contains('v1/live/'));
    });

    test('VisionCheckResponse decodes from fixture', () {
      final json = loadFixture('vision_check_response.json');
      final result = VisionCheckResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.assessment, 'on_track');
      expect(result.confidence, closeTo(0.87, 0.01));
      expect(result.stage, 'sauteing');
      expect(result.observations, hasLength(2));
      expect(result.recommendation, isNotEmpty);
    });

    test('VisualGuideResponse decodes from fixture', () {
      final json = loadFixture('visual_guide_response.json');
      final result = VisualGuideResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.guideImageUrl, contains('storage.googleapis.com'));
      expect(result.targetState, 'golden_brown_garlic');
      expect(result.visualCues, hasLength(2));
      expect(result.stage, 'sauteing_garlic');
    });

    test('TasteCheckResponse decodes from fixture', () {
      final json = loadFixture('taste_check_response.json');
      final result = TasteCheckResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.dimensions, hasLength(5));
      expect(result.dimensions['salt'], closeTo(0.65, 0.01));
      expect(result.dimensions['fat'], closeTo(0.8, 0.01));
      expect(result.recommendation, contains('lemon'));
      expect(result.confidence, 'high');
    });

    test('RecoveryResponse decodes from fixture', () {
      final json = loadFixture('recovery_response.json');
      final result = RecoveryResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.immediateAction, contains('off the heat'));
      expect(result.explanation, contains('bitter'));
      expect(result.alternativeActions, hasLength(2));
      expect(result.severity, 'high');
    });

    test('CompleteResponse decodes from fixture', () {
      final json = loadFixture('complete_response.json');
      final result = CompleteResponse.fromJson(json);

      expect(result.sessionId, 'sess_fixture_001');
      expect(result.status, 'completed');
      expect(result.summary, isNotNull);
      expect(result.summary!['total_steps'], 6);
      expect(result.summary!['duration_minutes'], 28);
    });

    test('All fixtures are valid JSON', () {
      final fixtureDir = Directory('test/fixtures');
      expect(fixtureDir.existsSync(), isTrue);
      final files = fixtureDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.json'),
          );
      expect(files, isNotEmpty, reason: 'No JSON fixture files found');
      for (final file in files) {
        expect(
          () => jsonDecode(file.readAsStringSync()),
          returnsNormally,
          reason: 'Invalid JSON in ${file.path}',
        );
      }
    });
  });
}
