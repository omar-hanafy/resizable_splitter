import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 2: the drag is a single idempotent state machine. A cancel, a mid-drag
/// reconfiguration, a disposal, and a throwing callback can never strand the
/// controller as "dragging", fire a phantom onChangeEnd, or touch a disposed
/// controller.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 408, height: 240, child: child)),
    ),
  );

  testWidgets(
    'a gesture end after a mid-drag interrupt fires no phantom onChangeEnd',
    (tester) async {
      final controller = SplitterController();
      var resizable = true;
      late StateSetter setOuter;
      final ends = <SplitterChangeDetails>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 408,
                height: 240,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setOuter = setState;
                    return ResizableSplitter(
                      controller: controller,
                      resizable: resizable,
                      divider: const SplitterDividerStyle(thickness: 8),
                      startConstraints: const SplitterPaneConstraints(),
                      endConstraints: const SplitterPaneConstraints(),
                      semanticsLabel: 'handle',
                      onChangeEnd: ends.add,
                      start: const SizedBox(),
                      end: const SizedBox(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();

      // Turn off resizing mid-drag: the drag is interrupted (no end event).
      setOuter(() => resizable = false);
      await tester.pump();

      // The recognizer still delivers its end. The drag was already torn down,
      // so this must NOT fire a phantom onChangeEnd.
      await gesture.up();
      await tester.pumpAndSettle();

      expect(ends, isEmpty);
    },
  );

  testWidgets(
    'a throwing onChanged on release does not strand the drag (deferred mode)',
    (tester) async {
      final controller = SplitterController();

      await tester.pumpWidget(
        host(
          ResizableSplitter(
            controller: controller,
            deferredResize: true,
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            onChanged: (_) => throw StateError('boom'),
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0)); // deferred: preview only
      await tester.pump();
      await gesture.up(); // release commits, firing the throwing onChanged
      await tester.pump();

      // The framework reports the thrown error, but teardown still ran: the
      // controller is not stranded as "dragging".
      expect(tester.takeException(), isA<StateError>());
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets(
    'swapping from the internal to an external controller mid-drag does not '
    'crash (no use of a disposed controller)',
    (tester) async {
      final external = SplitterController();
      SplitterController? provided; // null => splitter uses its internal one
      late StateSetter setOuter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 408,
                height: 240,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setOuter = setState;
                    return ResizableSplitter(
                      controller: provided,
                      divider: const SplitterDividerStyle(thickness: 8),
                      startConstraints: const SplitterPaneConstraints(),
                      endConstraints: const SplitterPaneConstraints(),
                      semanticsLabel: 'handle',
                      start: const SizedBox(),
                      end: const SizedBox(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();

      // Swap in an external controller mid-drag: the internal one is replaced.
      setOuter(() => provided = external);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
