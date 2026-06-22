import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_layout.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';

/// The resolved geometry of a split for one layout pass.
///
/// Every field is finite and non-negative, and [startExtent] + [endExtent]
/// equals the (sanitized) available space - except under
/// [SplitterSurplusPolicy.leaveGap], where their sum may be less (the remainder
/// is an intentional gap between the panes). The interval
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
    required this.resolution,
    required this.startCollapsed,
    required this.endCollapsed,
  });

  /// Start (left/top) pane extent in logical pixels.
  final double startExtent;

  /// End (right/bottom) pane extent in logical pixels.
  final double endExtent;

  /// On-screen start fraction, in `[0, 1]` (`startExtent / available`).
  final double effectiveFraction;

  /// Lowest legal start extent for this layout (the resolved band floor). Equals
  /// [startExtent] when the layout is pinned (collapsed, or an infeasible
  /// shortage/surplus).
  final double minStartExtent;

  /// Highest legal start extent for this layout (the resolved band ceiling).
  /// Equals [startExtent] when the layout is pinned.
  final double maxStartExtent;

  /// How the request resolved against the constraints for this layout.
  final SplitterResolution resolution;

  /// Whether the start pane is collapsed in this solution.
  final bool startCollapsed;

  /// Whether the end pane is collapsed in this solution.
  final bool endCollapsed;

  /// Whether the start pane has head-room to grow within the resolved band.
  bool get canIncreaseStart => maxStartExtent - startExtent > 1e-9;

  /// Whether the start pane has room to shrink within the resolved band.
  bool get canDecreaseStart => startExtent - minStartExtent > 1e-9;

  @override
  String toString() =>
      'SplitterSolution(start: $startExtent, end: $endExtent, '
      'effective: $effectiveFraction, resolution: ${resolution.name})';
}

/// The constraint inputs the solver needs, bundled into one value independent of
/// the available space (which the layout supplies per frame) and of the collapse
/// flags (which depend on the controller's current state).
///
/// This is the geometry-input channel that flows from the widget down to the
/// layout layer: the layer calls [solverFor] with the measured space to obtain a
/// [SplitterSolver] for that frame. Bundling the inputs as one value type with
/// cheap equality lets the layer skip work when nothing relevant changed, and
/// isolates a future render-object layout from how the inputs are gathered.
@immutable
class SplitterSolverConfig {
  /// Creates a solver configuration. Mirrors [SplitterSolver]'s inputs minus the
  /// per-frame [SplitterSolver.available] and the per-state collapse flags.
  const SplitterSolverConfig({
    required this.start,
    required this.end,
    this.minStartFraction = 0.0,
    this.maxStartFraction = 1.0,
    this.policy = SplitterConstraintPolicy.favorStart,
    this.surplusPolicy = SplitterSurplusPolicy.leaveGap,
    this.devicePixelRatio = 1.0,
    this.snapToPhysicalPixels = false,
  });

  /// Start (left/top) pane constraints.
  final SplitterPaneConstraints start;

  /// End (right/bottom) pane constraints.
  final SplitterPaneConstraints end;

  /// Lowest fraction of the available space the start pane may take.
  final double minStartFraction;

  /// Highest fraction of the available space the start pane may take.
  final double maxStartFraction;

  /// Tie-break applied in a minimum shortage.
  final SplitterConstraintPolicy policy;

  /// Policy applied in a maximum surplus.
  final SplitterSurplusPolicy surplusPolicy;

  /// The device pixel ratio used when [snapToPhysicalPixels] is set.
  final double devicePixelRatio;

  /// Whether to snap the start extent to a whole physical pixel.
  final bool snapToPhysicalPixels;

  /// Builds a solver for [available] space and the given collapse flags. This is
  /// the only place the config becomes a per-frame solver.
  SplitterSolver solverFor(
    double available, {
    bool startCollapsed = false,
    bool endCollapsed = false,
  }) => SplitterSolver(
    available: available,
    start: start,
    end: end,
    minStartFraction: minStartFraction,
    maxStartFraction: maxStartFraction,
    policy: policy,
    surplusPolicy: surplusPolicy,
    startCollapsed: startCollapsed,
    endCollapsed: endCollapsed,
    devicePixelRatio: devicePixelRatio,
    snapToPhysicalPixels: snapToPhysicalPixels,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterSolverConfig &&
          other.start == start &&
          other.end == end &&
          other.minStartFraction == minStartFraction &&
          other.maxStartFraction == maxStartFraction &&
          other.policy == policy &&
          other.surplusPolicy == surplusPolicy &&
          other.devicePixelRatio == devicePixelRatio &&
          other.snapToPhysicalPixels == snapToPhysicalPixels;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    minStartFraction,
    maxStartFraction,
    policy,
    surplusPolicy,
    devicePixelRatio,
    snapToPhysicalPixels,
  );

