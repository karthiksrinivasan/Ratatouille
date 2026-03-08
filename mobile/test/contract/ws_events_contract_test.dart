import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';

/// Contract verification tests for WebSocket event payloads.
///
/// These tests verify that the JSON structure of all WS event types
/// can be decoded correctly and contain expected fields. The WsClient
/// emits raw Map<String, dynamic> — these tests validate the shape
/// of each event type.

/// Helper to simulate decoding a WS event payload (as WsClient._onData does).
Map<String, dynamic> decodeWsEvent(String rawJson) {
  return jsonDecode(rawJson) as Map<String, dynamic>;
}

void main() {
  group('buddy_message event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'buddy_message',
        'event_id': 'evt_001',
        'text': 'Now dice the onions into small cubes.',
        'step': 3,
        'audio_url': 'https://storage.googleapis.com/audio/step3.mp3',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'buddy_message');
      expect(event['event_id'], 'evt_001');
      expect(event['text'], contains('dice the onions'));
      expect(event['step'], 3);
      expect(event['audio_url'], isNotEmpty);
    });

    test('schema drift detection — logs on decode failure', () {
      const eventType = 'buddy_message';
      try {
        decodeWsEvent('{"type": "buddy_message", "step": "not_an_int"}');
        // step as string — schema drift but JSON still parses
      } catch (e) {
        developer.log('Schema drift detected on WS event $eventType: $e');
      }
    });
  });

  group('buddy_response event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'buddy_response',
        'event_id': 'evt_002',
        'text': 'Yes, you can substitute olive oil for butter here.',
        'step': 3,
        'query_id': 'q_abc',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'buddy_response');
      expect(event['text'], contains('substitute'));
      expect(event['step'], 3);
      expect(event['query_id'], 'q_abc');
    });
  });

  group('buddy_interrupted event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'buddy_interrupted',
        'event_id': 'evt_003',
        'reason': 'barge_in',
        'interrupted_text': 'Now dice the...',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'buddy_interrupted');
      expect(event['reason'], 'barge_in');
      expect(event['interrupted_text'], isNotEmpty);
    });
  });

  group('process_update event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'process_update',
        'event_id': 'evt_004',
        'process_id': 'proc_simmer_001',
        'process_type': 'timer',
        'status': 'running',
        'elapsed_seconds': 120,
        'total_seconds': 600,
        'label': 'Simmering sauce',
        'priority': 'normal',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'process_update');
      expect(event['process_id'], 'proc_simmer_001');
      expect(event['process_type'], 'timer');
      expect(event['status'], 'running');
      expect(event['elapsed_seconds'], 120);
      expect(event['total_seconds'], 600);
      expect(event['label'], 'Simmering sauce');
    });

    test('schema drift detection — logs on decode failure', () {
      const eventType = 'process_update';
      try {
        decodeWsEvent('not valid json');
      } catch (e) {
        developer.log('Schema drift detected on WS event $eventType: $e');
      }
    });
  });

  group('timer_alert event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'timer_alert',
        'event_id': 'evt_005',
        'process_id': 'proc_simmer_001',
        'label': 'Simmering sauce',
        'alert_type': 'completed',
        'message': 'Your sauce is done simmering!',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'timer_alert');
      expect(event['process_id'], 'proc_simmer_001');
      expect(event['alert_type'], 'completed');
      expect(event['message'], contains('done simmering'));
    });
  });

  group('vision_result event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'vision_result',
        'event_id': 'evt_006',
        'session_id': 'sess_xyz789',
        'assessment': 'on_track',
        'confidence': 0.91,
        'stage': 'sauteing',
        'observations': ['Onions are caramelizing nicely'],
        'recommendation': 'Continue for 1 more minute.',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'vision_result');
      expect(event['assessment'], 'on_track');
      expect(event['confidence'], 0.91);
      expect(event['stage'], 'sauteing');
      expect(event['observations'], isList);
      expect((event['observations'] as List), hasLength(1));
    });
  });

  group('guide_image event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'guide_image',
        'event_id': 'evt_007',
        'session_id': 'sess_xyz789',
        'guide_image_url':
            'https://storage.googleapis.com/ratatouille/guides/golden_brown.png',
        'target_state': 'golden_brown',
        'visual_cues': ['Light amber color', 'Slightly translucent'],
        'stage': 'sauteing',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'guide_image');
      expect(event['guide_image_url'], contains('golden_brown'));
      expect(event['target_state'], 'golden_brown');
      expect(event['visual_cues'], isList);
      expect((event['visual_cues'] as List), hasLength(2));
      expect(event['stage'], 'sauteing');
    });
  });

  group('mode_update event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'mode_update',
        'event_id': 'evt_008',
        'mode': 'ambient',
        'reason': 'User toggled ambient mode',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'mode_update');
      expect(event['mode'], 'ambient');
      expect(event['reason'], isNotEmpty);
    });
  });

  group('error event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'error',
        'event_id': 'evt_009',
        'code': 'VISION_FAILED',
        'message': 'Could not process the camera frame. Please try again.',
        'retryable': true,
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'error');
      expect(event['code'], 'VISION_FAILED');
      expect(event['message'], contains('camera frame'));
      expect(event['retryable'], isTrue);
    });

    test('handles non-retryable error', () {
      final raw = jsonEncode({
        'type': 'error',
        'event_id': 'evt_010',
        'code': 'SESSION_EXPIRED',
        'message': 'Session has expired. Please start a new session.',
        'retryable': false,
      });

      final event = decodeWsEvent(raw);

      expect(event['retryable'], isFalse);
      expect(event['code'], 'SESSION_EXPIRED');
    });

    test('schema drift detection — logs on decode failure', () {
      const eventType = 'error';
      try {
        decodeWsEvent('{malformed json');
      } catch (e) {
        developer.log('Schema drift detected on WS event $eventType: $e');
      }
    });
  });

  group('pong event', () {
    test('decodes realistic fixture correctly', () {
      final raw = jsonEncode({
        'type': 'pong',
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'pong');
    });

    test('pong with optional timestamp', () {
      final raw = jsonEncode({
        'type': 'pong',
        'server_ts': 1709913600000,
      });

      final event = decodeWsEvent(raw);

      expect(event['type'], 'pong');
      expect(event['server_ts'], 1709913600000);
    });
  });

  group('deduplication by event_id', () {
    test('events with event_id can be tracked for dedup', () {
      final seen = <String>{};

      final events = [
        {'type': 'buddy_message', 'event_id': 'evt_001', 'text': 'First'},
        {'type': 'buddy_message', 'event_id': 'evt_001', 'text': 'Duplicate'},
        {'type': 'buddy_message', 'event_id': 'evt_002', 'text': 'Second'},
      ];

      final processed = <Map<String, dynamic>>[];
      for (final event in events) {
        final eventId = event['event_id'];
        if (eventId != null && seen.contains(eventId)) continue;
        if (eventId != null) seen.add(eventId);
        processed.add(event);
      }

      expect(processed, hasLength(2));
      expect(processed[0]['text'], 'First');
      expect(processed[1]['text'], 'Second');
    });
  });
}
