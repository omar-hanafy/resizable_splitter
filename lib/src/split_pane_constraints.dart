import 'package:flutter/foundation.dart';

/// Sentinel for [SplitterPaneConstraints.copyWith] so the nullable
/// [SplitterPaneConstraints.collapsedExtent] can be explicitly cleared (set back
/// to null) rather than only overwritten.
const Object _noUpdate = Object();

/// Per-pane sizing limits for one side of a split, in logical pixels.
///
/// Pixel limits (rather than fractions) are what let a pane keep a fixed size as
/// the container resizes. Fractional caps on the whole split live separately as
/// the start-fraction interval passed to the solver.
@immutable
class SplitterPaneConstraints {
  /// Creates pane constraints.
  ///
  /// [maxExtent] must be `>=` [minExtent]. [collapsedExtent], when set, marks the
  /// pane collapsible and must be in `[0, minExtent]` - collapsing shrinks a pane
  /// below its normal minimum, it never enlarges one. A null [collapsedExtent]
  /// (the default) means the pane cannot be collapsed.
  const SplitterPaneConstraints({
    this.minExtent = 0,
    this.maxExtent = double.infinity,
    this.collapsedExtent,
  }) : assert(minExtent >= 0, 'minExtent must be non-negative'),
       assert(
         maxExtent >= minExtent,
         'maxExtent must be greater than or equal to minExtent',
       ),
       assert(
         collapsedExtent == null || collapsedExtent >= 0,
         'collapsedExtent must be non-negative',
       ),
       assert(
         collapsedExtent == null || collapsedExtent <= minExtent,
         'collapsedExtent must be <= minExtent '
             '(collapse shrinks a pane below its minimum, it never enlarges it)',
       );

  /// Smallest extent this pane may occupy, in logical pixels.
  final double minExtent;

  /// Largest extent this pane may occupy, in logical pixels. Defaults to
  /// [double.infinity] (unbounded).
  final double maxExtent;

  /// The extent this pane occupies while collapsed, in logical pixels, or null
  /// (the default) if the pane cannot be collapsed. When set, must be
  /// `<= minExtent`. Collapsing bypasses [minExtent] to reach this size.
  final double? collapsedExtent;

  /// Whether this pane may be collapsed (i.e. [collapsedExtent] is set).
  bool get collapsible => collapsedExtent != null;

  /// Returns a copy with the given fields replaced. Pass `collapsedExtent: null`
  /// to make the pane non-collapsible; omit it to keep the current value.
  SplitterPaneConstraints copyWith({
    double? minExtent,
    double? maxExtent,
    Object? collapsedExtent = _noUpdate,
  }) {
    return SplitterPaneConstraints(
      minExtent: minExtent ?? this.minExtent,
      maxExtent: maxExtent ?? this.maxExtent,
      collapsedExtent: identical(collapsedExtent, _noUpdate)
          ? this.collapsedExtent
          : collapsedExtent as double?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterPaneConstraints &&
          other.minExtent == minExtent &&
          other.maxExtent == maxExtent &&
          other.collapsedExtent == collapsedExtent;

  @override
  int get hashCode => Object.hash(minExtent, maxExtent, collapsedExtent);

  @override
  String toString() =>
      'SplitterPaneConstraints(minExtent: $minExtent, '
      'maxExtent: $maxExtent, collapsedExtent: $collapsedExtent)';
}

/// Identifies one of the two panes of a split.
enum SplitterPane {
  /// The leading pane (left in LTR, right in RTL; top on a vertical axis).
  start,

  /// The trailing pane (right in LTR, left in RTL; bottom on a vertical axis).
  end,
}

/// Policy applied for a *shortage*: both panes' minimums cannot fit at once
/// (`start.minExtent + end.minExtent > available`).
///
/// A tie-break that only takes effect when the layout is too small to honor both
/// minimums; otherwise the requested position is simply clamped. The opposite
/// *surplus* case (both maximums too small to fill) is governed separately by
/// [SplitterSurplusPolicy].
enum SplitterConstraintPolicy {
  /// Keep the start pane at its minimum; the end pane gives up the deficit.
  favorStart,

  /// Keep the end pane at its minimum; the start pane gives up the deficit.
  favorEnd,

  /// Divide the available space in proportion to the configured pane minimums.
  proportional,
}

/// Policy applied for a *surplus*: both panes' maximums are too small to fill the
/// available space (`start.maxExtent + end.maxExtent < available`).
///
/// The counterpart to [SplitterConstraintPolicy] (which handles the shortage
/// case). It only takes effect when both panes have a finite [maxExtent] whose
/// sum is below the available space. The default, [giveToStart], matches the
/// behavior before this policy existed (the start pane absorbs the slack).
enum SplitterSurplusPolicy {
  /// Grow the start pane past its maximum to fill; the end pane stays at its
  /// maximum.
  giveToStart,

  /// Grow the end pane past its maximum to fill; the start pane stays at its
  /// maximum.
  giveToEnd,

  /// Grow both panes past their maximum, splitting the space in proportion to
  /// the two maximums.
  proportional,

  /// Keep both panes at their maximum and leave the leftover as an empty gap
  /// between them (the divider sits at the start pane's trailing edge).
  leaveGap,
}
