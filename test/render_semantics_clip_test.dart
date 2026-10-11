import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('collapsed pane excludes descendants outside its paint clip', (
    tester,
  ) async {
    final controller = SplitterController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 408,
              height: 240,
              child: ResizableSplitter(
                controller: controller,
                startConstraints: const SplitterPaneConstraints(
                  minExtent: 100,
                  collapsedExtent: 0,
                ),
                endConstraints: const SplitterPaneConstraints(),
                start: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: 100,
                  minWidth: 100,
                  maxHeight: 40,
                  minHeight: 40,
                  child: Semantics(
                    label: 'start action',
                    button: true,
                    onTap: () {},
                    child: const SizedBox(width: 100, height: 40),
                  ),
                ),
                end: const Semantics(
                  label: 'end content',
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('start action'), findsOneWidget);
      expect(find.bySemanticsLabel('end content'), findsOneWidget);

      controller.collapse(SplitterPane.start);
      await tester.pumpAndSettle();

      expect(controller.layout!.startExtent, 0);
      expect(find.bySemanticsLabel('start action'), findsNothing);
      expect(find.bySemanticsLabel('end content'), findsOneWidget);

      controller.expand();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('start action'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
