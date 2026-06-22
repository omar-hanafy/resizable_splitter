import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:resizable_splitter/src/split_divider_style.dart';
import 'package:resizable_splitter/src/split_semantics_labels.dart';

/// Sentinel for the copyWith methods in this library so a nullable field can be
/// explicitly cleared (set back to null) rather than only overwritten.
const Object _noUpdate = Object();

/// How the splitter should behave when the main-axis constraints are unbounded.
enum UnboundedBehavior {
  /// Expand panels using Flex widgets when constraints are unbounded.
  flexExpand,

  /// Constrain the layout using a [LimitedBox] when constraints are unbounded.
  limitedBox,
}

/// Shared styling and behavior for [ResizableSplitter] widgets.
///
/// Every field is nullable, and an unset field genuinely means "unset": it
/// falls through to the next layer rather than re-asserting a default. The
/// resolution order, lowest precedence first, is the built-in default, the
/// app-wide `ThemeData` extension, a local [ResizableSplitterTheme], then the
/// explicit constructor argument on the widget. Because nothing here carries a
/// default, layering a partial override (for example a local theme that sets
/// only [blockerColor]) can never clobber a value a broader scope supplied.
///
/// Use it in two interchangeable ways:
///  * app-wide, via `ThemeData(extensions: [ResizableSplitterThemeData(...)])`;
///  * for a subtree, via [ResizableSplitterTheme].
@immutable
class ResizableSplitterThemeData
    extends ThemeExtension<ResizableSplitterThemeData> {
  /// Creates theme data. Every field defaults to null, meaning "defer".
  const ResizableSplitterThemeData({
    this.divider,
    this.blockerColor,
    this.overlayEnabled,
    this.enableKeyboard,
    this.enableHaptics,
    this.keyboardStep,
    this.pageStep,
    this.unboundedBehavior,
    this.fallbackMainAxisExtent,
    this.antiAliasingWorkaround,
    this.semantics,
  }) : assert(
         keyboardStep == null || keyboardStep >= 0,
         'keyboardStep must be non-negative',
       ),
       assert(
         pageStep == null || pageStep >= 0,
         'pageStep must be non-negative',
       ),
       assert(
         fallbackMainAxisExtent == null || fallbackMainAxisExtent > 0,
         'fallbackMainAxisExtent must be greater than zero',
       );

  /// Divider appearance and grab configuration.
  final SplitterDividerStyle? divider;

  /// Optional overlay tint while dragging.
  final Color? blockerColor;

  /// Whether the overlay shield is inserted during drags.
  final bool? overlayEnabled;

  /// Whether keyboard interaction is enabled.
  final bool? enableKeyboard;

  /// Whether haptic feedback fires on drag start and keyboard adjustments.
  final bool? enableHaptics;

  /// Ratio delta applied when pressing arrow keys.
  final double? keyboardStep;

  /// Ratio delta applied when pressing page keys.
  final double? pageStep;

  /// Strategy when encountering unbounded main-axis constraints.
  final UnboundedBehavior? unboundedBehavior;

  /// Fallback extent used when opting into [UnboundedBehavior.limitedBox].
  final double? fallbackMainAxisExtent;

  /// Whether to snap the leading panel size to whole physical pixels.
  final bool? antiAliasingWorkaround;

  /// Localizable semantics strings and value formatting for descendant
  /// splitters. Null defers to the built-in English defaults.
  final SplitterSemanticsLabels? semantics;

  /// Returns a copy with the provided fields replaced.
  /// Returns a copy with the provided fields replaced. Every parameter accepts
  /// an explicit `null` to clear that field (fall back to the next layer);
  /// omitting a parameter keeps the current value.
  @override
  ResizableSplitterThemeData copyWith({
    Object? divider = _noUpdate,
    Object? blockerColor = _noUpdate,
    Object? overlayEnabled = _noUpdate,
    Object? enableKeyboard = _noUpdate,
    Object? enableHaptics = _noUpdate,
    Object? keyboardStep = _noUpdate,
    Object? pageStep = _noUpdate,
    Object? unboundedBehavior = _noUpdate,
    Object? fallbackMainAxisExtent = _noUpdate,
    Object? antiAliasingWorkaround = _noUpdate,
    Object? semantics = _noUpdate,
  }) {
    return ResizableSplitterThemeData(
      divider: identical(divider, _noUpdate)
          ? this.divider
          : divider as SplitterDividerStyle?,
      blockerColor: identical(blockerColor, _noUpdate)
          ? this.blockerColor
          : blockerColor as Color?,
      overlayEnabled: identical(overlayEnabled, _noUpdate)
          ? this.overlayEnabled
          : overlayEnabled as bool?,
      enableKeyboard: identical(enableKeyboard, _noUpdate)
          ? this.enableKeyboard
          : enableKeyboard as bool?,
      enableHaptics: identical(enableHaptics, _noUpdate)
          ? this.enableHaptics
          : enableHaptics as bool?,
      keyboardStep: identical(keyboardStep, _noUpdate)
          ? this.keyboardStep
          : (keyboardStep as num?)?.toDouble(),
      pageStep: identical(pageStep, _noUpdate)
          ? this.pageStep
          : (pageStep as num?)?.toDouble(),
      unboundedBehavior: identical(unboundedBehavior, _noUpdate)
          ? this.unboundedBehavior
          : unboundedBehavior as UnboundedBehavior?,
      fallbackMainAxisExtent: identical(fallbackMainAxisExtent, _noUpdate)
          ? this.fallbackMainAxisExtent
          : (fallbackMainAxisExtent as num?)?.toDouble(),
      antiAliasingWorkaround: identical(antiAliasingWorkaround, _noUpdate)
          ? this.antiAliasingWorkaround
          : antiAliasingWorkaround as bool?,
      semantics: identical(semantics, _noUpdate)
          ? this.semantics
          : semantics as SplitterSemanticsLabels?,
    );
  }

  /// Overlays [other] on top of this data, field by field. A non-null field in
  /// [other] wins; unset fields fall through to this. The nested [divider] is
  /// merged the same way, so a local divider style layers over the base instead
  /// of replacing it wholesale.
  ResizableSplitterThemeData merge(ResizableSplitterThemeData? other) {
    if (other == null) return this;
    return ResizableSplitterThemeData(
      divider: divider == null ? other.divider : divider!.merge(other.divider),
      blockerColor: other.blockerColor ?? blockerColor,
      overlayEnabled: other.overlayEnabled ?? overlayEnabled,
      enableKeyboard: other.enableKeyboard ?? enableKeyboard,
      enableHaptics: other.enableHaptics ?? enableHaptics,
      keyboardStep: other.keyboardStep ?? keyboardStep,
      pageStep: other.pageStep ?? pageStep,
      unboundedBehavior: other.unboundedBehavior ?? unboundedBehavior,
      fallbackMainAxisExtent:
          other.fallbackMainAxisExtent ?? fallbackMainAxisExtent,
      antiAliasingWorkaround:
          other.antiAliasingWorkaround ?? antiAliasingWorkaround,
      semantics: other.semantics ?? semantics,
    );
  }

  /// Linearly interpolates between two theme data objects.
  @override
  ResizableSplitterThemeData lerp(
    covariant ResizableSplitterThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ResizableSplitterThemeData(
      divider: SplitterDividerStyle.lerp(divider, other.divider, t),
      blockerColor: Color.lerp(blockerColor, other.blockerColor, t),
      overlayEnabled: t < 0.5 ? overlayEnabled : other.overlayEnabled,
      enableKeyboard: t < 0.5 ? enableKeyboard : other.enableKeyboard,
      enableHaptics: t < 0.5 ? enableHaptics : other.enableHaptics,
      keyboardStep: lerpDouble(keyboardStep, other.keyboardStep, t),
      pageStep: lerpDouble(pageStep, other.pageStep, t),
      unboundedBehavior: t < 0.5 ? unboundedBehavior : other.unboundedBehavior,
      fallbackMainAxisExtent: lerpDouble(
        fallbackMainAxisExtent,
        other.fallbackMainAxisExtent,
        t,
      ),
      antiAliasingWorkaround: t < 0.5
          ? antiAliasingWorkaround
          : other.antiAliasingWorkaround,
      // Labels are discrete strings/callbacks, not interpolable; swap at the
      // midpoint like the other non-numeric fields.
      semantics: t < 0.5 ? semantics : other.semantics,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResizableSplitterThemeData &&
          other.divider == divider &&
          other.blockerColor == blockerColor &&
          other.overlayEnabled == overlayEnabled &&
          other.enableKeyboard == enableKeyboard &&
          other.enableHaptics == enableHaptics &&
          other.keyboardStep == keyboardStep &&
          other.pageStep == pageStep &&
          other.unboundedBehavior == unboundedBehavior &&
          other.fallbackMainAxisExtent == fallbackMainAxisExtent &&
          other.antiAliasingWorkaround == antiAliasingWorkaround &&
          other.semantics == semantics;

  @override
  int get hashCode => Object.hash(
    divider,
    blockerColor,
    overlayEnabled,
    enableKeyboard,
    enableHaptics,
    keyboardStep,
    pageStep,
    unboundedBehavior,
    fallbackMainAxisExtent,
    antiAliasingWorkaround,
    semantics,
  );

  @override
  String toString() =>
      'ResizableSplitterThemeData(divider: $divider, '
      'blockerColor: $blockerColor, overlayEnabled: $overlayEnabled, '
      'enableKeyboard: $enableKeyboard, enableHaptics: $enableHaptics, '
      'keyboardStep: $keyboardStep, pageStep: $pageStep, '
      'unboundedBehavior: $unboundedBehavior, '
      'fallbackMainAxisExtent: $fallbackMainAxisExtent, '
      'antiAliasingWorkaround: $antiAliasingWorkaround, '
      'semantics: $semantics)';
}

/// Provides [ResizableSplitterThemeData] to a subtree.
class ResizableSplitterTheme extends StatelessWidget {
  /// Creates a theme boundary for [ResizableSplitter] widgets.
  const ResizableSplitterTheme({
    super.key,
    required this.data,
    required this.child,
  });

  /// Theme values applied to descendant splitters.
  final ResizableSplitterThemeData data;

  /// The subtree receiving the themed values.
  final Widget child;

  /// Resolves the effective theme for [context].
  ///
  /// Precedence, lowest to highest: the app-wide
  /// `ThemeData.extension<ResizableSplitterThemeData>()`, then every enclosing
  /// [ResizableSplitterTheme] from outermost to innermost. Because every field
  /// is nullable, a more specific scope only overrides the fields it actually
  /// sets; the rest fall through. Constructor parameters on the widget sit above
  /// all of these.
  static ResizableSplitterThemeData of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedSplitterTheme>();
    final extension = Theme.of(context).extension<ResizableSplitterThemeData>();
    final base = extension ?? const ResizableSplitterThemeData();
    // The nearest scope already folded every ancestor scope into its data (see
    // [build]), so layering it over the app-wide extension yields the full
    // extension -> outer -> ... -> inner resolution.
    final local = inherited?.data;
    return local == null ? base : base.merge(local);
  }

  @override
  Widget build(BuildContext context) {
    // Merge this scope's data OVER any ancestor scope so nested themes compose;
    // each level overrides only the fields it sets. Depending on the ancestor
    // also rebuilds this scope when an outer theme changes.
    final ancestor = context
        .dependOnInheritedWidgetOfExactType<_InheritedSplitterTheme>();
    final merged = ancestor == null ? data : ancestor.data.merge(data);
    return _InheritedSplitterTheme(data: merged, child: child);
  }
}

/// Carries the resolved [ResizableSplitterThemeData] to descendants. Extends
/// [InheritedTheme] so a scope can be captured into overlays and routes via
/// [InheritedTheme.captureAll] / [InheritedTheme.capture].
class _InheritedSplitterTheme extends InheritedTheme {
  const _InheritedSplitterTheme({required this.data, required super.child});

  final ResizableSplitterThemeData data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _InheritedSplitterTheme(data: data, child: child);

  @override
  bool updateShouldNotify(_InheritedSplitterTheme oldWidget) =>
      data != oldWidget.data;
}
