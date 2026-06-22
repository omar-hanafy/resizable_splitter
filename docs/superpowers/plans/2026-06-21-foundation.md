# Foundation (solver + position/value model) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure model + constraint solver that makes the "stored != visible / inverted clamp / NaN reaches layout" bug class unrepresentable.

**Architecture:** New pure-Dart files under `lib/src/` (no Flutter widgets). A sealed `SplitterPosition` request type, per-pane `SplitterPaneConstraints`, a `SplitterConstraintPolicy`, a pure `SplitterSolver` that computes a `SplitterSolution` (extents + effective fraction + legal bounds), and the user-facing `SplitterValue`/`SplitterChangeDetails`. Solver is public-named but unexported; tests import the `src` file directly.

**Tech Stack:** Dart, `package:flutter/foundation.dart` (only `@immutable`), `flutter_test`.

## Global Constraints

- `public_member_api_docs` is an analyzer error: every public member needs `///` (applied to internal classes too, to be safe).
- `always_use_package_imports: error`; `prefer_single_quotes`; `prefer_const_constructors`.
- No em-dash characters anywhere (use `-` or `_`).
- Library code must not use `Date.now`/randomness; property tests use a seeded PRNG.
- Imports limited to `dart:math` + `package:flutter/foundation.dart` in foundation lib files. No `widgets`/`material`, no `BuildContext`, no `TextDirection`.
- This sub-project is purely additive: it must not modify the existing widget/controller/theme, and all 46 existing tests must remain green.

---

### Task 1: SplitterPosition (sealed request)

**Files:**
- Create: `lib/src/split_position.dart`
- Test: `test/foundation/split_position_test.dart`

**Interfaces:**
- Produces: `sealed class SplitterPosition` with const factories `.fraction(double)`, `.startPixels(double)`, `.endPixels(double)`; public subclasses `FractionSplitterPosition`, `StartPixelsSplitterPosition`, `EndPixelsSplitterPosition`; method `double resolveFraction(double available)` returning a finite value in `[0,1]`.

- [ ] Write failing tests: `fraction(0.3).resolveFraction(1000) == 0.3`; `fraction(2).resolveFraction(1000) == 1.0`; `fraction(double.nan).resolveFraction(1000) == 0.0`; `startPixels(280).resolveFraction(1000) == 0.28`; `startPixels(280).resolveFraction(0) == 0`; `endPixels(320).resolveFraction(1000) == 0.68`; equality + `toString` for each subtype.
- [ ] Run, verify fail.
- [ ] Implement: sealed base with `resolveFraction`; each subtype sanitizes non-finite to a finite value then clamps the result to `[0,1]`. `const`, `@immutable`, `==`/`hashCode`/`toString`.
- [ ] Run, verify pass. `dart format`.
- [ ] Commit.

### Task 2: SplitterPaneConstraints + SplitterConstraintPolicy

**Files:**
- Create: `lib/src/split_pane_constraints.dart`
- Test: `test/foundation/split_pane_constraints_test.dart`

**Interfaces:**
- Produces: `class SplitterPaneConstraints { const SplitterPaneConstraints({double minExtent = 0, double maxExtent = double.infinity, bool collapsible = false, double collapsedExtent = 0}); ... copyWith, ==, hashCode, toString }`; `enum SplitterConstraintPolicy { favorStart, favorEnd, proportional }`.

- [ ] Write failing tests: defaults; asserts reject `minExtent < 0`, `maxExtent < minExtent`, `collapsedExtent < 0`; `copyWith`/equality.
- [ ] Run, verify fail.
- [ ] Implement with asserts + value semantics + docs.
- [ ] Run, verify pass. Format.
- [ ] Commit.

### Task 3: SplitterSolver + SplitterSolution (the core)

**Files:**
- Create: `lib/src/split_solver.dart`
- Test: `test/foundation/split_solver_cases_test.dart`, `test/foundation/split_solver_property_test.dart`

