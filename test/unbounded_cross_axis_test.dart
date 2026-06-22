import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Review issue #11: a bounded main axis with an *unbounded cross axis* (e.g. a
/// horizontal splitter in a Column) used to throw "BoxConstraints forces an
/// infinite size" from the layout Stack. The Stack now sizes to the panes when
/// the cross axis is unbounded, so the splitter still renders.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('horizontal splitter: finite width, unbounded height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResizableSplitter(
                  axis: Axis.horizontal,
                  divider: SplitterDividerStyle(thickness: 8),
                  startConstraints: SplitterPaneConstraints(),
                  endConstraints: SplitterPaneConstraints(),
                  start: SizedBox(height: 60, key: Key('start')),
                  end: SizedBox(height: 40, key: Key('end')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // available = 400 - 8 = 392; centered => start 196.
    expect(
      tester.getSize(find.byKey(const Key('start'))).width,
      closeTo(196, 1e-6),
    );
  });

  testWidgets('horizontal splitter ignores zero-width collapsed pane height', (
    tester,
  ) async {
    final controller = SplitterController()..collapse(SplitterPane.start);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResizableSplitter(
                  controller: controller,
                  axis: Axis.horizontal,
                  divider: const SplitterDividerStyle(thickness: 8),
                  startConstraints: const SplitterPaneConstraints(
                    minExtent: 100,
                    collapsedExtent: 0,
                  ),
                  endConstraints: const SplitterPaneConstraints(),
                  start: const SizedBox(height: 900, key: Key('start')),
                  end: const SizedBox(height: 40, key: Key('end')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ResizableSplitter)).height, 40);
    expect(tester.getSize(find.byKey(const Key('start'))), Size.zero);
  });

  testWidgets('vertical splitter: finite height, unbounded width', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResizableSplitter(
                  axis: Axis.vertical,
                  divider: SplitterDividerStyle(thickness: 8),
                  startConstraints: SplitterPaneConstraints(),
                  endConstraints: SplitterPaneConstraints(),
                  start: SizedBox(width: 60, key: Key('start')),
                  end: SizedBox(width: 40, key: Key('end')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // available = 400 - 8 = 392; centered => start 196.
    expect(
      tester.getSize(find.byKey(const Key('start'))).height,
      closeTo(196, 1e-6),
    );
  });

  testWidgets(
    'both axes unbounded: shrinkToChildren shows panes without throwing',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnconstrainedBox(
              child: ResizableSplitter(
                axis: Axis.horizontal,
                start: SizedBox(width: 30, height: 30, key: Key('start')),
                end: SizedBox(width: 30, height: 30, key: Key('end')),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('start')), findsOneWidget);
      expect(find.byKey(const Key('end')), findsOneWidget);
    },
  );

  testWidgets(
    'useFallbackExtent fallback renders with an unbounded cross axis',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnconstrainedBox(
              child: ResizableSplitter(
                axis: Axis.horizontal,
                unboundedBehavior: UnboundedBehavior.useFallbackExtent,
                fallbackExtent: 408,
                divider: SplitterDividerStyle(thickness: 8),
                startConstraints: SplitterPaneConstraints(),
                endConstraints: SplitterPaneConstraints(),
                start: SizedBox(height: 50, key: Key('start')),
                end: SizedBox(height: 50, key: Key('end')),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // main axis limited to 408; available = 408 - 8 = 400; centered => 200.
      expect(
        tester.getSize(find.byKey(const Key('start'))).width,
        closeTo(200, 1e-6),
      );
    },
  );
}
