import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/vision_guide/screens/vision_guide_screen.dart';

void main() {
  group('Epic 8 Vision/Guide/Taste/Recovery UX criteria', () {
    testWidgets('recovery card prioritizes immediate action first',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecoveryCard(
              result: {
                'type': 'recovery',
                'message':
                    'Take the pan off heat NOW.\n\nThe garlic is burning.\n\nPick out the dark pieces.',
                'techniques_affected': ['sauteing'],
              },
            ),
          ),
        ),
      );

      // Immediate action should be prominently displayed
      expect(find.text('Take the pan off heat NOW.'), findsOneWidget);
      // Secondary sections also visible
      expect(find.text('The garlic is burning.'), findsOneWidget);
      expect(find.text('Pick out the dark pieces.'), findsOneWidget);
    });

    testWidgets('vision result shows confidence badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisionResultCard(
              result: {
                'confidence': 'high',
                'message': 'The steak is well-seared',
                'recommendation': 'Flip now for even cooking',
              },
            ),
          ),
        ),
      );

      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('The steak is well-seared'), findsOneWidget);
      expect(find.text('Flip now for even cooking'), findsOneWidget);
    });

    testWidgets('vision result handles medium confidence', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisionResultCard(
              result: {
                'confidence': 'medium',
                'message': 'Might need more time',
              },
            ),
          ),
        ),
      );

      expect(find.text('MEDIUM'), findsOneWidget);
    });

    testWidgets('vision result handles low confidence with sensory check',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisionResultCard(
              result: {
                'confidence': 'low',
                'message': 'Hard to tell from the image',
                'sensory_check': 'Try pressing with tongs - it should spring back',
              },
            ),
          ),
        ),
      );

      expect(find.text('LOW'), findsOneWidget);
      expect(find.textContaining('pressing with tongs'), findsOneWidget);
    });

    testWidgets('guide image tab has side-by-side layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuideImageTab(sessionId: 'test-1'),
          ),
        ),
      );

      expect(find.text('Your Frame'), findsOneWidget);
      expect(find.text('Target State'), findsOneWidget);
      expect(find.text('Generate Guide Image'), findsOneWidget);
    });

    testWidgets('taste check shows five dimensions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasteCheckTab(sessionId: 'test-1'),
          ),
        ),
      );

      expect(find.text('Salt'), findsOneWidget);
      expect(find.text('Acid'), findsOneWidget);
      expect(find.text('Sweet'), findsOneWidget);
      expect(find.text('Fat'), findsOneWidget);
      expect(find.text('Umami'), findsOneWidget);
    });
  });
}