**Interfaces:**
- Consumes: `SplitterPosition`, `SplitterPaneConstraints`, `SplitterConstraintPolicy`.
- Produces:
  - `class SplitterSolution { final double startExtent, endExtent, effectiveFraction, minStartExtent, maxStartExtent; final bool isCramped, startCollapsed, endCollapsed; }` (all finite, `>= 0`).
  - `class SplitterSolver { const SplitterSolver({required double available, required SplitterPaneConstraints start, required SplitterPaneConstraints end, double minStartFraction = 0, double maxStartFraction = 1, SplitterConstraintPolicy policy = SplitterConstraintPolicy.favorStart, bool startCollapsed = false, bool endCollapsed = false}); SplitterSolution solve(SplitterPosition requested, {double devicePixelRatio = 1, bool snapToDevicePixels = false}); }`

- [ ] Cases tests (write first, verify fail):
  - cramped favorStart: available 174, start.min 100, end.min 100 -> `startExtent == 100`, `effectiveFraction closeTo(100/174)`, `isCramped`.
  - cramped favorEnd: same -> `startExtent == 74`.
  - proportional preserves 83/17: available 100, start.min 1000, end.min 200, policy proportional -> `startExtent closeTo(100*1000/1200)` (not 50).
  - maxExtent cap: available 1000, start.max 300, request fraction 0.9 -> `startExtent == 300`.
  - collapse: available 1000, startCollapsed, start.collapsedExtent 48 -> `startExtent == 48`, `endExtent == 952`.
  - device-pixel snap dpr 1.5: a fractional desired -> `startExtent*1.5` is integral.
  - infeasible never throws + sum invariant: `startExtent + endExtent == available`.
  - `available == 0` -> both 0, no throw.
- [ ] Property test (write, verify fail): seeded PRNG, ~4000 cases over random available/constraints/fractions/policy/position/collapse/dpr asserting: finite + `>= 0`; `start+end == available` within 1e-6; `effectiveFraction in [0,1]`; feasible -> `lo-1e-6 <= startExtent <= hi+1e-6`; never throws.
- [ ] Run both, verify fail.
- [ ] Implement solver per spec algorithm (collapse short-circuit; compute `lo`/`hi`; feasible clamp vs policy; raw minima for `proportional`; optional dpr snap; finite sanitization). Docs on all public members.
- [ ] Run, verify pass. Format.
- [ ] Commit.

### Task 4: SplitterValue + SplitterChangeDetails + SplitterChangeSource

**Files:**
- Create: `lib/src/split_view_value.dart`
- Test: `test/foundation/split_view_value_test.dart`

**Interfaces:**
- Consumes: `SplitterPosition`.
- Produces: `class SplitterValue { const SplitterValue({required SplitterPosition requestedPosition, required double effectiveFraction, required double startExtent, required double endExtent, required double availableExtent}); ==, hashCode, toString, copyWith }`; `enum SplitterChangeSource { drag, keyboard, semantics, programmatic, snap, collapse, restore }`; `class SplitterChangeDetails extends SplitterValue { const SplitterChangeDetails({...super, required SplitterChangeSource source}); }`.
- [ ] Failing tests: construction, equality incl. `source`, `copyWith`.
- [ ] Run, verify fail.
- [ ] Implement with docs + value semantics.
- [ ] Run, verify pass. Format.
- [ ] Commit.

### Task 5: Export the user-facing types + full green

**Files:**
- Modify: `lib/resizable_splitter.dart` (add exports for `split_position.dart`, `split_pane_constraints.dart`, `split_view_value.dart`; NOT `split_solver.dart`).

**Interfaces:**
- Produces: public API now includes `SplitterPosition` (+ subtypes), `SplitterPaneConstraints`, `SplitterConstraintPolicy`, `SplitterValue`, `SplitterChangeDetails`, `SplitterChangeSource`.
- [ ] Add the three `export` lines.
- [ ] Run `dart analyze` (full) -> No issues.
- [ ] Run `flutter test` -> all green (existing 46 + new foundation tests).
- [ ] `dart format .`
- [ ] Commit.

## Self-Review

- Spec coverage: position (T1), constraints+policy (T2), solver+invariants (T3), value+source (T4), exports (T5). All spec sections covered.
- Placeholders: none; signatures and key cases are concrete.
- Type consistency: `SplitterSolution` field names (`startExtent`, `endExtent`, `effectiveFraction`, `minStartExtent`, `maxStartExtent`, `isCramped`, `startCollapsed`, `endCollapsed`) used consistently; `resolveFraction` signature stable across tasks.
