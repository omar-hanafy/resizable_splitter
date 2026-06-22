// We intentionally expose imperative helpers instead of setters for ergonomics.
// ignore_for_file: use_setters_to_change_properties
// A robust, high-performance split view that plays nicely with platform views.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resizable_splitter/src/resizable_splitter_theme.dart';
import 'package:resizable_splitter/src/split_animation.dart';
import 'package:resizable_splitter/src/split_divider_style.dart';
import 'package:resizable_splitter/src/split_layout.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_semantics_labels.dart';
import 'package:resizable_splitter/src/split_snap_behavior.dart';
import 'package:resizable_splitter/src/split_solver.dart';
import 'package:resizable_splitter/src/split_state.dart';
import 'package:resizable_splitter/src/split_view_value.dart';

/// Axis helpers to eliminate H/V duplication.
extension _AxisHelpers on Axis {
  bool get isH => this == Axis.horizontal;

  double size(Size s) => isH ? s.width : s.height;

  SystemMouseCursor get cursor =>
      isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;
}

/// Why a drag ended, so the handle settles only on a real release and never
/// treats a cancel, a mid-drag reconfiguration, or a disposal as a successful
/// completion.
enum _DragEndReason {
  /// The pointer lifted normally - a gesture end, or a pointer-up a platform
  /// view swallowed that the global router still saw. Settles, snaps, and fires
  /// onChangeEnd.
  completed,

  /// A system cancel (gesture/pointer cancel). No commit, snap, or end event.
  canceled,

  /// A mid-drag reconfiguration (controller, axis, or mode swap, or resizing
  /// turned off). No commit, snap, or end event. Disposal tears down the same
  /// way, but directly (it cannot call setState), so it needs no reason here.
  interrupted,
}

/// A controller for a [ResizableSplitter]'s position.
///
/// Holds the requested [SplitterPosition] (a fraction or a pixel pin) and
/// exposes simple APIs to update or animate it; read [effectiveFraction] for
/// the on-screen ratio after constraints are applied.
/// A global pointer router prevents "stuck drags" when platform views steal
/// pointer events. The router attaches only when a [WidgetsBinding] is
/// available, so controllers created in pure Dart tests or before `runApp`
/// stay functional - the enhanced drag cleanup simply activates once Flutter is
/// initialized.
class SplitterController extends ValueNotifier<SplitterState> {
  /// Creates a splitter controller at [initialPosition] (default: centered).
  ///
  /// The controller stores the requested [SplitterPosition]; the splitter
  /// resolves it against the live layout every frame. A pixel request
  /// ([SplitterPosition.startPixels] / [SplitterPosition.endPixels]) therefore
  /// keeps its pixel size as the container resizes, while a drag or keyboard
  /// adjustment writes a fractional position (the pin releases on interaction).
  SplitterController({
    SplitterPosition initialPosition = const SplitterPosition.fraction(0.5),
  }) : super(SplitterState(position: initialPosition));

  static final _globalRouter = _GlobalPointerRouter();

  static const String _multiAttachErrorMessage =
      'SplitterController is already attached to another ResizableSplitter.\n'
      'A controller must not be shared across multiple ResizableSplitter instances simultaneously.';

  /// Emits `true` while the user is dragging the handle.
  ValueListenable<bool> get isDraggingListenable => _isDragging;

  /// A convenience getter for [_isDragging] as a boolean.
  bool get isDragging => _isDragging.value;
  final _isDragging = ValueNotifier<bool>(false);

  // The attached view drives vsync animation; null while detached.
  _SplitterAnimator? _animator;
  bool _isAnimationTick = false;
  Object? _owner;

  /// Exposes the widget currently owning this controller in debug/test builds.
  @visibleForTesting
  Object? get debugOwner => _owner;

  void _attach(Object owner) {
    // Enforced in release too: a shared controller silently corrupts drag
    // state (isDragging, drag callbacks, the active pointer), so fail loudly
    // rather than limp along when asserts are stripped.
    if (_owner != null && !identical(_owner, owner)) {
      throw FlutterError(_multiAttachErrorMessage);
    }
    _owner = owner;
  }

  void _detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      // No view is producing geometry anymore, so the published layout no
      // longer reflects anything on screen. Clear it (and notify) so [layout]
      // reads null while detached, as its documentation promises.
      if (_layout.prime(null)) _layout.flush();
    }
  }

  /// Whether this controller is currently attached to a [ResizableSplitter].
  ///
  /// While false, [layout] is null and [effectiveFraction] derives from the
  /// request rather than any on-screen geometry.
  bool get isAttached => _owner != null;

  @override
  void dispose() {
    _globalRouter.unregister(this);
    _animator?.cancel();
    _isDragging.dispose();
    _layout.dispose();
    super.dispose();
  }

  /// The resolved, on-screen layout the attached splitter last published, or
  /// null before the first layout (or while detached from any view).
  ///
  /// Unlike [value] (the request), this reflects what is actually drawn, and it
  /// notifies via [layoutListenable] whenever the geometry changes - including
  /// when a pixel-pinned pane's effective fraction shifts as the container
  /// resizes, which leaves the request untouched. Reading the request through
  /// [value] alone would miss that class of change.
  SplitterLayout? get layout => _layout.value;

  /// Notifies whenever the resolved [layout] changes. This is a separate
  /// observable from the request notifier ([value]); listen here to track the
  /// on-screen geometry rather than the intent.
  ValueListenable<SplitterLayout?> get layoutListenable => _layout;
  final _layout = _SplitterLayoutNotifier();

  // True once the request changed but the splitter has not yet re-solved, so the
  // published layout is stale and [effectiveFraction] derives from the request
  // instead. Cleared on the next solve.
  bool _layoutStale = false;

  /// The on-screen start fraction, in `[0, 1]`. Once laid out this is the
  /// resolved [layout]'s fraction; before the first layout, while detached, or
  /// in the brief window after a request change before the next solve, it
  /// derives from the request - resolved against the last known extent, so a
  /// pixel pin still estimates sensibly (0 before any layout). For change
  /// notifications, listen to [layoutListenable].
  double get effectiveFraction {
    final layout = _layout.value;
    if (layout != null && !_layoutStale) return layout.effectiveFraction;
    return value.position.resolveFraction(layout?.availableExtent ?? 0);
  }

  // Updates the resolved layout synchronously (so [layout] and
  // [effectiveFraction] are fresh within the frame the splitter solved in) and
  // returns whether it changed, so the splitter can defer the listener
  // notification out of the build phase.
  bool _primeLayout(SplitterLayout layout) {
    _layoutStale = false;
    return _layout.prime(layout);
  }

  // Fires the deferred layout notification; called post-frame by the splitter.
  void _flushLayout() => _layout.flush();

  /// The requested position (a fraction or pixel pin); shorthand for
  /// `value.position`.
  SplitterPosition get position => value.position;

  /// Sets the requested [SplitterState]. The solver sanitizes the position at
  /// layout, so a malformed request (for example a non-finite fraction) can
  /// never corrupt the layout. A write that *changes* the state and is not an
  /// animation tick (a drag, key press, reset, collapse, or direct assignment)
  /// takes over from a running animation.
  @override
  set value(SplitterState newValue) {
    // No-op writes change nothing observable, so they neither notify nor cancel
    // a running animation. Crucially, nothing mutates before this equality gate,
    // so a collapse (which lives inside the value) can never change without a
    // matching notification - the historic collapse/equal-write desync is gone.
    if (newValue == value) return;
    if (!_isAnimationTick) _animator?.cancel();
    // Mark the published layout stale BEFORE notifying: the request changed, so
    // it no longer reflects what is on screen. Doing this first means a listener
    // reacting to this write reads an [effectiveFraction] consistent with the
    // new request, not the prior layout's stale value (until the next solve).
    _layoutStale = true;
    super.value = newValue;
  }

  /// Requests [position] as a fresh intent: clears any collapse and supersedes a
  /// running animation. The on-screen result is still clamped by the solver.
  void jumpTo(SplitterPosition position) =>
      value = SplitterState(position: position);

  /// Updates to a fractional position, with an optional threshold to prevent
  /// chatty updates. The threshold is compared against [effectiveFraction].
  void updateRatio(double newRatio, {double threshold = 0.002}) {
    final clamped = newRatio.clamp(0.0, 1.0).toDouble();
    if ((clamped - effectiveFraction).abs() > threshold) {
      jumpTo(SplitterPosition.fraction(clamped));
    }
  }

  /// Resets the splitter to a fractional position, defaulting to center.
  void reset([double to = 0.5]) {
    assert(to >= 0.0 && to <= 1.0, 'to must be between 0.0 and 1.0');
    jumpTo(SplitterPosition.fraction(to));
  }

  /// Which pane, if any, is currently collapsed; null when neither is.
  SplitterPane? get collapsedPane => value.collapsedPane;

  /// Whether either pane is currently collapsed.
  bool get isCollapsed => value.isCollapsed;

  /// Collapses [pane] to its [SplitterPaneConstraints.collapsedExtent],
  /// bypassing that pane's minimum. The position in [value] is left untouched, so
  /// [expand] restores the prior position. Collapsing the already-collapsed pane
  /// is a no-op; collapsing the other pane just moves the collapse across.
  void collapse(SplitterPane pane) => value = value.collapse(pane);

  /// Expands a collapsed pane, restoring the position held before it collapsed
  /// (the untouched position). A no-op when neither pane is collapsed.
  void expand() => value = value.expand();

  /// Collapses [pane] if it is not already collapsed, otherwise expands.
  void toggleCollapse(SplitterPane pane) =>
      collapsedPane == pane ? expand() : collapse(pane);

  /// Animates the split ratio to [target], resolving with a
  /// [SplitterAnimationStatus] that reports how the run ended.
  ///
  /// Driven by the attached view's vsync, so it honors the platform refresh
  /// rate and `MediaQuery.disableAnimations`. A drag, key press, reset, or
  /// direct value write cancels a run in progress (resolving [canceled]); a
  /// disposal or controller swap ends it (resolving [detached]). With no view
  /// attached, disabled animations, or a target already current, the value is
  /// set immediately and the run resolves [completed].
  Future<SplitterAnimationStatus> animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeOutCubic,
  }) {
    final goal = target.clamp(0.0, 1.0).toDouble();
    if ((goal - effectiveFraction).abs() < 1e-7) {
      jumpTo(SplitterPosition.fraction(goal));
      return Future<SplitterAnimationStatus>.value(
        SplitterAnimationStatus.completed,
      );
    }
    final animator = _animator;
    if (animator == null) {
      jumpTo(SplitterPosition.fraction(goal));
      return Future<SplitterAnimationStatus>.value(
        SplitterAnimationStatus.completed,
      );
    }
    return animator.animateTo(goal, duration, curve);
  }

  void _attachAnimator(_SplitterAnimator animator) => _animator = animator;

  void _detachAnimator(_SplitterAnimator animator) {
    if (identical(_animator, animator)) _animator = null;
  }

  void _cancelAnimation() => _animator?.cancel();

  // Writes an animated position, preserving any collapse and without cancelling
  // the run (an animation tick is not a fresh user intent superseding it).
  void _setAnimatedPosition(SplitterPosition position) {
    _isAnimationTick = true;
    value = value.copyWith(position: position);
    _isAnimationTick = false;
  }

  // Internal methods for the global router. The reason distinguishes a normal
  // release (the route saw a pointer-up a platform view swallowed) from a
  // cancel, so the handle settles only on a real completion.
  void _endDragFromRouter(_DragEndReason reason) {
    final cb = _dragCallback;
    _dragCallback = null;
    cb?.call(reason);
  }

  void _setDragCallback(void Function(_DragEndReason)? cb) => _dragCallback = cb;
  void Function(_DragEndReason)? _dragCallback;

  void _setDragging(bool dragging) => _isDragging.value = dragging;

  /// Resets the global pointer router. For testing only.
  @visibleForTesting
  static void resetGlobalRouter() => _globalRouter.dispose();
}

