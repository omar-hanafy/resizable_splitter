# Sub-project 9: Atomic controller state + resolved-layout listenable

Status: in progress. Date: 2026-06-22. Branch `feat/resizable-splitter-2.0`.

Addresses the GPT Pro review's root recommendation ("Recommended 2.0 sequence" #1):
*"Replace the controller state model. Atomic immutable requested state plus a
separate resolved-layout listenable."* This is the foundation the later
recommendations (centralized dispatch, unified geometry) build on.

## Make-it-impossible analysis

```
Direct cause (issue #1):  SplitterController.value's setter mutates _collapsedPane
                          (and _effectiveFraction) BEFORE super.value. ValueNotifier
                          skips notification when newValue == oldValue, so
                          `collapse(start); value = value;` clears collapse with no
                          notification - controller says expanded, UI stays collapsed.
Deep cause:               The controller's true state is split across THREE fields -
                          super.value (the SplitterPosition request), _collapsedPane,
                          and _effectiveFraction - but only ONE (super.value) drives
                          notifications. Collapse and effectiveFraction are
                          side-channels. Invalid (desynced) states are representable.
                          [bad architecture: multiple sources of truth]
Fix level chosen:         1 (make it impossible by design). Fold ALL requested state
                          into one atomic immutable SplitterState{position, collapsedPane}
                          that IS the notifier's value. Collapse can no longer change
                          without being part of value, hence part of the == that gates
                          notification. The desync becomes unrepresentable.
Why tests missed it (#1): collapse_test only wrote *distinct* values; it never wrote an
                          EQUAL value while collapsed. New invariant test locks the
                          same-value-while-collapsed case (the reported scenario) AND
                          that collapse only ever changes through `value`.

Direct cause (issue #8):  effectiveFraction is a cached double pushed in via
                          _setEffectiveFraction; the controller never notifies when a
                          pixel-pinned pane's on-screen fraction changes on container
                          resize (the request did not change).
Fix:                      A SEPARATE ValueListenable<SplitterLayout?> published by the
                          attached view each solve. The request notifier (SplitterState)
                          and the resolved-layout notifier (SplitterLayout?) are two
                          distinct observables, each notifying for its own concern.
Why tests missed it (#8): no test resized the container under a pixel pin and asserted a
                          notification. New invariant test locks it.
```

## New public types

- `lib/src/split_state.dart` - `SplitterState { SplitterPosition position; SplitterPane? collapsedPane }`.
  Immutable; `==`/`hashCode` over both fields. Footgun-free transforms (no
  copyWith that silently can't clear the nullable collapse):
  - `copyWith({SplitterPosition? position})` - position only; preserves collapse
    (used by the animation tick).
  - `collapse(SplitterPane)` / `expand()` - intent-named; return `this` unchanged
    when already in that state (so the ValueNotifier no-ops).
  - `isCollapsed`.
- `lib/src/split_layout.dart` - `SplitterLayout { effectiveFraction, startExtent,
  endExtent, availableExtent, isConstrained, collapsedPane }`. The resolved,
  on-screen geometry. `null` before first layout (honest - no pretending a pixel
  request has fraction 0).

Both exported from the barrel.

## Controller shape (clean break - 2.0 is pre-publish)

- `SplitterController extends ValueNotifier<SplitterState>` (was `<SplitterPosition>`).
- `jumpTo(SplitterPosition)` - set position, clear collapse, cancel a running
  animation (replaces the old `value = SplitterPosition` ergonomic).
- `position` getter (= `value.position`); `collapsedPane` / `isCollapsed` derive
  from `value`.
- `collapse` / `expand` / `toggleCollapse` now write a new atomic `value`
  (so they correctly notify-iff-changed and supersede a running animation).
- `updateRatio` / `reset` route through `jumpTo`.
- `layout` -> `SplitterLayout?`, `layoutListenable` -> `ValueListenable<SplitterLayout?>`.
- `effectiveFraction` stays a non-null `double` convenience: `layout?.effectiveFraction
  ?? value.position.resolveFraction(0)`. The honest, notifying source of truth is
  `layout`/`layoutListenable`; `effectiveFraction` is documented as request-derived
  before the first layout. (Chosen over a nullable `effectiveFraction`: it keeps the
  large existing read-out surface ergonomic while the honest nullable path still
  exists via `layout`. A nullable effectiveFraction would break ~40 call sites for a
  honesty nit already covered by `layout`.)

## Migration map (internal, all mechanical)

`controller._collapsedPane` -> `controller.value.collapsedPane`;
`controller.value` (as position) -> `controller.value.position`;
`controller.value = SplitterPosition.x` -> `controller.jumpTo(...)`;
`_setEffectiveFraction(f)` -> `_publishLayout(SplitterLayout(...))` (post-frame, like
`_maybeReportCollapseChange`); animation tick -> `controller._setAnimatedPosition(pos)`
(preserves collapse via `value.copyWith(position:)`, so the existing
animation-while-collapsed behavior is unchanged).

## Increments (each green, own commit)

- A: `SplitterState` value type + `split_state_test.dart` + export.
- B: `SplitterLayout` value type + `split_layout_test.dart` + export.
- C: Controller -> `ValueNotifier<SplitterState>` + `jumpTo` + collapse/expand via
  value; migrate all internal call sites + all tests; add the issue-#1 desync
  invariant test. effectiveFraction stays cached here (no behavior change yet).
- D: Replace the cached effectiveFraction with the `SplitterLayout` listenable
  (`layout`/`layoutListenable`, post-frame publish, derived effectiveFraction);
  add the issue-#8 layout-listenable invariant test.
- E: Docs (README controller section + CHANGELOG 2.0.0 + roadmap), full analyze +
  test + publish dry-run.

## Explicitly out of scope (logged, enabled by this foundation)

- #9 change-details requested-position honesty on drag start (becomes trivial once
  `value.position` is available).
- #5 collapse-vs-interaction semantics (drag-to-expand, collapse animation).
- #2/#3 animation/drag as cancellable owned sessions (`SplitterAnimationResult`).
- A `hasClients`/attachment API + resetting `layout` to null on detach (minor
  staleness for a detached-but-alive external controller; one-frame on swap).
