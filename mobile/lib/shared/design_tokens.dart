/// Centralized design tokens for consistent spacing, typography, and layout.
///
/// Use these constants instead of magic numbers throughout the app.
class Spacing {
  Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Standard horizontal page padding.
  static const double pagePadding = 16;

  /// Card internal padding.
  static const double cardPadding = 16;
}

class Radii {
  Radii._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 100;
}

class Durations {
  Durations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Max acceptable screen transition time.
  static const Duration screenTransition = Duration(milliseconds: 250);
}

/// Touch target sizes for kitchen/hands-busy use.
class TouchTargets {
  TouchTargets._();

  /// Minimum touch target for accessibility (48dp).
  static const double minimum = 48;

  /// Large touch target for hands-busy cooking mode.
  static const double handsBusy = 64;

  /// Extra-large for critical actions during live session.
  static const double critical = 72;
}

/// Elevation levels for Material 3 surfaces.
class Elevations {
  Elevations._();

  static const double none = 0;
  static const double low = 1;
  static const double medium = 2;
  static const double high = 4;
}
