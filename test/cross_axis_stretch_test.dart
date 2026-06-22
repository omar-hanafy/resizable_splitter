import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 4 (review A#12): with a bounded cross axis, each pane is laid out with
/// a tight cross extent, so an intrinsically small child fills the splitter
/// rather than centering at its natural size.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('a horizontal splitter stretches panes to the full height', (
    tester,
  ) async {
    double? startMinHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: ResizableSplitter(
                start: LayoutBuilder(
                  builder: (context, constraints) {
                    startMinHeight = constraints.minHeight;
                    return const SizedBox.shrink();
                  },
                ),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(startMinHeight, closeTo(200, 1e-6));
  });

  testWidgets('a vertical splitter stretches panes to the full width', (
    tester,
  ) async {
    double? startMinWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: ResizableSplitter(
                axis: Axis.vertical,
                start: LayoutBuilder(
                  builder: (context, constraints) {
                    startMinWidth = constraints.minWidth;
                    return const SizedBox.shrink();
                  },
                ),
                end: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(startMinWidth, closeTo(400, 1e-6));
  });
}
