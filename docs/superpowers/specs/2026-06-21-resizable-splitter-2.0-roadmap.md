# Resizable Splitter 2.0 - Rebuild Roadmap

Status: in progress. Owner decision date: 2026-06-21.

This is the umbrella spec for a ground-up 2.0 of `resizable_splitter`. It records
the triage that motivated it, the locked decisions, and the dependency-ordered
sub-projects. Each sub-project gets its own spec + plan + implementation and must
land with `dart analyze` clean and `flutter test` green before the next starts.

## Goal

A two-pane split view good enough that the Flutter team could adopt it: correct
under cramped/RTL/transformed/tiny layouts, honest callbacks, framework-grade
accessibility, a clean controller/animation model, and a small well-organized
public API. "Robust, not gold-plated."

## Why (triage of the external review)

Verified against source. Confirmed bug classes:

- Stored ratio != visible ratio. Controller holds the raw value but the layout
  shows the constrained one whenever a pixel minimum bites. Causes: dishonest
  `onDragStart`, an invisible keyboard dead band, and a ~200px drag dead zone.
  Root cause of several other issues. (Critical)
- RTL reversed: no `Directionality` is read; drag + arrow keys move opposite the
  pointer in RTL. (Critical)
- Controller invariants bypassable: `extends ValueNotifier<double>` lets
  `value = NaN / -100 / 500` skip clamping and reach layout. (Critical)
- `handleHitSlop` consumes layout instead of overlapping it (the slop should
  enlarge the hit target over a thin visual bar, not widen the divider). (High)
- Global drag router supports a single drag; pointer identity reconstructed by
  position-matching instead of a real pointer id. (High)
- Animation is `Timer.periodic`, not vsync; not cancelled by drag/reset; can
  leave [0,1] with overshoot curves; leaks `frames`. (High)
- Tiny-layout overflow (parent < divider thickness). (High)
- `proportionallyClamp` loses its proportions (minima clamped before the split).
  (Medium)
- Snap distance measured in raw ratio space, tolerance scale-dependent. (Medium)
- Semantics: adjust actions die when keyboard disabled; no slider role / focus /
  text direction; "Drag to resize" even when not resizable; not localizable.
  (Medium)
- Polish: overlay entries never disposed; transparent `blockerColor` forced to
  alpha-1; haptics fire on no-op key presses; drag breaks under `Transform`;
  pixel snap is logical not physical; controller touches `WidgetsBinding` at
  construction; panes do not stretch on the cross axis and are not clipped.

Missing features worth having: pixel/fractional positions, max pane extents,
collapse/expand with restore, state restoration, deferred resize, change events
carrying a source.

## Locked decisions

1. Scope: full ground-up 2.0, decomposed into sequenced sub-projects.
2. Naming: keep `ResizableSplitter` + `SplitterController`. `SplitView` collides
   with the `split_view` and `flutter_split_view` packages. New support types use
   the existing `Splitter*` prefix. Panels become `start` / `end`.
3. Position model: sealed `SplitterPosition` (`fraction | startPixels |
   endPixels`). The controller stores the request; a pure solver derives the
   effective layout; callbacks expose both.
4. Migration posture: deprecation bridge. 2.0 ships the new API; the 1.x surface
   survives as `@Deprecated` shims plus a migration guide; removed in 3.0.
   Finalized in step 6.
5. Render: a custom `MultiChildRenderObject` is in scope (step 2). Most of its
   wins are also reachable in the widget layer, so if it turns hairy we fall back
   to a Stack-based overlap without losing the sub-project's guarantees.
6. Flutter floor: reconsider the 3.35 floor (de-sugar `(_, _)` wildcards so the
   floor is a support decision, not a syntax accident). Step 6.

## Build sequence

Each step is its own spec -> plan -> build -> green.

1. Foundation - pure solver + position/value model. Zero Flutter widgets,
   property-tested. Purely additive (no existing test changes). Kills the
   Critical bug class by construction.
