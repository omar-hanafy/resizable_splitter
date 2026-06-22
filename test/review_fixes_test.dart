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
      expect(controller.effectiveFraction, closeTo(100 / 174, 1e-6));
    });
  });

  group('unbounded shrinkToChildren no longer throws', () {
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
                    start: SizedBox(key: Key('start'), width: 40, height: 40),
                    end: SizedBox(key: Key('end'), width: 40, height: 40),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // shrinkToChildren (the default) shrink-wraps the two panes side by side
        // with no divider gap and no fallback sandbox: 40 + 40 = 80 wide.
        expect(tester.getSize(find.byKey(const Key('start'))).width, 40);
        expect(tester.getSize(find.byKey(const Key('end'))).width, 40);
        expect(tester.getSize(find.byType(ResizableSplitter)).width, 80);
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
          ResizableSplitterThemeData(
            divider: SplitterDividerStyle(thickness: 20),
          ),
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
                  data: const ResizableSplitterThemeData(
                    divider: SplitterDividerStyle(thickness: 10),
                  ),
                  child: ResizableSplitter(
                    semanticsLabel: 'handle',
                    start: const SizedBox(),
                    end: const SizedBox(),
                    divider: SplitterDividerStyle(
                      builder: (_, details) {
                        builtThickness = details.thickness;
                        return const SizedBox.shrink();
                      },
                    ),
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

    testWidgets(
      'a partial local override keeps the app extension value (no clobber)',
      (tester) async {
        double? builtThickness;

        // The app-wide extension supplies the thickness.
        final theme = ThemeData.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[
            ResizableSplitterThemeData(
              divider: SplitterDividerStyle(thickness: 20),
            ),
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
                  // The local theme touches an unrelated field only. It must
                  // not reset the thickness the extension supplied: every theme
                  // field is nullable, so "unset" falls through instead of
                  // re-asserting a default.
                  child: ResizableSplitterTheme(
                    data: const ResizableSplitterThemeData(
                      dragBarrierColor: Color(0xFFFF0000),
                    ),
                    child: ResizableSplitter(
                      semanticsLabel: 'handle',
                      start: const SizedBox(),
                      end: const SizedBox(),
                      divider: SplitterDividerStyle(
                        builder: (_, details) {
                          builtThickness = details.thickness;
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // The extension's 20 survives. The old non-nullable theme clobbered it
        // back to the 6.0 default whenever any local theme was present.
        expect(builtThickness, 20);
      },
    );

    testWidgets('a local divider style merges per field over the extension', (
      tester,
    ) async {
      double? builtThickness;

      final theme = ThemeData.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          ResizableSplitterThemeData(
            divider: SplitterDividerStyle(thickness: 18),
          ),
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
                // The local divider style sets only the color; the thickness
                // must fall through to the extension rather than being dropped.
                child: ResizableSplitterTheme(
                  data: const ResizableSplitterThemeData(
                    divider: SplitterDividerStyle(
                      color: WidgetStatePropertyAll<Color?>(Color(0xFF00FF00)),
                    ),
                  ),
                  child: ResizableSplitter(
                    semanticsLabel: 'handle',
                    start: const SizedBox(),
                    end: const SizedBox(),
                    divider: SplitterDividerStyle(
                      builder: (_, details) {
                        builtThickness = details.thickness;
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(builtThickness, 18);
    });
  });

  group('interactiveExtent overlaps the panels instead of reserving layout', () {
    testWidgets('the divider footprint reserves only the visual thickness', (
      tester,
    ) async {
      const thickness = 10.0;
      const slop = 20.0;
      const totalWidth = 400.0;

      await tester.pumpWidget(
        host(
          width: totalWidth,
          child: ResizableSplitter(
            divider: const SplitterDividerStyle(
              thickness: thickness,
              interactiveExtent: thickness + 2 * slop,
            ),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      );

      // The slop no longer eats layout: the panels share everything except the
      // visible bar (it used to reserve thickness + 2*slop). The grab zone
      // reclaims the slop by overlapping the panel edges from on top instead of
      // widening the divider footprint.
      const available = totalWidth - thickness; // 390
      final startRect = tester.getRect(find.byKey(const Key('start')));
      expect(startRect.width, closeTo(available / 2, 1e-6));

      // The grab catcher is thickness + 2*slop wide and overlaps each panel by
      // slop: its leading edge sits `slop` inside the start panel.
      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      expect(handleRect.width, closeTo(thickness + 2 * slop, 1e-6));
      expect(handleRect.left, closeTo(startRect.right - slop, 1e-6));
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
            divider: const SplitterDividerStyle(
              thickness: thickness,
              interactiveExtent: thickness + 2 * slop,
            ),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
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

      expect(controller.effectiveFraction, lessThan(0.5));
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
            divider: const SplitterDividerStyle(thickness: thickness),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
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

      expect(controller.effectiveFraction, greaterThan(0.5));
      expect(
        controller.effectiveFraction,
        closeTo(0.5 + 0.6 / available, 1e-6),
      );
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
