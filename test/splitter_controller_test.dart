import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  // Ensure bindings exist for controller registration with the pointer router.
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(SplitterController.resetGlobalRouter);

  group('SplitterController', () {
    test('stores the requested position and exposes the effective fraction', () {
      final pinned = SplitterController(
        initialPosition: const SplitterPosition.startPixels(280),
      );
      expect(pinned.value.position, const SplitterPosition.startPixels(280));
      // A pixel request has no fraction until it is laid out: the cache seeds to
      // 0 and the attached splitter fills it in on the first solve.
      expect(pinned.effectiveFraction, 0);

      final fractional = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.3),
      );
      expect(fractional.effectiveFraction, 0.3);
    });

    test('updateRatio respects threshold and clamps to [0,1]', () {
      final controller = SplitterController();
      final changes = <double>[];
      controller
        ..addListener(() => changes.add(controller.effectiveFraction))
        ..updateRatio(0.5005, threshold: 0.01);
      expect(controller.effectiveFraction, 0.5);
      expect(changes, isEmpty);

      controller.updateRatio(1.5);
      expect(controller.effectiveFraction, 1.0);
      expect(changes.last, 1.0);

      controller.updateRatio(-10);
      expect(controller.effectiveFraction, 0.0);
      expect(changes.last, 0.0);
    });

    test('reset sets value', () {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.25),
      )..reset(0.75);
      expect(controller.effectiveFraction, 0.75);
    });

    test('out-of-range and non-finite fractions resolve into [0, 1]', () {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.4),
      )..jumpTo(const SplitterPosition.fraction(2.0));
      expect(controller.effectiveFraction, 1.0);
      controller.jumpTo(const SplitterPosition.fraction(-3.0));
      expect(controller.effectiveFraction, 0.0);
      controller.jumpTo(const SplitterPosition.fraction(double.nan));
      expect(controller.effectiveFraction, 0.0);
      expect(controller.effectiveFraction.isFinite, isTrue);
    });

    test('animateTo applies immediately when no view is attached', () async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.1),
      );
      // No splitter is mounted, so there is no vsync host: the value is set
      // immediately and the future resolves.
      await controller.animateTo(0.9);
      expect(controller.effectiveFraction, closeTo(0.9, 1e-6));
    });

    test('collapse is atomic: an equal-value write neither clears it nor '
        'notifies (review issue #1)', () {
      final controller = SplitterController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.collapse(SplitterPane.start);
      expect(controller.isCollapsed, isTrue);
      expect(notifications, 1);

      // Re-assigning the identical value must not clear the collapse, and must
      // not notify - nothing changed. (The historic setter mutated the collapse
      // flag before the equality check, desyncing state from the UI.)
      controller.value = controller.value;
      expect(controller.isCollapsed, isTrue);
      expect(notifications, 1);

      // A redundant collapse onto the same pane is likewise a no-op.
      controller.collapse(SplitterPane.start);
      expect(notifications, 1);

      // Expanding changes the state and notifies exactly once.
      controller.expand();
      expect(controller.isCollapsed, isFalse);
      expect(notifications, 2);
    });

    test('jumpTo writes the position and clears any collapse', () {
      final controller = SplitterController()..collapse(SplitterPane.end);
      expect(controller.isCollapsed, isTrue);

      controller.jumpTo(const SplitterPosition.startPixels(120));
      expect(
        controller.value.position,
        const SplitterPosition.startPixels(120),
      );
      expect(controller.isCollapsed, isFalse);
    });

    testWidgets(
      'controller asserts when attached to multiple splitters simultaneously',
      (tester) async {
        final controller = SplitterController();
        var showSecond = false;
        late StateSetter setState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: StatefulBuilder(
                  builder: (context, innerSetState) {
                    setState = innerSetState;
                    return Column(
                      children: [
                        Expanded(
                          child: ResizableSplitter(
                            controller: controller,
                            semanticsLabel: 'first',
                            start: const SizedBox(),
                            end: const SizedBox(),
                          ),
                        ),
                        if (showSecond)
                          Expanded(
                            child: ResizableSplitter(
                              controller: controller,
                              semanticsLabel: 'second',
                              start: const SizedBox(),
                              end: const SizedBox(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        setState(() => showSecond = true);
        await tester.pump();

        final error = tester.takeException();
        expect(error, isFlutterError);
        expect('$error', contains('already attached'));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a listener notified by a position write sees a consistent '
        'effectiveFraction (no stale-layout desync)', (tester) async {
      final controller = SplitterController(); // fraction 0.5
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 408,
                height: 240,
                child: ResizableSplitter(
                  controller: controller,
                  startConstraints: const SplitterPaneConstraints(),
                  endConstraints: const SplitterPaneConstraints(),
                  start: const SizedBox(),
                  end: const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.effectiveFraction, closeTo(0.5, 1e-6));

      // Capture effectiveFraction at the instant the controller notifies.
      double? observed;
      controller.addListener(() => observed ??= controller.effectiveFraction);

      // A fresh request. The listener fires synchronously inside the write; it
      // must observe a fraction consistent with the NEW request (0.8), not the
      // stale published layout (0.5).
      controller.jumpTo(const SplitterPosition.fraction(0.8));

      expect(observed, isNotNull);
      expect(observed, closeTo(0.8, 1e-6));
    });

    testWidgets(
      'detaching the controller (splitter removed) clears the published layout',
      (tester) async {
        final controller = SplitterController();
        Widget build({required bool showSplitter}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 408,
                height: 240,
                child: showSplitter
                    ? ResizableSplitter(
                        controller: controller,
                        start: const SizedBox(),
                        end: const SizedBox(),
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        );

        await tester.pumpWidget(build(showSplitter: true));
        await tester.pumpAndSettle();
        expect(controller.layout, isNotNull);

        // Remove the splitter: the controller detaches and no longer produces
        // geometry, so its published layout must clear (the doc promises null
        // while detached).
        await tester.pumpWidget(build(showSplitter: false));
        await tester.pumpAndSettle();
        expect(controller.layout, isNull);
      },
    );
  });
}