  @override
  String toString() =>
      'SplitterSolverConfig(start: $start, end: $end, '
      'minStartFraction: $minStartFraction, maxStartFraction: $maxStartFraction, '
      'policy: ${policy.name}, surplusPolicy: ${surplusPolicy.name}, '
      'devicePixelRatio: $devicePixelRatio, '
      'snapToPhysicalPixels: $snapToPhysicalPixels)';
}

/// Pure constraint solver: turns a requested [SplitterPosition] into legal pane
/// extents for a given layout.
///
/// This is the single source of truth for the split geometry. Every consumer
/// (layout, drag, keyboard, snapping, semantics) routes through [solve], so they
/// can never disagree on the legal bounds.
///
/// Pixel limits are hard and always win: the solver computes the
/// pixel-feasible interval first, classifies why a layout is infeasible
/// (a minimum shortage vs. a maximum surplus), and only then intersects the
/// fractional caps - which can merely *narrow* a feasible pixel band, never push
/// the result outside it. When the fractional caps and the pixel limits conflict
/// the pixel limits win and the outcome is reported as a
/// [SplitterResolution.fractionConflict].
@immutable
class SplitterSolver {
  /// Creates a solver for a single layout pass.
  ///
  /// [available] is the space shared by the two panes (the container extent
  /// already net of the divider's visual thickness). [minStartFraction] and
  /// [maxStartFraction] are the fractional caps on the start pane.
  const SplitterSolver({
    required this.available,
    required this.start,
    required this.end,
    this.minStartFraction = 0.0,
    this.maxStartFraction = 1.0,
    this.policy = SplitterConstraintPolicy.favorStart,
    this.surplusPolicy = SplitterSurplusPolicy.leaveGap,
    this.startCollapsed = false,
    this.endCollapsed = false,
    this.devicePixelRatio = 1.0,
    this.snapToPhysicalPixels = false,
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

  /// Tie-break applied when the hard minimums cannot all be satisfied
  /// (a shortage).
  final SplitterConstraintPolicy policy;

  /// Policy applied when both maximums are too small to fill the space
  /// (a surplus). Defaults to [SplitterSurplusPolicy.leaveGap], which keeps
  /// [SplitterPaneConstraints.maxExtent] a true maximum.
  final SplitterSurplusPolicy surplusPolicy;

  /// Whether the start pane is collapsed.
  final bool startCollapsed;

  /// Whether the end pane is collapsed.
  final bool endCollapsed;

  /// The device pixel ratio used when [snapToPhysicalPixels] is set.
  final double devicePixelRatio;

  /// Whether to snap the start extent to a whole physical pixel (removing
  /// sub-pixel anti-aliasing seams between the panes).
  ///
  /// Carried on the solver rather than passed per-call so that every [solve]
  /// from this instance - layout, drag, snapping, semantics, preview - is
  /// pixel-consistent: the callbacks and the drawn extents can never disagree.
  final bool snapToPhysicalPixels;

  /// Resolves [requested] into legal extents.
  ///
  /// When [snapToPhysicalPixels] is set, the start extent is snapped to a whole
  /// physical pixel for [devicePixelRatio] then re-clamped into the resolved
  /// band (never just to `[0, available]`), so snapping can never violate the
  /// policy-chosen value.
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
        resolution: SplitterResolution.inactive,
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
        snapToPhysicalPixels,
      ).clamp(0.0, available).toDouble();
      return SplitterSolution(
        startExtent: startExtent,
        endExtent: available - startExtent,
        effectiveFraction: startExtent / available,
        minStartExtent: startExtent,
        maxStartExtent: startExtent,
        resolution: SplitterResolution.collapsed,
        startCollapsed: startCollapsed,
        endCollapsed: endCollapsed,
      );
    }

    final minFrac = minStartFraction.clamp(0.0, 1.0).toDouble();
    final maxFrac = maxStartFraction.clamp(0.0, 1.0).toDouble();