/// The resolved-layout observable behind [SplitterController.layoutListenable].
///
/// Its value updates synchronously (via [prime], during the splitter's build,
/// so read-outs are fresh in the same frame) while the listener notification is
/// deferred to [flush] (post-frame), so publishing the layout can never trigger
/// a listener's `setState` during build.
class _SplitterLayoutNotifier extends ChangeNotifier
    implements ValueListenable<SplitterLayout?> {
  SplitterLayout? _value;
  bool _dirty = false;

  @override
  SplitterLayout? get value => _value;

  /// Sets [next] immediately; returns true if it changed (so the caller knows a
  /// [flush] should be scheduled).
  bool prime(SplitterLayout? next) {
    if (_value == next) return false;
    _value = next;
    _dirty = true;
    return true;
  }

  /// Notifies listeners once if the value changed since the last flush.
  void flush() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }
}

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

/// Singleton global pointer router providing a stuck-drag backup: if a platform
/// view swallows the pointer-up that would normally end a drag, this global
/// route still sees it and ends the matching session. Active drags are keyed by
/// their real pointer id, so several splitters can be dragged at once and each
/// is cleaned up independently (the old single-slot design tracked only one).
class _GlobalPointerRouter {
  factory _GlobalPointerRouter() => _instance;

  _GlobalPointerRouter._() {
    _initialize();
  }

  static final _instance = _GlobalPointerRouter._();

  // Active drags keyed by their real pointer id.
  final Map<int, SplitterController> _activeByPointer =
      <int, SplitterController>{};
  bool _initialized = false;

  void _initialize() {
    if (_initialized) return;
    final binding = _maybeBinding();
    if (binding == null) return;
    binding.pointerRouter.addGlobalRoute(_handleGlobal);
    _initialized = true;
  }

  /// Removes every active drag owned by [c] (used when its controller is
  /// disposed).
  void unregister(SplitterController c) {
    _activeByPointer.removeWhere((_, controller) => identical(controller, c));
  }

  /// Registers [c] as dragging under [pointerId]. A controller drives one drag
  /// at a time, so any stale pointer it held is dropped first. A real
  /// (non-negative) pointer id is required for the backup route to match a later
  /// up; an unknown pointer (-1) simply gets no backup.
  void beginDrag(SplitterController c, int pointerId) {
    _initialize();
    _activeByPointer.removeWhere((_, controller) => identical(controller, c));
    if (pointerId >= 0) _activeByPointer[pointerId] = c;
  }

  /// Ends every active drag owned by [c] (its drag finished normally).
  void endDrag(SplitterController c) {
    _activeByPointer.removeWhere((_, controller) => identical(controller, c));
  }

  void _handleGlobal(PointerEvent event) {
    if (event is PointerUpEvent) {
      _activeByPointer
          .remove(event.pointer)
          ?._endDragFromRouter(_DragEndReason.completed);
    } else if (event is PointerCancelEvent) {
      _activeByPointer
          .remove(event.pointer)
          ?._endDragFromRouter(_DragEndReason.canceled);
    }
  }

  void dispose() {
    _activeByPointer.clear();
    if (!_initialized) return;
    final binding = _maybeBinding();
    if (binding != null) {
      binding.pointerRouter.removeGlobalRoute(_handleGlobal);
    }
    _initialized = false;
  }

  WidgetsBinding? _maybeBinding() {
    try {
      return WidgetsBinding.instance;
    } catch (error) {
      if (error is FlutterError) {
        return null;
      }
      rethrow;
    }
  }
}

/// A high-performance resizable splitter widget with robust pointer handling.
///
/// - Smooth dragging, keyboard navigation, and accessible semantics.
/// - Works with embedded platform views (e.g., WebViews) via an overlay shield
///   to stop pointer events from being stolen.
/// - Extensive customization via [divider] ([SplitterDividerStyle]): a
///   state-dependent color, thickness, grab slop, and a custom grip builder.
///
/// If the incoming constraints along [axis] are unbounded or zero, the
/// splitter cannot resize, so it shows the two panels without the divider:
/// [Expanded] when the extent is a finite zero, or at their intrinsic size
/// when truly unbounded (flexing into an unbounded axis would throw). Opt into
/// [UnboundedBehavior.limitedBox] (via [ResizableSplitterTheme] or the
/// constructor) to give the handle a finite sandbox while preserving side
/// panels.
///
/// Theme precedence: explicit constructor values override
/// [ResizableSplitterTheme], which in turn overrides
/// `Theme.of(context).extension<ResizableSplitterThemeData>()`. Every theme
/// field is nullable, so a partial override only replaces the fields it sets.
/// When nothing is provided, colors fall back to the ambient [ThemeData]
/// (via [ColorScheme]) and numeric values fall back to the defaults documented
/// on each parameter.
class ResizableSplitter extends StatefulWidget {
  /// Builds a resizable splitter with the provided panels and configuration.
  const ResizableSplitter({
    required this.start,
    required this.end,
    super.key,
    this.controller,
    this.axis = Axis.horizontal,
    this.initialPosition = const SplitterPosition.fraction(0.5),
    this.startConstraints = const SplitterPaneConstraints(minExtent: 100),
    this.endConstraints = const SplitterPaneConstraints(minExtent: 100),
    this.minStartFraction = 0.0,
    this.maxStartFraction = 1.0,
    this.divider,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.enableKeyboard,
    this.enableHaptics,
    this.keyboardStep,
    this.pageStep,
    this.semanticsLabel,
    this.semantics,
    this.blockerColor,
    this.dragBarrierBuilder,
    this.overlayEnabled,
    this.snap,
    this.holdScrollWhileDragging = false,
    this.deferredResize = false,
    this.doubleTapResetTo,
    this.resizable = true,
    this.onHandleTap,
    this.onHandleDoubleTap,
    this.constraintPolicy = SplitterConstraintPolicy.favorStart,
    this.surplusPolicy = SplitterSurplusPolicy.leaveGap,
    this.unboundedBehavior,
    this.fallbackMainAxisExtent,
    this.antiAliasingWorkaround,
    this.restorationId,
  }) : assert(
         minStartFraction >= 0.0 && minStartFraction <= 1.0,
         'minStartFraction must be between 0.0 and 1.0',
       ),
       assert(
         maxStartFraction >= 0.0 && maxStartFraction <= 1.0,
         'maxStartFraction must be between 0.0 and 1.0',
       ),
       assert(
         minStartFraction <= maxStartFraction,
         'minStartFraction must be <= maxStartFraction',
       ),
       assert(
         keyboardStep == null || keyboardStep >= 0,
         'keyboardStep must be non-negative',
       ),
       assert(
         pageStep == null || pageStep >= 0,
         'pageStep must be non-negative',
       ),
       assert(
         doubleTapResetTo == null ||
             (doubleTapResetTo >= 0.0 && doubleTapResetTo <= 1.0),
         'doubleTapResetTo must be between 0.0 and 1.0',
       ),
       assert(
         fallbackMainAxisExtent == null || fallbackMainAxisExtent > 0,
         'fallbackMainAxisExtent must be greater than zero',
       );
  static const double _defaultDividerThickness = 6;
  static const double _defaultKeyboardStep = 0.01;
  static const double _defaultPageStep = 0.1;
  static const double _defaultHandleHitSlop = 0;
  static const double _defaultFallbackMainAxisExtent = 500;

  /// The widget to display in the start position (left/top).
  final Widget start;

  /// The widget to display in the end position (right/bottom).
  final Widget end;

  /// Optional controller for programmatic control and persistence.
  final SplitterController? controller;

  /// The axis along which to split (horizontal or vertical).
  final Axis axis;

