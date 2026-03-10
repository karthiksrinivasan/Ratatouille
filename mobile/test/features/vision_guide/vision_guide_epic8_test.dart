import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/vision_guide/screens/vision_guide_screen.dart';

void main() {
  group('Epic 8 Vision/Guide/Taste/Recovery UX criteria', () {
    testWidgets('recovery tab prioritizes immediate action first',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecoveryTab(sessionId: 'test-1'),
          ),
        ),
      );

      // Recovery tab should show quick error chips and help button
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(find.text('Help Me Recover'), findsOneWidget);
      expect(find.text('Burnt'), findsOneWidget);
    });

    testWidgets('vision check tab renders capture button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VisionGuideScreen(sessionId: 'test-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Check Doneness'), findsOneWidget);
    });

    testWidgets('guide image tab has side-by-side layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GuideImageTab(sessionId: 'test-1'),
          ),
        ),
      );

      expect(find.text('Your Frame'), findsOneWidget);
      expect(find.text('Target State'), findsOneWidget);
      expect(find.text('Generate Guide Image'), findsOneWidget);
    });

    testWidgets('taste check shows conversational prompt', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TasteCheckTab(sessionId: 'test-1'),
          ),
        ),
      );

      // Now uses conversational style instead of five taste dimensions
      expect(find.textContaining('Ready for a taste check'), findsOneWidget);
      expect(find.text('Taste Check'), findsOneWidget);
    });
  });
}
