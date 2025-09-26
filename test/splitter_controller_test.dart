import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  // Ensure bindings exist for controller registration with the pointer router.
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(SplitterController.resetGlobalRouter);

  group('SplitterController', () {
    test('asserts on invalid initial ratio', () {
      expect(
        () => SplitterController(initialRatio: -0.1),
        throwsAssertionError,
      );
      expect(() => SplitterController(initialRatio: 1.1), throwsAssertionError);
    });

    test('updateRatio respects threshold and clamps to [0,1]', () {
      final controller = SplitterController();
      final changes = <double>[];
      controller
        ..addListener(() => changes.add(controller.value))
        ..updateRatio(0.5005, threshold: 0.01);
      expect(controller.value, 0.5);
      expect(changes, isEmpty);

      controller.updateRatio(1.5);
      expect(controller.value, 1.0);
      expect(changes.last, 1.0);

      controller.updateRatio(-10);
      expect(controller.value, 0.0);
      expect(changes.last, 0.0);
    });

    test('reset sets value', () {
      final controller = SplitterController(initialRatio: 0.25)..reset(0.75);
      expect(controller.value, 0.75);
    });

    test('animateTo tweens value without a Ticker', () {
      final controller = SplitterController(initialRatio: 0.1);

      FakeAsync().run((fake) {
        var completed = false;
        unawaited(
          controller
              .animateTo(
                0.9,
                duration: const Duration(milliseconds: 120),
                frames: 4,
              )
              .then((_) => completed = true),
        );

        fake.elapse(const Duration(milliseconds: 120));
        expect(controller.value, closeTo(0.9, 1e-6));
        fake.flushMicrotasks();
        expect(completed, isTrue);
      });
    });
  });
}
