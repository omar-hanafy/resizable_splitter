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
  `WidgetStateProperty<Color?>` resolved against `hovered` / `focused` / `dragged`.
- Pane limits grouped into `startConstraints` / `endConstraints`
  (`SplitterPaneConstraints`), replacing `minPanelSize` / `minStartPanelSize` /
  `minEndPanelSize`. Adds per-pane `maxExtent`. A pane is collapsible when its
  `collapsedExtent` is set (a nullable `double?` in `[0, minExtent]`; null = not
  collapsible) - this replaces the separate `collapsible` bool, so an
  unreachable/contradictory collapse config is now unrepresentable.
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
- Pixel `minExtent` / `maxExtent` are now **hard** limits that always win over the
  fractional `minStartFraction` / `maxStartFraction` caps when the two disagree
  (previously a fractional cap could override a feasible pixel minimum).
- `surplusPolicy` now defaults to `SplitterSurplusPolicy.leaveGap` (was
  `giveToStart`), so `maxExtent` is a true maximum by default: leftover space
  becomes a gap between the panes instead of overflowing one past its max.
- `SplitterLayout.isConstrained` (bool) -> `resolution` (a `SplitterResolution`:
  `exact` / `clamped` / `minShortage` / `maxSurplus` / `fractionConflict` /
  `collapsed` / `inactive`). It also gains `minStartExtent` / `maxStartExtent` and
  derived `canIncrease` / `canDecrease`.
- The redundant `SplitterValue` type is removed; `SplitterChangeDetails` is now a
  standalone value type carrying the same fields plus `source`.
- `SplitterDividerStyle.hitSlop` (additive padding) -> `interactiveExtent` (the
  total grab target across the bar). Defaults to 48 (the Material minimum touch
  target), up from an effective ~6px; migrate with
  `interactiveExtent = thickness + 2 * oldHitSlop`.
- `onChangeEnd` now also fires for a canceled drag, so every `onChangeStart` is
  balanced by exactly one end. `SplitterChangeDetails.end` (a `SplitterChangeEnd`)
  reports `committed` vs `canceled`.
- Behavioral renames: `blockerColor` -> `dragBarrierColor`; `overlayEnabled` ->
  `shieldPlatformViews`; `antiAliasingWorkaround` (and the solver's
  `snapToDevicePixels`) -> `snapToPhysicalPixels`; `fallbackMainAxisExtent` ->
  `fallbackExtent`; `UnboundedBehavior.flexExpand` / `.limitedBox` ->
  `shrinkToChildren` / `useFallbackExtent`; `SplitterChangeSource.programmatic` ->
  `doubleTapReset`.
- `SplitterController.layout` is now cleared (notifies `null`) when the controller
  detaches from its splitter, rather than retaining the last geometry.

### Added

- `SplitterController.layout` / `layoutListenable`: the resolved on-screen
  geometry (`SplitterLayout` - effective fraction, both pane extents, available
  extent, the legal `minStartExtent` / `maxStartExtent` band with derived
  `canIncrease` / `canDecrease`, a `resolution`, and `collapsedPane`) as an
  observable separate from the request. A pixel pin's fraction shifts when the
  container resizes without the request changing, so this is the signal for that
  class of change. `null` before the first layout (no pretending a pixel request
  already has a fraction), and cleared when the controller detaches.
- `SplitterState` (the atomic controller value) and `SplitterController.jumpTo`
  / `position`.
- `SplitterAnimationStatus` (`completed` / `canceled` / `detached`), the result
  of an `animateTo` run.
- `SplitterSurplusPolicy` (`giveToStart` / `giveToEnd` / `proportional` /
  `leaveGap`) + a `surplusPolicy` argument: the solver now defines the *surplus*
  case (both maximums too small to fill the space) explicitly, instead of
  silently overflowing a maximum. Defaults to `leaveGap`, which keeps both panes
  at their max and renders the leftover as a gap.
- Framework-grade accessibility: a keyboard focus ring (with `WidgetState.focused`
  in the divider color resolver and `SplitterHandleDetails.isFocused` for custom
  grips), localizable semantics via `SplitterSemanticsLabels` (on the widget or
  the theme), and assistive increase/decrease actions gated on whether the divider
  can actually move that way (dropped at a hard bound).
