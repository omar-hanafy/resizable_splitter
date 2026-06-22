part of 'resizable_splitter.dart';

/// Clamps the divider's visible thickness to the available main extent, so a
/// container smaller than the divider shrinks the bar to fit rather than
/// overflowing. NaN/negative collapses to 0; an infinite thickness fills.
double _clampedSplitterDividerThickness(
  double dividerThickness,
  double mainExtent,
) {
  final sanitizedMain = mainExtent.isFinite && mainExtent > 0
      ? mainExtent
      : 0.0;
  if (dividerThickness.isNaN || dividerThickness <= 0) return 0;
  if (!dividerThickness.isFinite) return sanitizedMain;
  return dividerThickness.clamp(0.0, sanitizedMain).toDouble();
}

/// The overhang on each side of the visible bar that the interactive catcher
/// adds without reserving layout: half of `interactiveExtent - dividerThickness`
/// (never negative, zero when the divider is not resizable).
double _splitterInteractiveSlop({
  required double interactiveExtent,
  required double dividerThickness,
  required bool resizable,
}) {
  if (!resizable) return 0;
  final sanitizedInteractiveExtent =
      interactiveExtent.isFinite && interactiveExtent >= 0
      ? interactiveExtent
      : dividerThickness;
  final rawSlop = (sanitizedInteractiveExtent - dividerThickness) / 2;
  return rawSlop > 0 ? rawSlop : 0;
}

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
    required this.requestedPosition,
    required this.requestedCollapsedPane,
    required this.solver,
    required this.solution,
    required this.layout,
    required this.axis,
    required this.textDirection,
    required this.dividerThickness,
    required this.interactiveSlop,
    required this.gapExtent,
    required this.size,
  });

  final SplitterController controller;
  final SplitterSolverConfig config;
  final SplitterPosition requestedPosition;
  final SplitterPane? requestedCollapsedPane;
  final SplitterSolver solver;
  final SplitterSolution solution;
  final SplitterLayout layout;
  final Axis axis;
  final TextDirection textDirection;
  final double dividerThickness;
  final double interactiveSlop;
  final double gapExtent;
  final Size size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ResolvedSplitterGeometry &&
          identical(other.controller, controller) &&
          other.config == config &&
          other.requestedPosition == requestedPosition &&
          other.requestedCollapsedPane == requestedCollapsedPane &&
          other.layout == layout &&
          other.axis == axis &&
          other.textDirection == textDirection &&
          other.dividerThickness == dividerThickness &&
          other.interactiveSlop == interactiveSlop &&
          other.gapExtent == gapExtent &&
          other.size == size;

  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
    config,
    requestedPosition,
    requestedCollapsedPane,
    layout,
    axis,
    textDirection,
    dividerThickness,
    interactiveSlop,
    gapExtent,
    size,
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

enum _SplitterSlot { start, end, divider, preview }

class _SplitterParentData extends ContainerBoxParentData<RenderBox> {
  _SplitterSlot? slot;

  @override
  String toString() => 'slot=$slot; ${super.toString()}';
}

class _SplitterSlotChild extends ParentDataWidget<_SplitterParentData> {
  const _SplitterSlotChild({required this.slot, required super.child});

  final _SplitterSlot slot;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as _SplitterParentData;
    if (parentData.slot == slot) return;
    parentData.slot = slot;
    final parent = renderObject.parent;
    if (parent is _RenderResizableSplitter) parent.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _ResizableSplitterRenderWidget;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<_SplitterSlot>('slot', slot));
  }
}

