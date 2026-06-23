# Native macOS Splitter Example - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an example that showcases `ResizableSplitter` inside authentic macOS chrome (macos_ui 2.2.2) with StickySnap detents and a collapsible sidebar, launched full-screen from the existing gallery.

**Architecture:** A new self-contained screen file roots itself under `MacosTheme -> MacosWindow -> MacosScaffold` with a real `ToolBar`; the scaffold's single `ContentArea` hosts our `ResizableSplitter` (sidebar | content). The existing Material gallery gets one entry whose pane shows a launcher card that pushes the screen via the root navigator. Pixel-target StickySnap detents are computed from the measured main extent inside a `LayoutBuilder`.

**Tech Stack:** Flutter, `resizable_splitter` (path dep), `macos_ui ^2.2.2`, `flutter_test`.

## Global Constraints

- `macos_ui: ^2.2.2` (example dev-facing dependency only; library untouched).
- No changes to any file under `lib/` (the published package).
- No em-dash characters anywhere; use `-` or `_`.
- macos_ui layout widgets need only a `MacosTheme` ancestor - do NOT add `MacosApp` or call `WindowManipulator`.
- Example SDK is `^3.9.2`; macos_ui 2.2.2 needs Dart `>=3.9.2`, Flutter `>=3.35.0`.
- Commits: do not add co-author/attribution footers (user rule).

---

### Task 1: Add macos_ui dependency

**Files:**
- Modify: `example/pubspec.yaml`

**Interfaces:**
- Produces: `package:macos_ui/macos_ui.dart` available to the example.

- [ ] **Step 1: Add the dependency** under `dependencies:` in `example/pubspec.yaml`, after `webview_flutter`:

```yaml
  macos_ui: ^2.2.2
```

- [ ] **Step 2: Resolve**

Run: `cd example && flutter pub get`
Expected: resolves with `macos_ui 2.2.2` and `macos_window_utils` in the lockfile, exit 0.

- [ ] **Step 3: Commit**

```bash
git add example/pubspec.yaml example/pubspec.lock
git commit -m "build(example): add macos_ui 2.2.2 dependency"
```

---

### Task 2: Native macOS splitter screen

**Files:**
- Create: `example/lib/native_macos_sidebar_demo.dart`
- Test: `example/test/native_macos_sidebar_demo_test.dart`

**Interfaces:**
- Produces:
  - `class NativeMacosSplitterDemo extends StatefulWidget` with
    `const NativeMacosSplitterDemo({super.key, this.controller})` where
    `final SplitterController? controller` (optional injection for tests; the
    state creates and owns one when null).
  - `List<double> macosSidebarDetentFractions(double availableExtent)` - pure
    helper converting the fixed pixel detents `[220, 280, 340]` to start
    fractions, clamped to `[0, 1]`. Exported for direct unit testing.

- [ ] **Step 1: Write the failing tests**

Create `example/test/native_macos_sidebar_demo_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
import 'package:resizable_splitter_example/native_macos_sidebar_demo.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('renders splitter, sidebar items, and toolbar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NativeMacosSplitterDemo()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ResizableSplitter), findsOneWidget);
    expect(find.byType(SidebarItems), findsOneWidget);
    expect(find.byType(ToolBar), findsOneWidget);
  });

  testWidgets('toolbar toggle collapses and expands the sidebar',
      (tester) async {
    final controller = SplitterController(
      initialPosition: const SplitterPosition.startPixels(280),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NativeMacosSplitterDemo(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(controller.collapsedPane, isNull);

    await tester.tap(find.byTooltip('Toggle sidebar'));
    await tester.pumpAndSettle();
    expect(controller.collapsedPane, SplitterPane.start);

    await tester.tap(find.byTooltip('Toggle sidebar'));
    await tester.pumpAndSettle();
    expect(controller.collapsedPane, isNull);
  });

  test('detent fractions convert pixel targets and clamp to [0,1]', () {
    final fractions = macosSidebarDetentFractions(1000);
    expect(fractions, <double>[0.22, 0.28, 0.34]);
    expect(macosSidebarDetentFractions(100).every((f) => f >= 0 && f <= 1),
        isTrue);
    // Zero / non-finite extent must not produce NaN or throw.
    expect(macosSidebarDetentFractions(0).every((f) => f >= 0 && f <= 1),
        isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd example && flutter test test/native_macos_sidebar_demo_test.dart`
Expected: FAIL - `native_macos_sidebar_demo.dart` / `NativeMacosSplitterDemo` not found.

- [ ] **Step 3: Implement the screen**

Create `example/lib/native_macos_sidebar_demo.dart`. Key requirements (assemble the full widget tree to satisfy the tests and the spec):