- `interactiveExtent` on `SplitterDividerStyle`: the grab target across the bar,
  default 48, decoupled from the visible `thickness` and from layout.
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
- Live snap modes alongside the existing release snapping:
  `SplitterSnapBehavior.magnetic` pulls the divider toward a point during the
  drag and can be pushed through (no release-time jump), and
  `SplitterSnapBehavior.sticky` captures onto a point and holds it until the
  pointer escapes past a hysteresis radius. `SplitterSnapBehavior` is now a
  sealed type (`ReleaseSnap` / `MagneticSnap` / `StickySnap`); the unnamed
  `SplitterSnapBehavior(...)` constructor still builds release snapping, so
  existing call sites are unchanged.
- The bounded layout is backed by a dedicated `RenderObject` that resolves the
  split in `performLayout` against the real constraints (no `LayoutBuilder`).
  This is behavior-preserving - the public widget, controller, handle, and
  solver are unchanged - but it adds **intrinsic sizing** and **dry layout**: a
  `ResizableSplitter` can now sit under `IntrinsicWidth` / `IntrinsicHeight` (or
  any parent that queries intrinsics) and size to its panes, where the previous
  layout threw. Painting (each pane clipped to its box), clipping, and hit
  testing (the divider winning inside its interactive slop) also move into the
  render object. The resolved layout is published from the layout pass, so
  `layoutListenable` notifies once per resolved change, after the frame.

### Fixed

- Collapse is now part of the atomic controller value, so collapsing and then
  writing an equal value can no longer silently desync the controller from the
  UI (it reported expanded while the pane stayed collapsed).
- Collapsibility is enforced: a pane only collapses if it has a `collapsedExtent`,
  and `collapsedExtent` is asserted `<= minExtent` (collapse can no longer
  enlarge a pane). `controller.layout.collapsedPane` reports the *resolved*
  collapse, so collapsing a fixed pane is a visible no-op rather than a phantom.
- `effectiveFraction` now reports the true on-screen value and updates on
  container resize (via `layoutListenable`); it no longer leaks the unclamped
  request after settling onto a constrained target.
- Stored ratio now equals the visible ratio: honest drag/keyboard callbacks, and
  the ~200px drag dead zone and cramped-drag crash are gone by construction.
- RTL: drag and arrow keys move with the pointer; the start pane lays out on the
  right.
- The controller rejects `NaN` / out-of-range values at the source.
- `interactiveExtent` enlarges the grab target by overlapping the panes instead
  of widening the divider footprint, and collapses to the visible thickness on a
  non-resizable divider so a static bar cannot steal the panes' hits.
- Overflow-safe under containers smaller than the divider; each pane is clipped.
- A bounded main axis with an unbounded cross axis (e.g. a horizontal splitter
  in a `Column`) no longer throws an infinite-size error; the layout sizes to the
  panes' cross extent instead.
- Animation is vsync-driven, cancels on drag, and honors
  `MediaQuery.disableAnimations`.
- Animation lifecycle is now deterministic: an `animateTo` future no longer
  hangs when the splitter is disposed mid-run (resolves `detached`), a controller
  swap no longer lets the animation bleed onto the new controller, and a
  cancelled run is distinguishable from a completed one (no phantom
  programmatic change after a cancel).
- Animation contract: a fresh `animateTo` always supersedes a run in progress
  (even when the target is already current), a listener's reentrant write cancels
  the run, a run from a collapsed pane clears the collapse and animates out, and
  the target is resolved through the solver so `completed` means the divider
  actually arrived (no stall against a target clamped off-screen).
- Swapping the controller (or axis) during an active drag now ends the drag on
  the original controller instead of stranding it flagged as dragging.
- The drag shield degrades gracefully when there is no `Overlay` ancestor
  (the drag still works) instead of throwing from a reusable layout primitive.
- Physical-pixel snapping (`snapToPhysicalPixels`) now applies to every solve -
  drag, keyboard, snap matching, semantics, deferred preview, and the published
  layout - not just the initial layout, so callbacks can no longer report an
  extent the layout never drew. The snap config moved from a per-`solve` argument
  onto `SplitterSolver` itself.
- Drag is measured in local space (correct under `Transform`); the stuck-drag
  router is keyed by pointer id (independent concurrent drags).
- Slider semantics: role, enabled/disabled state, focus, text direction, and
  assistive adjustment decoupled from the keyboard flag.
- The change-callback contract is now explicit and honest: `onChanged` /
  `onChangeStart` / `onChangeEnd` fire for interactions (drag, keyboard, assistive
  adjust, snap, double-tap) and collapse/expand only; programmatic writes
  (`jumpTo` / `updateRatio` / `reset` / `animateTo`) and restoration are observed
  through the `controller` and `layoutListenable` instead (documented, not a
  silent partial contract).

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
