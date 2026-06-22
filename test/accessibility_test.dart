import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 4 (review A#14): framework-grade accessibility.
///
/// Focus support (a visible ring, [WidgetState.focused], and
/// [SplitterHandleDetails.isFocused]), localizable semantics via
/// [SplitterSemanticsLabels], and assistive adjustment actions gated on whether
/// the divider can actually move in that direction.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child, {double width = 400, double height = 240}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  // Finds the single AnimatedContainer that paints the divider bar.
  Finder barFinder() => find.descendant(
    of: find.byType(ResizableSplitter),
    matching: find.byType(AnimatedContainer),
  );

  BoxDecoration barDecoration(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(barFinder()).decoration! as BoxDecoration;

  void forceKeyboardHighlight() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
  }

  void requestHandleFocus(WidgetTester tester) {
    final detector = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector),
    );
    detector.focusNode!.requestFocus();
  }

  group('focus', () {
    testWidgets('the default divider shows a focus ring when focused', (
      tester,
    ) async {
      forceKeyboardHighlight();
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            semanticsLabel: 'handle',
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      expect(barDecoration(tester).border, isNull);

      requestHandleFocus(tester);
      await tester.pump();

      expect(
        barDecoration(tester).border,
        isNotNull,
        reason: 'a focused divider must paint a visible focus ring',
      );

      // Unfocusing clears the ring again.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(barDecoration(tester).border, isNull);
    });

    testWidgets('WidgetState.focused reaches a custom color', (tester) async {
      forceKeyboardHighlight();
      const focused = Color(0xFF00FF00);
      const unfocused = Color(0xFF000000);
      await tester.pumpWidget(
        host(
          ResizableSplitter(
            divider: SplitterDividerStyle(
              color: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.focused) ? focused : unfocused,
              ),
            ),
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      expect(barDecoration(tester).color, unfocused);

      requestHandleFocus(tester);
      await tester.pump();

      expect(barDecoration(tester).color, focused);
    });

    testWidgets('SplitterHandleDetails.isFocused reaches a custom grip builder', (
      tester,
    ) async {
      forceKeyboardHighlight();
      final focusedSamples = <bool>[];
      await tester.pumpWidget(
        host(
          ResizableSplitter(
            divider: SplitterDividerStyle(
              builder: (context, details) {
                focusedSamples.add(details.isFocused);
                return const SizedBox.expand();
              },
            ),
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      expect(focusedSamples.last, isFalse);

      requestHandleFocus(tester);
      await tester.pump();

      expect(focusedSamples.last, isTrue);
    });
  });

  group('localizable semantics', () {
    testWidgets('SplitterSemanticsLabels overrides the label and value format', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ResizableSplitter(
            semantics: SplitterSemanticsLabels(
              resizeHorizontal: 'Redimensionner',
              formatValue: (fraction) =>
                  'ratio ${fraction.toStringAsFixed(2)}',
            ),
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        final node = tester.getSemantics(
          find.bySemanticsLabel('Redimensionner'),
        );
        expect(node.label, 'Redimensionner');
        expect(node.value, 'ratio 0.50');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('static labels are used when the splitter is not resizable', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            resizable: false,
            semantics: SplitterSemanticsLabels(staticHorizontal: 'Fixed bar'),
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('Fixed bar'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('labels resolve from the ambient theme', (tester) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitterTheme(
            data: ResizableSplitterThemeData(
              semantics: SplitterSemanticsLabels(
                resizeHorizontal: 'Themed resize',
              ),
            ),
            child: ResizableSplitter(start: SizedBox(), end: SizedBox()),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('Themed resize'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the single-string semanticsLabel still overrides the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            semanticsLabel: 'explicit',
            semantics: SplitterSemanticsLabels(resizeHorizontal: 'ignored'),
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('explicit'), findsOneWidget);
        expect(find.bySemanticsLabel('ignored'), findsNothing);
      } finally {
        handle.dispose();
      }
    });
  });

  group('interactiveExtent (touch target)', () {
    testWidgets('the default grab target is 48px wide, not the visible bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            divider: SplitterDividerStyle(thickness: 6),
            semanticsLabel: 'handle',
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      expect(
        handleRect.width,
        closeTo(48, 1e-6),
        reason: 'the default interactiveExtent is a 48px accessible target',
      );
    });

    testWidgets('interactiveExtent sets the grab target and overlaps the panes', (
      tester,
    ) async {
      const thickness = 10.0;
      const target = 60.0;
      const slop = (target - thickness) / 2; // 25
      await tester.pumpWidget(
        host(
          width: 400,
          ResizableSplitter(
            divider: const SplitterDividerStyle(
              thickness: thickness,
              interactiveExtent: target,
            ),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      );

      final startRect = tester.getRect(find.byKey(const Key('start')));
      // The interactive target does not eat layout: the footprint still reserves
      // only the visible thickness.
      expect(startRect.width, closeTo((400 - thickness) / 2, 1e-6));

      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      expect(handleRect.width, closeTo(target, 1e-6));
      expect(handleRect.left, closeTo(startRect.right - slop, 1e-6));
    });

    testWidgets('a non-resizable divider collapses the target to its thickness', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ResizableSplitter(
            resizable: false,
            divider: SplitterDividerStyle(thickness: 8),
            semanticsLabel: 'handle',
            start: SizedBox(),
            end: SizedBox(),
          ),
        ),
      );

      final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
      expect(
        handleRect.width,
        closeTo(8, 1e-6),
        reason: 'a static divider must not overlap the panes and steal hits',
      );
    });
  });

  group('assistive actions are gated on the resolved bounds', () {
    testWidgets('increase is dropped when the start pane is pinned at its max', (
      tester,
    ) async {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(1),
      );
      await tester.pumpWidget(
        host(
          ResizableSplitter(
            controller: controller,
            // A hard pixel cap on the start pane; a full-right request pins it
            // to 150, so it can shrink (decrease) but never grow (increase).
            startConstraints: const SplitterPaneConstraints(
              minExtent: 0,
              maxExtent: 150,
            ),
            endConstraints: const SplitterPaneConstraints(minExtent: 0),
            semanticsLabel: 'handle',
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        final data = tester
            .getSemantics(find.bySemanticsLabel('handle'))
            .getSemanticsData();
        expect(
          data.hasAction(SemanticsAction.increase),
          isFalse,
          reason: 'pinned at the max, the start pane cannot grow',
        );
        expect(data.hasAction(SemanticsAction.decrease), isTrue);
      } finally {
        handle.dispose();
      }
    });
  });
}
