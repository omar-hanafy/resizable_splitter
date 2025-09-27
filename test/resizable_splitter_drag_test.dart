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
      final controller = SplitterController();

      double? dragStart;
      double? dragEnd;
      final ratioChanges = <double>[];

      await tester.pumpWidget(
        host(
          child: ResizableSplitter(
            controller: controller,
            dividerThickness: dividerThickness,
            semanticsLabel: 'handle',
            minPanelSize: 0,
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
    final controller = SplitterController();
    final draggingStates = <bool>[];
    controller.isDraggingListenable.addListener(() {
      draggingStates.add(controller.isDragging);
    });

    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
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

    expect(controller.value, closeTo(130 / availableWidth, 1e-6));
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
    final controller = SplitterController();
    var showSplitter = true;
    late StateSetter setState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, innerSetState) {
          setState = innerSetState;
          return host(
            child: showSplitter
                ? ResizableSplitter(
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

  testWidgets('resizable false keeps ratio unchanged on drag attempts', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.45);

    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
          controller: controller,
          resizable: false,
          semanticsLabel: 'handle',
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();

    expect(controller.value, 0.45);
    expect(controller.isDragging, isFalse);
  });

  testWidgets('handle tap callback fires even when not dragging', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
          semanticsLabel: 'handle',
          onHandleTap: () => tapCount++,
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    await tester.tap(handle);
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('double-tap callback fires and ratio resets when configured', (
    tester,
  ) async {
    final controller = SplitterController(initialRatio: 0.3);
    var doubleTapCount = 0;

    await tester.pumpWidget(
      host(
        child: ResizableSplitter(
          controller: controller,
          semanticsLabel: 'handle',
          doubleTapResetTo: 0.75,
          onHandleDoubleTap: () => doubleTapCount++,
          startPanel: const SizedBox(),
          endPanel: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final center = tester.getCenter(handle);

    final firstTap = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 10));
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 40));

    final secondTap = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 10));
    await secondTap.up();
    await tester.pumpAndSettle();

    expect(doubleTapCount, 1);
    expect(controller.value, closeTo(0.75, 1e-6));
  });

  testWidgets('theme extension disables drag overlay when requested', (
    tester,
  ) async {
    final controller = SplitterController();

    final theme = ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        ResizableSplitterThemeOverrides(overlayEnabled: false),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: ResizableSplitter(
                controller: controller,
                blockerColor: Colors.red,
                semanticsLabel: 'handle',
                startPanel: const SizedBox(),
                endPanel: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.red,
      ),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isDragging, isFalse);
  });

  testWidgets('widget override re-enables overlay when theme disables it', (
    tester,
  ) async {
    final controller = SplitterController();

    final theme = ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        ResizableSplitterThemeOverrides(overlayEnabled: false),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: ResizableSplitter(
                controller: controller,
                overlayEnabled: true,
                blockerColor: Colors.red,
                semanticsLabel: 'handle',
                startPanel: const SizedBox(),
                endPanel: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.red,
      ),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.isDragging, isFalse);
  });
}
