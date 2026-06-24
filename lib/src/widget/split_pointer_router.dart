part of 'resizable_splitter.dart';

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

  // Active drags keyed by their real pointer id (the normal up/cancel path).
  final Map<int, SplitterController> _activeByPointer =
      <int, SplitterController>{};
  // Active MOUSE drags also keyed by (viewId, device). A platform view can
  // swallow the pointer-up so the same-pointer up/cancel never reaches the
  // framework, and an up with no cached hit test is dropped before this route
  // ever runs. The next hover (or a move whose primary button is no longer
  // held) for that device is then the only proof the press ended - and a hover
  // gets a fresh hit test and may carry a different pointer id, so this recovery
  // must key on the device, not the pointer.
  final Map<(int viewId, int device), SplitterController> _activeMouseByDevice =
      <(int, int), SplitterController>{};
  bool _initialized = false;

  // Last-resort watchdog: while a mouse drag is active, poll the OS for the
  // physical primary-button state. If a platform view captured the OS mouse and
  // swallowed the up so NO event (not even a reconciled hover) reaches Flutter,
  // this still observes the release and ends the drag. It reads live hardware
  // state, so a long motionless hold keeps dragging - it is not a timeout.
  static const Duration _buttonWatchdogInterval = Duration(milliseconds: 32);
  Timer? _buttonWatchdog;

  // Test-only override for the hardware probe (see SplitterController).
  bool Function()? _debugProbeOverride;

  void _initialize() {
    if (_initialized) return;
    final binding = _maybeBinding();
    if (binding == null) return;
    binding.pointerRouter.addGlobalRoute(_handleGlobal);
    _initialized = true;
  }

  /// Removes every active drag owned by [c] (used when its controller is
  /// disposed).
  void unregister(SplitterController c) => _forget(c);

  /// Registers [c] as dragging under [pointerId], and (for a mouse) also under
  /// its `(viewId, device)` so a swallowed up can still be recovered from a
  /// later hover. A controller drives one drag at a time, so any stale
  /// registration it held is dropped first. A real (non-negative) pointer id is
  /// required for the exact up/cancel backup; an unknown pointer (-1) simply
  /// gets no exact backup (the device recovery still applies for a mouse).
  void beginDrag(
    SplitterController c,
    int pointerId, {
    int? device,
    int? viewId,
    PointerDeviceKind? kind,
  }) {
    _initialize();
    _forget(c);
    if (pointerId >= 0) _activeByPointer[pointerId] = c;
    if (kind == PointerDeviceKind.mouse && device != null && viewId != null) {
      _activeMouseByDevice[(viewId, device)] = c;
      _ensureButtonWatchdog();
    }
  }

  /// Ends every active drag owned by [c] (its drag finished normally).
  void endDrag(SplitterController c) => _forget(c);

  void _forget(SplitterController c) {
    _activeByPointer.removeWhere((_, controller) => identical(controller, c));
    _activeMouseByDevice.removeWhere(
      (_, controller) => identical(controller, c),
    );
    if (_activeMouseByDevice.isEmpty) _stopButtonWatchdog();
  }

  void _handleGlobal(PointerEvent event) {
    if (event is PointerUpEvent) {
      _finish(_activeByPointer[event.pointer], _DragEndReason.completed);
      return;
    }
    if (event is PointerCancelEvent) {
      _finish(_activeByPointer[event.pointer], _DragEndReason.canceled);
      return;
    }
    // Recovery for a swallowed mouse release. Only relevant while a mouse drag
    // is active; the fast path keeps this off the hot hover/move stream.
    if (_activeMouseByDevice.isEmpty) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event is! PointerHoverEvent && event is! PointerMoveEvent) return;
    // The primary button still being held means a genuine drag is in progress
    // (during a real drag the framework emits moves with the button bit set and
    // never a hover), so only a primary-released event is proof the press ended.
    if (event.buttons & kPrimaryButton != 0) return;
    _finish(
      _activeMouseByDevice[(event.viewId, event.device)],
      _DragEndReason.completed,
    );
  }

  void _finish(SplitterController? controller, _DragEndReason reason) {
    if (controller == null) return;
    _forget(controller);
    controller._endDragFromRouter(reason);
  }

  void _ensureButtonWatchdog() {
    if (_buttonWatchdog != null) return;
    final probe =
        _debugProbeOverride ??
        (_isTestEnvironment ? null : createPrimaryMouseButtonProbe());
    if (probe == null) return;
    _buttonWatchdog = Timer.periodic(_buttonWatchdogInterval, (_) {
      if (probe()) return; // still physically held: a genuine ongoing drag.
      _endStrandedMouseDrags();
    });
  }

  void _stopButtonWatchdog() {
    _buttonWatchdog?.cancel();
    _buttonWatchdog = null;
  }

  // The physical button is no longer down but mouse drags are still registered:
  // their releases were swallowed. End them as completed (a real release).
  void _endStrandedMouseDrags() {
    if (_activeMouseByDevice.isEmpty) {
      _stopButtonWatchdog();
      return;
    }
    // Snapshot first - _finish mutates the map (and stops the watchdog) as it
    // tears each drag down.
    for (final controller in _activeMouseByDevice.values.toList(
      growable: false,
    )) {
      _finish(controller, _DragEndReason.completed);
    }
  }

  // The hardware probe reads a real button. Under the flutter_test binding,
  // pointer input is simulated and there is nothing to read, so tests inject a
  // fake probe and the real one is never used. (A library cannot import
  // flutter_test, hence the binding-type check.)
  bool get _isTestEnvironment {
    final binding = _maybeBinding();
    return binding != null && binding.runtimeType.toString().contains('Test');
  }

  void dispose() {
    _stopButtonWatchdog();
    _activeByPointer.clear();
    _activeMouseByDevice.clear();
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
