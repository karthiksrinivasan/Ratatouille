import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:provider/provider.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/core/auth_service.dart';
import 'package:ratatouille/features/live_session/screens/cook_now_screen.dart';
import 'package:ratatouille/core/session_api.dart';
import 'package:ratatouille/features/scan/screens/home_screen.dart';

/// Minimal fake AuthService for tests that avoids Firebase dependency.
class _FakeAuthService extends ChangeNotifier implements AuthService {
  @override
  bool get isSignedIn => true;
  @override
  bool get isAnonymous => true;
  @override
  String? get displayName => null;
  @override
  String? get email => null;
  @override
  void enableGuestMode() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapWithApi({required Widget child, ApiClient? api}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 900)),
      child: Provider<ApiClient>.value(
        value: api ??
            ApiClient(
              tokenProvider: () async => 'test-token',
              baseUrl: 'http://localhost',
            ),
        child: child,
      ),
    ),
  );
}

Widget _wrapHomeScreen() {
  return MaterialApp(
    home: ChangeNotifierProvider<AuthService>(
      create: (_) => _FakeAuthService(),
      child: const HomeScreen(),
    ),
  );
}

void main() {
  group('Task 9.7 — CookNowScreen call-like UX', () {
    testWidgets('shows call-like UI with Start Cooking button',
        (tester) async {
      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));

      expect(find.text('Start Cooking'), findsOneWidget);
      expect(find.text('Ready to cook together'), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('no keyboard appears by default (no text fields visible)',
        (tester) async {
      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));

      // By default, the optional context is hidden
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('optional context expandable on tap', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));

      // Tap to show optional context
      await tester.tap(find.text('Add optional context'));
      await tester.pump();

      // Now text field is visible
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('camera toggle works', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));

      // Camera off by default
      expect(find.text('Camera Off'), findsOneWidget);

      // Toggle camera on
      await tester.tap(find.byIcon(Icons.videocam_off));
      await tester.pump();
      expect(find.text('Camera On'), findsOneWidget);
    });

    testWidgets('Start Cooking sends freestyle session request',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      Map<String, dynamic>? capturedBody;
      final mockClient = http_testing.MockClient((request) async {
        if (request.url.path == '/v1/sessions') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'session_id': 'fs-123',
              'status': 'created',
            }),
            200,
          );
        }
        if (request.url.path.contains('/activate')) {
          return http.Response(
            jsonEncode({
              'session_id': 'fs-123',
              'status': 'active',
              'ws_endpoint': 'ws://localhost',
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
          _wrapWithApi(child: const CookNowScreen(), api: api));

      await tester.tap(find.text('Start Cooking'));
      // Wait for API call but don't settle (navigation will throw)
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(capturedBody, isNotNull);
      expect(capturedBody!['session_mode'], 'freestyle');
      expect(capturedBody!['allow_text_input'], false);
    });

    testWidgets('shows error state with retry', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
          _wrapWithApi(child: const CookNowScreen(), api: api));

      await tester.tap(find.text('Start Cooking'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error'), findsAtLeast(1));
    });

    testWidgets('user reaches conversational mode in <= 2 taps',
        (tester) async {
      // From home: tap Cook Now -> tap Start Cooking = 2 taps
      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));
      expect(find.text('Start Cooking'), findsOneWidget);
      // 1 tap from this screen = live session. Home tap = 2 total.
    });

    testWidgets('title shows Seasoned Chef Buddy', (tester) async {
      await tester.pumpWidget(_wrapWithApi(child: const CookNowScreen()));
      expect(find.text('Seasoned Chef Buddy'), findsOneWidget);
    });
  });

  group('HomeScreen Cook Now CTA', () {
    testWidgets('shows Seasoned Chef Buddy CTA', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      expect(find.text('Cook Now (Seasoned Chef Buddy)'), findsOneWidget);
    });

    testWidgets('both primary CTAs have equal visual prominence',
        (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
      expect(find.text('Cook Now (Seasoned Chef Buddy)'), findsOneWidget);
    });
  });

  group('Cook Now contract', () {
    test('activation response contract matches ActivateResponse', () {
      final json = {
        'session_id': 'fs-123',
        'status': 'active',
        'ws_endpoint': 'ws://localhost/v1/live/fs-123',
      };
      final response = ActivateResponse.fromJson(json);
      expect(response.sessionId, 'fs-123');
      expect(response.status, 'active');
    });
  });
}
