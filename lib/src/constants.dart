import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// Internal default values for the resizable splitter and its configuration
/// types, centralized here as a single tuning surface.
///
/// These back the documented defaults of the widget, theme, and snap behaviors.
/// Not exported from the package barrel, and carry no public API guarantee.
@internal
abstract final class SplitterDefaults {
  /// Visible divider thickness along the main axis, in logical pixels.
  static const double dividerThickness = 6;

  /// Interactive grab-target size across the divider's thin dimension, in
  /// logical pixels (the Material minimum touch target).
  static const double interactiveExtent = 48;

  /// Ratio delta applied per arrow-key press.
  static const double keyboardStep = 0.01;

  /// Ratio delta applied per page-key press.
  static const double pageStep = 0.1;

  /// Fallback main-axis extent, in logical pixels, used when the main-axis
  /// constraints are unbounded and the fallback behavior is selected.
  static const double fallbackExtent = 500;

  /// Snap capture tolerance, as a fraction of the available extent.
  static const double snapTolerance = 0.02;

  /// Magnetic-snap pull strength, in the range `(0, 1]`.
  static const double magneticStrength = 0.5;

  /// Magnetic-snap distance falloff curve. Shapes how the pull ramps from the
  /// tolerance edge (input 0) to the point (input 1): linear keeps the legacy
  /// behavior, while an ease-in curve concentrates the catch near the point.
  static const Curve magneticFalloff = Curves.linear;

  /// Magnetic-snap exact-settle core size, as a fraction of the tolerance, in
  /// `[0, 1]`. `0` disables settling (the pull never quite lands on a point).
  static const double magneticSettleFactor = 0;

  /// Sticky-snap escape factor: the escape radius as a multiple of the capture
  /// radius (always greater than 1).
  static const double stickyEscapeFactor = 1.5;
}
