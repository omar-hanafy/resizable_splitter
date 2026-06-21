import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';

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
/// A controller reports `null` for its layout before the first layout pass,
/// rather than pretending a pixel request already has an effective fraction.
@immutable
class SplitterLayout {
  /// Creates a resolved layout. Normally obtained from
  /// `SplitterController.layout` rather than constructed directly.
  const SplitterLayout({
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
    required this.isConstrained,
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

  /// Whether the panes' hard minimums could not all be honored, so the
  /// constraint-policy tie-break decided this layout.
  final bool isConstrained;

  /// Which pane is collapsed in this layout, or null when neither is.
  final SplitterPane? collapsedPane;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterLayout &&
          runtimeType == other.runtimeType &&
          other.effectiveFraction == effectiveFraction &&
          other.startExtent == startExtent &&
          other.endExtent == endExtent &&
          other.availableExtent == availableExtent &&
          other.isConstrained == isConstrained &&
          other.collapsedPane == collapsedPane;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    effectiveFraction,
    startExtent,
    endExtent,
    availableExtent,
    isConstrained,
    collapsedPane,
  );

  @override
  String toString() =>
      'SplitterLayout(effective: $effectiveFraction, start: $startExtent, '
      'end: $endExtent, available: $availableExtent, '
      'constrained: $isConstrained, collapsed: ${collapsedPane?.name})';
}
