import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Review issue #7: with `snapToPhysicalPixels` on, the pixel snap must apply
/// to *every* solve (layout, drag, callbacks, the published layout) - not only
/// the layout - so a callback can never report an extent the layout never drew.
/// The snap config now lives on the solver, so all of its solves snap alike.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('callbacks and the published layout match the drawn snapped '
      'extents (review #7)', (tester) async {
    final controller = SplitterController();
    SplitterChangeDetails? end;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // Fractional dpr so the snap actually moves the extent.
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(devicePixelRatio: 2.5),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 411, // odd width: a centered split needs snapping
                    height: 240,
                    child: ResizableSplitter(
                      controller: controller,
                      divider: const SplitterDividerStyle(thickness: 7),
                      startConstraints: const SplitterPaneConstraints(),
                      endConstraints: const SplitterPaneConstraints(),
                      snapToPhysicalPixels: true,
                      semanticsLabel: 'handle',
                      onChangeEnd: (d) => end = d,
                      start: const SizedBox(key: Key('start')),
                      end: const SizedBox(key: Key('end')),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(23, 0)); // an off-pixel amount
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final drawnStart = tester.getSize(find.byKey(const Key('start'))).width;

    expect(end, isNotNull);
    // The callback extent equals the drawn (snapped) extent - not an unsnapped
    // solve the layout never used.
    expect(end!.startExtent, closeTo(drawnStart, 1e-9));
    // It is genuinely snapped to a physical pixel at dpr 2.5.
    final physical = end!.startExtent * 2.5;
    expect((physical - physical.roundToDouble()).abs(), lessThan(1e-9));
    // The controller's published layout agrees with the drawn extent too.
    expect(controller.layout!.startExtent, closeTo(drawnStart, 1e-9));
  });
}
