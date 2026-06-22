import 'package:flutter/foundation.dart';

/// Sentinel for `copyWith` so the nullable [SplitterSnapBehavior.pixelTolerance]
/// can be explicitly cleared (set back to null) rather than only overwritten.
const Object _noUpdate = Object();

const double _defaultTolerance = 0.02;
const double _defaultMagneticStrength = 0.5;
const double _defaultStickyEscapeFactor = 1.5;

/// How a drag interacts with snap points.
///
/// Each point is a start fraction in `[0, 1]`. Points are matched in effective
/// space, so a point that constraints push aside is measured by where it
/// actually lands rather than its nominal value.
///
/// This is a sealed value type with three concrete modes:
///
/// - [ReleaseSnap] settles onto the nearest point only when the drag is
///   released within tolerance. This is the default and the legacy behavior:
///   the unnamed [SplitterSnapBehavior.new] factory builds one.
/// - [MagneticSnap] continuously pulls the divider toward a point during the
///   drag and can always be pushed through, with no release-time correction.
/// - [StickySnap] captures the divider onto a point during the drag and holds
///   it there until the pointer escapes past a hysteresis radius.
///
/// `null` (no behavior) means no snapping at all.
///
/// [points] is copied into an unmodifiable list at construction, so mutating
/// the iterable passed in can never change an existing behavior's points, hash
/// code, or equality. (That defensive copy is why the constructors are not
/// `const`.)
@immutable
sealed class SplitterSnapBehavior {
  SplitterSnapBehavior._({
    required Iterable<double> points,
    this.tolerance = _defaultTolerance,
    this.pixelTolerance,
  }) : points = List<double>.unmodifiable(points),
       assert(tolerance >= 0, 'tolerance must be non-negative'),
       assert(
         pixelTolerance == null || pixelTolerance >= 0,
         'pixelTolerance must be non-negative',
       );

  /// Builds [ReleaseSnap] - the divider settles onto the nearest point on
  /// release. Kept as the unnamed factory so existing call sites keep working.
  ///
  /// A body factory (not a redirecting one) so the defaults can live here.
  factory SplitterSnapBehavior({
    required Iterable<double> points,
    double tolerance = _defaultTolerance,
    double? pixelTolerance,
  }) => ReleaseSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
  );

  /// Builds [ReleaseSnap]; an explicit spelling of the unnamed factory.
  factory SplitterSnapBehavior.release({
    required Iterable<double> points,
    double tolerance = _defaultTolerance,
    double? pixelTolerance,
  }) => ReleaseSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
  );

  /// Builds [MagneticSnap] with the given pull [strength] in `(0, 1]`.
  factory SplitterSnapBehavior.magnetic({
    required Iterable<double> points,
    double tolerance = _defaultTolerance,
    double? pixelTolerance,
    double strength = _defaultMagneticStrength,
  }) => MagneticSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
    strength: strength,
  );

  /// Builds [StickySnap] with the given [escapeFactor] (`> 1`); the escape
  /// radius is `escapeFactor * tolerance`.
  factory SplitterSnapBehavior.sticky({
    required Iterable<double> points,
    double tolerance = _defaultTolerance,
    double? pixelTolerance,
    double escapeFactor = _defaultStickyEscapeFactor,
  }) => StickySnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
    escapeFactor: escapeFactor,
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

  /// Returns a copy with the given shared fields replaced, preserving the
  /// concrete mode (and its mode-specific fields). Pass `pixelTolerance: null`
  /// to clear it (falling back to [tolerance]); omit it to keep the current
  /// value.
  ///
  /// Stays on the base because callers may hold a behavior under its
  /// [SplitterSnapBehavior] static type.
  SplitterSnapBehavior copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance,
  });
}

double? _resolvePixelTolerance(Object? update, double? current) =>
    identical(update, _noUpdate) ? current : (update as num?)?.toDouble();

