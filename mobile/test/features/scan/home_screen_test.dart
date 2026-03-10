import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ratatouille/core/auth_service.dart';
import 'package:ratatouille/features/scan/screens/home_screen.dart';

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
  group('HomeScreen', () {
    testWidgets('renders app title', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      expect(find.text('Ratatouille'), findsOneWidget);
      expect(find.text('Your AI cooking companion'), findsOneWidget);
    });

    testWidgets('shows scan entry card', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
    });

    testWidgets('shows browse recipes entry card', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      expect(find.text('Browse Recipes'), findsOneWidget);
    });

    testWidgets('shows hackathon MVP footer', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      // Scroll down to reveal footer
      await tester.scrollUntilVisible(
        find.text('Hackathon MVP'),
        200,
      );
      expect(find.text('Hackathon MVP'), findsOneWidget);
    });

    testWidgets('entry cards are tappable', (tester) async {
      await tester.pumpWidget(_wrapHomeScreen());
      // Verify InkWell exists for interaction
      expect(find.byType(InkWell), findsAtLeast(2));
    });
  });
}
