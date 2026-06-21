// We intentionally expose imperative helpers instead of setters for ergonomics.
// ignore_for_file: use_setters_to_change_properties
// A robust, high-performance split view that plays nicely with platform views.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resizable_splitter/src/resizable_splitter_theme.dart';
import 'package:resizable_splitter/src/split_divider_style.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_snap_behavior.dart';
import 'package:resizable_splitter/src/split_solver.dart';
import 'package:resizable_splitter/src/split_view_value.dart';

/// Axis helpers to eliminate H/V duplication.
extension _AxisHelpers on Axis {
  bool get isH => this == Axis.horizontal;

  double size(Size s) => isH ? s.width : s.height;

  SystemMouseCursor get cursor =>
      isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;
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
class SplitterController extends ValueNotifier<SplitterPosition> {
  /// Creates a splitter controller at [initialPosition] (default: centered).
  ///
  /// The controller stores the requested [SplitterPosition]; the splitter
  /// resolves it against the live layout every frame. A pixel request
  /// ([SplitterPosition.startPixels] / [SplitterPosition.endPixels]) therefore
  /// keeps its pixel size as the container resizes, while a drag or keyboard
  /// adjustment writes a fractional position (the pin releases on interaction).
  SplitterController({
    SplitterPosition initialPosition = const SplitterPosition.fraction(0.5),
  }) : _effectiveFraction = initialPosition.resolveFraction(0),
       super(initialPosition);

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
    }
  }

  @override
  void dispose() {
    _globalRouter.unregister(this);
    _animator?.cancel();
    _isDragging.dispose();
    super.dispose();
  }

  /// The on-screen start fraction the attached splitter last resolved, in
  /// `[0, 1]`. Unlike [value] (the request, which may be in pixels) this is the
  /// effective ratio actually shown - the convenient value for read-outs. Before
  /// the first layout it reflects the requested fraction (0 for a pixel request).
  double get effectiveFraction => _effectiveFraction;
  double _effectiveFraction;

  // Updated by the attached splitter after each solve so [effectiveFraction]
  // tracks the constrained, on-screen ratio. Not a notification source: the
  // request in [value] is canonical and already drives rebuilds.
  void _setEffectiveFraction(double fraction) => _effectiveFraction = fraction;

  /// Sets the requested [SplitterPosition]. The solver sanitizes it at layout,
  /// so a malformed request (for example a non-finite fraction) can never
  /// corrupt the layout. A write that is not an animation tick (a drag, key
  /// press, reset, or direct assignment) takes over from a running animation.
  @override
  set value(SplitterPosition newValue) {
    if (!_isAnimationTick) _animator?.cancel();
    // A fractional request resolves without the layout, so refresh the cache
    // eagerly; the splitter overwrites it with the constrained value on layout.
    if (newValue is FractionSplitterPosition) {
      _effectiveFraction = newValue.resolveFraction(0);
    }
    super.value = newValue;
  }

  /// Updates to a fractional position, with an optional threshold to prevent
  /// chatty updates. The threshold is compared against [effectiveFraction].
  void updateRatio(double newRatio, {double threshold = 0.002}) {
    final clamped = newRatio.clamp(0.0, 1.0).toDouble();
    if ((clamped - effectiveFraction).abs() > threshold) {
      value = SplitterPosition.fraction(clamped);
    }
  }

  /// Resets the splitter to a fractional position, defaulting to center.
  void reset([double to = 0.5]) {
    assert(to >= 0.0 && to <= 1.0, 'to must be between 0.0 and 1.0');
    value = SplitterPosition.fraction(to);
  }

  /// Animates the split ratio to [target].
  ///
  /// Driven by the attached view's vsync, so it honors the platform refresh
  /// rate and `MediaQuery.disableAnimations`. A drag, key press, reset, or
  /// direct value write cancels a run in progress. With no view attached the
  /// value is set immediately.
  Future<void> animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeOutCubic,
  }) {
    final goal = target.clamp(0.0, 1.0).toDouble();
    if ((goal - effectiveFraction).abs() < 1e-7) {
      value = SplitterPosition.fraction(goal);
      return Future<void>.value();
    }
    final animator = _animator;
    if (animator == null) {
      value = SplitterPosition.fraction(goal);
      return Future<void>.value();
    }
    return animator.animateTo(goal, duration, curve);
  }

  void _attachAnimator(_SplitterAnimator animator) => _animator = animator;

  void _detachAnimator(_SplitterAnimator animator) {
    if (identical(_animator, animator)) _animator = null;
  }

  void _cancelAnimation() => _animator?.cancel();

  // Internal methods for global router
  void _stopDrag() {
    _dragCallback?.call();
    _dragCallback = null;
  }

  void _setDragCallback(VoidCallback? cb) => _dragCallback = cb;
  VoidCallback? _dragCallback;

  void _setDragging(bool dragging) => _isDragging.value = dragging;

  /// Resets the global pointer router. For testing only.
  @visibleForTesting
  static void resetGlobalRouter() => _globalRouter.dispose();
}

