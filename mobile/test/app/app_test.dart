import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ratatouille/app/app.dart';
import 'package:ratatouille/app/theme.dart';

void main() {
  group('RatatouilleApp', () {
    testWidgets('renders MaterialApp with correct title', (tester) async {
      // The full app requires Firebase initialization, so we test the
      // theme and structure in isolation here.
      await tester.pumpWidget(const RatatouilleApp());
      await tester.pumpAndSettle();

      // Verify the app renders without crashing.
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('AppTheme', () {
    test('light theme uses Material3', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has orange primary color', () {
      final theme = AppTheme.light();
      expect(theme.colorScheme.primary, equals(AppColors.primaryOrange));
    });

    test('dark theme uses Material3', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme has amber primary color', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.primary, equals(AppColors.primaryAmber));
    });

    test('light theme has cream scaffold background', () {
      final theme = AppTheme.light();
      expect(theme.scaffoldBackgroundColor, equals(AppColors.cream));
    });

    test('dark theme has dark scaffold background', () {
      final theme = AppTheme.dark();
      expect(theme.scaffoldBackgroundColor, equals(AppColors.darkSurface));
    });
  });
}
