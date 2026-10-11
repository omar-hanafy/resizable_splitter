import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('splitter supports intrinsic baseline-aligned rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 408,
                  child: ResizableSplitter(
                    start: Text('start'),
                    end: Text('end'),
                  ),
                ),
                Text('peer'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final startBox = tester.renderObject<RenderBox>(find.text('start'));
    final peerBox = tester.renderObject<RenderBox>(find.text('peer'));
    final startBaseline =
        startBox.localToGlobal(Offset.zero).dy +
        startBox.getDistanceToBaseline(TextBaseline.alphabetic)!;
    final peerBaseline =
        peerBox.localToGlobal(Offset.zero).dy +
        peerBox.getDistanceToBaseline(TextBaseline.alphabetic)!;
    expect(startBaseline, closeTo(peerBaseline, 1e-9));
  });

  for (final axis in Axis.values) {
    for (final boundedAxis in [null, Axis.horizontal, Axis.vertical]) {
      final boundedDescription = boundedAxis == null
          ? 'both axes'
          : '${boundedAxis.name} axis';
      testWidgets('dry baseline matches ${axis.name} RTL layout with '
          '$boundedDescription bounded', (tester) async {
        Widget child = ResizableSplitter(
          axis: axis,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          start: const SizedBox(width: 90, height: 60),
          end: const Text('end baseline'),
        );
        if (boundedAxis == null) {
          child = SizedBox(width: 408, height: 240, child: child);
        } else {
          child = UnconstrainedBox(
            constrainedAxis: boundedAxis,
            child: SizedBox(
              width: boundedAxis == Axis.horizontal ? 408 : null,
              height: boundedAxis == Axis.vertical ? 240 : null,
              child: child,
            ),
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(child: child),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final box = tester.renderObject<RenderBox>(
          find.byType(ResizableSplitter),
        );
        for (final baseline in TextBaseline.values) {
          expect(
            box.getDryBaseline(box.constraints, baseline),
            closeTo(box.getDistanceToBaseline(baseline, onlyReal: true)!, 1e-9),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a splitter with no child baseline has no dry baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 408,
            height: 240,
            child: ResizableSplitter(start: SizedBox(), end: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(ResizableSplitter));
    for (final baseline in TextBaseline.values) {
      expect(box.getDryBaseline(box.constraints, baseline), isNull);
      expect(box.getDistanceToBaseline(baseline, onlyReal: true), isNull);
    }
  });
}
