import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/model/split_change_details.dart';
import 'package:resizable_splitter/src/model/split_pane_constraints.dart';
import 'package:resizable_splitter/src/solver/split_snap_behavior.dart';
import 'package:resizable_splitter/src/solver/split_snap_engine.dart';
import 'package:resizable_splitter/src/solver/split_solver.dart';

/// An unconstrained solver over 400px: nominal fractions resolve unchanged.
const _free = SplitterSolver(
  available: 400,
  start: SplitterPaneConstraints(),
  end: SplitterPaneConstraints(),
);

/// The start pane has a 200px minimum, so any point below 0.5 is pushed to 0.5.
const _minStart = SplitterSolver(
  available: 400,
  start: SplitterPaneConstraints(minExtent: 200),
  end: SplitterPaneConstraints(),
);

void main() {
  group('SnapResolver.nearest', () {
    test('returns the closest point in ratio space', () {
      final r = SnapResolver(
        SplitterSnapBehavior(points: const [0.25, 0.75]),
        _free,
      );
      final near = r.nearest(0.3)!;
      expect(near.index, 0);
      expect(near.effectiveFraction, closeTo(0.25, 1e-9));
      expect(near.nominalFraction, 0.25);
      expect(near.distance, closeTo(0.05, 1e-9));
    });

    test('breaks ties toward the first configured point', () {
      final r = SnapResolver(
        SplitterSnapBehavior(points: const [0.4, 0.6]),
        _free,
      );
      expect(r.nearest(0.5)!.index, 0);
    });

    test('measures distance in pixels when pixelTolerance is set', () {
      final r = SnapResolver(
        SplitterSnapBehavior(points: const [0.25], pixelTolerance: 30),
        _free,
      );
      // point 0.25 -> startExtent 100; pointer 0.3 -> 120px; distance 20px.
      expect(r.nearest(0.3)!.distance, closeTo(20, 1e-9));
    });

    test('returns null when there are no points', () {
      final r = SnapResolver(SplitterSnapBehavior(points: const []), _free);
      expect(r.nearest(0.5), isNull);
    });
  });

  group('SnapResolver.resolveAt', () {
    test('re-resolves a constrained point to where it actually lands', () {
      final r = SnapResolver(
        SplitterSnapBehavior(points: const [0.1, 0.9]),
        _minStart,
      );
      final p = r.resolveAt(0, 0.6);
      expect(p.nominalFraction, 0.1);
      expect(
        p.effectiveFraction,
        closeTo(0.5, 1e-9),
      ); // pushed by the 200px min
      expect(p.distance, closeTo(0.1, 1e-9)); // |0.6 - 0.5|
    });
  });

  group('SnapResolver.radius', () {
    test('is the pixel tolerance when set, else the ratio tolerance', () {
      expect(
        SnapResolver(
          SplitterSnapBehavior(points: const [0.5], tolerance: 0.03),
          _free,
        ).radius,
        0.03,
      );
      expect(
        SnapResolver(
          SplitterSnapBehavior(points: const [0.5], pixelTolerance: 12),
          _free,
        ).radius,
        12,
      );
    });
  });

  group('SnapResolver.resolveSortedDistinct', () {
    test('sorts by coordinate and de-dupes coincident points (first wins)', () {
      final r = SnapResolver(
        // 0.1 and 0.12 both land at 0.5 under the 200px min; 0.9 stays at 0.9.
        SplitterSnapBehavior(points: const [0.9, 0.1, 0.12]),
        _minStart,
      );
      final sorted = r.resolveSortedDistinct(0.5);
      expect(sorted.map((p) => p.index), [1, 0]); // 0.1 (idx1) kept, 0.9 (idx0)
      expect(sorted.map((p) => p.effectiveFraction), [
        closeTo(0.5, 1e-9),
        closeTo(0.9, 1e-9),
      ]);
    });
  });

  group('magneticPull', () {
    SnapResolver mag(
      List<double> points, {
      double tolerance = 0.2,
      SplitterSolver solver = _free,
    }) => SnapResolver(
      SplitterSnapBehavior.magnetic(points: points, tolerance: tolerance),
      solver,
    );

    test('pulls the divider partway toward the point near it', () {
      // point 0.5, pointer 0.6, d=0.1, t=0.5, pull=0.5*0.5=0.25 -> 0.575
      final pulled = magneticPull(
        pointer: 0.6,
        resolver: mag(const [0.5]),
        strength: 0.5,
      );
      expect(pulled, closeTo(0.575, 1e-9));
    });

    test('applies no pull at or beyond the tolerance edge', () {
      final r = mag(const [0.5]);
      expect(magneticPull(pointer: 0.7, resolver: r, strength: 0.5), 0.7);
      expect(magneticPull(pointer: 0.95, resolver: r, strength: 0.5), 0.95);
    });

    test('is continuous across the midpoint of two overlapping zones', () {
      // points 0.4 / 0.6, radius 0.2 overlap; naive nearest-pull jumps ~0.05
      // across 0.5. With Voronoi clipping the rendered values stay together.
      final r = mag(const [0.4, 0.6]);
      final left = magneticPull(pointer: 0.499, resolver: r, strength: 0.5);
      final right = magneticPull(pointer: 0.501, resolver: r, strength: 0.5);
      expect((right - left).abs(), lessThan(0.01));
    });

    test('a stronger pull lands closer to the point', () {
      final r = mag(const [0.5]);
      final soft = magneticPull(pointer: 0.6, resolver: r, strength: 0.3);
      final hard = magneticPull(pointer: 0.6, resolver: r, strength: 0.8);
      expect(hard, lessThan(soft));
      expect(hard, greaterThan(0.5));
    });

    test('returns the pointer unchanged with no points', () {
      expect(
        magneticPull(pointer: 0.6, resolver: mag(const []), strength: 0.5),
        0.6,
      );
    });

    test('defaults to a linear falloff', () {
      final r = mag(const [0.5]);
      final byDefault = magneticPull(pointer: 0.6, resolver: r, strength: 0.5);
      final asLinear = magneticPull(
        pointer: 0.6,
        resolver: r,
        strength: 0.5,
        curve: Curves.linear,
      );
      expect(byDefault, asLinear);
      expect(byDefault, closeTo(0.575, 1e-9)); // unchanged legacy behavior
    });

    test('an ease-in falloff softens the pull away from the point', () {
      // At pointer 0.6 the nearness is 0.5 (d=0.1, radius 0.2). An ease-in curve
      // maps 0.5 below the diagonal, so the pull is weaker than linear - the
      // divider stays closer to the pointer out here and only catches near 0.5.
      final r = mag(const [0.5]);
      final linear = magneticPull(
        pointer: 0.6,
        resolver: r,
        strength: 0.5,
        curve: Curves.linear,
      );
      final easeIn = magneticPull(
        pointer: 0.6,
        resolver: r,
        strength: 0.5,
        curve: Curves.easeInCubic,
      );
      expect(easeIn, greaterThan(linear)); // less pulled (nearer the pointer)
      expect(easeIn, lessThan(0.6)); // but still drawn toward the point
    });

    test('an ease-in falloff still catches hard near the point', () {
      // Up close (pointer 0.51, nearness 0.95) the curve is near 1, so the pull
      // stays strong - the snappy catch lives right next to the point.
      final r = mag(const [0.5]);
      final easeIn = magneticPull(
        pointer: 0.51,
        resolver: r,
        strength: 0.9,
        curve: Curves.easeInCubic,
      );
      expect(easeIn, lessThan(0.505)); // pulled most of the way in
      expect(easeIn, greaterThanOrEqualTo(0.5));
    });

    test('settles exactly onto the point inside the settle core', () {
      // pointer 0.51, point 0.5, radius 0.2 -> distance 0.01; settleFactor 0.1
      // gives a 0.02 core, so 0.01 lands exactly on 0.5.
      final pulled = magneticPull(
        pointer: 0.51,
        resolver: mag(const [0.5]),
        strength: 0.8,
        settleFactor: 0.1,
      );
      expect(pulled, closeTo(0.5, 1e-9));
    });

    test('pulls but does not settle outside the core', () {
      // distance 0.05 > 0.02 core -> pulled toward 0.5 but not exactly onto it.
      final pulled = magneticPull(
        pointer: 0.55,
        resolver: mag(const [0.5]),
        strength: 0.8,
        settleFactor: 0.1,
      );
      expect(pulled, greaterThan(0.5));
      expect(pulled, lessThan(0.55));
    });

    test('settleFactor 0 never settles (default)', () {
      // A hair off the point still keeps a residual gap with no settle core.
      final pulled = magneticPull(
        pointer: 0.501,
        resolver: mag(const [0.5]),
        strength: 0.8,
      );
      expect(pulled, isNot(closeTo(0.5, 1e-12)));
    });
  });

  group('stickyStep', () {
    SnapResolver sticky(
      List<double> points, {
      double tolerance = 0.2,
      SplitterSolver solver = _free,
    }) => SnapResolver(
      SplitterSnapBehavior.sticky(points: points, tolerance: tolerance),
      solver,
    );

    test('captures the nearest point at the capture radius', () {
      final step = stickyStep(
        pointer: 0.7, // d == 0.2 == radius
        capturedIndex: null,
        resolver: sticky(const [0.5]),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, 0);
      expect(step.requestFraction, 0.5);
      expect(step.source, SplitterChangeSource.snap);
    });

    test('holds a captured point out to the escape radius', () {
      final step = stickyStep(
        pointer: 0.8, // d == 0.3 == radius * 1.5
        capturedIndex: 0,
        resolver: sticky(const [0.5]),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, 0);
      expect(step.requestFraction, 0.5);
      expect(step.source, SplitterChangeSource.snap);
    });

    test('releases just past the escape radius', () {
      final step = stickyStep(
        pointer: 0.81, // d == 0.31 > 0.3
        capturedIndex: 0,
        resolver: sticky(const [0.5]),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, isNull);
      expect(step.requestFraction, 0.81);
      expect(step.source, SplitterChangeSource.drag);
    });

    test('recaptures a different point within the same update', () {
      // Captured on 0.3; pointer leaps past its escape straight into 0.7's zone.
      final step = stickyStep(
        pointer: 0.72,
        capturedIndex: 0,
        resolver: sticky(const [0.3, 0.7], tolerance: 0.1),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, 1);
      expect(step.requestFraction, 0.7);
      expect(step.source, SplitterChangeSource.snap);
    });

    test('requests the nominal fraction, not the resolved one, on capture', () {
      // point 0.1 lands at 0.5 under the 200px min; the request must be 0.1.
      final step = stickyStep(
        pointer: 0.55,
        capturedIndex: null,
        resolver: sticky(const [0.1, 0.9], solver: _minStart),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, 0);
      expect(step.requestFraction, 0.1);
    });

    test('passes the pointer through when uncaptured and out of range', () {
      final step = stickyStep(
        pointer: 0.5,
        capturedIndex: null,
        resolver: sticky(const [0.2, 0.8], tolerance: 0.05),
        escapeFactor: 1.5,
      );
      expect(step.capturedIndex, isNull);
      expect(step.requestFraction, 0.5);
      expect(step.source, SplitterChangeSource.drag);
    });
  });
}
