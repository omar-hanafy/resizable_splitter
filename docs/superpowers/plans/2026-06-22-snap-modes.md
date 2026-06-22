# Snap Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, autonomous). Steps use checkbox (`- [ ]`) syntax. Algorithm detail lives in the companion spec `docs/superpowers/specs/2026-06-22-snap-modes-design.md`; this plan locks file structure, ordering, interfaces, and the test matrix.

**Goal:** Add `magnetic` and `sticky` live snap modes alongside the current release-only snapping, via a sealed `SplitterSnapBehavior` hierarchy and a pure snap engine, integrated into the drag path.

**Architecture:** A sealed value-type hierarchy (`ReleaseSnap` / `MagneticSnap` / `StickySnap`) replaces the concrete `SplitterSnapBehavior`, with back-compat body factories. A new pure, non-exported engine (`SnapResolver` + `magneticPull` + `stickyStep`) holds all snap math, unit-tested without widgets. `split_handle.dart` orchestrates: it captures the behavior in the drag session, transforms the raw pointer fraction per mode in `_onDragUpdate`, and commits through a single `_settle` path.

**Tech Stack:** Dart/Flutter, `flutter_test`, `very_good_analysis` lints.

## Global Constraints

- Lint: `very_good_analysis`; `dart format .` before finishing; package imports only (no relative).
- `public_member_api_docs` is enforced - every public member in `lib/` needs dartdoc. Engine types: document them and do NOT export from the barrel (use `@internal` only if `meta` is already a direct dep).
- Never use the `-` em-dash character (`—`); use `-` or `_`.
- Backward compatibility: existing `SplitterSnapBehavior(points: ...)` must keep compiling and behaving as release snapping.
- Live modes (`MagneticSnap`/`StickySnap`) must bypass `SplitterController.updateRatio`'s default `threshold: 0.002`.
- Keep `flutter analyze` clean and `flutter test` green at every checkpoint.
- Do NOT commit or publish (no explicit request); leave the tree green for review.

## File Structure

- Modify: `lib/src/split_snap_behavior.dart` - sealed base + `ReleaseSnap`/`MagneticSnap`/`StickySnap`, body factories, per-subtype `copyWith`/`==`/`hashCode`.
- Create: `lib/src/split_snap_engine.dart` - `ResolvedSnapPoint`, `SnapResolver`, `magneticPull`, `stickyStep`, `StickyStep` result. Standalone library; not exported.
- Modify: `lib/src/resizable_splitter.dart` - add `import '.../split_snap_engine.dart';`.
- Modify: `lib/src/split_handle.dart` - session.snap, state fields, `didUpdateWidget`, `_onDragUpdate`, `_writeExactDragRequest`, `_applyLiveSnap`, `_settle`, pure `_maybeSnap`.
- Modify: `lib/src/split_change_details.dart` - `SplitterChangeSource.snap` doc.
- Modify: `lib/src/resizable_splitter.dart` - `snap` field dartdoc (mention modes) near line 244.
- Create: `test/foundation/split_snap_behavior_test.dart`
- Create: `test/foundation/split_snap_engine_test.dart`
- Create: `test/snap_modes_drag_test.dart`
- Modify: `CHANGELOG.md` - one entry (invoke changelog-discipline).

---

### Task 1: Sealed `SplitterSnapBehavior` hierarchy

**Files:** Modify `lib/src/split_snap_behavior.dart`; Test `test/foundation/split_snap_behavior_test.dart`.

**Interfaces produced:**
- `sealed class SplitterSnapBehavior` with concrete fields `List<double> points`, `double tolerance`, `double? pixelTolerance`; abstract `copyWith({Iterable<double>? points, double? tolerance, Object? pixelTolerance})`.
- Body factories: `SplitterSnapBehavior({required points, tolerance=0.02, pixelTolerance})` -> `ReleaseSnap`; `.release({...})`; `.magnetic({..., strength=0.5})`; `.sticky({..., escapeFactor=1.5})`.
- `final class ReleaseSnap`, `final class MagneticSnap` (`double strength`, assert `0<strength<=1`), `final class StickySnap` (`double escapeFactor`, assert `escapeFactor>1`). Each: subtype `copyWith` (covariant return), `==`/`hashCode` requiring same runtime subtype, `toString`.

