import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/session_api.dart';

/// Contract verification tests for session-related REST response models.
///
/// Each test uses a realistic JSON fixture and verifies that decode succeeds
/// with expected field values.
void main() {
  group('ActivateResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'status': 'active',
        'ws_endpoint': 'wss://api.example.com/v1/live/sess_xyz789',
      };

      final result = ActivateResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.status, 'active');
      expect(result.wsEndpoint, 'wss://api.example.com/v1/live/sess_xyz789');
    });

    test('handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final result = ActivateResponse.fromJson(json);

      expect(result.sessionId, '');
      expect(result.status, '');
      expect(result.wsEndpoint, '');
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/activate';
      try {
        final broken = {'session_id': 12345};
        ActivateResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('VisionCheckResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'assessment': 'on_track',
        'confidence': 0.89,
        'stage': 'sauteing',
        'observations': [
          'Onions are translucent',
          'Oil temperature looks good',
        ],
        'recommendation': 'Continue sauteing for 2 more minutes.',
      };

      final result = VisionCheckResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.assessment, 'on_track');
      expect(result.confidence, 0.89);
      expect(result.stage, 'sauteing');
      expect(result.observations, hasLength(2));
      expect(result.observations[0], 'Onions are translucent');
      expect(result.recommendation, contains('2 more minutes'));
    });

    test('handles empty observations', () {
      final json = {
        'session_id': 'sess_xyz789',
        'assessment': 'needs_attention',
        'confidence': 0.6,
        'stage': 'boiling',
        'observations': [],
        'recommendation': 'Reduce heat slightly.',
      };

      final result = VisionCheckResponse.fromJson(json);

      expect(result.observations, isEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/vision-check';
      try {
        final broken = {'confidence': 'not_a_number'};
        VisionCheckResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('VisualGuideResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'guide_image_url':
            'https://storage.googleapis.com/ratatouille/guides/sauteing.png',
        'target_state': 'golden_brown',
        'visual_cues': [
          'Look for a light golden color',
          'Edges should be slightly crispy',
        ],
        'stage': 'sauteing',
      };

      final result = VisualGuideResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.guideImageUrl, contains('storage.googleapis.com'));
      expect(result.targetState, 'golden_brown');
      expect(result.visualCues, hasLength(2));
      expect(result.stage, 'sauteing');
    });

    test('handles empty visual cues', () {
      final json = {
        'session_id': 'sess_xyz789',
        'guide_image_url': '',
        'target_state': 'mixed',
        'visual_cues': [],
        'stage': 'mixing',
      };

      final result = VisualGuideResponse.fromJson(json);

      expect(result.visualCues, isEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/visual-guide';
      try {
        final broken = {'visual_cues': 'not_a_list'};
        VisualGuideResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('TasteCheckResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'dimensions': {
          'sweetness': 0.3,
          'saltiness': 0.7,
          'sourness': 0.2,
          'umami': 0.6,
          'bitterness': 0.1,
        },
        'recommendation': 'Add a pinch of salt to balance the flavors.',
        'confidence': 'high',
      };

      final result = TasteCheckResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.dimensions, hasLength(5));
      expect(result.dimensions['sweetness'], 0.3);
      expect(result.dimensions['saltiness'], 0.7);
      expect(result.recommendation, contains('salt'));
      expect(result.confidence, 'high');
    });

    test('handles empty dimensions', () {
      final json = {
        'session_id': 'sess_xyz789',
        'dimensions': <String, dynamic>{},
        'recommendation': 'Tastes good!',
        'confidence': 'medium',
      };

      final result = TasteCheckResponse.fromJson(json);

      expect(result.dimensions, isEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/taste-check';
      try {
        final broken = {'dimensions': 'not_a_map'};
        TasteCheckResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('RecoveryResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'immediate_action': 'Remove from heat immediately.',
        'explanation':
            'The sauce has started to burn on the bottom of the pan.',
        'alternative_actions': [
          'Transfer to a new pan',
          'Add water to cool the pan',
        ],
        'severity': 'high',
      };

      final result = RecoveryResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.immediateAction, 'Remove from heat immediately.');
      expect(result.explanation, contains('burn'));
      expect(result.alternativeActions, hasLength(2));
      expect(result.severity, 'high');
    });

    test('handles empty alternative actions', () {
      final json = {
        'session_id': 'sess_xyz789',
        'immediate_action': 'Stir more frequently.',
        'explanation': 'Minor sticking detected.',
        'alternative_actions': [],
        'severity': 'low',
      };

      final result = RecoveryResponse.fromJson(json);

      expect(result.alternativeActions, isEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/recover';
      try {
        final broken = {'alternative_actions': 'not_a_list'};
        RecoveryResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });

  group('CompleteResponse contract', () {
    test('decodes realistic fixture correctly', () {
      final json = {
        'session_id': 'sess_xyz789',
        'status': 'completed',
        'summary': {
          'total_steps': 8,
          'completed_steps': 8,
          'duration_minutes': 42,
          'vision_checks': 3,
          'recovery_actions': 1,
        },
      };

      final result = CompleteResponse.fromJson(json);

      expect(result.sessionId, 'sess_xyz789');
      expect(result.status, 'completed');
      expect(result.summary, isNotNull);
      expect(result.summary!['total_steps'], 8);
      expect(result.summary!['duration_minutes'], 42);
    });

    test('handles null summary', () {
      final json = {
        'session_id': 'sess_xyz789',
        'status': 'completed',
      };

      final result = CompleteResponse.fromJson(json);

      expect(result.summary, isNull);
    });

    test('schema drift detection — logs on decode failure', () {
      const endpoint = 'POST /v1/sessions/{id}/complete';
      try {
        final broken = {'summary': 'not_a_map'};
        CompleteResponse.fromJson(broken);
      } catch (e) {
        developer.log('Schema drift detected on $endpoint: $e');
      }
    });
  });
}
