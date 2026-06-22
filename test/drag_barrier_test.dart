import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Sub-project 8: a custom drag barrier. The framework keeps the opaque shield
/// that stops platform views from stealing pointer events during a drag;
/// [ResizableSplitter.dragBarrierBuilder] only supplies its visual.
void main() {
  tearDown(SplitterController.resetGlobalRouter);

  Widget host({Widget Function(BuildContext context)? barrier}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 240,
          child: ResizableSplitter(
            divider: const SplitterDividerStyle(thickness: 8),
            startConstraints: const SplitterPaneConstraints(),
            endConstraints: const SplitterPaneConstraints(),
            semanticsLabel: 'handle',
            dragBarrierBuilder: barrier,
            start: const SizedBox(),
            end: const SizedBox(),
          ),
        ),
      ),
    ),
  );

  testWidgets('a custom barrier appears during the drag and is removed after', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(barrier: (_) => const SizedBox(key: Key('barrier'))),
    );
    expect(find.byKey(const Key('barrier')), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
    );
    await tester.pump();
    expect(find.byKey(const Key('barrier')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barrier')), findsNothing);
  });
}
