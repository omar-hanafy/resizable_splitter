import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 7e: deferred resize. With [ResizableSplitter.deferredResize] the
/// panes do not re-lay-out during a drag (a preview line tracks the pointer);
/// the panes settle to the final position once, on release.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required SplitterController controller,
    ValueChanged<SplitterChangeDetails>? onChanged,
    SplitterSnapBehavior? snap,
    double width = 408,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            deferredResize: true,
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            snap: snap,
            onChanged: onChanged,
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      ),
    ),
  );

  double startWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('start'))).width;

  testWidgets('panes stay put during the drag and commit on release', (
    tester,
  ) async {
    final controller = SplitterController();
    final changes = <double>[];
    await tester.pumpWidget(
      host(
        controller: controller,
        onChanged: (d) => changes.add(d.effectiveFraction),
      ),
    );
    expect(startWidth(tester), closeTo(200, 1e-6)); // available 400, centered

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    // Deferred: the panes have not resized, and no onChanged has fired yet.
    expect(startWidth(tester), closeTo(200, 1e-6));
    expect(controller.effectiveFraction, closeTo(0.5, 1e-6));
    expect(changes, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();

    // Settled once, on release.
    expect(startWidth(tester), closeTo(240, 1e-6));
    expect(controller.effectiveFraction, closeTo(240 / 400, 1e-6));
    expect(changes, isNotEmpty);
  });

  testWidgets('a deferred drag still snaps on release', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        controller: controller,
        snap: SplitterSnapBehavior(points: [0.75], tolerance: 0.2),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0)); // toward 0.7
    await tester.pump();
    expect(startWidth(tester), closeTo(200, 1e-6)); // still deferred

    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.effectiveFraction, closeTo(0.75, 1e-6));
  });
}
