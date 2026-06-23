import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/model/split_pane_constraints.dart';

/// How the solver resolved a requested position against the pane constraints
/// and the available space, for one layout pass.
///
/// This replaces the old boolean "constrained" flag, which conflated three
/// distinct failures. Pixel limits ([SplitterPaneConstraints.minExtent] /
/// [SplitterPaneConstraints.maxExtent]) are hard and always win; a fractional
/// cap (the start-fraction interval) only narrows an otherwise feasible pixel
/// band, and a [fractionConflict] reports where it could not.
/// {@category Layout}
enum SplitterResolution {
  /// The request landed inside the legal band without being clamped.
  exact,

  /// The request was clamped to the legal band (a pixel limit or a fractional
  /// cap bit), which was non-empty.
  clamped,

  /// Both panes' minimums could not fit (`start.min + end.min > available`); the
  /// [SplitterConstraintPolicy] decided the split.
  minShortage,

  /// Both panes' maximums could not fill the space
  /// (`start.max + end.max < available`); the [SplitterSurplusPolicy] decided
  /// the split.
  maxSurplus,

  /// The pixel limits were feasible, but the fractional caps emptied the band;
  /// the pixel limits won and the fractional caps were ignored.
  fractionConflict,

  /// A pane is collapsed in this layout.
  collapsed,

  /// There is no usable space (the available extent is zero or non-finite).
  inactive,
}

/// The resolved, on-screen geometry of a split for the current layout.
///
/// Where a `SplitterState` is the *request* (a fraction or pixel pin, plus
/// collapse), this is the *result* after the solver clamps that request against
/// the pane constraints and available space. It is published separately from the
/// request - via `SplitterController.layoutListenable` - because the on-screen
/// geometry can change without the request changing (a pixel-pinned pane's
/// fraction shifts when the container resizes), and consumers that track the
/// visible layout need a signal for exactly those changes.
///
/// A controller reports `null` for its layout before the first layout pass (and
/// while detached), rather than pretending a pixel request already has an
/// effective fraction.
/// {@category Layout}
@immutable
class SplitterLayout with EquatableMixin {
  /// Creates a resolved layout. Normally obtained from
  /// `SplitterController.layout` rather than constructed directly.
  const SplitterLayout({
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
    required this.minStartExtent,
    required this.maxStartExtent,
    required this.resolution,
    this.collapsedPane,
  });

  /// The on-screen start fraction after constraints, in `[0, 1]`.
  final double effectiveFraction;

  /// Start (left/top) pane extent in logical pixels.
  final double startExtent;

  /// End (right/bottom) pane extent in logical pixels.
  final double endExtent;

  /// Space shared by the two panes in logical pixels (net of the divider).
  final double availableExtent;

  /// Lowest legal start extent for this layout, in logical pixels - the floor
  /// the divider can be dragged to. Equals [startExtent] when the layout is
  /// pinned (collapsed, or an infeasible shortage/surplus).
  final double minStartExtent;

  /// Highest legal start extent for this layout, in logical pixels - the ceiling
  /// the divider can be dragged to. Equals [startExtent] when the layout is
  /// pinned.
  final double maxStartExtent;

  /// How the solver resolved the request for this layout.
  final SplitterResolution resolution;

  /// Which pane is collapsed in this layout, or null when neither is.
  final SplitterPane? collapsedPane;

  /// Whether the start pane has head-room to grow (the divider can move toward
  /// the end). Useful for gating an "increase" affordance.
  bool get canIncrease => maxStartExtent - startExtent > 1e-9;

  /// Whether the start pane has room to shrink (the divider can move toward the
  /// start). Useful for gating a "decrease" affordance.
  bool get canDecrease => startExtent - minStartExtent > 1e-9;

  @override
  List<Object?> get props => [
    effectiveFraction,
    startExtent,
    endExtent,
    availableExtent,
    minStartExtent,
    maxStartExtent,
    resolution,
    collapsedPane,
  ];

  @override
  String toString() =>
      'SplitterLayout(effective: $effectiveFraction, start: $startExtent, '
      'end: $endExtent, available: $availableExtent, '
      'band: [$minStartExtent, $maxStartExtent], '
      'resolution: ${resolution.name}, collapsed: ${collapsedPane?.name})';
}
