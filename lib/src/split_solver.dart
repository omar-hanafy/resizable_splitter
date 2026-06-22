import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';

/// The resolved geometry of a split for one layout pass.
///
/// Every field is finite and non-negative, and [startExtent] + [endExtent]
/// equals the (sanitized) available space. The interval
/// [[minStartExtent], [maxStartExtent]] is the legal range the start extent was
/// clamped into; interaction code uses it to convert and clamp pointer motion.
@immutable
class SplitterSolution {
  /// Creates a solution. Callers normally obtain one from [SplitterSolver.solve]
  /// rather than constructing it directly.
  const SplitterSolution({
    required this.startExtent,
    required this.endExtent,
    required this.effectiveFraction,
    required this.minStartExtent,
    required this.maxStartExtent,
    required this.isCramped,
    required this.startCollapsed,
    required this.endCollapsed,
  });

  /// Start (left/top) pane extent in logical pixels.
  final double startExtent;

  /// End (right/bottom) pane extent in logical pixels.
  final double endExtent;

  /// On-screen start fraction, in `[0, 1]` (`startExtent / available`).
  final double effectiveFraction;

  /// Lowest legal start extent for this layout (the `lo` bound).
  final double minStartExtent;

  /// Highest legal start extent for this layout (the `hi` bound).
  final double maxStartExtent;

  /// Whether the panes' hard minimums could not all be honored, so the
  /// [SplitterConstraintPolicy] tie-break was applied.
  final bool isCramped;

  /// Whether the start pane is collapsed in this solution.
  final bool startCollapsed;

  /// Whether the end pane is collapsed in this solution.
  final bool endCollapsed;

  @override
  String toString() =>
      'SplitterSolution(start: $startExtent, end: $endExtent, '
      'effective: $effectiveFraction, cramped: $isCramped)';
}

/// Pure constraint solver: turns a requested [SplitterPosition] into legal pane
/// extents for a given layout.
///
/// This is the single source of truth for the split geometry. Every consumer
/// (layout, drag, keyboard, snapping, semantics) routes through [solve], so they
/// can never disagree on the legal bounds, and an inverted `clamp(min, max)` -
/// the historic crash when both pixel minimums could not be met - is structurally
/// impossible: the bounds are computed first, then a feasible/infeasible branch
/// is chosen.
@immutable
class SplitterSolver {
  /// Creates a solver for a single layout pass.
  ///
  /// [available] is the space shared by the two panes (the container extent
  /// already net of the divider's visual thickness). [minStartFraction] and
  /// [maxStartFraction] are the fractional caps on the start pane (the former
  /// `minRatio`/`maxRatio`).
  const SplitterSolver({
    required this.available,
    required this.start,
    required this.end,
    this.minStartFraction = 0.0,
    this.maxStartFraction = 1.0,
    this.policy = SplitterConstraintPolicy.favorStart,
    this.startCollapsed = false,
    this.endCollapsed = false,
    this.devicePixelRatio = 1.0,
    this.snapToDevicePixels = false,
  });

  /// Space shared by the two panes, in logical pixels.
  final double available;

  /// Start (left/top) pane constraints.
  final SplitterPaneConstraints start;

  /// End (right/bottom) pane constraints.
  final SplitterPaneConstraints end;

  /// Lowest fraction of [available] the start pane may take.
  final double minStartFraction;

  /// Highest fraction of [available] the start pane may take.
  final double maxStartFraction;

  /// Tie-break applied when the hard minimums cannot all be satisfied.
  final SplitterConstraintPolicy policy;

  /// Whether the start pane is collapsed.
  final bool startCollapsed;

  /// Whether the end pane is collapsed.
  final bool endCollapsed;

  /// The device pixel ratio used when [snapToDevicePixels] is set.
  final double devicePixelRatio;

  /// Whether to snap the start extent to a whole physical pixel (removing
  /// sub-pixel anti-aliasing seams between the panes).
  ///
  /// Carried on the solver rather than passed per-call so that every [solve]
  /// from this instance - layout, drag, snapping, semantics, preview - is
  /// pixel-consistent: the callbacks and the drawn extents can never disagree.
  final bool snapToDevicePixels;

