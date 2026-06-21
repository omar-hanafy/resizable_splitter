import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:resizable_splitter/src/split_divider_style.dart';

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

  /// Returns a copy with the provided fields replaced.
  @override
  ResizableSplitterThemeData copyWith({
    SplitterDividerStyle? divider,
    Color? blockerColor,
    bool? overlayEnabled,
    bool? enableKeyboard,
    bool? enableHaptics,
    double? keyboardStep,
    double? pageStep,
    UnboundedBehavior? unboundedBehavior,
    double? fallbackMainAxisExtent,
    bool? antiAliasingWorkaround,
  }) {
    return ResizableSplitterThemeData(
      divider: divider ?? this.divider,
      blockerColor: blockerColor ?? this.blockerColor,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      enableKeyboard: enableKeyboard ?? this.enableKeyboard,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      keyboardStep: keyboardStep ?? this.keyboardStep,
      pageStep: pageStep ?? this.pageStep,
      unboundedBehavior: unboundedBehavior ?? this.unboundedBehavior,
      fallbackMainAxisExtent:
          fallbackMainAxisExtent ?? this.fallbackMainAxisExtent,
      antiAliasingWorkaround:
          antiAliasingWorkaround ?? this.antiAliasingWorkaround,
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
          other.antiAliasingWorkaround == antiAliasingWorkaround;

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
  );

  @override
  String toString() =>
      'ResizableSplitterThemeData(divider: $divider, '
      'blockerColor: $blockerColor, overlayEnabled: $overlayEnabled, '
      'enableKeyboard: $enableKeyboard, enableHaptics: $enableHaptics, '
      'keyboardStep: $keyboardStep, pageStep: $pageStep, '
      'unboundedBehavior: $unboundedBehavior, '
      'fallbackMainAxisExtent: $fallbackMainAxisExtent, '
      'antiAliasingWorkaround: $antiAliasingWorkaround)';
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
  /// `ThemeData.extension<ResizableSplitterThemeData>()`, then a local
  /// [ResizableSplitterTheme]. Because every field is nullable, a more specific
  /// scope only overrides the fields it actually sets; the rest fall through.
  /// Constructor parameters on the widget sit above both.
  static ResizableSplitterThemeData of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedSplitterTheme>();
    final extension = Theme.of(context).extension<ResizableSplitterThemeData>();
    final base = extension ?? const ResizableSplitterThemeData();
    final local = inherited?.theme.data;
    return local == null ? base : base.merge(local);
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedSplitterTheme(theme: this, child: child);
  }
}

class _InheritedSplitterTheme extends InheritedWidget {
  const _InheritedSplitterTheme({required this.theme, required super.child});

  final ResizableSplitterTheme theme;

  @override
  bool updateShouldNotify(_InheritedSplitterTheme oldWidget) =>
      theme.data != oldWidget.theme.data;
}
