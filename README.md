# Resizable Splitter

<p align="center">
  <img src="https://github.com/omar-hanafy/resizable_splitter/blob/main/screenshots/1.gif?raw=true" alt="Resizable Splitter demo" width="90%">
</p>

A two-pane, drag-to-resize split view for Flutter that stays correct under the
hard cases: cramped and tiny layouts, RTL, transforms, pixel-pinned sidebars, and
embedded platform views. Every interaction - drag, keyboard, snap, screen reader -
runs through one pure constraint solver, so the stored position can never disagree
with what is drawn.

## Live demo

Try it in the browser: [resizable-splitter demo](https://omar-hanafy.github.io/resizable-splitter/)

## Features

- One solver drives layout, drag, keyboard, snapping, and semantics, so callbacks
  are honest (no drag dead zone, no stored-vs-visible drift).
- A sealed `SplitterPosition`: size a pane by `fraction`, or pin it to a pixel
  width (`startPixels` / `endPixels`) that survives container resizes.
- Per-pane constraints (`minExtent`, `maxExtent`, collapse) and a tie-break
  `constraintPolicy` for cramped layouts.
- Collapse / expand with automatic restore, opt-in state restoration, and a
  deferred-resize mode for expensive panes.
- Keyboard (Arrow / Page / Home / End), slider semantics, RTL, and haptics.
- Shields embedded platform views (WebView, Maps, video) during a drag, with a
  customizable barrier.
- Theme once via `ResizableSplitterTheme` or a `ThemeExtension`; every field is
  nullable, so partial overrides never clobber a broader scope.

## Install

```yaml
dependencies:
  resizable_splitter: ^2.0.0
```

```bash
flutter pub get
```

> Upgrading from 1.x? See [Migrating from 1.x](#migrating-from-1x).

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResizableSplitter(
        start: const Center(child: Text('Navigation')),
        end: const Center(child: Text('Content')),
        onChanged: (details) => debugPrint('ratio: ${details.effectiveFraction}'),
      ),
    );
  }
}
```

## The position model

A `SplitterPosition` describes where the divider is *wanted*; the solver derives
where it actually lands for the current layout.

```dart
// A ratio of the available space (the default).
const SplitterPosition.fraction(0.5);

// Pin the start pane to 280px - it keeps that width as the window grows.
const SplitterPosition.startPixels(280);

// Pin the end pane (e.g. a fixed inspector) to 320px.
const SplitterPosition.endPixels(320);
```

`controller.value` holds the request as an atomic `SplitterState` (the requested
`SplitterPosition` plus any collapsed pane). Read the request with
`controller.position` and the on-screen ratio with `controller.effectiveFraction`.
The resolved on-screen geometry is a separate observable, `controller.layout`
(a `SplitterLayout?`), with `controller.layoutListenable` for changes the request
alone does not signal - such as a pixel pin's fraction shifting as the container
resizes.

## Controller

```dart
final controller = SplitterController(
  initialPosition: const SplitterPosition.startPixels(280), // pinned sidebar
);

controller.isDraggingListenable.addListener(() {
  if (controller.isDragging) debugPrint('drag started');
});

controller.updateRatio(0.4);                  // clamp to [0,1] with a threshold
controller.jumpTo(const SplitterPosition.fraction(0.6)); // set the request
controller.reset();                           // back to 0.5
await controller.animateTo(0.8);              // vsync animation; cancels on drag

controller.collapse(SplitterPane.start);      // shrink the start pane
controller.expand();                          // restore the prior position

// controller.value is the atomic request (a SplitterState). Track the resolved
// on-screen geometry separately - it changes on resize even when the request
// does not:
controller.layoutListenable.addListener(() {
  debugPrint('on-screen ratio: ${controller.layout?.effectiveFraction}');
});
```

Provide a `controller` to persist or drive the position, or omit it and let the
splitter manage one internally. Set the position with `jumpTo` (or `updateRatio`
/ `reset` / `animateTo`); assigning `controller.value` directly takes a full
`SplitterState`.

## Constraints and policy

```dart
ResizableSplitter(
  startConstraints: const SplitterPaneConstraints(minExtent: 180, maxExtent: 480),
  endConstraints: const SplitterPaneConstraints(minExtent: 120),
  minStartFraction: 0.1,   // fractional caps on the start pane
  maxStartFraction: 0.9,
  // When both minimums cannot fit, decide who keeps theirs:
  constraintPolicy: SplitterConstraintPolicy.proportional,
  start: const LeftPane(),
  end: const RightPane(),
);
```

`SplitterConstraintPolicy` is `favorStart`, `favorEnd`, or `proportional`, and
only applies when the layout is too small to honor both minimums.

## Snapping

```dart
ResizableSplitter(
  snap: const SplitterSnapBehavior(
    points: [0.25, 0.5, 0.75],
    tolerance: 0.03,        // distance in ratio space
    // pixelTolerance: 16,  // or a size-independent distance in logical pixels
  ),
  onChangeEnd: (d) {
    if (d.source == SplitterChangeSource.snap) debugPrint('snapped to ${d.effectiveFraction}');
  },
  start: const LeftPane(),
  end: const RightPane(),
);
```

## Collapse and expand

`controller.collapse(...)` shrinks a pane to its `collapsedExtent` (bypassing its
minimum) and remembers the position so `expand()` restores it.

```dart
final controller = SplitterController();

