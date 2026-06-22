// We intentionally expose imperative helpers instead of setters for ergonomics.
// ignore_for_file: use_setters_to_change_properties
// A robust, high-performance split view that plays nicely with platform views.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
part 'render_resizable_splitter.dart';

/// Axis helpers to eliminate H/V duplication.
extension _AxisHelpers on Axis {
  bool get isH => this == Axis.horizontal;

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
/// splitter cannot resize, so under the default
/// [UnboundedBehavior.shrinkToChildren] it shows the two panels without the
/// divider, sized to their content. Opt into
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
  // previewing). The panes stay at the committed position; the render object
  // listens to this notifier and repaints only the preview line as it moves.
  late final ValueNotifier<double?> _previewFraction = ValueNotifier<double?>(
    null,
  );

  // The resolved geometry the render object publishes from each layout pass. The
  // handle listens to it for drag/keyboard/semantics; the state mirrors it to
  // the controller and reports collapse transitions from it.
  late final _SplitterGeometryNotifier _geometry = _SplitterGeometryNotifier();

  // Bumped on dispose and on a controller swap so a stale post-frame flush or
  // collapse report scheduled for an older controller/generation is dropped.
  int _layoutPublicationGeneration = 0;

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
  // No setState: the render object listens to the notifier and repaints just the
  // preview line, without rebuilding the widget subtree.
  void _setPreview(double? fraction) {
    if (!mounted || _previewFraction.value == fraction) return;
    _previewFraction.value = fraction;
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
      // Invalidate any pending post-frame flush/report scheduled for the
      // outgoing controller, and drop the geometry it produced so the handle
      // does not briefly read the old controller's layout.
      _layoutPublicationGeneration++;
      if (_geometry.prime(null)) _scheduleGeometryFlush();
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
    // Invalidate pending post-frame callbacks, then dispose the notifiers.
    _layoutPublicationGeneration++;
    _previewFraction.dispose();
    _geometry.dispose();
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

  // The render object's performLayout publishes its resolved geometry here. This
  // runs DURING layout, so it must never notify synchronously: it primes the
  // notifiers (value-only, no listeners fired) and defers every notification to
  // a post-frame flush. A geometry built for a since-swapped controller is
  // ignored; everything else is mirrored to the attached controller.
  void _handleResolvedGeometry(_ResolvedSplitterGeometry? geometry) {
    final controller = _attachedController ?? _effectiveController;
    if (geometry != null && !identical(geometry.controller, controller)) {
      return;
    }
    if (_geometry.prime(geometry)) _scheduleGeometryFlush();
    _publishLayout(controller, geometry?.layout);
    if (geometry != null) {
      _maybeReportCollapseChange(
        controller,
        geometry.solver,
        geometry.solution,
      );
    }
  }

  // Primes the controller's resolved layout synchronously (so its read-outs are
  // fresh this frame) and schedules the listener notification after the frame,
  // so it never triggers a listener's setState during build. Generation- and
  // controller-guarded so a stale post-frame flush (after a swap or disposal) is
  // dropped. No-ops when the layout is unchanged.
  void _publishLayout(SplitterController controller, SplitterLayout? layout) {
    if (!controller._primeLayout(layout)) return;
    final generation = _layoutPublicationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _layoutPublicationGeneration ||
          !identical(_attachedController, controller)) {
        return;
      }
      controller._flushLayout();
    });
  }

  // Fires the deferred geometry notification post-frame, so the handle's
  // ValueListenableBuilder never rebuilds mid-layout. Generation-guarded so a
  // controller swap drops a stale flush.
  void _scheduleGeometryFlush() {
    final generation = _layoutPublicationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutPublicationGeneration) return;
      _geometry.flush();
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
    final generation = _layoutPublicationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _layoutPublicationGeneration ||
          !identical(_attachedController, controller)) {
        return;
      }
      onChanged(details);
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
          value: _previewFraction.value != null,
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

    // The render object reserves only the divider's visible thickness for
    // layout (clamped to the container, so a parent smaller than the thickness
    // shrinks it rather than overflowing); the interactive grab slop on each
    // side overlaps the panes via the render object's hit test without reducing
    // pane layout.
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

    // A position change re-pushes the request into the render object (which
    // re-solves it in performLayout); the panes are the same widget instances,
    // so their subtrees are not rebuilt.
    final child = ValueListenableBuilder<SplitterState>(
      valueListenable: controller,
      builder: (_, state, _) => _buildBounded(
        state: state,
        dividerThickness: dividerThickness,
        interactiveExtent: interactiveExtent,
        enableKeyboard: enableKeyboard,
        enableHaptics: enableHaptics,
        keyboardStep: keyboardStep,
        pageStep: pageStep,
        shieldPlatformViews: shieldPlatformViews,
        dragBarrierColor: dragBarrierColor,
        dividerColor: dividerColor,
        handleBuilder: handleBuilder,
        config: solverConfig,
        controller: controller,
        semantics: semanticsLabels,
      ),
    );

    // No LayoutBuilder, so intrinsic queries reach the render object. The render
    // object handles a bounded main axis and, for shrinkToChildren, shrink-wraps
    // an unbounded main axis itself. useFallbackExtent instead caps an unbounded
    // main axis to a finite sandbox via LimitedBox (which forwards intrinsics,
    // unlike LayoutBuilder); a bounded axis passes straight through it.
    if (unboundedBehavior == UnboundedBehavior.useFallbackExtent) {
      return LimitedBox(
        maxWidth: widget.axis.isH ? fallbackExtent : double.infinity,
        maxHeight: widget.axis.isH ? double.infinity : fallbackExtent,
        child: child,
      );
    }
    return child;
  }

  Widget _buildBounded({
    required SplitterState state,
    required double dividerThickness,
    required double interactiveExtent,
    required bool enableKeyboard,
    required bool enableHaptics,
    required double keyboardStep,
    required double pageStep,
    required bool shieldPlatformViews,
    required Color? dragBarrierColor,
    required WidgetStateProperty<Color?>? dividerColor,
    required Widget Function(BuildContext, SplitterHandleDetails)?
    handleBuilder,
    required SplitterSolverConfig config,
    required SplitterController controller,
    required SplitterSemanticsLabels semantics,
  }) {
    // The interactive target is centered on the visible bar; the extent past the
    // bar becomes overhang (interactiveSlop) on each side that the render
    // object's hit test overlays onto the panes without reserving layout. A
    // non-resizable divider uses no overhang. This is computed from the raw
    // thickness: the render object clamps the visible thickness to the
    // container, but the interactive box width is `interactiveExtent` either way,
    // so the handle's padding matches the box in every normal layout and differs
    // only harmlessly when the container is smaller than the divider.
    final rawSlop = (interactiveExtent - dividerThickness) / 2;
    final interactiveSlop = widget.resizable && rawSlop > 0 ? rawSlop : 0.0;

    final divider = _DividerHandle(
      axis: widget.axis,
      controller: controller,
      thickness: dividerThickness,
      // The handle reads its solver/solution live from here (published by the
      // render object's performLayout) for drag/keyboard/snap/semantics.
      geometryListenable: _geometry,
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

    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final previewColor = Theme.of(context).colorScheme.primary;

    // The render object owns layout (solving the request against the real
    // constraints in performLayout), painting (each pane clipped to its box),
    // hit testing (the divider wins inside its slop), and publishing the
    // resolved geometry back up through [_handleResolvedGeometry] - which mirrors
    // it to the controller and reports collapse transitions. The handle is
    // passed opaquely; the preview line is laid out by the render object and
    // painted only while a deferred drag is previewing.
    return _ResizableSplitterRenderWidget(
      axis: widget.axis,
      textDirection: textDirection,
      position: state.position,
      collapsedPane: state.collapsedPane,
      dividerThickness: dividerThickness,
      interactiveExtent: interactiveExtent,
      resizable: widget.resizable,
      config: config,
      controller: controller,
      previewListenable: _previewFraction,
      onGeometryChanged: _handleResolvedGeometry,
      start: widget.start,
      end: widget.end,
      divider: divider,
      preview: IgnorePointer(child: ColoredBox(color: previewColor)),
    );
  }
}
