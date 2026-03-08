import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/session_api.dart';

void main() {
  group('ActivateResponse', () {
    test('parses from JSON', () {
      final r = ActivateResponse.fromJson({
        'session_id': 's1',
        'status': 'active',
        'ws_endpoint': '/v1/live/s1',
      });
      expect(r.sessionId, 's1');
      expect(r.status, 'active');
      expect(r.wsEndpoint, '/v1/live/s1');
    });

    test('handles missing fields', () {
      final r = ActivateResponse.fromJson({});
      expect(r.sessionId, '');
      expect(r.status, '');
    });
  });

  group('VisionCheckResponse', () {
    test('parses from JSON', () {
      final r = VisionCheckResponse.fromJson({
        'session_id': 's1',
        'assessment': 'needs more time',
        'confidence': 0.85,
        'stage': 'searing',
        'observations': ['surface browning incomplete'],
        'recommendation': 'Continue for 2 more minutes',
      });
      expect(r.confidence, 0.85);
      expect(r.observations, hasLength(1));
      expect(r.recommendation, contains('2 more minutes'));
    });
  });

  group('VisualGuideResponse', () {
    test('parses from JSON', () {
      final r = VisualGuideResponse.fromJson({
        'session_id': 's1',
        'guide_image_url': 'https://example.com/guide.png',
        'target_state': 'golden brown crust',
        'visual_cues': ['even color', 'slight char'],
        'stage': 'searing',
      });
      expect(r.guideImageUrl, contains('guide.png'));
      expect(r.visualCues, hasLength(2));
    });
  });

  group('TasteCheckResponse', () {
    test('parses dimensions map', () {
      final r = TasteCheckResponse.fromJson({
        'session_id': 's1',
        'dimensions': {'salt': 0.7, 'acid': 0.3, 'sweet': 0.5},
        'recommendation': 'Add a pinch of salt',
        'confidence': 'high',
      });
      expect(r.dimensions['salt'], 0.7);
      expect(r.dimensions.length, 3);
    });
  });

  group('RecoveryResponse', () {
    test('parses from JSON', () {
      final r = RecoveryResponse.fromJson({
        'session_id': 's1',
        'immediate_action': 'Remove from heat immediately',
        'explanation': 'The protein is overcooking',
        'alternative_actions': ['Lower heat', 'Add liquid'],
        'severity': 'high',
      });
      expect(r.immediateAction, contains('Remove'));
      expect(r.alternativeActions, hasLength(2));
      expect(r.severity, 'high');
    });
  });

  group('CompleteResponse', () {
    test('parses from JSON', () {
      final r = CompleteResponse.fromJson({
        'session_id': 's1',
        'status': 'completed',
        'summary': {'steps_completed': 8, 'total_time_min': 45},
      });
      expect(r.status, 'completed');
      expect(r.summary?['steps_completed'], 8);
    });

    test('handles null summary', () {
      final r = CompleteResponse.fromJson({
        'session_id': 's1',
        'status': 'completed',
      });
      expect(r.summary, isNull);
    });
  });
}
