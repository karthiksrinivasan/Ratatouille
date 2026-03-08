import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ratatouille/features/live_session/widgets/process_bar.dart';
import 'package:ratatouille/features/live_session/widgets/conflict_chooser.dart';

void main() {
  group('CookingProcess', () {
    test('fromJson parses all fields', () {
      final p = CookingProcess.fromJson({
        'process_id': 'pid-1',
        'name': 'Boil water',
        'step_number': 1,
        'priority': 'P2',
        'state': 'countdown',
        'due_at': '2099-01-01T00:10:00',
        'duration_minutes': 8.0,
        'buddy_managed': false,
        'is_parallel': true,
      });
      expect(p.processId, 'pid-1');
      expect(p.name, 'Boil water');
      expect(p.stepNumber, 1);
      expect(p.priority, 'P2');
      expect(p.state, 'countdown');
      expect(p.durationMinutes, 8.0);
      expect(p.isParallel, true);
    });

    test('fromJson uses defaults for missing fields', () {
      final p = CookingProcess.fromJson({});
      expect(p.processId, '');
      expect(p.priority, 'P2');
      expect(p.state, 'pending');
      expect(p.buddyManaged, false);
    });
  });

  group('ProcessBar', () {
    testWidgets('hides when no processes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProcessBar(processes: []),
          ),
        ),
      );
      expect(find.byType(ProcessBar), findsOneWidget);
      // Should be a SizedBox.shrink
      expect(find.text('active'), findsNothing);
    });

    testWidgets('shows active count', (tester) async {
      final processes = [
        CookingProcess(processId: 'a', name: 'Boil water', stepNumber: 1, state: 'countdown'),
        CookingProcess(processId: 'b', name: 'Slice garlic', stepNumber: 2, state: 'in_progress'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessBar(processes: processes),
          ),
        ),
      );
      expect(find.text('2 active'), findsOneWidget);
    });

    testWidgets('shows process chips', (tester) async {
      final processes = [
        CookingProcess(processId: 'a', name: 'Step 1: Boil', stepNumber: 1, state: 'in_progress'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessBar(processes: processes),
          ),
        ),
      );
      // Should find some text related to the process
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    });

    testWidgets('calls onProcessTap', (tester) async {
      String? tappedId;
      final processes = [
        CookingProcess(processId: 'a', name: 'Step 1: Boil', stepNumber: 1, state: 'in_progress'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessBar(
              processes: processes,
              onProcessTap: (id) => tappedId = id,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pump();
      expect(tappedId, 'a');
    });
  });

  group('ConflictOption', () {
    test('fromJson parses correctly', () {
      final opt = ConflictOption.fromJson({
        'process_id': 'a',
        'name': 'Garlic',
        'urgency': 'About to burn!',
      });
      expect(opt.processId, 'a');
      expect(opt.name, 'Garlic');
      expect(opt.urgency, 'About to burn!');
    });
  });

  group('ConflictChooser', () {
    testWidgets('shows two option buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictChooser(
              options: [
                ConflictOption(processId: 'a', name: 'Garlic', urgency: 'Burning!'),
                ConflictOption(processId: 'b', name: 'Pasta', urgency: 'Al dente!'),
              ],
              message: 'Choose one!',
              timeoutSeconds: 30,
              onChoice: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Choose one!'), findsOneWidget);
      expect(find.textContaining('Handle A'), findsOneWidget);
      expect(find.textContaining('Handle B'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
    });

    testWidgets('calls onChoice when tapped', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictChooser(
              options: [
                ConflictOption(processId: 'a', name: 'Garlic', urgency: 'Burning!'),
                ConflictOption(processId: 'b', name: 'Pasta', urgency: 'Al dente!'),
              ],
              message: 'Choose one!',
              timeoutSeconds: 30,
              onChoice: (id) => chosen = id,
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('Handle A'));
      await tester.pump();
      expect(chosen, 'a');
    });

    testWidgets('countdown ticks down', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictChooser(
              options: [
                ConflictOption(processId: 'a', name: 'Garlic', urgency: 'Burning!'),
                ConflictOption(processId: 'b', name: 'Pasta', urgency: 'Al dente!'),
              ],
              message: 'Choose one!',
              timeoutSeconds: 5,
              onChoice: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('5s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4s'), findsOneWidget);
    });
  });
}
