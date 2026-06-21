import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 3: right-to-left correctness. In RTL the start pane is on the
/// right, so pointer and arrow-key directions invert on the horizontal axis.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget rtlHost(Widget child) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(child: SizedBox(width: 400, height: 240, child: child)),
      ),
    ),
  );

  testWidgets('dragging the divider right shrinks the start pane in RTL', (
    tester,
  ) async {
    final controller = SplitterController();

    await tester.pumpWidget(
      rtlHost(
        ResizableSplitter(
          controller: controller,
          dividerThickness: 8,
          minPanelSize: 0,
          semanticsLabel: 'handle',
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Pointer moved right by 40; in RTL that shrinks the start pane (in LTR it
    // would grow it). available = 400 - 8 = 392.
    expect(controller.value, lessThan(0.5));
    expect(controller.value, closeTo(0.5 - 40 / 392, 1e-6));
  });

  testWidgets('arrow keys swap direction in RTL', (tester) async {
    final controller = SplitterController();

    await tester.pumpWidget(
      rtlHost(
        ResizableSplitter(
          controller: controller,
          minPanelSize: 0,
          semanticsLabel: 'handle',
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('handle'));
    await tester.pump();

    // Left arrow grows the start pane in RTL (it sits on the right).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.value, closeTo(0.51, 1e-6));

    // Right arrow shrinks it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.value, closeTo(0.50, 1e-6));
  });

  testWidgets('the start pane is laid out on the right in RTL', (tester) async {
    await tester.pumpWidget(
      rtlHost(
        ResizableSplitter(
          initialRatio: 0.25,
          dividerThickness: 8,
          minPanelSize: 0,
          semanticsLabel: 'handle',
          startPanel: Container(key: const Key('start')),
          endPanel: Container(key: const Key('end')),
        ),
      ),
    );

    final startRect = tester.getRect(find.byKey(const Key('start')));
    final endRect = tester.getRect(find.byKey(const Key('end')));
    expect(startRect.center.dx, greaterThan(endRect.center.dx));
  });
}
