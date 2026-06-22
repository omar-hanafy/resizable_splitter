# Snap Modes - Design

Status: accepted (revised after external review)
Date: 2026-06-22

## Summary

Today snapping is release-only: the divider follows the pointer freely during a
drag and, on release, jumps to the nearest snap point if it landed within
tolerance (`_maybeSnap` runs only from `_settle`). The visible post-release jump
is the one wart - it can feel like the app overriding the user.

This adds two live snap modes alongside the current one, exposed through a sealed
`SplitterSnapBehavior` hierarchy:

- `release` - today's behavior; the backward-compatible default.
- `magnetic` - a continuous pull toward points during the drag that the pointer
  can always push through. No post-release correction.
- `sticky` - a discrete capture at each point with hysteresis (escape radius >
  capture radius), so it does not flicker at the boundary.
- `none` - expressed as `snap: null`, already supported. Not a subtype.

`magnetic` is the showcase feel (the macOS draggable-divider feel: gently
attracted, push-through, release never forced-corrects). `sticky` is the best fit
for discrete preset stops and edge stops (25 / 50 / 75, or near 0% / 100%).

## Goals

- Add `magnetic` and `sticky` live modes with a precise, jitter-free feel.
- Keep every existing call site source-compatible.
- Reuse the existing solve-in-effective-space machinery so snap points respect
  pane constraints exactly as they do today.
- Make illegal states unrepresentable (escape radius only on sticky, strength only
  on magnetic).

## Non-goals (deferred)

- True pane collapse snapping. A point at `0` / `1` resolves through the normal
  uncollapsed solver, so with a pane minimum it lands at the minimum, not a real
  collapse - it does not set `controller.collapsedPane`, bypass the minimum, or get
  `expand()` restoration. Real collapse snapping needs a richer point model
  (`SplitterSnapPoint.collapseStart()` etc.) and is its own design.
- Haptic-on-capture and ghost-line preview indicators. `magnetic`/`sticky` carry
  their feedback in the divider's own motion; the feedback layer mainly helps
  `release` and can be added later without touching this API.
- Keyboard arrow-key snapping to points.
- A "hold Alt/Option to suppress snapping" override.
- Animated release-time completion for `magnetic`.

## The modes

All modes share the existing radius fields: `tolerance` (effective ratio, default
`0.02`) and the optional `pixelTolerance` (logical pixels; takes precedence).
These define the radius of influence / capture. Snap points are resolved through
`solver.solve(SplitterPosition.fraction(p))` so a point that constraints push
aside is matched by where it actually lands.

