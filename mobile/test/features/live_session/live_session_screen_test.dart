import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/ws_client.dart';
import 'package:ratatouille/features/live_session/screens/live_session_screen.dart';

/// A fake WsClient that uses ChangeNotifier directly, avoiding Firebase.
class FakeWsClient extends ChangeNotifier implements WsClient {
  final StreamController<Map<String, dynamic>> _fakeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sentMessages = [];

  @override
  Stream<Map<String, dynamic>> get messages => _fakeController.stream;

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  String? get lastError => null;

  @override
  Future<void> connect(String sessionId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  @override
  void sendVoiceQuery(String text) => send({'type': 'voice_query', 'text': text});

  @override
  void sendAudio(String base64Audio) => send({'type': 'voice_audio', 'audio': base64Audio});

  @override
  void sendStepComplete(int step) => send({'type': 'step_complete', 'step': step});

  @override
  void sendAmbientToggle(bool enabled) => send({'type': 'ambient_toggle', 'enabled': enabled});

  @override
  void sendBargeIn(String text) => send({'type': 'barge_in', 'text': text});

  @override
  void sendResumeInterrupted() => send({'type': 'resume_interrupted'});

  @override
  void sendVisionCheck(String frameUri) => send({'type': 'vision_check', 'frame_uri': frameUri});

  @override
  void sendPing() => send({'type': 'ping'});

  /// Simulate receiving a message from the server.
  void simulateMessage(Map<String, dynamic> msg) {
    _fakeController.add(msg);
  }

  @override
  void dispose() {
    _fakeController.close();
    super.dispose();
  }
}

void main() {
  group('LiveSessionScreen', () {
    late FakeWsClient fakeWs;

    setUp(() {
      fakeWs = FakeWsClient();
    });

    tearDown(() {
      fakeWs.dispose();
    });

    Widget buildApp() {
      return MaterialApp(
        // Use Material 2 to avoid shader asset issues in test environment
        theme: ThemeData(useMaterial3: false),
        home: LiveSessionScreen(
          sessionId: 'test-session-123',
          wsClient: fakeWs,
        ),
      );
    }

    testWidgets('shows Cooking Session title', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Cooking Session'), findsOneWidget);
    });

    testWidgets('shows state banner with Listening', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Listening'), findsOneWidget);
    });

    testWidgets('shows step indicator', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Step 1'), findsOneWidget);
    });

    testWidgets('shows hands-busy controls', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Next Step'), findsOneWidget);
      expect(find.text('Vision Check'), findsOneWidget);
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.text('Finish Session'), findsOneWidget);
    });

    testWidgets('ambient indicator toggles', (tester) async {
      await tester.pumpWidget(buildApp());

      // Find the hearing_disabled icon (ambient off by default)
      expect(find.byIcon(Icons.hearing_disabled), findsOneWidget);

      // Tap the ambient toggle
      await tester.tap(find.byIcon(Icons.hearing_disabled));
      await tester.pump();

      // Should send ambient_toggle message
      expect(fakeWs.sentMessages.length, 1);
      expect(fakeWs.sentMessages.last['type'], 'ambient_toggle');
      expect(fakeWs.sentMessages.last['enabled'], true);
    });

    testWidgets('Next Step sends step_complete', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Next Step'));
      await tester.pump();

      expect(fakeWs.sentMessages.length, 1);
      expect(fakeWs.sentMessages.last['type'], 'step_complete');
    });

    testWidgets('Repeat sends voice_query', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Repeat'));
      await tester.pump();

      expect(fakeWs.sentMessages.length, 1);
      expect(fakeWs.sentMessages.last['type'], 'voice_query');
      expect(fakeWs.sentMessages.last['text'], 'repeat quickly');
    });

    testWidgets('buddy_message updates display', (tester) async {
      await tester.pumpWidget(buildApp());

      fakeWs.simulateMessage({
        'type': 'buddy_message',
        'text': 'Boil the water first.',
        'step': 2,
      });
      await tester.pump();

      expect(find.text('Boil the water first.'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.text('Buddy speaking'), findsOneWidget);

      // Drain the 2-second auto-transition timer to avoid pending timer error
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('buddy_interrupted shows chip', (tester) async {
      await tester.pumpWidget(buildApp());

      fakeWs.simulateMessage({
        'type': 'buddy_interrupted',
        'interrupted_text': 'I was saying...',
        'resumable': true,
      });
      await tester.pump();

      expect(find.text('Interrupted — tap to resume summary'), findsOneWidget);
      expect(find.text('Interrupted'), findsOneWidget);
    });

    testWidgets('tapping resume chip sends resume_interrupted', (tester) async {
      await tester.pumpWidget(buildApp());

      fakeWs.simulateMessage({
        'type': 'buddy_interrupted',
        'interrupted_text': 'I was saying...',
        'resumable': true,
      });
      await tester.pump();

      await tester.tap(find.text('Interrupted — tap to resume summary'));
      await tester.pump();

      expect(fakeWs.sentMessages.length, 1);
      expect(fakeWs.sentMessages.last['type'], 'resume_interrupted');
    });

    testWidgets('mode_update updates ambient state', (tester) async {
      await tester.pumpWidget(buildApp());

      fakeWs.simulateMessage({
        'type': 'mode_update',
        'ambient_listen': true,
      });
      await tester.pump();

      // Ambient is now enabled — should show hearing icon
      expect(find.byIcon(Icons.hearing), findsOneWidget);
    });

    testWidgets('error message updates display', (tester) async {
      await tester.pumpWidget(buildApp());

      fakeWs.simulateMessage({
        'type': 'error',
        'message': 'Connection lost.',
      });
      await tester.pump();

      expect(find.text('Connection lost.'), findsOneWidget);
    });
  });
}
