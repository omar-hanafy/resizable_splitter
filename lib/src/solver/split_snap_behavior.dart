import 'package:equatable/equatable.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/constants.dart';

/// Sentinel for `copyWith` so the nullable [SplitterSnapBehavior.pixelTolerance]
/// can be explicitly cleared (set back to null) rather than only overwritten.
const Object _noUpdate = Object();

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
/// {@category Snapping}
@immutable
sealed class SplitterSnapBehavior {
  SplitterSnapBehavior._({
    required Iterable<double> points,
    this.tolerance = SplitterDefaults.snapTolerance,
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
    double tolerance = SplitterDefaults.snapTolerance,
    double? pixelTolerance,
  }) => ReleaseSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
  );

  /// Builds [ReleaseSnap]; an explicit spelling of the unnamed factory.
  factory SplitterSnapBehavior.release({
    required Iterable<double> points,
    double tolerance = SplitterDefaults.snapTolerance,
    double? pixelTolerance,
  }) => ReleaseSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
  );

  /// Builds [MagneticSnap] with the given pull [strength] in `(0, 1]`.
  factory SplitterSnapBehavior.magnetic({
    required Iterable<double> points,
    double tolerance = SplitterDefaults.snapTolerance,
    double? pixelTolerance,
    double strength = SplitterDefaults.magneticStrength,
    Curve falloff = SplitterDefaults.magneticFalloff,
    double settleFactor = SplitterDefaults.magneticSettleFactor,
  }) => MagneticSnap(
    points: points,
    tolerance: tolerance,
    pixelTolerance: pixelTolerance,
    strength: strength,
    falloff: falloff,
    settleFactor: settleFactor,
  );

  /// Builds [StickySnap] with the given [escapeFactor] (`> 1`); the escape
  /// radius is `escapeFactor * tolerance`.
  factory SplitterSnapBehavior.sticky({
    required Iterable<double> points,
    double tolerance = SplitterDefaults.snapTolerance,
    double? pixelTolerance,
    double escapeFactor = SplitterDefaults.stickyEscapeFactor,
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
/// {@category Snapping}
final class ReleaseSnap extends SplitterSnapBehavior with EquatableMixin {
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
  List<Object?> get props => [points, tolerance, pixelTolerance];

  @override
  String toString() =>
      'ReleaseSnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance)';
}

/// Snapping that continuously pulls the divider toward the nearest point during
/// the drag. The pull fades to zero at the tolerance edge, so the pointer can
/// always push through, and the released position is committed as shown. A
/// non-zero [settleFactor] adds a small core around each point where the divider
/// settles exactly onto it, giving the pull a crisp finish.
/// {@category Snapping}
final class MagneticSnap extends SplitterSnapBehavior with EquatableMixin {
  /// Creates magnetic snapping with the given pull [strength], [falloff], and
  /// [settleFactor].
  MagneticSnap({
    required super.points,
    super.tolerance,
    super.pixelTolerance,
    this.strength = SplitterDefaults.magneticStrength,
    this.falloff = SplitterDefaults.magneticFalloff,
    this.settleFactor = SplitterDefaults.magneticSettleFactor,
  }) : assert(strength > 0 && strength <= 1, 'strength must be in (0, 1]'),
       assert(
         settleFactor >= 0 && settleFactor <= 1,
         'settleFactor must be in [0, 1]',
       ),
       super._();

  /// How strongly the divider is pulled toward a point, in `(0, 1]`. Higher is
  /// clingier; it never fully captures, so the pointer always wins.
  final double strength;

  /// Shapes how the pull ramps across the influence zone. The linear nearness
  /// `t` (0 at the tolerance edge, 1 at the point) is passed through this curve
  /// before being scaled by [strength]. The default [Curves.linear] reproduces
  /// the original behavior; an ease-in curve (e.g. [Curves.easeInCubic]) lets
  /// the divider track the pointer freely until it is close, then catch harder
  /// near the point for a snappier feel.
  final Curve falloff;

  /// Size of the exact-settle core around each point, as a fraction of the
  /// tolerance, in `[0, 1]`. When the pointer is within `settleFactor *`
  /// tolerance of a point, the divider settles exactly onto it - the pull's
  /// crisp finish - instead of being drawn merely close. It stays pushable:
  /// moving the pointer past the core resumes the pull. `0` (the default)
  /// disables settling, preserving the never-quite-lands pull.
  final double settleFactor;

  @override
  MagneticSnap copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
    double? strength,
    Curve? falloff,
    double? settleFactor,
  }) => MagneticSnap(
    points: points ?? this.points,
    tolerance: tolerance ?? this.tolerance,
    pixelTolerance: _resolvePixelTolerance(pixelTolerance, this.pixelTolerance),
    strength: strength ?? this.strength,
    falloff: falloff ?? this.falloff,
    settleFactor: settleFactor ?? this.settleFactor,
  );

  @override
  List<Object?> get props => [
    points,
    tolerance,
    pixelTolerance,
    strength,
    falloff,
    settleFactor,
  ];

  @override
  String toString() =>
      'MagneticSnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance, strength: $strength, '
      'falloff: $falloff, settleFactor: $settleFactor)';
}

/// Snapping that captures the divider onto a point during the drag and holds it
/// there until the pointer escapes past `escapeFactor * tolerance`. The escape
/// radius exceeding the capture radius is the hysteresis that prevents flicker
/// at the boundary.
/// {@category Snapping}
final class StickySnap extends SplitterSnapBehavior with EquatableMixin {
  /// Creates sticky snapping with the given [escapeFactor] (`> 1`).
  StickySnap({
    required super.points,
    super.tolerance,
    super.pixelTolerance,
    this.escapeFactor = SplitterDefaults.stickyEscapeFactor,
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
  List<Object?> get props => [points, tolerance, pixelTolerance, escapeFactor];

  @override
  String toString() =>
      'StickySnap(points: $points, tolerance: $tolerance, '
      'pixelTolerance: $pixelTolerance, escapeFactor: $escapeFactor)';
}