  /// Resolves [requested] into legal extents.
  ///
  /// When [snapToDevicePixels] is set, the start extent is snapped to a whole
  /// physical pixel for [devicePixelRatio] (then re-clamped into the legal
  /// range), which removes sub-pixel anti-aliasing seams between the panes.
  SplitterSolution solve(SplitterPosition requested) {
    final available = (this.available.isFinite && this.available > 0)
        ? this.available
        : 0.0;

    if (available <= 0) {
      final eff = requested.resolveFraction(0).clamp(0.0, 1.0).toDouble();
      return SplitterSolution(
        startExtent: 0,
        endExtent: 0,
        effectiveFraction: eff,
        minStartExtent: 0,
        maxStartExtent: 0,
        isCramped: start.minExtent > 0 || end.minExtent > 0,
        startCollapsed: startCollapsed,
        endCollapsed: endCollapsed,
      );
    }

    // Collapse short-circuit. If both are collapsed, the start pane wins.
    if (startCollapsed || endCollapsed) {
      double startExtent;
      if (startCollapsed) {
        startExtent = (start.collapsedExtent ?? 0)
            .clamp(0.0, available)
            .toDouble();
      } else {
        final endExtent = (end.collapsedExtent ?? 0)
            .clamp(0.0, available)
            .toDouble();
        startExtent = available - endExtent;
      }
      startExtent = _maybeSnap(
        startExtent,
        devicePixelRatio,
        snapToDevicePixels,
      ).clamp(0.0, available).toDouble();
      return SplitterSolution(
        startExtent: startExtent,
        endExtent: available - startExtent,
        effectiveFraction: startExtent / available,
        minStartExtent: startExtent,
        maxStartExtent: startExtent,
        isCramped: false,
        startCollapsed: startCollapsed,
        endCollapsed: endCollapsed,
      );
    }

    final minFrac = minStartFraction.clamp(0.0, 1.0).toDouble();
    final maxFrac = maxStartFraction.clamp(0.0, 1.0).toDouble();

    // Legal start-extent interval, intersecting pixel and fractional bounds.
    final lo = <double>[
      start.minExtent,
      available * minFrac,
      available -
          end.maxExtent, // end <= maxExtent  =>  start >= available - it
    ].reduce(math.max).clamp(0.0, available).toDouble();
    final hi = <double>[
      start.maxExtent,
      available * maxFrac,
      available -
          end.minExtent, // end >= minExtent  =>  start <= available - it
    ].reduce(math.min).clamp(0.0, available).toDouble();

    final feasible = lo <= hi;

    var desired = requested.resolveFraction(available) * available;
    if (!desired.isFinite) desired = 0;
    desired = desired.clamp(0.0, available).toDouble();

    double startExtent;
    if (feasible) {
      startExtent = desired.clamp(lo, hi).toDouble();
    } else {
      startExtent = switch (policy) {
        SplitterConstraintPolicy.favorStart => lo,
        SplitterConstraintPolicy.favorEnd => hi,
        SplitterConstraintPolicy.proportional => _proportional(available),
      };
    }

    if (snapToDevicePixels) {
      startExtent = _maybeSnap(startExtent, devicePixelRatio, true);
      startExtent = feasible
          ? startExtent.clamp(lo, hi).toDouble()
          : startExtent.clamp(0.0, available).toDouble();
    }

    final endExtent = (available - startExtent)
        .clamp(0.0, available)
        .toDouble();

    return SplitterSolution(
      startExtent: startExtent,
      endExtent: endExtent,
      effectiveFraction: (startExtent / available).clamp(0.0, 1.0).toDouble(),
      minStartExtent: lo,
      maxStartExtent: hi,
      isCramped: !feasible,
      startCollapsed: false,
      endCollapsed: false,
    );
  }

  /// Distributes [available] by the raw configured pane minimums. Using the raw
  /// (un-clamped) minimums is what preserves the configured proportion in a
  /// cramped layout instead of collapsing to 50/50.
  double _proportional(double available) {
    final rawStart = start.minExtent;
    final rawEnd = end.minExtent;
    final sum = rawStart + rawEnd;
    if (sum <= 0 || !sum.isFinite) return available * 0.5;
    return (available * (rawStart / sum)).clamp(0.0, available).toDouble();
  }

  static double _maybeSnap(double extent, double dpr, bool enabled) {
    if (!enabled || !dpr.isFinite || dpr <= 0) return extent;
    return (extent * dpr).roundToDouble() / dpr;
  }
}
