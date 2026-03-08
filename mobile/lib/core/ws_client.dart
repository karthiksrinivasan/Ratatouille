import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_service.dart';
import 'env_config.dart';

/// Connection state for the WebSocket.
enum WsConnectionState { disconnected, connecting, connected, error }

/// WebSocket client for live cooking session communication.
///
/// Handles authentication, automatic reconnection, and message
/// serialization/deserialization.
class WsClient extends ChangeNotifier {
  final AuthService _authService;
  final String _baseWsUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  WsConnectionState _state = WsConnectionState.disconnected;
  String? _lastError;
  String? _currentSessionId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 5;

  /// Controller that broadcasts incoming messages to listeners.
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  WsClient({
    required AuthService authService,
    String? baseWsUrl,
  })  : _authService = authService,
        _baseWsUrl = baseWsUrl ?? EnvConfig.wsUrl;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  WsConnectionState get state => _state;
  bool get isConnected => _state == WsConnectionState.connected;
  String? get lastError => _lastError;

  /// Stream of decoded JSON messages from the server.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  // ---------------------------------------------------------------------------
  // Connect / Disconnect
  // ---------------------------------------------------------------------------

  /// Open a WebSocket connection to the given session.
  Future<void> connect(String sessionId) async {
    if (_state == WsConnectionState.connecting ||
        _state == WsConnectionState.connected) {
      return;
    }

    _setState(WsConnectionState.connecting);

    try {
      final token = await _authService.getIdToken();
      if (token == null) {
        throw Exception('User is not authenticated');
      }

      final uri = Uri.parse('$_baseWsUrl/v1/live/$sessionId?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // Wait for the connection to be ready.
      await _channel!.ready;

      _currentSessionId = sessionId;
      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _lastError = e.toString();
      _setState(WsConnectionState.error);
      _scheduleReconnect();
    }
  }

  /// Close the current WebSocket connection.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _currentSessionId = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------------

  /// Send a JSON message to the server.
  void send(Map<String, dynamic> message) {
    if (_state != WsConnectionState.connected || _channel == null) {
      throw StateError('WebSocket is not connected');
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// Send a voice query (active query — VM-02).
  void sendVoiceQuery(String text) {
    send({'type': 'voice_query', 'text': text});
  }

  /// Send an audio chunk (base64-encoded PCM — VM-01/VM-02).
  void sendAudio(String base64Audio) {
    send({'type': 'voice_audio', 'audio': base64Audio});
  }

  /// Send step-complete event.
  void sendStepComplete(int step) {
    send({'type': 'step_complete', 'step': step});
  }

  /// Send ambient toggle event.
  void sendAmbientToggle(bool enabled) {
    send({'type': 'ambient_toggle', 'enabled': enabled});
  }

  /// Send barge-in event.
  void sendBargeIn(String text) {
    send({'type': 'barge_in', 'text': text});
  }

  /// Send resume-interrupted request.
  void sendResumeInterrupted() {
    send({'type': 'resume_interrupted'});
  }

  /// Send vision check with frame URI.
  void sendVisionCheck(String frameUri) {
    send({'type': 'vision_check', 'frame_uri': frameUri});
  }

  /// Send process complete event (Epic 5).
  void sendProcessComplete(String processId) {
    send({'type': 'process_complete', 'process_id': processId});
  }

  /// Send process delegate event (Epic 5).
  void sendProcessDelegate(String processId) {
    send({'type': 'process_delegate', 'process_id': processId});
  }

  /// Send conflict choice event (Epic 5).
  void sendConflictChoice(String processId) {
    send({'type': 'conflict_choice', 'chosen_process_id': processId});
  }

  /// Send a ping to keep the connection alive.
  void sendPing() {
    send({'type': 'ping'});
  }

  /// Request session state after reconnect so client can resume.
  void sendSessionResume() {
    send({'type': 'session_resume'});
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _onData(dynamic data) {
    try {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      _messageController.add(decoded);
    } catch (e) {
      debugPrint('WsClient: failed to decode message: $e');
    }
  }

  void _onError(dynamic error) {
    _lastError = error.toString();
    _setState(WsConnectionState.error);
  }

  void _onDone() {
    _setState(WsConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// Schedule a reconnect with exponential backoff.
  void _scheduleReconnect() {
    if (_currentSessionId == null ||
        _reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }
    _reconnectAttempts++;
    final delay = Duration(
      milliseconds: 500 * (1 << (_reconnectAttempts - 1)), // 500ms, 1s, 2s, 4s, 8s
    );
    debugPrint('WsClient: reconnecting in ${delay.inMilliseconds}ms '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      final sessionId = _currentSessionId;
      if (sessionId != null) {
        _state = WsConnectionState.disconnected; // Allow connect()
        connect(sessionId);
      }
    });
  }

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
