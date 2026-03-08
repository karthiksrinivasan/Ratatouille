import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/scan/screens/home_screen.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('renders app title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      expect(find.text('Ratatouille'), findsOneWidget);
      expect(find.text('Your AI cooking companion'), findsOneWidget);
    });

    testWidgets('shows scan entry card', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
    });

    testWidgets('shows browse recipes entry card', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      expect(find.text('Browse Recipes'), findsOneWidget);
    });

    testWidgets('shows hackathon MVP footer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      expect(find.text('Hackathon MVP'), findsOneWidget);
    });

    testWidgets('entry cards are tappable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      // Verify InkWell exists for interaction
      expect(find.byType(InkWell), findsAtLeast(2));
    });
  });
}
