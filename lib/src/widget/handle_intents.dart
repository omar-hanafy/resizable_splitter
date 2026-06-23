part of 'resizable_splitter.dart';

/// Intent for keyboard-based splitter adjustment.
class _AdjustIntent extends Intent {
  const _AdjustIntent(this.delta);

  final double delta;
}

class _JumpIntent extends Intent {
  const _JumpIntent._(this.toMin);

  const _JumpIntent.toMin() : this._(true);

  const _JumpIntent.toMax() : this._(false);
  final bool toMin;
}
