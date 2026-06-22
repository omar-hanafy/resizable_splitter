import 'package:flutter/gestures.dart';
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

  Finder barFinder() => find.descendant(
    of: find.byType(ResizableSplitter),
    matching: find.byType(AnimatedContainer),
  );

  BoxDecoration barDecoration(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(barFinder()).decoration!
          as BoxDecoration;

  for (final axis in Axis.values) {
    testWidgets(
      'hidden grab slop does not create a visual hover state on $axis',
      (tester) async {
        const idle = Color(0xFF000001);
        const hover = Color(0xFF000002);
        const active = Color(0xFF000003);
        const thickness = 8.0;
        const interactiveExtent = 48.0;

        await tester.pumpWidget(
          host(
            ResizableSplitter(
              axis: axis,
              divider: SplitterDividerStyle(
                thickness: thickness,
                interactiveExtent: interactiveExtent,
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.dragged)) return active;
                  if (states.contains(WidgetState.hovered)) return hover;
                  return idle;
                }),
              ),
              startConstraints: const SplitterPaneConstraints(),
              endConstraints: const SplitterPaneConstraints(),
              semanticsLabel: 'handle',
              start: const SizedBox(),
              end: const SizedBox(),
            ),
          ),
        );

        expect(barDecoration(tester).color, idle);

        final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
        final slopPoint = axis == Axis.horizontal
            ? Offset(handleRect.left + 2, handleRect.center.dy)
            : Offset(handleRect.center.dx, handleRect.top + 2);
        final visibleBarPoint = Offset(
          handleRect.center.dx,
          handleRect.center.dy,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);

        await mouse.addPointer(location: slopPoint);
        await tester.pump();
        expect(barDecoration(tester).color, idle);

        await mouse.moveTo(visibleBarPoint);
        await tester.pump();
        expect(barDecoration(tester).color, hover);

        await mouse.moveTo(slopPoint);
        await tester.pump();
        expect(barDecoration(tester).color, idle);
      },
    );
  }

  testWidgets('drag released in hidden grab slop returns to idle color', (
    tester,
  ) async {
    const idle = Color(0xFF000001);
    const hover = Color(0xFF000002);
    const active = Color(0xFF000003);
    const thickness = 8.0;
    const interactiveExtent = 48.0;

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          divider: SplitterDividerStyle(
            thickness: thickness,
            interactiveExtent: interactiveExtent,
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.dragged)) return active;
              if (states.contains(WidgetState.hovered)) return hover;
              return idle;
            }),
          ),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handleRect = tester.getRect(find.bySemanticsLabel('handle'));
    final slopPoint = Offset(handleRect.left + 2, handleRect.center.dy);
    final gesture = await tester.startGesture(
      slopPoint,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(barDecoration(tester).color, active);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(barDecoration(tester).color, idle);
  });

  testWidgets('non-resizable divider does not create a hover state', (
    tester,
  ) async {
    const idle = Color(0xFF000001);
    const hover = Color(0xFF000002);

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          resizable: false,
          divider: SplitterDividerStyle(
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return hover;
              return idle;
            }),
          ),
          semanticsLabel: 'handle',
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(
      location: tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();

    expect(barDecoration(tester).color, idle);
  });
}
