import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_position.dart';

/// What triggered a split change reported to the change callbacks. Lets
/// consumers tell a user drag apart from a snap, a collapse, or the built-in
/// double-tap reset.
///
/// Note: direct controller writes ([SplitterController.jumpTo], `updateRatio`,
/// `reset`, `animateTo`) and state restoration do not produce a change event -
/// observe those through the controller and its `layoutListenable` - so there is
/// no source value for them.
enum SplitterChangeSource {
  /// A pointer drag of the divider.
  drag,

  /// A keyboard shortcut (arrows / page / home / end).
  keyboard,

  /// An assistive-technology adjust action.
  semantics,

  /// The built-in double-tap reset reaching its target.
  doubleTapReset,

  /// Settling onto a snap point at the end of a drag.
  snap,

  /// Collapsing a pane (`controller.collapse`).
  collapse,

  /// Expanding a collapsed pane back to its prior position
  /// (`controller.expand`).
  restore,
}

/// The payload delivered to the change callbacks: a snapshot of both what was
/// requested and what is actually shown, tagged with the [source] that produced
/// it.
///
/// Reporting [requestedPosition] alongside the resolved [effectiveFraction] and
/// pixel extents is what keeps callbacks honest. When a pixel minimum forces the
/// divider away from the request, consumers can see both the intent (e.g. a
/// pinned sidebar) and the on-screen result rather than a single ambiguous
/// number.
@immutable
class SplitterChangeDetails {
  /// Creates change details for a split update.
  const SplitterChangeDetails({
    required this.requestedPosition,
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
    required this.source,
  });

  /// The position that was requested (the user/controller intent).
  final SplitterPosition requestedPosition;

  /// The on-screen start fraction after constraints, in `[0, 1]`.
  final double effectiveFraction;

  /// Start (left/top) pane extent in logical pixels.
  final double startExtent;

  /// End (right/bottom) pane extent in logical pixels.
  final double endExtent;

  /// Space shared by the two panes in logical pixels (net of the divider).
  final double availableExtent;

  /// What triggered this change.
  final SplitterChangeSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterChangeDetails &&
          runtimeType == other.runtimeType &&
          other.requestedPosition == requestedPosition &&
          other.effectiveFraction == effectiveFraction &&
          other.startExtent == startExtent &&
          other.endExtent == endExtent &&
          other.availableExtent == availableExtent &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    requestedPosition,
    effectiveFraction,
    startExtent,
    endExtent,
    availableExtent,
    source,
  );

  @override
  String toString() =>
      'SplitterChangeDetails(source: ${source.name}, '
      'requested: $requestedPosition, effective: $effectiveFraction, '
      'start: $startExtent, end: $endExtent, available: $availableExtent)';
}
