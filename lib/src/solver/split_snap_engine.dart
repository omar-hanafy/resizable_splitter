import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';
import 'package:resizable_splitter/src/model/split_change_details.dart';
import 'package:resizable_splitter/src/model/split_position.dart';
import 'package:resizable_splitter/src/solver/split_snap_behavior.dart';
import 'package:resizable_splitter/src/solver/split_solver.dart';

/// Internal pure snap math shared by every snap mode. Not exported from the
/// package barrel; consumed only by the drag handle and exercised directly by
/// unit tests.

/// One snap point resolved against the current layout.
///
/// A point is configured as a [nominalFraction] in `[0, 1]` but lands at
/// [effectiveFraction] once the solver applies the pane constraints. [coordinate]
/// is the value distances are measured in - the effective fraction in ratio mode,
/// or the start extent (in logical pixels) when a pixel tolerance is active -
/// and [distance] is how far the pointer is from this point in that same space.
@internal
class ResolvedSnapPoint {
  /// Creates a resolved snap point.
  const ResolvedSnapPoint({
    required this.index,
    required this.nominalFraction,
    required this.effectiveFraction,
    required this.coordinate,
    required this.distance,
  });

  /// Index of this point in the behavior's configured `points` list.
  final int index;

  /// The configured start fraction, before constraints.
  final double nominalFraction;

  /// Where the point actually lands after the solver applies constraints.
  final double effectiveFraction;

  /// The point's position in the active measurement space (effective fraction,
  /// or start extent in pixels when a pixel tolerance is set).
  final double coordinate;

  /// Distance from the pointer to this point in the active measurement space.
  final double distance;
}

/// Resolves a [SplitterSnapBehavior]'s points against a [SplitterSolver] and
/// answers the distance queries the snap modes need. Performs no writes and no
/// callbacks - all snap state lives in the caller.
@internal
class SnapResolver {
  /// Creates a resolver for [behavior] against [solver].
  SnapResolver(this._behavior, this._solver)
    : _usePixels = _behavior.pixelTolerance != null;

  final SplitterSnapBehavior _behavior;
  final SplitterSolver _solver;
  final bool _usePixels;

  /// The capture radius in the active measurement space: the pixel tolerance
  /// when set, otherwise the ratio tolerance.
  double get radius => _behavior.pixelTolerance ?? _behavior.tolerance;

  double _pointerCoordinate(double pointerFraction) =>
      _usePixels ? pointerFraction * _solver.available : pointerFraction;

  ResolvedSnapPoint _resolve(int index, double pointerCoordinate) {
    final nominal = _behavior.points[index];
    final solution = _solver.solve(SplitterPosition.fraction(nominal));
    final coordinate = _usePixels
        ? solution.startExtent
        : solution.effectiveFraction;
    return ResolvedSnapPoint(
      index: index,
      nominalFraction: nominal,
      effectiveFraction: solution.effectiveFraction,
      coordinate: coordinate,
      distance: (pointerCoordinate - coordinate).abs(),
    );
  }

  /// Resolves the point at [index] and its distance from [pointerFraction].
  ResolvedSnapPoint resolveAt(int index, double pointerFraction) =>
      _resolve(index, _pointerCoordinate(pointerFraction));

  /// The point nearest [pointerFraction], or null when there are no points.
  /// Ties resolve to the earliest configured point.
  ResolvedSnapPoint? nearest(double pointerFraction) {
    final points = _behavior.points;
    if (points.isEmpty) return null;
    final pc = _pointerCoordinate(pointerFraction);
    ResolvedSnapPoint? best;
    for (var i = 0; i < points.length; i++) {
      final candidate = _resolve(i, pc);
      if (best == null || candidate.distance < best.distance) {
        best = candidate;
      }
    }
    return best;
  }

  /// All points resolved against [pointerFraction], sorted by [coordinate] and
  /// de-duplicated so coincident points collapse to one (the earliest configured
  /// index wins). Used to find a point's neighbors for the magnetic Voronoi clip.
  List<ResolvedSnapPoint> resolveSortedDistinct(double pointerFraction) {
    final points = _behavior.points;
    final pc = _pointerCoordinate(pointerFraction);
    final resolved =
        <ResolvedSnapPoint>[
          for (var i = 0; i < points.length; i++) _resolve(i, pc),
        ]..sort((a, b) {
          final byCoordinate = a.coordinate.compareTo(b.coordinate);
          return byCoordinate != 0 ? byCoordinate : a.index.compareTo(b.index);
        });
    final distinct = <ResolvedSnapPoint>[];
    for (final point in resolved) {
      if (distinct.isEmpty ||
          (distinct.last.coordinate - point.coordinate).abs() > 1e-9) {
        distinct.add(point);
      }
    }
    return distinct;
  }
}

