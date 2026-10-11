import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
// The platform-view input interceptor wrapper. VM tests resolve the library's
// conditional import to the stub, so this import names the same type the
// widget tree holds here; on web builds the web variant takes its place.
import 'package:resizable_splitter/src/widget/web_platform_view_interceptor_stub.dart';

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

  testWidgets('the shield is torn down when the press ends without a drag (it cannot '
      'outlive the pointer that armed it)', (tester) async {
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
  });

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

  testWidgets(
    'the divider catcher always paints (alpha > 0) across its FULL interactive '
    'extent - including the transparent grab slop that overlaps the panes - so '
    'the OS compositor carves the catcher out of a neighboring platform view '
    'and a press in the slop reaches Flutter at all',
    (tester) async {
      // The failure this locks out (observed on macOS with a WKWebView pane):
      // the grab slop (interactiveExtent > thickness) overlaps the platform
      // view, but painted NOTHING there. The macOS compositor only adds a
      // hit-test-ignore region to a platform view where a later Flutter layer
      // actually PAINTS (FlutterMutatorView.hitTest / FlutterCompositor's
      // paint_region intersection), so the un-painted slop belonged to the
      // native view: hover still reached Flutter via the engine's tracking
      // area, but mouse-DOWNs went to the WebView. The divider advertised a
      // grab zone it could not actually grab with. Painting an imperceptible
      // base (alpha 1/255) across the whole catcher is what makes the slop's
      // pixels Flutter-owned at the OS level. That swallow itself cannot be
      // reproduced in flutter_test (no native views), so - exactly like the
      // drag-shield test above - this locks the paint invariant that makes it
      // impossible.
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
                  // The report's shape: a visible 6px bar with a 4px grab slop
                  // overhanging each pane.
                  divider: const SplitterDividerStyle(
                    thickness: 6,
                    interactiveExtent: 14,
                  ),
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

      // Must match the package-internal `_catcherBasePaintKey` (a value key,
      // compared by equality - same pattern as the shield base above).
      const catcherBaseKey = Key('resizable_splitter.catcher_base_paint');
      final base = tester.widget<ColoredBox>(find.byKey(catcherBaseKey));
      expect(
        base.color.a,
        greaterThan(0),
        reason:
            'an un-painted catcher does not carve platform views out of the '
            'OS hit test, so presses in the grab slop never reach Flutter',
      );

      final catcherSize = tester.getSize(find.byKey(catcherBaseKey));
      expect(
        catcherSize.width,
        14,
        reason:
            'the paint must cover the FULL interactive extent (bar + both '
            'slops), not just the visible bar',
      );

      // The paint is part of the idle divider - present before any press or
      // drag, because the press itself is what needs to reach Flutter.
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets(
    'the catcher and the drag shield mount the web platform-view interceptor '
    '(a DOM element on web; pass-through elsewhere) - painting alone cannot '
    'keep pointer events out of an iframe on web',
    (tester) async {
      // The web failure this wiring closes: an iframe swallows every DOM
      // event over it, and a Flutter canvas paint is not a DOM hit target, so
      // neither the painted catcher slop nor the painted drag shield receive
      // input over an iframe pane - a drag released there strands, and the
      // slop cannot grab. The interceptor mounts an invisible DOM element
      // above the iframe so events bubble to the engine instead. That DOM
      // routing cannot run in flutter_test; this locks the wiring, and the
      // behavior itself is verified in a real browser.
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
                  divider: const SplitterDividerStyle(
                    thickness: 6,
                    interactiveExtent: 14,
                  ),
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

      // Idle: the catcher (slop > 0) is wrapped.
      expect(find.byType(WebPlatformViewInterceptor), findsOneWidget);

      // Pressing mounts the shield overlay, which is wrapped too.
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('handle')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.byType(WebPlatformViewInterceptor), findsNWidgets(2));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(WebPlatformViewInterceptor), findsOneWidget);
      expect(controller.isDragging, isFalse);
    },
  );

  testWidgets(
    'a zero-slop catcher does not pay for a web interceptor element',
    (tester) async {
      // With interactiveExtent == thickness the catcher never overlaps a
      // pane, so there is nothing for an iframe to swallow at idle - and on
      // web an interceptor element is a per-splitter DOM cost that zero-slop
      // configs should not pay. (The drag shield still mounts one during a
      // press, covering the in-flight drag.)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitter(
                  divider: SplitterDividerStyle(
                    thickness: 6,
                    interactiveExtent: 6,
                  ),
                  startConstraints: SplitterPaneConstraints(),
                  endConstraints: SplitterPaneConstraints(),
                  semanticsLabel: 'handle',
                  start: SizedBox.expand(),
                  end: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WebPlatformViewInterceptor), findsNothing);
    },
  );

  testWidgets(
    'shieldPlatformViews: false opts the catcher out of the base paint',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitter(
                  shieldPlatformViews: false,
                  divider: SplitterDividerStyle(
                    thickness: 6,
                    interactiveExtent: 14,
                  ),
                  startConstraints: SplitterPaneConstraints(),
                  endConstraints: SplitterPaneConstraints(),
                  semanticsLabel: 'handle',
                  start: SizedBox.expand(),
                  end: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      const catcherBaseKey = Key('resizable_splitter.catcher_base_paint');
      expect(
        find.byKey(catcherBaseKey),
        findsNothing,
        reason:
            'opting out of platform-view accommodations must also drop the '
            'catcher base paint',
      );
    },
  );

  testWidgets('the drag shield always paints a compositing surface (alpha > 0) while '
      'dragging - even with no dragBarrierColor - so it composites above platform '
      'views and the OS keeps delivering the release to Flutter', (tester) async {
    // The real failure is at the OS / compositor boundary: a native platform
    // view (e.g. a WebView) that stays the topmost surface swallows the
    // pointer-up, so the drag never ends. That swallow cannot be reproduced
    // in flutter_test - there is no native view and synthetic pointers always
    // reach Flutter - so this locks the invariant that makes the swallow
    // impossible: the shield must PAINT something above the platform view to
    // composite a Flutter surface over it. A fully transparent fill paints
    // nothing (ColoredBox skips alpha == 0), which was the regression: the
    // default barrier was Colors.transparent, so the default (most common)
    // configuration shielded nothing at the compositor level.
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
                // Default visuals: no dragBarrierColor, no dragBarrierBuilder -
                // exactly the path the regression lived on.
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
      kind: PointerDeviceKind.mouse,
    );
    // Cross touch slop so the drag is accepted and the shield paints.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(controller.isDragging, isTrue);

    // Must match the package-internal `_shieldBaseBarrierKey`. Value keys
    // compare by equality, so the test reaches the base layer without the
    // package exposing a debug symbol.
    const shieldBaseKey = Key('resizable_splitter.shield_base_barrier');
    final barrier = tester.widget<ColoredBox>(find.byKey(shieldBaseKey));
    expect(
      barrier.color.a,
      greaterThan(0),
      reason:
          'a fully transparent shield paints nothing above platform views, so '
          'the native view stays topmost and swallows the release',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.isDragging, isFalse);
    expect(
      find.byKey(shieldBaseKey),
      findsNothing,
      reason: 'the shield must not outlive the drag',
    );
  });
}
