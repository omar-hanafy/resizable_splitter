import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({
    required Widget child,
    double width = 400,
    double height = 240,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  testWidgets(
    'drag updates ratio, overlay appears, and snapping applies on release',
    (tester) async {
      const dividerThickness = 10.0;
      const totalWidth = 400.0;
      final controller = SplitterController(initialRatio: 0.5);

      double? dragStart;
      double? dragEnd;
      final ratioChanges = <double>[];

      await tester.pumpWidget(
        host(
          child: ResizableSplitter(
            axis: Axis.horizontal,
            controller: controller,
            dividerThickness: dividerThickness,
            semanticsLabel: 'handle',
            minPanelSize: 0,
            overlayEnabled: true,
            blockerColor: Colors.green,
            snapPoints: const [0.25, 0.75],
            snapTolerance: 0.1,
            onDragStart: (value) => dragStart = value,
            onDragEnd: (value) => dragEnd = value,
            onRatioChanged: ratioChanges.add,
            startPanel: const SizedBox(key: Key('start')),
            endPanel: const SizedBox(key: Key('end')),
          ),
        ),
      );

      expect(controller.value, 0.5);
      expect(dragStart, isNull);
      expect(dragEnd, isNull);

      final handle = find.bySemanticsLabel('handle');
      expect(handle, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();

      Finder overlayFinder() => find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.green,
      );
      expect(overlayFinder(), findsOneWidget);

      const availableWidth = totalWidth - dividerThickness;
      await gesture.moveBy(const Offset(availableWidth * 0.2, 0));
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(dragStart, isNotNull);
      expect(dragEnd, isNotNull);
      expect(controller.value, closeTo(0.75, 1e-6));
      expect(ratioChanges, isNotEmpty);
      expect(overlayFinder(), findsNothing);
    },
  );

  testWidgets('drag is clamped by ratio bounds and pixel minimums', (
    tester,
  ) async {
    const dividerThickness = 8.0;
    const totalWidth = 360.0;
    final controller = SplitterController(initialRatio: 0.6);

    await tester.pumpWidget(
      host(
        width: totalWidth,
        child: ResizableSplitter(
          axis: Axis.horizontal,
          controller: controller,
          dividerThickness: dividerThickness,
          semanticsLabel: 'handle',
          minRatio: 0.3,
          maxRatio: 0.9,
          minEndPanelSize: 150,
          startPanel: const SizedBox(key: Key('start')),
          endPanel: const SizedBox(key: Key('end')),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-1000, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.value, greaterThanOrEqualTo(0.3));
  });

  testWidgets('controller exposes dragging listenable updates', (tester) async {
    final controller = SplitterController(initialRatio: 0.5);
    final draggingStates = <bool>[];
    controller.isDraggingListenable.addListener(() {
      draggingStates.add(controller.isDragging);
    });

    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
          axis: Axis.horizontal,
          controller: controller,
          dividerThickness: 8,
          semanticsLabel: 'handle',
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(draggingStates, containsAllInOrder([true, false]));
  });

  testWidgets('snap points clamp to legal ratio bounds before applying', (
    tester,
  ) async {
    const dividerThickness = 8.0;
    const totalWidth = 320.0;
    final controller = SplitterController(initialRatio: 0.6);

    await tester.pumpWidget(
      host(
        width: totalWidth,
        child: ResizableSplitter(
          axis: Axis.horizontal,
          controller: controller,
          dividerThickness: dividerThickness,
          semanticsLabel: 'handle',
          minPanelSize: 0,
          minStartPanelSize: 130,
          minRatio: 0.2,
          snapPoints: const [0.0, 1.0],
          snapTolerance: 1,
          startPanel: const SizedBox(key: Key('start')),
          endPanel: const SizedBox(key: Key('end')),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();

    const availableWidth = totalWidth - dividerThickness;
    await gesture.moveBy(const Offset(-availableWidth, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.value,
      closeTo(130 / availableWidth, 1e-6),
    );
  });

  testWidgets('vertical drags respect pixel minimums', (tester) async {
    const dividerThickness = 12.0;
    const totalHeight = 360.0;
    final controller = SplitterController(initialRatio: 0.4);

    await tester.pumpWidget(
      host(
        height: totalHeight,
        child: ResizableSplitter(
          axis: Axis.vertical,
          controller: controller,
          dividerThickness: dividerThickness,
          semanticsLabel: 'handle',
          minStartPanelSize: 150,
          minEndPanelSize: 120,
          startPanel: Container(key: const Key('top')),
          endPanel: Container(key: const Key('bottom')),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -1000));
    await gesture.up();
    await tester.pumpAndSettle();

    final topSize = tester.getSize(find.byKey(const Key('top')));
    expect(topSize.height, greaterThanOrEqualTo(150));
  });

  testWidgets('controller.isDragging resets when handle is disposed mid-drag', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.5);
    var showSplitter = true;
    late StateSetter setState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, innerSetState) {
          setState = innerSetState;
          return host(
            child: showSplitter
                ? ResizableSplitter(
                    axis: Axis.horizontal,
                    controller: controller,
                    dividerThickness: 10,
                    semanticsLabel: 'handle',
                    startPanel: const SizedBox(),
                    endPanel: const SizedBox(),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(controller.isDragging, isTrue);

    setState(() {
      showSplitter = false;
    });
    await tester.pump();

    expect(controller.isDragging, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
