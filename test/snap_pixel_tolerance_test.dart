import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 3 tail: a snap tolerance expressed in logical pixels, so the snap
/// feel is the same regardless of container size (ratio tolerance is not).
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(SplitterController controller, SplitterSnapBehavior snap) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 408,
              height: 240,
              child: ResizableSplitter(
                controller: controller,
                divider: const SplitterDividerStyle(thickness: 8),
                startConstraints: const SplitterPaneConstraints(),
                endConstraints: const SplitterPaneConstraints(),
                semanticsLabel: 'handle',
                snap: snap,
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      );

  // available = 408 - 8 = 400; the 0.75 snap point sits at 300px.
  testWidgets('snaps when released within the pixel tolerance', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        controller,
        const SplitterSnapBehavior(points: [0.75], pixelTolerance: 12),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(92, 0)); // 200 -> 292px, 8px from 300
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.effectiveFraction, closeTo(0.75, 1e-6));
  });

  testWidgets('does not snap beyond the pixel tolerance', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        controller,
        const SplitterSnapBehavior(points: [0.75], pixelTolerance: 12),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0)); // 200 -> 280px, 20px from 300
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.effectiveFraction, closeTo(280 / 400, 1e-6));
  });
}