- Imports: `package:flutter/cupertino.dart` (CupertinoIcons), `package:flutter/material.dart`, `package:macos_ui/macos_ui.dart`, `package:resizable_splitter/resizable_splitter.dart`.
- Pure helper (top-level), uses the fixed detents and guards bad extents:

```dart
const List<double> _detentPixels = <double>[220, 280, 340];

List<double> macosSidebarDetentFractions(double availableExtent) {
  if (!availableExtent.isFinite || availableExtent <= 0) {
    return const <double>[0, 0, 0];
  }
  return _detentPixels
      .map((px) => (px / availableExtent).clamp(0.0, 1.0).toDouble())
      .toList(growable: false);
}
```

- `NativeMacosSplitterDemo` state: owns `late final SplitterController _controller` set to `widget.controller ?? SplitterController(initialPosition: const SplitterPosition.startPixels(280))`; track `_ownsController = widget.controller == null`; dispose only if owned. Track `Brightness _brightness` defaulting from `MediaQuery.platformBrightnessOf(context)` (read in `didChangeDependencies` once).
- `build`: wrap in
  `MacosTheme(data: _brightness == Brightness.dark ? MacosThemeData.dark() : MacosThemeData.light(), child: MacosWindow(child: MacosScaffold(toolBar: _toolBar(context), children: [ContentArea(builder: (ctx, _) => _splitter(ctx))])))`.
- `_toolBar`: `ToolBar(title: const Text('ResizableSplitter | macOS'), leading: MacosBackButton(onPressed: () => Navigator.of(context, rootNavigator: true).maybePop()), actions: [ToolBarIconButton(label: 'Toggle sidebar', icon: const MacosIcon(CupertinoIcons.sidebar_left), showLabel: false, tooltipMessage: 'Toggle sidebar', onPressed: () => _controller.toggleCollapse(SplitterPane.start)), ToolBarIconButton(label: 'Toggle appearance', icon: MacosIcon(_brightness == Brightness.dark ? CupertinoIcons.sun_max : CupertinoIcons.moon), showLabel: false, tooltipMessage: 'Toggle appearance', onPressed: () => setState(() => _brightness = _brightness == Brightness.dark ? Brightness.light : Brightness.dark))])`.
- `_splitter`: `LayoutBuilder(builder: (ctx, constraints) { final detents = macosSidebarDetentFractions(constraints.maxWidth); return ResizableSplitter(axis: Axis.horizontal, controller: _controller, startConstraints: const SplitterPaneConstraints(minExtent: 200, maxExtent: 360, collapsedExtent: 0), snap: SplitterSnapBehavior.sticky(points: detents, pixelTolerance: 16), divider: _dividerStyle(ctx), start: const _SidebarPane(), end: const _DetailPane()); })`.
- `_dividerStyle`: `SplitterDividerStyle(thickness: 1, interactiveExtent: 12, color: WidgetStatePropertyAll(MacosTheme.of(context).dividerColor))`.
- `_SidebarPane`: `MacosScrollbar(child: SidebarItems(currentIndex: <local state or fixed 0>, onChanged: <setState>, items: const [SidebarItem(section: true, label: Text('Showcase')), SidebarItem(leading: MacosIcon(CupertinoIcons.square_split_2x1), label: Text('Splitter')), SidebarItem(leading: MacosIcon(CupertinoIcons.slider_horizontal_3), label: Text('Controls')), SidebarItem(leading: MacosIcon(CupertinoIcons.textformat), label: Text('Typography'))]))`. Keep selection in a `StatefulWidget` (small) so SidebarItems has a valid `currentIndex`/`onChanged`.
- `_DetailPane`: `MacosScrollbar` wrapping a `ListView`/`Column` with a title and a few native controls: a `PushButton(controlSize: ControlSize.large, child: Text('Primary'), onPressed: () {})`, a `MacosSwitch(value: ..., onChanged: ...)`, a `MacosSlider(value: ..., onChanged: ...)`. Local `StatefulWidget` to hold switch/slider state. This is placeholder content - keep it short.

Note: `SidebarItems`, `MacosSwitch`, and `MacosSlider` need state; implement `_SidebarPane`/`_DetailPane` as small `StatefulWidget`s.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd example && flutter test test/native_macos_sidebar_demo_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze**

Run: `cd example && dart analyze lib/native_macos_sidebar_demo.dart test/native_macos_sidebar_demo_test.dart`
Expected: No issues. (Run `dart format .` from repo root if needed.)

- [ ] **Step 6: Commit**

```bash
git add example/lib/native_macos_sidebar_demo.dart example/test/native_macos_sidebar_demo_test.dart
git commit -m "feat(example): add native macOS splitter demo screen"
```

---

### Task 3: Wire the gallery entry + launcher

