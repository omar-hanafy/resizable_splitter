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
      expect(pinned.value, const SplitterPosition.startPixels(280));
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
      )..value = const SplitterPosition.fraction(2.0);
      expect(controller.effectiveFraction, 1.0);
      controller.value = const SplitterPosition.fraction(-3.0);
      expect(controller.effectiveFraction, 0.0);
      controller.value = const SplitterPosition.fraction(double.nan);
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
  });
}