ResizableSplitter(
  controller: controller,
  startConstraints: const SplitterPaneConstraints(
    minExtent: 200,
    collapsible: true,
    collapsedExtent: 0,
  ),
  start: const Sidebar(),
  end: const Content(),
);

IconButton(
  onPressed: () => controller.toggleCollapse(SplitterPane.start),
  icon: const Icon(Icons.menu_open),
);
```

## State restoration

Persist the divider position across app restarts with a `restorationId` (works
with the internal controller too):

```dart
MaterialApp(
  restorationScopeId: 'app',
  home: const ResizableSplitter(
    restorationId: 'editor-split',
    start: Sidebar(),
    end: Content(),
  ),
);
```

## Deferred resize

For panes with expensive subtrees, defer the resize until the drag is released - a
lightweight preview line tracks the pointer while the panes hold their size:

```dart
ResizableSplitter(
  deferredResize: true,
  start: const ExpensiveTree(),
  end: const ExpensiveTree(),
);
```

## Change details

`onChanged` / `onChangeStart` / `onChangeEnd` deliver a `SplitterChangeDetails`:
the request, the resolved `effectiveFraction`, both pane extents, the available
extent, and the `SplitterChangeSource` (`drag`, `keyboard`, `semantics`,
`programmatic`, `snap`, `collapse`, `restore`).

```dart
ResizableSplitter(
  onChanged: (d) => save(d.effectiveFraction),
  onChangeEnd: (d) => debugPrint('${d.source}: ${d.startExtent} | ${d.endExtent}'),
  start: const LeftPane(),
  end: const RightPane(),
);
```

## Divider styling

Group divider appearance and grab configuration under `divider`. The color is a
`WidgetStateProperty<Color?>`, resolved against `hovered` and `dragged`:

```dart
ResizableSplitter(
  divider: SplitterDividerStyle(
    thickness: 8,
    hitSlop: 6, // enlarge the grab target without widening the bar
    color: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.dragged)) return Colors.blue;
      if (states.contains(WidgetState.hovered)) return Colors.blueGrey;
      return Colors.grey.shade300;
    }),
    builder: (context, details) => Center(
      child: Icon(
        details.axis == Axis.horizontal ? Icons.drag_handle : Icons.drag_indicator,
        size: 16,
      ),
    ),
  ),
  start: const LeftPane(),
  end: const RightPane(),
);
```

## Theming

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    divider: SplitterDividerStyle(thickness: 8),
    overlayEnabled: false,
    keyboardStep: 0.02,
  ),
  child: const ResizableSplitter(start: NavPane(), end: ContentPane()),
);
```

For app-wide defaults, register the same type as a `ThemeExtension`:

```dart
ThemeData.light().copyWith(
  extensions: const [
    ResizableSplitterThemeData(
      divider: SplitterDividerStyle(thickness: 6),
      pageStep: 0.1,
    ),
  ],
);
```

Precedence (highest first): widget arguments -> `ResizableSplitterTheme` ->
`ThemeData.extension<ResizableSplitterThemeData>()` -> built-in defaults. Because
every field is nullable, a more specific scope only overrides the fields it sets.

## Unbounded constraints

Inside an unbounded constraint (e.g. `UnconstrainedBox`) the splitter cannot size
the handle, so it shows the panes without a divider. Opt into a finite sandbox:

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    unboundedBehavior: UnboundedBehavior.limitedBox,
    fallbackMainAxisExtent: 420,
  ),
  child: const ResizableSplitter(start: LeftPane(), end: RightPane()),
);
```

## Platform views

A drag inserts an invisible shield over the tree so embedded platform views
(WebView, Maps, video) cannot steal the pointer. Tune it with `overlayEnabled`,
`blockerColor`, or a custom `dragBarrierBuilder`.

## Migrating from 1.x

| 1.x | 2.0 |
| --- | --- |
| `initialRatio: 0.5` | `initialPosition: SplitterPosition.fraction(0.5)` |
| `controller.value = 0.6` *(double)* | `controller.jumpTo(SplitterPosition.fraction(0.6))` |
| `controller.value` *(read, double)* | `controller.position` *(SplitterPosition)* / `controller.effectiveFraction` *(double)*; `controller.value` is now a `SplitterState` |
| `dividerThickness`, `dividerColor`, `dividerHoverColor`, `dividerActiveColor`, `handleHitSlop`, `handleBuilder` | `divider: SplitterDividerStyle(thickness, color, hitSlop, builder)` |
| `minPanelSize`, `minStartPanelSize`, `minEndPanelSize` | `startConstraints` / `endConstraints: SplitterPaneConstraints(minExtent: ...)` |
| `minRatio`, `maxRatio` | `minStartFraction`, `maxStartFraction` |
| `snapPoints`, `snapTolerance` | `snap: SplitterSnapBehavior(points, tolerance, pixelTolerance)` |
| `onRatioChanged`, `onDragStart`, `onDragEnd` *(double)* | `onChanged`, `onChangeStart`, `onChangeEnd` *(SplitterChangeDetails)* |
| `crampedBehavior: CrampedBehavior` | `constraintPolicy: SplitterConstraintPolicy` |
| `ResizableSplitterThemeOverrides` | `ResizableSplitterThemeData` (the single `ThemeExtension`) |
| `animateTo(..., frames: 12)` | `animateTo(...)` (vsync-driven) |

## Example app

An end-to-end demo lives under [`example/`](example/):

```bash
cd example
flutter run
```

## Testing

```bash
flutter test
```

## License

Resizable Splitter is available under the [MIT License](LICENSE).
