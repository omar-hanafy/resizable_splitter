import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// How the splitter should behave when the main-axis constraints are unbounded.
enum UnboundedBehavior {
  /// Expand panels using Flex widgets when constraints are unbounded.
  flexExpand,

  /// Constrain the layout using a [LimitedBox] when constraints are unbounded.
  limitedBox,
}

/// Shared styling and behavior overrides for [ResizableSplitter] widgets.
@immutable
class ResizableSplitterThemeData {
  /// Creates theme data with optional overrides for splitter presentation.
  const ResizableSplitterThemeData({
    this.dividerThickness = 6.0,
    this.dividerColor,
    this.dividerHoverColor,
    this.dividerActiveColor,
    this.blockerColor,
    this.handleHitSlop = 0.0,
    this.overlayEnabled = true,
    this.enableKeyboard = true,
    this.enableHaptics = true,
    this.keyboardStep = 0.01,
    this.pageStep = 0.1,
    this.unboundedBehavior = UnboundedBehavior.flexExpand,
    this.fallbackMainAxisExtent = 500.0,
    this.antiAliasingWorkaround = false,
  }) : assert(dividerThickness >= 0, 'dividerThickness must be non-negative'),
       assert(handleHitSlop >= 0, 'handleHitSlop must be non-negative'),
       assert(
         fallbackMainAxisExtent > 0,
         'fallbackMainAxisExtent must be greater than zero',
       );

  /// Thickness of the divider in logical pixels.
  final double dividerThickness;

  /// Idle color for the divider.
  final Color? dividerColor;

  /// Divider color when hovered.
  final Color? dividerHoverColor;

  /// Divider color when dragged.
  final Color? dividerActiveColor;

  /// Optional overlay tint while dragging.
  final Color? blockerColor;

  /// Extra invisible padding around the handle to ease hit testing.
  final double handleHitSlop;

  /// Whether the overlay shield should be inserted during drags.
  final bool overlayEnabled;

  /// Whether keyboard interaction is enabled by default.
  final bool enableKeyboard;

  /// Whether haptic feedback fires on drag start and keyboard adjustments.
  final bool enableHaptics;

  /// Ratio delta applied when pressing arrow keys.
  final double keyboardStep;

  /// Ratio delta applied when pressing page keys.
  final double pageStep;

  /// Strategy when encountering unbounded main-axis constraints.
  final UnboundedBehavior unboundedBehavior;

  /// Fallback extent used when opting into [UnboundedBehavior.limitedBox].
  final double fallbackMainAxisExtent;

  /// Whether to snap the leading panel size to whole pixels.
  final bool antiAliasingWorkaround;

  /// Returns a copy of this theme with the provided fields replaced.
  ResizableSplitterThemeData copyWith({
    double? dividerThickness,
    Color? dividerColor,
    Color? dividerHoverColor,
    Color? dividerActiveColor,
    Color? blockerColor,
    double? handleHitSlop,
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
      dividerThickness: dividerThickness ?? this.dividerThickness,
      dividerColor: dividerColor ?? this.dividerColor,
      dividerHoverColor: dividerHoverColor ?? this.dividerHoverColor,
      dividerActiveColor: dividerActiveColor ?? this.dividerActiveColor,
      blockerColor: blockerColor ?? this.blockerColor,
      handleHitSlop: handleHitSlop ?? this.handleHitSlop,
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

  /// Returns a copy of this theme with missing values filled from [overrides].
  ResizableSplitterThemeData mergeOverrides(
    ResizableSplitterThemeOverrides? overrides,
  ) {
    if (overrides == null) return this;
    return ResizableSplitterThemeData(
      dividerThickness: overrides.dividerThickness ?? dividerThickness,
      dividerColor: overrides.dividerColor ?? dividerColor,
      dividerHoverColor: overrides.dividerHoverColor ?? dividerHoverColor,
      dividerActiveColor: overrides.dividerActiveColor ?? dividerActiveColor,
      blockerColor: overrides.blockerColor ?? blockerColor,
      handleHitSlop: overrides.handleHitSlop ?? handleHitSlop,
      overlayEnabled: overrides.overlayEnabled ?? overlayEnabled,
      enableKeyboard: overrides.enableKeyboard ?? enableKeyboard,
      enableHaptics: overrides.enableHaptics ?? enableHaptics,
      keyboardStep: overrides.keyboardStep ?? keyboardStep,
      pageStep: overrides.pageStep ?? pageStep,
      unboundedBehavior: overrides.unboundedBehavior ?? unboundedBehavior,
      fallbackMainAxisExtent:
          overrides.fallbackMainAxisExtent ?? fallbackMainAxisExtent,
      antiAliasingWorkaround:
          overrides.antiAliasingWorkaround ?? antiAliasingWorkaround,
    );
  }

  /// Overlays a more specific [local] theme on top of this base, with [local]
  /// taking precedence. Nullable fields fall back to this base when [local]
  /// leaves them unset (so an app-wide extension can still supply colors a
  /// local theme omits); the remaining fields always come from [local].
  ///
  /// Used by [ResizableSplitterTheme.of] so a local `ResizableSplitterTheme`
  /// overrides the global `ThemeExtension`, matching the documented precedence.
  ResizableSplitterThemeData mergeTheme(ResizableSplitterThemeData local) {
    return ResizableSplitterThemeData(
      dividerThickness: local.dividerThickness,
      dividerColor: local.dividerColor ?? dividerColor,
      dividerHoverColor: local.dividerHoverColor ?? dividerHoverColor,
      dividerActiveColor: local.dividerActiveColor ?? dividerActiveColor,
      blockerColor: local.blockerColor ?? blockerColor,
      handleHitSlop: local.handleHitSlop,
      overlayEnabled: local.overlayEnabled,
      enableKeyboard: local.enableKeyboard,
      enableHaptics: local.enableHaptics,
      keyboardStep: local.keyboardStep,
      pageStep: local.pageStep,
      unboundedBehavior: local.unboundedBehavior,
      fallbackMainAxisExtent: local.fallbackMainAxisExtent,
      antiAliasingWorkaround: local.antiAliasingWorkaround,
    );
  }
}

/// Provides [ResizableSplitterThemeData] to descendants.
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

  static const _default = ResizableSplitterThemeData();

  /// Retrieves the nearest [ResizableSplitterThemeData].
  ///
  /// Precedence, lowest to highest: Material defaults, then the app-wide
  /// `ThemeData.extension<ResizableSplitterThemeOverrides>()`, then a local
  /// [ResizableSplitterTheme]. The local theme is more specific, so it
  /// overrides the global extension (constructor parameters, resolved by the
  /// widget, sit above all of these).
  static ResizableSplitterThemeData of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedSplitterTheme>();
    final overridesExt = Theme.of(
      context,
    ).extension<ResizableSplitterThemeOverrides>();
    final base = _default.mergeOverrides(overridesExt);
    final local = inherited?.theme.data;
    return local == null ? base : base.mergeTheme(local);
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedSplitterTheme(theme: this, child: child);
  }
}

