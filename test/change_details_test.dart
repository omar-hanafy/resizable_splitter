import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 6: the rich change callbacks carry both the request and the
/// effective layout, tagged with the [SplitterChangeSource] that produced them.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 408, height: 240, child: child)),
    ),
  );

  testWidgets('a drag reports drag-sourced start/changed/end details', (
    tester,
  ) async {
    final controller = SplitterController();
    SplitterChangeDetails? start;
    SplitterChangeDetails? end;
    final changes = <SplitterChangeDetails>[];

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          divider: const SplitterDividerStyle(thickness: 8),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChangeStart: (d) => start = d,
          onChanged: changes.add,
          onChangeEnd: (d) => end = d,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(start, isNotNull);
    expect(start!.source, SplitterChangeSource.drag);
    expect(changes, isNotEmpty);
    expect(changes.every((d) => d.source == SplitterChangeSource.drag), isTrue);
    expect(end, isNotNull);
    expect(end!.source, SplitterChangeSource.drag);

    // available = 408 - 8 = 400. The payload exposes the resolved geometry.
    expect(end!.availableExtent, closeTo(400, 1e-6));
    expect(end!.startExtent + end!.endExtent, closeTo(400, 1e-6));
    expect(end!.effectiveFraction, closeTo(controller.effectiveFraction, 1e-6));
  });

  testWidgets('a snap on release reports SplitterChangeSource.snap', (
    tester,
  ) async {
    final controller = SplitterController();
    SplitterChangeDetails? end;

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          divider: const SplitterDividerStyle(thickness: 8),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          snap: const SplitterSnapBehavior(points: [0.75], tolerance: 0.2),
          onChangeEnd: (d) => end = d,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    // Drag from 0.5 toward 0.7 so the 0.75 snap point claims the release.
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(end, isNotNull);
    expect(end!.source, SplitterChangeSource.snap);
    expect(controller.effectiveFraction, closeTo(0.75, 1e-6));
  });

  testWidgets('a canceled drag does not snap or fire a successful end '
      '(a cancel is not a release)', (tester) async {
    final controller = SplitterController();
    SplitterChangeDetails? end;

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          divider: const SplitterDividerStyle(thickness: 8),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          snap: const SplitterSnapBehavior(points: [0.75], tolerance: 0.2),
          onChangeEnd: (d) => end = d,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    // Drag toward the 0.75 snap point, then a system cancel interrupts it.
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final atCancel = controller.effectiveFraction;
    await gesture.cancel();
    await tester.pumpAndSettle();

    // A cancel is not a successful release: it must neither settle onto the
    // snap point nor report a drag/snap end.
    expect(controller.effectiveFraction, closeTo(atCancel, 1e-6));
    expect(controller.effectiveFraction, isNot(closeTo(0.75, 1e-6)));
    expect(end, isNull);
  });

  testWidgets('a keyboard adjust reports SplitterChangeSource.keyboard', (
    tester,
  ) async {
    final controller = SplitterController();
    final sources = <SplitterChangeSource>[];

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChanged: (d) => sources.add(d.source),
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('handle'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(sources, contains(SplitterChangeSource.keyboard));
  });

  testWidgets('change details carry the real request: a pin at start, a '
      'fraction after moving (review #9)', (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.startPixels(120),
    );
    SplitterChangeDetails? start;
    SplitterChangeDetails? lastChange;

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          divider: const SplitterDividerStyle(thickness: 8),
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChangeStart: (d) => start = d,
          onChanged: (d) => lastChange = d,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );

    final handle = find.bySemanticsLabel('handle');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();

    // At drag start the request is still the pixel pin - not a fraction
    // fabricated from the effective value - even though it shows at 120/400.
    expect(start, isNotNull);
    expect(start!.requestedPosition, const SplitterPosition.startPixels(120));
    expect(start!.effectiveFraction, closeTo(120 / 400, 1e-6));

    // Moving the divider releases the pin: the request becomes a fraction.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(lastChange, isNotNull);
    expect(lastChange!.requestedPosition, isA<FractionSplitterPosition>());

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a direct controller write notifies the controller but does not '
      'fire onChanged (review #4)', (tester) async {
    final controller = SplitterController();
    var onChangedCount = 0;
    var controllerNotifications = 0;
    var layoutNotifications = 0;
    controller.addListener(() => controllerNotifications++);
    controller.layoutListenable.addListener(() => layoutNotifications++);

    await tester.pumpWidget(
      host(
        ResizableSplitter(
          controller: controller,
          startConstraints: const SplitterPaneConstraints(),
          endConstraints: const SplitterPaneConstraints(),
          semanticsLabel: 'handle',
          onChanged: (_) => onChangedCount++,
          onChangeStart: (_) => onChangedCount++,
          onChangeEnd: (_) => onChangedCount++,
          start: const SizedBox(),
          end: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final onChangedBefore = onChangedCount;
    final controllerBefore = controllerNotifications;
    final layoutBefore = layoutNotifications;

    // A direct programmatic write.
    controller.jumpTo(const SplitterPosition.fraction(0.7));
    await tester.pumpAndSettle();

    // The contract: programmatic writes are observed via the controller /
    // layoutListenable, NOT via the interaction callbacks.
    expect(
      onChangedCount,
      onChangedBefore,
      reason: 'onChanged is interaction-only',
    );
    expect(controllerNotifications, greaterThan(controllerBefore));
    expect(layoutNotifications, greaterThan(layoutBefore));
    expect(controller.effectiveFraction, closeTo(0.7, 1e-6));
  });
}
