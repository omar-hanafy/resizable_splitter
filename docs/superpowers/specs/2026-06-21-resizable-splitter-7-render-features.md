# Sub-project 7 - Layout guarantees + features

Part of the [2.0 roadmap](./2026-06-21-resizable-splitter-2.0-roadmap.md). Branch
`feat/resizable-splitter-2.0`. Each increment lands `dart analyze` clean and
`flutter test` green.

## Goal

Close the last known bug class (grab slop consuming layout) and add the missing
features (collapse/expand + restore, state restoration, deferred resize), while
making the panel layout overflow-safe, cross-axis stretched, and clipped.

## Locked architecture decision: widget layer, not a custom render object

The roadmap floated a custom `MultiChildRenderObject` for the render layer, with
an explicit blessed fallback (decision #5) to a Stack-based overlap "without
losing the sub-project's guarantees." After tracing the mechanics, the
widget-layer approach is not just a fallback - it is the correct, proportionate
fix:

- The headline win is **hit-region-overlaps-panels** (so `hitSlop` enlarges the
  grab target over a thin bar instead of widening the divider footprint). In a
  plain `Flex`, children are hit-tested in reverse paint order, so an opaque end
  panel is tested *before* the divider; an inflated divider hit rect would still
  lose to the panel. The grab region must sit **on top** of the panels. A Stack
  overlay is the only structure that delivers this - a custom render object would
  have to do the same layering, plus re-implement Flex layout for arbitrary child
  widgets.
- Standard primitives (`Stack`, `Flex`, `Positioned.directional`, `ClipRect`)
  are battle-tested, fully widget-testable, and more adoptable than a bespoke
  render object - matching the "robust, not gold-plated" and make-it-impossible
  "don't manufacture a subsystem for a proportionate fix" doctrines.

**The fix (make-it-impossible):** assemble the bounded layout as a `Stack` of two
layers - a `Flex` `[start | thin visual gap (thickness) | end]` for layout+paint,
and a transparent **gesture catcher** (`thickness + 2*slop` along the main axis,
full cross axis) overlaid on top via `Positioned.directional`, centered on the
divider. Slop sizes only the overlay; the Flex footprint is always exactly
`thickness`. It is then structurally impossible for slop to reduce panel layout.

## Increments

- **7a - Hit-region overlaps panels.** Divider footprint drops to `thickness`
  (was `thickness + 2*slop`). The handle moves from a Flex child to a
  `Positioned.directional` catcher on top of a Stack, centered on the divider, so
  its grab zone overlaps the panel edges by `slop`. Default (`slop == 0`) path is
  geometrically identical to today. Flips the interim `review_fixes` footprint
  test; the "drag inside the slop still resizes" test stays green.
- **7b - Overflow-safe + cross-axis stretch + clip.** Clamp the divider's own
  extent to the container so a parent smaller than `thickness` cannot overflow.
  Panels stretch to fill the cross axis and are wrapped in `ClipRect` so panel
  content cannot bleed past its box.
- **7c - Collapse/expand + restore.** Controller API to collapse either pane to
  its `collapsedExtent` and restore the prior position; emits change events with
  `SplitterChangeSource.collapse` / `.restore`. The solver already supports
  `startCollapsed` / `endCollapsed`; thread it through the widget.
- **7d - State restoration.** Opt-in persistence of the position across app
  restarts via the Flutter restoration framework (a `restorationId` on the
  widget and/or a `RestorableSplitterController`).
- **7e - Deferred resize.** A mode where panels resize only on drag end (a live
  divider preview during the drag), for expensive panel subtrees.

## Working agreements

Same as the umbrella roadmap: TDD (lock invariants), make-it-impossible, green at
every commit, migrate tests + example alongside, one commit per coherent sub-step.
