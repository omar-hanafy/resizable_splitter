import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
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

  testWidgets('mouse click focus does not leave a stale focused visual state', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    const idle = Color(0xFF000001);
    const hover = Color(0xFF000002);
    const active = Color(0xFF000003);
    const focused = Color(0xFF000004);
    final controller = SplitterController();

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          divider: SplitterDividerStyle(
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.dragged)) return active;
              if (states.contains(WidgetState.focused)) return focused;
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

    final handle = find.bySemanticsLabel('handle');
    final outsideHandle = tester.getTopRight(find.byType(ResizableSplitter));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: tester.getCenter(handle));
    await tester.pump();
    expect(barDecoration(tester).color, hover);

    await mouse.down(tester.getCenter(handle));
    await tester.pump();
    expect(barDecoration(tester).color, active);

    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.moveTo(outsideHandle);
    await tester.pumpAndSettle();

    expect(barDecoration(tester).color, idle);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(controller.effectiveFraction, greaterThan(0.5));
    expect(barDecoration(tester).color, focused);
  });

  group('default state colors compose onto the resting color', () {
    // Regression: the old defaults REPLACED the opaque resting color
    // (outlineVariant) with a bare onSurface tint (alpha 20/31) for
    // hovered/dragged. Over a dark surface that tint is DARKER than the
    // resting color, so hovering visually dimmed the bar - users read the
    // hover state as "hover broken / flickering" when sweeping across the
    // divider. The contract locked here: the default hovered/dragged colors
    // are the resting color WITH the emphasis tint composited on top, so a
    // state change can never make the divider less visible than at rest.
    Future<({Color resting, Color hovered, Color dragged})> stateColors(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitter(
                  // No divider color anywhere: exercise the package defaults.
                  startConstraints: SplitterPaneConstraints(),
                  endConstraints: SplitterPaneConstraints(),
                  semanticsLabel: 'handle',
                  start: SizedBox(),
                  end: SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );

      final resting = barDecoration(tester).color!;

      final center = tester.getCenter(find.bySemanticsLabel('handle'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: center);
      await tester.pump();
      final hovered = barDecoration(tester).color!;

      await mouse.down(center);
      await tester.pump();
      final dragged = barDecoration(tester).color!;
      await mouse.up();
      await tester.pumpAndSettle();

      return (resting: resting, hovered: hovered, dragged: dragged);
    }

    testWidgets('dark theme: hover/drag brighten the bar, never dim it', (
      tester,
    ) async {
      // The palette from the report: resting outlineVariant 0xFF2A3139 is
      // clearly visible, while the old bare onSurface-alpha-20 hover paint
      // composited to ~0xFF1F2228 over the surface - darker than resting.
      final theme = ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ).copyWith(
              surface: const Color(0xFF0E1217),
              outlineVariant: const Color(0xFF2A3139),
            ),
      );
      final cs = theme.colorScheme;

      final colors = await stateColors(tester, theme);

      expect(colors.resting, cs.outlineVariant);
      expect(
        colors.hovered,
        Color.alphaBlend(cs.onSurface.withAlpha(20), cs.outlineVariant),
      );
      expect(
        colors.dragged,
        Color.alphaBlend(cs.onSurface.withAlpha(31), cs.outlineVariant),
      );
      // The perceptual invariant the regression violated: in a dark theme the
      // emphasis tint (onSurface = near-white) must move the bar TOWARD
      // onSurface, i.e. brighter than resting - never darker.
      expect(
        colors.hovered.computeLuminance(),
        greaterThan(colors.resting.computeLuminance()),
        reason: 'hovering dimmed the divider instead of highlighting it',
      );
      expect(
        colors.dragged.computeLuminance(),
        greaterThan(colors.hovered.computeLuminance()),
        reason: 'dragging must be the strongest emphasis',
      );
    });

    testWidgets('light theme: hover/drag darken the bar, never wash it out', (
      tester,
    ) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue).copyWith(
          surface: const Color(0xFFF7F7F8),
          outlineVariant: const Color(0xFFE1E3E6),
        ),
      );
      final cs = theme.colorScheme;

      final colors = await stateColors(tester, theme);

      expect(colors.resting, cs.outlineVariant);
      expect(
        colors.hovered,
        Color.alphaBlend(cs.onSurface.withAlpha(20), cs.outlineVariant),
      );
      expect(
        colors.dragged,
        Color.alphaBlend(cs.onSurface.withAlpha(31), cs.outlineVariant),
      );
      // Mirror of the dark case: in a light theme onSurface is near-black, so
      // emphasis must make the bar darker than resting.
      expect(
        colors.hovered.computeLuminance(),
        lessThan(colors.resting.computeLuminance()),
        reason: 'hovering washed the divider out instead of highlighting it',
      );
      expect(
        colors.dragged.computeLuminance(),
        lessThan(colors.hovered.computeLuminance()),
        reason: 'dragging must be the strongest emphasis',
      );
    });
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
