import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/vision_guide/screens/vision_guide_screen.dart';

void main() {
  Widget buildTestWidget({String sessionId = 'test-session'}) {
    return MaterialApp(
      home: VisionGuideScreen(sessionId: sessionId),
    );
  }

  group('VisionGuideScreen', () {
    testWidgets('renders with four tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Cooking Tools'), findsOneWidget);
      expect(find.text('Vision'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Taste'), findsOneWidget);
      expect(find.text('Recovery'), findsOneWidget);
    });

    testWidgets('shows back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('VisionCheckTab', () {
    testWidgets('renders camera preview and capture button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Camera Preview'), findsOneWidget);
      expect(find.text('Check Doneness'), findsOneWidget);
    });

    testWidgets('capture button is tappable and handles gracefully', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check Doneness'));
      await tester.pumpAndSettle();

      // After tap (camera unavailable in test), should show error or return to idle
      // The button should still be present (no crash)
      expect(find.text('Check Doneness'), findsOneWidget);
    });
  });

  group('VisionCheckTab confidence display', () {
    testWidgets('vision check tab renders capture button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Check Doneness'), findsOneWidget);
    });
  });

  group('GuideImageTab', () {
    testWidgets('renders side-by-side areas and generate button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Switch to Guide tab
      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Your Frame'), findsOneWidget);
      expect(find.text('Target State'), findsOneWidget);
      expect(find.text('Generate Guide Image'), findsOneWidget);
    });

    testWidgets('shows stage dropdown', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Target Stage'), findsOneWidget);
    });
  });

  group('TasteCheckTab', () {
    testWidgets('renders prompt and taste check button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste'));
      await tester.pumpAndSettle();

      // Conversational prompt (not Five Taste Dimensions)
      expect(find.textContaining('Ready for a taste check'), findsOneWidget);
      expect(find.text('Taste Check'), findsOneWidget);
    });

    testWidgets('taste check shows prompt and diagnostic input', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste Check'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Take a small spoonful'), findsOneWidget);
      // Quick diagnostic chips are primary (voice-first UX)
      expect(find.text("It's flat"), findsOneWidget);
      // Text input is visible (not behind ExpansionTile)
      expect(find.text('Or describe in your own words...'), findsOneWidget);
    });
  });

  group('RecoveryTab', () {
    testWidgets('renders emergency header and input', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recovery'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      // Text input is directly visible (not behind ExpansionTile)
      expect(find.text('Or describe in your own words...'), findsOneWidget);
      expect(find.text('Help Me Recover'), findsOneWidget);
    });

    testWidgets('shows quick error chips', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recovery'));
      await tester.pumpAndSettle();

      expect(find.text('Burnt'), findsOneWidget);
      expect(find.text('Overcooked'), findsOneWidget);
      expect(find.text('Sauce broke'), findsOneWidget);
    });
  });

  group('RecoveryTab quick chips', () {
    testWidgets('recovery tab renders quick error chips', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recovery'));
      await tester.pumpAndSettle();

      expect(find.text('Burnt'), findsOneWidget);
      expect(find.text('Overcooked'), findsOneWidget);
    });
  });
}
