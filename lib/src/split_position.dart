import 'package:flutter/foundation.dart';

/// A requested split position, independent of the current layout.
///
/// A [SplitterPosition] describes where the divider is *wanted*, in one of three
/// units. The on-screen position is derived per layout by the solver, which
/// clamps the request against the pane constraints. Storing the request (rather
/// than the already-resolved value) is what lets a pixel-pinned sidebar keep its
/// width as the window grows, and keeps callbacks honest about intent.
@immutable
sealed class SplitterPosition {
  /// Const base constructor for subclasses.
  const SplitterPosition();

  /// A position expressed as the fraction of the available space given to the
  /// start panel. [value] is clamped to `[0, 1]` when resolved.
  const factory SplitterPosition.fraction(double value) =
      FractionSplitterPosition;

  /// A fixed start-panel extent in logical pixels. The start panel keeps this
  /// width as the container grows (its fraction shrinks).
  const factory SplitterPosition.startPixels(double extent) =
      StartPixelsSplitterPosition;

  /// A fixed end-panel extent in logical pixels. The end panel keeps this width
  /// as the container grows.
  const factory SplitterPosition.endPixels(double extent) =
      EndPixelsSplitterPosition;

  /// The desired start-panel fraction for [available] logical pixels, before
  /// pane constraints are applied. Always returns a finite value in `[0, 1]`.
  double resolveFraction(double available);
}

/// Clamps [value] to the unit interval, mapping NaN to 0 and infinities to the
/// nearer bound.
double _clampUnit(double value) {
  if (value.isNaN) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}

/// A [SplitterPosition] expressed as a start-panel fraction.
@immutable
class FractionSplitterPosition extends SplitterPosition {
  /// Creates a fractional position with the given [value].
  const FractionSplitterPosition(this.value);

  /// The requested start fraction, before clamping to `[0, 1]`.
  final double value;

  @override
  double resolveFraction(double available) => _clampUnit(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FractionSplitterPosition && other.value == value;

  @override
  int get hashCode => Object.hash(FractionSplitterPosition, value);

  @override
  String toString() => 'SplitterPosition.fraction($value)';
}

/// A [SplitterPosition] that fixes the start panel to a pixel [extent].
@immutable
class StartPixelsSplitterPosition extends SplitterPosition {
  /// Creates a fixed start-pixel position.
  const StartPixelsSplitterPosition(this.extent);

  /// The requested start-panel extent in logical pixels.
  final double extent;

  @override
  double resolveFraction(double available) {
    if (available <= 0) return 0;
    return _clampUnit(extent / available);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartPixelsSplitterPosition && other.extent == extent;

  @override
  int get hashCode => Object.hash(StartPixelsSplitterPosition, extent);

  @override
  String toString() => 'SplitterPosition.startPixels($extent)';
}

/// A [SplitterPosition] that fixes the end panel to a pixel [extent].
@immutable
class EndPixelsSplitterPosition extends SplitterPosition {
  /// Creates a fixed end-pixel position.
  const EndPixelsSplitterPosition(this.extent);

  /// The requested end-panel extent in logical pixels.
  final double extent;

  @override
  double resolveFraction(double available) {
    if (available <= 0) return 0;
    return _clampUnit((available - extent) / available);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EndPixelsSplitterPosition && other.extent == extent;

  @override
  int get hashCode => Object.hash(EndPixelsSplitterPosition, extent);

  @override
  String toString() => 'SplitterPosition.endPixels($extent)';
}
