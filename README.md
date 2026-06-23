# Resizable Splitter

[![pub package](https://img.shields.io/pub/v/resizable_splitter.svg)](https://pub.dev/packages/resizable_splitter)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="https://github.com/omar-hanafy/resizable_splitter/blob/main/assets/workspace.png?raw=true" alt="The resizable_splitter showcase - an editor workspace built entirely out of the package" width="100%">
</p>

<p align="center"><em>The interactive showcase, built entirely out of the package.</em></p>

A two-pane, drag-to-resize split view for Flutter that stays correct under the
hard cases: cramped and tiny layouts, right-to-left, `Transform`, pixel-pinned
sidebars, and embedded platform views. Drag, keyboard, snapping, and screen
readers all flow through **one pure constraint solver**, so the position you
store can never disagree with the pixels that get drawn.

**[Live demo](https://omar-hanafy.github.io/resizable-splitter/)** - try it in
your browser.

<p align="center">
  <img src="https://github.com/omar-hanafy/resizable_splitter/blob/main/screenshots/1.gif?raw=true" alt="Resizable Splitter drag demo" width="90%">
</p>

## Contents

- [Why this splitter](#why-this-splitter)
- [Features](#features)
- [Install](#install)
- [Quick start](#quick-start)
- [The mental model: request vs. result](#the-mental-model-request-vs-result)
- [Controller](#controller)
- [Constraints and policies](#constraints-and-policies)
- [Snapping](#snapping)
- [Collapse and expand](#collapse-and-expand)
- [Deferred resize](#deferred-resize)
- [State restoration](#state-restoration)
- [Change callbacks](#change-callbacks)
- [Divider styling](#divider-styling)
- [Theming](#theming)
- [Accessibility](#accessibility)
- [Platform views](#platform-views)
- [Unbounded constraints and intrinsic sizing](#unbounded-constraints-and-intrinsic-sizing)
- [API cheat sheet](#api-cheat-sheet)
- [Migrating from 1.x](#migrating-from-1x)
- [Example app](#example-app)
- [Testing](#testing)
- [License](#license)

## Why this splitter

Most split views store a number (a ratio, or a pixel width) and hope it matches
what ends up on screen. The moment a constraint bites - a pane hits its minimum,
the window gets too small, a sidebar is pinned to a fixed width - the stored
value and the visible layout drift apart. Callbacks lie, drags develop dead
zones, and "collapsed" can quietly disagree with "shown".

Resizable Splitter is built around a single idea: **store the intent, resolve it
every frame.** A `SplitterPosition` is what you *want* (a fraction or a pixel
pin). A pure solver turns that intent into the on-screen geometry against the
real constraints, in the layout pass, in a dedicated `RenderObject`. Every
interaction reads and writes the *effective* position, so:

- callbacks report what is actually drawn, not a stale request;
- there is no drag dead zone and no cramped-layout crash;
- a pixel-pinned sidebar keeps its width as the window grows;
- collapse is part of the atomic value, so it can never silently desync.

## Features

- **One solver, everywhere.** Drag, keyboard, snapping, the double-tap reset,
  and assistive adjustments all run through the same constraint solver.
- **A sealed position model.** Size a pane by `fraction`, or pin it to a pixel
  width (`startPixels` / `endPixels`) that survives container resizes.
- **Per-pane constraints.** `minExtent`, `maxExtent`, and collapse, plus a
  `constraintPolicy` (shortage) and `surplusPolicy` (surplus) for layouts that
  cannot honor every limit at once.
- **Collapse / expand** with automatic restore, opt-in state restoration, and a
  deferred-resize mode for expensive pane subtrees.
- **Three snap modes.** Settle on release, pull magnetically during the drag, or
  capture stickily with hysteresis.
- **Accessible by default.** A 48px touch target, a keyboard focus ring, slider
  semantics with bounds-aware actions, localizable labels, RTL, and haptics.
- **Platform-view safe.** A drag shields embedded WebViews, maps, and video from
  stealing the pointer, with a customizable barrier.
- **Intrinsic sizing.** Backed by a real `RenderObject`, so it sizes correctly
  under `IntrinsicWidth` / `IntrinsicHeight` and supports dry layout.
- **Composable theming.** One nullable `ResizableSplitterThemeData` works as both
  a `ThemeExtension` and a scoped theme; partial overrides never clobber a
  broader scope.

## Install

```yaml
dependencies:
  resizable_splitter: ^2.0.0
```

```bash
flutter pub get
```

Requires Dart `>=3.9.2` and Flutter `>=3.35.0`.

> Upgrading from 1.x? Jump to [Migrating from 1.x](#migrating-from-1x).

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

That is the whole minimum: two panes and an optional callback. The divider
starts centered, is keyboard-focusable, exposes slider semantics, and shields
platform views during a drag - all with no extra configuration.

## The mental model: request vs. result

This is the one concept worth internalizing; everything else follows from it.

**The request** is a `SplitterPosition` - where the divider is *wanted*,
independent of the current layout:

```dart
// A ratio of the available space (the default).
const SplitterPosition.fraction(0.5);

// Pin the start pane to 280px - it keeps that width as the window grows.
const SplitterPosition.startPixels(280);

// Pin the end pane (e.g. a fixed inspector) to 320px.
const SplitterPosition.endPixels(320);
```

The controller's `value` is an atomic `SplitterState` - the requested
`SplitterPosition` plus which pane (if any) is collapsed. Bundling them makes a
desynced controller unrepresentable.

**The result** is a `SplitterLayout` - the resolved on-screen geometry after the
solver clamps the request against the pane constraints and available space. It
carries the effective fraction, both pane extents, the available extent, the
legal `[minStartExtent, maxStartExtent]` band with derived `canIncrease` /
`canDecrease`, a `resolution`, and the resolved `collapsedPane`.

The result is published **separately** from the request, because the on-screen
geometry can change without the request changing - a pixel-pinned pane's
fraction shifts whenever the container resizes. Track each on its own channel:

| You want to observe | Listen to |
| --- | --- |
| The intent (fraction / pixel pin, collapse) | `controller` (it is a `ValueListenable<SplitterState>`) |
| The resolved on-screen geometry | `controller.layoutListenable` (a `SplitterLayout?`) |
| Just the current on-screen ratio | `controller.effectiveFraction` |

`controller.layout` is `null` before the first layout pass and while detached -
it never pretends a pixel request already has a fraction.

## Controller

Provide a `controller` to drive or persist the position, or omit it and let the
splitter manage one internally.

```dart
final controller = SplitterController(
  initialPosition: const SplitterPosition.startPixels(280), // a pinned sidebar
);

// Read the request and the resolved geometry.
controller.position;          // the requested SplitterPosition
controller.effectiveFraction; // the on-screen start ratio in [0, 1]
controller.layout;            // the resolved SplitterLayout? (null until laid out)

// Set the position.
controller.jumpTo(const SplitterPosition.fraction(0.6)); // fresh intent
controller.updateRatio(0.4);  // clamp to [0, 1] with a chatty-update threshold
controller.reset();           // back to 0.5
await controller.animateTo(0.8); // vsync animation; returns how the run ended

// Collapse.
controller.collapse(SplitterPane.start);
controller.toggleCollapse(SplitterPane.end);
controller.expand();          // restore the position held before collapsing

// Observe.
controller.isDraggingListenable.addListener(() {
  if (controller.isDragging) debugPrint('drag started');
});
controller.layoutListenable.addListener(() {
  debugPrint('on-screen ratio: ${controller.layout?.effectiveFraction}');
});
```

`animateTo` is driven by the attached view's vsync, so it honors the platform
refresh rate and `MediaQuery.disableAnimations`. Its future resolves with a
`SplitterAnimationStatus` - `completed`, `canceled` (a drag / key / write
superseded it), or `detached` (the splitter was disposed or its controller
swapped) - so you can tell a real arrival from an interruption. A drag, key
press, reset, or direct value write cancels a run in progress.

Set the position with `jumpTo` / `updateRatio` / `reset` / `animateTo`;
assigning `controller.value` directly takes a full `SplitterState`.

## Constraints and policies

```dart
ResizableSplitter(
  startConstraints: const SplitterPaneConstraints(minExtent: 180, maxExtent: 480),
  endConstraints: const SplitterPaneConstraints(minExtent: 120),
  minStartFraction: 0.1,   // fractional caps on the start pane
  maxStartFraction: 0.9,
  // Shortage: both minimums cannot fit. Decide who keeps theirs.
  constraintPolicy: SplitterConstraintPolicy.proportional,
  // Surplus: both maximums cannot fill. Decide what takes the slack.
  surplusPolicy: SplitterSurplusPolicy.leaveGap,
  start: const LeftPane(),
  end: const RightPane(),
);
```

Two policies cover the two ways constraints can conflict:

- **`SplitterConstraintPolicy`** (`favorStart` - the default, `favorEnd`,
  `proportional`) only applies in a **shortage**: the layout is too small to
  honor both minimums (`start.min + end.min > available`).
- **`SplitterSurplusPolicy`** (`giveToStart`, `giveToEnd`, `proportional`,
  `leaveGap` - the default) only applies in a **surplus**: both panes have a
  finite `maxExtent` whose sum is below the available space. `leaveGap` keeps
  both at their max (so `maxExtent` is a true maximum) and renders the remainder
  as a gap between the panes, rather than overflowing one past its max.

Pixel `minExtent` / `maxExtent` are **hard** limits: they always win over the
fractional `minStartFraction` / `maxStartFraction` caps when the two disagree.
When the fractional caps would empty an otherwise feasible pixel band, the pixel
limits win and `SplitterLayout.resolution` reports `fractionConflict`.

> Pane constraints default to `minExtent: 100` on the widget (a sensible floor
> for real panes), even though a bare `SplitterPaneConstraints()` defaults to
> `0`.

## Snapping

Snap points are start fractions in `[0, 1]`, matched in **effective** space (so
a point a constraint pushes aside is measured by where it actually lands).
`SplitterSnapBehavior` is a sealed type with three modes:

```dart
// Release snap (the default): settle onto the nearest point when the drag ends.
SplitterSnapBehavior(points: [0.25, 0.5, 0.75], tolerance: 0.03);

// Magnetic: pull toward a point during the drag; can always be pushed through.
SplitterSnapBehavior.magnetic(points: [0.5], tolerance: 0.06, strength: 0.5);

// Sticky: capture onto a point and hold until the pointer escapes past
// escapeFactor * tolerance (the hysteresis that prevents flicker).
SplitterSnapBehavior.sticky(points: [0.5], tolerance: 0.02, escapeFactor: 1.5);
```

`tolerance` is a distance in ratio space; set `pixelTolerance` instead for a
size-independent distance in logical pixels (it takes precedence when set). The
unnamed `SplitterSnapBehavior(...)` constructor builds a `ReleaseSnap`, so
existing call sites keep working.

```dart
ResizableSplitter(
  snap: const SplitterSnapBehavior(points: [0.25, 0.5, 0.75], tolerance: 0.03),
  onChangeEnd: (d) {
    if (d.source == SplitterChangeSource.snap) {
      debugPrint('snapped to ${d.effectiveFraction}');
    }
  },
  start: const LeftPane(),
  end: const RightPane(),
);
```

## Collapse and expand

A pane is collapsible when its constraints set a `collapsedExtent` (in
`[0, minExtent]`; `null` means not collapsible). `controller.collapse(...)`
shrinks that pane to its `collapsedExtent` (bypassing its minimum) and remembers
the position, so `expand()` restores it. Collapsing a pane that has no
`collapsedExtent` is a layout no-op - read the resolved state from
`controller.layout?.collapsedPane`.

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

Collapse is part of the atomic `SplitterState`, so collapsing and then writing
an equal value can never desync the controller from the UI. Collapse / expand
emit `collapse` / `restore` change events.

## Deferred resize

For panes with expensive subtrees, defer the resize until the drag is released.
A lightweight preview line tracks the pointer while the panes hold their size,
then settle once on release:

```dart
ResizableSplitter(
  deferredResize: true,
  start: const ExpensiveTree(),
  end: const ExpensiveTree(),
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

## Change callbacks

`onChanged` / `onChangeStart` / `onChangeEnd` deliver a `SplitterChangeDetails`:
the `requestedPosition`, the resolved `effectiveFraction`, both pane extents, the
available extent, and the `SplitterChangeSource`
(`drag`, `keyboard`, `semantics`, `doubleTapReset`, `snap`, `collapse`,
`restore`).

```dart
ResizableSplitter(
  onChanged: (d) => save(d.effectiveFraction),
  onChangeEnd: (d) => debugPrint('${d.source}: ${d.startExtent} | ${d.endExtent}'),
  start: const LeftPane(),
  end: const RightPane(),
);
```

These fire for **interactions** (drag, keyboard, assistive adjust, snap, the
double-tap reset) and for `collapse` / `expand`. Direct controller writes
(`jumpTo`, `updateRatio`, `reset`, `animateTo`) and state restoration do **not**
fire them - observe those through the `controller` (request) and
`controller.layoutListenable` (resolved geometry), which avoids feedback loops.
This mirrors how `Slider.onChanged` reports interaction rather than every write.

`onChangeStart` and `onChangeEnd` are **balanced**: every start is followed by
exactly one end. On the end, `details.end` is `SplitterChangeEnd.committed` for a
normal release (the `source` is `snap` when a snap point claimed it) or
`SplitterChangeEnd.canceled` for a system cancel (nothing committed) - so a
"dragging" flag toggled on start always clears.

## Divider styling

Group divider appearance and grab configuration under `divider`. The color is a
`WidgetStateProperty<Color?>`, resolved against `hovered`, `focused`, and
`dragged`:

```dart
ResizableSplitter(
  divider: SplitterDividerStyle(
    thickness: 8,          // visible bar (defaults to 6)
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

The `builder` receives a `SplitterHandleDetails` with `isDragging`,
`isHovering`, `isFocused`, `axis`, and `thickness` - enough to render any grip
and react to interaction state. (Supplying a builder suppresses the default focus
ring, since the builder owns its own focus visual.)

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
every field is nullable, a more specific scope only overrides the fields it sets,
and nested `ResizableSplitterTheme`s compose instead of replacing one another.

## Accessibility

The divider is a first-class control out of the box:

- **Touch target.** The grab region defaults to a 48px `interactiveExtent` (the
  Material minimum), independent of the thin visible `thickness`. The extra width
  overlays the panes from on top, so it never changes their layout, and a
  non-resizable divider collapses the target to its thickness so it cannot steal
  pane hits.
- **Keyboard and focus.** Tab to the divider and use the arrow keys
  (`keyboardStep`, default 1%), Page keys for larger steps (`pageStep`, default
  10%), and Home / End to jump to the bounds. A focused divider shows a focus
  ring; a custom color resolver can react to `WidgetState.focused`, and a custom
  grip `builder` receives `details.isFocused`.
- **Screen readers.** The divider is exposed as a slider with a spoken value.
  Increase / decrease actions are offered only in the direction it can actually
  move - a pane pinned at a hard bound drops the unavailable action.
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

## Platform views

A drag inserts an invisible shield over the tree so embedded platform views
(WebView, Maps, video) cannot steal the pointer. Tune it with
`shieldPlatformViews`, `dragBarrierColor`, or a custom `dragBarrierBuilder`. The
shield degrades gracefully when there is no `Overlay` ancestor - the drag still
works - and the stuck-drag router is keyed by pointer id, so several splitters
can be dragged independently at once.

## Unbounded constraints and intrinsic sizing

The layout is a dedicated `RenderObject` (not a `LayoutBuilder`), which buys two
things.

**Intrinsic sizing and dry layout.** Place the splitter under `IntrinsicWidth` /
`IntrinsicHeight` (or any parent that queries intrinsics) and it reports a
sensible intrinsic size: along the axis, `start + divider + end`; across it, the
larger pane. A bounded main axis with an unbounded cross axis (a horizontal
splitter in a `Column`, say) sizes to the panes' cross extent instead of
throwing.

**Unbounded main axis.** When the main axis is unbounded the splitter cannot size
the handle, so under the default `UnboundedBehavior.shrinkToChildren` it shows
the two panes without a divider, sized to their content. Opt into a finite
sandbox instead:

```dart
ResizableSplitterTheme(
  data: const ResizableSplitterThemeData(
    unboundedBehavior: UnboundedBehavior.useFallbackExtent,
    fallbackExtent: 420, // defaults to 500
  ),
  child: const ResizableSplitter(start: LeftPane(), end: RightPane()),
);
```

## API cheat sheet

**Widget - `ResizableSplitter`**

| Parameter | Type | Default |
| --- | --- | --- |
| `start`, `end` | `Widget` | required |
| `controller` | `SplitterController?` | internal |
| `axis` | `Axis` | `horizontal` |
| `initialPosition` | `SplitterPosition` | `fraction(0.5)` |
| `startConstraints` / `endConstraints` | `SplitterPaneConstraints` | `minExtent: 100` |
| `minStartFraction` / `maxStartFraction` | `double` | `0.0` / `1.0` |
| `constraintPolicy` | `SplitterConstraintPolicy` | `favorStart` |
| `surplusPolicy` | `SplitterSurplusPolicy` | `leaveGap` |
| `divider` | `SplitterDividerStyle?` | theme / defaults |
| `snap` | `SplitterSnapBehavior?` | none |
| `deferredResize` | `bool` | `false` |
| `resizable` | `bool` | `true` |
| `doubleTapResetTo` | `double?` | none |
| `onChanged` / `onChangeStart` / `onChangeEnd` | `ValueChanged<SplitterChangeDetails>?` | none |
| `onHandleTap` / `onHandleDoubleTap` | `VoidCallback?` | none |
| `enableKeyboard` / `enableHaptics` | `bool?` | `true` |
| `keyboardStep` / `pageStep` | `double?` | `0.01` / `0.1` |
| `semantics` / `semanticsLabel` | `SplitterSemanticsLabels?` / `String?` | defaults |
| `shieldPlatformViews` | `bool?` | `true` |
| `dragBarrierColor` / `dragBarrierBuilder` | `Color?` / builder | none |
| `holdScrollWhileDragging` | `bool` | `false` |
| `unboundedBehavior` / `fallbackExtent` | `UnboundedBehavior?` / `double?` | `shrinkToChildren` / `500` |
| `snapToPhysicalPixels` | `bool?` | `false` |
| `restorationId` | `String?` | none |

**Controller - `SplitterController`**

| Member | Description |
| --- | --- |
| `value` | atomic `SplitterState` (position + collapse) |
| `position` / `effectiveFraction` | the request / the on-screen ratio |
| `layout` / `layoutListenable` | resolved `SplitterLayout?` and its notifier |
| `isDragging` / `isDraggingListenable` | drag state |
| `isAttached` | whether a splitter currently drives it |
| `jumpTo` / `updateRatio` / `reset` | set the position |
| `animateTo` | vsync animate; returns `Future<SplitterAnimationStatus>` |
| `collapse` / `expand` / `toggleCollapse` | collapse control |
| `collapsedPane` / `isCollapsed` | collapse state |

**Supporting types**

`SplitterPosition` (`fraction` / `startPixels` / `endPixels`) ·
`SplitterState` · `SplitterLayout` · `SplitterResolution` ·
`SplitterPaneConstraints` · `SplitterPane` ·
`SplitterConstraintPolicy` · `SplitterSurplusPolicy` ·
`SplitterSnapBehavior` (`ReleaseSnap` / `MagneticSnap` / `StickySnap`) ·
`SplitterDividerStyle` · `SplitterHandleDetails` ·
`ResizableSplitterThemeData` · `ResizableSplitterTheme` ·
`SplitterSemanticsLabels` · `SplitterChangeDetails` ·
`SplitterChangeSource` · `SplitterChangeEnd` ·
`SplitterAnimationStatus` · `UnboundedBehavior`

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
| `animateTo(..., frames: 12)` | `animateTo(...)` (vsync-driven, returns `SplitterAnimationStatus`) |
| `blockerColor` / `overlayEnabled` | `dragBarrierColor` / `shieldPlatformViews` |
| `antiAliasingWorkaround` | `snapToPhysicalPixels` |
| `fallbackMainAxisExtent`, `UnboundedBehavior.flexExpand` / `.limitedBox` | `fallbackExtent`, `UnboundedBehavior.shrinkToChildren` / `.useFallbackExtent` |

The `Axis` re-export was dropped - import it from `package:flutter/material.dart`.
See the [CHANGELOG](CHANGELOG.md) for the full list of breaking changes.

## Example app

An end-to-end demo lives under [`example/`](example/) - it tours the basics,
custom theming, keyboard and snapping, vertical layouts, and an embedded
platform WebView:

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