/// The seam widget: a [MultiChildRenderObjectWidget] whose render object owns
/// the bounded (and unbounded-shrink-wrap) layout, painting, clipping, and hit
/// testing of the four slots. Everything else - gestures, focus, semantics,
/// animation, restoration, platform-view shielding - lives above it in the
/// widget layer.
class _ResizableSplitterRenderWidget extends MultiChildRenderObjectWidget {
  _ResizableSplitterRenderWidget({
    required Widget start,
    required Widget end,
    required Widget divider,
    required Widget preview,
    required this.axis,
    required this.textDirection,
    required this.position,
    required this.collapsedPane,
    required this.dividerThickness,
    required this.interactiveExtent,
    required this.resizable,
    required this.config,
    required this.controller,
    required this.previewListenable,
    required this.onGeometryChanged,
  }) : super(
         children: <Widget>[
           _SplitterSlotChild(slot: _SplitterSlot.start, child: start),
           _SplitterSlotChild(slot: _SplitterSlot.end, child: end),
           _SplitterSlotChild(slot: _SplitterSlot.divider, child: divider),
           _SplitterSlotChild(slot: _SplitterSlot.preview, child: preview),
         ],
       );

  final Axis axis;
  final TextDirection textDirection;
  final SplitterPosition position;
  final SplitterPane? collapsedPane;
  final double dividerThickness;
  final double interactiveExtent;
  final bool resizable;
  final SplitterSolverConfig config;
  final SplitterController controller;
  final ValueListenable<double?> previewListenable;
  final _SplitterGeometryChanged onGeometryChanged;

  @override
  _RenderResizableSplitter createRenderObject(BuildContext context) =>
      _RenderResizableSplitter(
        axis: axis,
        textDirection: textDirection,
        position: position,
        collapsedPane: collapsedPane,
        dividerThickness: dividerThickness,
        interactiveExtent: interactiveExtent,
        resizable: resizable,
        config: config,
        controller: controller,
        previewListenable: previewListenable,
        onGeometryChanged: onGeometryChanged,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderResizableSplitter renderObject,
  ) {
    renderObject
      ..axis = axis
      ..textDirection = textDirection
      ..position = position
      ..collapsedPane = collapsedPane
      ..dividerThickness = dividerThickness
      ..interactiveExtent = interactiveExtent
      ..resizable = resizable
      ..config = config
      ..controller = controller
      ..previewListenable = previewListenable
      ..onGeometryChanged = onGeometryChanged;
  }
}

typedef _SplitterGeometryChanged =
    void Function(_ResolvedSplitterGeometry? geometry);

class _RenderResizableSplitter extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SplitterParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SplitterParentData> {
  _RenderResizableSplitter({
    required Axis axis,
    required TextDirection textDirection,
    required SplitterPosition position,
    required SplitterPane? collapsedPane,
    required double dividerThickness,
    required double interactiveExtent,
    required bool resizable,
    required SplitterSolverConfig config,
    required SplitterController controller,
    required ValueListenable<double?> previewListenable,
    required this.onGeometryChanged,
  }) : _axis = axis,
       _textDirection = textDirection,
       _position = position,
       _collapsedPane = collapsedPane,
       _dividerThickness = dividerThickness,
       _interactiveExtent = interactiveExtent,
       _resizable = resizable,
       _config = config,
       _controller = controller,
       _previewListenable = previewListenable,
       _previewFraction = previewListenable.value;

  Axis _axis;
  TextDirection _textDirection;
  SplitterPosition _position;
  SplitterPane? _collapsedPane;
  double _dividerThickness;
  double _interactiveExtent;
  bool _resizable;
  SplitterSolverConfig _config;
  SplitterController _controller;
  ValueListenable<double?> _previewListenable;
  double? _previewFraction;

  /// Called at the end of every layout pass with the resolved geometry (or null
  /// for an unbounded shrink-wrap). Not a layout-affecting input, so it is a
  /// plain mutable field rather than a markNeedsLayout setter.
  _SplitterGeometryChanged onGeometryChanged;

  // The solver from the last bounded layout, kept so a preview move can be a
  // repaint (reposition the preview line) instead of a full relayout.
  SplitterSolver? _lastSolver;
  double _lastEffectiveDividerThickness = 0;

  Axis get axis => _axis;
  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  SplitterPosition get position => _position;
  set position(SplitterPosition value) {
    if (_position == value) return;
    _position = value;
    markNeedsLayout();
  }

