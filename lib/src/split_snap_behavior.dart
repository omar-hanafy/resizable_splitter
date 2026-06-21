import 'package:flutter/foundation.dart';

/// Snap points a drag settles onto when released within [tolerance].
///
/// Each point is a start fraction in `[0, 1]`. Points are matched in effective
/// space, so a point that constraints push aside is measured by where it
/// actually lands rather than its nominal value.
@immutable
class SplitterSnapBehavior {
  /// Creates snap behavior with the given [points] and [tolerance].
  const SplitterSnapBehavior({required this.points, this.tolerance = 0.02})
    : assert(tolerance >= 0, 'tolerance must be non-negative');

  /// Start fractions to snap to, each in `[0, 1]`.
  final List<double> points;

  /// Largest distance (in effective ratio) from a point that still snaps.
  final double tolerance;

  /// Returns a copy with the given fields replaced.
  SplitterSnapBehavior copyWith({List<double>? points, double? tolerance}) =>
      SplitterSnapBehavior(
        points: points ?? this.points,
        tolerance: tolerance ?? this.tolerance,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterSnapBehavior &&
          listEquals(other.points, points) &&
          other.tolerance == tolerance;

  @override
  int get hashCode => Object.hash(Object.hashAll(points), tolerance);

  @override
  String toString() =>
      'SplitterSnapBehavior(points: $points, tolerance: $tolerance)';
}
