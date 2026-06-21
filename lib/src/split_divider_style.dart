import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Snapshot of the divider handle's interaction state, passed to a custom
/// [SplitterDividerStyle.builder].
@immutable
class SplitterHandleDetails {
  /// Captures the current handle interaction state for custom builders.
  const SplitterHandleDetails({
    required this.isDragging,
    required this.isHovering,
    required this.axis,
    required this.thickness,
  });

  /// Whether the handle is currently being dragged by the user.
  final bool isDragging;

  /// Whether the pointer is hovering over the handle.
  final bool isHovering;

  /// The axis (horizontal/vertical) of the associated splitter.
  final Axis axis;

  /// Thickness of the handle in logical pixels.
  final double thickness;
}

/// Visual and grab configuration for the splitter's divider handle.
///
/// Every field is nullable, and an unset field genuinely means "unset": it
/// falls through to the ambient theme and then to a built-in default. That is
/// what lets a local style override a single property (say [color]) without
/// clobbering the [thickness] an app-wide theme supplied.
///
/// [color] is a [WidgetStateProperty], resolved against the active
/// [WidgetState]s - `hovered` while the pointer is over the bar and `dragged`
/// during a drag. Returning null for a state (or leaving [color] null) falls
/// back to a tint derived from the ambient [ColorScheme].
@immutable
class SplitterDividerStyle {
  /// Creates a divider style. Unset fields fall back to the theme and defaults.
  const SplitterDividerStyle({
    this.thickness,
    this.color,
    this.hitSlop,
    this.builder,
  }) : assert(
         thickness == null || thickness >= 0,
         'thickness must be non-negative',
       ),
       assert(hitSlop == null || hitSlop >= 0, 'hitSlop must be non-negative');

  /// Visible thickness of the divider along the main axis, in logical pixels.
  /// Defaults to 6.
  final double? thickness;

  /// State-dependent divider color, resolved against the active [WidgetState]s
  /// (`hovered`, `dragged`). A null result - or a null property - falls back to
  /// a tint derived from the ambient [ColorScheme].
  final WidgetStateProperty<Color?>? color;

  /// Invisible padding on either side of the divider that enlarges the grab
  /// target without widening the visible bar. Defaults to 0.
  final double? hitSlop;

  /// Replaces the default inner grip with custom content.
  final Widget Function(BuildContext context, SplitterHandleDetails details)?
  builder;

  /// Returns a copy with the given fields replaced.
  SplitterDividerStyle copyWith({
    double? thickness,
    WidgetStateProperty<Color?>? color,
    double? hitSlop,
    Widget Function(BuildContext context, SplitterHandleDetails details)?
    builder,
  }) {
    return SplitterDividerStyle(
      thickness: thickness ?? this.thickness,
      color: color ?? this.color,
      hitSlop: hitSlop ?? this.hitSlop,
      builder: builder ?? this.builder,
    );
  }

  /// Overlays [other] on top of this style, field by field. A non-null field in
  /// [other] wins; the rest fall through to this style. Returns this style
  /// unchanged when [other] is null.
  SplitterDividerStyle merge(SplitterDividerStyle? other) {
    if (other == null) return this;
    return SplitterDividerStyle(
      thickness: other.thickness ?? thickness,
      color: other.color ?? color,
      hitSlop: other.hitSlop ?? hitSlop,
      builder: other.builder ?? builder,
    );
  }

  /// Linearly interpolates between two divider styles, field by field.
  static SplitterDividerStyle? lerp(
    SplitterDividerStyle? a,
    SplitterDividerStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null) return b;
    if (b == null) return a;
    return SplitterDividerStyle(
      thickness: lerpDouble(a.thickness, b.thickness, t),
      color: WidgetStateProperty.lerp<Color?>(a.color, b.color, t, Color.lerp),
      hitSlop: lerpDouble(a.hitSlop, b.hitSlop, t),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitterDividerStyle &&
          other.thickness == thickness &&
          other.color == color &&
          other.hitSlop == hitSlop &&
          other.builder == builder;

  @override
  int get hashCode => Object.hash(thickness, color, hitSlop, builder);

  @override
  String toString() =>
      'SplitterDividerStyle(thickness: $thickness, color: $color, '
      'hitSlop: $hitSlop, builder: ${builder == null ? null : 'set'})';
}
