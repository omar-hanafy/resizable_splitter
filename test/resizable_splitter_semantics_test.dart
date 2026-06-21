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
          start: SizedBox(),
          end: SizedBox(),
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
          isSlider: true,
          hasEnabledState: true,
          isEnabled: true,
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
          start: const SizedBox(),
          end: const SizedBox(),
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
          isSlider: true,
          hasEnabledState: true,
          isEnabled: true,
          value: '61%',
          // The increase preview reflects what an adjust action actually does:
          // nudge from the effective 61% to 62% (not the never-visible stored
          // request).
          increasedValue: '62%',
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

  testWidgets(
    'assistive adjustment stays available when the keyboard is disabled',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            enableKeyboard: false,
            minPanelSize: 0,
            semanticsLabel: 'handle',
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      final semanticsHandle = tester.ensureSemantics();
      try {
        // No physical keyboard, so the node is not focusable - but a screen
        // reader can still adjust it.
        expect(
          tester.getSemantics(find.bySemanticsLabel('handle')),
          matchesSemantics(
            label: 'handle',
            isSlider: true,
            hasEnabledState: true,
            isEnabled: true,
            value: '50%',
            increasedValue: '51%',
            decreasedValue: '49%',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ),
        );
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets('a non-resizable splitter reads as a disabled slider', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ResizableSplitter(
          resizable: false,
          minPanelSize: 0,
          start: SizedBox(),
          end: SizedBox(),
        ),
      ),
    );

    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Splitter between left and right panels.'),
        ),
        matchesSemantics(
          label: 'Splitter between left and right panels.',
          isSlider: true,
          hasEnabledState: true,
          value: '50%',
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });
}