2. Render layer - `MultiChildRenderObject`: overflow-safe layout, a hit region
   that overlaps the panels, RTL, cross-axis stretch + clip, physical-pixel snap,
   precise semantic bounds.
3. Interaction - gesture recognizer with real pointer ids, drag-from-effective,
   transform-safe local coordinates, multi-drag sessions, snap in pixel space,
   haptics-on-change, keyboard.
4. Controller + animation - validated value (no NaN), vsync animation in State,
   cancel-on-drag, controlled/uncontrolled constructors, overlay lifecycle.
5. Accessibility - slider role, focus, decoupled from keyboard, read-only state,
   localizable label + formatter.
6. Theme + public API - single nullable theme + `WidgetStateProperty`, grouped
   config objects, change `source`, final naming, drop the `Axis` re-export,
   Flutter floor, deprecation shims + migration guide.
7. Features - collapse/expand + restore, state restoration, deferred resize.
8. Platform barrier + integration tests + release - `dragBarrierBuilder`, honest
   platform-view claims, CI matrix, pana, publish dry-run, deprecate 1.x.

## Target file tree

```
lib/
  resizable_splitter.dart            # public exports only
  src/
    split_position.dart              # sealed SplitterPosition
    split_pane_constraints.dart      # per-pane pixel min/max + collapse
    split_solver.dart                # SplitterConstraintPolicy + pure solver
    split_view_value.dart            # SplitterValue + SplitterChangeDetails + source
    splitter_controller.dart         # validated controller
    resizable_splitter.dart          # the public StatefulWidget
    split_view_render.dart           # MultiChildRenderObject
    split_view_gestures.dart         # drag recognizer + multi-drag + barrier
    resizable_splitter_theme.dart    # single nullable theme + WidgetStateProperty
```

Solver and session classes stay private; only the model/widget/theme/position
types are exported.

## Progress log (2026-06-21)

Branch `feat/resizable-splitter-2.0`. 90 tests green, `dart analyze` clean.

- DONE Sub-project 1 (Foundation): `SplitterPosition`, `SplitterPaneConstraints`,
  `SplitterConstraintPolicy`, `SplitterSolver`/`SplitterSolution`,
  `SplitterValue`/`SplitterChangeDetails`/`SplitterChangeSource`. Pure, exported
  (solver kept internal). Locked by a ~4000-case property sweep.
- DONE Sub-project 2 (Integration): widget + handle now route geometry and every
  interaction through the solver on the EFFECTIVE fraction. Eliminated: the
  cramped-drag crash class, the drag dead zone, dishonest drag/keyboard
  callbacks, NaN-to-layout, and the proportional 50/50 bug. Also: physical-pixel
  anti-alias snap, snap matching in effective space, haptics-on-change, overlay
  dispose, transparent barrier honored. Tests migrated to the honest values;
  `effective_position_test.dart` locks the invariants.
- DONE Sub-project 3 (Interaction): RTL (drag + arrows + layout, `rtl_test.dart`)
  and the NaN / out-of-range controller hardening landed earlier; the tail landed
  with sub-project 7 - transform-safe local-space drag (`globalToLocal` anchored
  on the stationary splitter box, `transform_drag_test.dart`), a pointer-id-keyed
  multi-drag stuck-drag router (map instead of a single slot, `multi_drag_test.dart`),
  and a pixel-space snap tolerance (`SplitterSnapBehavior.pixelTolerance`,
  `snap_pixel_tolerance_test.dart`). A full custom drag recognizer was judged
  disproportionate (the position-matching pointer correlation is adequate; the
  map fixes the real backup-cleanup gap at the right level).
- DONE Sub-project 4 (Controller + animation): vsync `AnimationController` owned
  by the State; controller delegates via a private `_SplitterAnimator`. Honors
  `MediaQuery.disableAnimations`; a drag/key/reset/direct-write cancels a run;
  `frames` removed; no `WidgetsBinding` at construction; controller swap keeps
  the last shown position. `animation_test.dart` covers it. DEFERRED to 6:
  `SplitterPosition` on the controller, controlled/uncontrolled constructors.