  SplitterPane? get collapsedPane => _collapsedPane;
  set collapsedPane(SplitterPane? value) {
    if (_collapsedPane == value) return;
    _collapsedPane = value;
    markNeedsLayout();
  }

  double get dividerThickness => _dividerThickness;
  set dividerThickness(double value) {
    if (_dividerThickness == value) return;
    _dividerThickness = value;
    markNeedsLayout();
  }

  double get interactiveExtent => _interactiveExtent;
  set interactiveExtent(double value) {
    if (_interactiveExtent == value) return;
    _interactiveExtent = value;
    markNeedsLayout();
  }

  bool get resizable => _resizable;
  set resizable(bool value) {
    if (_resizable == value) return;
    _resizable = value;
    markNeedsLayout();
  }

  SplitterSolverConfig get config => _config;
  set config(SplitterSolverConfig value) {
    if (_config == value) return;
    _config = value;
    markNeedsLayout();
  }

  SplitterController get controller => _controller;
  set controller(SplitterController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markNeedsLayout();
  }

  ValueListenable<double?> get previewListenable => _previewListenable;
  set previewListenable(ValueListenable<double?> value) {
    if (identical(_previewListenable, value)) return;
    if (attached) _previewListenable.removeListener(_handlePreviewChanged);
    _previewListenable = value;
    if (attached) _previewListenable.addListener(_handlePreviewChanged);
    _handlePreviewChanged();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplitterParentData) {
      child.parentData = _SplitterParentData();
    }
  }

  // Listen to the preview only while attached, so a preview move never calls
  // markNeedsPaint on a detached render object. Resync on attach in case the
  // value changed while detached.
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _previewListenable.addListener(_handlePreviewChanged);
    _previewFraction = _previewListenable.value;
  }

  @override
  void detach() {
    _previewListenable.removeListener(_handlePreviewChanged);
    super.detach();
  }

  void _handlePreviewChanged() {
    final next = _previewListenable.value;
    if (_previewFraction == next) return;
    _previewFraction = next;
    // A preview move only repositions the preview line; reuse the cached solver
    // to update its offset and repaint, avoiding a full pane relayout.
    if (_updatePreviewOffsetFromCachedGeometry()) {
      markNeedsPaint();
    } else {
      markNeedsLayout();
    }
  }

  bool _updatePreviewOffsetFromCachedGeometry() {
    final preview = _childForSlot(_SplitterSlot.preview);
    final solver = _lastSolver;
    if (preview == null || solver == null || !hasSize) return false;
    _setChildOffset(
      preview,
      _previewOffsetFor(
        solver: solver,
        renderSize: size,
        dividerThickness: _lastEffectiveDividerThickness,
      ),
    );
    return true;
  }

  RenderBox? _childForSlot(_SplitterSlot slot) {
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as _SplitterParentData;
      if (parentData.slot == slot) return child;
      child = parentData.nextSibling;
    }
    return null;
  }

  bool _debugValidateSlots() {
    final seen = <_SplitterSlot>{};
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as _SplitterParentData;
      assert(parentData.slot != null, 'Every splitter child must have a slot.');
      assert(
        seen.add(parentData.slot!),
        'Duplicate splitter slot: ${parentData.slot}.',
      );
      child = parentData.nextSibling;
    }
    return true;
  }

  // ---- axis helpers (main = along [axis], cross = perpendicular) ----

  double _main(Size size) => _axis.isH ? size.width : size.height;
  double _cross(Size size) => _axis.isH ? size.height : size.width;
  double _maxMain(BoxConstraints c) => _axis.isH ? c.maxWidth : c.maxHeight;
  double _maxCross(BoxConstraints c) => _axis.isH ? c.maxHeight : c.maxWidth;
  bool _hasPaneMainExtent(double extent) => extent > 0;

  bool get _startRequestedCollapsed =>
      _collapsedPane == SplitterPane.start && _config.start.collapsible;

  bool get _endRequestedCollapsed =>
      _collapsedPane == SplitterPane.end && _config.end.collapsible;

  SplitterSolver _solverFor(double available) => _config.solverFor(
    available,
    startCollapsed: _startRequestedCollapsed,
    endCollapsed: _endRequestedCollapsed,
  );

  Size _sizeFrom({required double main, required double cross}) =>
      _axis.isH ? Size(main, cross) : Size(cross, main);

  Offset _offsetFrom({required double main, required double cross}) =>
      _axis.isH ? Offset(main, cross) : Offset(cross, main);

  bool get _horizontalRtl =>
      _axis == Axis.horizontal && _textDirection == TextDirection.rtl;

  BoxConstraints _paneConstraints({
    required BoxConstraints parent,
    required double mainExtent,
    required double? tightCrossExtent,
  }) {
    final main = mainExtent.isFinite && mainExtent > 0 ? mainExtent : 0.0;
    if (!_hasPaneMainExtent(main)) return BoxConstraints.tight(Size.zero);
    if (_axis.isH) {
      return BoxConstraints(
        minWidth: main,
        maxWidth: main,
        minHeight: tightCrossExtent ?? 0,
        maxHeight: tightCrossExtent ?? parent.maxHeight,
      );
    }
    return BoxConstraints(
      minWidth: tightCrossExtent ?? 0,
      maxWidth: tightCrossExtent ?? parent.maxWidth,
      minHeight: main,
      maxHeight: main,
    );
  }

  BoxConstraints _dividerConstraints({
    required double mainExtent,
    required double crossExtent,
  }) {
    final main = mainExtent.isFinite && mainExtent > 0 ? mainExtent : 0.0;
    final cross = crossExtent.isFinite && crossExtent > 0 ? crossExtent : 0.0;
    return _axis.isH
        ? BoxConstraints.tight(Size(main, cross))
        : BoxConstraints.tight(Size(cross, main));
  }

  double _constrainCross(BoxConstraints c, double main, double cross) =>
      _cross(c.constrain(_sizeFrom(main: main, cross: cross)));

  double _paneCrossExtent(RenderBox? child, double mainExtent) {
    if (child == null || !_hasPaneMainExtent(mainExtent)) return 0.0;
    return _cross(child.size);
  }

  // ---- main-axis offsets (RTL puts the logical start pane on the right) ----

  double _startMainOffset(double renderMain, double startExtent) =>
      _horizontalRtl ? renderMain - startExtent : 0;

  double _endMainOffset({
    required double startExtent,
    required double dividerThickness,
    required double gapExtent,
  }) => _horizontalRtl ? 0 : startExtent + dividerThickness + gapExtent;

  double _dividerMainOffset({
    required double renderMain,
    required double startExtent,
    required double dividerThickness,
    required double interactiveSlop,
  }) => _horizontalRtl
      ? renderMain - startExtent - dividerThickness - interactiveSlop
      : startExtent - interactiveSlop;

  double _previewMainOffset({
    required double renderMain,
    required double previewStartExtent,
    required double dividerThickness,
  }) => _horizontalRtl
      ? renderMain - previewStartExtent - dividerThickness
      : previewStartExtent;

  Offset _previewOffsetFor({
    required SplitterSolver solver,
    required Size renderSize,
    required double dividerThickness,
  }) {
    final previewFraction = _previewFraction;
    if (previewFraction == null) return Offset.zero;
    final previewStart = solver
        .solve(SplitterPosition.fraction(previewFraction))
        .startExtent;
    return _offsetFrom(
      main: _previewMainOffset(
        renderMain: _main(renderSize),
        previewStartExtent: previewStart,
        dividerThickness: dividerThickness,
      ),
      cross: 0,
    );
  }

  void _setChildOffset(RenderBox? child, Offset offset) {
    if (child == null) return;
    (child.parentData! as _SplitterParentData).offset = offset;
  }

  @override
  void performLayout() {
    assert(_debugValidateSlots());

    final mainMax = _maxMain(constraints);
    if (!mainMax.isFinite) {
      _performUnboundedMainAxisLayout();
      return;
    }

    final renderMain = mainMax > 0 ? mainMax : 0.0;
    final effectiveDividerThickness = _clampedSplitterDividerThickness(
      _dividerThickness,
      renderMain,
    );
    final available = math.max(0.0, renderMain - effectiveDividerThickness);
    final interactiveSlop = _splitterInteractiveSlop(
      interactiveExtent: _interactiveExtent,
      dividerThickness: effectiveDividerThickness,
      resizable: _resizable,
    );
    final dividerInteractiveExtent =
        effectiveDividerThickness + interactiveSlop * 2;

    final solver = _solverFor(available);
    final solution = solver.solve(_position);
    final gap = (available - solution.startExtent - solution.endExtent).clamp(
      0.0,
      available,
    );

    final start = _childForSlot(_SplitterSlot.start);
    final end = _childForSlot(_SplitterSlot.end);
    final divider = _childForSlot(_SplitterSlot.divider);
    final preview = _childForSlot(_SplitterSlot.preview);

    final crossBounded = _maxCross(constraints).isFinite;
    final double renderCross;

    if (crossBounded) {
      renderCross = _maxCross(constraints) > 0 ? _maxCross(constraints) : 0.0;
      start?.layout(
        _paneConstraints(
          parent: constraints,
          mainExtent: solution.startExtent,
          tightCrossExtent: renderCross,
        ),
      );
      end?.layout(
        _paneConstraints(
          parent: constraints,
          mainExtent: solution.endExtent,
          tightCrossExtent: renderCross,
        ),
      );
    } else {
      start?.layout(
        _paneConstraints(
          parent: constraints,
          mainExtent: solution.startExtent,
          tightCrossExtent: null,
        ),
        parentUsesSize: true,
      );
      end?.layout(
        _paneConstraints(
          parent: constraints,
          mainExtent: solution.endExtent,
          tightCrossExtent: null,
        ),
        parentUsesSize: true,
      );
      final startCross = _paneCrossExtent(start, solution.startExtent);
      final endCross = _paneCrossExtent(end, solution.endExtent);
      renderCross = _constrainCross(
        constraints,
        renderMain,
        math.max(startCross, endCross),
      );
    }

    size = constraints.constrain(
      _sizeFrom(main: renderMain, cross: renderCross),
    );

    divider?.layout(
      _dividerConstraints(
        mainExtent: dividerInteractiveExtent,
        crossExtent: _cross(size),
      ),
    );
    preview?.layout(
      _dividerConstraints(
        mainExtent: effectiveDividerThickness,
        crossExtent: _cross(size),
      ),
    );

    final startCrossOffset = crossBounded || start == null
        ? 0.0
        : math.max(0.0, (_cross(size) - _cross(start.size)) / 2);
    final endCrossOffset = crossBounded || end == null
        ? 0.0
        : math.max(0.0, (_cross(size) - _cross(end.size)) / 2);

    _setChildOffset(
      start,
      _offsetFrom(
        main: _startMainOffset(_main(size), solution.startExtent),
        cross: startCrossOffset,
      ),
    );
    _setChildOffset(
      end,
      _offsetFrom(
        main: _endMainOffset(
          startExtent: solution.startExtent,
          dividerThickness: effectiveDividerThickness,
          gapExtent: gap,
        ),
        cross: endCrossOffset,
      ),
    );
    _setChildOffset(
      divider,
      _offsetFrom(
        main: _dividerMainOffset(
          renderMain: _main(size),
          startExtent: solution.startExtent,
          dividerThickness: effectiveDividerThickness,
          interactiveSlop: interactiveSlop,
        ),
        cross: 0,
      ),
    );

    _lastSolver = solver;
    _lastEffectiveDividerThickness = effectiveDividerThickness;

    _setChildOffset(
      preview,
      _previewOffsetFor(
        solver: solver,
        renderSize: size,
        dividerThickness: effectiveDividerThickness,
      ),
    );

    final layout = SplitterLayout(
      effectiveFraction: solution.effectiveFraction,
      startExtent: solution.startExtent,
      endExtent: solution.endExtent,
      availableExtent: solver.available,
      minStartExtent: solution.minStartExtent,
      maxStartExtent: solution.maxStartExtent,
      resolution: solution.resolution,
      collapsedPane: solution.startCollapsed
          ? SplitterPane.start
          : solution.endCollapsed
          ? SplitterPane.end
          : null,
    );

    onGeometryChanged(
      _ResolvedSplitterGeometry(
        controller: _controller,
        config: _config,
        requestedPosition: _position,
        requestedCollapsedPane: _collapsedPane,
        solver: solver,
        solution: solution,
        layout: layout,
        axis: _axis,
        textDirection: _textDirection,
        dividerThickness: effectiveDividerThickness,
        interactiveSlop: interactiveSlop,
        gapExtent: gap,
        size: size,
      ),
    );
  }

  // Unbounded main axis (shrinkToChildren): shrink-wrap the two panes at their
  // intrinsic main size, side by side, with no divider gap - the render-object
  // equivalent of the old `Flex([start, end])` fallback.
  void _performUnboundedMainAxisLayout() {
    final start = _childForSlot(_SplitterSlot.start);
    final end = _childForSlot(_SplitterSlot.end);
    final divider = _childForSlot(_SplitterSlot.divider);
    final preview = _childForSlot(_SplitterSlot.preview);

    final loose = constraints.loosen();
    start?.layout(loose, parentUsesSize: true);
    end?.layout(loose, parentUsesSize: true);
    divider?.layout(BoxConstraints.tight(Size.zero));
    preview?.layout(BoxConstraints.tight(Size.zero));

    final startMain = start == null ? 0.0 : _main(start.size);
    final endMain = end == null ? 0.0 : _main(end.size);
    final startCross = start == null ? 0.0 : _cross(start.size);
    final endCross = end == null ? 0.0 : _cross(end.size);

    size = constraints.constrain(
      _sizeFrom(
        main: startMain + endMain,
        cross: math.max(startCross, endCross),
      ),
    );

    _setChildOffset(
      start,
      _offsetFrom(
        main: _horizontalRtl ? _main(size) - startMain : 0,
        cross: math.max(0.0, (_cross(size) - startCross) / 2),
      ),
    );
    _setChildOffset(
      end,
      _offsetFrom(
        main: _horizontalRtl ? 0 : startMain,
        cross: math.max(0.0, (_cross(size) - endCross) / 2),
      ),
    );
    _setChildOffset(divider, Offset.zero);
    _setChildOffset(preview, Offset.zero);

    _lastSolver = null;
    _lastEffectiveDividerThickness = 0;
    onGeometryChanged(null);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final mainMax = _maxMain(constraints);
    if (!mainMax.isFinite) {
      final start = _childForSlot(_SplitterSlot.start);
      final end = _childForSlot(_SplitterSlot.end);
      final startSize = start?.getDryLayout(constraints.loosen()) ?? Size.zero;
      final endSize = end?.getDryLayout(constraints.loosen()) ?? Size.zero;
      return constraints.constrain(
        _sizeFrom(
          main: _main(startSize) + _main(endSize),
          cross: math.max(_cross(startSize), _cross(endSize)),
        ),
      );
    }

    final renderMain = mainMax > 0 ? mainMax : 0.0;
    final effectiveDividerThickness = _clampedSplitterDividerThickness(
      _dividerThickness,
      renderMain,
    );
    final available = math.max(0.0, renderMain - effectiveDividerThickness);
    final solver = _solverFor(available);
    final solution = solver.solve(_position);

    final crossBounded = _maxCross(constraints).isFinite;
    final renderCross = crossBounded
        ? (_maxCross(constraints) > 0 ? _maxCross(constraints) : 0.0)
        : _dryCrossForPanes(
            constraints: constraints,
            startExtent: solution.startExtent,
            endExtent: solution.endExtent,
            mainExtent: renderMain,
          );

    return constraints.constrain(
      _sizeFrom(main: renderMain, cross: renderCross),
    );
  }

  double _dryCrossForPanes({
    required BoxConstraints constraints,
    required double startExtent,
    required double endExtent,
    required double mainExtent,
  }) {
    final start = _childForSlot(_SplitterSlot.start);
    final end = _childForSlot(_SplitterSlot.end);
    final startSize =
        start?.getDryLayout(
          _paneConstraints(
            parent: constraints,
            mainExtent: startExtent,
            tightCrossExtent: null,
          ),
        ) ??
        Size.zero;
    final endSize =
        end?.getDryLayout(
          _paneConstraints(
            parent: constraints,
            mainExtent: endExtent,
            tightCrossExtent: null,
          ),
        ) ??
        Size.zero;
    return _constrainCross(
      constraints,
      mainExtent,
      math.max(
        _hasPaneMainExtent(startExtent) ? _cross(startSize) : 0.0,
        _hasPaneMainExtent(endExtent) ? _cross(endSize) : 0.0,
      ),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => _axis.isH
      ? _mainIntrinsic(
          crossExtent: height,
          getter: (c, cross) => c.getMinIntrinsicWidth(cross),
        )
      : _crossIntrinsic(
          mainExtent: height,
          getter: (c, main) => c.getMinIntrinsicWidth(main),
        );

  @override
  double computeMaxIntrinsicWidth(double height) => _axis.isH
      ? _mainIntrinsic(
          crossExtent: height,
          getter: (c, cross) => c.getMaxIntrinsicWidth(cross),
        )
      : _crossIntrinsic(
          mainExtent: height,
          getter: (c, main) => c.getMaxIntrinsicWidth(main),
        );

  @override
  double computeMinIntrinsicHeight(double width) => _axis.isH
      ? _crossIntrinsic(
          mainExtent: width,
          getter: (c, main) => c.getMinIntrinsicHeight(main),
        )
      : _mainIntrinsic(
          crossExtent: width,
          getter: (c, cross) => c.getMinIntrinsicHeight(cross),
        );

  @override
  double computeMaxIntrinsicHeight(double width) => _axis.isH
      ? _crossIntrinsic(
          mainExtent: width,
          getter: (c, main) => c.getMaxIntrinsicHeight(main),
        )
      : _mainIntrinsic(
          crossExtent: width,
          getter: (c, cross) => c.getMaxIntrinsicHeight(cross),
        );

  // Main-axis intrinsic = start + divider + end (the divider's full thickness).
  double _mainIntrinsic({
    required double crossExtent,
    required double Function(RenderBox child, double crossExtent) getter,
  }) {
    final start = _childForSlot(_SplitterSlot.start);
    final end = _childForSlot(_SplitterSlot.end);
    final startMain = start == null ? 0.0 : getter(start, crossExtent);
    final endMain = end == null ? 0.0 : getter(end, crossExtent);
    final divider = _dividerThickness.isFinite && _dividerThickness > 0
        ? _dividerThickness
        : 0.0;
    return startMain + divider + endMain;
  }

  // Cross-axis intrinsic = the taller/wider pane at its solved main extent.
  double _crossIntrinsic({
    required double mainExtent,
    required double Function(RenderBox child, double mainExtent) getter,
  }) {
    final start = _childForSlot(_SplitterSlot.start);
    final end = _childForSlot(_SplitterSlot.end);

    if (!mainExtent.isFinite || mainExtent <= 0) {
      final startCross = _crossIntrinsicForPane(
        child: start,
        mainExtent: _startRequestedCollapsed
            ? _config.start.collapsedExtent ?? 0.0
            : double.infinity,
        getter: getter,
      );
      final endCross = _crossIntrinsicForPane(
        child: end,
        mainExtent: _endRequestedCollapsed
            ? _config.end.collapsedExtent ?? 0.0
            : double.infinity,
        getter: getter,
      );
      return math.max(startCross, endCross);
    }

    final divider = _clampedSplitterDividerThickness(
      _dividerThickness,
      mainExtent,
    );
    final solver = _solverFor(math.max(0.0, mainExtent - divider));
    final solution = solver.solve(_position);
    final startCross = _crossIntrinsicForPane(
      child: start,
      mainExtent: solution.startExtent,
      getter: getter,
    );
    final endCross = _crossIntrinsicForPane(
      child: end,
      mainExtent: solution.endExtent,
      getter: getter,
    );
    return math.max(startCross, endCross);
  }

  double _crossIntrinsicForPane({
    required RenderBox? child,
    required double mainExtent,
    required double Function(RenderBox child, double mainExtent) getter,
  }) {
    if (child == null || !_hasPaneMainExtent(mainExtent)) return 0.0;
    return getter(child, mainExtent);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => null;

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(_debugValidateSlots());
    _paintPane(context, offset, _childForSlot(_SplitterSlot.start));
    _paintPane(context, offset, _childForSlot(_SplitterSlot.end));
    _paintClippedToSplitter(
      context,
      offset,
      _childForSlot(_SplitterSlot.divider),
    );
    if (_previewFraction != null) {
      _paintClippedToSplitter(
        context,
        offset,
        _childForSlot(_SplitterSlot.preview),
      );
    }
  }

  // Each pane is clipped to its own box so content cannot bleed across the
  // divider (replaces the old per-pane ClipRect widgets).
  void _paintPane(PaintingContext context, Offset offset, RenderBox? child) {
    if (child == null) return;
    final childOffset =
        offset + (child.parentData! as _SplitterParentData).offset;
    context.pushClipRect(
      needsCompositing,
      childOffset,
      Offset.zero & child.size,
      (context, clippedOffset) => context.paintChild(child, clippedOffset),
    );
  }

  // The divider/preview are clipped to the splitter bounds (as the old Stack
  // did), but only when they actually exceed them, to avoid a needless layer.
  void _paintClippedToSplitter(
    PaintingContext context,
    Offset offset,
    RenderBox? child,
  ) {
    if (child == null) return;
    final childOffset = (child.parentData! as _SplitterParentData).offset;
    final childRect = childOffset & child.size;
    final bounds = Offset.zero & size;
    final fullyInside =
        childRect.left >= bounds.left &&
        childRect.top >= bounds.top &&
        childRect.right <= bounds.right &&
        childRect.bottom <= bounds.bottom;
    if (fullyInside) {
      context.paintChild(child, offset + childOffset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      bounds,
      (context, clippedOffset) =>
          context.paintChild(child, clippedOffset + childOffset),
    );
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    assert(_debugValidateSlots());
    // Divider first so it wins inside the transparent interactive slop that
    // overlaps the panes (the old Stack achieved this by painting the handle on
    // top; reverse-paint-order hit testing would otherwise let a pane win).
    return _hitTestChild(
          result,
          _childForSlot(_SplitterSlot.divider),
          position,
        ) ||
        _hitTestChild(result, _childForSlot(_SplitterSlot.start), position) ||
        _hitTestChild(result, _childForSlot(_SplitterSlot.end), position);
  }

  bool _hitTestChild(
    BoxHitTestResult result,
    RenderBox? child,
    Offset position,
  ) {
    if (child == null) return false;
    final parentData = child.parentData! as _SplitterParentData;
    return result.addWithPaintOffset(
      offset: parentData.offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as _SplitterParentData).offset;
    transform.multiply(Matrix4.translationValues(offset.dx, offset.dy, 0));
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<Axis>('axis', _axis))
      ..add(EnumProperty<TextDirection>('textDirection', _textDirection))
      ..add(DiagnosticsProperty<SplitterPosition>('position', _position))
      ..add(
        DiagnosticsProperty<SplitterPane?>(
          'collapsedPane',
          _collapsedPane,
          defaultValue: null,
        ),
      )
      ..add(DoubleProperty('dividerThickness', _dividerThickness))
      ..add(DoubleProperty('interactiveExtent', _interactiveExtent))
      ..add(DiagnosticsProperty<bool>('resizable', _resizable))
      ..add(DiagnosticsProperty<SplitterSolverConfig>('config', _config))
      ..add(DoubleProperty('previewFraction', _previewFraction));
  }
}
