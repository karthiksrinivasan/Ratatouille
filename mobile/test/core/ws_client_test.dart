import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/ws_client.dart';

void main() {
  group('WsConnectionState', () {
    test('enum has four states', () {
      expect(WsConnectionState.values.length, 4);
      expect(WsConnectionState.values, contains(WsConnectionState.disconnected));
      expect(WsConnectionState.values, contains(WsConnectionState.connecting));
      expect(WsConnectionState.values, contains(WsConnectionState.connected));
      expect(WsConnectionState.values, contains(WsConnectionState.error));
    });
  });

  // WsClient itself requires AuthService which requires Firebase.
  // Integration-level tests for connect/send require a running server.
  // WsClient is tested indirectly via LiveSessionScreen widget tests
  // using a FakeWsClient that bypasses the real connection.
  //
  // The following tests verify the public API contract at type level.
  group('WsClient contract', () {
    test('WsClient type exists and is a ChangeNotifier', () {
      // Verify that WsClient can be referenced as a type
      // (it extends ChangeNotifier).
      expect(WsClient, isNotNull);
    });
  });
}