- DONE Sub-project 5 (Accessibility, semantics layer): slider role, enabled /
  disabled state, read-only label when not resizable, assistive adjust decoupled
  from the keyboard flag, honest value previews, text direction, focus-on-press.
  DEFERRED to 6: public `focusNode`/`autofocus`/`onFocusChange`, value formatter.

- IN PROGRESS Sub-project 6 (API restructure, clean break - no deprecations per
  owner direction). DONE: (1) `startPanel`/`endPanel` -> `start`/`end`; (2) pane
  constraints grouped into `startConstraints`/`endConstraints`
  (`SplitterPaneConstraints`) + `minStartFraction`/`maxStartFraction` +
  `constraintPolicy` (removed `CrampedBehavior`; default min stays 100px so
  behavior is preserved; `maxExtent` now exposes per-pane maximums); (3) snapping
  grouped into `SplitterSnapBehavior`; (4) dropped the `Axis` re-export;
  (5) single nullable theme + `SplitterDividerStyle` + `WidgetStateProperty`
  (collapsed `ResizableSplitterThemeData`/`ResizableSplitterThemeOverrides` into
  one all-nullable `ThemeExtension`, fixing the partial-override clobber bug by
  construction; grouped the divider params under `divider:`; state-dependent
  color via `WidgetStateProperty<Color?>`; moved `SplitterHandleDetails` to
  `split_divider_style.dart`); (6) rich callbacks - `onRatioChanged`/
  `onDragStart`/`onDragEnd` -> `onChanged`/`onChangeStart`/`onChangeEnd` carrying
  `SplitterChangeDetails` (request + effective + extents + `SplitterChangeSource`),
  matching Slider's shape.
  (7) `SplitterPosition` controller + pixel pinning (owner chose the full model).
  `SplitterController.value` is now a `SplitterPosition` (was `double`); the
  splitter re-resolves it each frame, so `startPixels`/`endPixels` keep their
  pixel width across container resizes (true pinned sidebars). A drag/keyboard
  adjustment writes a fractional position (the pin releases on interaction, the
  standard behavior). `controller.effectiveFraction` is the on-screen read-out;
  `initialRatio` -> `initialPosition: SplitterPosition` on the widget. Locked by
  `pixel_pinning_test.dart`.

DONE Sub-project 6 (all increments). Status: 114 tests green, analyze clean
(package + example).

DONE Sub-project 7 (layout guarantees + features). Delivered in the widget layer
rather than a custom `MultiChildRenderObject` (locked decision #5's blessed
fallback): tracing the hit test showed the grab region must sit *on top* of the
panels to win in its slop zone - which a Stack overlay provides and a render
object would also have to, plus re-implement Flex for arbitrary children. See
`2026-06-21-resizable-splitter-7-render-features.md`. Increments:
- 7a `handleHitSlop` now overlaps the panels (Stack + `Positioned.directional`
  catcher over a `thickness`-only Flex footprint); slop can no longer eat layout.
  The interim `review_fixes` footprint test migrated to the overlap invariant.
- 7b overflow-safe footprint (the divider clamps to the container, so a tiny
  parent cannot overflow the Flex) + per-pane `ClipRect`. Cross-axis stretch was
  intentionally NOT forced (`CrossAxisAlignment.stretch` throws under an
  unbounded cross axis; fill-capable panes already fill a bounded one).
- 7c collapse/expand + restore: `SplitterPane` + controller
  `collapse`/`expand`/`toggleCollapse` + `collapsedPane`/`isCollapsed`. Collapse
  is a flag that never writes `value`, so restore is free; emits collapse/restore
  change events.
- 7d state restoration via `restorationId` (a private
  `RestorableSplitterPosition`; default = the controller's current value, so a
  first run with no saved state never clobbers an external controller).
- 7e deferred resize (`deferredResize`): a preview line tracks the drag and the
  panes settle once on release, reusing the snap+commit path.
Status: 127 tests green, analyze clean (package + example).

