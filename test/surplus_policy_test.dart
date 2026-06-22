import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Review issue #6: when both panes' maximums are too small to fill the space
/// (a surplus), the [SplitterSurplusPolicy] decides the layout. `leaveGap` keeps
/// both panes at their maximum and renders the leftover as a gap between them.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('leaveGap pins both panes to their max with a gap between them '
      '(review #6)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 200,
              child: ResizableSplitter(
                divider: const SplitterDividerStyle(thickness: 8),
                startConstraints: const SplitterPaneConstraints(maxExtent: 150),
                endConstraints: const SplitterPaneConstraints(maxExtent: 150),
                surplusPolicy: SplitterSurplusPolicy.leaveGap,
                start: Container(key: const Key('start')),
                end: Container(key: const Key('end')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // available = 600 - 8 = 592; maxes 150 + 150 = 300 < 592, so each pane sits
    // at its maximum and the remaining ~292px is the gap.
    expect(
      tester.getSize(find.byKey(const Key('start'))).width,
      closeTo(150, 1e-6),
    );
    expect(
      tester.getSize(find.byKey(const Key('end'))).width,
      closeTo(150, 1e-6),
    );
  });

  testWidgets('giveToEnd grows the end pane past its max to fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 200,
              child: ResizableSplitter(
                divider: const SplitterDividerStyle(thickness: 8),
                startConstraints: const SplitterPaneConstraints(maxExtent: 150),
                endConstraints: const SplitterPaneConstraints(maxExtent: 150),
                surplusPolicy: SplitterSurplusPolicy.giveToEnd,
                start: Container(key: const Key('start')),
                end: Container(key: const Key('end')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // start stays at its 150 max; end absorbs the slack (592 - 150 = 442).
    expect(
      tester.getSize(find.byKey(const Key('start'))).width,
      closeTo(150, 1e-6),
    );
    expect(
      tester.getSize(find.byKey(const Key('end'))).width,
      closeTo(442, 1e-6),
    );
  });
}
