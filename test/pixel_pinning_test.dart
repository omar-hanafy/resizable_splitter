import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 6: a pixel-pinned position is stored as the durable request and
/// re-resolved every layout, so a pinned pane keeps its width as the container
/// resizes. A drag releases the pin to a fraction.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required double width,
    SplitterController? controller,
    SplitterPosition initialPosition = const SplitterPosition.fraction(0.5),
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            initialPosition: initialPosition,
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      ),
    ),
  );

  double startWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('start'))).width;

  // Widths stay within the 800px default test surface so Center does not clamp.
  testWidgets('a start-pixel pin keeps its width as the container grows', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        width: 400,
        initialPosition: const SplitterPosition.startPixels(200),
      ),
    );
    expect(startWidth(tester), closeTo(200, 1e-6));

    // Same State, wider container: a fraction would have grown the pane, but the
    // stored pixel request re-resolves to the same 200px.
    await tester.pumpWidget(
      host(
        width: 760,
        initialPosition: const SplitterPosition.startPixels(200),
      ),
    );
    expect(startWidth(tester), closeTo(200, 1e-6));
  });

  testWidgets(
    'an end-pixel pin keeps the end pane fixed as the container grows',
    (tester) async {
      await tester.pumpWidget(
        host(
          width: 400,
          initialPosition: const SplitterPosition.endPixels(150),
        ),
      );
      // available = 400 - 8 = 392; end pinned at 150 => start = 242.
      expect(startWidth(tester), closeTo(242, 1e-6));

      await tester.pumpWidget(
        host(
          width: 760,
          initialPosition: const SplitterPosition.endPixels(150),
        ),
      );
      // available = 760 - 8 = 752; end still 150 => start = 602.
      expect(startWidth(tester), closeTo(602, 1e-6));
    },
  );

  testWidgets('assigning a startPixels position pins the pane', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(host(width: 600, controller: controller));
    expect(startWidth(tester), closeTo((600 - 8) / 2, 1e-6));

    controller.jumpTo(const SplitterPosition.startPixels(150));
    await tester.pump();
    expect(startWidth(tester), closeTo(150, 1e-6));
    expect(controller.value.position, const SplitterPosition.startPixels(150));
  });

  testWidgets('a drag releases the pixel pin to a fraction', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.startPixels(200),
    );
    await tester.pumpWidget(host(width: 600, controller: controller));
    expect(startWidth(tester), closeTo(200, 1e-6));
    expect(controller.value.position, isA<StartPixelsSplitterPosition>());

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // The pin is gone: the request is now a fraction near (200 + 40) / 592.
    expect(controller.value.position, isA<FractionSplitterPosition>());
    expect(controller.effectiveFraction, closeTo(240 / 592, 1e-6));
  });
}
