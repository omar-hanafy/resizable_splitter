// ignore_for_file: use_setters_to_change_properties
part of 'resizable_splitter.dart';

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
/// {@category Controller}
class SplitterController extends ValueNotifier<SplitterState>
    with Diagnosticable {
  /// Creates a splitter controller at [initialPosition] (default: centered).
  ///
  /// The controller stores the requested [SplitterPosition]; the splitter
  /// resolves it against the live layout every frame. A pixel request
  /// ([SplitterPosition.startPixels] / [SplitterPosition.endPixels]) therefore
  /// keeps its pixel size as the container resizes, while a drag or keyboard
  /// adjustment writes a fractional position (the pin releases on interaction).
  SplitterController({
    SplitterPosition initialPosition = const SplitterPosition.fraction(0.5),
  }) : this._(SplitterState(position: initialPosition));

  SplitterController._(super.initialState);

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
      // reads null while detached, as its documentation promises. Clearing the
      // stale flag too keeps [effectiveFraction] deriving cleanly from the
      // request while detached.
      _layoutStale = false;
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
  ///
  /// Contract: it notifies once per resolved change, after the frame that
  /// produced it (never during build), so a listener may freely read [layout] or
  /// call `setState`. A re-solve that yields the same geometry coalesces to no
  /// notification. The notification is scheduled, not synchronous with the
  /// request write - do not assume a particular number of frames, only this
  /// ordering. (This contract is what lets the layout publish move into a
  /// render object's layout pass in a future release without consumers noticing.)
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
  bool _primeLayout(SplitterLayout? layout) {
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
  /// never corrupt the layout. Any write that *changes* the state (a drag, key
  /// press, reset, collapse, or direct assignment) takes over from a running
  /// animation. The animation's own ticks bypass this setter (they write through
  /// `super.value` in [_setAnimatedPosition]), so a run never cancels itself -
  /// yet a listener's reentrant public write still goes through here and cancels.
  @override
  set value(SplitterState newValue) {
    // No-op writes change nothing observable, so they neither notify nor cancel
    // a running animation. Crucially, nothing mutates before this equality gate,
    // so a collapse (which lives inside the value) can never change without a
    // matching notification - the historic collapse/equal-write desync is gone.
    if (newValue == value) return;
    _animator?.cancel();
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
  /// direct value write cancels a run in progress (resolving [SplitterAnimationStatus.canceled]); a
  /// disposal or controller swap ends it (resolving [SplitterAnimationStatus.detached]). With no view
  /// attached, disabled animations, or a target already current, the value is
  /// set immediately and the run resolves [SplitterAnimationStatus.completed].
  Future<SplitterAnimationStatus> animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeOutCubic,
  }) {
    final goal = target.clamp(0.0, 1.0).toDouble();
    final animator = _animator;
    if (animator == null) {
      // Detached: no view drives a run, so none can be in flight to supersede.
      // Set the value immediately and report completed.
      jumpTo(SplitterPosition.fraction(goal));
      return Future<SplitterAnimationStatus>.value(
        SplitterAnimationStatus.completed,
      );
    }
    // The attached view owns the run. It cancels any in-flight run first (so a
    // fresh animateTo always supersedes it, even when it then resolves
    // instantly), resolves the target through the solver, and applies the
    // disabled-animations / already-there shortcuts.
    return animator.animateTo(goal, duration, curve);
  }

  void _attachAnimator(_SplitterAnimator animator) => _animator = animator;

  void _detachAnimator(_SplitterAnimator animator) {
    if (identical(_animator, animator)) _animator = null;
  }

  void _cancelAnimation() => _animator?.cancel();

  // Writes an animated position. A fresh animateTo is a new intent, so the run
  // animates an uncollapsed state (the first tick clears any collapse), matching
  // jumpTo/keyboard/drag. The write goes through `super.value` so the run never
  // cancels itself, while a listener's reentrant *public* write still routes
  // through the overridden setter and cancels the run.
  void _setAnimatedPosition(SplitterPosition position) {
    final next = SplitterState(position: position);
    if (next == value) return;
    _layoutStale = true;
    super.value = next;
  }

  // Internal methods for the global router. The reason distinguishes a normal
  // release (the route saw a pointer-up a platform view swallowed) from a
  // cancel, so the handle settles only on a real completion.
  void _endDragFromRouter(_DragEndReason reason) {
    final cb = _dragCallback;
    _dragCallback = null;
    cb?.call(reason);
  }

  void _setDragCallback(void Function(_DragEndReason)? cb) =>
      _dragCallback = cb;
  void Function(_DragEndReason)? _dragCallback;

  void _setDragging(bool dragging) => _isDragging.value = dragging;

  /// Resets the global pointer router. For testing only.
  @visibleForTesting
  static void resetGlobalRouter() {
    _globalRouter._debugProbeOverride = null;
    _globalRouter.dispose();
  }

  /// Overrides the hardware primary-mouse-button probe that backs the
  /// stuck-drag watchdog, so tests can simulate the physical button without a
  /// real device. Cleared by [resetGlobalRouter]. For testing only.
  @visibleForTesting
  static set debugPrimaryMouseButtonProbe(bool Function()? probe) =>
      _globalRouter._debugProbeOverride = probe;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<SplitterPosition>('position', position))
      ..add(DoubleProperty('effectiveFraction', effectiveFraction))
      ..add(DiagnosticsProperty<bool>('isAttached', isAttached))
      ..add(DiagnosticsProperty<bool>('isDragging', isDragging))
      ..add(
        DiagnosticsProperty<SplitterPane?>(
          'collapsedPane',
          collapsedPane,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<SplitterLayout?>(
          'layout',
          layout,
          defaultValue: null,
        ),
      );
  }
}
