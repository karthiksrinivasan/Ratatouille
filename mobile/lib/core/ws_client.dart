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

      final uri = Uri.parse('$_baseWsUrl/ws/session/$sessionId?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // Wait for the connection to be ready.
      await _channel!.ready;

      _setState(WsConnectionState.connected);

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _lastError = e.toString();
      _setState(WsConnectionState.error);
    }
  }

  /// Close the current WebSocket connection.
  Future<void> disconnect() async {
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

  /// Send a text-only chat message.
  void sendText(String text) {
    send({'type': 'text', 'content': text});
  }

  /// Send an audio chunk (base64-encoded).
  void sendAudio(String base64Audio) {
    send({'type': 'audio', 'content': base64Audio});
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
  }

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