  /// Initial split position if no controller is provided. Use
  /// [SplitterPosition.startPixels] / [SplitterPosition.endPixels] to pin a pane
  /// to a pixel width that survives container resizes, or
  /// [SplitterPosition.fraction] for a ratio. Defaults to a centered fraction.
  final SplitterPosition initialPosition;

  /// Pixel sizing limits for the start (left/top) pane. Defaults to a 100px
  /// minimum. Set [SplitterPaneConstraints.maxExtent] to cap the pane, or
  /// [SplitterPaneConstraints.collapsible] to allow collapsing.
  final SplitterPaneConstraints startConstraints;

  /// Pixel sizing limits for the end (right/bottom) pane. Defaults to a 100px
  /// minimum.
  final SplitterPaneConstraints endConstraints;

  /// Lowest fraction of the available space the start pane may take (0.0-1.0).
  ///
  /// Layout still enforces the pixel limits in [startConstraints] /
  /// [endConstraints], so under extreme constraints the visible split may differ
  /// from this cap while it is honored where feasible.
  final double minStartFraction;

  /// Highest fraction of the available space the start pane may take (0.0-1.0).
  final double maxStartFraction;

  /// Divider appearance and grab configuration: thickness, a state-dependent
  /// color, the grab [SplitterDividerStyle.hitSlop], and a custom grip
  /// [SplitterDividerStyle.builder]. Unset fields fall back to
  /// [ResizableSplitterTheme], then to the built-in defaults.
  final SplitterDividerStyle? divider;

  /// Called as the divider moves through an interaction or a collapse, with both
  /// the request and the resolved layout plus the [SplitterChangeSource].
  ///
  /// Fires for a pointer drag, keyboard adjustment, assistive (semantics)
  /// adjustment, a snap settling a release, the built-in double-tap reset, and
  /// `controller.collapse` / `expand`. It deliberately does NOT fire for direct
  /// programmatic writes ([SplitterController.jumpTo], `updateRatio`, `reset`,
  /// `animateTo`) or state restoration - those are observed by listening to the
  /// `controller` (request changes) and `controller.layoutListenable` (resolved
  /// geometry), which avoids feedback loops. This mirrors how `Slider.onChanged`
  /// reports interaction rather than every value write.
  final ValueChanged<SplitterChangeDetails>? onChanged;

  /// Called when a drag gesture starts, with the position at that moment - the
  /// real request, which may be a pixel pin.
  final ValueChanged<SplitterChangeDetails>? onChangeStart;

  /// Called when a drag gesture ends, with the settled position. The source is
  /// [SplitterChangeSource.snap] when a snap point claimed the release.
  final ValueChanged<SplitterChangeDetails>? onChangeEnd;

  /// Whether to enable keyboard navigation with arrow keys. Defaults to true.
  final bool? enableKeyboard;

  /// Whether haptic feedback fires on drag start and keyboard adjustments.
  ///
  /// Defaults to true. On platforms without a haptic engine (web, most
  /// desktops) the calls are silent no-ops regardless.
  final bool? enableHaptics;

  /// Step applied with Arrow keys (e.g., 0.01 = 1%). Defaults to 0.01.
  final double? keyboardStep;

  /// Step applied with PageUp/PageDown keys (e.g., 0.1 = 10%). Defaults to 0.1.
  final double? pageStep;

  /// Accessibility label for the divider. Overrides the label resolved from
  /// [semantics] (or the ambient theme) when set, leaving the value formatting
  /// intact - a quick way to relabel a single splitter without supplying a full
  /// [SplitterSemanticsLabels].
  final String? semanticsLabel;

  /// Localizable semantics strings and value formatting. Unset fields fall back
  /// to [ResizableSplitterTheme], then to the built-in English defaults. Set it
  /// app-wide via the theme to localize every splitter at once.
  final SplitterSemanticsLabels? semantics;

  /// The blocked color when dragged. Ignored if [dragBarrierBuilder] is set.
  final Color? blockerColor;

  /// Builds the visual of the drag barrier - the overlay that shields embedded
  /// platform views from stealing pointer events while dragging. The framework
  /// always keeps the opaque hit shield; this only replaces what it looks like
  /// (the default is a [blockerColor] fill). Only used when the overlay is
  /// enabled.
  final Widget Function(BuildContext context)? dragBarrierBuilder;

  /// Whether the protective overlay is used while dragging. Defaults to true.
  final bool? overlayEnabled;

  /// Optional snap points; a drag settles onto the nearest within tolerance.
  final SplitterSnapBehavior? snap;

  /// Whether to temporarily hold the nearest Scrollable's position while dragging.
  final bool holdScrollWhileDragging;

  /// Defers the resize until the drag is released. While dragging, the panes
  /// keep their committed size and a lightweight preview line tracks the
  /// pointer; on release the panes settle to the final position once. Useful
  /// when the panes contain expensive subtrees. Defaults to false (live resize).
  final bool deferredResize;

  /// Optional ratio to jump to on double-tap.
  final double? doubleTapResetTo;

  /// Whether the divider responds to drag gestures.
  final bool resizable;

  /// Called when the divider is tapped.
  final VoidCallback? onHandleTap;

  /// Called when the divider is double-tapped.
  final VoidCallback? onHandleDoubleTap;

  /// Policy applied when both panes cannot meet their minimums at once
  /// (a shortage).
  final SplitterConstraintPolicy constraintPolicy;

  /// Policy applied when both panes' maximums are too small to fill the space
  /// (a surplus). Defaults to [SplitterSurplusPolicy.leaveGap], which keeps
  /// [SplitterPaneConstraints.maxExtent] a true maximum (the leftover becomes a
  /// gap between the panes rather than overflowing one past its maximum).
  final SplitterSurplusPolicy surplusPolicy;

  /// Fallback layout behavior when constraints are unbounded along the main
  /// axis. Defaults to [UnboundedBehavior.flexExpand].
  final UnboundedBehavior? unboundedBehavior;

  /// Extent in pixels to use when [unboundedBehavior] is
  /// [UnboundedBehavior.limitedBox]. Defaults to 500.
  final double? fallbackMainAxisExtent;

  /// Floors the leading panel size to whole physical pixels to avoid anti-alias
  /// gaps. Defaults to false.
  final bool? antiAliasingWorkaround;

  /// Restoration id for persisting the divider position across app restarts.
  ///
  /// When non-null the splitter saves its position into the ambient
  /// [RestorationScope], so it is restored after the app is killed and
  /// relaunched (see [RestorationMixin]). Restoration works with the internal
  /// controller as well as an external one. Null disables restoration.
  final String? restorationId;

  @override
  State<ResizableSplitter> createState() => _ResizableSplitterState();
}

