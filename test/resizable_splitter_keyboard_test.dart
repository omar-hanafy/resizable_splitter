import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 400, height: 240, child: child)),
    ),
  );

  testWidgets('keyboard shortcuts adjust ratio respecting bounds', (
    tester,
  ) async {
    final controller = SplitterController();

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          semanticsLabel: 'handle',
          divider: const SplitterDividerStyle(thickness: 8),
          minStartFraction: 0.2,
          maxStartFraction: 0.8,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    await tester.tap(handle);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.value, closeTo(0.51, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(controller.value, closeTo(0.61, 1e-6));

    // Home/End jump to the real legal bounds. With minPanelSize 100 and
    // available 392, the end pane's pixel minimum caps the start at 292/392, so
    // End lands there - not the looser maxRatio 0.8 that was never visible
    // (the old code stored 0.8 while the layout showed 292/392).
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(controller.value, closeTo(100 / 392, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(controller.value, closeTo(292 / 392, 1e-6));
  });

  testWidgets(
    'theme-provided keyboard steps apply when widget defers to theme',
    (tester) async {
      final controller = SplitterController(initialRatio: 0.4);

      await tester.pumpWidget(
        host(
          ResizableSplitterTheme(
            data: const ResizableSplitterThemeData(
              keyboardStep: 0.2,
              pageStep: 0.4,
            ),
            child: ResizableSplitter(
              controller: controller,
              semanticsLabel: 'handle',
              start: const SizedBox(),
              end: const SizedBox(),
            ),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      await tester.tap(handle);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.value, closeTo(0.6, 1e-6));

      // pageDown lands on the real maximum: minPanelSize 100 caps the start at
      // 294/394 (the old code reported the never-visible 1.0).
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(controller.value, closeTo(294 / 394, 1e-6));
    },
  );

  testWidgets('keyboard input is ignored when resizable is false', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.5);

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          resizable: false,
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
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

    expect(controller.value, 0.5);
  });

  testWidgets('theme extension overrides keyboard defaults', (tester) async {
    final controller = SplitterController(initialRatio: 0.25);

    final theme = ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        ResizableSplitterThemeData(keyboardStep: 0.2, pageStep: 0.45),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 200,
              child: ResizableSplitter(
                controller: controller,
                semanticsLabel: 'handle',
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    await tester.tap(handle);
    await tester.pump();

    // Steps move the *effective* position. available 314, minPanelSize 100, so
    // the start is pinned at >= 100 (0.318); the caps then land honestly.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.value, closeTo(100 / 314 + 0.2, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(controller.value, closeTo(214 / 314, 1e-6));
  });

  testWidgets('widget override keeps keyboard interaction enabled', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.4);

    final theme = ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        ResizableSplitterThemeData(enableKeyboard: false),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 200,
              child: ResizableSplitter(
                controller: controller,
                enableKeyboard: true,
                semanticsLabel: 'handle',
                start: const SizedBox(),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    await tester.tap(handle);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(controller.value, closeTo(0.41, 1e-6));
  });
}
