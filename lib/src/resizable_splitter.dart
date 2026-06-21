// We intentionally expose imperative helpers instead of setters for ergonomics.
// ignore_for_file: use_setters_to_change_properties
// A robust, high-performance split view that plays nicely with platform views.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resizable_splitter/src/resizable_splitter_theme.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_solver.dart';

/// Re-export for clean imports when only Axis is needed.
export 'package:flutter/material.dart' show Axis;

/// Axis helpers to eliminate H/V duplication.
extension _AxisHelpers on Axis {
  bool get isH => this == Axis.horizontal;

  double size(Size s) => isH ? s.width : s.height;

  SystemMouseCursor get cursor =>
      isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;
}

/// Public handle details passed to [ResizableSplitter.handleBuilder].
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

/// A controller for managing splitter position (0.0–1.0).
///
/// Maintains the split ratio and exposes simple APIs to update or animate it.
/// A global pointer router prevents “stuck drags” when platform views steal
/// pointer events. The router attaches only when a [WidgetsBinding] is
/// available, so controllers created in pure Dart tests or before `runApp`
/// stay functional—the enhanced drag cleanup simply activates once Flutter is
/// initialized.
class SplitterController extends ValueNotifier<double> {
  /// Creates a splitter controller with the given initial ratio.
  SplitterController({double initialRatio = 0.5})
    : assert(
        initialRatio >= 0.0 && initialRatio <= 1.0,
        'initialRatio must be between 0.0 and 1.0',
      ),
      super(initialRatio);

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

  /// Sets the split ratio, sanitized into `[0, 1]`. Non-finite values are
  /// ignored, so the controller can never hold a value that would corrupt the
  /// layout, even when written directly instead of through [updateRatio] (and
  /// even when an overshooting animation curve runs past the bounds).
  @override
  set value(double newValue) {
    if (!newValue.isFinite) return;
    // Any value change that is not an animation tick (a drag, key press, reset,
    // or direct write) takes over from a running animation.
    if (!_isAnimationTick) _animator?.cancel();
    super.value = newValue.clamp(0.0, 1.0).toDouble();
  }

  /// Updates the ratio with an optional threshold to prevent chatty updates.
  void updateRatio(double newRatio, {double threshold = 0.002}) {
    final clamped = newRatio.clamp(0.0, 1.0);
    if ((clamped - value).abs() > threshold) {
      value = clamped;
    }
  }

