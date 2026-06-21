# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0

A ground-up rebuild around a pure constraint solver. Every interaction (drag,
keyboard, snap, semantics) now operates on the **effective** on-screen position,
so the stored value can no longer disagree with what is drawn.

### Breaking changes

- `SplitterController.value` is now an atomic `SplitterState` (the requested
  `SplitterPosition` plus any collapsed pane); was `double` in 1.x. Set the
  position with `controller.jumpTo(SplitterPosition)`, read it with
  `controller.position`, and the on-screen ratio with
  `controller.effectiveFraction`.
- `initialRatio` -> `initialPosition` (a `SplitterPosition`).
- Divider styling grouped into `divider: SplitterDividerStyle(...)`, replacing
  `dividerThickness` / `dividerColor` / `dividerHoverColor` /
  `dividerActiveColor` / `handleHitSlop` / `handleBuilder`. The color is a
  `WidgetStateProperty<Color?>` resolved against `hovered` / `dragged`.
- Pane limits grouped into `startConstraints` / `endConstraints`
  (`SplitterPaneConstraints`), replacing `minPanelSize` / `minStartPanelSize` /
  `minEndPanelSize`. Adds per-pane `maxExtent`, `collapsible`, `collapsedExtent`.
- `minRatio` / `maxRatio` -> `minStartFraction` / `maxStartFraction`.
- Snapping grouped into `snap: SplitterSnapBehavior(points, tolerance,
  pixelTolerance)`, replacing `snapPoints` / `snapTolerance`.
- Callbacks `onRatioChanged` / `onDragStart` / `onDragEnd` (carrying a `double`)
  -> `onChanged` / `onChangeStart` / `onChangeEnd` carrying
  `SplitterChangeDetails` (the request, the effective fraction, both pane
  extents, and a `SplitterChangeSource`).
- `crampedBehavior` (`CrampedBehavior`) -> `constraintPolicy`
  (`SplitterConstraintPolicy.favorStart` / `favorEnd` / `proportional`).
- `ResizableSplitterThemeOverrides` removed. The single, all-nullable
  `ResizableSplitterThemeData` is now both the `ThemeExtension` and the
  `ResizableSplitterTheme` data, which fixes a partial-override clobber bug by
  construction.
- `SplitterController.animateTo` no longer takes `frames` (it is vsync-driven)
  and now returns `Future<SplitterAnimationStatus>` (was `Future<void>`), so a
  caller can tell a completed run from one a drag cancelled or a disposal ended.
- The `Axis` re-export was dropped; import it from `package:flutter/material.dart`.

### Added

- `SplitterController.layout` / `layoutListenable`: the resolved on-screen
  geometry (`SplitterLayout` - effective fraction, both pane extents, available
  extent, `isConstrained`, `collapsedPane`) as an observable separate from the
  request. A pixel pin's fraction shifts when the container resizes without the
  request changing, so this is the signal for that class of change. `null` before
  the first layout (no pretending a pixel request already has a fraction).
- `SplitterState` (the atomic controller value) and `SplitterController.jumpTo`
  / `position`.
- `SplitterAnimationStatus` (`completed` / `canceled` / `detached`), the result
  of an `animateTo` run.
- Pixel pinning: `SplitterPosition.startPixels` / `endPixels` keep a pane's pixel
  width as the container resizes (true fixed sidebars).
- Collapse/expand: `controller.collapse(SplitterPane.start | SplitterPane.end)`,
  `expand()`, `toggleCollapse()`, with `collapsedPane` / `isCollapsed`. Restores
  the prior position automatically; emits `collapse` / `restore` change events.
- State restoration via `ResizableSplitter.restorationId`.
- Deferred resize (`deferredResize`): a preview line tracks the drag and the
  panes settle once on release - for expensive pane subtrees.
- Customizable drag barrier (`dragBarrierBuilder`) over the platform-view shield.
- `SplitterSnapBehavior.pixelTolerance` for a size-independent snap feel.

### Fixed

- Collapse is now part of the atomic controller value, so collapsing and then
  writing an equal value can no longer silently desync the controller from the
  UI (it reported expanded while the pane stayed collapsed).
- `effectiveFraction` now reports the true on-screen value and updates on
  container resize (via `layoutListenable`); it no longer leaks the unclamped
  request after settling onto a constrained target.
- Stored ratio now equals the visible ratio: honest drag/keyboard callbacks, and
  the ~200px drag dead zone and cramped-drag crash are gone by construction.
- RTL: drag and arrow keys move with the pointer; the start pane lays out on the
  right.
- The controller rejects `NaN` / out-of-range values at the source.
- `handleHitSlop` now enlarges the grab target by overlapping the panes instead
  of widening the divider footprint.
- Overflow-safe under containers smaller than the divider; each pane is clipped.
- Animation is vsync-driven, cancels on drag, and honors
  `MediaQuery.disableAnimations`.
- Animation lifecycle is now deterministic: an `animateTo` future no longer
  hangs when the splitter is disposed mid-run (resolves `detached`), a controller
  swap no longer lets the animation bleed onto the new controller, and a
  cancelled run is distinguishable from a completed one (no phantom
  programmatic change after a cancel).
- Swapping the controller (or axis) during an active drag now ends the drag on
  the original controller instead of stranding it flagged as dragging.
- The drag shield degrades gracefully when there is no `Overlay` ancestor
  (the drag still works) instead of throwing from a reusable layout primitive.
- Drag is measured in local space (correct under `Transform`); the stuck-drag
  router is keyed by pointer id (independent concurrent drags).
- Slider semantics: role, enabled/disabled state, focus, text direction, and
  assistive adjustment decoupled from the keyboard flag.

## 1.1.1

- Refined drag coalescing, semantics percentages, and anti-alias minima handling.

## 1.1.0

- Theming refresh: `ResizableSplitterTheme` plus a `ThemeExtension` drive divider styling, keyboard steps, overlays, and
  unbounded policies.
- Layout policies: `UnboundedBehavior` (`LimitedBox` opt-in), `CrampedBehavior`, and `antiAliasingWorkaround` for crisp
  panes.
- Interactions: `resizable` toggle, `onHandleTap` / `onHandleDoubleTap`, and controller multi-attach guard.
- Fixed precedence so per-instance constructor arguments override themed switches.
- Tests expanded to cover new theming, policies, and interaction paths.

## 1.0.0

- Initial release of `ResizableSplitter` with drag-to-resize layouts.
- Keyboard navigation, screen-reader semantics, and customizable divider styling.
- `SplitterController` for programmatic control and testing.
