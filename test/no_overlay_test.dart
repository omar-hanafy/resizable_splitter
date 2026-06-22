import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Review issue #10: the drag platform-view shield needs an Overlay, but the
/// splitter must not *require* one. With no Overlay ancestor it degrades
/// gracefully (skips the shield) instead of throwing from `Overlay.of`.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('drags without an Overlay ancestor (no throw, shield skipped)', (
    tester,
  ) async {
    final controller = SplitterController();

    // No MaterialApp / Navigator, so there is no Overlay in the tree.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: SizedBox(
              width: 408,
              height: 240,
              child: ResizableSplitter(
                controller: controller,
                divider: const SplitterDividerStyle(thickness: 8),
                startConstraints: const SplitterPaneConstraints(),
                endConstraints: const SplitterPaneConstraints(),
                semanticsLabel: 'handle',
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    // The drag works even though the overlay shield could not be inserted.
    expect(tester.takeException(), isNull);
    expect(controller.effectiveFraction, closeTo(240 / 400, 1e-6));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.isDragging, isFalse);
  });
}