DONE Sub-project 3 tail (transform-safe drag, multi-drag router, pixel snap
tolerance). Status: 131 tests green, analyze clean (package + example).

PARTIAL Sub-project 8 (release). DONE: platform barrier (`dragBarrierBuilder`,
`drag_barrier_test.dart`); 2.0 README + 1.x->2.0 migration table; 2.0.0 CHANGELOG
(breaking / added / fixed); version bump to 2.0.0; a clean
`flutter pub publish --dry-run` (0 warnings - internal planning docs excluded via
`.pubignore`). Status: 132 tests green, analyze clean (package + example).

OWNER-GATED REMAINING (deliberately not done autonomously):
- `flutter pub publish` - outward-facing/irreversible; owner runs or approves.
- CI workflow (e.g. GitHub Actions analyze+test matrix) - infra preference.
- De-sugar the `(_, _)` wildcards and lower the Flutter floor below 3.35 - a
  support-policy decision (broader compatibility vs simpler source).
- Optional: integration tests (the widget suite already covers the surface).

## Post-release hardening (second pass on the external review, 2026-06-22)

After the 2.0 surface was release-ready, a deeper re-read of the external review
flagged that the patches so far did not make the controller/event/animation state
machine production-grade. Walking the review's "Recommended 2.0 sequence":

DONE Sub-project 9 (atomic controller state + resolved-layout listenable;
recommendation #1). `SplitterController` now extends
`ValueNotifier<SplitterState>` ({position, collapsedPane}); collapse moved out of
a side-channel field into the value, so the "collapse then write an equal value"
desync (review issue #1) is unrepresentable. A separate
`SplitterLayout`/`layoutListenable` publishes the resolved on-screen geometry, so
a pixel pin's fraction shift on resize is observable (review issue #8) - the
notifier primes synchronously (fresh read-outs) and flushes post-frame (no
setState-in-build). `jumpTo(SplitterPosition)` replaces the `value =
SplitterPosition` ergonomic. New value types `SplitterState`/`SplitterLayout` are
exported and property-tested; invariant tests lock #1 and #8. Spec:
`2026-06-22-resizable-splitter-9-atomic-state.md`. Status: 155 tests green,
analyze clean (package + tests + example).

DONE Review issue #9 (change-details honesty). `_changeDetails` reported a
fabricated `SplitterPosition.fraction(...)`; now that the atomic value exposes
`value.position` it reports the controller's real request, so a drag starting on
a pixel-pinned pane reports the pin (and a fraction once a move releases it).

DONE Review issue #2 (animation lifecycle) + #3 (drag session) - explicit
cancellable sessions. The animation is now an `_AnimationSession` capturing the
controller it targets; `animateTo` returns `Future<SplitterAnimationStatus>`
({completed, canceled, detached}); disposal resolves `detached` (no hung
future), a controller swap stops the run and resolves `detached` (no bleed onto
the new controller), and a drag/value-write resolves `canceled` (distinct from a
finish, so no phantom programmatic onChanged). The drag got the matching fix: a
`_DividerHandle.didUpdateWidget` ends an in-flight drag on the original
controller when the controller/axis is swapped mid-drag (shared `_teardownDrag`).
Status: 161 tests green, analyze clean (package + tests + example).

REMAINING from the review (next candidates): #10 overlay `maybeOf` graceful
degrade; #7 unify geometry so pixel snapping is consistent across solve sites;
#4 honest callback contract / centralized dispatch (product-shaped); #5 collapse
respects `collapsible` (needs a model decision); #6 solver surplus policy
(product-shaped); #11 unbounded cross axis.

## Working agreements

- TDD: tests first, lock invariants (not just reported inputs).
- make-it-impossible: eliminate bug classes at the highest proportionate level;
  log the decision chain.
- Keep `dart analyze` clean and `flutter test` green at every commit. Migrate
  existing tests + the example app as the API changes; log each behavior change.
- Branch `feat/resizable-splitter-2.0`; one commit per coherent sub-step.