**Files:**
- Modify: `example/lib/main.dart` (the `_baseDemos` list near line 72, plus a new launcher widget)
- Test: `example/test/native_macos_sidebar_demo_test.dart` (add a launch-flow test)

**Interfaces:**
- Consumes: `NativeMacosSplitterDemo` from Task 2.
- Produces: a gallery demo titled "Native macOS" whose pane is a launcher.

- [ ] **Step 1: Write the failing test** (append to the existing test file `main`):

```dart
  testWidgets('gallery lists Native macOS entry and launches the screen',
      (tester) async {
    await tester.pumpWidget(const ResizableSplitterExampleApp());
    await tester.pumpAndSettle();

    final navEntry = find.text('Native macOS');
    expect(navEntry, findsOneWidget);

    await tester.tap(navEntry);
    await tester.pumpAndSettle();

    final launchButton = find.widgetWithText(PushButton, 'Open full-screen demo');
    expect(launchButton, findsOneWidget);

    await tester.tap(launchButton);
    await tester.pumpAndSettle();

    expect(find.byType(NativeMacosSplitterDemo), findsOneWidget);
  });
```

Add the import at the top of the test file:
```dart
import 'package:resizable_splitter_example/main.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd example && flutter test test/native_macos_sidebar_demo_test.dart -k 'gallery lists'` (or run the whole file)
Expected: FAIL - no "Native macOS" entry.

- [ ] **Step 3: Implement** in `example/lib/main.dart`:

Add the import:
```dart
import 'package:resizable_splitter_example/native_macos_sidebar_demo.dart';
```

Append to `_baseDemos`:
```dart
    _Demo(
      title: 'Native macOS',
      subtitle: 'macos_ui chrome with our splitter + StickySnap',
      builder: (context) => const _NativeMacosLauncher(),
    ),
```

Add a launcher widget (near `_NavigationPane`):
```dart
class _NativeMacosLauncher extends StatelessWidget {
  const _NativeMacosLauncher();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Native macOS demo', style: textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'Opens a full-screen macos_ui window where ResizableSplitter drives '
              'the sidebar with sticky pixel detents and a collapsible pane.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const NativeMacosSplitterDemo(),
                ),
              ),
              child: const Text('Open full-screen demo'),
            ),
          ],
        ),
      ),
    );
  }
}
```

NOTE: the test in Step 1 looks for a `PushButton` (macos_ui). The launcher lives in the Material gallery, so use a Material `FilledButton` and update the Step-1 finder to `find.widgetWithText(FilledButton, 'Open full-screen demo')` before running. (Decision: keep the gallery Material; macos_ui buttons belong only inside the native route.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd example && flutter test test/native_macos_sidebar_demo_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Analyze**

Run: `cd example && dart analyze lib/main.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add example/lib/main.dart example/test/native_macos_sidebar_demo_test.dart
git commit -m "feat(example): add Native macOS gallery entry + launcher"
```

---

### Task 4: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole example**

Run: `cd example && dart analyze`
Expected: No issues. (From repo root, `dart format .` if any file needs formatting, then re-commit.)

- [ ] **Step 2: Run the full example test suite**

Run: `cd example && flutter test`
Expected: All tests pass.

- [ ] **Step 3: (macOS) Smoke-run the app** if a macOS toolchain is available

Run: `cd example && flutter run -d macos` then open the "Native macOS" entry and the full-screen demo; drag the divider (feel the sticky detents), toggle collapse, toggle appearance.
Expected: native-looking window, splitter resizes, detents engage, collapse + theme toggles work.

- [ ] **Step 4: Final commit** (only if formatting or fixes were needed)

```bash
git add -A
git commit -m "chore(example): formatting and verification fixes"
```

---

## Self-Review

- **Spec coverage:** entry+launcher (Task 3) = spec B/A; native skeleton + splitter + panes + detents + light/dark (Task 2) = spec sections C-F; dependency (Task 1) = spec "files changed"; tests (Tasks 2-4) = spec "Testing and verification". Covered.
- **Placeholder scan:** pane content is intentionally minimal per spec non-goals; all test code is complete; no TBDs.
- **Type consistency:** `NativeMacosSplitterDemo({controller})`, `macosSidebarDetentFractions(double)`, `SplitterPane.start`, `controller.toggleCollapse`, `controller.collapsedPane`, `SplitterPosition.startPixels`, `SplitterPaneConstraints(minExtent/maxExtent/collapsedExtent)`, `SplitterSnapBehavior.sticky(points/pixelTolerance)` - all verified against source.
- **Known cross-task fix:** Task 3 Step 1 test references `PushButton`; Step 3 NOTE corrects it to `FilledButton`. Apply the corrected finder.