class _ResizableSplitterState extends State<ResizableSplitter>
    with SingleTickerProviderStateMixin, RestorationMixin
    implements _SplitterAnimator {
  late final FocusNode _focusNode;
  late final AnimationController _animationController;
  SplitterController? _internalController;
  SplitterController? _attachedController;

  // The collapse state last surfaced to onChanged, so a collapse/expand is
  // reported exactly once (not on every rebuild while it stays collapsed).
  SplitterPane? _reportedCollapsePane;

  // False until the first resolved layout seeds [_reportedCollapsePane] without
  // emitting. This stops a controller mounted already collapsed (or a freshly
  // swapped-in one) from firing a phantom collapse/restore for a state it never
  // transitioned into while attached here.
  bool _hasReportedInitialCollapse = false;

  // The preview fraction shown during a deferred drag (null when not
  // previewing). The panes stay at the committed position; only this line moves.
  double? _previewFraction;

  // Persists the divider position when widget.restorationId is set. The mixin
  // owns and disposes it; _restorationReady gates writes until it is registered.
  // Its default is the controller's *current* value, so a first run with no
  // saved state re-applies what is already there (never clobbering an external
  // controller); only a genuine restore overrides it.
  late final _RestorableSplitterPosition _restorablePosition =
      _RestorableSplitterPosition(
        () => (_attachedController ?? _effectiveController).value.position,
      );
  bool _restorationReady = false;

  // The in-flight animateTo run (null when idle). It owns the controller it
  // targets, so a controller swap or disposal can end it cleanly instead of
  // letting its ticks bleed onto a different controller or hang forever.
  _AnimationSession? _animSession;

  SplitterController get _effectiveController =>
      widget.controller ??
      (_internalController ??= SplitterController(
        initialPosition: widget.initialPosition,
      ));

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorablePosition, 'position');
    _restorationReady = true;
    // Re-apply the restored position, but only when it actually differs from the
    // controller's current request. The restorable defaults to the current
    // position, so with no saved state this would otherwise jumpTo an equal
    // position - and jumpTo clears collapse, which would silently expand a
    // controller mounted already collapsed. Skipping the equal write keeps it
    // collapsed (review A#6). (restoreState runs even without a restorationId.)
    final controller = _attachedController ?? _effectiveController;
    final restored = _restorablePosition.value;
    if (restored != controller.value.position) {
      controller.jumpTo(restored);
    }
  }

  // Updates the deferred-drag preview line (the panes stay put until release).
  void _setPreview(double? fraction) {
    if (!mounted || _previewFraction == fraction) return;
    setState(() => _previewFraction = fraction);
  }

  // Converts a global pointer position to the splitter's local main-axis
  // coordinate, so a drag stays correct under a Transform (scale/rotate). The
  // splitter's own box is stationary during a drag (unlike the moving handle),
  // which is why the conversion is anchored here rather than on the handle.
  double? _localMainAxisOf(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final local = box.globalToLocal(globalPosition);
    return widget.axis.isH ? local.dx : local.dy;
  }

  // Mirrors the live controller position into the restorable so it persists.
  void _handlePositionChanged() {
    if (!_restorationReady) return;
    final controller = _attachedController;
    if (controller != null) _restorablePosition.value = controller.value.position;
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ResizableSplitterHandle');
    _animationController = AnimationController(vsync: this)
      ..addListener(_onAnimationTick)
      ..addStatusListener(_onAnimationStatus);
    final controller = _effectiveController
      .._attach(this)
      .._attachAnimator(this)
      ..addListener(_handlePositionChanged);
    _attachedController = controller;
  }

  @override
  void didUpdateWidget(ResizableSplitter oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Dropping an external controller: seed the internal one with the last
    // shown position so the divider does not jump back to initialRatio.
    if (oldWidget.controller != null &&
        widget.controller == null &&
        _internalController == null) {
      _internalController = SplitterController(
        initialPosition:
            (_attachedController ?? oldWidget.controller!).value.position,
      );
    }

    final newController =
        widget.controller ??
        (_internalController ??= SplitterController(
          initialPosition: widget.initialPosition,
        ));

    if (!identical(_attachedController, newController)) {
      // End any in-flight animation on the outgoing controller; it must not
      // continue ticking onto the incoming one.
      _animationController.stop();
      _resolveSession(SplitterAnimationStatus.detached);
      _attachedController
        ?..removeListener(_handlePositionChanged)
        .._detachAnimator(this)
        .._detach(this);

      if (oldWidget.controller == null && widget.controller != null) {
        // Defer disposing the internal controller until after this frame: the
        // child handle's didUpdateWidget (which runs later in this build) tears
        // down any in-flight drag on it, and that must not touch a disposed
        // controller (review C#4).
        final disposing = _internalController;
        _internalController = null;
        if (disposing != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => disposing.dispose());
        }
      }

      newController
        .._attach(this)
        .._attachAnimator(this)
        ..addListener(_handlePositionChanged);
      _attachedController = newController;
      // Re-seed the incoming controller's collapse (without emitting) on its
      // first resolved layout, so a swap fires no phantom collapse/restore for
      // state that was never this controller's - and seeds from the *resolved*
      // collapse, not the request, so a non-collapsible pane is handled too.
      _hasReportedInitialCollapse = false;
    }
  }

  @override
  void dispose() {
    // Resolve a pending animateTo future so it can never hang past disposal.
    _resolveSession(SplitterAnimationStatus.detached);
    _animationController.dispose();
    _attachedController
      ?..removeListener(_handlePositionChanged)
      .._detachAnimator(this)
      .._detach(this);
    _focusNode.dispose();
    _internalController?.dispose();
    // RestorationMixin unregisters the property but does not dispose it; do it
    // here to avoid leaking the listener (review A#6).
    _restorablePosition.dispose();
    super.dispose();
  }

  @override
  Future<SplitterAnimationStatus> animateTo(
    double target,
    Duration duration,
    Curve curve,
  ) {
    _animationController.stop();
    // A new run supersedes any in-flight one.
    _resolveSession(SplitterAnimationStatus.canceled);

    final controller = _attachedController ?? _effectiveController;
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable || duration <= Duration.zero) {
      controller.jumpTo(SplitterPosition.fraction(target));
      return Future<SplitterAnimationStatus>.value(
        SplitterAnimationStatus.completed,
      );
    }
    final session = _AnimationSession(
      controller: controller,
      begin: controller.effectiveFraction,
      end: target,
      curve: curve,
    );
    _animSession = session;
    _animationController.duration = duration;
    _animationController.forward(from: 0);
    return session.future;
  }

  @override
  void cancel() {
    if (_animSession == null) return;
    _animationController.stop();
    _resolveSession(SplitterAnimationStatus.canceled);
  }

  // Ends the in-flight run (if any) with [status], resolving its future once.
  void _resolveSession(SplitterAnimationStatus status) {
    final session = _animSession;
    _animSession = null;
    session?.resolve(status);
  }

  void _onAnimationTick() {
    final session = _animSession;
    if (session == null) return;
    final t = session.curve.transform(_animationController.value);
    final value = session.begin + (session.end - session.begin) * t;
    session.controller._setAnimatedPosition(SplitterPosition.fraction(value));
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final session = _animSession;
    if (session == null) return;
    session.controller._setAnimatedPosition(
      SplitterPosition.fraction(session.end),
    );
    _animSession = null;
    session.resolve(SplitterAnimationStatus.completed);
  }

  // Primes the controller's resolved layout synchronously (so its read-outs are
  // fresh this frame) and schedules the listener notification after the frame,
  // so it never triggers a listener's setState during build. No-ops when the
  // layout is unchanged.
  void _publishLayout(SplitterController controller, SplitterLayout layout) {
    if (!controller._primeLayout(layout)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller._flushLayout();
    });
  }

  // Surfaces a collapse/expand transition to onChanged exactly once, tagged with
  // the matching source, after the frame settles. Called from _buildBounded with
  // the freshly solved geometry, so the reported extents match what is drawn.
  void _maybeReportCollapseChange(
    SplitterController controller,
    SplitterSolver solver,
    SplitterSolution solution,
  ) {
    // Use the resolved collapse (from the solution), not the request: a collapse
    // of a non-collapsible pane resolves to nothing and must not fire an event.
    final pane = solution.startCollapsed
        ? SplitterPane.start
        : solution.endCollapsed
        ? SplitterPane.end
        : null;
    // The first resolved layout seeds the baseline without emitting: a
    // controller mounted already collapsed has not transitioned while attached
    // here, so it must not fire a phantom collapse/restore.
    if (!_hasReportedInitialCollapse) {
      _hasReportedInitialCollapse = true;
      _reportedCollapsePane = pane;
      return;
    }
    if (pane == _reportedCollapsePane) return;
    final source = pane != null
        ? SplitterChangeSource.collapse
        : SplitterChangeSource.restore;
    _reportedCollapsePane = pane;
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    final details = SplitterChangeDetails(
      requestedPosition: controller.value.position,
      effectiveFraction: solution.effectiveFraction,
      startExtent: solution.startExtent,
      endExtent: solution.endExtent,
      availableExtent: solver.available,
      source: source,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onChanged(details);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ResizableSplitterTheme.of(context);
    final dividerStyle = widget.divider;
    final themeDivider = theme.divider;

    // Each effective value resolves widget -> theme -> built-in default. Null
    // means "unset" at every layer, so a partial override never clobbers a
    // value supplied by a broader scope.
    final dividerThickness =
        dividerStyle?.thickness ??
        themeDivider?.thickness ??
        ResizableSplitter._defaultDividerThickness;
    final handleHitSlop =
        dividerStyle?.hitSlop ??
        themeDivider?.hitSlop ??
        ResizableSplitter._defaultHandleHitSlop;
    final handleBuilder = dividerStyle?.builder ?? themeDivider?.builder;
    final dividerColor = dividerStyle?.color ?? themeDivider?.color;
    final semanticsLabels =
        widget.semantics ?? theme.semantics ?? const SplitterSemanticsLabels();

    final keyboardStep =
        widget.keyboardStep ??
        theme.keyboardStep ??
        ResizableSplitter._defaultKeyboardStep;
    final pageStep =
        widget.pageStep ?? theme.pageStep ?? ResizableSplitter._defaultPageStep;
    final overlayEnabled =
        widget.overlayEnabled ?? theme.overlayEnabled ?? true;
    final enableKeyboard =
        widget.enableKeyboard ?? theme.enableKeyboard ?? true;
    final enableHaptics = widget.enableHaptics ?? theme.enableHaptics ?? true;

    // The divider reserves only its visible thickness (not the grab slop): the
    // slop is applied by the catcher overlay in _buildBounded, which sits on top
    // of the panels and overlaps their edges instead of reducing panel layout.
    // Decoupling the grab region (overlay) from the layout footprint (Flex) makes
    // it structurally impossible for slop to eat layout. The footprint is also
    // clamped to the container per layout below, so a parent smaller than the
    // thickness shrinks the divider to fit rather than overflowing.

    final blockerColor = widget.blockerColor ?? theme.blockerColor;

    final unboundedBehavior =
        widget.unboundedBehavior ??
        theme.unboundedBehavior ??
        UnboundedBehavior.flexExpand;

    final fallbackExtent =
        widget.fallbackMainAxisExtent ??
        theme.fallbackMainAxisExtent ??
        ResizableSplitter._defaultFallbackMainAxisExtent;

    final antiAliasingWorkaround =
        widget.antiAliasingWorkaround ?? theme.antiAliasingWorkaround ?? false;

    final controller = _attachedController ?? _effectiveController;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSize = widget.axis.size(constraints.biggest);

        if (!maxSize.isFinite || maxSize <= 0) {
          if (unboundedBehavior == UnboundedBehavior.limitedBox) {
            return LimitedBox(
              maxWidth: widget.axis.isH ? fallbackExtent : double.infinity,
              maxHeight: widget.axis.isH ? double.infinity : fallbackExtent,
              child: LayoutBuilder(
                builder: (context, bounded) {
                  final boundedMax = widget.axis.size(bounded.biggest);
                  if (!boundedMax.isFinite || boundedMax <= 0) {
                    return Flex(
                      direction: widget.axis,
                      children: [
                        Expanded(child: widget.start),
                        Expanded(child: widget.end),
                      ],
                    );
                  }

                  return ValueListenableBuilder<SplitterState>(
                    valueListenable: controller,
                    builder: (_, state, _) {
                      // Clamp the divider to the container so it can never make
                      // the Flex overflow; the panes share whatever is left.
                      final effectiveThickness = dividerThickness.clamp(
                        0.0,
                        boundedMax,
                      );
                      final availableSize = boundedMax - effectiveThickness;
                      return _buildBounded(
                        position: state.position,
                        availableSize: availableSize,
                        dividerThickness: effectiveThickness,
                        enableKeyboard: enableKeyboard,
                        enableHaptics: enableHaptics,
                        keyboardStep: keyboardStep,
                        pageStep: pageStep,
                        overlayEnabled: overlayEnabled,
                        handleHitSlop: handleHitSlop,
                        blockerColor: blockerColor,
                        dividerColor: dividerColor,
                        handleBuilder: handleBuilder,
                        antiAliasingWorkaround: antiAliasingWorkaround,
                        crossAxisBounded: _crossAxisBounded(bounded),
                        controller: controller,
                        semantics: semanticsLabels,
                      );
                    },
                  );
                },
              ),
            );
          }

          // flexExpand fallback. Expanded requires a bounded main axis - under
          // a truly unbounded constraint RenderFlex throws ("children have
          // non-zero flex but incoming constraints are unbounded"). So only
          // flex when finite (e.g. a zero extent); otherwise let the panels
          // take their intrinsic size. Use limitedBox for a working splitter
          // under unbounded constraints.
          final bounded = maxSize.isFinite;
          return Flex(
            direction: widget.axis,
            children: bounded
                ? [Expanded(child: widget.start), Expanded(child: widget.end)]
                : [widget.start, widget.end],
          );
        }

        return ValueListenableBuilder<SplitterState>(
          valueListenable: controller,
          builder: (_, state, _) {
            // Clamp the divider to the container so it can never make the Flex
            // overflow; the panes share whatever is left.
            final effectiveThickness = dividerThickness.clamp(0.0, maxSize);
            final availableSize = maxSize - effectiveThickness;

            return _buildBounded(
              position: state.position,
              availableSize: availableSize,
              dividerThickness: effectiveThickness,
              enableKeyboard: enableKeyboard,
              enableHaptics: enableHaptics,
              keyboardStep: keyboardStep,
              pageStep: pageStep,
              overlayEnabled: overlayEnabled,
              handleHitSlop: handleHitSlop,
              blockerColor: blockerColor,
              dividerColor: dividerColor,
              handleBuilder: handleBuilder,
              antiAliasingWorkaround: antiAliasingWorkaround,
              crossAxisBounded: _crossAxisBounded(constraints),
              controller: controller,
              semantics: semanticsLabels,
            );
          },
        );
      },
    );
  }

  // Whether the cross axis (perpendicular to [axis]) is bounded. When it is not,
  // the layout Stack must size to the panes (loose) instead of expanding to an
  // infinite cross extent, which RenderStack would reject.
  bool _crossAxisBounded(BoxConstraints constraints) =>
      (widget.axis.isH ? constraints.maxHeight : constraints.maxWidth).isFinite;

  Widget _buildBounded({
    required SplitterPosition position,
    required double availableSize,
    required double dividerThickness,
    required bool enableKeyboard,
    required bool enableHaptics,
    required double keyboardStep,
    required double pageStep,
    required bool overlayEnabled,
    required double handleHitSlop,
    required Color? blockerColor,
    required WidgetStateProperty<Color?>? dividerColor,
    required Widget Function(BuildContext, SplitterHandleDetails)?
    handleBuilder,
    required bool antiAliasingWorkaround,
    required bool crossAxisBounded,
    required SplitterController controller,
    required SplitterSemanticsLabels semantics,
  }) {
    // Raw configured minimums (not pre-clamped): the solver clamps internally
    // and uses the raw values for proportional distribution, so a cramped
    // layout keeps its configured proportions instead of collapsing to 50/50.
    // One solver drives both the layout here and every ratio decision inside
    // the handle, so the two can never disagree on the legal bounds, and an
    // inverted clamp (the historic cramped-drag crash) is impossible.
    final collapsedPane = controller.value.collapsedPane;
    // The pixel-snap config lives on the solver, so every solve() it performs -
    // here for layout, and inside the handle for drag/keyboard/snap/semantics/
    // preview - snaps identically. The callbacks can never report a position the
    // layout did not actually draw.
    final solver = SplitterSolver(
      available: availableSize,
      start: widget.startConstraints,
      end: widget.endConstraints,
      minStartFraction: widget.minStartFraction,
      maxStartFraction: widget.maxStartFraction,
      policy: widget.constraintPolicy,
      surplusPolicy: widget.surplusPolicy,
      // Only an actually-collapsible pane resolves collapsed; a collapse request
      // on a fixed pane is ignored by the layout (the request still lives on the
      // controller). This is the request-vs-resolved split, like position vs
      // effective fraction.
      startCollapsed:
          collapsedPane == SplitterPane.start &&
          widget.startConstraints.collapsible,
      endCollapsed:
          collapsedPane == SplitterPane.end && widget.endConstraints.collapsible,
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
      snapToDevicePixels: antiAliasingWorkaround,
    );

    final solution = solver.solve(position);

    // Publish the resolved geometry to the controller (after the frame, so the
    // notification never fires mid-build). This is the on-screen read-out and
    // the signal for layout changes the request alone cannot produce - e.g. a
    // pixel pin's fraction shifting as the container resizes.
    _publishLayout(
      controller,
      SplitterLayout(
        effectiveFraction: solution.effectiveFraction,
        startExtent: solution.startExtent,
        endExtent: solution.endExtent,
        availableExtent: solver.available,
        minStartExtent: solution.minStartExtent,
        maxStartExtent: solution.maxStartExtent,
        resolution: solution.resolution,
        // The resolved collapse, not the request.
        collapsedPane: solution.startCollapsed
            ? SplitterPane.start
            : solution.endCollapsed
            ? SplitterPane.end
            : null,
      ),
    );

    // Report a collapse/expand transition once, after the frame, so the change
    // callbacks stay honest about every layout change and its source without
    // calling user code mid-build.
    _maybeReportCollapseChange(controller, solver, solution);

    final first = solution.startExtent;
    final second = solution.endExtent;
    // Under SplitterSurplusPolicy.leaveGap the panes do not fill the space; the
    // leftover becomes part of the middle slot (after the divider bar), so the
    // two panes stay pinned to their edges with the gap between them.
    final gap = (availableSize - first - second).clamp(0.0, availableSize);
    final middleExtent = dividerThickness + gap;

    final divider = _DividerHandle(
      axis: widget.axis,
      controller: controller,
      thickness: dividerThickness,
      solver: solver,
      solution: solution,
      blockerColor: blockerColor,
      dragBarrierBuilder: widget.dragBarrierBuilder,
      dividerColor: dividerColor,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
      enableKeyboard: enableKeyboard && widget.resizable,
      enableHaptics: enableHaptics,
      keyboardStep: keyboardStep,
      pageStep: pageStep,
      focusNode: _focusNode,
      semanticsLabel: widget.semanticsLabel,
      semantics: semantics,
      overlayEnabled: overlayEnabled && widget.resizable,
      snap: widget.snap,
      handleBuilder: handleBuilder,
      holdScrollWhileDragging:
          widget.holdScrollWhileDragging && widget.resizable,
      handleHitSlop: handleHitSlop,
      doubleTapResetTo: widget.doubleTapResetTo,
      resizable: widget.resizable,
      onTap: widget.onHandleTap,
      onDoubleTap: widget.onHandleDoubleTap,
      deferred: widget.deferredResize && widget.resizable,
      onPreviewChanged: widget.deferredResize && widget.resizable
          ? _setPreview
          : null,
      localMainAxisOf: _localMainAxisOf,
    );

    // During a deferred drag the panes hold their committed size; a lightweight
    // preview line tracks the pointer at the would-be boundary instead.
    final previewFraction = _previewFraction;
    final previewStart = previewFraction == null
        ? null
        : solver.solve(SplitterPosition.fraction(previewFraction)).startExtent;
    final previewColor = Theme.of(context).colorScheme.primary;

    // Layout + paint live in the Flex; the interactive handle is overlaid on top
    // of the panels. The middle Flex slot is a transparent gap of exactly the
    // visual thickness, and the handle (a `thickness + 2*slop` catcher) paints
    // its bar over that gap while its grab slop overhangs the panel edges. The
    // overlay sits above the panels, so it wins the hit test inside the slop -
    // which a plain Flex child could never do (the opaque panel is hit-tested
    // first in reverse paint order). `Positioned.directional` keeps the catcher
    // aligned with the divider under RTL, where the start pane is on the right.
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

    return Stack(
      // With an unbounded cross axis, StackFit.expand would force an infinite
      // cross extent (RenderStack throws); size to the panes instead so a
      // finite-main / unbounded-cross layout (e.g. a horizontal splitter in a
      // Column) still renders.
      fit: crossAxisBounded ? StackFit.expand : StackFit.loose,
      children: [
        Flex(
          direction: widget.axis,
          // With a bounded cross axis, stretch the panes so an intrinsically
          // small child (e.g. Text) fills the splitter's cross extent instead of
          // centering at its natural size (review A#12). Under an unbounded cross
          // axis the Stack sizes to the panes, so keep them at their intrinsic
          // size (stretch against an unbounded extent would throw).
          crossAxisAlignment: crossAxisBounded
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: widget.axis.isH ? first : null,
              height: widget.axis.isH ? null : first,
              // Clip each pane to its box so content cannot bleed across the
              // divider into the other pane.
              child: ClipRect(child: widget.start),
            ),
            SizedBox(
              width: widget.axis.isH ? middleExtent : null,
              height: widget.axis.isH ? null : middleExtent,
            ),
            SizedBox(
              width: widget.axis.isH ? second : null,
              height: widget.axis.isH ? null : second,
              child: ClipRect(child: widget.end),
            ),
          ],
        ),
        if (widget.axis.isH)
          Positioned.directional(
            textDirection: textDirection,
            start: first - handleHitSlop,
            top: 0,
            bottom: 0,
            child: divider,
          )
        else
          Positioned(
            top: first - handleHitSlop,
            left: 0,
            right: 0,
            child: divider,
          ),
        if (previewStart != null)
          if (widget.axis.isH)
            Positioned.directional(
              textDirection: textDirection,
              start: previewStart,
              width: dividerThickness,
              top: 0,
              bottom: 0,
              child: IgnorePointer(child: ColoredBox(color: previewColor)),
            )
          else
            Positioned(
              top: previewStart,
              height: dividerThickness,
              left: 0,
              right: 0,
              child: IgnorePointer(child: ColoredBox(color: previewColor)),
            ),
      ],
    );
  }
}

