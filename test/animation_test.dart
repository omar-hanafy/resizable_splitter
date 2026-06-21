import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 4: animation is driven by the attached view's vsync, honors
/// MediaQuery.disableAnimations, and yields to a drag.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(
    SplitterController controller, {
    bool disableAnimations = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: SizedBox(
            width: 400,
            height: 240,
            child: ResizableSplitter(
              controller: controller,
              minPanelSize: 0,
              semanticsLabel: 'handle',
              start: const SizedBox(),
              end: const SizedBox(),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('animateTo drives the value over vsync frames to the target', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.2);
    await tester.pumpWidget(host(controller));

    final future = controller.animateTo(
      0.8,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump(); // kick off
    await tester.pump(const Duration(milliseconds: 150)); // mid-flight

    expect(controller.value, greaterThan(0.2));
    expect(controller.value, lessThan(0.8));

    await tester.pumpAndSettle();
    expect(controller.value, closeTo(0.8, 1e-6));
    await future;
  });

  testWidgets('starting a drag cancels a running animation', (tester) async {
    final controller = SplitterController(initialRatio: 0.2);
    await tester.pumpWidget(host(controller));

    unawaited(
      controller.animateTo(0.9, duration: const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value, greaterThan(0.2));
    expect(controller.value, lessThan(0.9));

    // Grab the divider and drag left; the animation must yield.
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();

    // If the animation were still alive it would march on toward 0.9 over the
    // next 600ms. It must not.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.value, lessThan(0.6));
  });

  testWidgets('animateTo is instant when MediaQuery disables animations', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.2);
    await tester.pumpWidget(host(controller, disableAnimations: true));

    final future = controller.animateTo(
      0.8,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(controller.value, closeTo(0.8, 1e-6));
    await future;
  });
}
