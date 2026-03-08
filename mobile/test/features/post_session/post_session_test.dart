import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/post_session/screens/post_session_screen.dart';

void main() {
  late ApiClient apiClient;

  setUp(() {
    final mockClient = http_testing.MockClient((request) async {
      return http.Response(
        jsonEncode({
          'session_id': 'test-1',
          'status': 'completed',
          'summary': {
            'steps_completed': 8,
            'total_time_min': 45,
            'processes_managed': 3,
          },
        }),
        200,
      );
    });
    apiClient = ApiClient(
      httpClient: mockClient,
      baseUrl: 'http://localhost',
      tokenProvider: () async => 'test-token',
    );
  });

  Widget buildWidget() {
    return MaterialApp(
      home: Provider<ApiClient>.value(
        value: apiClient,
        child: const PostSessionScreen(sessionId: 'test-1'),
      ),
    );
  }

  group('PostSessionScreen', () {
    testWidgets('shows completion celebration after API call',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      // First pump: initState triggers completeSession
      await tester.pump();
      // Wait for async completion
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Great job!'), findsOneWidget);
    });

    testWidgets('shows memory confirmation prompt', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Save to Memory?'), findsOneWidget);
      expect(find.text('Yes, Save'), findsOneWidget);
      expect(find.text('No Thanks'), findsOneWidget);
    });

    testWidgets('confirming memory shows confirmation message',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.ensureVisible(find.text('Yes, Save'));
      await tester.pump();
      await tester.tap(find.text('Yes, Save'));
      await tester.pump();

      expect(find.textContaining('Preferences saved'), findsOneWidget);
    });

    testWidgets('declining memory shows declined message', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.ensureVisible(find.text('No Thanks'));
      await tester.pump();
      await tester.tap(find.text('No Thanks'));
      await tester.pump();

      expect(find.textContaining('Nothing was saved'), findsOneWidget);
    });

    testWidgets('shows session summary with steps and time',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Session Summary'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('shows navigation buttons', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Back to Home'), findsOneWidget);
      expect(find.text('Cook Something Else'), findsOneWidget);
    });
  });
}
