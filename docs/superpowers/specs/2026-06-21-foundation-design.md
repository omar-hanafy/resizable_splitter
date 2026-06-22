# Sub-project 1: Foundation (pure solver + position/value model)

Parent: [2.0 roadmap](2026-06-21-resizable-splitter-2.0-roadmap.md). Status: in progress.

## Purpose

The model + math layer that makes the Critical bug class (stored != visible,
inverted clamp, NaN reaching layout) unrepresentable. Zero Flutter widgets, zero
`BuildContext`, so it is exhaustively unit + property testable. Purely additive:
no existing widget/controller/theme code changes, so all current tests stay green.

## Constraints

- Files may import `dart:math` and `package:flutter/foundation.dart` (for
  `@immutable`), nothing from `widgets`/`material`. No `BuildContext`, no
  `TextDirection` (the solver works in logical start/end extents; direction is a
  render concern handled in step 2).
- `public_member_api_docs` is an analyzer error: every public member needs `///`.
- No `Date.now`/randomness in library code. Property tests use a seeded PRNG.

## Public types

### `SplitterPosition` (sealed) - the request

```dart
sealed class SplitterPosition {
  const SplitterPosition();
  const factory SplitterPosition.fraction(double value)     = FractionSplitterPosition;
  const factory SplitterPosition.startPixels(double extent) = StartPixelsSplitterPosition;
  const factory SplitterPosition.endPixels(double extent)   = EndPixelsSplitterPosition;

  /// Desired start-panel fraction for [available] logical px, before
  /// constraints. Always returns a finite value in [0, 1].
  double resolveFraction(double available);
}
```

- `fraction(v)` -> `v` clamped to [0, 1] (NaN/inf -> 0.5 fallback is wrong; clamp
  non-finite to 0). Decision: non-finite request -> 0.0 for pixels, and for
  fraction clamp via `clampFinite`. Document it.
- `startPixels(px)` at `available` -> `px / available` (available <= 0 -> 0).
- `endPixels(px)` at `available` -> `(available - px) / available`.
- Subclasses are public (needed for `switch`/pattern exhaustiveness and equality)
  with `==`/`hashCode`/`toString`. Each is `@immutable` and `const`.

### `SplitterPaneConstraints` - per pane, pixels

```dart
@immutable
class SplitterPaneConstraints {
  const SplitterPaneConstraints({
    this.minExtent = 0,
    this.maxExtent = double.infinity,
    this.collapsible = false,
    this.collapsedExtent = 0,
  });
  final double minExtent;       // >= 0
  final double maxExtent;       // >= minExtent, may be infinity
  final bool collapsible;
  final double collapsedExtent; // >= 0, the extent when collapsed
}
```

`maxExtent` is the "max pane size" feature. Asserts enforce the ordering;
`==`/`hashCode`/`copyWith`/`toString`.

### `SplitterConstraintPolicy` - infeasible tie-break

```dart
enum SplitterConstraintPolicy { favorStart, favorEnd, proportional }
```

Documented resolution hierarchy (highest wins):
1. Divider stays in `[0, available]`.
2. Collapse state honored.
3. Hard pane minimums (pixel + start fraction interval).
4. Hard pane maximums.
5. Requested fractional preference.
6. When 3 and 4 cannot both hold (cramped/infeasible), apply policy.

### `SplitterValue` / `SplitterChangeDetails` - the public payload

```dart
@immutable
class SplitterValue {
  const SplitterValue({
    required this.requestedPosition,
    required this.effectiveFraction,
    required this.startExtent,
    required this.endExtent,
    required this.availableExtent,
  });
  final SplitterPosition requestedPosition;
  final double effectiveFraction; // start/available, in [0,1]
  final double startExtent;       // logical px, >= 0
  final double endExtent;         // logical px, >= 0
  final double availableExtent;   // logical px, >= 0
}

enum SplitterChangeSource { drag, keyboard, semantics, programmatic, snap, collapse, restore }

@immutable
class SplitterChangeDetails extends SplitterValue {
  const SplitterChangeDetails({ ...super..., required this.source });
  final SplitterChangeSource source;
}
```

## The solver (private impl, public IO)

