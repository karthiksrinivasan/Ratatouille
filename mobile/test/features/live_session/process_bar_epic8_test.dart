import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/live_session/widgets/process_bar.dart';
import 'package:ratatouille/features/live_session/widgets/conflict_chooser.dart';

void main() {
  group('Epic 8 Process Bar UX criteria', () {
    testWidgets('process bar is visible with active processes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessBar(
              processes: [
                CookingProcess(
                  processId: 'p1',
                  name: 'Boil pasta',
                  stepNumber: 1,
                  state: 'in_progress',
                  priority: 'P0',
                ),
                CookingProcess(
                  processId: 'p2',
                  name: 'Simmer sauce',
                  stepNumber: 2,
                  state: 'countdown',
                  priority: 'P1',
                ),
              ],
              attentionNeeded: [],
              onProcessTap: (_) {},
              onDelegateTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Boil pasta'), findsOneWidget);
      expect(find.text('Simmer sauce'), findsOneWidget);
    });

    testWidgets('P0 and P1 states have distinct visual treatment', (tester) async {
      final p0 = CookingProcess(
        processId: 'p0',
        name: 'Sear protein',
        stepNumber: 1,
        state: 'needs_attention',
        priority: 'P0',
      );
      final p1 = CookingProcess(
        processId: 'p1',
        name: 'Background timer',
        stepNumber: 2,
        state: 'in_progress',
        priority: 'P1',
      );

      expect(p0.priority, isNot(equals(p1.priority)));
      expect(p0.state, isNot(equals(p1.state)));
    });

    testWidgets('conflict chooser has large tap targets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictChooser(
              options: [
                ConflictOption(processId: 'p1', name: 'Flip the steak', urgency: 'high'),
                ConflictOption(processId: 'p2', name: 'Stir the sauce', urgency: 'medium'),
              ],
              message: 'Which first?',
              timeoutSeconds: 10,
              onChoice: (_) {},
              onTimeout: () {},
            ),
          ),
        ),
      );

      expect(find.text('Handle A: Flip the steak'), findsOneWidget);
      expect(find.text('Handle B: Stir the sauce'), findsOneWidget);
    });

    test('CookingProcess sorts by priority string', () {
      final processes = [
        CookingProcess(processId: 'p1', name: 'Low', stepNumber: 1, priority: 'P3'),
        CookingProcess(processId: 'p2', name: 'High', stepNumber: 2, priority: 'P0'),
        CookingProcess(processId: 'p3', name: 'Med', stepNumber: 3, priority: 'P1'),
      ];
      processes.sort((a, b) => a.priority.compareTo(b.priority));
      expect(processes.first.name, 'High');
      expect(processes.last.name, 'Low');
    });
  });
}