/// The immutable identity and start anchors of an in-flight drag.
///
/// Capturing the controller, pointer, axis, direction, start fraction/position,
/// available extent, mode, and preview callback at the moment a drag begins is
/// what lets it end cleanly on the controller it started on - even if the parent
/// swaps the controller, axis, mode, or preview callback mid-drag - and keeps
/// the pointer-to-fraction math stable if the container resizes underneath.
@immutable
class _DragSession {
  const _DragSession({
    required this.controller,
    required this.pointerId,
    required this.axis,
    required this.isRtl,
    required this.startEffectiveFraction,
    required this.startLocalMainAxis,
    required this.availableExtent,
    required this.deferred,
    required this.onPreviewChanged,
  });

  final SplitterController controller;
  final int pointerId;
  final Axis axis;
  final bool isRtl;
  final double startEffectiveFraction;
  final double startLocalMainAxis;
  final double availableExtent;
  final bool deferred;
  final ValueChanged<double?>? onPreviewChanged;

  /// Maps the current local main-axis pointer position to a clamped effective
  /// start fraction, measuring motion against the extent captured at drag start
  /// (stable under a mid-drag container resize) and clamping through [solver].
  double fractionFor(double currentLocalMainAxis, SplitterSolver solver) {
    // In RTL the start pane sits on the right, so a rightward (positive) delta
    // must shrink it. Vertical axes are unaffected.
    final delta =
        (currentLocalMainAxis - startLocalMainAxis) * (isRtl ? -1.0 : 1.0);
    final deltaRatio = availableExtent > 0 ? delta / availableExtent : 0.0;
    return solver
        .solve(SplitterPosition.fraction(startEffectiveFraction + deltaRatio))
        .effectiveFraction;
  }
}

