import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/scan/providers/scan_provider.dart';
import 'package:ratatouille/features/scan/screens/scan_screen.dart';

Widget _buildTestWidget({ScanProvider? provider}) {
  final scanProvider = provider ??
      ScanProvider(apiClient: ApiClient(baseUrl: 'http://localhost'));

  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, __) => const ScanScreen(),
      ),
      GoRoute(
        path: '/scan/review',
        builder: (_, __) => const Scaffold(body: Text('Review')),
      ),
      GoRoute(
        path: '/recipes',
        builder: (_, __) => const Scaffold(body: Text('Recipes')),
      ),
    ],
  );

  return ChangeNotifierProvider<ScanProvider>.value(
    value: scanProvider,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('ScanScreen', () {
    testWidgets('shows source selector', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Fridge'), findsOneWidget);
      expect(find.text('Pantry'), findsOneWidget);
    });

    testWidgets('shows capture guidance with photo count', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('0/6'), findsOneWidget);
      expect(find.textContaining('minimum 2 required'), findsOneWidget);
    });

    testWidgets('shows camera and gallery buttons', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    });

    testWidgets('shows manual entry fallback', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enter ingredients manually'), findsOneWidget);
    });

    testWidgets('does not show scan button with < 2 images', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Scan Ingredients'), findsNothing);
    });

    testWidgets('shows app title', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Scan Your Kitchen'), findsOneWidget);
    });
  });
}
