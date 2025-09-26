import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  // Ensure Flutter bindings exist so SplitterController can register safely.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep the global pointer router from leaking across tests.
  tearDown(SplitterController.resetGlobalRouter);

  test('animateTo completes and updates value with FakeAsync', () {
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

      // Advance fake time to cover all frames.
      fake
        ..elapse(const Duration(milliseconds: 120))
        // Let the `.then` microtask run.
        ..flushMicrotasks();

      // Assertions
      expect(completed, isTrue);
      expect(controller.value, closeTo(0.9, 1e-6));
    });
  });
}