/// Internal widget for the draggable divider handle.
class _DividerHandle extends StatefulWidget {
  const _DividerHandle({
    required this.axis,
    required this.controller,
    required this.thickness,
    required this.solver,
    required this.solution,
    required this.dividerColor,
    required this.blockerColor,
    required this.dragBarrierBuilder,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    required this.enableKeyboard,
    required this.enableHaptics,
    required this.keyboardStep,
    required this.pageStep,
    required this.focusNode,
    required this.semanticsLabel,
    required this.semantics,
    required this.overlayEnabled,
    required this.snap,
    required this.handleBuilder,
    required this.holdScrollWhileDragging,
    required this.handleHitSlop,
    required this.doubleTapResetTo,
    required this.resizable,
    this.onTap,
    this.onDoubleTap,
    this.deferred = false,
    this.onPreviewChanged,
    required this.localMainAxisOf,
  });

  final Axis axis;
  final SplitterController controller;
  final double thickness;
  final SplitterSolver solver;
  final SplitterSolution solution;
  final WidgetStateProperty<Color?>? dividerColor;
  final Color? blockerColor;
  final Widget Function(BuildContext context)? dragBarrierBuilder;
  final ValueChanged<SplitterChangeDetails>? onChanged;
  final ValueChanged<SplitterChangeDetails>? onChangeStart;
  final ValueChanged<SplitterChangeDetails>? onChangeEnd;
  final bool enableKeyboard;
  final bool enableHaptics;
  final double keyboardStep;
  final double pageStep;
  final FocusNode focusNode;
  final String? semanticsLabel;
  final SplitterSemanticsLabels semantics;
  final bool overlayEnabled;
  final SplitterSnapBehavior? snap;
  final Widget Function(BuildContext, SplitterHandleDetails)? handleBuilder;
  final bool holdScrollWhileDragging;
  final double handleHitSlop;
  final double? doubleTapResetTo;
  final bool resizable;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Whether to defer the resize until release, tracking the drag with a preview
  /// line instead of resizing the panes every frame.
  final bool deferred;

  /// Reports the live preview fraction during a deferred drag (null on release).
  final ValueChanged<double?>? onPreviewChanged;

  /// Maps a global pointer position to the splitter's local main-axis
  /// coordinate so drag math is transform-safe. Returns null if unavailable.
  final double? Function(Offset globalPosition) localMainAxisOf;

  @override
  State<_DividerHandle> createState() => _DividerHandleState();
}

class _DividerHandleState extends State<_DividerHandle> {
  // The active drag, or null when not dragging. A single nullable field is the
  // whole drag state machine: `_session != null` means dragging, and the
  // terminal [_endDrag] claims it before any user code, so a cancel, a
  // reconfiguration, a disposal, the router backup, or a throwing callback can
  // never double-fire, snap on a cancel, or strand the controller.
  _DragSession? _session;
  bool get _isDragging => _session != null;
  bool _isHovering = false;
  // Whether the keyboard focus highlight should show. Driven by
  // FocusableActionDetector.onShowFocusHighlight, so it tracks Flutter's focus
  // highlight mode (a ring for keyboard traversal, not for touch). Only ever set
  // true in the keyboard-enabled branch, so a divider without keyboard support
  // never paints a misleading ring.
  bool _isFocused = false;
  // Set when a PointerCancelEvent arrives for the active drag pointer. Flutter's
  // drag recognizer reports BOTH a normal release and a mid-drag cancel through
  // onEnd, so this flag - set by the Listener, which sees the raw cancel before
  // the recognizer's onEnd - is what lets _onDragEnd tell them apart so a cancel
  // never snaps or fires a successful onChangeEnd.
  bool _activePointerCanceled = false;
  double? _lastDragRatio;
  OverlayEntry? _dragOverlay;
  ScrollHoldController? _scrollHold;
  final List<_PendingPointer> _pendingPointers = <_PendingPointer>[];

  void _haptic() {
    if (widget.enableHaptics) unawaited(HapticFeedback.selectionClick());
  }

  // The pointer's position along the main axis in the splitter's local frame
  // (transform-safe), falling back to the raw global coordinate if the render
  // box is unavailable.
  double _mainAxisPosition(Offset globalPosition) =>
      widget.localMainAxisOf(globalPosition) ??
      (widget.axis.isH ? globalPosition.dx : globalPosition.dy);

  /// Builds the change payload for the effective [fraction], resolving the
  /// layout through the shared solver so the reported extents match what is
  /// drawn. [requestedPosition] is the controller's *actual* request - which may
  /// be a pixel pin - rather than a fraction fabricated from the effective value,
  /// so a drag that starts on a pinned pane reports the pin honestly.
  SplitterChangeDetails _changeDetails(
    double fraction,
    SplitterChangeSource source,
  ) {
    final solution = widget.solver.solve(SplitterPosition.fraction(fraction));
    return SplitterChangeDetails(
      requestedPosition: widget.controller.value.position,
      effectiveFraction: solution.effectiveFraction,
      startExtent: solution.startExtent,
      endExtent: solution.endExtent,
      availableExtent: widget.solver.available,
      source: source,
    );
  }

  /// The current on-screen start fraction, freshly re-solved from the
  /// controller's requested position so synchronous adjustments accumulate
  /// against what is actually shown (not a stale build-time solution).
  double get _effective =>
      widget.solver.solve(widget.controller.value.position).effectiveFraction;

  @override
  void didUpdateWidget(_DividerHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final session = _session;
    if (session == null) return;
    // A drag is anchored to the controller, axis, and mode it began on. If the
    // parent swaps any of those (or turns resizing off) mid-drag, interrupt it
    // on the controller it began on (held by the session): no commit, no snap,
    // no onChangeEnd. The idempotent [_endDrag] guard also means a later gesture
    // end/cancel for the same pointer can no longer fire a phantom onChangeEnd.
    if (!identical(session.controller, widget.controller) ||
        session.axis != widget.axis ||
        session.deferred != widget.deferred ||
        !widget.resizable) {
      _endDrag(_DragEndReason.interrupted);
    }
  }

  @override
  void dispose() {
    // Tear down on the session's controller (not necessarily widget.controller)
    // without setState. No commit, snap, or onChangeEnd.
    final session = _session;
    _session = null;
    if (session != null) _teardown(session);
    widget.controller._setDragCallback(null);
    _removeOverlay();
    _scrollHold?.cancel();
    _scrollHold = null;
    _pendingPointers.clear();
    super.dispose();
  }

  /// Resolves the divider color for the active [states], falling back to a tint
  /// derived from the ambient [ColorScheme] when the style leaves it unset. The
  /// merge of widget-over-theme already happened upstream, so [dividerColor] is
  /// the single resolved property here.
  Color _resolveDividerColor(Set<WidgetState> states) {
    final resolved = widget.dividerColor?.resolve(states);
    if (resolved != null) return resolved;
    final cs = Theme.of(context).colorScheme;
    if (states.contains(WidgetState.dragged)) {
      return cs.onSurface.withAlpha(31);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return cs.onSurface.withAlpha(20);
    }
    return cs.outlineVariant;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.resizable || _isDragging) return;
    if (!_isSupportedPointerKind(details.kind)) return;

    final controller = widget.controller;
    final pointerId = _takePendingPointer(details.globalPosition) ?? -1;
    final isRtl =
        widget.axis.isH && Directionality.maybeOf(context) == TextDirection.rtl;
    final session = _DragSession(
      controller: controller,
      pointerId: pointerId,
      axis: widget.axis,
      isRtl: isRtl,
      startEffectiveFraction: widget.solution.effectiveFraction,
      startLocalMainAxis: _mainAxisPosition(details.globalPosition),
      availableExtent: widget.solver.available,
      deferred: widget.deferred,
      onPreviewChanged: widget.onPreviewChanged,
    );
    setState(() => _session = session);
    _lastDragRatio = null;
    _activePointerCanceled = false;

