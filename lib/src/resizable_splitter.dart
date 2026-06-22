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
import 'package:resizable_splitter/src/split_change_details.dart';

part 'split_controller.dart';
part 'split_handle.dart';
part 'split_restoration.dart';

/// Axis helpers to eliminate H/V duplication.
extension _AxisHelpers on Axis {
  bool get isH => this == Axis.horizontal;

  double size(Size s) => isH ? s.width : s.height;

  SystemMouseCursor get cursor =>
      isH ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;
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
/// [UnboundedBehavior.useFallbackExtent] (via [ResizableSplitterTheme] or the
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
    this.dragBarrierColor,
    this.dragBarrierBuilder,
    this.shieldPlatformViews,
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
    this.fallbackExtent,
    this.snapToPhysicalPixels,
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
         fallbackExtent == null || fallbackExtent > 0,
         'fallbackExtent must be greater than zero',
       );
  static const double _defaultDividerThickness = 6;
  static const double _defaultKeyboardStep = 0.01;
  static const double _defaultPageStep = 0.1;
  static const double _defaultInteractiveExtent = 48;
  static const double _defaultFallbackExtent = 500;

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
  /// color, the [SplitterDividerStyle.interactiveExtent] grab target, and a
  /// custom grip [SplitterDividerStyle.builder]. Unset fields fall back to
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

  /// Called when a drag gesture ends, balancing every [onChangeStart] with
  /// exactly one end so a consumer can pair them (e.g. to clear a "dragging"
  /// flag). [SplitterChangeDetails.end] reports how it ended:
  /// [SplitterChangeEnd.committed] for a normal release (the source is
  /// [SplitterChangeSource.snap] when a snap point claimed it) or
  /// [SplitterChangeEnd.canceled] for a system cancel (nothing is committed).
  /// The one unbalanced case is a drag force-ended by reconfiguring or disposing
  /// the splitter mid-gesture, which fires no end.
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
  final Color? dragBarrierColor;

  /// Builds the visual of the drag barrier - the overlay that shields embedded
  /// platform views from stealing pointer events while dragging. The framework
  /// always keeps the opaque hit shield; this only replaces what it looks like
  /// (the default is a [dragBarrierColor] fill). Only used when the overlay is
  /// enabled.
  final Widget Function(BuildContext context)? dragBarrierBuilder;

  /// Whether the protective overlay is used while dragging. Defaults to true.
  final bool? shieldPlatformViews;

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
  /// axis. Defaults to [UnboundedBehavior.shrinkToChildren].
  final UnboundedBehavior? unboundedBehavior;

  /// Extent in pixels to use when [unboundedBehavior] is
  /// [UnboundedBehavior.useFallbackExtent]. Defaults to 500.
  final double? fallbackExtent;

  /// Floors the leading panel size to whole physical pixels to avoid anti-alias
  /// gaps. Defaults to false.
  final bool? snapToPhysicalPixels;

  /// Restoration id for persisting the divider position across app restarts.
  ///
  /// When non-null the splitter saves its position into the ambient
  /// [RestorationScope], so it is restored after the app is killed and
  /// relaunched (see [RestorationMixin]). Restoration works with the internal
  /// controller as well as an external one. Null disables restoration.
  final String? restorationId;

  @override
  State<ResizableSplitter> createState() => _ResizableSplitterState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<Axis>('axis', axis))
      ..add(DiagnosticsProperty<bool>('resizable', resizable))
      ..add(
        DiagnosticsProperty<SplitterPosition>(
          'initialPosition',
          initialPosition,
        ),
      )
      ..add(
        FlagProperty(
          'controller',
          value: controller != null,
          ifTrue: 'external',
          ifFalse: 'internal',
          showName: true,
        ),
      )
      ..add(
        DiagnosticsProperty<SplitterPaneConstraints>(
          'startConstraints',
          startConstraints,
        ),
      )
      ..add(
        DiagnosticsProperty<SplitterPaneConstraints>(
          'endConstraints',
          endConstraints,
        ),
      )
      ..add(
        EnumProperty<SplitterConstraintPolicy>(
          'constraintPolicy',
          constraintPolicy,
        ),
      )
      ..add(EnumProperty<SplitterSurplusPolicy>('surplusPolicy', surplusPolicy))
      ..add(
        FlagProperty(
          'deferredResize',
          value: deferredResize,
          ifTrue: 'deferred',
        ),
      )
      ..add(StringProperty('restorationId', restorationId, defaultValue: null));
  }
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

  // The solver inputs captured at the last build (null before the first). Lets
  // animateTo resolve a target through the same configuration the layout draws.
  SplitterSolverConfig? _solverConfig;

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
    if (controller != null) {
      _restorablePosition.value = controller.value.position;
    }
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
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => disposing.dispose(),
          );
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
    // A new run supersedes any in-flight one - resolving it canceled - before any
    // shortcut can return, so a fresh animateTo can never leave the old run alive.
    _resolveSession(SplitterAnimationStatus.canceled);

    final controller = _attachedController ?? _effectiveController;
    // Resolve the requested fraction through the solver so the run targets a
    // position the divider can actually reach (clamped by the constraints).
    // "completed" then means the divider arrived there, never a target clamped
    // off-screen, and there is no stall while an unreachable request runs past
    // the edge. The uncollapsed solver is used because a fresh animateTo clears
    // any collapse (see _setAnimatedPosition).
    final available = controller.layout?.availableExtent ?? 0.0;
    final config = _solverConfig;
    final resolved = (available > 0 && config != null)
        ? config
              .solverFor(available)
              .solve(SplitterPosition.fraction(target))
              .effectiveFraction
        : target;

    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable ||
        duration <= Duration.zero ||
        (resolved - controller.effectiveFraction).abs() < 1e-7) {
      controller.jumpTo(SplitterPosition.fraction(resolved));
      return Future<SplitterAnimationStatus>.value(
        SplitterAnimationStatus.completed,
      );
    }
    final session = _AnimationSession(
      controller: controller,
      begin: controller.effectiveFraction,
      end: resolved,
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
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final controller = _attachedController ?? _internalController;
    final layout = controller?.layout;
    properties
      ..add(
        DiagnosticsProperty<SplitterLayout?>(
          'layout',
          layout,
          defaultValue: null,
        ),
      )
      ..add(
        EnumProperty<SplitterResolution?>(
          'resolution',
          layout?.resolution,
          defaultValue: null,
        ),
      )
      ..add(
        FlagProperty(
          'animating',
          value: _animSession != null,
          ifTrue: 'animating',
        ),
      )
      ..add(
        FlagProperty(
          'previewing',
          value: _previewFraction != null,
          ifTrue: 'previewing',
        ),
      );
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
    final interactiveExtent =
        dividerStyle?.interactiveExtent ??
        themeDivider?.interactiveExtent ??
        ResizableSplitter._defaultInteractiveExtent;
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
    final shieldPlatformViews =
        widget.shieldPlatformViews ?? theme.shieldPlatformViews ?? true;
    final enableKeyboard =
        widget.enableKeyboard ?? theme.enableKeyboard ?? true;
    final enableHaptics = widget.enableHaptics ?? theme.enableHaptics ?? true;

    // The divider reserves only its visible thickness (not the interactive grab
    // target): any extent beyond the bar is applied by the catcher overlay in
    // _buildBounded, which sits on top of the panels and overlaps their edges
    // instead of reducing panel layout. Decoupling the grab region (overlay)
    // from the layout footprint (Flex) makes it structurally impossible for the
    // target to eat layout. The footprint is also clamped to the container per
    // layout below, so a parent smaller than the thickness shrinks the divider
    // to fit rather than overflowing.

    final dragBarrierColor = widget.dragBarrierColor ?? theme.dragBarrierColor;

    final unboundedBehavior =
        widget.unboundedBehavior ??
        theme.unboundedBehavior ??
        UnboundedBehavior.shrinkToChildren;

    final fallbackExtent =
        widget.fallbackExtent ??
        theme.fallbackExtent ??
        ResizableSplitter._defaultFallbackExtent;

    final snapToPhysicalPixels =
        widget.snapToPhysicalPixels ?? theme.snapToPhysicalPixels ?? false;

    // The geometry-input channel that flows down to the layout layer. Captured
    // once per build and cached so animateTo can resolve a target the same way
    // the layout will draw it; in 2.1 this is exactly what the seam widget
    // forwards to the render object.
    final solverConfig = SplitterSolverConfig(
      start: widget.startConstraints,
      end: widget.endConstraints,
      minStartFraction: widget.minStartFraction,
      maxStartFraction: widget.maxStartFraction,
      policy: widget.constraintPolicy,
      surplusPolicy: widget.surplusPolicy,
      devicePixelRatio: MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
      snapToPhysicalPixels: snapToPhysicalPixels,
    );
    _solverConfig = solverConfig;

    final controller = _attachedController ?? _effectiveController;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSize = widget.axis.size(constraints.biggest);

        if (!maxSize.isFinite || maxSize <= 0) {
          if (unboundedBehavior == UnboundedBehavior.useFallbackExtent) {
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
                        shieldPlatformViews: shieldPlatformViews,
                        interactiveExtent: interactiveExtent,
                        dragBarrierColor: dragBarrierColor,
                        dividerColor: dividerColor,
                        handleBuilder: handleBuilder,
                        config: solverConfig,
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

          // shrinkToChildren fallback. Expanded requires a bounded main axis - under
          // a truly unbounded constraint RenderFlex throws ("children have
          // non-zero flex but incoming constraints are unbounded"). So only
          // flex when finite (e.g. a zero extent); otherwise let the panels
          // take their intrinsic size. Use useFallbackExtent for a working splitter
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
              shieldPlatformViews: shieldPlatformViews,
              interactiveExtent: interactiveExtent,
              dragBarrierColor: dragBarrierColor,
              dividerColor: dividerColor,
              handleBuilder: handleBuilder,
              config: solverConfig,
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
    required bool shieldPlatformViews,
    required double interactiveExtent,
    required Color? dragBarrierColor,
    required WidgetStateProperty<Color?>? dividerColor,
    required Widget Function(BuildContext, SplitterHandleDetails)?
    handleBuilder,
    required SplitterSolverConfig config,
    required bool crossAxisBounded,
    required SplitterController controller,
    required SplitterSemanticsLabels semantics,
  }) {
    // The interactive target is centered on the visible bar; the extent past the
    // bar becomes overhang (interactiveSlop) on each side that the catcher
    // overlays onto the panels without reserving layout. A non-resizable divider
    // uses no overhang, so it cannot cover and steal hits from the panes.
    final rawSlop = (interactiveExtent - dividerThickness) / 2;
    final interactiveSlop = widget.resizable && rawSlop > 0 ? rawSlop : 0.0;

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
    final solver = config.solverFor(
      availableSize,
      // Only an actually-collapsible pane resolves collapsed; a collapse request
      // on a fixed pane is ignored by the layout (the request still lives on the
      // controller). This is the request-vs-resolved split, like position vs
      // effective fraction.
      startCollapsed:
          collapsedPane == SplitterPane.start &&
          widget.startConstraints.collapsible,
      endCollapsed:
          collapsedPane == SplitterPane.end &&
          widget.endConstraints.collapsible,
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
      dragBarrierColor: dragBarrierColor,
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
      shieldPlatformViews: shieldPlatformViews && widget.resizable,
      snap: widget.snap,
      handleBuilder: handleBuilder,
      holdScrollWhileDragging:
          widget.holdScrollWhileDragging && widget.resizable,
      interactiveSlop: interactiveSlop,
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
            start: first - interactiveSlop,
            top: 0,
            bottom: 0,
            child: divider,
          )
        else
          Positioned(
            top: first - interactiveSlop,
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
