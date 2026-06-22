import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 7: the layout contract - the acceptance gate for the future 2.1
/// internal RenderObject rewrite.
///
/// Every assertion here is **behavioral or geometric** (measured pane rects,
/// the reported [SplitterLayout], the effect of a drag) and never inspects the
/// widget tree shape (no `find.byType(Stack/Flex/Positioned)`), so it must pass
/// identically before and after the layout layer is swapped for a render object.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required Widget child,
    double width = 400,
    double height = 240,
    TextDirection textDirection = TextDirection.ltr,
  }) => MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );

  Widget splitter({
    required SplitterController controller,
    Axis axis = Axis.horizontal,
    SplitterPaneConstraints start = const SplitterPaneConstraints(),
    SplitterPaneConstraints end = const SplitterPaneConstraints(),
    SplitterSurplusPolicy surplusPolicy = SplitterSurplusPolicy.leaveGap,
    SplitterDividerStyle? divider,
  }) => ResizableSplitter(
    controller: controller,
    axis: axis,
    startConstraints: start,
    endConstraints: end,
    surplusPolicy: surplusPolicy,
    divider: divider,
    semanticsLabel: 'handle',
    start: Container(key: const Key('start')),
    end: Container(key: const Key('end')),
  );

  // The main-axis size of a keyed pane.
  double mainSize(WidgetTester tester, Key key, Axis axis) {
    final size = tester.getSize(find.byKey(key));
    return axis == Axis.horizontal ? size.width : size.height;
  }

  group('geometry coheres with the reported layout', () {
    for (final axis in Axis.values) {
      for (final dir in TextDirection.values) {
        testWidgets('$axis / $dir: pane sizes match layout extents', (
          tester,
        ) async {
          final controller = SplitterController(
            initialPosition: const SplitterPosition.fraction(0.35),
          );
          await tester.pumpWidget(
            host(
              textDirection: dir,
              child: splitter(controller: controller, axis: axis),
            ),
          );
          await tester.pumpAndSettle();

          final layout = controller.layout!;
          expect(
            mainSize(tester, const Key('start'), axis),
            closeTo(layout.startExtent, 0.5),
          );
          expect(
            mainSize(tester, const Key('end'), axis),
            closeTo(layout.endExtent, 0.5),
          );
          // The two panes plus the divider account for the whole main extent.
          final total =
              mainSize(tester, const Key('start'), axis) +
              mainSize(tester, const Key('end'), axis);
          expect(total, lessThanOrEqualTo(layout.availableExtent + 0.5));
        });
      }
    }

    testWidgets('a horizontal LTR splitter puts the start pane on the left', (
      tester,
    ) async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.4),
      );
      await tester.pumpWidget(host(child: splitter(controller: controller)));
      await tester.pumpAndSettle();

      final startRect = tester.getRect(find.byKey(const Key('start')));
      final endRect = tester.getRect(find.byKey(const Key('end')));
      expect(startRect.left, lessThan(endRect.left));
    });

    testWidgets('a horizontal RTL splitter puts the start pane on the right', (
      tester,
    ) async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.4),
      );
      await tester.pumpWidget(
        host(
          textDirection: TextDirection.rtl,
          child: splitter(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      final startRect = tester.getRect(find.byKey(const Key('start')));
      final endRect = tester.getRect(find.byKey(const Key('end')));
      expect(startRect.left, greaterThan(endRect.left));
    });
  });

  group('pixel pins and constraints', () {
    testWidgets('a start pixel pin resolves to that many logical pixels', (
      tester,
    ) async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.startPixels(150),
      );
      await tester.pumpWidget(host(child: splitter(controller: controller)));
      await tester.pumpAndSettle();

      expect(
        mainSize(tester, const Key('start'), Axis.horizontal),
        closeTo(150, 0.5),
      );
    });

    testWidgets('a hard pixel minimum overrides a conflicting fractional cap', (
      tester,
    ) async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0),
      );
      await tester.pumpWidget(
        host(
          child: ResizableSplitter(
            controller: controller,
            // The fractional cap says start <= 30% (~118px), but the start pane's
            // own 200px hard minimum says start >= 200px. They conflict; the
            // pixel limit must win, so the start lands at 200px (not 118), and
            // the layer reports the conflict.
            maxStartFraction: 0.3,
            startConstraints: const SplitterPaneConstraints(minExtent: 200),
            endConstraints: const SplitterPaneConstraints(minExtent: 0),
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        mainSize(tester, const Key('start'), Axis.horizontal),
        closeTo(200, 0.5),
      );
      expect(
        controller.layout!.resolution,
        SplitterResolution.fractionConflict,
      );
    });

    testWidgets('leaveGap keeps both maxima and leaves a gap between the panes', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          child: splitter(
            controller: controller,
            // Both panes cap at 100px; 200 < 394 available, so the rest is a gap.
            start: const SplitterPaneConstraints(maxExtent: 100),
            end: const SplitterPaneConstraints(maxExtent: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        mainSize(tester, const Key('start'), Axis.horizontal),
        closeTo(100, 0.5),
      );
      expect(
        mainSize(tester, const Key('end'), Axis.horizontal),
        closeTo(100, 0.5),
      );
      expect(controller.layout!.resolution, SplitterResolution.maxSurplus);
    });
  });

  group('the interactive hit region', () {
    testWidgets('overlaps each pane by the effective slop', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          child: splitter(
            controller: controller,
            divider: const SplitterDividerStyle(
              thickness: 10,
              interactiveExtent: 50, // slop = (50 - 10) / 2 = 20
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startRect = tester.getRect(find.byKey(const Key('start')));
      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      // The catcher is interactiveExtent wide and starts `slop` inside the start
      // pane: this is the geometry a render-object hit test must reproduce.
      expect(handleRect.width, closeTo(50, 0.5));
      expect(handleRect.left, closeTo(startRect.right - 20, 0.5));
    });
  });

  group('drag direction', () {
    testWidgets('LTR: dragging right grows the start pane', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(host(child: splitter(controller: controller)));
      await tester.pumpAndSettle();
      final before = mainSize(tester, const Key('start'), Axis.horizontal);

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        mainSize(tester, const Key('start'), Axis.horizontal),
        greaterThan(before),
      );
    });

    testWidgets('RTL: dragging right shrinks the start pane', (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          textDirection: TextDirection.rtl,
          child: splitter(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final before = mainSize(tester, const Key('start'), Axis.horizontal);

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        mainSize(tester, const Key('start'), Axis.horizontal),
        lessThan(before),
      );
    });
  });
}
