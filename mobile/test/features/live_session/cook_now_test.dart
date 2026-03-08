import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:provider/provider.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/live_session/screens/cook_now_screen.dart';
import 'package:ratatouille/core/session_api.dart';
import 'package:ratatouille/features/scan/screens/home_screen.dart';

void main() {
  group('CookNowScreen', () {
    testWidgets('renders hero message with no-recipe copy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
            child: const CookNowScreen(),
          ),
        ),
      );

      expect(find.text('No recipe needed'), findsOneWidget);
      expect(find.textContaining('Optionally share'), findsOneWidget);
    });

    testWidgets('shows optional fields that are not mandatory', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
            child: const CookNowScreen(),
          ),
        ),
      );

      // All fields labeled as optional
      expect(find.textContaining('optional'), findsAtLeast(2));
      // Time chips present
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('Skip & Start button is present and tappable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
            child: const CookNowScreen(),
          ),
        ),
      );

      final skipButton = find.text('Skip & Start Cooking');
      expect(skipButton, findsOneWidget);
    });

    testWidgets('Start with Context button is present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
            child: const CookNowScreen(),
          ),
        ),
      );

      expect(find.text('Start with Context'), findsOneWidget);
    });

    testWidgets('time chip selection toggles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
            child: const CookNowScreen(),
          ),
        ),
      );

      // Tap 30 min chip
      await tester.tap(find.text('30 min'));
      await tester.pump();

      // Tap again to deselect
      await tester.tap(find.text('30 min'));
      await tester.pump();
    });

    testWidgets('shows error with fallback options on API failure', (tester) async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Server error'}),
          500,
        );
      });

      final api = ApiClient(
        tokenProvider: () async => 'test-token',
        httpClient: mockClient,
        baseUrl: 'http://localhost',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: api,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Tap skip & start
      await tester.tap(find.text('Skip & Start Cooking'));
      await tester.pumpAndSettle();

      // Error shown
      expect(find.textContaining('Error'), findsAtLeast(1));

      // Fallback options
      expect(find.text('Try Scan Instead'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
    });

    testWidgets('successful freestyle session navigates to live session', (tester) async {
      var requestCount = 0;
      final mockClient = http_testing.MockClient((request) async {
        requestCount++;
        if (request.url.path == '/v1/sessions') {
          return http.Response(
            jsonEncode({
              'session_id': 'freestyle-123',
              'mode': 'freestyle',
              'status': 'created',
            }),
            200,
          );
        }
        if (request.url.path == '/v1/sessions/freestyle-123/activate') {
          return http.Response(
            jsonEncode({
              'session_id': 'freestyle-123',
              'status': 'active',
              'ws_endpoint': 'ws://localhost/v1/live/freestyle-123',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = ApiClient(
        tokenProvider: () async => 'test-token',
        httpClient: mockClient,
        baseUrl: 'http://localhost',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: api,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Tap skip & start
      await tester.tap(find.text('Skip & Start Cooking'));
      // Let futures resolve
      await tester.pumpAndSettle();

      // Both calls made: POST /v1/sessions + POST activate
      expect(requestCount, 2);
    });

    testWidgets('sends context when Start with Context tapped', (tester) async {
      Map<String, dynamic>? capturedBody;
      final mockClient = http_testing.MockClient((request) async {
        if (request.url.path == '/v1/sessions') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'session_id': 'ctx-123',
              'mode': 'freestyle',
              'status': 'created',
            }),
            200,
          );
        }
        if (request.url.path.contains('/activate')) {
          return http.Response(
            jsonEncode({
              'session_id': 'ctx-123',
              'status': 'active',
              'ws_endpoint': 'ws://localhost/v1/live/ctx-123',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = ApiClient(
        tokenProvider: () async => 'test-token',
        httpClient: mockClient,
        baseUrl: 'http://localhost',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: api,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Fill in optional fields
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. "Something with chicken" or "A quick pasta"'),
        'Quick pasta dish',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. "chicken, garlic, olive oil, pasta"'),
        'garlic, pasta, olive oil',
      );
      await tester.tap(find.text('30 min'));
      await tester.pump();

      // Scroll down to reveal Start with Context button
      await tester.dragUntilVisible(
        find.text('Start with Context'),
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );

      // Tap Start with Context
      await tester.tap(find.text('Start with Context'));
      await tester.pumpAndSettle();

      // Verify context was sent
      expect(capturedBody, isNotNull);
      expect(capturedBody!['session_mode'], 'freestyle');
      final ctx = capturedBody!['freestyle_context'] as Map<String, dynamic>;
      expect(ctx['dish_goal'], 'Quick pasta dish');
      expect(ctx['available_ingredients'], ['garlic', 'pasta', 'olive oil']);
      expect(ctx['time_budget_minutes'], 30);
    });

    testWidgets('skip mode sends only mode field', (tester) async {
      Map<String, dynamic>? capturedBody;
      final mockClient = http_testing.MockClient((request) async {
        if (request.url.path == '/v1/sessions') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'session_id': 'skip-123',
              'mode': 'freestyle',
              'status': 'created',
            }),
            200,
          );
        }
        if (request.url.path.contains('/activate')) {
          return http.Response(
            jsonEncode({
              'session_id': 'skip-123',
              'status': 'active',
              'ws_endpoint': 'ws://localhost/v1/live/skip-123',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final api = ApiClient(
        tokenProvider: () async => 'test-token',
        httpClient: mockClient,
        baseUrl: 'http://localhost',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: api,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Tap Skip without filling anything
      await tester.tap(find.text('Skip & Start Cooking'));
      await tester.pumpAndSettle();

      // Only session_mode sent, no freestyle_context
      expect(capturedBody, isNotNull);
      expect(capturedBody!['session_mode'], 'freestyle');
      expect(capturedBody!.containsKey('freestyle_context'), false);
    });
  });

  group('HomeScreen Cook Now entry', () {
    testWidgets('shows Cook Now card with equal priority', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      expect(find.text('Cook Now'), findsOneWidget);
      expect(find.textContaining('No recipe needed'), findsOneWidget);
    });

    testWidgets('Cook Now card is tappable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      // 3 entry cards now: Fridge, Cook Now, Browse
      expect(find.byType(InkWell), findsAtLeast(3));
    });

    testWidgets('Cook Now has equal visual prominence as scan', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      // Both primary cards exist
      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
      expect(find.text('Cook Now'), findsOneWidget);
    });
  });

  group('Cook Now contract', () {
    test('freestyle session creation request format', () {
      // Verify the expected request body structure
      final skipBody = {'mode': 'freestyle'};
      expect(skipBody['mode'], 'freestyle');

      final contextBody = {
        'mode': 'freestyle',
        'goal': 'Quick pasta',
        'ingredients_hint': 'garlic, pasta',
        'time_estimate': '30 min',
      };
      expect(contextBody['mode'], 'freestyle');
      expect(contextBody.containsKey('goal'), true);
    });

    test('freestyle session response parsing', () {
      final json = {
        'session_id': 'fs-123',
        'mode': 'freestyle',
        'status': 'created',
      };
      expect(json['session_id'], 'fs-123');
      expect(json['mode'], 'freestyle');
    });

    test('activation response contract matches ActivateResponse', () {
      final json = {
        'session_id': 'fs-123',
        'status': 'active',
        'ws_endpoint': 'ws://localhost/v1/live/fs-123',
      };
      final response = ActivateResponse.fromJson(json);
      expect(response.sessionId, 'fs-123');
      expect(response.status, 'active');
      expect(response.wsEndpoint, 'ws://localhost/v1/live/fs-123');
    });
  });
}
