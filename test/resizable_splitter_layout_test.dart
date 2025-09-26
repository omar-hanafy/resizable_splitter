import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget frame({
    required Widget child,
    double width = 300,
    double height = 200,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  testWidgets('horizontal splitter enforces asymmetric minimum sizes', (
    tester,
  ) async {
    const dividerThickness = 10.0;
    const totalWidth = 300.0;

    await tester.pumpWidget(
      frame(
        width: totalWidth,
        child: ResizableSplitter(
          axis: Axis.horizontal,
          initialRatio: 0.1,
          dividerThickness: dividerThickness,
          minStartPanelSize: 200,
          minEndPanelSize: 50,
          semanticsLabel: 'handle',
          startPanel: Container(key: const Key('start')),
          endPanel: Container(key: const Key('end')),
        ),
      ),
    );

    final startSize = tester.getSize(find.byKey(const Key('start')));
    final endSize = tester.getSize(find.byKey(const Key('end')));

    expect(startSize.width, 200);
    expect(endSize.width, (totalWidth - dividerThickness) - 200);
  });

  testWidgets('start wins when combined minima exceed available width', (
    tester,
  ) async {
    const dividerThickness = 10.0;
    const totalWidth = 300.0;

    await tester.pumpWidget(
      frame(
        width: totalWidth,
        child: ResizableSplitter(
          axis: Axis.horizontal,
          initialRatio: 0.8,
          dividerThickness: dividerThickness,
          minStartPanelSize: 200,
          minEndPanelSize: 150,
          semanticsLabel: 'handle',
          startPanel: Container(key: const Key('start')),
          endPanel: Container(key: const Key('end')),
        ),
      ),
    );

    final startSize = tester.getSize(find.byKey(const Key('start')));
    final endSize = tester.getSize(find.byKey(const Key('end')));
    const available = totalWidth - dividerThickness;

    expect(startSize.width, closeTo(200, 1e-6));
    expect(endSize.width, closeTo(available - 200, 1e-6));
  });

  testWidgets('vertical splitter positions children using ratio', (
    tester,
  ) async {
    const dividerThickness = 12.0;
    const totalHeight = 400.0;
    final controller = SplitterController(initialRatio: 0.25);

    await tester.pumpWidget(
      frame(
        height: totalHeight,
        child: ResizableSplitter(
          axis: Axis.vertical,
          controller: controller,
          minPanelSize: 0,
          dividerThickness: dividerThickness,
          semanticsLabel: 'handle',
          startPanel: Container(key: const Key('top')),
          endPanel: Container(key: const Key('bottom')),
        ),
      ),
    );

    final topSize = tester.getSize(find.byKey(const Key('top')));
    final bottomSize = tester.getSize(find.byKey(const Key('bottom')));

    const availableHeight = totalHeight - dividerThickness;
    expect(topSize.height, closeTo(availableHeight * 0.25, 1e-3));
    expect(bottomSize.height, closeTo(availableHeight * 0.75, 1e-3));
  });

  testWidgets('vertical start panel keeps minimum when space is constrained', (
    tester,
  ) async {
    const dividerThickness = 12.0;
    const totalHeight = 280.0;

    await tester.pumpWidget(
      frame(
        height: totalHeight,
        child: ResizableSplitter(
          axis: Axis.vertical,
          initialRatio: 0.7,
          dividerThickness: dividerThickness,
          minStartPanelSize: 180,
          minEndPanelSize: 140,
          semanticsLabel: 'handle',
          startPanel: Container(key: const Key('top')),
          endPanel: Container(key: const Key('bottom')),
        ),
      ),
    );

    final topSize = tester.getSize(find.byKey(const Key('top')));
    final bottomSize = tester.getSize(find.byKey(const Key('bottom')));
    const availableHeight = totalHeight - dividerThickness;

    expect(topSize.height, closeTo(180, 1e-6));
    expect(bottomSize.height, closeTo(availableHeight - 180, 1e-6));
  });

  testWidgets('custom handleBuilder is invoked with details', (tester) async {
    await tester.pumpWidget(
      frame(
        child: ResizableSplitter(
          axis: Axis.horizontal,
          semanticsLabel: 'handle',
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
          dividerThickness: 6,
          handleBuilder: (_, details) {
            expect(details.thickness, 6.0);
            expect(details.axis, Axis.horizontal);
            return Container(key: const Key('customGrip'));
          },
        ),
      ),
    );

    expect(find.byKey(const Key('customGrip')), findsOneWidget);
  });
}
