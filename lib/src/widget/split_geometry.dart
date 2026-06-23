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
    required this.solver,
    required this.solution,
    required this.layout,
    required this.dividerThickness,
  });

  final SplitterController controller;
  final SplitterSolver solver;
  final SplitterSolution solution;
  final SplitterLayout layout;
  final double dividerThickness;

  // Equality drives the handle's rebuild coalescing (via the notifier's
  // [prime]). Every consumer reads only the [solution] (the handle), the
  // [solver] derived from it, or the [controller]/[layout] (the state), so two
  // geometries that resolve to the same [solution] for the same controller are
  // interchangeable. Comparing the resolved [solution] directly - now that it is
  // a value type - is the single, honest equality, replacing the former habit of
  // comparing a dozen raw layout inputs as a stand-in for "did the result
  // change". Add a field that affects a consumer's output and it must join here.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ResolvedSplitterGeometry &&
          identical(other.controller, controller) &&
          other.solution == solution &&
          other.layout == layout &&
          other.dividerThickness == dividerThickness;

  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
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
