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

    testWidgets('capture button shows loading state', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check Doneness'));
      await tester.pump();

      expect(find.text('Analyzing...'), findsOneWidget);

      // Wait for future to complete
      await tester.pumpAndSettle();
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
    testWidgets('renders taste dimensions and check button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste'));
      await tester.pumpAndSettle();

      expect(find.text('Five Taste Dimensions'), findsOneWidget);
      expect(find.text('Salt'), findsOneWidget);
      expect(find.text('Acid'), findsOneWidget);
      expect(find.text('Sweet'), findsOneWidget);
      expect(find.text('Fat'), findsOneWidget);
      expect(find.text('Umami'), findsOneWidget);
      expect(find.text('Taste Check'), findsOneWidget);
    });

    testWidgets('taste check shows prompt and diagnostic input', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Taste Check'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Good moment to taste'), findsOneWidget);
      // Quick diagnostic chips are primary (voice-first UX)
      expect(find.text("It's flat"), findsOneWidget);
      // Text input is behind ExpansionTile — verify the toggle exists
      expect(find.text('Or type your own description'), findsOneWidget);
    });
  });

  group('RecoveryTab', () {
    testWidgets('renders emergency header and input', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recovery'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      // Text input is behind ExpansionTile — verify the toggle exists
      expect(find.text('Or describe in your own words'), findsOneWidget);
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