class _InheritedSplitterTheme extends InheritedWidget {
  /// Creates an inherited widget that exposes [ResizableSplitterThemeData].
  const _InheritedSplitterTheme({required this.theme, required super.child});

  /// The theme wrapper that owns the exposed data.
  final ResizableSplitterTheme theme;

  /// Rebuild descendants when the underlying theme data changes.
  @override
  bool updateShouldNotify(_InheritedSplitterTheme oldWidget) =>
      theme.data != oldWidget.theme.data;
}

/// Theme extension enabling app-wide overrides without wrapping widgets.
class ResizableSplitterThemeOverrides
    extends ThemeExtension<ResizableSplitterThemeOverrides> {
  /// Creates a theme extension with optional overrides.
  const ResizableSplitterThemeOverrides({
    this.dividerThickness,
    this.dividerColor,
    this.dividerHoverColor,
    this.dividerActiveColor,
    this.blockerColor,
    this.handleHitSlop,
    this.overlayEnabled,
    this.enableKeyboard,
    this.enableHaptics,
    this.keyboardStep,
    this.pageStep,
    this.unboundedBehavior,
    this.fallbackMainAxisExtent,
    this.antiAliasingWorkaround,
  });

  /// Divider thickness override.
  final double? dividerThickness;

  /// Idle divider color override.
  final Color? dividerColor;

  /// Hover divider color override.
  final Color? dividerHoverColor;

  /// Active divider color override.
  final Color? dividerActiveColor;

  /// Drag overlay tint override.
  final Color? blockerColor;

  /// Handle hit test padding override.
  final double? handleHitSlop;

  /// Drag overlay toggle override.
  final bool? overlayEnabled;

  /// Keyboard enablement override.
  final bool? enableKeyboard;

  /// Haptic feedback enablement override.
  final bool? enableHaptics;

  /// Arrow-key step override.
  final double? keyboardStep;

  /// Page-key step override.
  final double? pageStep;

  /// Unbounded constraints behavior override.
  final UnboundedBehavior? unboundedBehavior;

  /// LimitedBox fallback extent override.
  final double? fallbackMainAxisExtent;

  /// Anti-alias workaround override.
  final bool? antiAliasingWorkaround;

  /// Returns a copy of this extension with the provided values replaced.
  @override
  ResizableSplitterThemeOverrides copyWith({
    double? dividerThickness,
    Color? dividerColor,
    Color? dividerHoverColor,
    Color? dividerActiveColor,
    Color? blockerColor,
    double? handleHitSlop,
    bool? overlayEnabled,
    bool? enableKeyboard,
    bool? enableHaptics,
    double? keyboardStep,
    double? pageStep,
    UnboundedBehavior? unboundedBehavior,
    double? fallbackMainAxisExtent,
    bool? antiAliasingWorkaround,
  }) {
    return ResizableSplitterThemeOverrides(
      dividerThickness: dividerThickness ?? this.dividerThickness,
      dividerColor: dividerColor ?? this.dividerColor,
      dividerHoverColor: dividerHoverColor ?? this.dividerHoverColor,
      dividerActiveColor: dividerActiveColor ?? this.dividerActiveColor,
      blockerColor: blockerColor ?? this.blockerColor,
      handleHitSlop: handleHitSlop ?? this.handleHitSlop,
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

  /// Linearly interpolates between two extensions.
  @override
  ResizableSplitterThemeOverrides lerp(
    covariant ResizableSplitterThemeOverrides? other,
    double t,
  ) {
    if (other == null) return this;
    return ResizableSplitterThemeOverrides(
      dividerThickness: lerpDouble(dividerThickness, other.dividerThickness, t),
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t),
      dividerHoverColor: Color.lerp(
        dividerHoverColor,
        other.dividerHoverColor,
        t,
      ),
      dividerActiveColor: Color.lerp(
        dividerActiveColor,
        other.dividerActiveColor,
        t,
      ),
      blockerColor: Color.lerp(blockerColor, other.blockerColor, t),
      handleHitSlop: lerpDouble(handleHitSlop, other.handleHitSlop, t),
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

  /// Converts this extension into a theme data object using [base] as fallback.
  ResizableSplitterThemeData asThemeData(ResizableSplitterThemeData base) =>
      base.mergeOverrides(this);
}
