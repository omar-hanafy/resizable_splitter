import 'package:flutter/foundation.dart';

/// Per-pane sizing limits for one side of a split, in logical pixels.
///
/// Pixel limits (rather than fractions) are what let a pane keep a fixed size as
/// the container resizes. Fractional caps on the whole split live separately as
/// the start-fraction interval passed to the solver.
@immutable
class SplitterPaneConstraints {
  /// Creates pane constraints. [maxExtent] must be `>=` [minExtent], and both
  /// [minExtent] and [collapsedExtent] must be non-negative.
  const SplitterPaneConstraints({
    this.minExtent = 0,
    this.maxExtent = double.infinity,
    this.collapsible = false,
    this.collapsedExtent = 0,
  }) : assert(minExtent >= 0, 'minExtent must be non-negative'),
       assert(
         maxExtent >= minExtent,
         'maxExtent must be greater than or equal to minExtent',
       ),
       assert(collapsedExtent >= 0, 'collapsedExtent must be non-negative');

  /// Smallest extent this pane may occupy, in logical pixels.
  final double minExtent;

  /// Largest extent this pane may occupy, in logical pixels. Defaults to
  /// [double.infinity] (unbounded).
  final double maxExtent;

  /// Whether this pane may be collapsed to [collapsedExtent].
  final bool collapsible;

  /// Extent this pane occupies while collapsed, in logical pixels.
  final double collapsedExtent;

  /// Returns a copy with the given fields replaced.
  SplitterPaneConstraints copyWith({
    double? minExtent,
    double? maxExtent,
    bool? collapsible,
    double? collapsedExtent,
  }) {
    return SplitterPaneConstraints(
      minExtent: minExtent ?? this.minExtent,
      maxExtent: maxExtent ?? this.maxExtent,
      collapsible: collapsible ?? this.collapsible,
      collapsedExtent: collapsedExtent ?? this.collapsedExtent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterPaneConstraints &&
          other.minExtent == minExtent &&
          other.maxExtent == maxExtent &&
          other.collapsible == collapsible &&
          other.collapsedExtent == collapsedExtent;

  @override
  int get hashCode =>
      Object.hash(minExtent, maxExtent, collapsible, collapsedExtent);

  @override
  String toString() =>
      'SplitterPaneConstraints(minExtent: $minExtent, '
      'maxExtent: $maxExtent, collapsible: $collapsible, '
      'collapsedExtent: $collapsedExtent)';
}

/// Identifies one of the two panes of a split.
enum SplitterPane {
  /// The leading pane (left in LTR, right in RTL; top on a vertical axis).
  start,

  /// The trailing pane (right in LTR, left in RTL; bottom on a vertical axis).
  end,
}

/// Policy applied when both panes cannot satisfy their hard limits at once.
///
/// This is the final tie-break in the constraint hierarchy: it only takes effect
/// when the legal start-extent interval is empty (a layout too small to honor
/// both minimums). Otherwise the requested position is simply clamped.
enum SplitterConstraintPolicy {
  /// Keep the start pane at its minimum; the end pane gives up the deficit.
  favorStart,

  /// Keep the end pane at its minimum; the start pane gives up the deficit.
  favorEnd,

  /// Divide the available space in proportion to the configured pane minimums.
  proportional,
}
