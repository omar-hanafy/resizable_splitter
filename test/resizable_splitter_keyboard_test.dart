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
          dividerThickness: 8,
          minRatio: 0.2,
          maxRatio: 0.8,
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
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

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(controller.value, 0.2);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(controller.value, 0.8);
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
              startPanel: const SizedBox(),
              endPanel: const SizedBox(),
            ),
          ),
        ),
      );

      final handle = find.bySemanticsLabel('handle');
      await tester.tap(handle);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.value, closeTo(0.6, 1e-6));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(controller.value, closeTo(1.0, 1e-6));
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
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
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
        ResizableSplitterThemeOverrides(keyboardStep: 0.2, pageStep: 0.45),
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
                startPanel: const SizedBox(),
                endPanel: const SizedBox(),
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
    expect(controller.value, closeTo(0.45, 1e-6));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(controller.value, closeTo(0.9, 1e-6));
  });

  testWidgets('widget override keeps keyboard interaction enabled', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.4);

    final theme = ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        ResizableSplitterThemeOverrides(enableKeyboard: false),
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
                startPanel: const SizedBox(),
                endPanel: const SizedBox(),
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
