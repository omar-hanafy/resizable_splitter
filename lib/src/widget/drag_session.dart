part of 'resizable_splitter.dart';

/// The immutable identity and start anchors of an in-flight drag.
///
/// Capturing the controller, pointer, axis, direction, start fraction/position,
/// available extent, mode, and preview callback at the moment a drag begins is
/// what lets it end cleanly on the controller it started on - even if the parent
/// swaps the controller, axis, mode, or preview callback mid-drag - and keeps
/// the pointer-to-fraction math stable if the container resizes underneath.
@immutable
class _DragSession {
  const _DragSession({
    required this.controller,
    required this.pointerId,
    required this.axis,
    required this.isRtl,
    required this.startEffectiveFraction,
    required this.startLocalMainAxis,
    required this.availableExtent,
    required this.deferred,
    required this.snap,
    required this.onPreviewChanged,
  });

  final SplitterController controller;
  final int pointerId;
  final Axis axis;
  final bool isRtl;
  final double startEffectiveFraction;
  final double startLocalMainAxis;
  final double availableExtent;
  final bool deferred;

  /// The snap behavior captured at drag start, so the mode and points stay fixed
  /// for the gesture even if the parent rebuilds.
  final SplitterSnapBehavior? snap;
  final ValueChanged<double?>? onPreviewChanged;

  /// Maps the current local main-axis pointer position to a clamped effective
  /// start fraction, measuring motion against the extent captured at drag start
  /// (stable under a mid-drag container resize) and clamping through [solver].
  double fractionFor(double currentLocalMainAxis, SplitterSolver solver) {
    // In RTL the start pane sits on the right, so a rightward (positive) delta
    // must shrink it. Vertical axes are unaffected.
    final delta =
        (currentLocalMainAxis - startLocalMainAxis) * (isRtl ? -1.0 : 1.0);
    final deltaRatio = availableExtent > 0 ? delta / availableExtent : 0.0;
    return solver
        .solve(SplitterPosition.fraction(startEffectiveFraction + deltaRatio))
        .effectiveFraction;
  }
}

/// The result of applying a live snap mode to one drag update: the fraction to
/// request, the source to report, and whether it is a live mode (so the caller
/// writes it exactly rather than through the chatty-update threshold).
class _LiveSnapResult {
  const _LiveSnapResult(
    this.requestFraction,
    this.source, {
    required this.live,
  });

  final double requestFraction;
  final SplitterChangeSource source;
  final bool live;
}
