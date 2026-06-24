import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Regression: when a platform view (e.g. a WebView) swallows the pointer-up
/// that would normally end a divider drag, the framework never sees that
/// release, so neither the gesture recognizer nor the global pointer route
/// (which both need the same-pointer up to reach `GestureBinding.dispatchEvent`)
/// can terminate the drag. The drag is then stranded as "dragging".
///
/// A mouse, however, eventually moves back over Flutter content. Because the
/// physical button is no longer held, that motion arrives as a `PointerHover`
/// (or a move whose primary button bit is clear) for the SAME device - and
/// hovers DO reach the global route (they get a fresh hit-test). That is proof
/// the press ended, so the splitter must recover and end the drag.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(SplitterController controller) => MaterialApp(
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
            start: const SizedBox.expand(),
            end: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'a mouse drag whose pointer-up was swallowed recovers on the next hover',
    (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(host(controller));
      final center = tester.getCenter(find.bySemanticsLabel('handle'));

      // Start a real mouse drag with a pointer we control.
      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      final down = pointer.down(center);
      tester.binding.handlePointerEvent(down);
      await tester.pump();
      tester.binding.handlePointerEvent(
        pointer.move(center + const Offset(30, 0)),
      );
      await tester.pump();
      expect(controller.isDragging, isTrue);

      // The platform view swallows the release: NO pointer-up reaches the
      // framework. Later the mouse moves back over Flutter with the button
      // already up -> a hover for the same device (note: a hover carries no
      // buttons and may have a different pointer id, so this must match by
      // device, not by pointer id).
      tester.binding.handlePointerEvent(
        PointerHoverEvent(
          viewId: down.viewId,
          kind: PointerDeviceKind.mouse,
          device: down.device,
          position: center + const Offset(60, 0),
        ),
      );
      await tester.pump();

      expect(
        controller.isDragging,
        isFalse,
        reason:
            'the swallowed-up drag must recover on the next no-button hover',
      );

      // The real up may still arrive much later; it must be a safe no-op.
      tester.binding.handlePointerEvent(pointer.up());
      await tester.pump();
      expect(controller.isDragging, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a hover from a DIFFERENT device does not end an active mouse drag',
    (tester) async {
      final controller = SplitterController();
      await tester.pumpWidget(host(controller));
      final center = tester.getCenter(find.bySemanticsLabel('handle'));

      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      final down = pointer.down(center);
      tester.binding.handlePointerEvent(down);
      await tester.pump();
      tester.binding.handlePointerEvent(
        pointer.move(center + const Offset(30, 0)),
      );
      await tester.pump();
      expect(controller.isDragging, isTrue);

      // A second mouse (different device) hovering must not terminate this drag.
      tester.binding.handlePointerEvent(
        PointerHoverEvent(
          viewId: down.viewId,
          kind: PointerDeviceKind.mouse,
          device: down.device + 1,
          position: center + const Offset(60, 0),
        ),
      );
      await tester.pump();
      expect(controller.isDragging, isTrue);

      tester.binding.handlePointerEvent(pointer.up());
      await tester.pumpAndSettle();
      expect(controller.isDragging, isFalse);
    },
  );
}
