import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 3 tail: the drag is measured in the splitter's local coordinate
/// space, so it stays correct under a [Transform] (here a 2x scale) rather than
/// tracking the pointer at the wrong rate in global pixels.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('a drag tracks the pointer in local space under Transform.scale', (
    tester,
  ) async {
    final controller = SplitterController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Transform.scale(
              scale: 2,
              child: SizedBox(
                width: 308,
                height: 240,
                child: ResizableSplitter(
                  controller: controller,
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
        ),
      ),
    );

    // available = 308 - 8 = 300 (local); centered => 150 local.
    expect(
      tester.getSize(find.byKey(const Key('start'))).width,
      closeTo(150, 1e-6),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    // 40 GLOBAL pixels under a 2x scale is 20 LOCAL pixels of movement.
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Local delta 20 => start 170. Global-space math would have moved it 40 to
    // 190, twice as far as the pointer actually travelled in the panel.
    expect(
      tester.getSize(find.byKey(const Key('start'))).width,
      closeTo(170, 1e-6),
    );
    expect(controller.effectiveFraction, closeTo(170 / 300, 1e-6));
  });
}
