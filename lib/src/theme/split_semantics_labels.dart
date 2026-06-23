import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// Localizable strings and value formatting for a [ResizableSplitter]'s
/// accessibility semantics.
///
/// The divider is exposed to assistive technologies as a slider. This object
/// supplies the spoken label (different for a resizable vs a fixed divider, and
/// for each [Axis]) and how the divider's position is read out
/// ([formatValue]). Every field defaults to the built-in English string, so an
/// app only overrides what it needs - typically once, app-wide, via
/// `ResizableSplitterTheme` (or `ThemeData.extension`).
///
/// To override only the spoken label for a single splitter, the simpler
/// [ResizableSplitter.semanticsLabel] string takes precedence over the label
/// resolved here.
/// {@category Theming}
@immutable
class SplitterSemanticsLabels with EquatableMixin {
  /// Creates a set of semantics labels. Every field defaults to English.
  const SplitterSemanticsLabels({
    this.resizeHorizontal = 'Drag to resize left and right panels.',
    this.resizeVertical = 'Drag to resize top and bottom panels.',
    this.staticHorizontal = 'Splitter between left and right panels.',
    this.staticVertical = 'Splitter between top and bottom panels.',
    this.formatValue = _defaultFormatValue,
  });

  /// Label for a resizable horizontal splitter (panes side by side).
  final String resizeHorizontal;

  /// Label for a resizable vertical splitter (panes stacked).
  final String resizeVertical;

  /// Label for a non-resizable horizontal splitter.
  final String staticHorizontal;

  /// Label for a non-resizable vertical splitter.
  final String staticVertical;

  /// Formats the effective start fraction (`0.0`-`1.0`) for the slider's spoken
  /// value, and for the increase/decrease previews. Defaults to a whole
  /// percentage (e.g. `50%`).
  final String Function(double fraction) formatValue;

  static String _defaultFormatValue(double fraction) =>
      '${(fraction.clamp(0.0, 1.0) * 100).round()}%';

  /// The spoken label for the given [axis] and [resizable] state.
  String label({required Axis axis, required bool resizable}) {
    if (axis == Axis.horizontal) {
      return resizable ? resizeHorizontal : staticHorizontal;
    }
    return resizable ? resizeVertical : staticVertical;
  }

  @override
  List<Object?> get props => [
    resizeHorizontal,
    resizeVertical,
    staticHorizontal,
    staticVertical,
    formatValue,
  ];

  @override
  String toString() =>
      'SplitterSemanticsLabels(resizeHorizontal: $resizeHorizontal, '
      'resizeVertical: $resizeVertical, staticHorizontal: $staticHorizontal, '
      'staticVertical: $staticVertical)';
}