    controller
      .._cancelAnimation()
      .._setDragging(true)
      .._setDragCallback(_endDrag);
    SplitterController._globalRouter.beginDrag(controller, pointerId);

    if (widget.holdScrollWhileDragging) {
      _scrollHold?.cancel();
      _scrollHold = Scrollable.maybeOf(context)?.position.hold(() {});
    }

    if (widget.overlayEnabled) _insertOverlay();

    _haptic();
    widget.focusNode.requestFocus();
    widget.onChangeStart?.call(
      _changeDetails(session.startEffectiveFraction, SplitterChangeSource.drag),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final session = _session;
    if (session == null) return;

    // The session captured the start anchors and available extent, so the math
    // stays stable even if the container resizes mid-drag; the live solver still
    // clamps to current constraints (no dead zone, no inverted clamp).
    final currentPos = _mainAxisPosition(details.globalPosition);
    final newRatio = session.fractionFor(currentPos, widget.solver);
    _lastDragRatio = newRatio;

    if (session.deferred) {
      // Defer the resize: move only the preview line. The panes keep their
      // committed size and onChanged stays silent until the drag is released.
      widget.onPreviewChanged?.call(newRatio);
      return;
    }

    final previous = _effective;
    widget.controller.updateRatio(newRatio);
    final current = _effective;
    if ((current - previous).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, SplitterChangeSource.drag));
    }
  }

  void _onDragEnd(DragEndDetails details) {
    // Flutter routes a mid-drag pointer cancel through onEnd, so classify it
    // with the flag the Listener set from the raw PointerCancelEvent.
    _endDrag(
      _activePointerCanceled
          ? _DragEndReason.canceled
          : _DragEndReason.completed,
    );
  }

  // Fires only when a drag is rejected before it is accepted (the session, if
  // any, is already gone); the idempotent _endDrag makes it a safe no-op.
  void _onDragCancel() => _endDrag(_DragEndReason.canceled);

  // The single, idempotent terminal for a drag. Claims the session before any
  // user code so a re-entrant call (the router backup plus the gesture end, or
  // a callback that triggers a rebuild) no-ops; settles only on a real
  // completion; and ALWAYS tears down, even if a user callback throws.
  void _endDrag(_DragEndReason reason) {
    final session = _session;
    if (session == null) return;
    _session = null;
    if (mounted) setState(() {}); // drop the dragged visual state

    SplitterChangeDetails? endDetails;
    try {
      if (reason == _DragEndReason.completed) endDetails = _settle(session);
    } finally {
      _teardown(session);
    }

    // onChangeEnd fires only on a real release, after teardown (so the
    // controller already reads isDragging == false), and never if settle threw.
    if (endDetails != null && mounted) widget.onChangeEnd?.call(endDetails);
  }

  // Commits the final position (or a snap) for a completed drag and returns the
  // end payload. May invoke onChanged; if that throws, [_endDrag]'s finally
  // still tears the drag down.
  SplitterChangeDetails _settle(_DragSession session) {
    // In deferred mode the controller has not moved during the drag, so the
    // target is the last preview; in live mode it equals the effective value.
    final target = _lastDragRatio ?? _effective;
    session.onPreviewChanged?.call(null);
    final snapped = _maybeSnap(target);

    // No snap claimed the release: commit the exact final ratio. The per-update
    // threshold can otherwise leave the handle a fraction short of where the
    // pointer let go (and in deferred mode the controller has not moved at all).
    if (snapped == null && _lastDragRatio != null) {
      final previous = _effective;
      session.controller.updateRatio(_lastDragRatio!, threshold: 0);
      final current = _effective;
      if ((current - previous).abs() > 1e-9) {
        widget.onChanged?.call(_changeDetails(current, SplitterChangeSource.drag));
      }
    }

    return _changeDetails(
      snapped ?? _effective,
      snapped != null ? SplitterChangeSource.snap : SplitterChangeSource.drag,
    );
  }

  // Releases the session's controller (the one the drag began on, never a
  // swapped-in one) and clears all per-drag resources, using the preview
  // callback captured at start so the preview clears even if the parent flipped
  // deferredResize/resizable off mid-drag. Commits nothing and never calls
  // setState, so it is safe to run from dispose.
  void _teardown(_DragSession session) {
    final controller = session.controller;
    controller
      .._setDragging(false)
      .._setDragCallback(null);
    SplitterController._globalRouter.endDrag(controller);
    session.onPreviewChanged?.call(null);
    _removeOverlay();
    _scrollHold?.cancel();
    _scrollHold = null;
    _lastDragRatio = null;
    _activePointerCanceled = false;
    if (session.pointerId >= 0) {
      _pendingPointers.removeWhere((pointer) => pointer.id == session.pointerId);
    }
  }

  double? _maybeSnap(double value) {
    final snap = widget.snap;
    final points = snap?.points;
    if (snap == null || points == null || points.isEmpty) return null;
    final available = widget.solver.available;
    if (available <= 0) return null;

    // A pixel tolerance is measured in logical pixels (size-independent);
    // otherwise the distance and tolerance are both in effective-ratio space.
    final usePixels = snap.pixelTolerance != null;
    final tolerance = snap.pixelTolerance ?? snap.tolerance;

    // Compare in effective space: a snap point that constraints push aside is
    // measured by where it actually lands, not by its nominal ratio.
    var nearest = value;
    var bestDist = double.infinity;
    for (final p in points) {
      final resolved = widget.solver
          .solve(SplitterPosition.fraction(p))
          .effectiveFraction;
      final d = (value - resolved).abs() * (usePixels ? available : 1.0);
      if (d < bestDist) {
        bestDist = d;
        nearest = resolved;
      }
    }
    if (bestDist <= tolerance) {
      final previous = _effective;
      if ((nearest - previous).abs() > 1e-9) {
        widget.controller.updateRatio(nearest, threshold: 0);
        final current = _effective;
        if ((current - previous).abs() > 1e-9) {
          widget.onChanged?.call(
            _changeDetails(current, SplitterChangeSource.snap),
          );
        }
      }
      return nearest;
    }
    return null;
  }

  void _insertOverlay() {
    if (_dragOverlay != null) return;

    // The shield needs a root Overlay to sit above platform views. Apps built on
    // MaterialApp/Navigator have one; if there is none, degrade gracefully - the
    // drag still works, just without the platform-view shield - rather than
    // throwing from a reusable layout primitive (Overlay.of would).
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      assert(() {
        debugPrint(
          'ResizableSplitter: no Overlay ancestor, so the drag platform-view '
          'shield is disabled. Provide a MaterialApp/Navigator (or any Overlay), '
          'or set overlayEnabled: false to opt out and silence this.',
        );
        return true;
      }());
      return;
    }

    final entry = OverlayEntry(
      builder: (context) => _DragOverlay(
        axis: widget.axis,
        blockerColor: widget.blockerColor,
        barrierBuilder: widget.dragBarrierBuilder,
      ),
    );

    // Only record the entry once it is actually inserted, so _removeOverlay can
    // always pair a remove() with the dispose() (mounted tracks the built
    // widget, not overlay membership).
    overlay.insert(entry);
    _dragOverlay = entry;
  }

  void _removeOverlay() {
    final overlay = _dragOverlay;
    _dragOverlay = null;
    if (overlay == null) return;
    overlay
      ..remove()
      ..dispose();
  }

  void _rememberPointer(PointerDownEvent event) {
    if (!widget.resizable || _isDragging) return;

    final isPrimaryMouse =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton;
    final isTouchLike =
        event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.trackpad ||
        event.kind == PointerDeviceKind.unknown;

    if (!isPrimaryMouse && !isTouchLike) return;

    // Pressing the handle focuses it, so keyboard adjustment works after a tap
    // (not only after a drag).
    if (widget.enableKeyboard && widget.resizable) {
      widget.focusNode.requestFocus();
    }

    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
    _pendingPointers.add(_PendingPointer(event.pointer, event.position));
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isDragging) return;

    for (final pointer in _pendingPointers) {
      if (pointer.id == event.pointer) {
        pointer.position = event.position;
        break;
      }
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
  }

  void _handlePointerCancel(PointerEvent event) {
    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
    // The recognizer's onEnd (which Flutter fires next, for both a release and
    // a cancel) reads this to settle a cancel as a cancel, not a completion.
    final session = _session;
    if (session != null && event.pointer == session.pointerId) {
      _activePointerCanceled = true;
    }
  }

  int? _takePendingPointer(Offset globalPosition) {
    if (_pendingPointers.isEmpty) return null;

    const double toleranceSquared = 16.0;
    _PendingPointer? match;
    var matchIndex = -1;

    for (var i = _pendingPointers.length - 1; i >= 0; i--) {
      final candidate = _pendingPointers[i];
      final diff = candidate.position - globalPosition;
      if (diff.distanceSquared <= toleranceSquared) {
        match = candidate;
        matchIndex = i;
        break;
      }
    }

    match ??= _pendingPointers.first;
    matchIndex = matchIndex >= 0 ? matchIndex : 0;
    _pendingPointers.removeAt(matchIndex);
    return match.id;
  }

  bool _isSupportedPointerKind(PointerDeviceKind? kind) {
    if (kind == null) return true;
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.mouse ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.trackpad ||
        kind == PointerDeviceKind.unknown;
  }

  /// The on-screen ratio for [ratio], honoring ratio caps and pixel minimums.
  /// Used for the semantics readout so it matches what the layout shows.
  double _effectiveRatio(double ratio) =>
      widget.solver.solve(SplitterPosition.fraction(ratio)).effectiveFraction;

  void _nudge(double delta, SplitterChangeSource source) {
    if (!widget.resizable) return;

    // Step from the current *effective* position (re-solved fresh, so repeated
    // presses without a rebuild still accumulate), then re-solve to clamp. This
    // moves the divider by the step in what the user actually sees, instead of
    // nudging a stored value through a dead band.
    final base = _effective;
    final newRatio = widget.solver
        .solve(SplitterPosition.fraction(base + delta))
        .effectiveFraction;
    widget.controller.jumpTo(SplitterPosition.fraction(newRatio));
    final current = _effective;
    if ((current - base).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, source));
      _haptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Focus is only meaningful when the handle is a keyboard-navigable resize
    // affordance; gate it so a stale highlight (e.g. after keyboard support is
    // turned off) can never paint a ring on a non-interactive divider.
    final isFocused = _isFocused && widget.enableKeyboard && widget.resizable;
    final states = <WidgetState>{
      if (!widget.resizable) WidgetState.disabled,
      if (_isHovering) WidgetState.hovered,
      if (isFocused) WidgetState.focused,
      if (_isDragging) WidgetState.dragged,
    };
    // The default focus ring is a border on the bar. A custom grip builder owns
    // its own focus visual (it receives isFocused), so the default ring is
    // suppressed when a builder is supplied to avoid a doubled indicator.
    final showFocusRing = isFocused && widget.handleBuilder == null;
    final currentDecoration = BoxDecoration(
      color: _resolveDividerColor(states),
      border: showFocusRing
          ? Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            )
          : null,
    );

    final grip =
        widget.handleBuilder?.call(
          context,
          SplitterHandleDetails(
            isDragging: _isDragging,
            isHovering: _isHovering,
            isFocused: isFocused,
            axis: widget.axis,
            thickness: widget.thickness,
          ),
        ) ??
        // Default subtle grip.
        Center(
          child: Container(
            width: widget.axis.isH ? 2 : 24,
            height: widget.axis.isH ? 24 : 2,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(77),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );

    Widget handle = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: currentDecoration,
      child: grip,
    );

    if (widget.axis.isH) {
      handle = SizedBox(width: widget.thickness, child: handle);
    } else {
      handle = SizedBox(height: widget.thickness, child: handle);
    }

    // Widen the *grab* area across the divider's thin dimension without moving
    // the visible bar: the slop is transparent padding that still sits inside
    // the opaque Listener below, so it hit-tests. The matching extent was
    // already reserved out of the panels via the divider footprint.
    if (widget.handleHitSlop > 0) {
      handle = Padding(
        padding: widget.axis.isH
            ? EdgeInsets.symmetric(horizontal: widget.handleHitSlop)
            : EdgeInsets.symmetric(vertical: widget.handleHitSlop),
        child: handle,
      );
    }

    Widget divider = GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      excludeFromSemantics: true,
      onHorizontalDragStart: widget.axis.isH ? _onDragStart : null,
      onHorizontalDragUpdate: widget.axis.isH ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.axis.isH ? _onDragEnd : null,
      onHorizontalDragCancel: widget.axis.isH ? _onDragCancel : null,
      onVerticalDragStart: widget.axis.isH ? null : _onDragStart,
      onVerticalDragUpdate: widget.axis.isH ? null : _onDragUpdate,
      onVerticalDragEnd: widget.axis.isH ? null : _onDragEnd,
      onVerticalDragCancel: widget.axis.isH ? null : _onDragCancel,
      onTap: widget.onTap,
      onDoubleTap:
          (widget.onDoubleTap != null || widget.doubleTapResetTo != null)
          ? () {
              widget.onDoubleTap?.call();
              if (widget.doubleTapResetTo != null && widget.resizable) {
                final target = widget.doubleTapResetTo!;
                final startValue = widget.controller.effectiveFraction;
                unawaited(
                  widget.controller.animateTo(target).then((status) {
                    // Only report a settle when the animation actually reached
                    // the target; a drag/value-write that cancelled it, or a
                    // disposal, must not emit a phantom programmatic change.
                    if (!mounted ||
                        status != SplitterAnimationStatus.completed) {
                      return;
                    }
                    final updated = _effective;
                    if ((updated - startValue).abs() > 1e-9) {
                      widget.onChanged?.call(
                        _changeDetails(
                          updated,
                          SplitterChangeSource.programmatic,
                        ),
                      );
                    }
                  }),
                );
              }
            }
          : null,
      child: MouseRegion(
        cursor: widget.resizable
            ? widget.axis.cursor
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _rememberPointer,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: handle,
        ),
      ),
    );

    // Value previews mirror what an adjust action actually does: move from the
    // current effective position by one step. Assistive adjustment is offered
    // whenever the splitter is resizable, independent of physical keyboard
    // support - a screen reader is its own input channel. Each direction is
    // additionally gated on whether the divider can actually move that way, so a
    // pane pinned at a hard bound drops the action it cannot perform rather than
    // announcing a no-op (review A#14).
    final effective = _effective;
    final labels = widget.semantics;
    String fmt(double ratio) => labels.formatValue(ratio.clamp(0.0, 1.0));
    final canIncrease = widget.resizable && widget.solution.canIncreaseStart;
    final canDecrease = widget.resizable && widget.solution.canDecreaseStart;

    divider = Semantics(
      slider: true,
      enabled: widget.resizable,
      textDirection: Directionality.maybeOf(context),
      label:
          widget.semanticsLabel ??
          labels.label(axis: widget.axis, resizable: widget.resizable),
      value: fmt(effective),
      increasedValue: canIncrease
          ? fmt(_effectiveRatio(effective + widget.keyboardStep))
          : null,
      decreasedValue: canDecrease
          ? fmt(_effectiveRatio(effective - widget.keyboardStep))
          : null,
      onIncrease: canIncrease
          ? () => _nudge(widget.keyboardStep, SplitterChangeSource.semantics)
          : null,
      onDecrease: canDecrease
          ? () => _nudge(-widget.keyboardStep, SplitterChangeSource.semantics)
          : null,
      child: divider,
    );

    if (widget.enableKeyboard && widget.resizable) {
      final isRtl =
          widget.axis.isH && Directionality.of(context) == TextDirection.rtl;
      final decreaseKey = widget.axis.isH
          ? (isRtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)
          : LogicalKeyboardKey.arrowUp;
      final increaseKey = widget.axis.isH
          ? (isRtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight)
          : LogicalKeyboardKey.arrowDown;
      divider = FocusableActionDetector(
        focusNode: widget.focusNode,
        // Tracks Flutter's focus highlight mode so the ring shows for keyboard
        // traversal but not for a touch/mouse focus.
        onShowFocusHighlight: (show) {
          if (show != _isFocused) setState(() => _isFocused = show);
        },
        shortcuts: <LogicalKeySet, Intent>{
          // Fine step (left/right swap under RTL on the horizontal axis).
          LogicalKeySet(decreaseKey): _AdjustIntent(-widget.keyboardStep),
          LogicalKeySet(increaseKey): _AdjustIntent(widget.keyboardStep),
          // Page step
          LogicalKeySet(LogicalKeyboardKey.pageUp): _AdjustIntent(
            -widget.pageStep,
          ),
          LogicalKeySet(LogicalKeyboardKey.pageDown): _AdjustIntent(
            widget.pageStep,
          ),
          // Jump to bounds
          LogicalKeySet(LogicalKeyboardKey.home): const _JumpIntent.toMin(),
          LogicalKeySet(LogicalKeyboardKey.end): const _JumpIntent.toMax(),
        },
        actions: <Type, Action<Intent>>{
          _AdjustIntent: CallbackAction<_AdjustIntent>(
            onInvoke: (intent) {
              _nudge(intent.delta, SplitterChangeSource.keyboard);
              return null;
            },
          ),
          _JumpIntent: CallbackAction<_JumpIntent>(
            onInvoke: (intent) {
              final previous = _effective;
              final dest = intent.toMin
                  ? widget.solver
                        .solve(const SplitterPosition.fraction(0))
                        .effectiveFraction
                  : widget.solver
                        .solve(const SplitterPosition.fraction(1))
                        .effectiveFraction;
              widget.controller.jumpTo(SplitterPosition.fraction(dest));
              final current = _effective;
              if ((current - previous).abs() > 1e-9) {
                widget.onChanged?.call(
                  _changeDetails(current, SplitterChangeSource.keyboard),
                );
                _haptic();
              }
              return null;
            },
          ),
        },
        child: divider,
      );
    }

    return divider;
  }
}

class _PendingPointer {
  _PendingPointer(this.id, this.position);

  final int id;
  Offset position;
}

/// An invisible overlay that acts as a shield to block pointer events
/// from reaching platform views during a drag operation.
class _DragOverlay extends StatelessWidget {
  const _DragOverlay({
    required this.axis,
    this.blockerColor,
    this.barrierBuilder,
  });

  final Axis axis;
  final Color? blockerColor;
  final Widget Function(BuildContext context)? barrierBuilder;

  @override
  Widget build(BuildContext context) {
    // The Listener below hit-tests opaquely regardless of paint, so the visual
    // is purely cosmetic - the shield works even with a transparent barrier. A
    // custom barrierBuilder replaces only that visual, never the shield.
    final barrier =
        barrierBuilder?.call(context) ??
        ColoredBox(color: blockerColor ?? Colors.transparent);

    return Positioned.fill(
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: axis.cursor,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            // The opaque Listener already wins every hit, so the shield works
            // even with a transparent barrier. IgnorePointer additionally keeps
            // a custom barrierBuilder strictly visual: its own recognizers or
            // buttons can never receive the pointer events (review A#16).
            child: IgnorePointer(child: barrier),
          ),
        ),
      ),
    );
  }
}

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