```dart
@immutable
class _SplitterSolver {
  const _SplitterSolver({
    required this.available,           // >= 0, already net of divider visual extent
    required this.start,               // SplitterPaneConstraints
    required this.end,                 // SplitterPaneConstraints
    this.minStartFraction = 0.0,       // today's minRatio
    this.maxStartFraction = 1.0,       // today's maxRatio
    this.policy = SplitterConstraintPolicy.favorStart,
    this.startCollapsed = false,
    this.endCollapsed = false,
  });

  _SplitterSolution solve(
    SplitterPosition requested, {
    double devicePixelRatio = 1.0,
    bool snapToDevicePixels = false,
  });
}
```

`_SplitterSolution { startExtent, endExtent, effectiveFraction, isCramped,
startCollapsed, endCollapsed }` (all finite, non-negative).

Algorithm:

1. `available <= 0` -> both extents 0, `effectiveFraction =
   requested.resolveFraction(0).clamp(0,1)`, `isCramped = !feasible`.
2. Collapse short-circuit: if `startCollapsed`, `startExtent =
   start.collapsedExtent.clamp(0, available)`; if `endCollapsed`, `endExtent =
   end.collapsedExtent.clamp(0, available)` and `startExtent = available - that`.
   Both collapsed -> start wins, remainder to end.
3. Legal start-extent interval (pixels):
   - `lo = max(start.minExtent, available*minStartFraction, available - end.maxExtent)` clamped to [0, available]
   - `hi = min(start.maxExtent, available*maxStartFraction, available - end.minExtent)` clamped to [0, available]
   - feasible iff `lo <= hi`.
4. `desired = requested.resolveFraction(available) * available`, sanitized finite,
   clamped to [0, available].
5. feasible -> `startExtent = desired.clamp(lo, hi)`.
6. infeasible -> policy:
   - `favorStart` -> `lo`
   - `favorEnd` -> `hi`
   - `proportional` -> `available * rawMinStart / (rawMinStart + rawMinEnd)` using
     the RAW configured `start.minExtent` / `end.minExtent` (not the clamped
     interval). This fixes the 83/17 -> 50/50 bug. Sum 0 -> 0.5.
7. Optional device-pixel snap: `startExtent = (startExtent*dpr).round()/dpr`, then
   re-clamp to `[lo, hi]` if feasible else `[0, available]`.
8. `endExtent = available - startExtent`; `effectiveFraction = available > 0 ?
   startExtent/available : effFromStep1`.

Never an inverted clamp (`lo`/`hi` are computed then a feasibility branch chosen),
never throws. NaN/inf requests are sanitized in step 4.

## Invariants (property-tested)

For all generated `(available, start, end, minStartFraction, maxStartFraction,
policy, requested, collapse, dpr)`:

- `startExtent`, `endExtent`, `effectiveFraction` are finite and `>= 0`.
- `startExtent + endExtent == available` (within 1e-6).
- `0 <= effectiveFraction <= 1`.
- feasible -> `lo - 1e-6 <= startExtent <= hi + 1e-6`, and every hard pixel/
  fraction constraint is honored.
- `solve` never throws for any finite-or-not input.
- monotonicity (feasible, non-collapsed): a larger requested fraction yields a
  `startExtent` that is `>=` the smaller request's (within epsilon).

## Tests (the lock)

- `test/foundation/split_position_test.dart` - each position resolves correctly
  across available sizes incl. 0 and non-finite inputs.
- `test/foundation/split_solver_property_test.dart` - seeded grid/random sweep of
  the invariants above (a few thousand cases).
- `test/foundation/split_solver_cases_test.dart` - targeted regressions: cramped
  favorStart/favorEnd, proportional 83/17 preservation, max-extent caps, collapse
  extents, device-pixel snap at dpr 1.25/1.5, infeasible-never-throws, the old
  `_SplitterMetrics` cramped expectation (start pinned at 100/174).

## Out of scope (later sub-projects)

The widget, render object, gestures/drag-from-effective, controller, and
animation. The foundation only makes the right model exist; the dead-zone and RTL
fixes consume `effectiveFraction`/extents in steps 2-3.

## Notes / decisions log

- Fractional caps stay a single start interval (`minStartFraction`/
  `maxStartFraction`), not per-pane: `end >= 30%` is `maxStartFraction = 0.7`.
- Solver is pre-wired for collapse now so step 7 does not rework it.
- Solver kept private (`_SplitterSolver`); its inputs/outputs are public. The
  widget/controller call it internally. Keeping it private avoids committing to a
  solver API surface in 2.0.
