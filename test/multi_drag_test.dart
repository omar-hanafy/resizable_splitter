import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 3 tail: the global stuck-drag router keys active drags by their
/// real pointer id, so two splitters can be dragged at once without their drag
/// sessions cross-wiring.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget splitter(SplitterController controller, String label) => SizedBox(
    height: 120,
    child: ResizableSplitter(
      controller: controller,
      divider: const SplitterDividerStyle(thickness: 8),
      startConstraints: const SplitterPaneConstraints(),
      endConstraints: const SplitterPaneConstraints(),
      semanticsLabel: label,
      start: const SizedBox(),
      end: const SizedBox(),
    ),
  );

  testWidgets('two splitters drag concurrently without cross-wiring', (
    tester,
  ) async {
    final a = SplitterController();
    final b = SplitterController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 408,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [splitter(a, 'A'), splitter(b, 'B')],
              ),
            ),
          ),
        ),
      ),
    );

    // available = 408 - 8 = 400; both centered.
    expect(a.effectiveFraction, closeTo(0.5, 1e-6));
    expect(b.effectiveFraction, closeTo(0.5, 1e-6));

    final gestureA = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('A')),
    );
    final gestureB = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('B')),
    );
    await tester.pump();

    // Drag A right (grow) and B left (shrink) at the same time.
    await gestureA.moveBy(const Offset(40, 0));
    await gestureB.moveBy(const Offset(-40, 0));
    await tester.pump();

    expect(a.isDragging, isTrue);
    expect(b.isDragging, isTrue);

    await gestureA.up();
    await gestureB.up();
    await tester.pumpAndSettle();

    expect(a.effectiveFraction, closeTo(240 / 400, 1e-6));
    expect(b.effectiveFraction, closeTo(160 / 400, 1e-6));
    expect(a.isDragging, isFalse);
    expect(b.isDragging, isFalse);
  });

  testWidgets('swapping the controller mid-drag releases the old one, not the '
      'new one (review #3)', (tester) async {
    final a = SplitterController();
    final b = SplitterController();
    var useA = true;
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 408,
              height: 120,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return ResizableSplitter(
                    controller: useA ? a : b,
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

    // Start a drag on controller A.
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(a.isDragging, isTrue);

    // Swap the controller out from under the active drag.
    setOuter(() => useA = false);
    await tester.pump();

    // The old controller is released (not stranded as dragging), and the new
    // controller - which never started a drag - was not flagged either.
    expect(a.isDragging, isFalse);
    expect(b.isDragging, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(a.isDragging, isFalse);
    expect(b.isDragging, isFalse);
  });
}
