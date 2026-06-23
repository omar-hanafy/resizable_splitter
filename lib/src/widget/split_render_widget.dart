part of 'resizable_splitter.dart';

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
    if (parent is _RenderResizableSplitter) {
      parent
        .._invalidateSlotCache()
        ..markNeedsLayout();
    }
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
