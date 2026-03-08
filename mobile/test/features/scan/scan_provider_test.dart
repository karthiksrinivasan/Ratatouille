import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/features/scan/providers/scan_provider.dart';

void main() {
  late ScanProvider provider;

  setUp(() {
    // Create provider with a mock api client (no auth, no real backend)
    provider = ScanProvider(
      apiClient: ApiClient(baseUrl: 'http://localhost'),
    );
  });

  group('ScanProvider initial state', () {
    test('starts in idle phase', () {
      expect(provider.phase, ScanPhase.idle);
      expect(provider.scanId, isNull);
      expect(provider.source, 'fridge');
      expect(provider.selectedImages, isEmpty);
      expect(provider.detected, isEmpty);
      expect(provider.confirmed, isEmpty);
      expect(provider.suggestions, isNull);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });
  });

  group('source selection', () {
    test('setSource updates source', () {
      provider.setSource('pantry');
      expect(provider.source, 'pantry');
    });

    test('setSource notifies listeners', () {
      bool notified = false;
      provider.addListener(() => notified = true);
      provider.setSource('pantry');
      expect(notified, true);
    });
  });

  group('ingredient management', () {
    test('toggleIngredient adds and removes', () {
      provider.addManualIngredient('salt');
      expect(provider.confirmed, contains('salt'));

      provider.toggleIngredient('salt');
      expect(provider.confirmed, isNot(contains('salt')));

      provider.toggleIngredient('salt');
      expect(provider.confirmed, contains('salt'));
    });

    test('addManualIngredient normalizes to lowercase', () {
      provider.addManualIngredient('Red Bell Pepper');
      expect(provider.confirmed, contains('red bell pepper'));
    });

    test('addManualIngredient ignores empty strings', () {
      provider.addManualIngredient('');
      provider.addManualIngredient('  ');
      expect(provider.confirmed, isEmpty);
    });

    test('addManualIngredient ignores duplicates', () {
      provider.addManualIngredient('salt');
      provider.addManualIngredient('salt');
      expect(provider.confirmed.length, 1);
    });

    test('removeIngredient removes from confirmed list', () {
      provider.addManualIngredient('salt');
      provider.addManualIngredient('pepper');
      provider.removeIngredient('salt');
      expect(provider.confirmed, ['pepper']);
    });
  });

  group('uploadAndDetect validation', () {
    test('sets error when fewer than 2 images', () async {
      // No images selected
      await provider.uploadAndDetect();
      expect(provider.error, 'Please select at least 2 images');
      expect(provider.phase, ScanPhase.idle);
    });
  });

  group('reset', () {
    test('resets all state to initial', () {
      provider.setSource('pantry');
      provider.addManualIngredient('salt');
      provider.reset();

      expect(provider.phase, ScanPhase.idle);
      expect(provider.source, 'fridge');
      expect(provider.confirmed, isEmpty);
      expect(provider.error, isNull);
    });
  });

  group('clearError', () {
    test('clears error state', () async {
      await provider.uploadAndDetect(); // triggers error
      expect(provider.error, isNotNull);

      provider.clearError();
      expect(provider.error, isNull);
    });
  });
}
