import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 5 (review A#7): the animation contract.
///
/// A fresh `animateTo` always supersedes a run in progress (even when it then
/// resolves instantly); a listener's reentrant write cancels the run; a run from
/// a collapsed state clears the collapse and animates; and the run targets the
/// solver-resolved position so `completed` cannot mean a target clamped
/// off-screen.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(
    SplitterController controller, {
    SplitterPaneConstraints start = const SplitterPaneConstraints(),
    SplitterPaneConstraints end = const SplitterPaneConstraints(),
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            startConstraints: start,
            endConstraints: end,
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      ),
    ),
  );

  testWidgets('a fresh animateTo supersedes a run in progress, even at the '
      'current position (review A#7)', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    SplitterAnimationStatus? firstStatus;
    unawaited(
      controller
          .animateTo(0.9, duration: const Duration(milliseconds: 600))
          .then((s) => firstStatus = s),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = controller.effectiveFraction;
    expect(mid, greaterThan(0.2));
    expect(mid, lessThan(0.9));

    // Animate to the position it is already at. The equality shortcut still has
    // to cancel the first run rather than leave it ticking on toward 0.9.
    await controller.animateTo(mid);
    expect(firstStatus, SplitterAnimationStatus.canceled);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(controller.effectiveFraction, closeTo(mid, 0.02));
  });

  testWidgets('a reentrant write from a listener cancels the run', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(host(controller));

    var jumped = false;
    controller.addListener(() {
      if (!jumped && controller.effectiveFraction >= 0.4) {
        jumped = true;
        controller.jumpTo(const SplitterPosition.fraction(0.25));
      }
    });

    SplitterAnimationStatus? status;
    unawaited(
      controller
          .animateTo(0.9, duration: const Duration(milliseconds: 600))
          .then((s) => status = s),
    );
    await tester.pump();
    // Drive far enough for the listener to fire and write reentrantly.
    await tester.pump(const Duration(milliseconds: 200));

    // The reentrant write must have cancelled the run: it cannot keep ticking
    // back up toward 0.9.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(status, SplitterAnimationStatus.canceled);
    expect(controller.effectiveFraction, closeTo(0.25, 0.03));
  });

  testWidgets('animateTo from a collapsed state clears the collapse and '
      'animates to the target (review A#7)', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(
      host(
        controller,
        start: const SplitterPaneConstraints(minExtent: 50, collapsedExtent: 0),
      ),
    );

    controller.collapse(SplitterPane.start);
    await tester.pump();
    expect(controller.isCollapsed, isTrue);

    final status = await () {
      final future = controller.animateTo(
        0.6,
        duration: const Duration(milliseconds: 200),
      );
      return tester.pumpAndSettle().then((_) => future);
    }();

    expect(
      controller.isCollapsed,
      isFalse,
      reason: 'a fresh animateTo is a new intent that clears the collapse',
    );
    expect(controller.effectiveFraction, closeTo(0.6, 0.02));
    expect(status, SplitterAnimationStatus.completed);
  });

  testWidgets('animateTo settles at the solver-resolved target, not a target '
      'clamped off-screen (review A#7)', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.2),
    );
    await tester.pumpWidget(
      host(
        controller,
        // The start pane is hard-capped at 150px; available is 400 - 6 = 394, so
        // a full-right request resolves to 150/394 ~= 0.38.
        start: const SplitterPaneConstraints(maxExtent: 150),
      ),
    );
    const resolved = 150 / 394;

    final status = await () {
      final future = controller.animateTo(
        0.9,
        duration: const Duration(milliseconds: 200),
      );
      return tester.pumpAndSettle().then((_) => future);
    }();

    expect(status, SplitterAnimationStatus.completed);
    expect(controller.effectiveFraction, closeTo(resolved, 1e-3));
    // The stored request settles at the achievable target rather than the
    // unreachable 0.9: "completed" means the divider actually arrived there.
    expect(
      controller.position.resolveFraction(394),
      closeTo(resolved, 1e-3),
    );
  });
}