/// Drives vsync animation for a [SplitterController]. Implemented by the
/// splitter's [State], which owns the [TickerProvider].
abstract interface class _SplitterAnimator {
  /// Animates the controller value to [target]; the future resolves when the
  /// run completes or is cancelled.
  Future<void> animateTo(double target, Duration duration, Curve curve);

  /// Stops any in-progress animation.
  void cancel();
}

/// Singleton global pointer router to handle drag completion events.
class _GlobalPointerRouter {
  factory _GlobalPointerRouter() => _instance;

  _GlobalPointerRouter._() {
    _initialize();
  }

  static final _instance = _GlobalPointerRouter._();
  SplitterController? _currentlyDragging;
  int? _activePointer;
  bool _initialized = false;

  void _initialize() {
    if (_initialized) return;
    final binding = _maybeBinding();
    if (binding == null) return;
    binding.pointerRouter.addGlobalRoute(_handleGlobal);
    _initialized = true;
  }

  /// Lazily installs the global pointer route. Named for what it actually
  /// does: it keeps no per-controller registry, it just ensures init.
  void ensureInitialized() {
    _initialize();
  }

  void unregister(SplitterController c) {
    if (c == _currentlyDragging) {
      _currentlyDragging = null;
      _activePointer = null;
    }
  }

  void setDragging(SplitterController? c, [int? pointerId]) {
    if (c != null) {
      _initialize();
    }
    _currentlyDragging = c;
    _activePointer = pointerId;
  }

  void _handleGlobal(PointerEvent event) {
    final isUp = event is PointerUpEvent || event is PointerCancelEvent;
    if (isUp &&
        _currentlyDragging != null &&
        _activePointer != null &&
        _activePointer! >= 0 &&
        event.pointer == _activePointer) {
      _currentlyDragging?._stopDrag();
      _currentlyDragging = null;
      _activePointer = null;
    }
  }

