# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.1.2

### Fixed

- The divider could still stay stuck in the dragging state when the pointer was
  released over a platform view (for example a `WebView`) on macOS - the case
  2.1.1 targeted but did not fully resolve. Arming the shield earlier was not
  enough: the shield's barrier defaulted to a fully transparent fill, which
  paints nothing, so no Flutter layer was composited above the platform view.
  With nothing painted there the native view stayed the topmost surface, and the
  OS delivered the pointer release to it instead of to Flutter, so the drag never
  ended. The shield now always paints an imperceptible layer above platform views
  while dragging (independent of `dragBarrierColor` / `dragBarrierBuilder`), so
  the release reaches Flutter and the drag ends reliably. Known limitation: iOS
  and web platform views may still need an app-supplied pointer interceptor, as a
  painted Flutter layer is not an input target on those platforms.

## 2.1.1

### Fixed

- A divider next to a platform view (for example a `WebView`) could stay stuck
  in the dragging state when the pointer was released over that view:
  `controller.isDragging` stayed `true` and the divider kept tracking as if the
  button were still held. The platform-view shield was armed only once the drag
  was recognized, so a divider that also handles a tap or double-tap left a brief
  window - before the drag won the gesture arena - in which the neighboring
  platform view could capture the pointer and swallow the release. The shield is
  now armed on pointer-down and its lifetime is bounded by the press, so the
  release is delivered reliably and the drag always ends. The visible drag
  barrier still appears only while a drag is in progress.

## 2.1.0

Adds two magnetic-snap shaping controls and a large internal reorganization.
The public API is unchanged apart from the two additive `MagneticSnap` options
below (both default to the previous behavior), so existing code keeps working.

### Added

- `MagneticSnap.falloff` (and the `SplitterSnapBehavior.magnetic(falloff:)`
  parameter): a `Curve` that shapes the magnetic pull across the influence zone.
  The linear nearness (`1` at the point, `0` at the tolerance edge) is passed
  through the curve before being scaled by `strength`, so an ease-in curve such
  as `Curves.easeInCubic` lets the divider track the pointer freely until it is
  close, then catch harder near the point for a snappier feel. Defaults to
  `Curves.linear`, which reproduces the previous behavior exactly - so this is a
  backward-compatible addition.
- `MagneticSnap.settleFactor` (and the
  `SplitterSnapBehavior.magnetic(settleFactor:)` parameter): a `[0, 1]` fraction
  of the tolerance defining a small core around each point where the divider
  settles exactly onto it, giving the pull a crisp finish (it stays pushable -
  moving the pointer past the core resumes the pull). Defaults to `0`, which
  keeps the never-quite-lands pull - a backward-compatible addition.

### Changed

- Adopted `equatable` for the equality of the value and configuration types
  (`SplitterPosition`, `SplitterState`, `SplitterLayout`,
  `SplitterPaneConstraints`, `SplitterChangeDetails`, the snap behaviors, and
  the theme/style types). The hand-written `==` / `hashCode` were replaced by
  `EquatableMixin` `props` over the same fields, so equality, hash codes,
  `toString`, `copyWith`, and `lerp` are unchanged - this is purely an internal
  simplification, not a behavior change.
- Added `equatable` and `meta` dependencies. `meta` backs the `@immutable` /
  `@internal` annotations applied across the source.
- Reorganized `lib/src` into `model/`, `solver/`, `theme/`, and `widget/`
  folders and split the large widget files into focused parts. This is internal
  only: the package barrel still exports the same public types, so
  `import 'package:resizable_splitter/resizable_splitter.dart'` is unaffected.
- Rebuilt the example into an interactive showcase - snapping, constraints,
  collapse, pixel pinning, an IDE-style layout, and accessibility - replacing
  the previous minimal demo.

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
