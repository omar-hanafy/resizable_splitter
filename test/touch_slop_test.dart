import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 4 (review B): the divider is an explicit affordance and should grab
/// almost immediately on touch, not wait for the default ~18px drag slop.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('a small touch drag grabs the divider (no ~18px dead zone)', (
    tester,
  ) async {
    final controller = SplitterController();
    await tester.pumpWidget(
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
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    // 12px is below the default 18px touch slop but should still start a drag.
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();

    expect(controller.effectiveFraction, greaterThan(0.5));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
