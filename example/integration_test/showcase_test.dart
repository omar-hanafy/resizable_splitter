import 'dart:async';
import 'dart:ui' show FrameTiming, SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
import 'package:resizable_splitter_example/main.dart';
import 'package:resizable_splitter_example/stations/a11y.dart';
import 'package:resizable_splitter_example/stations/collapse.dart';
import 'package:resizable_splitter_example/stations/constraints.dart';
import 'package:resizable_splitter_example/stations/ide.dart';
import 'package:resizable_splitter_example/stations/pixel_pin.dart';
import 'package:resizable_splitter_example/stations/snapping.dart';
import 'package:resizable_splitter_example/theme/tokens.dart';

Finder _within(Type station, Finder matching) =>
    find.descendant(of: find.byType(station), matching: matching);

Finder _splitter(Type station) =>
    _within(station, find.byType(ResizableSplitter));

SplitterController _controller(WidgetTester tester, Type station) =>
    tester.widget<ResizableSplitter>(_splitter(station)).controller!;

// The app intentionally has continuous live-dot/caret animations. Advance the
// documented reveal/transition durations instead of waiting for it to settle.
Future<void> _finishTransitions(WidgetTester tester) async {
  // Build first so implicit animations start, then finish the longest app
  // transition. The final frame delivers deferred geometry/semantics updates.
  await tester.pump();
  await tester.pump(Motion.slow);
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    const TickerMode(enabled: true, child: SplitterShowcaseApp()),
  );
  // The last hero reveal is scheduled at 5 * 70 milliseconds.
  await tester.pump(const Duration(milliseconds: 350));
  await _finishTransitions(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  // Center controls clear of the pinned header, including stacked stations.
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _finishTransitions(tester);
}