  void dispose() {
    if (!_initialized) {
      _currentlyDragging = null;
      _activePointer = null;
      return;
    }

    final binding = _maybeBinding();
    if (binding != null) {
      binding.pointerRouter.removeGlobalRoute(_handleGlobal);
    }
    _initialized = false;
    _currentlyDragging = null;
    _activePointer = null;
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
    this.blockerColor,
    this.overlayEnabled,
    this.snap,
    this.holdScrollWhileDragging = false,
    this.doubleTapResetTo,
    this.resizable = true,
    this.onHandleTap,
    this.onHandleDoubleTap,
    this.constraintPolicy = SplitterConstraintPolicy.favorStart,
    this.unboundedBehavior,
    this.fallbackMainAxisExtent,
    this.antiAliasingWorkaround,
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

  /// Called whenever the split position changes, with both the request and the
  /// effective layout plus the [SplitterChangeSource] (drag, keyboard, snap,
  /// semantics, or the built-in double-tap reset).
  final ValueChanged<SplitterChangeDetails>? onChanged;

  /// Called when a drag gesture starts, with the position at that moment.
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

  /// Accessibility label for the divider.
  final String? semanticsLabel;

  /// The blocked color when dragged.
  final Color? blockerColor;

  /// Whether the protective overlay is used while dragging. Defaults to true.
  final bool? overlayEnabled;

  /// Optional snap points; a drag settles onto the nearest within tolerance.
  final SplitterSnapBehavior? snap;

  /// Whether to temporarily hold the nearest Scrollable's position while dragging.
  final bool holdScrollWhileDragging;

  /// Optional ratio to jump to on double-tap.
  final double? doubleTapResetTo;

  /// Whether the divider responds to drag gestures.
  final bool resizable;

  /// Called when the divider is tapped.
  final VoidCallback? onHandleTap;

  /// Called when the divider is double-tapped.
  final VoidCallback? onHandleDoubleTap;

  /// Policy applied when both panes cannot meet their minimums at once.
  final SplitterConstraintPolicy constraintPolicy;

  /// Fallback layout behavior when constraints are unbounded along the main
  /// axis. Defaults to [UnboundedBehavior.flexExpand].
  final UnboundedBehavior? unboundedBehavior;

  /// Extent in pixels to use when [unboundedBehavior] is
  /// [UnboundedBehavior.limitedBox]. Defaults to 500.
  final double? fallbackMainAxisExtent;

  /// Floors the leading panel size to whole physical pixels to avoid anti-alias
  /// gaps. Defaults to false.
  final bool? antiAliasingWorkaround;

  @override
  State<ResizableSplitter> createState() => _ResizableSplitterState();
}

class _ResizableSplitterState extends State<ResizableSplitter>
    with SingleTickerProviderStateMixin
    implements _SplitterAnimator {
  late final FocusNode _focusNode;
  late final AnimationController _animationController;
  SplitterController? _internalController;
  SplitterController? _attachedController;

  // vsync animation state backing SplitterController.animateTo.
  double _animBegin = 0;
  double _animEnd = 0;
  Curve _animCurve = Curves.linear;
  Completer<void>? _animCompleter;

  SplitterController get _effectiveController =>
      widget.controller ??
      (_internalController ??= SplitterController(
        initialPosition: widget.initialPosition,
      ));

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ResizableSplitterHandle');
    _animationController = AnimationController(vsync: this)
      ..addListener(_onAnimationTick)
      ..addStatusListener(_onAnimationStatus);
    final controller = _effectiveController
      .._attach(this)
      .._attachAnimator(this);
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
        initialPosition: (_attachedController ?? oldWidget.controller!).value,
      );
    }

    final newController =
        widget.controller ??
        (_internalController ??= SplitterController(
          initialPosition: widget.initialPosition,
        ));

    if (!identical(_attachedController, newController)) {
      _attachedController
        ?.._detachAnimator(this)
        .._detach(this);

      if (oldWidget.controller == null && widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      }

      newController
        .._attach(this)
        .._attachAnimator(this);
      _attachedController = newController;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _attachedController
      ?.._detachAnimator(this)
      .._detach(this);
    _focusNode.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Future<void> animateTo(double target, Duration duration, Curve curve) {
    _animationController.stop();
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final controller = _attachedController ?? _effectiveController;
    if (disable || duration <= Duration.zero) {
      _completeAnimation();
      controller.value = SplitterPosition.fraction(target);
      return Future<void>.value();
    }
    _animBegin = controller.effectiveFraction;
    _animEnd = target;
    _animCurve = curve;
    _animationController.duration = duration;
    _completeAnimation();
    final completer = Completer<void>();
    _animCompleter = completer;
    _animationController.forward(from: 0);
    return completer.future;
  }

  @override
  void cancel() {
    if (!_animationController.isAnimating && _animCompleter == null) return;
    _animationController.stop();
    _completeAnimation();
  }

  void _completeAnimation() {
    final completer = _animCompleter;
    _animCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _setAnimatedValue(double value) {
    final controller = _attachedController ?? _effectiveController;
    controller._isAnimationTick = true;
    controller.value = SplitterPosition.fraction(value);
    controller._isAnimationTick = false;
  }

  void _onAnimationTick() {
    final t = _animCurve.transform(_animationController.value);
    _setAnimatedValue(_animBegin + (_animEnd - _animBegin) * t);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _setAnimatedValue(_animEnd);
      _completeAnimation();
    }
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

    // The divider reserves only its visible thickness. The grab slop is applied
    // by the catcher overlay in _buildBounded, which sits on top of the panels,
    // so the slop enlarges the hit target by overlapping the panel edges instead
    // of reducing panel layout. Decoupling the grab region (overlay) from the
    // layout footprint (Flex) makes it structurally impossible for slop to eat
    // layout.
    final dividerExtent = dividerThickness;

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

                  return ValueListenableBuilder<SplitterPosition>(
                    valueListenable: controller,
                    builder: (_, position, _) {
                      final availableSize = (boundedMax - dividerExtent).clamp(
                        0.0,
                        double.infinity,
                      );
                      return _buildBounded(
                        position: position,
                        availableSize: availableSize,
                        dividerThickness: dividerThickness,
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
                        controller: controller,
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

        return ValueListenableBuilder<SplitterPosition>(
          valueListenable: controller,
          builder: (_, position, _) {
            final availableSize = (maxSize - dividerExtent).clamp(
              0.0,
              double.infinity,
            );

            return _buildBounded(
              position: position,
              availableSize: availableSize,
              dividerThickness: dividerThickness,
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
              controller: controller,
            );
          },
        );
      },
    );
  }

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
    required SplitterController controller,
  }) {
    // Raw configured minimums (not pre-clamped): the solver clamps internally
    // and uses the raw values for proportional distribution, so a cramped
    // layout keeps its configured proportions instead of collapsing to 50/50.
    // One solver drives both the layout here and every ratio decision inside
    // the handle, so the two can never disagree on the legal bounds, and an
    // inverted clamp (the historic cramped-drag crash) is impossible.
    final solver = SplitterSolver(
      available: availableSize,
      start: widget.startConstraints,
      end: widget.endConstraints,
      minStartFraction: widget.minStartFraction,
      maxStartFraction: widget.maxStartFraction,
      policy: widget.constraintPolicy,
    );

    final solution = solver.solve(
      position,
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
      snapToDevicePixels: antiAliasingWorkaround,
    );

    // Keep the controller's effective-fraction read-out in step with the
    // constrained, on-screen ratio it just resolved to.
    controller._setEffectiveFraction(solution.effectiveFraction);

    final first = solution.startExtent;
    final second = solution.endExtent;

    final divider = _DividerHandle(
      axis: widget.axis,
      controller: controller,
      thickness: dividerThickness,
      solver: solver,
      solution: solution,
      blockerColor: blockerColor,
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
    );

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
      fit: StackFit.expand,
      children: [
        Flex(
          direction: widget.axis,
          children: [
            SizedBox(
              width: widget.axis.isH ? first : null,
              height: widget.axis.isH ? null : first,
              child: widget.start,
            ),
            SizedBox(
              width: widget.axis.isH ? dividerThickness : null,
              height: widget.axis.isH ? null : dividerThickness,
            ),
            SizedBox(
              width: widget.axis.isH ? second : null,
              height: widget.axis.isH ? null : second,
              child: widget.end,
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
      ],
    );
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
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    required this.enableKeyboard,
    required this.enableHaptics,
    required this.keyboardStep,
    required this.pageStep,
    required this.focusNode,
    required this.semanticsLabel,
    required this.overlayEnabled,
    required this.snap,
    required this.handleBuilder,
    required this.holdScrollWhileDragging,
    required this.handleHitSlop,
    required this.doubleTapResetTo,
    required this.resizable,
    this.onTap,
    this.onDoubleTap,
  });

  final Axis axis;
  final SplitterController controller;
  final double thickness;
  final SplitterSolver solver;
  final SplitterSolution solution;
  final WidgetStateProperty<Color?>? dividerColor;
  final Color? blockerColor;
  final ValueChanged<SplitterChangeDetails>? onChanged;
  final ValueChanged<SplitterChangeDetails>? onChangeStart;
  final ValueChanged<SplitterChangeDetails>? onChangeEnd;
  final bool enableKeyboard;
  final bool enableHaptics;
  final double keyboardStep;
  final double pageStep;
  final FocusNode focusNode;
  final String? semanticsLabel;
  final bool overlayEnabled;
  final SplitterSnapBehavior? snap;
  final Widget Function(BuildContext, SplitterHandleDetails)? handleBuilder;
  final bool holdScrollWhileDragging;
  final double handleHitSlop;
  final double? doubleTapResetTo;
  final bool resizable;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_DividerHandle> createState() => _DividerHandleState();
}

