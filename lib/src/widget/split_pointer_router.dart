part of 'resizable_splitter.dart';

/// Why a drag ended, so the handle settles only on a real release and never
/// treats a cancel, a mid-drag reconfiguration, or a disposal as a successful
/// completion.
enum _DragEndReason {
  /// The pointer lifted normally - a gesture end, or an up the gesture
  /// recognizer missed but the global route still saw. Settles, snaps, and fires
  /// onChangeEnd.
  completed,

  /// A system cancel (gesture/pointer cancel). No commit, snap, or end event.
  canceled,

  /// A mid-drag reconfiguration (controller, axis, or mode swap, or resizing
  /// turned off). No commit, snap, or end event. Disposal tears down the same
  /// way, but directly (it cannot call setState), so it needs no reason here.
  interrupted,
}

/// Singleton global pointer router providing a stuck-drag backup. It only ends a
/// drag from an up/cancel that actually reaches Flutter; it cannot see an event
/// a platform view swallowed before the engine (the painted drag shield is what
/// keeps the platform view from swallowing it - see `_DragOverlay`). Given the
/// event does reach Flutter, this route ends the matching session even if the
/// gesture recognizer's own end never fires. Active drags are keyed by their
/// real pointer id, so several splitters can be dragged at once and each is
/// cleaned up independently (the old single-slot design tracked only one).
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