Coordinate space: when `pixelTolerance` is set, distances are measured in logical
pixels using `solution.startExtent` (the physically snapped extent), and the
pointer in pixels is `pointerFraction * available`. Otherwise everything is in
effective-fraction space. Ties are first-point-wins (`<`, not `<=`, when replacing
the current best - matching today's `_maybeSnap`).

Let `pointer` be the raw, constraint-clamped effective fraction the drag would
produce (`session.fractionFor(...)`). For the nearest point, `point` is its
resolved effective fraction, `d` its distance in the active space, `radius` the
active tolerance.

### release (unchanged)

During drag the divider tracks the pointer 1:1. On release, `_settle` snaps to the
nearest point if `d <= radius`. This preserves today's behavior exactly.

### magnetic

During drag, for the nearest point, with the radius clipped to the Voronoi
boundary (see below):

```
t = clamp(1 - d / effectiveRadius, 0, 1)   // 1 at the point, 0 at the edge
pull = strength * t
rendered = pointer + (point - pointer) * pull
```

- At the edge (`t = 0`) there is zero pull, so the function is continuous - no
  jitter, no hysteresis needed.
- Near the point the divider leads toward it; because the pull fades as the
  pointer moves away, the pointer always wins (push-through).
- `strength` in `(0, 1]`, default `0.5`. It never fully captures, so magnetic
  never lands exactly on a point unless the pointer is on it - intentional for an
  advisory pull.
- On release, magnetic commits the divider's visible (attracted) position. There
  is deliberately no release-time correction - that is the whole point of the mode.

Overlap handling (required for continuity): when two influence zones overlap, the
naive nearest-point pull is discontinuous at the midpoint - the chosen point flips
and the pull direction reverses, producing a visible jump (e.g. points 0.4 / 0.6,
radius 0.2, strength 0.5 jumps ~0.07 across 0.5). Fix: clip the radius to half the
distance to the nearest neighbor on the side the pointer is on, so the pull tapers
to zero before the nearest-point identity changes:

```
effectiveRadius = min(radius, halfDistanceToNeighborOnPointerSide)
```

At the midpoint `d == effectiveRadius`, so `t == 0` from both sides: continuous.
Points whose resolved positions coincide are de-duplicated (first configured point
keeps identity).

### sticky

During drag, with a captured-point **index** held across updates (not a resolved
fraction - see below):

- Capture: when not captured and `d <= radius`, capture that point's index;
  `rendered = point`.
- Hold: while captured, `rendered = point` until the pointer leaves the escape
  radius.
- Escape: when `d > escapeRadius` (`escapeRadius = escapeFactor * radius`,
  `escapeFactor > 1`), release the capture, then immediately attempt a fresh
  capture in the same update (so a high-velocity drag that leaps from one zone into
  another snaps on the same frame rather than going unsnapped).

Hysteresis (escape > capture) is what stops the boundary flicker a single
threshold would cause.

Capture by index, request the nominal fraction: the captured state is the point's
*index*, re-resolved through the live solver each update (`resolveAt(index)`); the
written request is the point's *nominal* fraction. This is what makes capture
survive a mid-drag container resize: if point `0.1` is pushed to `0.2` by a pane
minimum and the container then grows enough that `0.1` becomes legal, re-solving
the index tracks it, and writing the nominal `0.1` lets the controller (live) or
the render object (deferred) re-resolve the point on the next layout even with no
new pointer event. Storing the resolved `0.2` would strand the divider.

## API design

`SplitterSnapBehavior` becomes a sealed base with three final subtypes and **body**
factory constructors (not redirecting - redirecting factories cannot declare their
own default values in Dart). The unnamed factory preserves the current signature
and returns a `ReleaseSnap`, so existing code keeps compiling unchanged.

```dart
@immutable
sealed class SplitterSnapBehavior {
  SplitterSnapBehavior._({
    required Iterable<double> points,
    required this.tolerance,
    required this.pixelTolerance,
  })  : points = List<double>.unmodifiable(points),
        assert(tolerance >= 0),
        assert(pixelTolerance == null || pixelTolerance >= 0);

  // Backward-compatible: existing SplitterSnapBehavior(points: ...) -> ReleaseSnap.
  factory SplitterSnapBehavior({
    required Iterable<double> points,
    double tolerance,
    double? pixelTolerance,
  }) = ... // body factory returning ReleaseSnap

  factory SplitterSnapBehavior.release({ ... }) = ...        // explicit spelling
  factory SplitterSnapBehavior.magnetic({ ..., double strength });
  factory SplitterSnapBehavior.sticky({ ..., double escapeFactor });

  final List<double> points;       // shared, unmodifiable
  final double tolerance;          // shared
  final double? pixelTolerance;    // shared

  // Stays on the base: variables may be statically typed SplitterSnapBehavior.
  SplitterSnapBehavior copyWith({
    Iterable<double>? points,
    double? tolerance,
    Object? pixelTolerance = _noUpdate,
  });
}

final class ReleaseSnap extends SplitterSnapBehavior { ... }
final class MagneticSnap extends SplitterSnapBehavior {
  final double strength;   // assert strength > 0 && strength <= 1
  @override MagneticSnap copyWith({ ..., double? strength });
}
final class StickySnap extends SplitterSnapBehavior {
  final double escapeFactor;   // assert escapeFactor > 1
  @override StickySnap copyWith({ ..., double? escapeFactor });
}
```

Defaults: `tolerance = 0.02`, `strength = 0.5`, `escapeFactor = 1.5`.

Notes:
- Shared fields are concrete on the base (set via the private constructor), so
  `behavior.points` etc. work everywhere.
- `points` keeps its defensive `List.unmodifiable` copy (the reason the
  constructor is not `const`).
- `copyWith` is abstract on the base, overridden per subtype with a covariant
  subtype return and the subtype-specific param. `==`/`hashCode` are per subtype
  and require the same runtime subtype. `ReleaseSnap.toString()` keeps the legacy
  `SplitterSnapBehavior(...)` prefix is not required, but its fields match.

## Internal snap engine

A new internal file `lib/src/split_snap_engine.dart` (types `@internal`, not
re-exported by the barrel, directly unit-testable) holds the pure resolver shared
by all modes:

```dart
@internal
final class ResolvedSnapPoint {
  final int index;
  final double nominalFraction;
  final double effectiveFraction;
  final double coordinate;   // effectiveFraction in ratio mode, startExtent in pixel mode
  final double distance;
}

@internal
final class SnapResolver {
  SnapResolver(SplitterSnapBehavior behavior, SplitterSolver solver);
  double get radius;                                   // active tolerance
  ResolvedSnapPoint? nearest(double pointerFraction);  // null if no points
  ResolvedSnapPoint resolveAt(int pointIndex);
  List<ResolvedSnapPoint> resolveSortedDistinct(double pointerFraction); // for Voronoi clip
}
```

The resolver is the single place that calls `solver.solve(...)` per point, mirroring
the existing `_maybeSnap` loop. It performs no controller writes and no callbacks.

## Integration (split_handle.dart)

1. `_DragSession` gains `final SplitterSnapBehavior? snap;`, initialized from
   `widget.snap` at `_onDragStart`, so the behavior is stable for the gesture.

2. `didUpdateWidget` interruption check (currently controller/axis/deferred/
   resizable) also interrupts on `session.snap != widget.snap`. Value-type equality
   means a rebuilt-but-equivalent behavior does not interrupt; a real mode/points/
   param change does (so a sticky capture is never reinterpreted against a new
   point list mid-gesture).

3. State fields replace `_lastDragRatio`:
   - `double? _lastDragRequestFraction;` - what was written to the controller/preview.
   - `SplitterChangeSource? _lastDragSource;`
   - `int? _stickyCapturedIndex;`
   Reset all three in `_onDragStart` and `_teardown` where `_lastDragRatio` was.

4. `_onDragUpdate`: after `rawPointer = session.fractionFor(...)`, run
   `applied = _applyLiveSnap(rawPointer, geometry, session.snap)` returning a small
   `_LiveSnapResult { requestFraction, source }`. Dispatch exhaustively on the
   sealed type:
   - `null` / `ReleaseSnap` -> `(rawPointer, drag)` (release handled at settle).
   - `MagneticSnap` -> Voronoi-clipped continuous pull, source `drag`.
   - `StickySnap` -> capture/escape via `_stickyCapturedIndex`; source `snap` when
     captured/recaptured, else `drag`.
   Record `_lastDragRequestFraction`/`_lastDragSource`. Then:
   - deferred: `session.onPreviewChanged?.call(applied.requestFraction)` (use the
     session callback, not `widget.onPreviewChanged`).
   - live: write exactly for magnetic/sticky (bypass the `0.002` threshold), else
     `updateRatio(applied.requestFraction)` for release/null to preserve legacy
     chattiness behavior; fire `onChanged` with `applied.source` if the visible
     fraction changed.

5. Exact write helper (bypasses the threshold; converts a pixel pin to a fraction):
   ```dart
   void _writeExactDragRequest(SplitterController c, double fraction) {
     final clamped = fraction.clamp(0.0, 1.0).toDouble();
     final pos = SplitterPosition.fraction(clamped);
     if (c.value.position != pos || c.value.collapsedPane != null) c.jumpTo(pos);
   }
   ```

6. `_settle` becomes the single commit path. `_maybeSnap` is refactored to a pure
   selection via `SnapResolver` (no writes/callbacks). On release:
   - start from `request = _lastDragRequestFraction ?? _effective`,
     `source = _lastDragSource ?? drag`.
   - if `session.snap is ReleaseSnap` and the nearest point is within tolerance,
     set `request = candidate.effectiveFraction`, `source = snap`.
   - `_writeExactDragRequest(...)`, fire `onChanged` if the visible fraction moved,
     return a `committed` end with `source`.
   This preserves release semantics (snap source on a claimed release; exact final
   commit otherwise) and gives magnetic WYSIWYG / sticky nominal-point commits for
   free (their request is already in `_lastDragRequestFraction`).

7. Composition:
   - `deferredResize`: the snapped/attracted request flows into the preview; commit
     happens on release. Sticky's nominal request lets the render object re-resolve
     the point through a resize.
   - `snapToPhysicalPixels`: unchanged - applied inside `solver.solve`, which runs
     when resolving point positions (pixel-mode metric uses `solution.startExtent`).

8. Theme: no change. Snap is a widget prop; only the unrelated
   `snapToPhysicalPixels` is themed.

## Callback-source policy

- magnetic motion: `drag`.
- sticky capture / recapture transition: `snap`. Held position: no new callback
  unless the visible fraction changes. Escape: `drag`.
- release-time snap: `snap`. `onChangeEnd` is `snap` when the committed state is a
  sticky capture or a release snap, else `drag`.
- deferred mode keeps suppressing `onChanged` during the drag; it reports the final
  source once on release.

Update the `SplitterChangeSource.snap` doc from "Settling onto a snap point at the
end of a drag" to cover a live sticky capture as well as a release-mode settle.

## Edge cases and invariants

- Empty `points` or non-positive available space: live transform is a no-op
  (returns the raw pointer), matching `_maybeSnap`'s guards.
- Coincident resolved points: de-duplicated; first configured point wins identity.
- Magnetic with dense/overlapping points: continuous via Voronoi clipping (tested).
- Sticky across a mid-drag resize: tracked by index + nominal request (tested).
- Interrupt / cancel / dispose: `_teardown` clears `_stickyCapturedIndex` and the
  request/source fields; no commit, no snap (unchanged contract).

## Testing

Foundation (pure, against `SnapResolver` and the transforms):
- Legacy `SplitterSnapBehavior(points: ...)` constructs a `ReleaseSnap`; base-typed
  `copyWith` callable; factory defaults; subtype equality/hashCode; unmodifiable
  points; `SplitterSnapBehavior.new` tear-off still works.
- Magnetic values at the point, the boundary, the midpoint, several strengths;
  continuity immediately on both sides of an overlapping-point midpoint.
- Sticky capture at `d == radius`, hold at `d == escapeRadius`, escape just beyond;
  high-velocity escape + same-update recapture.
- Pixel-mode metric uses `startExtent`; `escapeFactor` boundary.

Widget (drag):
- Magnetic push-through (commit passes through a point, not pinned) and no
  release-time layout change.
- Sticky captures within radius, holds, releases only past escape; captured nominal
  point tracks a container resize with no new pointer event; deferred preview
  tracks the same resize.
- Live modes bypass the `0.002` threshold (sticky lands exactly).
- Source policy: sticky capture emits `snap`, escape emits `drag`, release does not
  duplicate `onChanged`.
- `snapToPhysicalPixels` yields whole-physical-pixel extents under all three modes.
- Cancel / configuration-change interruption clears `_stickyCapturedIndex` without
  committing.

Regression: existing release-snap tests (`snap_pixel_tolerance_test.dart`,
`pixel_snap_consistency_test.dart`) pass unchanged via the back-compat factory.

## Migration and versioning

- Source-compatible for the common case: `SplitterSnapBehavior(points: ...)` still
  constructs (now a `ReleaseSnap`); field access and `release`-shaped `copyWith`
  unchanged.
- One genuine breaking aspect: sealing a previously-concrete public class breaks any
  external code that `extends`/`implements` it (unusual for a value type). Warrants
  a major version bump and a CHANGELOG note. (Releasing/publishing is gated on the
  maintainer; this change documents the bump rather than performing it.)
- Example app: add a `magnetic` showcase and a `sticky` preset-stops demo.

## Review reconciliation (external review, 2026-06-22)

Verified each claim against the codebase before accepting. All checked claims held;
nothing required pushback.

Accepted as correctness fixes:
- Magnetic overlap discontinuity is real (verified by working the math); added
  Voronoi radius-clipping. My earlier "dense points need no handling" was wrong.
- Sticky must capture by index and write the nominal fraction, or the documented
  resize-survival invariant does not actually hold.
- Live modes must bypass `updateRatio`'s default `threshold: 0.002` (confirmed at
  `split_controller.dart:193`) or sticky cannot land exactly and magnetic's
  committed value lags the visible one.
- `copyWith` must remain on the sealed base (base-typed variables call it).
- Body factories required (redirecting factories cannot declare default values).
- `escapeFactor > 1` strict (==1 disables hysteresis, contradicting escape>capture).
- Sticky edge points are not true collapse (verified: a `0`/`1` point routes through
  the uncollapsed solver). Reworded; collapse-snapping moved to non-goals.
- Pure resolver + single commit path; same-update recapture; pixel metric via
  `startExtent`; `<` tie-break; interrupt on `session.snap` change; session-captured
  preview callback.

Verified APIs the review relied on: `jumpTo` (`split_controller.dart:188`),
`value.position` (`:161`), `value.collapsedPane` (`:207`), the `0.002` threshold
(`:193`), the `didUpdateWidget` interruption set (`split_handle.dart:332`).

Owned deviations (reversible, my call under autonomy): adopted the review's internal
names (`SnapResolver`, `ResolvedSnapPoint`, `_LiveSnapResult`, `_stickyCapturedIndex`,
`_lastDragRequestFraction`, `split_snap_engine.dart`); exact writes via a guarded
`jumpTo` helper.
