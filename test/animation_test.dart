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

  testWidgets('animateTo drives the value over vsync frames to the target', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    final future = controller.animateTo(
      0.8,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump(); // kick off
    await tester.pump(const Duration(milliseconds: 150)); // mid-flight

    expect(controller.effectiveFraction, greaterThan(0.2));
    expect(controller.effectiveFraction, lessThan(0.8));

    await tester.pumpAndSettle();
    expect(controller.effectiveFraction, closeTo(0.8, 1e-6));
    await future;
  });

  testWidgets('starting a drag cancels a running animation', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    unawaited(
      controller.animateTo(0.9, duration: const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.effectiveFraction, greaterThan(0.2));
    expect(controller.effectiveFraction, lessThan(0.9));

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

    expect(controller.effectiveFraction, lessThan(0.6));
  });

  testWidgets('animateTo is instant when MediaQuery disables animations', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller, disableAnimations: true));

    final future = controller.animateTo(
      0.8,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(controller.effectiveFraction, closeTo(0.8, 1e-6));
    expect(await future, SplitterAnimationStatus.completed);
  });

  testWidgets('a normal finish resolves the future completed', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    final future = controller.animateTo(
      0.7,
      duration: const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();

    expect(await future, SplitterAnimationStatus.completed);
    expect(controller.effectiveFraction, closeTo(0.7, 1e-6));
  });

  testWidgets('a drag resolves the run as canceled (review #2)', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    final future = controller.animateTo(
      0.9,
      duration: const Duration(milliseconds: 600),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Grabbing the divider cancels the animation - distinguishable from a finish.
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    expect(await future, SplitterAnimationStatus.canceled);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disposing the splitter mid-run resolves the future detached '
      '(review #2: no hung future)', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    final future = controller.animateTo(
      0.9,
      duration: const Duration(milliseconds: 600),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Remove the splitter from the tree while the animation is in flight.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

    expect(await future, SplitterAnimationStatus.detached);
  });

  testWidgets('swapping the controller mid-run resolves detached and leaves '
      'the incoming controller untouched (review #2)', (tester) async {
    final a = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    final b = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.5),
    );
    var useA = true;
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 240,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return ResizableSplitter(
                    controller: useA ? a : b,
                    startConstraints: const SplitterPaneConstraints(),
                    endConstraints: const SplitterPaneConstraints(),
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

    final future = a.animateTo(
      0.9,
      duration: const Duration(milliseconds: 600),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Swap the controller out from under the running animation.
    setOuter(() => useA = false);
    await tester.pump();
    expect(await future, SplitterAnimationStatus.detached);

    // Let any (wrongly) surviving animation tick; controller B must not move.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(b.effectiveFraction, closeTo(0.5, 1e-6));
  });
}
