import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 7c: programmatic collapse/expand. A pane collapses to its
/// [SplitterPaneConstraints.collapsedExtent] (bypassing its minimum) and expand
/// restores the position the splitter held before collapsing.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required SplitterController controller,
    double width = 408,
    ValueChanged<SplitterChangeDetails>? onChanged,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 240,
          child: ResizableSplitter(
            controller: controller,
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(
              minExtent: 100,
              collapsible: true,
            ),
            endConstraints: const SplitterPaneConstraints(
              minExtent: 100,
              collapsible: true,
              collapsedExtent: 24,
            ),
            semanticsLabel: 'handle',
            onChanged: onChanged,
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      ),
    ),
  );

  double startWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('start'))).width;

  testWidgets('collapse(start) shrinks the start pane to its collapsedExtent '
      'past its minimum', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(host(controller: controller));
    // available = 408 - 8 = 400; centered => start 200.
    expect(startWidth(tester), closeTo(200, 1e-6));

    controller.collapse(SplitterPane.start);
    await tester.pump();

    // collapsedExtent defaults to 0, bypassing the 100px minimum.
    expect(startWidth(tester), closeTo(0, 1e-6));
    expect(controller.collapsedPane, SplitterPane.start);
    expect(controller.isCollapsed, isTrue);
  });

  testWidgets('collapse(end) shrinks the end pane to its collapsedExtent', (
    tester,
  ) async {
    final controller = SplitterController();
    await tester.pumpWidget(host(controller: controller));

    controller.collapse(SplitterPane.end);
    await tester.pump();

    // end collapsedExtent 24, available 400 => start 376.
    expect(startWidth(tester), closeTo(376, 1e-6));
    expect(controller.collapsedPane, SplitterPane.end);
  });

  testWidgets('expand() restores the pre-collapse position', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.3),
    );
    await tester.pumpWidget(host(controller: controller));
    expect(startWidth(tester), closeTo(120, 1e-6)); // 0.3 * 400

    controller.collapse(SplitterPane.start);
    await tester.pump();
    expect(startWidth(tester), closeTo(0, 1e-6));

    controller.expand();
    await tester.pump();

    expect(startWidth(tester), closeTo(120, 1e-6));
    expect(controller.collapsedPane, isNull);
    expect(controller.isCollapsed, isFalse);
    expect(controller.value.position, const SplitterPosition.fraction(0.3));
  });

  testWidgets('toggleCollapse collapses then expands the same pane', (
    tester,
  ) async {
    final controller = SplitterController();
    await tester.pumpWidget(host(controller: controller));

    controller.toggleCollapse(SplitterPane.start);
    await tester.pump();
    expect(controller.collapsedPane, SplitterPane.start);
    expect(startWidth(tester), closeTo(0, 1e-6));

    controller.toggleCollapse(SplitterPane.start);
    await tester.pump();
    expect(controller.collapsedPane, isNull);
    expect(startWidth(tester), closeTo(200, 1e-6));
  });

  testWidgets('collapse then expand report collapse/restore change sources', (
    tester,
  ) async {
    final controller = SplitterController();
    final sources = <SplitterChangeSource>[];
    await tester.pumpWidget(
      host(controller: controller, onChanged: (d) => sources.add(d.source)),
    );

    controller.collapse(SplitterPane.start);
    await tester.pumpAndSettle();
    controller.expand();
    await tester.pumpAndSettle();

    expect(
      sources,
      containsAllInOrder([
        SplitterChangeSource.collapse,
        SplitterChangeSource.restore,
      ]),
    );
  });

  testWidgets('jumpTo clears a collapse', (tester) async {
    final controller = SplitterController();
    await tester.pumpWidget(host(controller: controller));

    controller.collapse(SplitterPane.start);
    await tester.pump();
    expect(controller.isCollapsed, isTrue);

    controller.jumpTo(const SplitterPosition.fraction(0.25));
    await tester.pump();

    expect(controller.isCollapsed, isFalse);
    expect(startWidth(tester), closeTo(100, 1e-6)); // 0.25 * 400
  });

  testWidgets('an equal-value write while collapsed stays collapsed (no desync)', (
    tester,
  ) async {
    // The historic bug (review issue #1): the value setter mutated the collapse
    // flag before the ValueNotifier equality check, so re-assigning the current
    // value cleared the collapse with no notification - the controller reported
    // expanded while the UI stayed collapsed. With collapse folded into the
    // atomic SplitterState, an equal write changes nothing.
    final controller = SplitterController();
    await tester.pumpWidget(host(controller: controller));

    controller.collapse(SplitterPane.start);
    await tester.pump();
    expect(controller.isCollapsed, isTrue);
    expect(startWidth(tester), closeTo(0, 1e-6));

    // Re-assign the identical state.
    controller.value = controller.value;
    await tester.pump();

    expect(controller.isCollapsed, isTrue);
    expect(controller.collapsedPane, SplitterPane.start);
    expect(startWidth(tester), closeTo(0, 1e-6));
  });
}
