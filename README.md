# Resizable Splitter

<p align="center">
  <img src="https://github.com/omar-hanafy/resizable_splitter/blob/main/screenshots/1.gif?raw=true" alt="Resizable Splitter demo" width="90%">
</p>

Flutter widget for building drag-to-resize layouts that feel native on every platform. Resizable Splitter focuses on fluid pointer gestures, keyboard accessibility, and easy customization.

## Live Demo

Test it in the browser: [resizable-splitter demo](https://omar-hanafy.github.io/resizable-splitter/)

## Features

- Global pointer routing keeps drags alive even when platform views (WebView, Maps, video) try to steal focus; enable/disable with `overlayEnabled` and `blockerColor`.
- Built-in snapping via `snapPoints` + `snapTolerance`, so handles land exactly on your breakpoints.
- First-class keyboard support (Arrow/Page/Home/End) with semantics describing the current ratio, next/previous values, and how to interact.
- Flexible layout constraints: `minRatio`, asymmetric `minStartPanelSize`/`minEndPanelSize`, and a safe default `minPanelSize` fallback.
- Theme once, reuse everywhere via `ResizableSplitterTheme` or the `ResizableSplitterThemeOverrides` `ThemeExtension`.
- Opt-in policies for unbounded layouts (`UnboundedBehavior` + `fallbackMainAxisExtent`), anti-aliasing, and cramped minima (`CrampedBehavior`).

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  resizable_splitter: ^1.1.1
```

Then fetch packages:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResizableSplitter(
        axis: Axis.horizontal,
        startPanel: const Center(child: Text('Navigation')),
        endPanel: const Center(child: Text('Content')),
        dividerThickness: 8,
        onRatioChanged: (ratio) => debugPrint('ratio: $ratio'),
      ),
    );
  }
}
```

## Advanced Example

```dart
final controller = SplitterController(initialRatio: 0.6);

ResizableSplitter(
  axis: Axis.horizontal,
  controller: controller,
  dividerThickness: 6,
  minStartPanelSize: 180,
  minEndPanelSize: 120,
  snapPoints: const [0.25, 0.5, 0.75],
  snapTolerance: 0.03,
  overlayEnabled: true,
  blockerColor: Colors.black.withOpacity(0.05),
  handleBuilder: (context, details) => Center(
    child: Container(
      width: details.axis == Axis.horizontal ? 2 : 24,
      height: details.axis == Axis.horizontal ? 24 : 2,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(90),
        borderRadius: BorderRadius.circular(1),
      ),
    ),
  ),
  onRatioChanged: (ratio) => debugPrint('ratio=$ratio'),
  startPanel: const YourMainPane(),
  endPanel: const YourSidebar(),
);
```

## API Quick Reference

### SplitterController

```dart
final controller = SplitterController(initialRatio: 0.6); // start 60/40

controller.isDraggingListenable.addListener(() {
  if (controller.isDragging) {
    debugPrint('user started dragging');
  }
});

controller.updateRatio(0.4); // clamp to 0-1 with a noise threshold
controller.reset(); // jump back to 0.5
await controller.animateTo(
  0.8,
  duration: const Duration(milliseconds: 180),
  curve: Curves.easeOut,
  frames: 12,
); // simple animation without a ticker
```

### ResizableSplitter options

```dart
ResizableSplitter(
  startPanel: const NavigationPane(), // required left/top child
  endPanel: const ContentPane(),      // required right/bottom child
  controller: controller,             // reuse to persist ratios
  axis: Axis.horizontal,              // Axis.vertical for top/bottom split
  initialRatio: 0.5,                  // used only when controller is null
  minRatio: 0.1,                      // clamp lower bound (0-1)
  maxRatio: 0.9,                      // clamp upper bound (0-1)
  minPanelSize: 120,                  // default pixel minimum for both panels
  minStartPanelSize: 180,             // specific pixel minimum for start pane
  minEndPanelSize: 140,               // specific pixel minimum for end pane
  dividerThickness: 6,                // drag handle width/height in px
  dividerColor: Colors.grey,          // idle divider color
  dividerHoverColor: Colors.grey.shade700, // pointer hover color
  dividerActiveColor: Colors.blue,    // active drag color
  onRatioChanged: (ratio) => save(ratio), // fires on every update
  onDragStart: (ratio) => pauseWork(),    // first pointer down
  onDragEnd: (ratio) => resumeWork(),     // pointer up (after snapping)
  enableKeyboard: true,                // arrow/page/home/end shortcuts
  keyboardStep: 0.02,                  // arrow key delta (2%)
  pageStep: 0.15,                      // page key delta (15%)
  semanticsLabel: 'Resize panels',     // screen-reader label
  blockerColor: Colors.black12,        // overlay tint during drag
  overlayEnabled: true,                // shield platform views
  unboundedBehavior: UnboundedBehavior.flexExpand, // LimitedBox fallback via .limitedBox
  fallbackMainAxisExtent: 420,        // used when unboundedBehavior == limitedBox
  antiAliasingWorkaround: false,      // floor start panel to whole pixels
  crampedBehavior: CrampedBehavior.favorStart, // pick who keeps their minimum first
  snapPoints: const [0.25, 0.5, 0.75], // optional ratio targets
  snapTolerance: 0.03,                 // how close before snapping
  resizable: true,                     // disable to render a static divider
  onHandleTap: () => logTap(),         // tap without dragging
  onHandleDoubleTap: () => logDoubleTap(), // fires before optional reset
  doubleTapResetTo: 0.5,               // animate back to mid on double tap
  handleBuilder: (context, details) {
    final color = details.isDragging ? Colors.blue : Colors.grey;
    return Center(
      child: Container(
        width: details.axis == Axis.horizontal ? 2 : details.thickness - 2,
        height: details.axis == Axis.horizontal ? details.thickness - 2 : 2,
        color: color,
      ),
    );
  },
);
```

### SplitterHandleDetails

```dart
handleBuilder: (context, details) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: details.isHovering ? Colors.white24 : Colors.white10,
      borderRadius: BorderRadius.circular(details.thickness / 3),
    ),
    child: SizedBox.expand(
      child: Icon(
        details.axis == Axis.horizontal ? Icons.drag_indicator : Icons.more_vert,
        color: details.isDragging ? Colors.blue : Colors.white54,
      ),
    ),
  );
};
```

Callbacks receive the live ratio so you can store it, pause work, or react to snapping. Keyboard shortcuts honor `enableKeyboard`, `keyboardStep`, and `pageStep`, and semantics read out `semanticsLabel` plus the percentage.

## Theming

Wrap a subtree with `ResizableSplitterTheme` when you want bespoke styling:

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    dividerThickness: 8,
    dividerHoverColor: Colors.indigoAccent,
    overlayEnabled: false,
    unboundedBehavior: UnboundedBehavior.limitedBox,
    fallbackMainAxisExtent: 360,
  ),
  child: const ResizableSplitter(
    startPanel: NavPane(),
    endPanel: ContentPane(),
  ),
);
```

For app-wide overrides hook into Material theming via the provided `ThemeExtension`:

```dart
final theme = ThemeData.light().copyWith(
  extensions: const [
    ResizableSplitterThemeOverrides(
      keyboardStep: 0.2,
      pageStep: 0.4,
      handleHitSlop: 8,
      overlayEnabled: false,
    ),
  ],
);

return MaterialApp(theme: theme, home: const SplitterShowcase());
```

Precedence: explicit widget parameters → `ResizableSplitterTheme` → `ThemeData.extension<ResizableSplitterThemeOverrides>()` → derived Material defaults.

## Unbounded constraints

If your splitter lives inside an unbounded constraint (e.g. `UnconstrainedBox`), opt into the `LimitedBox` fallback:

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    unboundedBehavior: UnboundedBehavior.limitedBox,
    fallbackMainAxisExtent: 420,
  ),
  child: const ResizableSplitter(
    startPanel: LeftPane(),
    endPanel: RightPane(),
  ),
);
```

The legacy `flexExpand` behavior is still the default so existing layouts keep working.

## Example App

An end-to-end demo lives under [`example/`](example/). It showcases persistence, snapping, asymmetric minimums, and custom handles. Run it locally:

```bash
cd example
flutter run
```

## Testing

Widget and controller tests live under `test/`. Run them all:

```bash
flutter test
```

Core scenarios include controller thresholds, drag snapping, keyboard shortcuts, layout constraints, and semantics coverage.

## License

Resizable Splitter is available under the [MIT License](LICENSE).
