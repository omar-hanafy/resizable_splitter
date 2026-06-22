import 'package:flutter/foundation.dart';

/// Sentinel for [SplitterSnapBehavior.copyWith] so the nullable
/// [SplitterSnapBehavior.pixelTolerance] can be explicitly cleared (set back to
/// null) rather than only overwritten.
const Object _noUpdate = Object();

/// Snap points a drag settles onto when released within [tolerance].
///
/// Each point is a start fraction in `[0, 1]`. Points are matched in effective
/// space, so a point that constraints push aside is measured by where it
/// actually lands rather than its nominal value.
///
/// This is a value type: [points] is copied into an unmodifiable list at
/// construction, so mutating the iterable passed in can never change an existing
/// behavior's points, hash code, or equality. (That defensive copy is why the
/// constructor is not `const`.)
@immutable
class SplitterSnapBehavior {
  /// Creates snap behavior with the given [points] and tolerance. [points] is
  /// copied into an unmodifiable list.
  SplitterSnapBehavior({
    required Iterable<double> points,
    this.tolerance = 0.02,
    this.pixelTolerance,
  }) : points = List<double>.unmodifiable(points),
       assert(tolerance >= 0, 'tolerance must be non-negative'),
       assert(
         pixelTolerance == null || pixelTolerance >= 0,
         'pixelTolerance must be non-negative',
       );

  /// Start fractions to snap to, each in `[0, 1]`. Unmodifiable.
  final List<double> points;

  /// Largest distance (in effective ratio) from a point that still snaps. Used
  /// only when [pixelTolerance] is null.
  final double tolerance;

  /// Largest distance in logical pixels from a point that still snaps. When set,
  /// it takes precedence over [tolerance], giving a snap feel that does not
  /// change with the container size.
  final double? pixelTolerance;

  /// Returns a copy with the given fields replaced. Pass `pixelTolerance: null`
  /// to clear it (falling back to [tolerance]); omit it to keep the current
  /// value.
  SplitterSnapBehavior copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
  }) => SplitterSnapBehavior(
    points: points ?? this.points,
    tolerance: tolerance ?? this.tolerance,
    pixelTolerance: identical(pixelTolerance, _noUpdate)
        ? this.pixelTolerance
        : (pixelTolerance as num?)?.toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterSnapBehavior &&
          listEquals(other.points, points) &&
          other.tolerance == tolerance &&
          other.pixelTolerance == pixelTolerance;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), tolerance, pixelTolerance);

  @override
  String toString() =>
      'SplitterSnapBehavior(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance)';
}