    // STEP 1 - the hard pixel-feasible interval. Pixels are hard and always win.
    //   start >= start.min  AND  end <= end.max  =>  start >= available - end.max
    //   start <= start.max  AND  end >= end.min  =>  start <= available - end.min
    final pixLo = <double>[
      start.minExtent,
      available - end.maxExtent,
    ].reduce(math.max).clamp(0.0, available).toDouble();
    final pixHi = <double>[
      start.maxExtent,
      available - end.minExtent,
    ].reduce(math.min).clamp(0.0, available).toDouble();

    // STEP 2 - classify the pixel layer before fractions. Mutually exclusive:
    // min <= max implies min+min <= max+max, so a shortage and a surplus cannot
    // both hold. pixLo > pixHi (an empty pixel band) happens exactly here.
    final pixShortage = (start.minExtent + end.minExtent) > available;
    final pixSurplus = (start.maxExtent + end.maxExtent) < available;
    final pixFeasible = pixLo <= pixHi;

    // STEP 3 - intersect the fractional caps. They only narrow a feasible pixel
    // band; if they empty it, the pixels win and we report a fraction conflict.
    final fLo = available * minFrac;
    final fHi = available * maxFrac;
    var lo = math.max(pixLo, fLo);
    var hi = math.min(pixHi, fHi);
    final fractionConflict = pixFeasible && lo > hi;
    if (fractionConflict) {
      lo = pixLo;
      hi = pixHi;
    }

    var desired = requested.resolveFraction(available) * available;
    if (!desired.isFinite) desired = 0;
    desired = desired.clamp(0.0, available).toDouble();

    // STEP 4 - resolve the start extent and the band it was resolved within.
    final double startExtentRaw;
    final double minBand;
    final double maxBand;
    final SplitterResolution resolution;

    if (pixShortage) {
      startExtentRaw = switch (policy) {
        SplitterConstraintPolicy.favorStart => pixLo,
        SplitterConstraintPolicy.favorEnd => pixHi,
        SplitterConstraintPolicy.proportional => _proportional(available),
      };
      minBand = startExtentRaw;
      maxBand = startExtentRaw;
      resolution = SplitterResolution.minShortage;
    } else if (pixSurplus) {
      startExtentRaw = switch (surplusPolicy) {
        SplitterSurplusPolicy.giveToStart => available - end.maxExtent,
        SplitterSurplusPolicy.giveToEnd => start.maxExtent,
        SplitterSurplusPolicy.proportional =>
          (start.maxExtent + end.maxExtent) > 0
              ? available *
                    (start.maxExtent / (start.maxExtent + end.maxExtent))
              : available * 0.5,
        SplitterSurplusPolicy.leaveGap => start.maxExtent,
      };
      minBand = startExtentRaw;
      maxBand = startExtentRaw;
      resolution = SplitterResolution.maxSurplus;
    } else if (fractionConflict) {
      startExtentRaw = desired.clamp(pixLo, pixHi).toDouble();
      minBand = pixLo;
      maxBand = pixHi;
      resolution = SplitterResolution.fractionConflict;
    } else {
      final clamped = desired.clamp(lo, hi).toDouble();
      startExtentRaw = clamped;
      minBand = lo;
      maxBand = hi;
      resolution = (clamped - desired).abs() > 1e-9
          ? SplitterResolution.clamped
          : SplitterResolution.exact;
    }

    // leaveGap keeps the end pane at its own maximum; the leftover is a gap.
    final leavingGap =
        pixSurplus && surplusPolicy == SplitterSurplusPolicy.leaveGap;

    var startExtent = startExtentRaw;
    var endExtent = leavingGap ? end.maxExtent : available - startExtent;

    // STEP 5 - snap to a physical pixel, then re-clamp to the SAME band the
    // policy used so snapping cannot violate the chosen value.
    if (snapToPhysicalPixels) {
      startExtent = _maybeSnap(
        startExtent,
        devicePixelRatio,
        true,
      ).clamp(minBand, maxBand).toDouble();
      if (!leavingGap) endExtent = available - startExtent;
    }

    startExtent = startExtent.clamp(0.0, available).toDouble();
    endExtent = endExtent.clamp(0.0, available).toDouble();

    return SplitterSolution(
      startExtent: startExtent,
      endExtent: endExtent,
      effectiveFraction: (startExtent / available).clamp(0.0, 1.0).toDouble(),
      minStartExtent: minBand,
      maxStartExtent: maxBand,
      resolution: resolution,
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
