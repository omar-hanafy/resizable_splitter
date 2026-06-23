part of 'resizable_splitter.dart';

/// Drives vsync animation for a [SplitterController]. Implemented by the
/// splitter's [State], which owns the [TickerProvider].
abstract interface class _SplitterAnimator {
  /// Animates the controller value to [target]; the future resolves with the
  /// outcome ([SplitterAnimationStatus]) when the run ends.
  Future<SplitterAnimationStatus> animateTo(
    double target,
    Duration duration,
    Curve curve,
  );

  /// Stops any in-progress animation (resolving it as cancelled).
  void cancel();
}

/// One run of [SplitterController.animateTo], owned by the splitter's [State].
///
/// Captures the [controller] it targets plus the interpolation, and a completer
/// resolved exactly once with the run's [SplitterAnimationStatus]. Tying a run
/// to its controller is what lets a controller swap end it cleanly instead of
/// letting its ticks bleed onto a different controller.
class _AnimationSession {
  _AnimationSession({
    required this.controller,
    required this.begin,
    required this.end,
    required this.curve,
  });

  final SplitterController controller;
  final double begin;
  final double end;
  final Curve curve;
  final Completer<SplitterAnimationStatus> _completer =
      Completer<SplitterAnimationStatus>();

  Future<SplitterAnimationStatus> get future => _completer.future;

  /// Resolves the run's future once; later calls are ignored.
  void resolve(SplitterAnimationStatus status) {
    if (!_completer.isCompleted) _completer.complete(status);
  }
}
