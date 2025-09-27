import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 400, height: 240, child: child)),
    ),
  );

  testWidgets('default semantics expose label and percent values', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ResizableSplitter(
          dividerThickness: 8,
          startPanel: SizedBox(),
          endPanel: SizedBox(),
        ),
      ),
    );

    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Drag to resize left and right panels.'),
        ),
        matchesSemantics(
          label: 'Drag to resize left and right panels.',
          value: '50%',
          increasedValue: '51%',
          decreasedValue: '49%',
          isFocusable: true,
          hasFocusAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('semantics value reflects effective ratio with pixel minimums', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.1);

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          minStartPanelSize: 240,
          minEndPanelSize: 120,
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Drag to resize left and right panels.'),
        ),
        matchesSemantics(
          label: 'Drag to resize left and right panels.',
          value: '61%',
          increasedValue: '61%',
          decreasedValue: '61%',
          isFocusable: true,
          hasFocusAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });
}
