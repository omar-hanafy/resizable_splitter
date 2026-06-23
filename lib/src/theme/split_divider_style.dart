import 'dart:ui' show lerpDouble;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// Sentinel for [SplitterDividerStyle.copyWith] so a nullable field can be
/// explicitly cleared (set back to null) rather than only overwritten.
const Object _noUpdate = Object();

/// Snapshot of the divider handle's interaction state, passed to a custom
/// [SplitterDividerStyle.builder].
/// {@category Theming}
@immutable
class SplitterHandleDetails {
  /// Captures the current handle interaction state for custom builders.
  const SplitterHandleDetails({
    required this.isDragging,
    required this.isHovering,
    required this.isFocused,
    required this.axis,
    required this.thickness,
  });

  /// Whether the handle is currently being dragged by the user.
  final bool isDragging;

  /// Whether the pointer is hovering over the handle.
  final bool isHovering;

  /// Whether the handle currently holds keyboard focus and should show a focus
  /// affordance. A custom [SplitterDividerStyle.builder] owns its own focus
  /// visual (the default ring is suppressed when a builder is supplied).
  final bool isFocused;

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
/// {@category Theming}
@immutable
class SplitterDividerStyle with EquatableMixin {
  /// Creates a divider style. Unset fields fall back to the theme and defaults.
  const SplitterDividerStyle({
    this.thickness,
    this.color,
    this.interactiveExtent,
    this.builder,
  }) : assert(
         thickness == null || thickness >= 0,
         'thickness must be non-negative',
       ),
       assert(
         interactiveExtent == null || interactiveExtent >= 0,
         'interactiveExtent must be non-negative',
       );

  /// Visible thickness of the divider along the main axis, in logical pixels.
  /// Defaults to 6.
  final double? thickness;

  /// State-dependent divider color, resolved against the active [WidgetState]s
  /// (`hovered`, `focused`, `dragged`). A null result - or a null property -
  /// falls back to a tint derived from the ambient [ColorScheme].
  final WidgetStateProperty<Color?>? color;

  /// Size of the interactive grab target across the divider's thin dimension,
  /// in logical pixels. Defaults to 48 (the Material minimum touch target).
  ///
  /// The target is centered on the visible bar and extends past it without
  /// reserving layout: any extent beyond [thickness] overlaps the panel edges
  /// from on top, so widening it never changes the panes' sizes. When it is
  /// smaller than [thickness] the visible bar is the whole target. A
  /// non-resizable divider ignores this and uses only [thickness] so it cannot
  /// overlap the panes and steal their hits.
  final double? interactiveExtent;

  /// Replaces the default inner grip with custom content.
  final Widget Function(BuildContext context, SplitterHandleDetails details)?
  builder;

  /// Returns a copy with the given fields replaced. Every parameter accepts an
  /// explicit `null` to clear that field (fall back to the theme/default);
  /// omitting a parameter keeps the current value.
  SplitterDividerStyle copyWith({
    Object? thickness = _noUpdate,
    Object? color = _noUpdate,
    Object? interactiveExtent = _noUpdate,
    Object? builder = _noUpdate,
  }) {
    return SplitterDividerStyle(
      thickness: identical(thickness, _noUpdate)
          ? this.thickness
          : (thickness as num?)?.toDouble(),
      color: identical(color, _noUpdate)
          ? this.color
          : color as WidgetStateProperty<Color?>?,
      interactiveExtent: identical(interactiveExtent, _noUpdate)
          ? this.interactiveExtent
          : (interactiveExtent as num?)?.toDouble(),
      builder: identical(builder, _noUpdate)
          ? this.builder
          : builder as Widget Function(BuildContext, SplitterHandleDetails)?,
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
      interactiveExtent: other.interactiveExtent ?? interactiveExtent,
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
      interactiveExtent: lerpDouble(
        a.interactiveExtent,
        b.interactiveExtent,
        t,
      ),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  List<Object?> get props => [thickness, color, interactiveExtent, builder];

  @override
  String toString() =>
      'SplitterDividerStyle(thickness: $thickness, color: $color, '
      'interactiveExtent: $interactiveExtent, '
      'builder: ${builder == null ? null : 'set'})';
}