/// Snapping that settles onto the nearest point only when the drag is released
/// within tolerance. The divider tracks the pointer freely during the drag.
final class ReleaseSnap extends SplitterSnapBehavior {
  /// Creates release snapping.
  ReleaseSnap({required super.points, super.tolerance, super.pixelTolerance})
    : super._();

  @override
  ReleaseSnap copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
  }) => ReleaseSnap(
    points: points ?? this.points,
    tolerance: tolerance ?? this.tolerance,
    pixelTolerance: _resolvePixelTolerance(pixelTolerance, this.pixelTolerance),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseSnap &&
          listEquals(other.points, points) &&
          other.tolerance == tolerance &&
          other.pixelTolerance == pixelTolerance;

  @override
  int get hashCode => Object.hash(
    ReleaseSnap,
    Object.hashAll(points),
    tolerance,
    pixelTolerance,
  );

  @override
  String toString() =>
      'ReleaseSnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance)';
}

/// Snapping that continuously pulls the divider toward the nearest point during
/// the drag. The pull fades to zero at the tolerance edge, so the pointer can
/// always push through, and the released position is committed as shown.
final class MagneticSnap extends SplitterSnapBehavior {
  /// Creates magnetic snapping with the given pull [strength].
  MagneticSnap({
    required super.points,
    super.tolerance,
    super.pixelTolerance,
    this.strength = _defaultMagneticStrength,
  }) : assert(strength > 0 && strength <= 1, 'strength must be in (0, 1]'),
       super._();

  /// How strongly the divider is pulled toward a point, in `(0, 1]`. Higher is
  /// clingier; it never fully captures, so the pointer always wins.
  final double strength;

  @override
  MagneticSnap copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
    double? strength,
  }) => MagneticSnap(
    points: points ?? this.points,
    tolerance: tolerance ?? this.tolerance,
    pixelTolerance: _resolvePixelTolerance(pixelTolerance, this.pixelTolerance),
    strength: strength ?? this.strength,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MagneticSnap &&
          listEquals(other.points, points) &&
          other.tolerance == tolerance &&
          other.pixelTolerance == pixelTolerance &&
          other.strength == strength;

  @override
  int get hashCode => Object.hash(
    MagneticSnap,
    Object.hashAll(points),
    tolerance,
    pixelTolerance,
    strength,
  );

  @override
  String toString() =>
      'MagneticSnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance, strength: $strength)';
}

/// Snapping that captures the divider onto a point during the drag and holds it
/// there until the pointer escapes past `escapeFactor * tolerance`. The escape
/// radius exceeding the capture radius is the hysteresis that prevents flicker
/// at the boundary.
final class StickySnap extends SplitterSnapBehavior {
  /// Creates sticky snapping with the given [escapeFactor] (`> 1`).
  StickySnap({
    required super.points,
    super.tolerance,
    super.pixelTolerance,
    this.escapeFactor = _defaultStickyEscapeFactor,
  }) : assert(escapeFactor > 1, 'escapeFactor must be greater than 1'),
       super._();

  /// The escape radius as a multiple of the capture radius (`> 1`). The divider
  /// holds a captured point until the pointer moves past `escapeFactor *`
  /// the active tolerance.
  final double escapeFactor;

  @override
  StickySnap copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
    double? escapeFactor,
  }) => StickySnap(
    points: points ?? this.points,
    tolerance: tolerance ?? this.tolerance,
    pixelTolerance: _resolvePixelTolerance(pixelTolerance, this.pixelTolerance),
    escapeFactor: escapeFactor ?? this.escapeFactor,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickySnap &&
          listEquals(other.points, points) &&
          other.tolerance == tolerance &&
          other.pixelTolerance == pixelTolerance &&
          other.escapeFactor == escapeFactor;

  @override
  int get hashCode => Object.hash(
    StickySnap,
    Object.hashAll(points),
    tolerance,
    pixelTolerance,
    escapeFactor,
  );

  @override
  String toString() =>
      'StickySnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance, escapeFactor: $escapeFactor)';
}
