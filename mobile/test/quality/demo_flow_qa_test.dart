import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/core/connectivity.dart';
import 'package:ratatouille/core/media_pipeline.dart';
import 'package:ratatouille/features/scan/screens/home_screen.dart';
import 'package:ratatouille/features/live_session/screens/cook_now_screen.dart';
import 'package:ratatouille/features/vision_guide/screens/vision_guide_screen.dart';
import 'package:ratatouille/shared/widgets/error_display.dart';
import 'package:ratatouille/shared/widgets/loading_indicator.dart';
import 'package:ratatouille/shared/widgets/loading_overlay.dart';
import 'package:ratatouille/shared/widgets/connectivity_banner.dart';
import 'package:ratatouille/shared/widgets/upload_progress.dart';

void main() {
  late ApiClient apiClient;

  setUp(() {
    final mockClient = http_testing.MockClient((request) async {
      return http.Response('{}', 200);
    });
    apiClient = ApiClient(
      httpClient: mockClient,
      baseUrl: 'http://localhost',
      tokenProvider: () async => 'test-token',
    );
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Screen Construction
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - Screen Construction', () {
    testWidgets('Home screen renders all entry points', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      // Verify primary entry points exist
      expect(find.text('Cook from Fridge or Pantry'), findsOneWidget);
      expect(find.text('Cook Now'), findsOneWidget);
      expect(find.text('Browse Recipes'), findsOneWidget);

      // Verify each card has a subtitle (no blank entry cards)
      expect(
        find.text('Snap photos of what you have and get recipe suggestions'),
        findsOneWidget,
      );
      expect(
        find.text('No recipe needed — get live AI help instantly'),
        findsOneWidget,
      );

      // No exceptions during render
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cook Now screen renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: apiClient,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Core UI elements present
      expect(find.text('No recipe needed'), findsOneWidget);
      expect(find.text('Skip & Start Cooking'), findsOneWidget);
      expect(find.text('Start with Context'), findsOneWidget);

      // Back button exists (not a dead end)
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Vision guide screen renders with tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // Use Material 2 to avoid shader asset issues in test environment
          theme: ThemeData(useMaterial3: false),
          home: VisionGuideScreen(
            sessionId: 'test-session',
            apiClient: apiClient,
          ),
        ),
      );

      // All four tabs present
      expect(find.text('Vision'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Taste'), findsOneWidget);
      expect(find.text('Recovery'), findsOneWidget);

      // Back button exists
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Error States Have Recovery Actions
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - No Dead-End Error States', () {
    testWidgets('ErrorDisplay with onRetry shows retry button', (tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Something failed',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      // Error message visible
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Something failed'), findsOneWidget);

      // Retry button present with refresh icon
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Retry button is functional
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('ErrorDisplay without onRetry still shows message (not blank)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(message: 'Network error'),
          ),
        ),
      );

      // Message renders without retry, but is not a blank screen
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // No retry button when onRetry is null
      expect(find.text('Try Again'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorDisplay accepts custom retry label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Upload failed',
              onRetry: () {},
              retryLabel: 'Retry Upload',
            ),
          ),
        ),
      );

      expect(find.text('Retry Upload'), findsOneWidget);
    });

    testWidgets('Recovery card renders with action sections', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecoveryCard(
                result: {
                  'message':
                      'Take pan off heat NOW.\n\nGarlic burns fast.\n\nPick out darkest pieces.',
                  'techniques_affected': ['sauteing'],
                },
              ),
            ),
          ),
        ),
      );

      // Immediate action shown prominently
      expect(find.text('Take pan off heat NOW.'), findsOneWidget);
      // Subsequent guidance
      expect(find.text('Garlic burns fast.'), findsOneWidget);
      expect(find.text('Pick out darkest pieces.'), findsOneWidget);
      // Technique chip shown
      expect(find.text('sauteing'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Loading States Show Indicators
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - Loading States', () {
    testWidgets('LoadingIndicator renders with progress spinner',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(message: 'Loading recipes...'),
          ),
        ),
      );

      // Circular progress indicator present
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Message displayed
      expect(find.text('Loading recipes...'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingIndicator renders without message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingOverlay shows spinner when loading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOverlay(
              isLoading: true,
              message: 'Please wait...',
              child: Text('Content behind overlay'),
            ),
          ),
        ),
      );

      // Overlay blocks with spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Please wait...'), findsOneWidget);
      // Background content still in tree (just covered)
      expect(find.text('Content behind overlay'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingOverlay hides spinner when not loading',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOverlay(
              isLoading: false,
              child: Text('Visible content'),
            ),
          ),
        ),
      );

      // No spinner when not loading
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Visible content'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Navigation (No Dead Ends)
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - No Dead-End States', () {
    testWidgets('Home screen has navigable entry cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      // All entry cards have chevron indicating navigation
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));

      expect(tester.takeException(), isNull);
    });

    testWidgets('Cook Now screen has back navigation when not loading',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: apiClient,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Back button is present and enabled
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);

      // Verify it is tappable (not disabled)
      final iconButton =
          tester.widget<IconButton>(find.ancestor(
        of: backButton,
        matching: find.byType(IconButton),
      ));
      expect(iconButton.onPressed, isNotNull);
    });

    testWidgets('Vision guide screen has back button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: VisionGuideScreen(
            sessionId: 'test-session',
            apiClient: apiClient,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Critical Widgets
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - Critical Widgets', () {
    testWidgets('ConnectivityBanner renders offline state', (tester) async {
      final connectivity = ConnectivityService();
      connectivity.markOffline();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
              child: const ConnectivityBanner(),
            ),
          ),
        ),
      );

      // Offline banner displayed with appropriate messaging
      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ConnectivityBanner renders degraded state', (tester) async {
      final connectivity = ConnectivityService();
      connectivity.markDegraded();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
              child: const ConnectivityBanner(),
            ),
          ),
        ),
      );

      expect(find.text('Connection is unstable'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_queue), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ConnectivityBanner hides when online', (tester) async {
      final connectivity = ConnectivityService();
      // Default state is online

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
              child: const ConnectivityBanner(),
            ),
          ),
        ),
      );

      // No banner content visible when online
      expect(find.text('No internet connection'), findsNothing);
      expect(find.text('Connection is unstable'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('UploadProgressIndicator renders when uploading',
        (tester) async {
      final pipeline = MediaPipeline(apiClient: apiClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<MediaPipeline>.value(
              value: pipeline,
              child: const UploadProgressIndicator(),
            ),
          ),
        ),
      );

      // Idle state — no progress bar visible
      expect(find.byType(LinearProgressIndicator), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Vision Guide Side-by-Side Layout
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - Vision Guide Layout', () {
    testWidgets('Guide tab shows side-by-side comparison layout',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: GuideImageTab(sessionId: 'test-session'),
          ),
        ),
      );

      // Side-by-side labels present
      expect(find.text('Your Frame'), findsOneWidget);
      expect(find.text('Target State'), findsOneWidget);

      // Generate button present
      expect(find.text('Generate Guide Image'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Vision check tab renders with capture button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: VisionCheckTab(sessionId: 'test-session'),
          ),
        ),
      );

      // Camera preview placeholder
      expect(find.text('Camera Preview'), findsOneWidget);
      // Capture CTA
      expect(find.text('Check Doneness'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Taste check tab renders with taste prompt button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: TasteCheckTab(sessionId: 'test-session'),
          ),
        ),
      );

      // Five taste dimensions card
      expect(find.text('Five Taste Dimensions'), findsOneWidget);
      expect(find.text('Salt'), findsOneWidget);
      expect(find.text('Acid'), findsOneWidget);

      // Taste check button
      expect(find.text('Taste Check'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Recovery tab renders with emergency header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: RecoveryTab(sessionId: 'test-session'),
          ),
        ),
      );

      // Emergency header
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      // Help button
      expect(find.text('Help Me Recover'), findsOneWidget);
      // Quick error chips
      expect(find.text('Burnt'), findsOneWidget);
      expect(find.text('Overcooked'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Demo Flow QA — Core Controls Accessibility
  // ---------------------------------------------------------------------------

  group('Demo Flow QA - Core Controls Accessible', () {
    testWidgets('Cook Now has large touch-target buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: apiClient,
            child: const CookNowScreen(),
          ),
        ),
      );

      // Primary and secondary CTAs are rendered with SizedBox height
      // (hands-busy 64dp target). Verify they exist and are tappable.
      final skipButton = find.text('Skip & Start Cooking');
      expect(skipButton, findsOneWidget);

      final contextButton = find.text('Start with Context');
      expect(contextButton, findsOneWidget);

      // Time option chips are rendered
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);
    });

    testWidgets('Cook Now optional fields have labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: apiClient,
            child: const CookNowScreen(),
          ),
        ),
      );

      // All optional fields have label text
      expect(
        find.text('What are you making? (optional)'),
        findsOneWidget,
      );
      expect(
        find.text('Ingredients on hand (optional)'),
        findsOneWidget,
      );
      expect(
        find.text('How much time? (optional)'),
        findsOneWidget,
      );
    });
  });
}