Future<void> _tap(WidgetTester tester, Type station, String label) async {
  final button = _within(station, find.text(label));
  await _show(tester, button);
  await tester.tap(button);
  await _finishTransitions(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _resize(WidgetTester tester, Type station, double fraction) async {
  final slider = _within(station, find.byType(Slider));
  await _show(tester, slider);
  final rect = tester.getRect(slider);
  // Stay inside the track's thumb inset. Tapping the track is a real UI action.
  await tester.tapAt(
    Offset(rect.left + 24 + (rect.width - 48) * fraction, rect.center.dy),
  );
  await _finishTransitions(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _dragTo(WidgetTester tester, Type station, double fraction) async {
  final splitter = _splitter(station);
  await _show(tester, splitter);
  final controller = _controller(tester, station);
  final rect = tester.getRect(splitter);
  final layout = controller.layout!;
  final thickness = rect.width - layout.availableExtent;
  final start = Offset(
    rect.left + layout.startExtent + thickness / 2,
    rect.center.dy,
  );
  final target = Offset(
    rect.left + layout.availableExtent * fraction + thickness / 2,
    start.dy,
  );
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await _finishTransitions(tester);
  expect(tester.takeException(), isNull);
}

void _expectRenderedStart(WidgetTester tester, Type station) {
  final widget = tester.widget<ResizableSplitter>(_splitter(station));
  expect(
    tester.getSize(find.byWidget(widget.start)).width,
    closeTo(widget.controller!.layout!.startExtent, 0.01),
  );
}

// A framework pump ends before the web engine finishes its asynchronous scene
// rasterization. Wait for the newest requested frame, including any replacement
// frame requested to flush the web engine's 100ms timing-report batch.
Future<void> _rasterizedFrame(WidgetTester tester, Widget child) async {
  if (!kIsWeb) {
    await tester.pumpWidget(child);
    return;
  }

  final binding = tester.binding;
  final elapsed = Stopwatch()..start();
  const totalTimeout = Duration(seconds: 10);
  var frameWait = const Duration(milliseconds: 101);
  var latestRasterizedFrame = -1;
  int? targetFrame;
  var rasterized = Completer<void>();
  Never failCleanup() => fail(
    'The web engine did not rasterize cleanup frame $targetFrame '
    'within $totalTimeout; latest observed frame: $latestRasterizedFrame.',
  );

  Duration remainingBudget() {
    final remaining = totalTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      failCleanup();
    }
    return remaining;
  }

  void reportTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      if (timing.frameNumber > latestRasterizedFrame) {
        latestRasterizedFrame = timing.frameNumber;
      }
    }
    if (targetFrame != null &&
        latestRasterizedFrame >= targetFrame! &&
        !rasterized.isCompleted) {
      rasterized.complete();
    }
  }

  binding.addTimingsCallback(reportTimings);
  try {
    var firstFrame = true;
    while (true) {
      final pumpBudget = remainingBudget();
      targetFrame = null;
      rasterized = Completer<void>();
      binding.addPostFrameCallback((_) {
        targetFrame = binding.platformDispatcher.frameData.frameNumber;
        if (latestRasterizedFrame >= targetFrame! && !rasterized.isCompleted) {
          rasterized.complete();
        }
      });
      if (firstFrame) {
        await tester
            .pumpWidget(child)
            .timeout(pumpBudget, onTimeout: failCleanup);
        firstFrame = false;
      } else {
        await tester.pump().timeout(pumpBudget, onTimeout: failCleanup);
      }
      try {
        // The web engine reports timings only when a rendered frame flushes its
        // 100ms batch. A fixed 101ms retry can continually supersede the target
        // before a slow raster completes. Grow the event-driven wait so the
        // current/next scene queue can drain, still requiring the newest frame.
        final remaining = remainingBudget();
        final wait = frameWait < remaining ? frameWait : remaining;
        await rasterized.future.timeout(wait);
        return;
      } on TimeoutException {
        remainingBudget();
        frameWait *= 2;
      }
    }
  } finally {
    binding.removeTimingsCallback(reportTimings);
  }
}

void _showcaseTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      final previousPolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
      try {
        // Keep the same app element, but mute its continuous animations before
        // draining its last scene. No automatic app frame may follow that fence.
        await _rasterizedFrame(
          tester,
          const TickerMode(enabled: false, child: SplitterShowcaseApp()),
        );
        await _rasterizedFrame(tester, const SizedBox.shrink());
      } finally {
        binding.framePolicy = previousPolicy;
      }
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  _showcaseTest('pixel pin and fraction survive container resize', (
    tester,
  ) async {
    await _open(tester);
    final controller = _controller(tester, PixelPinStation);
    final original = controller.layout!;
    expect(original.startExtent, closeTo(260, 0.01));
    await _resize(tester, PixelPinStation, 0.65);
    final resized = controller.layout!;
    expect(resized.availableExtent, lessThan(original.availableExtent));
    expect(resized.startExtent, closeTo(260, 0.01));
    expect(resized.effectiveFraction, greaterThan(original.effectiveFraction));
    _expectRenderedStart(tester, PixelPinStation);

    await _tap(tester, PixelPinStation, 'Fraction');
    expect(controller.layout!.effectiveFraction, closeTo(0.42, 0.001));
    final fractionWidth = controller.layout!.startExtent;
    await _resize(tester, PixelPinStation, 0.95);
    expect(controller.layout!.effectiveFraction, closeTo(0.42, 0.001));
    expect(controller.layout!.startExtent, greaterThan(fractionWidth));
    _expectRenderedStart(tester, PixelPinStation);
  });

  _showcaseTest('constraints render a gap and shortage policies', (
    tester,
  ) async {
    await _open(tester);
    final controller = _controller(tester, ConstraintsStation);
    final original = controller.layout!;
    expect(original.resolution, SplitterResolution.maxSurplus);
    expect(original.startExtent, closeTo(340, 0.01));
    expect(original.endExtent, closeTo(340, 0.01));
    expect(original.availableExtent - 680, greaterThan(0));
    _expectRenderedStart(tester, ConstraintsStation);

    await _resize(tester, ConstraintsStation, 0);
    expect(controller.layout!.resolution, SplitterResolution.minShortage);
    expect(controller.layout!.startExtent, closeTo(160, 0.01));
    expect(controller.layout!.endExtent, lessThan(160));
    await _tap(tester, ConstraintsStation, 'favorEnd');
    expect(controller.layout!.endExtent, closeTo(160, 0.01));
    expect(controller.layout!.startExtent, lessThan(160));
    _expectRenderedStart(tester, ConstraintsStation);
  });

  _showcaseTest('all snap modes land on the selected detent', (tester) async {
    await _open(tester);
    for (final mode in ['Release', 'Magnetic', 'Sticky']) {
      await _tap(tester, SnappingStation, mode);
      await _dragTo(tester, SnappingStation, 0.74);
      expect(
        _controller(tester, SnappingStation).layout!.effectiveFraction,
        closeTo(0.75, 0.001),
        reason: '$mode must land on the 75% detent',
      );
      expect(_within(SnappingStation, find.text('on detent')), findsOneWidget);
      _expectRenderedStart(tester, SnappingStation);
      // Move off the detent so the next mode must perform a real capture.
      await _dragTo(tester, SnappingStation, 0.4);
      expect(
        _controller(tester, SnappingStation).layout!.effectiveFraction,
        lessThan(0.5),
      );
    }
  });

  _showcaseTest(
    'collapse restores a dragged position and animation completes',
    (tester) async {
      await _open(tester);
      await _dragTo(tester, CollapseStation, 0.6);
      final controller = _controller(tester, CollapseStation);
      final before = controller.layout!.startExtent;
      expect(controller.layout!.effectiveFraction, closeTo(0.6, 0.001));
      await _tap(tester, CollapseStation, 'Toggle');
      expect(controller.value.collapsedPane, SplitterPane.start);
      expect(controller.layout!.startExtent, 0);
      _expectRenderedStart(tester, CollapseStation);
      await _tap(tester, CollapseStation, 'Expand');
      expect(controller.value.collapsedPane, isNull);
      expect(controller.layout!.startExtent, closeTo(before, 0.01));
      await _tap(tester, CollapseStation, '50%');
      expect(controller.layout!.effectiveFraction, closeTo(0.5, 0.001));
      _expectRenderedStart(tester, CollapseStation);
    },
  );

  _showcaseTest('keyboard bounds, semantics, RTL and double-tap reset agree', (
    tester,
  ) async {
    await _open(tester);
    final semantics = tester.ensureSemantics();
    try {
      final handle = find.bySemanticsLabel('Demo panel divider');
      final controller = _controller(tester, A11yStation);
      // Offscreen controls intentionally have no semantics node. Scroll using
      // the widget tree before finding the visible accessibility control.
      await _show(tester, _splitter(A11yStation));
      expect(handle, findsOneWidget);
      await tester.tap(handle);
      // Finish this single focus tap's double-tap window. Flutter deliberately
      // ignores taps at a different position while the first tap is pending;
      // the keyboard moves the divider before the reset pair below.
      await tester.pump(kDoubleTapTimeout);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.layout!.effectiveFraction, closeTo(0.52, 0.001));
      final initialSemantics = tester.getSemantics(handle).getSemanticsData();
      expect(initialSemantics.value, '52%');
      expect(initialSemantics.flagsCollection.isSlider, isTrue);
      expect(initialSemantics.hasAction(SemanticsAction.increase), isTrue);
      expect(initialSemantics.hasAction(SemanticsAction.decrease), isTrue);
      tester
          .renderObject(handle)
          .owner!
          .semanticsOwner!
          .performAction(
            tester.getSemantics(handle).id,
            SemanticsAction.increase,
          );
      await tester.pump();
      await tester.pump();
      expect(controller.layout!.effectiveFraction, closeTo(0.54, 0.001));
      expect(tester.getSemantics(handle).getSemanticsData().value, '54%');
      await _key(tester, LogicalKeyboardKey.pageDown);
      expect(controller.layout!.effectiveFraction, closeTo(0.64, 0.001));
      await _key(tester, LogicalKeyboardKey.home);
      expect(controller.layout!.startExtent, closeTo(140, 0.01));
      expect(
        tester
            .getSemantics(handle)
            .getSemanticsData()
            .hasAction(SemanticsAction.decrease),
        isFalse,
      );
      await _key(tester, LogicalKeyboardKey.end);
      expect(controller.layout!.endExtent, closeTo(140, 0.01));
      expect(
        tester
            .getSemantics(handle)
            .getSemanticsData()
            .hasAction(SemanticsAction.increase),
        isFalse,
      );

      await tester.tap(handle);
      await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 1));
      await tester.tap(handle);
      await _finishTransitions(tester);
      expect(controller.layout!.effectiveFraction, closeTo(0.5, 0.001));
      await _tap(tester, A11yStation, 'RTL');
      await _show(tester, _splitter(A11yStation));
      expect(handle, findsOneWidget);
      await tester.tap(handle);
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.layout!.effectiveFraction, closeTo(0.48, 0.001));
      expect(tester.getSemantics(handle).getSemanticsData().value, '48%');
      _expectRenderedStart(tester, A11yStation);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  _showcaseTest('nested workspace dividers resize independently', (
    tester,
  ) async {
    await _open(tester);
    final outer = _splitter(IdeStation).first;
    final inner = _splitter(IdeStation).last;
    await _show(tester, outer);
    final outerWidget = tester.widget<ResizableSplitter>(outer);
    final explorer = find.byWidget(outerWidget.start);
    final outerRect = tester.getRect(outer);
    final outerThickness =
        outerRect.width -
        tester.getSize(explorer).width -
        tester.getSize(find.byWidget(outerWidget.end)).width;
    expect(tester.getSize(explorer).width, closeTo(240, 0.01));
    var gesture = await tester.startGesture(
      Offset(outerRect.left + 240 + outerThickness / 2, outerRect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tester.getSize(explorer).width, closeTo(290, 0.01));

    final innerWidget = tester.widget<ResizableSplitter>(inner);
    final editor = find.byWidget(innerWidget.start);
    final terminal = find.byWidget(innerWidget.end);
    final innerRect = tester.getRect(inner);
    final beforeEditor = tester.getSize(editor).height;
    final beforeTerminal = tester.getSize(terminal).height;
    final innerThickness = innerRect.height - beforeEditor - beforeTerminal;
    gesture = await tester.startGesture(
      Offset(
        innerRect.center.dx,
        innerRect.top + beforeEditor + innerThickness / 2,
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tester.getSize(editor).height, closeTo(beforeEditor - 40, 0.01));
    expect(tester.getSize(terminal).height, closeTo(beforeTerminal + 40, 0.01));
    expect(tester.getSize(explorer).width, closeTo(290, 0.01));
    expect(tester.takeException(), isNull);
  });
}
