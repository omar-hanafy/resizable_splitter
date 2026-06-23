import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:resizable_splitter/src/model/split_layout.dart';

/// The resolved geometry of a split for one layout pass.
///
/// Every field is finite and non-negative, and [startExtent] + [endExtent]
/// equals the (sanitized) available space - except under
/// [SplitterSurplusPolicy.leaveGap], where their sum may be less (the remainder
/// is an intentional gap between the panes). The interval
/// [[minStartExtent], [maxStartExtent]] is the legal range the start extent was
/// clamped into; interaction code uses it to convert and clamp pointer motion.
@immutable
@internal
class SplitterSolution with EquatableMixin {
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
  List<Object?> get props => [
    startExtent,
    endExtent,
    effectiveFraction,
    minStartExtent,
    maxStartExtent,
    resolution,
    startCollapsed,
    endCollapsed,
  ];

  @override
  String toString() =>
      'SplitterSolution(start: $startExtent, end: $endExtent, '
      'effective: $effectiveFraction, resolution: ${resolution.name})';
}
