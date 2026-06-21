import 'package:flutter/foundation.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';

/// The complete, atomic requested state of a split: where the divider is wanted
/// ([position]) and which pane, if any, is collapsed ([collapsedPane]).
///
/// This is the value held by a `SplitterController`. Bundling the request and
/// the collapse into one immutable object is deliberate: it makes a desynced
/// controller unrepresentable. Because collapse is part of the value, it is part
/// of the `==` that gates notification, so a collapse can never change silently
/// (the historic "collapse, then write an equal value" bug, where the controller
/// reported expanded while the UI stayed collapsed, is gone by construction).
///
/// The resolved, on-screen geometry is published separately as a
/// `SplitterLayout`; this type is purely the intent.
@immutable
class SplitterState {
  /// Creates a split state at [position], optionally with [collapsedPane]
  /// collapsed.
  const SplitterState({required this.position, this.collapsedPane});

  /// Where the divider is requested, independent of the current layout.
  final SplitterPosition position;

  /// Which pane is collapsed, or null when neither is.
  final SplitterPane? collapsedPane;

  /// Whether either pane is currently collapsed.
  bool get isCollapsed => collapsedPane != null;

  /// Returns a copy with a different [position], keeping the collapse.
  ///
  /// Used for an animation tick, where the position moves but the pane stays
  /// collapsed. To change the position as a fresh user intent that *clears* the
  /// collapse, construct a new [SplitterState] (or use the controller's
  /// `jumpTo`) instead - there is intentionally no way to clear the collapse
  /// through [copyWith], so the nullable field can never be cleared by accident.
  SplitterState copyWith({SplitterPosition? position}) =>
      SplitterState(position: position ?? this.position, collapsedPane: collapsedPane);

  /// Returns a state with [pane] collapsed, keeping the position. Returns this
  /// same instance when [pane] is already the collapsed one, so a redundant
  /// collapse is a no-op the controller's notifier can skip.
  SplitterState collapse(SplitterPane pane) => collapsedPane == pane
      ? this
      : SplitterState(position: position, collapsedPane: pane);

  /// Returns an expanded state (no collapse), keeping the position. Returns this
  /// same instance when nothing is collapsed.
  SplitterState expand() =>
      collapsedPane == null ? this : SplitterState(position: position);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterState &&
          runtimeType == other.runtimeType &&
          other.position == position &&
          other.collapsedPane == collapsedPane;

  @override
  int get hashCode => Object.hash(runtimeType, position, collapsedPane);

  @override
  String toString() =>
      'SplitterState(position: $position, collapsedPane: ${collapsedPane?.name})';
}
