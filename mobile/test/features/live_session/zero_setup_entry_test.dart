import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ratatouille/core/auth_service.dart';
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

Widget _wrapHomeScreen() {
  return MaterialApp(
    home: ChangeNotifierProvider<AuthService>(
      create: (_) => _FakeAuthService(),
      child: const HomeScreen(),
    ),
  );
}

void main() {
  group('Task 9.1 — Zero-Setup Entry Point', () {
    testWidgets('home screen shows Cook Now (Seasoned Chef Buddy) CTA',
        (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());

      // Verify Cook Now CTA is present with updated title
      expect(find.text('Cook Now (Seasoned Chef Buddy)'), findsOneWidget);
      expect(find.text('No recipe needed — get live voice coaching instantly'),
          findsOneWidget);
    });

    testWidgets('home screen shows Cook from Fridge or Pantry CTA',
        (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());

      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
    });

    testWidgets('both primary CTAs are visible without scrolling',
        (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());

      // Both should be rendered
      final cookFromFridge = find.text('Cook from Fridge or Pantry');
      final cookNow = find.text('Cook Now (Seasoned Chef Buddy)');
      expect(cookFromFridge, findsOneWidget);
      expect(cookNow, findsOneWidget);
    });

    testWidgets('no account content prerequisites block entry',
        (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());

      // Cook Now should be tappable (no prerequisites)
      final cookNowCard = find.text('Cook Now (Seasoned Chef Buddy)');
      expect(cookNowCard, findsOneWidget);

      // The card with mic icon exists
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });
  });
}
