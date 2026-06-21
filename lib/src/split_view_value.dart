import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_position.dart';

/// A snapshot of a split: both what was requested and what is actually shown.
///
/// Reporting [requestedPosition] alongside the resolved [effectiveFraction] and
/// pixel extents is what keeps callbacks honest. When a pixel minimum forces the
/// divider away from the request, consumers can see both the intent (e.g. a
/// pinned sidebar) and the on-screen result rather than a single ambiguous
/// number.
@immutable
class SplitterValue {
  /// Creates a split snapshot.
  const SplitterValue({
    required this.requestedPosition,
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterValue &&
          runtimeType == other.runtimeType &&
          other.requestedPosition == requestedPosition &&
          other.effectiveFraction == effectiveFraction &&
          other.startExtent == startExtent &&
          other.endExtent == endExtent &&
          other.availableExtent == availableExtent;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    requestedPosition,
    effectiveFraction,
    startExtent,
    endExtent,
    availableExtent,
  );

  @override
  String toString() =>
      'SplitterValue(requested: $requestedPosition, '
      'effective: $effectiveFraction, start: $startExtent, '
      'end: $endExtent, available: $availableExtent)';
}

/// What triggered a split change. Lets consumers tell a user drag apart from a
/// programmatic move, a restore, or a snap.
enum SplitterChangeSource {
  /// A pointer drag of the divider.
  drag,

  /// A keyboard shortcut (arrows / page / home / end).
  keyboard,

  /// An assistive-technology adjust action.
  semantics,

  /// A controller call (`updatePosition`, `animateTo`, ...).
  programmatic,

  /// Settling onto a snap point at the end of a drag.
  snap,

  /// Collapsing or expanding a pane.
  collapse,

  /// Restoring a persisted position.
  restore,
}

/// A [SplitterValue] tagged with the [source] that produced it. This is the
/// payload delivered to change callbacks.
@immutable
class SplitterChangeDetails extends SplitterValue {
  /// Creates change details for a split update.
  const SplitterChangeDetails({
    required super.requestedPosition,
    required super.effectiveFraction,
    required super.startExtent,
    required super.endExtent,
    required super.availableExtent,
    required this.source,
  });

  /// What triggered this change.
  final SplitterChangeSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterChangeDetails &&
          other.requestedPosition == requestedPosition &&
          other.effectiveFraction == effectiveFraction &&
          other.startExtent == startExtent &&
          other.endExtent == endExtent &&
          other.availableExtent == availableExtent &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
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
