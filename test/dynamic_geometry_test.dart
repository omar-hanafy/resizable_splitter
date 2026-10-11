import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  for (final updatePixelRatio in [false, true]) {
    testWidgets(
      updatePixelRatio
          ? 'keyboard uses a new pixel ratio when current extents stay equal'
          : 'keyboard uses pixel snapping enabled without changing the layout',
      (tester) async {
        final controller = SplitterController();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        });
        final changes = <SplitterChangeDetails>[];
        var snap = updatePixelRatio;
        var pixelRatio = 1.0;
        late StateSetter updateHost;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(devicePixelRatio: pixelRatio),
                  child: Center(
                    child: SizedBox(
                      width: 408,
                      height: 240,
                      child: ResizableSplitter(
                        controller: controller,
                        divider: const SplitterDividerStyle(thickness: 8),
                        keyboardStep: 0.0015,
                        enableHaptics: false,
                        snapToPhysicalPixels: snap,
                        startConstraints: const SplitterPaneConstraints(),
                        endConstraints: const SplitterPaneConstraints(),
                        semanticsLabel: 'handle',
                        semantics: SplitterSemanticsLabels(
                          formatValue: (fraction) =>
                              (fraction * 400).toStringAsFixed(1),
                        ),
                        onChanged: changes.add,
                        start: const SizedBox(key: Key('start')),
                        end: const SizedBox(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        updateHost(() {
          if (updatePixelRatio) {
            pixelRatio = 2;
          } else {
            snap = true;
          }
        });
        await tester.pumpAndSettle();
        expect(controller.layout!.startExtent, 200);

        final expectedExtent = updatePixelRatio ? 200.5 : 201.0;
        final semantics = tester.ensureSemantics();
        try {
          expect(
            tester.getSemantics(find.bySemanticsLabel('handle')).increasedValue,
            expectedExtent.toStringAsFixed(1),
          );
        } finally {
          semantics.dispose();
        }

        await tester.tap(find.bySemanticsLabel('handle'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(changes, hasLength(1));
        expect(changes.single.startExtent, expectedExtent);
        expect(controller.layout!.startExtent, expectedExtent);
        expect(
          tester.getSize(find.byKey(const Key('start'))).width,
          expectedExtent,
        );
      },
    );
  }
}
