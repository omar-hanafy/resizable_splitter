import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/model/split_position.dart';

/// What triggered a split change reported to the change callbacks. Lets
/// consumers tell a user drag apart from a snap, a collapse, or the built-in
/// double-tap reset.
///
/// Note: direct controller writes ([SplitterController.jumpTo], `updateRatio`,
/// `reset`, `animateTo`) and state restoration do not produce a change event -
/// observe those through the controller and its `layoutListenable` - so there is
/// no source value for them.
/// {@category Events}
enum SplitterChangeSource {
  /// A pointer drag of the divider.
  drag,

  /// A keyboard shortcut (arrows / page / home / end).
  keyboard,

  /// An assistive-technology adjust action.
  semantics,

  /// The built-in double-tap reset reaching its target.
  doubleTapReset,

  /// A snap point claiming the divider: either a live [StickySnap] capture
  /// during the drag, or settling onto the nearest point when a [ReleaseSnap]
  /// drag ends.
  snap,

  /// Collapsing a pane (`controller.collapse`).
  collapse,

  /// Expanding a collapsed pane back to its prior position
  /// (`controller.expand`).
  restore,
}

/// How an interaction that began with [ResizableSplitter.onChangeStart] ended,
/// reported in the [SplitterChangeDetails] passed to
/// [ResizableSplitter.onChangeEnd].
///
/// `onChangeStart` and `onChangeEnd` are balanced: every start is followed by
/// exactly one end (for a normal pointer release or a system cancel), so a
/// consumer can pair them - to toggle a "dragging" flag, say - and still tell a
/// committed release from a cancel. (A drag force-ended by reconfiguring or
/// disposing the widget mid-gesture is the one exception: it fires no end, as
/// calling back during a lifecycle change would be unsafe.)
/// {@category Events}
enum SplitterChangeEnd {
  /// The pointer lifted and the final position was committed (a snap may have
  /// claimed it - see [SplitterChangeDetails.source]).
  committed,

  /// The gesture was canceled by the system before commit. Nothing new is
  /// committed; the divider stays where it was when the cancel arrived.
  canceled,
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
/// {@category Events}
@immutable
class SplitterChangeDetails with EquatableMixin {
  /// Creates change details for a split update.
  const SplitterChangeDetails({
    required this.requestedPosition,
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
    required this.source,
    this.end,
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

  /// How the interaction ended. Non-null only in [ResizableSplitter.onChangeEnd];
  /// null for [ResizableSplitter.onChangeStart] and `onChanged`.
  final SplitterChangeEnd? end;

  @override
  List<Object?> get props => [
    requestedPosition,
    effectiveFraction,
    startExtent,
    endExtent,
    availableExtent,
    source,
    end,
  ];

  @override
  String toString() =>
      'SplitterChangeDetails(source: ${source.name}, '
      'end: ${end?.name}, requested: $requestedPosition, '
      'effective: $effectiveFraction, startExtent: $startExtent, '
      'endExtent: $endExtent, available: $availableExtent)';
}
