import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
import 'package:resizable_splitter_example/main.dart';
import 'package:resizable_splitter_example/native_macos_sidebar_demo.dart';

/// Finds a [MacosIcon] by its [IconData] - macos_ui uses [MacosTooltip] (not
/// the Material [Tooltip]), so `find.byTooltip` does not work for toolbar items.
Finder _macosIcon(IconData icon) =>
    find.byWidgetPredicate((w) => w is MacosIcon && w.icon == icon);

void main() {
  testWidgets('renders splitter, sidebar items, and toolbar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NativeMacosSplitterDemo()));
    await tester.pumpAndSettle();

    expect(find.byType(ResizableSplitter), findsOneWidget);
    expect(find.byType(SidebarItems), findsOneWidget);
    expect(find.byType(ToolBar), findsOneWidget);
  });

  testWidgets('toolbar toggle collapses and expands the sidebar', (
    tester,
  ) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.startPixels(280),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NativeMacosSplitterDemo(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(controller.collapsedPane, isNull);

    final toggle = find.ancestor(
      of: _macosIcon(CupertinoIcons.sidebar_left),
      matching: find.byType(MacosIconButton),
    );
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.collapsedPane, SplitterPane.start);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.collapsedPane, isNull);
  });

  test('detent fractions convert pixel targets and clamp to [0,1]', () {
    expect(macosSidebarDetentFractions(1000), <Matcher>[
      closeTo(0.22, 1e-9),
      closeTo(0.28, 1e-9),
      closeTo(0.34, 1e-9),
    ]);
    // Tiny container: every pixel target exceeds it, so all clamp to 1.0.
    expect(
      macosSidebarDetentFractions(100).every((f) => f >= 0 && f <= 1),
      isTrue,
    );
    // Zero / non-finite extent must not produce NaN or throw.
    expect(
      macosSidebarDetentFractions(0).every((f) => f >= 0 && f <= 1),
      isTrue,
    );
  });

  testWidgets('gallery lists Native macOS entry and launches the screen', (
    tester,
  ) async {
    // Desktop-sized surface so all gallery nav entries are built (the lazy
    // ListView would not build the off-screen "Native macOS" entry at 800x600).
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ResizableSplitterExampleApp());
    await tester.pumpAndSettle();

    final navEntry = find.text('Native macOS');
    expect(navEntry, findsOneWidget);

    await tester.tap(navEntry);
    await tester.pumpAndSettle();

    final launchButton = find.widgetWithText(
      FilledButton,
      'Open full-screen demo',
    );
    expect(launchButton, findsOneWidget);

    await tester.tap(launchButton);
    await tester.pumpAndSettle();

    expect(find.byType(NativeMacosSplitterDemo), findsOneWidget);
  });
}
