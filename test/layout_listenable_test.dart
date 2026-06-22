import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Review issue #8: a pixel-pinned pane's effective fraction changes when the
/// container resizes, but the *request* does not - so the request notifier never
/// fires. The resolved geometry is published as a separate [SplitterLayout]
/// observable, which fires for exactly those changes.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('layout is null before the first layout, populated after', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.4),
    );
    // No view attached yet.
    expect(controller.layout, isNull);
    // effectiveFraction falls back to the request before layout (no pretending).
    expect(controller.effectiveFraction, 0.4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 300,
              child: ResizableSplitter(
                controller: controller,
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.layout, isNotNull);
    // available = 600 - 6 = 594; 0.4 => start 237.6.
    expect(controller.layout!.effectiveFraction, closeTo(0.4, 1e-6));
    expect(controller.layout!.startExtent, closeTo(0.4 * 594, 1e-6));
    expect(controller.layout!.availableExtent, closeTo(594, 1e-6));
    expect(
      controller.layout!.resolution,
      anyOf(SplitterResolution.exact, SplitterResolution.clamped),
    );
    expect(controller.layout!.collapsedPane, isNull);
  });

  testWidgets('layoutListenable fires on resize while the request is unchanged', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.startPixels(200),
    );
    final layouts = <SplitterLayout>[];
    controller.layoutListenable.addListener(() {
      final l = controller.layout;
      if (l != null) layouts.add(l);
    });

    var width = 600.0;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return SizedBox(
                  width: width,
                  height: 300,
                  child: ResizableSplitter(
                    controller: controller,
                    start: const SizedBox(),
                    end: const SizedBox(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // available = 594; the 200px pin lands at 200/594.
    expect(controller.value.position, const SplitterPosition.startPixels(200));
    expect(controller.layout!.startExtent, closeTo(200, 1e-6));
    expect(controller.layout!.effectiveFraction, closeTo(200 / 594, 1e-6));

    final requestBefore = controller.value;
    final countBefore = layouts.length;

    // Resize the container: the pixel request does NOT change, but the effective
    // fraction does (the pane stays pinned at 200px of a smaller space).
    setOuter(() => width = 400);
    await tester.pumpAndSettle();

    // The request is untouched...
    expect(controller.value, requestBefore);
    // ...yet the resolved layout shifted, and a notification was delivered.
    expect(controller.layout!.startExtent, closeTo(200, 1e-6));
    expect(controller.layout!.effectiveFraction, closeTo(200 / 394, 1e-6));
    expect(
      layouts.length,
      greaterThan(countBefore),
      reason: 'layoutListenable must fire when the resize shifts the fraction',
    );
  });

  // The ordering contract the future 2.1 RenderObject publish must preserve: a
  // resolved change notifies exactly once, after the frame that produced it
  // (never during build), and a no-op re-solve does not notify. These assert the
  // ordering, never a frame count, so the publish can move into performLayout.
  testWidgets('a resolved change notifies once, deferred past the build', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.3),
    );
    var count = 0;
    SchedulerPhase? phaseAtNotify;
    controller.layoutListenable.addListener(() {
      count++;
      phaseAtNotify = SchedulerBinding.instance.schedulerPhase;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 300,
              child: ResizableSplitter(
                controller: controller,
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = count;

    controller.jumpTo(const SplitterPosition.fraction(0.6));
    // The layout notification is deferred: writing the request does not fire it
    // synchronously (the controller's own request notifier does that).
    expect(
      count,
      baseline,
      reason: 'the layout notify is deferred, not synchronous with the request',
    );

    await tester.pump();
    // Exactly one notification for the one resolved change.
    expect(count, baseline + 1);
    // It fired in the post-frame phase, never during build/layout/paint.
    expect(phaseAtNotify, SchedulerPhase.postFrameCallbacks);
  });

  testWidgets('a request change resolving to the same layout does not notify', (
    tester,
  ) async {
    // A 200px start minimum: both requests below it clamp to the same extent, so
    // the resolved layout is identical and the no-op re-solve must not notify.
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.0),
    );
    var count = 0;
    controller.layoutListenable.addListener(() => count++);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: ResizableSplitter(
                controller: controller,
                startConstraints: const SplitterPaneConstraints(minExtent: 200),
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = count;

    // A different request that still clamps to the 200px minimum: the request
    // notifier fires and the widget rebuilds, but the geometry is unchanged.
    controller.jumpTo(const SplitterPosition.fraction(0.1));
    await tester.pumpAndSettle();

    expect(
      count,
      baseline,
      reason: 'an unchanged resolved layout coalesces to no notification',
    );
  });

  testWidgets('layout reports the collapsed pane', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 406,
              height: 300,
              child: ResizableSplitter(
                controller: controller,
                startConstraints: const SplitterPaneConstraints(
                  minExtent: 100,
                  collapsedExtent: 0,
                ),
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.layout!.collapsedPane, isNull);

    controller.collapse(SplitterPane.start);
    await tester.pumpAndSettle();

    expect(controller.layout!.collapsedPane, SplitterPane.start);
    expect(controller.layout!.startExtent, closeTo(0, 1e-6));
  });
}
