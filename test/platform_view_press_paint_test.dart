import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  tearDown(SplitterController.resetGlobalRouter);

  testWidgets('platform-view shield paints before a drag accepts the press', (
    tester,
  ) async {
    final controller = SplitterController();
    const cosmeticKey = Key('cosmetic-barrier');
    const baseKey = Key('resizable_splitter.shield_base_barrier');

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 408,
            height: 240,
            child: ResizableSplitter(
              controller: controller,
              semanticsLabel: 'handle',
              onHandleDoubleTap: () {},
              dragBarrierBuilder: (_) =>
                  const ColoredBox(key: cosmeticKey, color: Colors.red),
              start: const SizedBox(),
              end: const SizedBox(),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('handle')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(controller.isDragging, isFalse);
    expect(find.byKey(cosmeticKey), findsNothing);
    expect(find.byKey(baseKey), findsOneWidget);
    expect(
      tester.widget<ColoredBox>(find.byKey(baseKey)).color.a,
      greaterThan(0),
    );

    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(controller.isDragging, isTrue);
    expect(find.byKey(baseKey), findsOneWidget);
    expect(find.byKey(cosmeticKey), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.isDragging, isFalse);
    expect(find.byKey(baseKey), findsNothing);
    expect(find.byKey(cosmeticKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
