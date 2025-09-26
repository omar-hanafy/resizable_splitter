import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 400, height: 240, child: child),
      ),
    ),
  );

  testWidgets('keyboard shortcuts adjust ratio respecting bounds', (
    tester,
  ) async {
    final controller = SplitterController();

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          semanticsLabel: 'handle',
          dividerThickness: 8,
          minRatio: 0.2,
          maxRatio: 0.8,
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    await tester.tap(handle);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.value, closeTo(0.51, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(controller.value, closeTo(0.61, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(controller.value, 0.2);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(controller.value, 0.8);
  });
}
