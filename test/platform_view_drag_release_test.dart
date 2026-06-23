import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Regression: a divider next to a platform view (WebView) must never be left
/// stranded as "dragging".
///
/// The class of bug: drag teardown and the platform-view shield were anchored to
/// the gesture *recognizer's* accept/end callbacks. A neighboring platform view
/// can swallow the pointer-up so the recognizer's end never fires, and the
/// shield armed only once the recognizer accepted - leaving a window (and a
/// missing teardown path) the platform view could exploit.
///
/// The fix anchors both the shield and the teardown to the divider's own
/// pointer [Listener], which is guaranteed to sit in the in-flight pointer's
/// captured hit-test path: the shield arms on pointer-down (before the drag is
/// even recognized) and the drag tears down on that Listener's pointer-up /
/// pointer-cancel, independent of the recognizer.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  const endPaneKey = Key('end-pane-platform-view');

  // A splitter whose divider ALSO handles a double-tap. That puts a competing
  // recognizer in the gesture arena, so the horizontal drag can only win AFTER
  // touch slop - opening a window between the press and drag-acceptance. This is
  // the realistic shape of an app that offers "double-tap the divider to reset".
  Widget tapAwareSplitter({
    required SplitterController controller,
    required ValueChanged<PointerDownEvent> onPanePointerDown,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            onHandleDoubleTap: () {},
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: const SizedBox.expand(),
            // Stand-in for a platform view / WebView pane: an opaque Listener
            // that records whether a pointer ever reached it.
            end: Listener(
              key: endPaneKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: onPanePointerDown,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'the platform-view shield is armed from the press, before the drag is '
    'recognized (no slop window for a platform view to exploit)',
    (tester) async {
      final controller = SplitterController();
      var paneReceivedPointer = false;

      await tester.pumpWidget(
        tapAwareSplitter(
          controller: controller,
          onPanePointerDown: (_) => paneReceivedPointer = true,
        ),
      );

      // Press and HOLD the divider. Do not move: with a double-tap recognizer
      // competing, the drag is NOT yet accepted, so this is exactly the
      // pre-acceptance window.
      final hold = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(
        controller.isDragging,
        isFalse,
        reason: 'the drag must not be accepted yet (competing double-tap)',
      );

      // A pointer now lands on the platform-view pane. If the shield is armed
      // from the press, it intercepts this before the pane can capture it.
      final probe = await tester.startGesture(
        tester.getCenter(find.byKey(endPaneKey)),
        pointer: 1000,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      expect(
        paneReceivedPointer,
        isFalse,
        reason:
            'the platform-view shield must cover the pane from the press, not '
            'only after the gesture recognizer accepts the drag',
      );

      await probe.up();
      await hold.up();
      await tester.pumpAndSettle();
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets(
    'the shield is torn down when the press ends without a drag (it cannot '
    'outlive the pointer that armed it)',
    (tester) async {
      final controller = SplitterController();
      var paneReceivedPointer = false;

      await tester.pumpWidget(
        tapAwareSplitter(
          controller: controller,
          onPanePointerDown: (_) => paneReceivedPointer = true,
        ),
      );

      // Press and release the divider without dragging (a plain tap). The shield
      // is armed on the press and must be dropped on release.
      await tester.tap(find.bySemanticsLabel('handle'));
      await tester.pumpAndSettle();

      // With the shield gone, a pointer now reaches the platform-view pane.
      final probe = await tester.startGesture(
        tester.getCenter(find.byKey(endPaneKey)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        paneReceivedPointer,
        isTrue,
        reason: 'the shield must not survive a press that never became a drag',
      );
      await probe.up();
      await tester.pumpAndSettle();
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets(
    'arming the shield early never flashes the visible barrier on a press that '
    'is not (yet) a drag',
    (tester) async {
      const barrierKey = Key('drag-barrier');
      final controller = SplitterController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitter(
                  controller: controller,
                  onHandleDoubleTap: () {},
                  dragBarrierBuilder: (_) => const SizedBox(key: barrierKey),
                  divider: const SplitterDividerStyle(thickness: 8),
                  startConstraints: const SplitterPaneConstraints(),
                  endConstraints: const SplitterPaneConstraints(),
                  semanticsLabel: 'handle',
                  start: const SizedBox.expand(),
                  end: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      // Shield is armed (see the test above), but the drag is not accepted yet,
      // so the visible barrier must NOT paint.
      expect(find.byKey(barrierKey), findsNothing);

      // Cross touch slop: the drag is now live and the barrier appears.
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(find.byKey(barrierKey), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(barrierKey), findsNothing);
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets('a quick press-drag-release commits and never strands the drag', (
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
                dragBarrierColor: Colors.red,
                divider: const SplitterDividerStyle(
                  thickness: 6,
                  interactiveExtent: 6,
                ),
                startConstraints: const SplitterPaneConstraints(minExtent: 50),
                endConstraints: const SplitterPaneConstraints(minExtent: 50),
                semanticsLabel: 'handle',
                start: const SizedBox.expand(),
                end: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    // Press, drag, and release in a single burst (no settle in between) - the
    // "quick drag/release" from the original report.
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isDragging, isFalse);
    expect(controller.effectiveFraction, greaterThan(0.5));
    // The shield/barrier is removed: nothing is left tracking the pointer.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.red,
      ),
      findsNothing,
    );
  });
}