**Steps:**
- [ ] Write failing tests: back-compat `SplitterSnapBehavior(points:[0.5])` is a `ReleaseSnap` with tolerance 0.02; `.magnetic`/`.sticky` defaults; base-typed `SplitterSnapBehavior b = ...; b.copyWith(tolerance: .1)` keeps subtype; `MagneticSnap.copyWith(strength:.8)`; equality across subtypes differs; `points` is unmodifiable; assertions (`strength` range, `escapeFactor>1`) throw; `SplitterSnapBehavior.new` tear-off compiles.
- [ ] Run -> fail.
- [ ] Implement the sealed hierarchy per spec "API design".
- [ ] Run -> pass. `dart analyze lib/src/split_snap_behavior.dart test/foundation/split_snap_behavior_test.dart` clean.
- [ ] Grep `SplitterSnapBehavior(` across `lib/`, `test/`, `example/`; fix any call site that breaks (should be none for the unnamed factory).
- [ ] Checkpoint: full `flutter test` green.

### Task 2: `SnapResolver` engine

**Files:** Create `lib/src/split_snap_engine.dart`; Modify `lib/src/resizable_splitter.dart` (import); Test `test/foundation/split_snap_engine_test.dart`.

**Interfaces produced:**
- `class ResolvedSnapPoint { int index; double nominalFraction; double effectiveFraction; double coordinate; double distance; }`
- `class SnapResolver { SnapResolver(SplitterSnapBehavior behavior, SplitterSolver solver); double get radius; ResolvedSnapPoint? nearest(double pointerFraction); ResolvedSnapPoint resolveAt(int index); List<ResolvedSnapPoint> resolveSortedDistinct(double pointerFraction); }`
- Behavior: `usePixels = pixelTolerance != null`; `coordinate` = `solution.startExtent` (pixel) or `effectiveFraction` (ratio); pointer mapped to the same space; `distance` in that space; tie-break `<` (first-point-wins). `nearest`/`resolveAt` compute via `solver.solve(SplitterPosition.fraction(point))`.

**Steps:**
- [ ] Write failing tests against a hand-built `SplitterSolver` (available e.g. 400, no constraints, and a constrained variant with a `start.minExtent`): `nearest` returns first-point-wins on ties; pixel-mode distance uses `startExtent`; `resolveAt` re-resolves a constrained point to its pushed-aside position; `resolveSortedDistinct` de-dups coincident points keeping first index.
- [ ] Run -> fail (file/types absent).
- [ ] Implement engine; add import to `lib/src/resizable_splitter.dart`. Document public members (no barrel export).
- [ ] Run -> pass; `dart analyze lib/src/split_snap_engine.dart` clean.
- [ ] Checkpoint: `flutter test` green.

### Task 3: `magneticPull` (pure, Voronoi-clipped)

**Files:** Modify `lib/src/split_snap_engine.dart`; Test `test/foundation/split_snap_engine_test.dart`.

**Interfaces produced:**
- `double magneticPull({required double pointer, required SnapResolver resolver, required double strength})` - returns the attracted effective fraction. Uses `resolveSortedDistinct` to clip `effectiveRadius = min(radius, halfDistanceToNeighborOnPointerSide)`; `t = clamp(1 - d/effectiveRadius, 0, 1)`; `return pointer + (point - pointer) * strength * t`. Returns `pointer` unchanged when no points or `d >= effectiveRadius`.

**Steps:**
- [ ] Write failing tests: at the point (d=0) returns ~point*strength-weighted (verify formula); at/just beyond radius returns pointer (continuity at edge); **overlap continuity**: points `[0.4,0.6]`, radius 0.2, strength 0.5 - sample pointer at 0.499 and 0.501, assert `|f(0.501)-f(0.499)|` is tiny (< a small epsilon), proving no jump across the midpoint; strength scaling monotonic.
- [ ] Run -> fail.
- [ ] Implement `magneticPull`.
- [ ] Run -> pass.
- [ ] Checkpoint: `flutter test` green.

### Task 4: `stickyStep` (pure, capture/escape/recapture by index)

**Files:** Modify `lib/src/split_snap_engine.dart`; Test `test/foundation/split_snap_engine_test.dart`.

**Interfaces produced:**
- `class StickyStep { double requestFraction; SplitterChangeSource source; int? capturedIndex; }`
- `StickyStep stickyStep({required double pointer, required int? capturedIndex, required SnapResolver resolver, required double escapeFactor})`:
  - if captured: re-resolve `resolveAt(capturedIndex)`; if `distance <= radius*escapeFactor` -> hold (`requestFraction = nominalFraction`, `source = snap`, keep index); else release (index = null) and fall through.
  - then `nearest(pointer)`; if within `radius` -> capture (`requestFraction = nominalFraction`, `source = snap`, index = found).
  - else `requestFraction = pointer`, `source = drag`, index = null.

**Steps:**
- [ ] Write failing tests: capture exactly at `d == radius`; hold at `d == radius*escapeFactor`; escape just beyond; **same-update recapture** (start captured on A, pointer leaps into B's radius beyond A's escape -> result captures B, source snap, index B); returns nominal fraction (not resolved) for a constrained point; uncaptured between points returns pointer/drag.
- [ ] Run -> fail.
- [ ] Implement `stickyStep`.
- [ ] Run -> pass.
- [ ] Checkpoint: `flutter test` green.