  /// Resets the splitter to the specified position, defaulting to center.
  void reset([double to = 0.5]) {
    assert(to >= 0.0 && to <= 1.0, 'to must be between 0.0 and 1.0');
    value = to;
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
    if ((goal - value).abs() < 1e-7) {
      value = goal;
      return Future<void>.value();
    }
    final animator = _animator;
    if (animator == null) {
      value = goal;
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
/// - Extensive customization via colors and a custom [handleBuilder].
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
/// `Theme.of(context).extension<ResizableSplitterThemeOverrides>()`. When no
/// overrides are provided, colors fall back to the ambient [ThemeData]
/// (via [ColorScheme]) and numeric values fall back to the defaults documented
/// on each parameter.
class ResizableSplitter extends StatefulWidget {
  /// Builds a resizable splitter with the provided panels and configuration.
  const ResizableSplitter({
    required this.startPanel,
    required this.endPanel,
    super.key,
    this.controller,
    this.axis = Axis.horizontal,
    this.initialRatio = 0.5,
    this.minRatio = 0.0,
    this.maxRatio = 1.0,
    this.minPanelSize = 100.0,
    this.minStartPanelSize,
    this.minEndPanelSize,
    double? dividerThickness,
    this.dividerColor,
    this.dividerHoverColor,
    this.dividerActiveColor,
    this.onRatioChanged,
    this.onDragStart,
    this.onDragEnd,
    bool? enableKeyboard,
    bool? enableHaptics,
    double? keyboardStep,
    double? pageStep,
    this.semanticsLabel,
    this.blockerColor,
    bool? overlayEnabled,
    this.snapPoints,
    this.snapTolerance = 0.02,
    this.handleBuilder,
    this.holdScrollWhileDragging = false,
    double? handleHitSlop,
    this.doubleTapResetTo,
    this.resizable = true,
    this.onHandleTap,
    this.onHandleDoubleTap,
    this.crampedBehavior = CrampedBehavior.favorStart,
    UnboundedBehavior? unboundedBehavior,
    double? fallbackMainAxisExtent,
    bool? antiAliasingWorkaround,
  }) : enableKeyboard = enableKeyboard ?? true,
       _enableKeyboardExplicit = enableKeyboard != null,
       enableHaptics = enableHaptics ?? true,
       _enableHapticsExplicit = enableHaptics != null,
       overlayEnabled = overlayEnabled ?? true,
       _overlayEnabledExplicit = overlayEnabled != null,
       unboundedBehavior = unboundedBehavior ?? UnboundedBehavior.flexExpand,
       _unboundedBehaviorExplicit = unboundedBehavior != null,
       antiAliasingWorkaround = antiAliasingWorkaround ?? false,
       _antiAliasingWorkaroundExplicit = antiAliasingWorkaround != null,
       dividerThickness = dividerThickness ?? _defaultDividerThickness,
       _dividerThicknessExplicit = dividerThickness != null,
       keyboardStep = keyboardStep ?? _defaultKeyboardStep,
       _keyboardStepExplicit = keyboardStep != null,
       pageStep = pageStep ?? _defaultPageStep,
       _pageStepExplicit = pageStep != null,
       handleHitSlop = handleHitSlop ?? _defaultHandleHitSlop,
       _handleHitSlopExplicit = handleHitSlop != null,
       fallbackMainAxisExtent =
           fallbackMainAxisExtent ?? _defaultFallbackMainAxisExtent,
       _fallbackExtentExplicit = fallbackMainAxisExtent != null,
       assert(
         initialRatio >= 0.0 && initialRatio <= 1.0,
         'initialRatio must be between 0.0 and 1.0',
       ),
       assert(
         minRatio >= 0.0 && minRatio <= 1.0,
         'minRatio must be between 0.0 and 1.0',
       ),
       assert(
         maxRatio >= 0.0 && maxRatio <= 1.0,
         'maxRatio must be between 0.0 and 1.0',
       ),
       assert(minRatio < maxRatio, 'minRatio must be less than maxRatio'),
       assert(
         handleHitSlop == null || handleHitSlop >= 0,
         'handleHitSlop must be non-negative',
       ),
       assert(
         dividerThickness == null || dividerThickness >= 0,
         'dividerThickness must be non-negative',
       ),
       assert(minPanelSize >= 0, 'minPanelSize must be non-negative'),
       assert(
         minStartPanelSize == null || minStartPanelSize >= 0,
         'minStartPanelSize must be non-negative',
       ),
       assert(
         minEndPanelSize == null || minEndPanelSize >= 0,
         'minEndPanelSize must be non-negative',
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
  final Widget startPanel;

  /// The widget to display in the end position (right/bottom).
  final Widget endPanel;

  /// Optional controller for programmatic control and persistence.
  final SplitterController? controller;

  /// The axis along which to split (horizontal or vertical).
  final Axis axis;

  /// Initial split ratio if no controller is provided.
  final double initialRatio;

  /// Minimum allowed ratio (0.0 to 1.0).
  final double minRatio;

  /// Maximum allowed ratio (0.0 to 1.0).
  ///
  /// Keyboard shortcuts (Home/End/Page keys) clamp the controller value within
  /// [minRatio] and [maxRatio]. Layout still enforces pixel minimums, so under
  /// extreme constraints the visible split may differ slightly from the stored
  /// ratio while these caps are respected.
  final double maxRatio;

  /// Minimum size in pixels for either panel (fallback for the specific mins).
  final double minPanelSize;

  /// Minimum size for the start (left/top) panel. Defaults to [minPanelSize].
  /// If both panels' minimums cannot be satisfied, the start panel keeps its
  /// minimum and the end panel receives the remaining space.
  final double? minStartPanelSize;

  /// Minimum size for the end (right/bottom) panel. Defaults to [minPanelSize].
  final double? minEndPanelSize;

  /// Thickness of the divider handle in pixels.
  final double dividerThickness;
  final bool _dividerThicknessExplicit;

  /// Color of the divider in its idle state.
  final Color? dividerColor;

  /// Color of the divider when hovered.
  final Color? dividerHoverColor;

  /// Color of the divider when being dragged.
  final Color? dividerActiveColor;

  /// Called when the split ratio changes (e.g., dragging or keyboard).
  final ValueChanged<double>? onRatioChanged;

  /// Called when a drag gesture starts.
  final ValueChanged<double>? onDragStart;

  /// Called when a drag gesture ends.
  final ValueChanged<double>? onDragEnd;

  /// Whether to enable keyboard navigation with arrow keys.
  final bool enableKeyboard;
  final bool _enableKeyboardExplicit;

  /// Whether haptic feedback fires on drag start and keyboard adjustments.
  ///
  /// Defaults to true. On platforms without a haptic engine (web, most
  /// desktops) the calls are silent no-ops regardless.
  final bool enableHaptics;
  final bool _enableHapticsExplicit;

  /// Step applied with Arrow keys (e.g., 0.01 = 1%).
  final double keyboardStep;
  final bool _keyboardStepExplicit;

  /// Step applied with PageUp/PageDown keys (e.g., 0.1 = 10%).
  final double pageStep;
  final bool _pageStepExplicit;

  /// Accessibility label for the divider.
  final String? semanticsLabel;

  /// The blocked color when dragged.
  final Color? blockerColor;

  /// Whether the protective overlay is used while dragging.
  final bool overlayEnabled;
  final bool _overlayEnabledExplicit;

  /// Optional snap points (0–1). If close on drag end, snaps to the nearest.
  final List<double>? snapPoints;

  /// Max distance to snap to a snap point (0–1 range).
  final double snapTolerance;

  /// Custom handle builder to replace the inner “grip” UI.
  final Widget Function(BuildContext, SplitterHandleDetails)? handleBuilder;

  /// Whether to temporarily hold the nearest Scrollable's position while dragging.
  final bool holdScrollWhileDragging;

  /// Extra, invisible padding around the handle to make it easier to grab.
  final double handleHitSlop;
  final bool _handleHitSlopExplicit;

  /// Optional ratio to jump to on double-tap.
  final double? doubleTapResetTo;

  /// Whether the divider responds to drag gestures.
  final bool resizable;

  /// Called when the divider is tapped.
  final VoidCallback? onHandleTap;

  /// Called when the divider is double-tapped.
  final VoidCallback? onHandleDoubleTap;

  /// Policy for distributing space when both panels cannot meet their minimums.
  final CrampedBehavior crampedBehavior;

  /// Fallback layout behavior when constraints are unbounded along the main axis.
  final UnboundedBehavior unboundedBehavior;
  final bool _unboundedBehaviorExplicit;

  /// Extent in pixels to use when [unboundedBehavior] is [UnboundedBehavior.limitedBox].
  final double fallbackMainAxisExtent;
  final bool _fallbackExtentExplicit;

  /// Floors the leading panel size to whole pixels to avoid anti-alias gaps.
  final bool antiAliasingWorkaround;
  final bool _antiAliasingWorkaroundExplicit;

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
        initialRatio: widget.initialRatio,
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
        initialRatio: (_attachedController ?? oldWidget.controller!).value,
      );
    }

    final newController =
        widget.controller ??
        (_internalController ??= SplitterController(
          initialRatio: widget.initialRatio,
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
      controller.value = target;
      return Future<void>.value();
    }
    _animBegin = controller.value;
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
    controller.value = value;
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

    final dividerThickness = widget._dividerThicknessExplicit
        ? widget.dividerThickness
        : theme.dividerThickness;

    final keyboardStep = widget._keyboardStepExplicit
        ? widget.keyboardStep
        : theme.keyboardStep;

    final pageStep = widget._pageStepExplicit
        ? widget.pageStep
        : theme.pageStep;

    final handleHitSlop = widget._handleHitSlopExplicit
        ? widget.handleHitSlop
        : theme.handleHitSlop;

    final overlayEnabled = widget._overlayEnabledExplicit
        ? widget.overlayEnabled
        : theme.overlayEnabled;
    final enableKeyboard = widget._enableKeyboardExplicit
        ? widget.enableKeyboard
        : theme.enableKeyboard;
    final enableHaptics = widget._enableHapticsExplicit
        ? widget.enableHaptics
        : theme.enableHaptics;

    // The divider reserves its visible thickness plus the invisible grab slop
    // on either side. Panels share whatever is left, so the slop widens the
    // hit target instead of silently overlapping the panels.
    final dividerExtent = dividerThickness + 2 * handleHitSlop;

    final blockerColor = widget.blockerColor ?? theme.blockerColor;
    final dividerColor = widget.dividerColor ?? theme.dividerColor;
    final dividerHoverColor =
        widget.dividerHoverColor ?? theme.dividerHoverColor;
    final dividerActiveColor =
        widget.dividerActiveColor ?? theme.dividerActiveColor;

    final unboundedBehavior = widget._unboundedBehaviorExplicit
        ? widget.unboundedBehavior
        : theme.unboundedBehavior;

    final fallbackExtent = widget._fallbackExtentExplicit
        ? widget.fallbackMainAxisExtent
        : theme.fallbackMainAxisExtent;

    final antiAliasingWorkaround = widget._antiAliasingWorkaroundExplicit
        ? widget.antiAliasingWorkaround
        : theme.antiAliasingWorkaround;

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
                        Expanded(child: widget.startPanel),
                        Expanded(child: widget.endPanel),
                      ],
                    );
                  }

