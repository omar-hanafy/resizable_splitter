part of 'resizable_splitter.dart';

/// The geometry one bounded layout pass resolved, published up from the render
/// object's `performLayout` to the splitter state (which republishes it to the
/// controller and feeds the handle). It carries the already-built [solver] and
/// [solution] so the handle never re-solves, plus the [controller] it was built
/// for so a stale publication after a controller swap can be ignored.
@immutable
class _ResolvedSplitterGeometry {
  const _ResolvedSplitterGeometry({
    required this.controller,
    required this.config,
    required this.solver,
    required this.solution,
    required this.layout,
    required this.dividerThickness,
  });

  final SplitterController controller;
  final SplitterSolverConfig config;
  final SplitterSolver solver;
  final SplitterSolution solution;
  final SplitterLayout layout;
  final double dividerThickness;

  // A handle resolves future pointer/keyboard positions and semantics previews
  // through the solver. Its configuration therefore matters even when the
  // current solution is equal: changing pixel snapping or DPR can change the
  // next adjustment without moving the divider in this layout pass.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ResolvedSplitterGeometry &&
          identical(other.controller, controller) &&
          other.config == config &&
          other.solution == solution &&
          other.layout == layout &&
          other.dividerThickness == dividerThickness;

  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
    config,
    solution,
    layout,
    dividerThickness,
  );
}

/// The resolved-geometry observable the render object publishes to and the
/// handle listens to. Mirrors [_SplitterLayoutNotifier]: [prime] updates the
/// value synchronously during layout (without notifying, which would be illegal
/// mid-layout); [flush] fires the notification post-frame.
class _SplitterGeometryNotifier extends ChangeNotifier
    implements ValueListenable<_ResolvedSplitterGeometry?> {
  _ResolvedSplitterGeometry? _value;
  bool _dirty = false;

  @override
  _ResolvedSplitterGeometry? get value => _value;

  bool prime(_ResolvedSplitterGeometry? next) {
    if (_value == next) return false;
    _value = next;
    _dirty = true;
    return true;
  }

  void flush() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }
}