/// Magnetic transform: returns the attracted effective fraction for [pointer].
///
/// The divider is pulled toward the nearest point by `strength * t`, where
/// `t = 1 - distance / effectiveRadius` tapers to zero at the edge of influence.
/// The radius is clipped to half the distance to the nearest neighbor on the
/// pointer's side, so the pull reaches zero at the midpoint between two points
/// before the nearest-point identity flips - keeping the transform continuous
/// when influence zones overlap. The pointer always wins as it moves away.
///
/// The linear nearness `1 - distance / effectiveRadius` is passed through
/// [curve] before scaling, so an ease-in curve keeps the pull faint across most
/// of the zone and concentrates the catch near the point for a snappier feel.
/// [Curves.linear] (the default) leaves the original linear taper unchanged.
///
/// When the pointer is within `settleFactor * effectiveRadius` of the point the
/// divider settles exactly onto it - the pull's crisp finish - rather than being
/// drawn merely close; it stays pushable, since moving past the core resumes the
/// pull. `settleFactor == 0` (the default) disables settling.
@internal
double magneticPull({
  required double pointer,
  required SnapResolver resolver,
  required double strength,
  Curve curve = Curves.linear,
  double settleFactor = 0,
}) {
  final sorted = resolver.resolveSortedDistinct(pointer);
  if (sorted.isEmpty) return pointer;

  var nearestIndex = 0;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].distance < sorted[nearestIndex].distance) nearestIndex = i;
  }
  final point = sorted[nearestIndex];
  final radius = resolver.radius;

  // Clip the radius to the Voronoi boundary on the side the pointer is on.
  // (Coordinate order matches effective-fraction order, so the fraction-space
  // comparison picks the correct neighbor in either measurement space.)
  var directionalLimit = radius;
  final pointerOnLeft = pointer < point.effectiveFraction;
  if (pointerOnLeft && nearestIndex > 0) {
    directionalLimit =
        (point.coordinate - sorted[nearestIndex - 1].coordinate) / 2;
  } else if (!pointerOnLeft && nearestIndex < sorted.length - 1) {
    directionalLimit =
        (sorted[nearestIndex + 1].coordinate - point.coordinate) / 2;
  }

  final effectiveRadius = radius < directionalLimit ? radius : directionalLimit;
  final distance = point.distance;
  if (effectiveRadius <= 0 || distance >= effectiveRadius) return pointer;

  if (distance <= settleFactor * effectiveRadius) {
    return point.effectiveFraction;
  }

  final nearness = (1 - distance / effectiveRadius).clamp(0.0, 1.0).toDouble();
  final t = curve.transform(nearness);
  return pointer + (point.effectiveFraction - pointer) * strength * t;
}

/// The outcome of one sticky drag update: what to request, why, and the new
/// captured-point index to carry into the next update (null when not captured).
@internal
class StickyStep {
  /// Creates a sticky step result.
  const StickyStep({
    required this.requestFraction,
    required this.source,
    required this.capturedIndex,
  });

  /// The start fraction to request. While captured this is the point's *nominal*
  /// fraction, so the solver re-resolves the point through a layout change.
  final double requestFraction;

  /// [SplitterChangeSource.snap] while captured, else [SplitterChangeSource.drag].
  final SplitterChangeSource source;

  /// The captured point's index to carry forward, or null when not captured.
  final int? capturedIndex;
}

/// Sticky transform: a capture/hold/escape step with hysteresis.
///
/// [capturedIndex] is the point captured on the previous update (null if none).
/// A captured point holds while the pointer stays within `escapeFactor * radius`;
/// once it escapes, a fresh capture is attempted in the same update so a fast
/// drag that leaps between zones snaps on the same frame. The returned
/// [StickyStep.requestFraction] is the captured point's nominal fraction so it
/// survives a mid-drag resize.
@internal
StickyStep stickyStep({
  required double pointer,
  required int? capturedIndex,
  required SnapResolver resolver,
  required double escapeFactor,
}) {
  final radius = resolver.radius;

  if (capturedIndex != null) {
    final captured = resolver.resolveAt(capturedIndex, pointer);
    if (captured.distance <= radius * escapeFactor) {
      return StickyStep(
        requestFraction: captured.nominalFraction,
        source: SplitterChangeSource.snap,
        capturedIndex: capturedIndex,
      );
    }
    // Escaped: fall through and try to capture a new point this same update.
  }

  final nearest = resolver.nearest(pointer);
  if (nearest != null && nearest.distance <= radius) {
    return StickyStep(
      requestFraction: nearest.nominalFraction,
      source: SplitterChangeSource.snap,
      capturedIndex: nearest.index,
    );
  }

  return StickyStep(
    requestFraction: pointer,
    source: SplitterChangeSource.drag,
    capturedIndex: null,
  );
}
