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
- Accessible by default: a 48px touch target, a keyboard focus ring, slider
  semantics with bounds-aware actions, localizable labels, RTL, and haptics.
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
  // When both minimums cannot fit (a shortage), decide who keeps theirs:
  constraintPolicy: SplitterConstraintPolicy.proportional,
  // When both maximums cannot fill (a surplus), decide what fills the slack.
  // The default, leaveGap, keeps both at their max and leaves a gap between them.
  surplusPolicy: SplitterSurplusPolicy.leaveGap,
  start: const LeftPane(),
  end: const RightPane(),
);
```

`SplitterConstraintPolicy` (`favorStart` / `favorEnd` / `proportional`) only
applies in a **shortage** - the layout is too small to honor both minimums.
`SplitterSurplusPolicy` (`giveToStart` / `giveToEnd` / `proportional` /
`leaveGap`) is its counterpart for a **surplus** - both panes have a `maxExtent`
whose sum is below the available space. It defaults to `leaveGap`, which keeps
both at their max (so `maxExtent` is a true maximum) and leaves the remainder as
a gap between them. Pixel `minExtent` / `maxExtent` are hard limits: they always
win over `minStartFraction` / `maxStartFraction` when the two disagree.

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

A pane is collapsible when its constraints set a `collapsedExtent` (in
`[0, minExtent]`; null means not collapsible). `controller.collapse(...)` shrinks
that pane to its `collapsedExtent` (bypassing its minimum) and remembers the
position so `expand()` restores it. Collapsing a pane that has no `collapsedExtent`
is a layout no-op; read the resolved state from `controller.layout?.collapsedPane`.

```dart
final controller = SplitterController();

ResizableSplitter(
  controller: controller,
  startConstraints: const SplitterPaneConstraints(
    minExtent: 200,
    collapsedExtent: 0, // set => collapsible (here, collapses fully)
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
`doubleTapReset`, `snap`, `collapse`, `restore`).

These fire for interactions (drag, keyboard, assistive adjust, snap, the
double-tap reset) and `collapse` / `expand`. Direct controller writes
(`jumpTo`, `updateRatio`, `reset`, `animateTo`) and state restoration do **not**
fire them - observe those with the `controller` (request) and
`controller.layoutListenable` (resolved geometry), which avoids feedback loops.

`onChangeStart` and `onChangeEnd` are balanced: every start is followed by
exactly one end. On the end, `details.end` is `SplitterChangeEnd.committed` for a
normal release or `SplitterChangeEnd.canceled` for a system cancel (nothing is
committed), so a "dragging" flag toggled on start always clears on the end.

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
`WidgetStateProperty<Color?>`, resolved against `hovered`, `focused`, and
`dragged`:

```dart
ResizableSplitter(
  divider: SplitterDividerStyle(
    thickness: 8,
    interactiveExtent: 48, // grab target across the bar (defaults to 48); the
                           // extra width overlays the panes without resizing them
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
    shieldPlatformViews: false,
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

## Accessibility

The divider is a first-class control out of the box:

- **Touch target.** The grab region defaults to a 48px `interactiveExtent` (the
  Material minimum), independent of the thin visible `thickness`. The extra width
  overlays the panes from on top, so it never changes their layout, and a
  non-resizable divider collapses the target to its thickness so it can't steal
  pane hits.
- **Keyboard + focus.** Tab to the divider and use the arrow keys (Page keys for
  larger steps, Home/End to jump to the bounds). A focused divider shows a focus
  ring; a custom `WidgetStateProperty` colour can also resolve `WidgetState.focused`,
  and a custom grip `builder` receives `details.isFocused`.
- **Screen readers.** The divider is exposed as a slider with a spoken value.
  Increase/decrease actions are offered only in the direction the divider can
  actually move - a pane pinned at a hard bound drops the unavailable action.
- **Localization.** Override the spoken strings and value format with
  `SplitterSemanticsLabels`, per widget (`semantics:`) or app-wide via the theme.
  `semanticsLabel` remains a quick single-string label override.

```dart
MaterialApp(
  theme: ThemeData.light().copyWith(
    extensions: const [
      ResizableSplitterThemeData(
        semantics: SplitterSemanticsLabels(
          resizeHorizontal: 'Redimensionner les panneaux',
          // formatValue defaults to a whole percentage.
        ),
      ),
    ],
  ),
  // ...
);
```

`onChangeStart` / `onChangeEnd` are balanced (every start gets exactly one end),
and the end's `SplitterChangeDetails.end` distinguishes a committed release from a
cancel - see [Change details](#change-details).

## Unbounded constraints

Inside an unbounded constraint (e.g. `UnconstrainedBox`) the splitter cannot size
the handle, so it shows the panes without a divider. Opt into a finite sandbox:

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    unboundedBehavior: UnboundedBehavior.useFallbackExtent,
    fallbackExtent: 420,
  ),
  child: const ResizableSplitter(start: LeftPane(), end: RightPane()),
);
```

## Platform views

A drag inserts an invisible shield over the tree so embedded platform views
(WebView, Maps, video) cannot steal the pointer. Tune it with
`shieldPlatformViews`, `dragBarrierColor`, or a custom `dragBarrierBuilder`.

## Migrating from 1.x

| 1.x | 2.0 |
| --- | --- |
| `initialRatio: 0.5` | `initialPosition: SplitterPosition.fraction(0.5)` |
| `controller.value = 0.6` *(double)* | `controller.jumpTo(SplitterPosition.fraction(0.6))` |
| `controller.value` *(read, double)* | `controller.position` *(SplitterPosition)* / `controller.effectiveFraction` *(double)*; `controller.value` is now a `SplitterState` |
| `dividerThickness`, `dividerColor`, `dividerHoverColor`, `dividerActiveColor`, `handleHitSlop`, `handleBuilder` | `divider: SplitterDividerStyle(thickness, color, interactiveExtent, builder)` (`interactiveExtent` is the total grab target, default 48; replaces the additive `handleHitSlop`) |
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
