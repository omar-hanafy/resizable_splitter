import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
import 'package:resizable_splitter_example/main.dart';

/// Loads the app's bundled fonts so text measures with real metrics (the
/// default test font renders every glyph one em wide, which wildly inflates
/// widths and would flag overflows that never happen in production).
Future<void> _loadFonts() async {
  const families = {
    'JetBrains Mono': 'assets/fonts/JetBrainsMono.ttf',
    'Hanken Grotesk': 'assets/fonts/HankenGrotesk.ttf',
    'Bricolage Grotesque': 'assets/fonts/BricolageGrotesque.ttf',
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

/// The showcase is full of intentionally infinite animations (live dots, the
/// terminal caret), so [pumpAndSettle] would never return. These tests pump a
/// fixed number of frames instead, and assert the whole page builds and lays
/// out without throwing at several breakpoints - a deterministic overflow check
/// that needs no browser.
Future<void> _pumpShowcase(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const SplitterShowcaseApp());
  // Advance past the staggered reveal timers and a few animation frames.
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('builds at desktop width without exceptions', (tester) async {
    await _pumpShowcase(tester, const Size(1440, 1000));
    expect(tester.takeException(), isNull);
    expect(find.byType(SplitterShowcaseApp), findsOneWidget);
    // Several live splitters compose the page (hero + stations).
    expect(find.byType(ResizableSplitter), findsWidgets);
  });

  testWidgets('builds at tablet width without exceptions', (tester) async {
    await _pumpShowcase(tester, const Size(834, 1112));
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds at mobile width without exceptions', (tester) async {
    await _pumpShowcase(tester, const Size(390, 1800));
    expect(tester.takeException(), isNull);
    expect(find.byType(ResizableSplitter), findsWidgets);
  });

  testWidgets('hero divider drags without error', (tester) async {
    await _pumpShowcase(tester, const Size(1440, 1000));
    final splitter = find.byType(ResizableSplitter).first;
    // Drag near the center of the first (hero) splitter's divider region.
    final center = tester.getCenter(splitter);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
