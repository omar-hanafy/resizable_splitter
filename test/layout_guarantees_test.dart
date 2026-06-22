import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('content cannot bleed across the divider (panes are clipped)', (
    tester,
  ) async {
    // Behavioral clip guarantee (replaces the old ClipRect-count assertion, which
    // coupled to the widget tree shape): an oversized start child must not paint
    // into the end pane. Holds whether the clip is a ClipRect widget or the
    // render object's own paint-time clip.
    await tester.pumpWidget(
      host(
        width: 200,
        height: 100,
        child: const RepaintBoundary(
          key: Key('boundary'),
          child: ResizableSplitter(
            divider: SplitterDividerStyle(thickness: 0),
            startConstraints: SplitterPaneConstraints(),
            endConstraints: SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: 200,
              child: SizedBox(
                width: 200,
                height: 100,
                child: ColoredBox(color: Colors.red),
              ),
            ),
            end: ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // x=150 is inside the end pane ([100, 200]); the red start pane must be
    // clipped out of it.
    final color = await _sampleColor(tester, const Key('boundary'), 150, 50);
    expect(color, isSameColorAs(Colors.white));
  });
}

Future<Color> _sampleColor(
  WidgetTester tester,
  Key boundaryKey,
  int x,
  int y,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  // toImage()/toByteData() resolve on the engine, which needs real async - the
  // default fake-async test zone would deadlock, so run them via runAsync.
  final color = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final offset = (y * image.width + x) * 4;
    final sampled = Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
    image.dispose();
    return sampled;
  });
  return color!;
}
