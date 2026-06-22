import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// RenderObject migration tests.
///
/// Two kinds live here:
///  * **New capability** the widget-layer `LayoutBuilder` impl could never give:
///    intrinsic sizing and dry layout. These FAIL before the render object lands
///    (a `LayoutBuilder` throws on an intrinsic query) and pass after.
///  * **Parity guarantees** the swap must preserve: painting is clipped to each
///    pane, the divider wins the hit test inside its interactive slop, physical
///    pixel snapping, collapse, and the unbounded shrink-wrap. Every assertion is
///    behavioral or geometric - never `find.byType(Stack/Flex/Positioned)`.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  const startKey = Key('start');
  const endKey = Key('end');
  const boundaryKey = Key('boundary');

  Widget host({
    required Widget child,
    double? width,
    double? height,
    TextDirection textDirection = TextDirection.ltr,
  }) => MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );

  ResizableSplitter splitter({
    required SplitterController controller,
    Axis axis = Axis.horizontal,
    SplitterPaneConstraints start = const SplitterPaneConstraints(),
    SplitterPaneConstraints end = const SplitterPaneConstraints(),
    SplitterSurplusPolicy surplusPolicy = SplitterSurplusPolicy.leaveGap,
    SplitterConstraintPolicy constraintPolicy =
        SplitterConstraintPolicy.favorStart,
    double thickness = 10,
    double? interactiveExtent,
    bool deferredResize = false,
    bool snapToPhysicalPixels = false,
    VoidCallback? onHandleTap,
    Widget? startChild,
    Widget? endChild,
  }) => ResizableSplitter(
    controller: controller,
    axis: axis,
    startConstraints: start,
    endConstraints: end,
    surplusPolicy: surplusPolicy,
    constraintPolicy: constraintPolicy,
    snapToPhysicalPixels: snapToPhysicalPixels,
    deferredResize: deferredResize,
    onHandleTap: onHandleTap,
    divider: SplitterDividerStyle(
      thickness: thickness,
      interactiveExtent: interactiveExtent,
    ),
    semanticsLabel: 'handle',
    start: startChild ?? const ColoredBox(key: startKey, color: Colors.red),
    end: endChild ?? const ColoredBox(key: endKey, color: Colors.blue),
  );

  double mainSize(WidgetTester tester, Key key, Axis axis) {
    final size = tester.getSize(find.byKey(key));
    return axis == Axis.horizontal ? size.width : size.height;
  }

  group('intrinsic sizing (new capability)', () {
    testWidgets('IntrinsicHeight sizes a horizontal splitter to its tallest '
        'pane', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          width: 300,
          child: IntrinsicHeight(
            child: splitter(
              controller: controller,
              thickness: 10,
              startChild: const SizedBox(key: startKey, height: 40),
              endChild: const SizedBox(key: endKey, height: 90),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The cross axis (height) shrink-wraps to the taller pane's intrinsic
      // height. A LayoutBuilder-based layout throws on this query.
      expect(
        tester.getSize(find.byType(ResizableSplitter)).height,
        closeTo(90, 0.5),
      );
    });

    testWidgets('IntrinsicHeight ignores a zero-width collapsed pane', (
      tester,
    ) async {
      final controller = SplitterController()..collapse(SplitterPane.start);
      await tester.pumpWidget(
        host(
          width: 300,
          child: IntrinsicHeight(
            child: splitter(
              controller: controller,
              thickness: 10,
              start: const SplitterPaneConstraints(
                minExtent: 50,
                collapsedExtent: 0,
              ),
              startChild: const SizedBox(key: startKey, height: 900),
              endChild: const SizedBox(key: endKey, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(ResizableSplitter)).height,
        closeTo(40, 0.5),
      );
    });

    testWidgets('IntrinsicWidth sums pane widths plus the divider', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          height: 100,
          child: IntrinsicWidth(
            child: splitter(
              controller: controller,
              thickness: 10,
              startChild: const SizedBox(key: startKey, width: 120, height: 50),
              endChild: const SizedBox(key: endKey, width: 80, height: 50),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 120 (start) + 10 (divider) + 80 (end) = 210.
      expect(
        tester.getSize(find.byType(ResizableSplitter)).width,
        closeTo(210, 0.5),
      );
    });
  });

  group('dry layout (new capability)', () {
    testWidgets('dry layout equals the real laid-out size', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(width: 400, height: 240, child: splitter(controller: controller)),
      );
      await tester.pumpAndSettle();

      final renderObject = tester.allRenderObjects.firstWhere(
        (r) => r.runtimeType.toString() == '_RenderResizableSplitter',
      );
      final dry = (renderObject as RenderBox).getDryLayout(
        BoxConstraints.tight(const Size(400, 240)),
      );
      expect(dry, const Size(400, 240));
    });
  });

  group('painting is clipped to each pane (parity)', () {
    testWidgets('start pane content cannot bleed past the divider', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          width: 400,
          height: 100,
          child: RepaintBoundary(
            key: boundaryKey,
            child: splitter(
              controller: controller,
              thickness: 0,
              // The red pane tries to paint 400px wide while its box is 200px;
              // without a clip it would bleed into the white end pane.
              startChild: const OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: 400,
                child: SizedBox(
                  key: startKey,
                  width: 400,
                  height: 100,
                  child: ColoredBox(color: Colors.red),
                ),
              ),
              endChild: const ColoredBox(key: endKey, color: Colors.white),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // x=300 is deep inside the end pane (start is [0,200]); it must be white.
      final color = await _sampleColor(tester, boundaryKey, 300, 50);
      expect(color, isSameColorAs(Colors.white));
    });
  });

  group('deferred preview (parity)', () {
    testWidgets('panes stay put during a deferred drag and move on release', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          width: 400,
          height: 100,
          child: splitter(
            controller: controller,
            thickness: 4,
            deferredResize: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialStart = controller.layout!.startExtent;

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      // Deferred: the committed geometry has not moved yet.
      expect(controller.layout!.startExtent, closeTo(initialStart, 0.5));

      await gesture.up();
      await tester.pumpAndSettle();
      // On release the committed geometry catches up.
      expect(controller.layout!.startExtent, greaterThan(initialStart + 10));
    });
  });

  group('geometry (parity)', () {
    testWidgets('horizontal LTR pane sizes and offsets', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(width: 500, height: 100, child: splitter(controller: controller)),
      );
      await tester.pumpAndSettle();

      // 500 wide, 10px divider => available 490, centered at x=150 in the 800
      // test surface.
      expect(mainSize(tester, startKey, Axis.horizontal), closeTo(245, 0.5));
      expect(mainSize(tester, endKey, Axis.horizontal), closeTo(245, 0.5));
      expect(tester.getRect(find.byKey(startKey)).left, closeTo(150, 0.5));
      expect(tester.getRect(find.byKey(endKey)).left, closeTo(405, 0.5));
    });

    testWidgets('physical-pixel snapping snaps the start extent', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(1 / 3),
      );
      await tester.pumpWidget(
        host(
          width: 102,
          height: 100,
          child: splitter(
            controller: controller,
            thickness: 1,
            snapToPhysicalPixels: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // available 101; 101/3 = 33.667; *2 -> 67.33 -> round 67 -> /2 = 33.5.
      expect(controller.layout!.availableExtent, closeTo(101, 0.001));
      expect(controller.layout!.startExtent, closeTo(33.5, 0.001));
    });

    testWidgets('a collapsed start pane uses its collapsedExtent', (
      tester,
    ) async {
      final controller = SplitterController()..collapse(SplitterPane.start);
      await tester.pumpWidget(
        host(
          width: 400,
          height: 100,
          child: splitter(
            controller: controller,
            start: const SplitterPaneConstraints(
              minExtent: 100,
              collapsedExtent: 20,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.layout!.collapsedPane, SplitterPane.start);
      expect(mainSize(tester, startKey, Axis.horizontal), closeTo(20, 0.5));
    });
  });

  group('hit testing (parity)', () {
    testWidgets('the divider wins the hit test inside its interactive slop', (
      tester,
    ) async {
      var handleTaps = 0;
      var paneTaps = 0;
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          width: 400,
          height: 100,
          child: splitter(
            controller: controller,
            thickness: 4,
            interactiveExtent: 44, // slop = (44 - 4) / 2 = 20
            onHandleTap: () => handleTaps++,
            startChild: GestureDetector(
              onTap: () => paneTaps++,
              child: const ColoredBox(key: startKey, color: Colors.red),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 10px inside the start pane's right edge - within the divider's slop.
      final startRect = tester.getRect(find.byKey(startKey));
      await tester.tapAt(Offset(startRect.right - 10, startRect.center.dy));
      await tester.pump();

      expect(handleTaps, 1);
      expect(paneTaps, 0);
    });
  });

  group('unbounded main axis (parity, mechanism changed)', () {
    testWidgets(
      'shrinkToChildren lays the panes at their intrinsic main size',
      (tester) async {
        final controller = SplitterController();
        await tester.pumpWidget(
          host(
            height: 100,
            child: UnconstrainedBox(
              constrainedAxis: Axis.vertical,
              child: splitter(
                controller: controller,
                thickness: 10,
                startChild: const SizedBox(
                  key: startKey,
                  width: 120,
                  height: 50,
                ),
                endChild: const SizedBox(key: endKey, width: 80, height: 50),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // No divider gap is inserted in the unbounded shrink-wrap; panes keep
        // their intrinsic widths.
        expect(mainSize(tester, startKey, Axis.horizontal), closeTo(120, 0.5));
        expect(mainSize(tester, endKey, Axis.horizontal), closeTo(80, 0.5));
      },
    );
  });
}

Future<Color> _sampleColor(
  WidgetTester tester,
  Key boundaryKey,
  int x,
  int y,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  // toImage()/toByteData() resolve on the engine, which needs real async - the
  // default fake-async test zone would deadlock, so run them via runAsync.
  final color = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final offset = (y * image.width + x) * 4;
    final sampled = Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
    image.dispose();
    return sampled;
  });
  return color!;
}
