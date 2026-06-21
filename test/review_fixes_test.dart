import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Regression tests for the review round: each locks the invariant that the
/// corresponding fix established, not just the originally reported input.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required Widget child,
    double width = 400,
    double height = 240,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );

  group('cramped drag no longer throws (inverted clamp range)', () {
    testWidgets('drag in a container too small for both minimums', (
      tester,
    ) async {
      final controller = SplitterController();

      // available = 180 - 6 = 174 < 100 + 100, so the ratio bounds invert.
      // Before the fix this threw ArgumentError from clamp(min, max).
      await tester.pumpWidget(
        host(
          width: 180,
          child: ResizableSplitter(
            controller: controller,
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // favorStart (default) keeps the start panel at its pixel minimum.
      expect(controller.value, closeTo(100 / 174, 1e-6));
    });
  });

  group('unbounded flexExpand no longer throws', () {
    testWidgets(
      'splitter under an unbounded main axis with the default policy',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                // Both axes unbounded: Expanded here would throw RenderFlex.
                child: UnconstrainedBox(
                  child: ResizableSplitter(
                    semanticsLabel: 'handle',
                    start: SizedBox(width: 40, height: 40),
                    end: SizedBox(width: 40, height: 40),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(Flex), findsWidgets);
        // flexExpand was requested (the default), so no LimitedBox sandbox.
        expect(find.byType(LimitedBox), findsNothing);
      },
    );
  });

  group('theme precedence: local theme overrides the global extension', () {
    testWidgets('local ResizableSplitterTheme wins over ThemeExtension', (
      tester,
    ) async {
      double? builtThickness;

      final theme = ThemeData.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          ResizableSplitterThemeOverrides(dividerThickness: 20),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitterTheme(
                  data: const ResizableSplitterThemeData(dividerThickness: 10),
                  child: ResizableSplitter(
                    semanticsLabel: 'handle',
                    start: const SizedBox(),
                    end: const SizedBox(),
                    handleBuilder: (_, details) {
                      builtThickness = details.thickness;
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Local theme (10) wins over the global extension (20).
      expect(builtThickness, 10);
    });
  });

  group('handleHitSlop widens the grab area across the thin axis', () {
    testWidgets('the divider footprint reserves thickness + 2 * slop', (
      tester,
    ) async {
      const thickness = 10.0;
      const slop = 20.0;
      const totalWidth = 400.0;

      await tester.pumpWidget(
        host(
          width: totalWidth,
          child: ResizableSplitter(
            dividerThickness: thickness,
            handleHitSlop: slop,
            minPanelSize: 0,
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      );

      // The slop is reserved out of the shared space on the main axis, so the
      // panels shrink by 2 * slop rather than the slop doing nothing.
      const available = totalWidth - thickness - 2 * slop; // 350
      final startSize = tester.getSize(find.byKey(const Key('start')));
      expect(startSize.width, closeTo(available / 2, 1e-6));
    });

    testWidgets('a drag started inside the slop margin still resizes', (
      tester,
    ) async {
      const thickness = 6.0;
      const slop = 24.0;
      final controller = SplitterController();

      await tester.pumpWidget(
        host(
          width: 400,
          child: ResizableSplitter(
            controller: controller,
            dividerThickness: thickness,
            handleHitSlop: slop,
            minPanelSize: 0,
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      // Aim near the edge of the grab footprint - outside the visible bar but
      // inside the slop. With the old (outside, wrong-axis) padding this point
      // was inert.
      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      final grabPoint = Offset(handleRect.left + 2, handleRect.center.dy);
      final gesture = await tester.startGesture(grabPoint);
      await tester.pump();
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.value, lessThan(0.5));
    });
  });

  group('drag commits the exact final position', () {
    testWidgets('a sub-threshold release is not quantized away', (
      tester,
    ) async {
      final controller = SplitterController();
      const totalWidth = 400.0;
      const thickness = 6.0;
      const available = totalWidth - thickness; // 394

      await tester.pumpWidget(
        host(
          width: totalWidth,
          child: ResizableSplitter(
            controller: controller,
            dividerThickness: thickness,
            minPanelSize: 0,
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      // 0.6px is below the 0.002 (~0.79px) update threshold, so it is dropped
      // during the drag; the release must still commit it exactly.
      final handle = find.bySemanticsLabel('handle');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0.6, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.value, greaterThan(0.5));
      expect(controller.value, closeTo(0.5 + 0.6 / available, 1e-6));
    });
  });

  group('enableHaptics gates haptic feedback', () {
    Future<int> hapticCountFor(
      WidgetTester tester, {
      required bool enableHaptics,
    }) async {
      var haptics = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        host(
          child: ResizableSplitter(
            enableHaptics: enableHaptics,
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      await tester.tap(handle);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      return haptics;
    }

    testWidgets('enabled (default) fires on keyboard adjust', (tester) async {
      expect(await hapticCountFor(tester, enableHaptics: true), greaterThan(0));
    });

    testWidgets('disabled fires nothing', (tester) async {
      expect(await hapticCountFor(tester, enableHaptics: false), 0);
    });
  });
}
