// ignore_for_file: use_setters_to_change_properties
part of 'resizable_splitter.dart';

/// Serializes a [SplitterPosition] for state restoration as a `[kind, number]`
/// pair, where kind is 0 (fraction), 1 (start pixels), or 2 (end pixels).
class _RestorableSplitterPosition extends RestorableValue<SplitterPosition> {
  _RestorableSplitterPosition(this._defaultValue);

  final SplitterPosition Function() _defaultValue;

  @override
  SplitterPosition createDefaultValue() => _defaultValue();

  @override
  void didUpdateValue(SplitterPosition? oldValue) {
    if (oldValue == null || oldValue != value) {
      notifyListeners();
    }
  }

  @override
  SplitterPosition fromPrimitives(Object? data) {
    // Be defensive: restoration data can be malformed or from an older version.
    if (data is List && data.length == 2 && data[1] is num) {
      final number = (data[1]! as num).toDouble();
      return switch (data[0]) {
        1 => SplitterPosition.startPixels(number),
        2 => SplitterPosition.endPixels(number),
        _ => SplitterPosition.fraction(number),
      };
    }
    return _defaultValue();
  }

  @override
  Object toPrimitives() => switch (value) {
    FractionSplitterPosition(:final value) => <Object>[0, value],
    StartPixelsSplitterPosition(:final extent) => <Object>[1, extent],
    EndPixelsSplitterPosition(:final extent) => <Object>[2, extent],
  };
}
