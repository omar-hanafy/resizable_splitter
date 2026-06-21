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
        child: ResizableSplitter(
          initialPosition: const SplitterPosition.fraction(0.1),
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          startConstraints: const SplitterPaneConstraints(minExtent: 200),
          endConstraints: const SplitterPaneConstraints(minExtent: 50),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
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
        child: ResizableSplitter(
          initialPosition: const SplitterPosition.fraction(0.8),
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          startConstraints: const SplitterPaneConstraints(minExtent: 200),
          endConstraints: const SplitterPaneConstraints(minExtent: 150),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
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
    final controller = SplitterController(
      initialPosition: const SplitterPosition.fraction(0.25),
    );

    await tester.pumpWidget(
      frame(
        height: totalHeight,
        child: ResizableSplitter(
          axis: Axis.vertical,
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          semanticsLabel: 'handle',
          start: Container(key: const Key('top')),
          end: Container(key: const Key('bottom')),
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
          initialPosition: const SplitterPosition.fraction(0.7),
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          startConstraints: const SplitterPaneConstraints(minExtent: 180),
          endConstraints: const SplitterPaneConstraints(minExtent: 140),
          semanticsLabel: 'handle',
          start: Container(key: const Key('top')),
          end: Container(key: const Key('bottom')),
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
          semanticsLabel: 'handle',
          start: const SizedBox(),
          end: const SizedBox(),
          divider: SplitterDividerStyle(
            builder: (_, details) {
              expect(details.thickness, 6.0);
              expect(details.axis, Axis.horizontal);
              return Container(key: const Key('customGrip'));
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('customGrip')), findsOneWidget);
  });

  testWidgets('end panel keeps its minimum when cramped behavior favors end', (
    tester,
  ) async {
    const dividerThickness = 8.0;
    const totalWidth = 320.0;

    await tester.pumpWidget(
      frame(
        width: totalWidth,
        child: ResizableSplitter(
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          constraintPolicy: SplitterConstraintPolicy.favorEnd,
          startConstraints: const SplitterPaneConstraints(minExtent: 200),
          endConstraints: const SplitterPaneConstraints(minExtent: 140),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
        ),
      ),
    );

    final startSize = tester.getSize(find.byKey(const Key('start')));
    final endSize = tester.getSize(find.byKey(const Key('end')));
    const available = totalWidth - dividerThickness;

    expect(endSize.width, closeTo(140, 1e-6));
    expect(startSize.width, closeTo(available - 140, 1e-6));
  });

  testWidgets('cramped proportionallyClamp splits space by configured minima', (
    tester,
  ) async {
    const dividerThickness = 6.0;
    const totalWidth = 270.0;

    await tester.pumpWidget(
      frame(
        width: totalWidth,
        child: ResizableSplitter(
          divider: const SplitterDividerStyle(thickness: dividerThickness),
          constraintPolicy: SplitterConstraintPolicy.proportional,
          startConstraints: const SplitterPaneConstraints(minExtent: 180),
          endConstraints: const SplitterPaneConstraints(minExtent: 120),
          semanticsLabel: 'handle',
          start: Container(key: const Key('start')),
          end: Container(key: const Key('end')),
        ),
      ),
    );

    final startSize = tester.getSize(find.byKey(const Key('start')));
    final endSize = tester.getSize(find.byKey(const Key('end')));
    const available = totalWidth - dividerThickness;
    const expectedRatio = 180 / (180 + 120); // 0.6

    expect(startSize.width, closeTo(available * expectedRatio, 1e-3));
    expect(endSize.width, closeTo(available * (1 - expectedRatio), 1e-3));
  });

  testWidgets(
    'antiAliasingWorkaround snaps the leading panel to a physical pixel',
    (tester) async {
      const dividerThickness = 3.0;
      const totalWidth = 303.0;
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.331),
      );

      await tester.pumpWidget(
        frame(
          width: totalWidth,
          child: ResizableSplitter(
            controller: controller,
            divider: const SplitterDividerStyle(thickness: dividerThickness),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            antiAliasingWorkaround: true,
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      );

      final startSize = tester.getSize(find.byKey(const Key('start')));
      final endSize = tester.getSize(find.byKey(const Key('end')));
      const available = totalWidth - dividerThickness;

      // Now snaps to a whole *physical* pixel (was a whole logical pixel), so
      // it stays crisp at fractional device-pixel ratios. The leading extent
      // lands on a device-pixel boundary near the requested 0.331 * available.
      final dpr = tester.view.devicePixelRatio;
      final physical = startSize.width * dpr;
      expect((physical - physical.roundToDouble()).abs(), lessThan(1e-6));
      expect(startSize.width, closeTo(available * 0.331, 1.0));
      expect(endSize.width, closeTo(available - startSize.width, 1e-6));
    },
  );

  testWidgets('LimitedBox fallback is used when unconstrained and opted in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResizableSplitterTheme(
          data: const ResizableSplitterThemeData(
            unboundedBehavior: UnboundedBehavior.limitedBox,
            fallbackMainAxisExtent: 420,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: UnconstrainedBox(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: 200,
                  child: ResizableSplitter(
                    semanticsLabel: 'handle',
                    start: Container(key: const Key('start')),
                    end: Container(key: const Key('end')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is LimitedBox && widget.maxWidth == 420,
      ),
      findsOneWidget,
    );

    final startSize = tester.getSize(find.byKey(const Key('start')));
    final endSize = tester.getSize(find.byKey(const Key('end')));
    const expectedAvailable = 420 - 6; // fallbackExtent - default divider

    expect(startSize.width, closeTo(expectedAvailable / 2, 1e-6));
    expect(endSize.width, closeTo(expectedAvailable / 2, 1e-6));
  });

  testWidgets(
    'widget override keeps flexExpand even when theme uses LimitedBox',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResizableSplitterTheme(
            data: const ResizableSplitterThemeData(
              unboundedBehavior: UnboundedBehavior.limitedBox,
              fallbackMainAxisExtent: 420,
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 0,
                  child: SizedBox(
                    height: 200,
                    child: ResizableSplitter(
                      unboundedBehavior: UnboundedBehavior.flexExpand,
                      semanticsLabel: 'handle',
                      start: Container(key: const Key('start')),
                      end: Container(key: const Key('end')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is LimitedBox && widget.maxWidth == 420,
        ),
        findsNothing,
      );

      expect(find.byType(Flex), findsWidgets);
    },
  );

  testWidgets(
    'widget override disables anti-alias workaround when theme enables',
    (tester) async {
      const dividerThickness = 3.0;
      const totalWidth = 303.0;
      final controller = SplitterController(
        initialPosition: const SplitterPosition.fraction(0.331),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResizableSplitterTheme(
            data: const ResizableSplitterThemeData(
              antiAliasingWorkaround: true,
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: totalWidth,
                  child: ResizableSplitter(
                    controller: controller,
                    divider: const SplitterDividerStyle(
                      thickness: dividerThickness,
                    ),
                    startConstraints: const SplitterPaneConstraints(),
                    endConstraints: const SplitterPaneConstraints(),
                    antiAliasingWorkaround: false,
                    semanticsLabel: 'handle',
                    start: Container(key: const Key('start')),
                    end: Container(key: const Key('end')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final startSize = tester.getSize(find.byKey(const Key('start')));
      final endSize = tester.getSize(find.byKey(const Key('end')));
      const available = totalWidth - dividerThickness;

      expect(startSize.width.floorToDouble(), equals(99.0));
      expect(startSize.width, greaterThan(99.0));
      expect(startSize.width, closeTo(available * 0.331, 1e-3));
      expect(endSize.width, closeTo(available - startSize.width, 1e-6));
    },
  );
}
