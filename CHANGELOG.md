# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0

A ground-up rebuild around a pure constraint solver. Every interaction (drag,
keyboard, snap, semantics) now operates on the **effective** on-screen position,
so the stored value can no longer disagree with what is drawn.

### Breaking changes

- `SplitterController.value` is now a `SplitterPosition` (was `double`). Read the
  on-screen ratio with `controller.effectiveFraction`.
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
- `SplitterController.animateTo` no longer takes `frames` (it is vsync-driven).
- The `Axis` re-export was dropped; import it from `package:flutter/material.dart`.

### Added

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
