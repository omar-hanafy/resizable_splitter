import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 2 regressions: every interaction now operates on the *effective*
/// (visible) position, so the stored value can no longer disagree with what is
/// drawn. These lock the invariants, not just the originally reported inputs.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  // width 408, divider 8 => available 400. minStart 200 pins the visible start
  // fraction at 0.5 even though the controller requested 0.10.
  Widget host({
    required SplitterController controller,
    ValueChanged<double>? onDragStart,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 408,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            dividerThickness: 8,
            minPanelSize: 0,
            minStartPanelSize: 200,
            semanticsLabel: 'handle',
            onDragStart: onDragStart,
            startPanel: const SizedBox(),
            endPanel: const SizedBox(),
          ),
        ),
      ),
    ),
  );

  testWidgets('onDragStart reports the effective position, not the stored '
      'request', (tester) async {
    final controller = SplitterController(initialRatio: 0.10);
    double? dragStart;

    await tester.pumpWidget(
      host(controller: controller, onDragStart: (v) => dragStart = v),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();

    // The pane is pinned at 200/400 = 0.5; the callback says so (it used to
    // report the never-visible stored 0.10).
    expect(dragStart, closeTo(0.5, 1e-6));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a small drag moves the divider immediately (no dead zone)', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.10);

    await tester.pumpWidget(host(controller: controller));

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();

    // 8px right. Because the drag begins at the effective 0.5 (not the stored
    // 0.10), the divider moves at once. The old code stayed pinned at 0.5 until
    // the pointer travelled ~160px (0.5 - 0.10 of 400px) of dead zone.
    await gesture.moveBy(const Offset(8, 0));
    await tester.pump();

    expect(controller.value, greaterThan(0.5));
    expect(controller.value, closeTo(208 / 400, 1e-6));

    await gesture.up();
    await tester.pumpAndSettle();

    // Stored == visible after the gesture.
    expect(controller.value, closeTo(208 / 400, 1e-6));
  });

  testWidgets('a non-finite controller value cannot corrupt the layout', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.4);

    await tester.pumpWidget(host(controller: controller));

    // Bypassing updateRatio's clamp by writing the ValueNotifier directly used
    // to be able to push NaN into a SizedBox. The solver sanitizes it now.
    controller.value = double.nan;
    await tester.pump();
    expect(tester.takeException(), isNull);

    controller.value = -100;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
