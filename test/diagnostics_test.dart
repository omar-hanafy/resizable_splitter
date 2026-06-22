import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 8: diagnostics for the Flutter Inspector / `toStringDeep`.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  List<String> propNames(Diagnosticable target) => target
      .toDiagnosticsNode()
      .getProperties()
      .map((p) => p.name ?? '')
      .toList();

  String propsString(Diagnosticable target) => target
      .toDiagnosticsNode()
      .getProperties()
      .map((p) => p.toString())
      .join(', ');

  group('ResizableSplitter widget', () {
    test('exposes its configuration', () {
      const widget = ResizableSplitter(
        axis: Axis.vertical,
        resizable: false,
        start: SizedBox(),
        end: SizedBox(),
      );
      final names = propNames(widget);
      expect(names, containsAll(<String>['axis', 'resizable']));
      final text = propsString(widget);
      expect(text, contains('vertical'));
    });
  });

  group('SplitterController', () {
    test('exposes request, effective fraction, and live state', () {
      final controller = SplitterController(
        initialPosition: const SplitterPosition.startPixels(200),
      );
      addTearDown(controller.dispose);

      final names = propNames(controller);
      expect(
        names,
        containsAll(<String>['position', 'effectiveFraction', 'isAttached']),
      );

      final text = propsString(controller);
      // Detached, not dragging, not collapsed by default.
      expect(text, contains('isAttached: false'));
    });

    testWidgets('reports drag + attachment state while mounted', (
      tester,
    ) async {
      final controller = SplitterController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: ResizableSplitter(
                  controller: controller,
                  start: const SizedBox(),
                  end: const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = propsString(controller);
      expect(text, contains('isAttached: true'));
      expect(propNames(controller), contains('layout'));
    });
  });

  testWidgets('the splitter State surfaces the live layout + resolution', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 240,
              child: ResizableSplitter(start: SizedBox(), end: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<State<StatefulWidget>>(
      find.byType(ResizableSplitter),
    );
    final deep = state.toDiagnosticsNode().toStringDeep();
    expect(deep, contains('resolution'));
    expect(deep, contains('layout'));
  });
}
