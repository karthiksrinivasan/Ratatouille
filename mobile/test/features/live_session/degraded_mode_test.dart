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

  void simulateMessage(Map<String, dynamic> msg) => _fakeController.add(msg);

  @override
  void dispose() {
    _fakeController.close();
    super.dispose();
  }
}

/// A WsClient that simulates degraded (error/disconnected) state.
class DegradedFakeWsClient extends ChangeNotifier implements WsClient {
  final StreamController<Map<String, dynamic>> _fakeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sentMessages = [];

  @override
  Stream<Map<String, dynamic>> get messages => _fakeController.stream;
  @override
  WsConnectionState get state => WsConnectionState.error;
  @override
  bool get isConnected => false;
  @override
  String? get lastError => 'Connection failed';
  @override
  int get lastKnownStep => 0;
  @override
  bool get bargeInActive => false;
  @override
  Map<String, Map<String, dynamic>> get lastProcessStates => {};

  @override
  Future<void> connect(String sessionId) async {
    // Simulate connection failure → triggers degraded state
    notifyListeners();
  }
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

    testWidgets('Type Instead hidden in normal (voice-available) state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionScreen(sessionId: 'test-1', wsClient: fakeWs),
        ),
      );
      await tester.pump();

      // Type Instead should NOT be visible in normal (listening) state
      expect(find.text('Type Instead'), findsNothing);
    });

    testWidgets('degraded state shows text input bar automatically',
        (tester) async {
      // Use a FakeWsClient that reports degraded/error state
      final degradedWs = DegradedFakeWsClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionScreen(sessionId: 'test-1', wsClient: degradedWs),
        ),
      );
      await tester.pump();

      // In degraded state, text input bar shows automatically
      expect(find.byType(TextField), findsOneWidget);
      degradedWs.dispose();
    });

    testWidgets('text input sends voice_query in degraded mode',
        (tester) async {
      final degradedWs = DegradedFakeWsClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionScreen(sessionId: 'test-1', wsClient: degradedWs),
        ),
      );
      await tester.pump();

      // Text input bar is visible in degraded state
      await tester.enterText(find.byType(TextField), 'How long to boil?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      final voiceQueries = degradedWs.sentMessages.where(
        (m) => m['type'] == 'voice_query' && m['text'] == 'How long to boil?',
      );
      expect(voiceQueries, isNotEmpty);
      degradedWs.dispose();
    });

    testWidgets('BuddyState has degraded value', (tester) async {
      expect(BuddyState.values, contains(BuddyState.degraded));
    });
  });
}
