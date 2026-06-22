import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Drag-path tests for the live snap modes (magnetic / sticky). The pure math is
/// covered in test/foundation/split_snap_engine_test.dart; these assert the
/// handle wires it into the drag, preview, settle, and callback paths.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  // 400 wide, 10px divider => 390px shared between the panes.
  const available = 390.0;

  Widget host({
    required SplitterController controller,
    required SplitterSnapBehavior snap,
    double width = 400,
    bool snapToPhysicalPixels = false,
    void Function(SplitterChangeDetails)? onChanged,
    void Function(SplitterChangeDetails)? onChangeEnd,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            divider: const SplitterDividerStyle(thickness: 10),
            semanticsLabel: 'handle',
            snap: snap,
            snapToPhysicalPixels: snapToPhysicalPixels,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            start: const SizedBox(key: Key('start')),
            end: const SizedBox(key: Key('end')),
          ),
        ),
      ),
    ),
  );

  Future<TestGesture> dragFromCenter(
    WidgetTester tester,
    double dxFraction,
  ) async {
    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(Offset(available * dxFraction, 0));
    await tester.pump();
    return gesture;
  }

  group('magnetic', () {
    testWidgets('pulls toward the point but can be pushed through', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.magnetic(
            points: const [0.6],
            tolerance: 0.2,
          ),
        ),
      );

      // Drag from 0.5 to a raw 0.55: inside 0.6's influence, so it is pulled
      // past the raw position toward 0.6, yet never pinned to it.
      final gesture = await dragFromCenter(tester, 0.05);
      expect(controller.effectiveFraction, greaterThan(0.55));
      expect(controller.effectiveFraction, lessThan(0.6));

      // Release commits exactly what was shown - no sudden correction onto 0.6.
      final beforeRelease = controller.effectiveFraction;
      await gesture.up();
      await tester.pump();
      expect(controller.effectiveFraction, closeTo(beforeRelease, 1e-9));
    });
  });

  group('sticky', () {
    testWidgets('captures exactly onto a point within the radius', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.sticky(
            points: const [0.6],
            tolerance: 0.2,
          ),
        ),
      );

      await dragFromCenter(tester, 0.05); // raw 0.55, within 0.2 of 0.6
      expect(controller.effectiveFraction, closeTo(0.6, 1e-9));
    });

    // A wider surface (790px shared) keeps the pointer well inside the splitter
    // across the larger travel these need. Moves use generous margins so the
    // gesture-recognizer's touch-slop does not flip a boundary assertion.
    testWidgets(
      'holds a captured point through a move inside the escape radius',
      (tester) async {
        final controller = SplitterController();
        await tester.pumpWidget(
          host(
            controller: controller,
            width: 800,
            snap: SplitterSnapBehavior.sticky(
              points: const [0.6],
              tolerance: 0.2, // escape radius = 0.3
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.bySemanticsLabel('handle')),
        );
        await tester.pump();

        await gesture.moveBy(
          const Offset(790 * 0.1, 0),
        ); // ~raw 0.58 -> capture
        await tester.pump();
        expect(controller.effectiveFraction, closeTo(0.6, 1e-9));

        await gesture.moveBy(
          const Offset(790 * 0.15, 0),
        ); // ~raw 0.72, still held
        await tester.pump();
        expect(controller.effectiveFraction, closeTo(0.6, 1e-9));

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'escapes past the hysteresis radius and reports a drag source',
      (tester) async {
        final controller = SplitterController();
        final sources = <SplitterChangeSource>[];
        await tester.pumpWidget(
          host(
            controller: controller,
            width: 800,
            snap: SplitterSnapBehavior.sticky(
              points: const [0.6],
              tolerance: 0.1, // escape radius = 0.15
            ),
            onChanged: (d) => sources.add(d.source),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.bySemanticsLabel('handle')),
        );
        await tester.pump();

        await gesture.moveBy(
          const Offset(790 * 0.1, 0),
        ); // ~raw 0.58 -> capture 0.6
        await tester.pump();
        expect(controller.effectiveFraction, closeTo(0.6, 1e-9));
        expect(sources, contains(SplitterChangeSource.snap));

        await gesture.moveBy(const Offset(790 * 0.3, 0)); // ~raw 0.86, d > 0.15
        await tester.pump();
        expect(controller.effectiveFraction, greaterThan(0.6));
        expect(sources, contains(SplitterChangeSource.drag));

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('a captured point stays put across a container resize', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.sticky(
            points: const [0.6],
            tolerance: 0.2,
          ),
        ),
      );

      final gesture = await dragFromCenter(tester, 0.05);
      expect(controller.effectiveFraction, closeTo(0.6, 1e-9));

      // Resize the container mid-capture, with no new pointer event.
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.sticky(
            points: const [0.6],
            tolerance: 0.2,
          ),
          width: 600,
        ),
      );
      expect(controller.effectiveFraction, closeTo(0.6, 1e-9));

      await gesture.up();
      await tester.pump();
    });
  });

  group('interruption', () {
    testWidgets('changing the snap behavior mid-drag interrupts (no end)', (
      tester,
    ) async {
      final controller = SplitterController();
      var endCount = 0;
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.sticky(
            points: const [0.6],
            tolerance: 0.2,
          ),
          onChangeEnd: (_) => endCount++,
        ),
      );

      final gesture = await dragFromCenter(tester, 0.05);

      // Swap to a different snap behavior: the in-flight drag must be dropped.
      await tester.pumpWidget(
        host(
          controller: controller,
          snap: SplitterSnapBehavior.sticky(
            points: const [0.3],
            tolerance: 0.2,
          ),
          onChangeEnd: (_) => endCount++,
        ),
      );

      await gesture.up();
      await tester.pump();
      expect(endCount, 0); // an interrupted drag fires no onChangeEnd
    });
  });
}
