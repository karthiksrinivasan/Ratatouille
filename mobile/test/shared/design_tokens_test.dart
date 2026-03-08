import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/shared/design_tokens.dart';

void main() {
  group('Spacing', () {
    test('values increase monotonically', () {
      expect(Spacing.xs, lessThan(Spacing.sm));
      expect(Spacing.sm, lessThan(Spacing.md));
      expect(Spacing.md, lessThan(Spacing.lg));
      expect(Spacing.lg, lessThan(Spacing.xl));
      expect(Spacing.xl, lessThan(Spacing.xxl));
    });

    test('page padding equals md', () {
      expect(Spacing.pagePadding, equals(Spacing.md));
    });
  });

  group('Radii', () {
    test('values increase monotonically', () {
      expect(Radii.sm, lessThan(Radii.md));
      expect(Radii.md, lessThan(Radii.lg));
      expect(Radii.lg, lessThan(Radii.xl));
      expect(Radii.xl, lessThan(Radii.pill));
    });
  });

  group('AppDurations', () {
    test('fast < normal < slow', () {
      expect(AppDurations.fast, lessThan(AppDurations.normal));
      expect(AppDurations.normal, lessThan(AppDurations.slow));
    });

    test('screen transition target is 250ms', () {
      expect(AppDurations.screenTransition.inMilliseconds, equals(250));
    });
  });

  group('TouchTargets', () {
    test('minimum meets accessibility guidelines (48dp)', () {
      expect(TouchTargets.minimum, equals(48));
    });

    test('hands-busy is larger than minimum', () {
      expect(TouchTargets.handsBusy, greaterThan(TouchTargets.minimum));
    });
  });

  group('Elevations', () {
    test('none is zero', () {
      expect(Elevations.none, equals(0));
    });
  });
}
