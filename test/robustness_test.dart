import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 8: robustness gaps - a misbehaving callback or an unusual pointer
/// sequence must never strand the drag state machine (one session, teardown
/// always runs, no callback after teardown).
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child, {double width = 400}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: 240, child: child),
      ),
    ),
  );

  testWidgets(
    'a throwing onChanged during a live drag does not strand the drag',
    (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          ResizableSplitter(
            controller: controller,
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            onChanged: (_) => throw StateError('boom'),
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0)); // throws inside onChanged
      await tester.pump();
      // The throw surfaces, but the drag is still alive and consistent.
      expect(tester.takeException(), isStateError);

      await gesture.up();
      await tester.pumpAndSettle();
      // Teardown ran on release: not stranded.
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets('a throwing onChangeEnd does not strand the drag', (
    tester,
  ) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChangeEnd: (_) => throw StateError('boom'),
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isStateError);
    // onChangeEnd fires after teardown, so a throw there cannot strand state.
    expect(controller.isDragging, isFalse);
  });

  testWidgets('a second pointer on the handle does not start a second drag', (
    tester,
  ) async {
    final controller = SplitterController();
    var startCount = 0;
    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChangeStart: (_) => startCount++,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final center = tester.getCenter(find.bySemanticsLabel('handle'));
    final first = await tester.startGesture(center);
    await tester.pump();
    final second = await tester.startGesture(center);
    await tester.pump();
    await first.moveBy(const Offset(20, 0));
    await second.moveBy(const Offset(20, 0));
    await tester.pump();

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Exactly one drag session was started despite the two pointers.
    expect(startCount, 1);
    expect(controller.isDragging, isFalse);
  });

  testWidgets('a cancel then a fresh drag leaves a single, clean session', (
    tester,
  ) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );
    final handle = find.bySemanticsLabel('handle');

    // Drag, cancel, then drag again and release - the idempotent terminal must
    // leave exactly one clean outcome with no stranded session.
    final g1 = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await g1.moveBy(const Offset(25, 0));
    await tester.pump();
    await g1.cancel();
    await tester.pumpAndSettle();
    expect(controller.isDragging, isFalse);

    final g2 = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await g2.moveBy(const Offset(-25, 0));
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.isDragging, isFalse);
  });

  testWidgets('disposing mid-drag tears down without firing onChangeEnd', (
    tester,
  ) async {
    final controller = SplitterController();
    var ends = 0;
    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChangeEnd: (_) => ends++,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    // Remove the splitter mid-drag.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Disposal is a lifecycle teardown, not a gesture end: no onChangeEnd, and
    // the controller is not stranded as dragging.
    expect(ends, 0);
    expect(controller.isDragging, isFalse);
  });
}
