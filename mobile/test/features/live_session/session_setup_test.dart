import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/live_session/screens/session_setup_screen.dart';

void main() {
  late ApiClient apiClient;

  setUp(() {
    final mockClient = http_testing.MockClient((request) async {
      return http.Response('{"session_id": "s1", "status": "active", "ws_endpoint": "/v1/live/s1"}', 200);
    });
    apiClient = ApiClient(
      httpClient: mockClient,
      baseUrl: 'http://localhost',
      tokenProvider: () async => 'test-token',
    );
  });

  Widget buildWidget({String? title}) {
    return MaterialApp(
      home: Provider<ApiClient>.value(
        value: apiClient,
        child: SessionSetupScreen(
          sessionId: 'test-session-1',
          recipeTitle: title ?? 'Pasta Carbonara',
        ),
      ),
    );
  }

  group('SessionSetupScreen', () {
    testWidgets('shows recipe title', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Pasta Carbonara'), findsOneWidget);
    });

    testWidgets('shows session ID', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.textContaining('test-session-1'), findsOneWidget);
    });

    testWidgets('shows phone setup instructions', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Phone Setup'), findsOneWidget);
      expect(find.textContaining('volume'), findsOneWidget);
      expect(find.textContaining('screen on'), findsOneWidget);
    });

    testWidgets('shows ambient listening toggle', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Ambient Listening'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('shows Start Cooking button', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Start Cooking'), findsOneWidget);
    });

    testWidgets('shows Go Back button', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Go Back'), findsOneWidget);
    });

    testWidgets('ambient toggle changes state', (tester) async {
      await tester.pumpWidget(buildWidget());

      final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchWidget.value, isTrue); // Default on

      // Toggle off
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      final updatedSwitch = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(updatedSwitch.value, isFalse);
    });
  });
}