class _DividerHandleState extends State<_DividerHandle> {
  bool _isDragging = false;
  bool _isHovering = false;
  double? _dragStartPosition;
  double? _dragStartRatio;
  double? _lastDragRatio;
  OverlayEntry? _dragOverlay;
  int? _activePointer;
  ScrollHoldController? _scrollHold;
  final List<_PendingPointer> _pendingPointers = <_PendingPointer>[];

  void _haptic() {
    if (widget.enableHaptics) unawaited(HapticFeedback.selectionClick());
  }

  /// Builds the change payload for [fraction], resolving the effective layout
  /// through the shared solver so the reported extents match what is drawn.
  SplitterChangeDetails _changeDetails(
    double fraction,
    SplitterChangeSource source,
  ) {
    final solution = widget.solver.solve(SplitterPosition.fraction(fraction));
    return SplitterChangeDetails(
      requestedPosition: SplitterPosition.fraction(fraction),
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
      widget.solver.solve(widget.controller.value).effectiveFraction;

  @override
  void dispose() {
    if (_isDragging) {
      widget.controller._setDragging(false);
      SplitterController._globalRouter.setDragging(null);
    }
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
    if (states.contains(WidgetState.hovered)) {
      return cs.onSurface.withAlpha(20);
    }
    return cs.outlineVariant;
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.resizable || _isDragging) return;
    if (!_isSupportedPointerKind(details.kind)) return;

    setState(() => _isDragging = true);
    widget.controller
      .._cancelAnimation()
      .._setDragging(true);

    _dragStartRatio = widget.solution.effectiveFraction;
    _dragStartPosition = widget.axis.isH
        ? details.globalPosition.dx
        : details.globalPosition.dy;

    final pointerId = _takePendingPointer(details.globalPosition) ?? -1;
    _activePointer = pointerId;

    SplitterController._globalRouter.setDragging(widget.controller, pointerId);
    widget.controller._setDragCallback(_stopDrag);

    if (widget.holdScrollWhileDragging) {
      _scrollHold?.cancel();
      _scrollHold = Scrollable.maybeOf(context)?.position.hold(() {});
    }

    if (widget.overlayEnabled) _insertOverlay();

    _haptic();
    widget.focusNode.requestFocus();
    widget.onChangeStart?.call(
      _changeDetails(
        widget.solution.effectiveFraction,
        SplitterChangeSource.drag,
      ),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final available = widget.solver.available;
    if (!_isDragging ||
        _dragStartPosition == null ||
        _dragStartRatio == null ||
        available <= 0) {
      return;
    }

    final currentPos = widget.axis.isH
        ? details.globalPosition.dx
        : details.globalPosition.dy;
    // In RTL the start pane sits on the right, so dragging the divider right (a
    // positive delta) must shrink it. Vertical axes are unaffected.
    final isRtl =
        widget.axis.isH && Directionality.maybeOf(context) == TextDirection.rtl;
    final delta = (currentPos - _dragStartPosition!) * (isRtl ? -1.0 : 1.0);
    final deltaRatio = delta / available;

    // Resolve through the shared solver so the stored value tracks what is
    // actually shown (no dead zone) and a cramped layout can never invert a
    // clamp. The drag began at the effective fraction, so motion is 1:1.
    final newRatio = widget.solver
        .solve(SplitterPosition.fraction(_dragStartRatio! + deltaRatio))
        .effectiveFraction;
    _lastDragRatio = newRatio;

    final previous = _effective;
    widget.controller.updateRatio(newRatio);
    final current = _effective;
    if ((current - previous).abs() > 1e-9) {
      widget.onChanged?.call(
        _changeDetails(current, SplitterChangeSource.drag),
      );
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _stopDrag();
  }

  void _onDragCancel() {
    _stopDrag();
  }

  void _stopDrag() {
    final snapped = _maybeSnap(_effective);

    // No snap point claimed the release: commit the exact final ratio. The
    // per-update threshold can otherwise leave the handle a fraction short of
    // where the pointer actually let go.
    if (snapped == null && _lastDragRatio != null) {
      final previous = _effective;
      widget.controller.updateRatio(_lastDragRatio!, threshold: 0);
      final current = _effective;
      if ((current - previous).abs() > 1e-9) {
        widget.onChanged?.call(
          _changeDetails(current, SplitterChangeSource.drag),
        );
      }
    }

    if (mounted) {
      setState(() => _isDragging = false);
    } else {
      _isDragging = false;
    }

    widget.controller._setDragging(false);
    widget.controller._setDragCallback(null);
    SplitterController._globalRouter.setDragging(null);
    _removeOverlay();
    _scrollHold?.cancel();
    _scrollHold = null;

    _dragStartPosition = null;
    _dragStartRatio = null;
    _lastDragRatio = null;

    if (_activePointer != null && _activePointer! >= 0) {
      _pendingPointers.removeWhere((pointer) => pointer.id == _activePointer);
    }
    _activePointer = null;

    if (mounted) {
      widget.onChangeEnd?.call(
        _changeDetails(
          snapped ?? _effective,
          snapped != null
              ? SplitterChangeSource.snap
              : SplitterChangeSource.drag,
        ),
      );
    }
  }

  double? _maybeSnap(double value) {
    final snap = widget.snap;
    final points = snap?.points;
    if (snap == null || points == null || points.isEmpty) return null;
    if (widget.solver.available <= 0) return null;

    // Compare in effective space: a snap point that constraints push aside is
    // measured by where it actually lands, not by its nominal ratio.
    var nearest = value;
    var bestDist = double.infinity;
    for (final p in points) {
      final resolved = widget.solver
          .solve(SplitterPosition.fraction(p))
          .effectiveFraction;
      final d = (value - resolved).abs();
      if (d < bestDist) {
        bestDist = d;
        nearest = resolved;
      }
    }
    if (bestDist <= snap.tolerance) {
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

    final entry = OverlayEntry(
      builder: (context) =>
          _DragOverlay(axis: widget.axis, blockerColor: widget.blockerColor),
    );

    // Use the root overlay so it sits above platform views. Only record the
    // entry once it is actually inserted, so _removeOverlay can always pair a
    // remove() with the dispose() (mounted tracks the built widget, not overlay
    // membership).
    Overlay.of(context, rootOverlay: true).insert(entry);
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

  void _handlePointerEnd(PointerEvent event) {
    _pendingPointers.removeWhere((pointer) => pointer.id == event.pointer);
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
    widget.controller.value = SplitterPosition.fraction(newRatio);
    final current = _effective;
    if ((current - base).abs() > 1e-9) {
      widget.onChanged?.call(_changeDetails(current, source));
      _haptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = <WidgetState>{
      if (!widget.resizable) WidgetState.disabled,
      if (_isHovering) WidgetState.hovered,
      if (_isDragging) WidgetState.dragged,
    };
    final currentDecoration = BoxDecoration(
      color: _resolveDividerColor(states),
    );

    final grip =
        widget.handleBuilder?.call(
          context,
          SplitterHandleDetails(
            isDragging: _isDragging,
            isHovering: _isHovering,
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
                  widget.controller.animateTo(target).then((_) {
                    if (!mounted) return;
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
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: handle,
        ),
      ),
    );

    // Value previews mirror what an adjust action actually does: move from the
    // current effective position by one step. Assistive adjustment is offered
    // whenever the splitter is resizable, independent of physical keyboard
    // support - a screen reader is its own input channel.
    final effective = _effective;
    String pct(double ratio) => '${(ratio.clamp(0.0, 1.0) * 100).round()}%';
    final allowSemanticAdjust = widget.resizable;

    divider = Semantics(
      slider: true,
      enabled: widget.resizable,
      textDirection: Directionality.maybeOf(context),
      label:
          widget.semanticsLabel ??
          (widget.resizable
              ? (widget.axis.isH
                    ? 'Drag to resize left and right panels.'
                    : 'Drag to resize top and bottom panels.')
              : (widget.axis.isH
                    ? 'Splitter between left and right panels.'
                    : 'Splitter between top and bottom panels.')),
      value: pct(effective),
      increasedValue: allowSemanticAdjust
          ? pct(_effectiveRatio(effective + widget.keyboardStep))
          : null,
      decreasedValue: allowSemanticAdjust
          ? pct(_effectiveRatio(effective - widget.keyboardStep))
          : null,
      onIncrease: allowSemanticAdjust
          ? () => _nudge(widget.keyboardStep, SplitterChangeSource.semantics)
          : null,
      onDecrease: allowSemanticAdjust
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
              widget.controller.value = SplitterPosition.fraction(dest);
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
  const _DragOverlay({required this.axis, this.blockerColor});

  final Axis axis;
  final Color? blockerColor;

  @override
  Widget build(BuildContext context) {
    // The Listener below hit-tests opaquely regardless of paint, so the color
    // is purely cosmetic - an explicit transparent barrier is honored.
    final color = blockerColor ?? Colors.transparent;

    return Positioned.fill(
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: axis.cursor,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: ColoredBox(color: color),
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