                  return ValueListenableBuilder<double>(
                    valueListenable: controller,
                    builder: (_, ratio, _) {
                      final availableSize = (boundedMax - dividerExtent).clamp(
                        0.0,
                        double.infinity,
                      );
                      return _buildBounded(
                        ratio: ratio,
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
                        dividerHoverColor: dividerHoverColor,
                        dividerActiveColor: dividerActiveColor,
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
                ? [
                    Expanded(child: widget.startPanel),
                    Expanded(child: widget.endPanel),
                  ]
                : [widget.startPanel, widget.endPanel],
          );
        }

        return ValueListenableBuilder<double>(
          valueListenable: controller,
          builder: (_, ratio, _) {
            final availableSize = (maxSize - dividerExtent).clamp(
              0.0,
              double.infinity,
            );

            return _buildBounded(
              ratio: ratio,
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
              dividerHoverColor: dividerHoverColor,
              dividerActiveColor: dividerActiveColor,
              antiAliasingWorkaround: antiAliasingWorkaround,
              controller: controller,
            );
          },
        );
      },
    );
  }

  static SplitterConstraintPolicy _policyFor(CrampedBehavior behavior) =>
      switch (behavior) {
        CrampedBehavior.favorStart => SplitterConstraintPolicy.favorStart,
        CrampedBehavior.favorEnd => SplitterConstraintPolicy.favorEnd,
        CrampedBehavior.proportionallyClamp =>
          SplitterConstraintPolicy.proportional,
      };

  Widget _buildBounded({
    required double ratio,
    required double availableSize,
    required double dividerThickness,
    required bool enableKeyboard,
    required bool enableHaptics,
    required double keyboardStep,
    required double pageStep,
    required bool overlayEnabled,
    required double handleHitSlop,
    required Color? blockerColor,
    required Color? dividerColor,
    required Color? dividerHoverColor,
    required Color? dividerActiveColor,
    required bool antiAliasingWorkaround,
    required SplitterController controller,
  }) {
    // Raw configured minimums (not pre-clamped): the solver clamps internally
    // and uses the raw values for proportional distribution, so a cramped
    // layout keeps its configured proportions instead of collapsing to 50/50.
    final minStart = widget.minStartPanelSize ?? widget.minPanelSize;
    final minEnd = widget.minEndPanelSize ?? widget.minPanelSize;

    // One solver drives both the layout here and every ratio decision inside
    // the handle, so the two can never disagree on the legal bounds, and an
    // inverted clamp (the historic cramped-drag crash) is impossible.
    final solver = SplitterSolver(
      available: availableSize,
      start: SplitterPaneConstraints(minExtent: minStart),
      end: SplitterPaneConstraints(minExtent: minEnd),
      minStartFraction: widget.minRatio,
      maxStartFraction: widget.maxRatio,
      policy: _policyFor(widget.crampedBehavior),
    );

    final solution = solver.solve(
      SplitterPosition.fraction(ratio),
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
      snapToDevicePixels: antiAliasingWorkaround,
    );

    final first = solution.startExtent;
    final second = solution.endExtent;

    return Flex(
      direction: widget.axis,
      children: [
        SizedBox(
          width: widget.axis.isH ? first : null,
          height: widget.axis.isH ? null : first,
          child: widget.startPanel,
        ),
        _DividerHandle(
          axis: widget.axis,
          controller: controller,
          thickness: dividerThickness,
          solver: solver,
          solution: solution,
          blockerColor: blockerColor,
          dividerColor: dividerColor,
          dividerHoverColor: dividerHoverColor,
          dividerActiveColor: dividerActiveColor,
          onRatioChanged: widget.onRatioChanged,
          onDragStart: widget.onDragStart,
          onDragEnd: widget.onDragEnd,
          enableKeyboard: enableKeyboard && widget.resizable,
          enableHaptics: enableHaptics,
          keyboardStep: keyboardStep,
          pageStep: pageStep,
          focusNode: _focusNode,
          semanticsLabel: widget.semanticsLabel,
          overlayEnabled: overlayEnabled && widget.resizable,
          snapPoints: widget.snapPoints,
          snapTolerance: widget.snapTolerance,
          handleBuilder: widget.handleBuilder,
          holdScrollWhileDragging:
              widget.holdScrollWhileDragging && widget.resizable,
          handleHitSlop: handleHitSlop,
          doubleTapResetTo: widget.doubleTapResetTo,
          resizable: widget.resizable,
          onTap: widget.onHandleTap,
          onDoubleTap: widget.onHandleDoubleTap,
        ),
        SizedBox(
          width: widget.axis.isH ? second : null,
          height: widget.axis.isH ? null : second,
          child: widget.endPanel,
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
    required this.dividerHoverColor,
    required this.dividerActiveColor,
    required this.onRatioChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.enableKeyboard,
    required this.enableHaptics,
    required this.keyboardStep,
    required this.pageStep,
    required this.focusNode,
    required this.semanticsLabel,
    required this.overlayEnabled,
    required this.snapPoints,
    required this.snapTolerance,
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
  final Color? dividerColor;
  final Color? blockerColor;
  final Color? dividerHoverColor;
  final Color? dividerActiveColor;
  final ValueChanged<double>? onRatioChanged;
  final ValueChanged<double>? onDragStart;
  final ValueChanged<double>? onDragEnd;
  final bool enableKeyboard;
  final bool enableHaptics;
  final double keyboardStep;
  final double pageStep;
  final FocusNode focusNode;
  final String? semanticsLabel;
  final bool overlayEnabled;
  final List<double>? snapPoints;
  final double snapTolerance;
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

  late BoxDecoration _idleDecoration;
  late BoxDecoration _hoverDecoration;
  late BoxDecoration _activeDecoration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDecorations();
  }

  @override
  void didUpdateWidget(_DividerHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dividerColor != widget.dividerColor ||
        oldWidget.dividerHoverColor != widget.dividerHoverColor ||
        oldWidget.dividerActiveColor != widget.dividerActiveColor) {
      _updateDecorations();
    }
  }

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

  void _updateDecorations() {
    final cs = Theme.of(context).colorScheme;
    final theme = ResizableSplitterTheme.of(context);
    // Calm splitter colors derived from the surrounding theme unless overridden.
    final baseColor =
        widget.dividerColor ?? theme.dividerColor ?? cs.outlineVariant;
    final hoverColor =
        widget.dividerHoverColor ??
        theme.dividerHoverColor ??
        cs.onSurface.withAlpha(20);
    final activeColor =
        widget.dividerActiveColor ??
        theme.dividerActiveColor ??
        cs.onSurface.withAlpha(31);

    _idleDecoration = BoxDecoration(color: baseColor);
    _hoverDecoration = BoxDecoration(color: hoverColor);
    _activeDecoration = BoxDecoration(color: activeColor);
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
    widget.onDragStart?.call(widget.solution.effectiveFraction);
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

    final previous = widget.controller.value;
    widget.controller.updateRatio(newRatio);
    if ((widget.controller.value - previous).abs() > 1e-9) {
      widget.onRatioChanged?.call(widget.controller.value);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _stopDrag();
  }

  void _onDragCancel() {
    _stopDrag();
  }

  void _stopDrag() {
    final snapped = _maybeSnap(widget.controller.value);

    // No snap point claimed the release: commit the exact final ratio. The
    // per-update threshold can otherwise leave the handle a fraction short of
    // where the pointer actually let go.
    if (snapped == null && _lastDragRatio != null) {
      final previous = widget.controller.value;
      widget.controller.updateRatio(_lastDragRatio!, threshold: 0);
      if ((widget.controller.value - previous).abs() > 1e-9) {
        widget.onRatioChanged?.call(widget.controller.value);
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
      widget.onDragEnd?.call(snapped ?? widget.controller.value);
    }
  }

  double? _maybeSnap(double value) {
    final points = widget.snapPoints;
    if (points == null || points.isEmpty) return null;
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
    if (bestDist <= widget.snapTolerance) {
      if ((nearest - widget.controller.value).abs() > 1e-9) {
        final previous = widget.controller.value;
        widget.controller.updateRatio(nearest, threshold: 0);
        if ((widget.controller.value - previous).abs() > 1e-9) {
          widget.onRatioChanged?.call(widget.controller.value);
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

  void _nudge(double delta) {
    if (!widget.resizable) return;

    // Step from the current *effective* position (re-solved fresh, so repeated
    // presses without a rebuild still accumulate), then re-solve to clamp. This
    // moves the divider by the step in what the user actually sees, instead of
    // nudging a stored value through a dead band.
    final previous = widget.controller.value;
    final base = widget.solver
        .solve(SplitterPosition.fraction(previous))
        .effectiveFraction;
    final newRatio = widget.solver
        .solve(SplitterPosition.fraction(base + delta))
        .effectiveFraction;
    widget.controller.value = newRatio;
    if ((widget.controller.value - previous).abs() > 1e-9) {
      widget.onRatioChanged?.call(widget.controller.value);
      _haptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    BoxDecoration currentDecoration;
    if (_isDragging) {
      currentDecoration = _activeDecoration;
    } else if (_isHovering) {
      currentDecoration = _hoverDecoration;
    } else {
      currentDecoration = _idleDecoration;
    }

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
                final startValue = widget.controller.value;
                unawaited(
                  widget.controller.animateTo(target).then((_) {
                    if (!mounted) return;
                    final updated = widget.controller.value;
                    if ((updated - startValue).abs() > 1e-9) {
                      widget.onRatioChanged?.call(updated);
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

    String formatPercent(double ratio) {
      final effective = _effectiveRatio(ratio).clamp(0.0, 1.0);
      return '${(effective * 100).round()}%';
    }

    final currentRatio = widget.controller.value;

    // Screen reader actions & value.
    final allowSemanticAdjust = widget.resizable && widget.enableKeyboard;

    divider = Semantics(
      label:
          widget.semanticsLabel ??
          (widget.axis.isH
              ? 'Drag to resize left and right panels.'
              : 'Drag to resize top and bottom panels.'),
      value: formatPercent(currentRatio),
      increasedValue: allowSemanticAdjust
          ? formatPercent(currentRatio + widget.keyboardStep)
          : null,
      decreasedValue: allowSemanticAdjust
          ? formatPercent(currentRatio - widget.keyboardStep)
          : null,
      onIncrease: allowSemanticAdjust
          ? () => _nudge(widget.keyboardStep)
          : null,
      onDecrease: allowSemanticAdjust
          ? () => _nudge(-widget.keyboardStep)
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
              _nudge(intent.delta);
              return null;
            },
          ),
          _JumpIntent: CallbackAction<_JumpIntent>(
            onInvoke: (intent) {
              final previous = widget.controller.value;
              final dest = intent.toMin
                  ? widget.solver
                        .solve(const SplitterPosition.fraction(0))
                        .effectiveFraction
                  : widget.solver
                        .solve(const SplitterPosition.fraction(1))
                        .effectiveFraction;
              widget.controller.value = dest;
              if ((widget.controller.value - previous).abs() > 1e-9) {
                widget.onRatioChanged?.call(widget.controller.value);
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
