/// The outcome of a [SplitterController.animateTo] run, delivered when its
/// future resolves.
///
/// Distinguishing a natural finish from an interruption is what lets an awaiting
/// caller avoid mistaking a cancelled animation for a successful one - for
/// example, emitting a "settled at target" callback only when the animation
/// actually reached the target.
enum SplitterAnimationStatus {
  /// The animation reached its target - or finished instantly because there was
  /// no attached view, animations were disabled, or the target was already the
  /// current position.
  completed,

  /// A drag, key press, reset, or direct value write superseded the animation
  /// before it reached the target.
  canceled,

  /// The splitter was disposed, or its controller was swapped out, before the
  /// animation could finish.
  detached,
}
