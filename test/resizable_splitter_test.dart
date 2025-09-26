import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

void main() {
  testWidgets('renders and responds to controller updates', (tester) async {
    final controller = SplitterController(initialRatio: 0.4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizableSplitter(
            controller: controller,
            startPanel: const ColoredBox(color: Colors.red),
            endPanel: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );

    expect(find.byType(ResizableSplitter), findsOneWidget);

    controller.value = 0.6;
    await tester.pump();

    expect(controller.value, equals(0.6));
  });
}
