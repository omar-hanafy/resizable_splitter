import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 7b: the bounded layout is overflow-safe (a container smaller than
/// the divider cannot overflow) and each pane is clipped to its box so content
/// cannot bleed across the divider.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required Widget child,
    double width = 300,
    double height = 200,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );

  testWidgets('a container narrower than the divider does not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        width: 4,
        child: ResizableSplitter(
          // Thickness far exceeds the 4px container.
          divider: const SplitterDividerStyle(thickness: 20),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
        ),
      ),
    );
    await tester.pump();

    // The divider shrinks to fit the container instead of overflowing it; the
    // panes collapse to zero. A plain Flex of [0, 20, 0] in a 4px box used to
    // overflow and report an error.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('start'))).width, 0);
    expect(tester.getSize(find.byKey(const Key('end'))).width, 0);
  });

  testWidgets('a container shorter than a vertical divider does not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        height: 4,
        child: ResizableSplitter(
          axis: Axis.vertical,
          divider: const SplitterDividerStyle(thickness: 20),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          start: Container(key: const Key('top')),
          end: Container(key: const Key('bottom')),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('top'))).height, 0);
  });

  testWidgets('each pane is wrapped in a ClipRect so content cannot bleed', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ResizableSplitter),
        matching: find.byType(ClipRect),
      ),
      findsNWidgets(2),
    );
  });
}
