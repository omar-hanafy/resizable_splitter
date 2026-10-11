import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('splitter supports intrinsic baseline-aligned rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 408,
                  child: ResizableSplitter(
                    start: _BaselineProbe(
                      key: Key('start baseline'),
                      child: Text('start'),
                    ),
                    end: Text('end'),
                  ),
                ),
                _BaselineProbe(key: Key('peer baseline'), child: Text('peer')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final startBox = tester.renderObject<_RenderBaselineProbe>(
      find.byKey(const Key('start baseline')),
    );
    final peerBox = tester.renderObject<_RenderBaselineProbe>(
      find.byKey(const Key('peer baseline')),
    );
    final startBaseline =
        startBox.localToGlobal(Offset.zero).dy +
        startBox.actualBaselines[TextBaseline.alphabetic]!;
    final peerBaseline =
        peerBox.localToGlobal(Offset.zero).dy +
        peerBox.actualBaselines[TextBaseline.alphabetic]!;
    expect(startBaseline, closeTo(peerBaseline, 1e-9));
  });

  for (final axis in Axis.values) {
    for (final boundedAxis in [null, Axis.horizontal, Axis.vertical]) {
      final boundedDescription = boundedAxis == null
          ? 'both axes'
          : '${boundedAxis.name} axis';
      testWidgets('dry baseline matches ${axis.name} RTL layout with '
          '$boundedDescription bounded', (tester) async {
        Widget child = _BaselineProbe(
          child: ResizableSplitter(
            axis: axis,
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            start: const SizedBox(width: 90, height: 60),
            end: const Text('end baseline'),
          ),
        );
        if (boundedAxis == null) {
          child = SizedBox(width: 408, height: 240, child: child);
        } else {
          child = UnconstrainedBox(
            constrainedAxis: boundedAxis,
            child: SizedBox(
              width: boundedAxis == Axis.horizontal ? 408 : null,
              height: boundedAxis == Axis.vertical ? 240 : null,
              child: child,
            ),
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(child: child),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final box = tester.renderObject<_RenderBaselineProbe>(
          find.byType(_BaselineProbe),
        );
        for (final baseline in TextBaseline.values) {
          expect(box.actualBaselines[baseline], isNotNull);
          expect(
            box.dryBaselines[baseline],
            closeTo(box.actualBaselines[baseline]!, 1e-9),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a splitter with no child baseline has no dry baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 408,
            height: 240,
            child: _BaselineProbe(
              child: ResizableSplitter(start: SizedBox(), end: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<_RenderBaselineProbe>(
      find.byType(_BaselineProbe),
    );
    for (final baseline in TextBaseline.values) {
      expect(box.dryBaselines[baseline], isNull);
      expect(box.actualBaselines[baseline], isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom handle can provide the first baseline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 408,
            height: 240,
            child: _BaselineProbe(
              child: ResizableSplitter(
                start: const SizedBox(),
                end: const SizedBox(),
                divider: SplitterDividerStyle(
                  thickness: 8,
                  builder: (_, _) =>
                      const Text('H', style: TextStyle(fontSize: 8)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<_RenderBaselineProbe>(
      find.byType(_BaselineProbe),
    );
    for (final baseline in TextBaseline.values) {
      expect(box.actualBaselines[baseline], isNotNull);
      expect(
        box.dryBaselines[baseline],
        closeTo(box.actualBaselines[baseline]!, 1e-9),
      );
    }
    expect(tester.takeException(), isNull);
  });
}

class _BaselineProbe extends SingleChildRenderObjectWidget {
  const _BaselineProbe({required super.child, super.key});

  @override
  _RenderBaselineProbe createRenderObject(BuildContext context) =>
      _RenderBaselineProbe();
}

class _RenderBaselineProbe extends RenderProxyBox {
  final actualBaselines = <TextBaseline, double?>{};
  final dryBaselines = <TextBaseline, double?>{};

  @override
  void performLayout() {
    super.performLayout();
    final baselineChild = child!;
    for (final baseline in TextBaseline.values) {
      // Actual baselines may only be queried by a parent during layout/paint.
      actualBaselines[baseline] = baselineChild.getDistanceToBaseline(
        baseline,
        onlyReal: true,
      );
      dryBaselines[baseline] = baselineChild.getDryBaseline(
        baselineChild.constraints,
        baseline,
      );
    }
  }
}
