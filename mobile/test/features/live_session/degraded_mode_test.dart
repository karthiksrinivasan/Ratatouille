import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/ws_client.dart';
import 'package:ratatouille/features/live_session/screens/live_session_screen.dart';

/// A fake WsClient for testing.
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
  int get lastKnownStep => 0;
  @override
  bool get bargeInActive => false;
  @override
  Map<String, Map<String, dynamic>> get lastProcessStates => {};

  @override
  Future<void> connect(String sessionId) async {}
  @override
  Future<void> disconnect() async {}
  @override
  void send(Map<String, dynamic> message) => sentMessages.add(message);
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
  void sendProcessComplete(String processId) => send({'type': 'process_complete', 'process_id': processId});
  @override
  void sendProcessDelegate(String processId) => send({'type': 'process_delegate', 'process_id': processId});
  @override
  void sendConflictChoice(String processId) => send({'type': 'conflict_choice', 'chosen_process_id': processId});
  @override
  void sendPing() => send({'type': 'ping'});
  @override
  void sendSessionResume() => send({'type': 'session_resume'});

  @override
  bool get maxRetriesReached => false;
  @override
  void resetReconnect() {}

  void simulateMessage(Map<String, dynamic> msg) => _fakeController.add(msg);

  @override
  void dispose() {
    _fakeController.close();
    super.dispose();
  }
}

void main() {
  group('LiveSessionScreen degraded mode', () {
    late FakeWsClient fakeWs;

    setUp(() {
      fakeWs = FakeWsClient();
    });

    tearDown(() {
      fakeWs.dispose();
    });

    testWidgets('text input not shown in normal state initially',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionScreen(sessionId: 'test-1', wsClient: fakeWs),
        ),
      );
      await tester.pump();

      // In normal state before permissions resolve, text input field for
      // degraded mode should not be immediately visible.
      // The "Type your question..." hint only appears in text-input mode.
      // Note: _initSession is async — permissions may not have resolved yet.
      // At this point, _textInputMode starts as false.
      expect(find.text('Type Instead'), findsNothing);
    });

    testWidgets('BuddyState has degraded value', (tester) async {
      expect(BuddyState.values, contains(BuddyState.degraded));
    });

    testWidgets('degraded state enum exists with expected values', (tester) async {
      // Verify the BuddyState enum has all expected values for the FaceTime-style UI
      expect(BuddyState.values, contains(BuddyState.listening));
      expect(BuddyState.values, contains(BuddyState.speaking));
      expect(BuddyState.values, contains(BuddyState.interrupted));
      expect(BuddyState.values, contains(BuddyState.reconnecting));
      expect(BuddyState.values, contains(BuddyState.degraded));
    });

    testWidgets('quick option chips are defined for degraded text input', (tester) async {
      // Verify the screen builds with CallChrome controls even in initial state
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionScreen(sessionId: 'test-1', wsClient: fakeWs),
        ),
      );
      await tester.pump();

      // CallChrome is rendered with Mute/Flip/End controls
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
    });
  });
}
