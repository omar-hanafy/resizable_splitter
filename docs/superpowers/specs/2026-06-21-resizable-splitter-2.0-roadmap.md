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
- PARTIAL Sub-project 3 (Interaction): RTL done (drag + arrows + layout,
  `rtl_test.dart`). Controller value-setter hardened to reject NaN / out-of-range
  at the source. REMAINING: transform-safe local coordinates, a custom drag
  recognizer with real pointer ids + multi-drag sessions keyed by pointer,
  pixel-space snap tolerance.
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

Interim notes for the next session:
- The controller value is a single `double` (requested/effective fraction). The
  sealed `SplitterPosition` public input (pixel pinning) lands in Sub-project 6.
- `handleHitSlop` still reserves layout (`thickness + 2*slop`); the overlap fix
  arrives with the render object (Sub-project 7). The two `review_fixes`
  hit-slop tests still assert the interim behavior and will migrate then.
- Next major phase = Sub-project 6 (API restructure + deprecation bridge) and 7
  (render object + features). 6 carries public-API shape decisions; 7 is the
  highest-risk piece to land without visual verification.

## Working agreements

- TDD: tests first, lock invariants (not just reported inputs).
- make-it-impossible: eliminate bug classes at the highest proportionate level;
  log the decision chain.
- Keep `dart analyze` clean and `flutter test` green at every commit. Migrate
  existing tests + the example app as the API changes; log each behavior change.
- Branch `feat/resizable-splitter-2.0`; one commit per coherent sub-step.