### Task 5: Handle integration

**Files:** Modify `lib/src/split_handle.dart`; Test `test/snap_modes_drag_test.dart`.

**Interfaces consumed:** Task 1 subtypes; Task 2-4 engine functions; `SplitterController.jumpTo`, `value.position`, `value.collapsedPane`.

**Changes (per spec "Integration"):**
- `_DragSession`: add `final SplitterSnapBehavior? snap;`; set from `widget.snap` in `_onDragStart`.
- Replace `double? _lastDragRatio` with `double? _lastDragRequestFraction;`, add `SplitterChangeSource? _lastDragSource;`, `int? _stickyCapturedIndex;`. Reset all in `_onDragStart` and `_teardown`.
- `didUpdateWidget`: add `|| session.snap != widget.snap` to the interruption condition.
- Add `_writeExactDragRequest(SplitterController, double)` (guarded `jumpTo`).
- Add `_LiveSnapResult { double requestFraction; SplitterChangeSource source; }` and `_applyLiveSnap(double rawPointer, _ResolvedGeometry geometry, SplitterSnapBehavior? snap)` switching on the sealed type (null/Release -> drag passthrough; Magnetic -> `magneticPull`; Sticky -> `stickyStep`, updating `_stickyCapturedIndex`).
- `_onDragUpdate`: apply `_applyLiveSnap`; store request/source; deferred -> `session.onPreviewChanged?.call(request)`; live -> exact write for Magnetic/Sticky else `updateRatio`; fire `onChanged(source)` when visible fraction moved.
- Refactor `_maybeSnap` to a pure selection (no writes/callbacks) used only for `ReleaseSnap` in `_settle`.
- `_settle`: single commit path per spec (release candidate when `ReleaseSnap`; otherwise commit `_lastDragRequestFraction`); exact write; correct `source`.

**Steps:**
- [ ] Write failing widget tests (`test/snap_modes_drag_test.dart`): magnetic push-through commits a value strictly between two points (not pinned) and no jump on release; sticky drag within radius commits exactly the point; sticky holds through small moves then escapes; deferred + sticky previews then commits the nominal point; container resize mid-sticky-capture keeps the divider on the point (pump a resize, no new pointer event); live-mode lands exactly despite the 0.002 threshold; `onChanged` source is `snap` on sticky capture and `drag` on escape; `snapToPhysicalPixels` commits whole-pixel extents under magnetic+sticky; mid-drag `snap` change interrupts (no onChangeEnd, capture cleared).
- [ ] Run -> fail.
- [ ] Implement the integration above.
- [ ] Run -> pass.
- [ ] Run the full suite incl. existing `test/snap_pixel_tolerance_test.dart`, `test/pixel_snap_consistency_test.dart`, `test/resizable_splitter_drag_test.dart`, `test/deferred_resize_test.dart` -> all green (regression gate).
- [ ] Checkpoint: `flutter analyze` clean.

### Task 6: Docs + CHANGELOG

**Files:** Modify `lib/src/split_change_details.dart`, `lib/src/resizable_splitter.dart` (snap field doc), `CHANGELOG.md`.

**Steps:**
- [ ] Update `SplitterChangeSource.snap` dartdoc to cover a live sticky capture as well as a release-mode settle.
- [ ] Update `ResizableSplitter.snap` field dartdoc (around line 244) to describe the three modes briefly and that `null` means no snapping.
- [ ] Add dartdoc to all new public members (subtypes, factories) - behavior-first per flutter-docs style.
- [ ] Invoke changelog-discipline; add one user-facing entry describing magnetic/sticky modes and the breaking seal (major bump recommended).
- [ ] `dart format .`; `flutter analyze` clean; `flutter test` green.

## Self-Review

- Spec coverage: modes (T1,T3,T4,T5), API shape (T1), engine/resolver (T2), Voronoi (T3), sticky-by-index + recapture (T4), threshold bypass + single commit + source policy + deferred + pixel + interruption (T5), docs/changelog/versioning (T6). Non-goals (collapse snapping, feedback, keyboard, alt-suppress) intentionally absent.
- Placeholder scan: algorithms are in the spec by reference; test matrix is concrete. No TBDs.
- Type consistency: `requestFraction`/`source`/`capturedIndex`, `effectiveFraction`/`coordinate`/`distance`, `magneticPull`/`stickyStep`/`SnapResolver` used consistently T2-T5.
- Example app demo: deferred to a follow-up (not required for a green, complete library change); noted in summary.
