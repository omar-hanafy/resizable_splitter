// We intentionally expose imperative helpers instead of setters for ergonomics.
// ignore_for_file: use_setters_to_change_properties
// A robust, high-performance split view that plays nicely with platform views.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resizable_splitter/src/resizable_splitter_theme.dart';

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
      super(initialRatio) {
    _globalRouter.register(this);
  }

  static final _globalRouter = _GlobalPointerRouter();

  static const String _multiAttachErrorMessage =
      'SplitterController is already attached to another ResizableSplitter.\n'
      'A controller must not be shared across multiple ResizableSplitter instances simultaneously.';

  /// Emits `true` while the user is dragging the handle.
  ValueListenable<bool> get isDraggingListenable => _isDragging;

  /// A convenience getter for [_isDragging] as a boolean.
  bool get isDragging => _isDragging.value;
  final _isDragging = ValueNotifier<bool>(false);
  Timer? _animationTimer;
  Completer<void>? _animationCompleter;
  Object? _owner;

  /// Exposes the widget currently owning this controller in debug/test builds.
  @visibleForTesting
  Object? get debugOwner => _owner;

  void _attach(Object owner) {
    assert(() {
      if (_owner != null && !identical(_owner, owner)) {
        throw FlutterError(_multiAttachErrorMessage);
      }
      return true;
    }(), _multiAttachErrorMessage);
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
    _cancelActiveAnimation();
    _isDragging.dispose();
    super.dispose();
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

  /// Convenience animation (no Ticker dependency).
  Future<void> animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 160),
    Curve curve = Curves.easeOut,
    int frames = 12,
  }) {
    final goal = target.clamp(0.0, 1.0);
    if ((goal - value).abs() < 1e-7) {
      value = goal;
      return Future<void>.value();
    }

    if (duration <= Duration.zero || frames <= 0) {
      _cancelActiveAnimation();
      value = goal;
      return Future<void>.value();
    }

    _cancelActiveAnimation();

    final totalFrames = math.max(1, frames);
    final start = value;
    final completer = Completer<void>();
    final intervalMicros = math.max(1, duration.inMicroseconds ~/ totalFrames);
    final interval = Duration(microseconds: intervalMicros);
    var frame = 0;

    _animationCompleter = completer;
    _animationTimer = Timer.periodic(interval, (timer) {
      frame += 1;
      final progress = curve.transform(math.min(1, frame / totalFrames));
      value = start + (goal - start) * progress;

      if (frame >= totalFrames) {
        timer.cancel();
        _animationTimer = null;
        value = goal;
        if (!completer.isCompleted) {
          completer.complete();
        }
        _animationCompleter = null;
      }
    });

    return completer.future;
  }

  void _cancelActiveAnimation() {
    _animationTimer?.cancel();
    _animationTimer = null;
    if (_animationCompleter != null && !_animationCompleter!.isCompleted) {
      _animationCompleter!.complete();
    }
    _animationCompleter = null;
  }

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

  void register(SplitterController c) {
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
/// splitter defaults to two [Expanded] children without the divider. Opt into
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

class _ResizableSplitterState extends State<ResizableSplitter> {
  late final FocusNode _focusNode;
  SplitterController? _internalController;
  SplitterController? _attachedController;

  SplitterController get _effectiveController =>
      widget.controller ??
      (_internalController ??= SplitterController(
        initialRatio: widget.initialRatio,
      ));

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ResizableSplitterHandle');
    final controller = _effectiveController.._attach(this);
    _attachedController = controller;
  }

  @override
  void didUpdateWidget(ResizableSplitter oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newController =
        widget.controller ??
        (_internalController ??= SplitterController(
          initialRatio: widget.initialRatio,
        ));

    if (!identical(_attachedController, newController)) {
      _attachedController?._detach(this);

      if (oldWidget.controller == null && widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      }

      newController._attach(this);
      _attachedController = newController;
    }
  }

  @override
  void dispose() {
    _attachedController?._detach(this);
    _focusNode.dispose();
    _internalController?.dispose();
    super.dispose();
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
                      final availableSize = (boundedMax - dividerThickness)
                          .clamp(0.0, double.infinity);
                      return _buildBounded(
                        ratio: ratio,
                        availableSize: availableSize,
                        dividerThickness: dividerThickness,
                        enableKeyboard: enableKeyboard,
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
            final availableSize = (maxSize - dividerThickness).clamp(
              0.0,
              double.infinity,
            );

            return _buildBounded(
              ratio: ratio,
              availableSize: availableSize,
              dividerThickness: dividerThickness,
              enableKeyboard: enableKeyboard,
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

  Widget _buildBounded({
    required double ratio,
    required double availableSize,
    required double dividerThickness,
    required bool enableKeyboard,
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
    final minStart = (widget.minStartPanelSize ?? widget.minPanelSize).clamp(
      0.0,
      availableSize,
    );
    final minEnd = (widget.minEndPanelSize ?? widget.minPanelSize).clamp(
      0.0,
      availableSize,
    );

    double first;
    double second;

    if (availableSize <= 0) {
      first = 0;
      second = 0;
    } else {
      final pixelMinRatio = (minStart / availableSize).clamp(0.0, 1.0);
      final pixelMaxRatio = (1.0 - minEnd / availableSize).clamp(0.0, 1.0);
      final minR = math.max(widget.minRatio, pixelMinRatio);
      final maxR = math.min(widget.maxRatio, pixelMaxRatio);

      double effectiveRatio;
      if (minR <= maxR) {
        effectiveRatio = ratio.clamp(minR, maxR);
      } else {
        final sum = minStart + minEnd;
        effectiveRatio = switch (widget.crampedBehavior) {
          CrampedBehavior.favorStart => minR,
          CrampedBehavior.favorEnd => maxR,
          CrampedBehavior.proportionallyClamp =>
            sum <= 0 ? 0.5 : (minStart / sum).clamp(0.0, 1.0),
        };
      }

      first = availableSize * effectiveRatio;
      if (antiAliasingWorkaround) {
        first = first.floorToDouble();
        final maxAllowed = (availableSize - minEnd).clamp(0.0, availableSize);
        if (minStart <= maxAllowed) {
          first = first.clamp(minStart, maxAllowed);
        } else {
          first = switch (widget.crampedBehavior) {
            CrampedBehavior.favorStart => minStart,
            CrampedBehavior.favorEnd => maxAllowed,
            CrampedBehavior.proportionallyClamp =>
              (availableSize *
                      (minStart + minEnd <= 0
                          ? 0.5
                          : (minStart / (minStart + minEnd)).clamp(0.0, 1.0)))
                  .clamp(0.0, availableSize),
          };
        }
      }
      second = (availableSize - first).clamp(0.0, availableSize);
    }

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
          minRatio: widget.minRatio,
          maxRatio: widget.maxRatio,
          minStart: minStart,
          minEnd: minEnd,
          maxSize: availableSize,
          crampedBehavior: widget.crampedBehavior,
          blockerColor: blockerColor,
          dividerColor: dividerColor,
          dividerHoverColor: dividerHoverColor,
          dividerActiveColor: dividerActiveColor,
          onRatioChanged: widget.onRatioChanged,
          onDragStart: widget.onDragStart,
          onDragEnd: widget.onDragEnd,
          enableKeyboard: enableKeyboard && widget.resizable,
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
    required this.minRatio,
    required this.maxRatio,
    required this.minStart,
    required this.minEnd,
    required this.maxSize,
    required this.crampedBehavior,
    required this.dividerColor,
    required this.blockerColor,
    required this.dividerHoverColor,
    required this.dividerActiveColor,
    required this.onRatioChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.enableKeyboard,
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
  final double minRatio;
  final double maxRatio;
  final double minStart;
  final double minEnd;
  final double maxSize;
  final CrampedBehavior crampedBehavior;
  final Color? dividerColor;
  final Color? blockerColor;
  final Color? dividerHoverColor;
  final Color? dividerActiveColor;
  final ValueChanged<double>? onRatioChanged;
  final ValueChanged<double>? onDragStart;
  final ValueChanged<double>? onDragEnd;
  final bool enableKeyboard;
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
  OverlayEntry? _dragOverlay;
  int? _activePointer;
  ScrollHoldController? _scrollHold;
  final List<_PendingPointer> _pendingPointers = <_PendingPointer>[];

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
    widget.controller._setDragging(true);

    _dragStartRatio = widget.controller.value;
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

    unawaited(HapticFeedback.selectionClick());
    widget.focusNode.requestFocus();
    widget.onDragStart?.call(widget.controller.value);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging ||
        _dragStartPosition == null ||
        _dragStartRatio == null ||
        widget.maxSize <= 0) {
      return;
    }

    final currentPos = widget.axis.isH
        ? details.globalPosition.dx
        : details.globalPosition.dy;
    final delta = currentPos - _dragStartPosition!;
    final deltaRatio = delta / widget.maxSize;

    var newRatio = _dragStartRatio! + deltaRatio;

    final minR = math.max(
      widget.minRatio,
      (widget.minStart / widget.maxSize).clamp(0.0, 1.0),
    );
    final maxR = math.min(
      widget.maxRatio,
      (1.0 - widget.minEnd / widget.maxSize).clamp(0.0, 1.0),
    );

    newRatio = newRatio.clamp(minR, maxR);

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
    if (widget.maxSize <= 0) return null;

    final minR = math.max(
      widget.minRatio,
      (widget.minStart / widget.maxSize).clamp(0.0, 1.0),
    );
    final maxR = math.min(
      widget.maxRatio,
      (1.0 - widget.minEnd / widget.maxSize).clamp(0.0, 1.0),
    );

    var nearest = value;
    var bestDist = double.infinity;
    for (final p in points) {
      final d = (value - p).abs();
      if (d < bestDist) {
        bestDist = d;
        nearest = p;
      }
    }
    if (bestDist <= widget.snapTolerance) {
      final bounded = minR <= maxR ? nearest.clamp(minR, maxR) : minR;
      if ((bounded - widget.controller.value).abs() > 1e-9) {
        final previous = widget.controller.value;
        widget.controller.updateRatio(bounded, threshold: 0);
        if ((widget.controller.value - previous).abs() > 1e-9) {
          widget.onRatioChanged?.call(widget.controller.value);
        }
      }
      return bounded;
    }
    return null;
  }

  void _insertOverlay() {
    if (_dragOverlay != null) return;

    _dragOverlay = OverlayEntry(
      builder: (context) =>
          _DragOverlay(axis: widget.axis, blockerColor: widget.blockerColor),
    );

    // Use the root overlay so it sits above platform views.
    Overlay.of(context, rootOverlay: true).insert(_dragOverlay!);
  }

  void _removeOverlay() {
    if (_dragOverlay?.mounted ?? false) {
      _dragOverlay?.remove();
    }
    _dragOverlay = null;
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

  double _effectiveRatio(double ratio) {
    if (widget.maxSize <= 0) {
      return ratio.clamp(widget.minRatio, widget.maxRatio).clamp(0.0, 1.0);
    }

    final pixelMinRatio = (widget.minStart / widget.maxSize).clamp(0.0, 1.0);
    final pixelMaxRatio = (1.0 - widget.minEnd / widget.maxSize).clamp(
      0.0,
      1.0,
    );
    final minR = math.max(widget.minRatio, pixelMinRatio);
    final maxR = math.min(widget.maxRatio, pixelMaxRatio);

    if (minR <= maxR) {
      return ratio.clamp(minR, maxR).clamp(0.0, 1.0);
    }

    final minClamped = minR.clamp(0.0, 1.0);
    final maxClamped = maxR.clamp(0.0, 1.0);

    switch (widget.crampedBehavior) {
      case CrampedBehavior.favorStart:
        return minClamped;
      case CrampedBehavior.favorEnd:
        return maxClamped;
      case CrampedBehavior.proportionallyClamp:
        final sum = widget.minStart + widget.minEnd;
        final fallback = sum <= 0
            ? 0.5
            : (widget.minStart / sum).clamp(0.0, 1.0);
        return fallback;
    }
  }

  void _nudge(double delta) {
    if (!widget.resizable) return;

    final previous = widget.controller.value;
    final newRatio = (previous + delta).clamp(widget.minRatio, widget.maxRatio);
    widget.controller.value = newRatio;
    if ((widget.controller.value - previous).abs() > 1e-9) {
      widget.onRatioChanged?.call(widget.controller.value);
    }
    unawaited(HapticFeedback.selectionClick());
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

    if (widget.handleHitSlop > 0) {
      final lr = widget.axis.isH ? 0.0 : widget.handleHitSlop;
      final tb = widget.axis.isH ? widget.handleHitSlop : 0.0;
      divider = Padding(
        padding: EdgeInsets.fromLTRB(lr, tb, lr, tb),
        child: divider,
      );
    }

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
      divider = FocusableActionDetector(
        focusNode: widget.focusNode,
        shortcuts: <LogicalKeySet, Intent>{
          // Fine step
          LogicalKeySet(
            widget.axis.isH
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowUp,
          ): _AdjustIntent(
            -widget.keyboardStep,
          ),
          LogicalKeySet(
            widget.axis.isH
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown,
          ): _AdjustIntent(
            widget.keyboardStep,
          ),
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
              final previous = widget.controller.value;
              final newRatio = (previous + intent.delta).clamp(
                widget.minRatio,
                widget.maxRatio,
              );
              widget.controller.value = newRatio;
              if ((widget.controller.value - previous).abs() > 1e-9) {
                widget.onRatioChanged?.call(widget.controller.value);
              }
              unawaited(HapticFeedback.selectionClick());
              return null;
            },
          ),
          _JumpIntent: CallbackAction<_JumpIntent>(
            onInvoke: (intent) {
              final previous = widget.controller.value;
              final dest = intent.toMin ? widget.minRatio : widget.maxRatio;
              widget.controller.value = dest;
              if ((widget.controller.value - previous).abs() > 1e-9) {
                widget.onRatioChanged?.call(widget.controller.value);
              }
              unawaited(HapticFeedback.selectionClick());
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
    // A fully transparent color can be optimized away; use 1 alpha.
    final defaultColor = Theme.of(context).colorScheme.scrim.withAlpha(1);
    final color = blockerColor == Colors.transparent
        ? defaultColor
        : blockerColor ?? defaultColor;

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
