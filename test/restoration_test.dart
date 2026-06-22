import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 7d: opt-in state restoration. With a [restorationId] the divider
/// position survives a restart (the Flutter restoration framework), even with
/// the internal controller.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget app({String? restorationId}) => MaterialApp(
    restorationScopeId: 'app',
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 408,
          height: 240,
          child: ResizableSplitter(
            restorationId: restorationId,
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            start: Container(key: const Key('start')),
            end: Container(key: const Key('end')),
          ),
        ),
      ),
    ),
  );

  double startWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('start'))).width;

  Future<void> dragRight40(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('restores the divider position across a restart', (tester) async {
    await tester.pumpWidget(app(restorationId: 'splitter'));
    expect(startWidth(tester), closeTo(200, 1e-6)); // centered, available 400

    await dragRight40(tester);
    expect(startWidth(tester), closeTo(240, 1e-6));

    await tester.restartAndRestore();

    // A fresh internal controller would reset to the centered 200; restoration
    // brings back 240.
    expect(startWidth(tester), closeTo(240, 1e-6));
  });

  testWidgets('without a restorationId the position is not restored', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    await dragRight40(tester);
    expect(startWidth(tester), closeTo(240, 1e-6));

    await tester.restartAndRestore();

    // No restorationId => the fresh controller falls back to the centered 200.
    expect(startWidth(tester), closeTo(200, 1e-6));
  });
}
