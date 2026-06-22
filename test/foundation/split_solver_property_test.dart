import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_layout.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_solver.dart';

/// The solver's guarantees, asserted over thousands of randomized layouts.
/// A seeded PRNG keeps the run deterministic (no `Random()` without a seed).
void main() {
  test('solver invariants hold for ~4000 random layouts', () {
    final r = math.Random(0xC0FFEE);
    const iterations = 4000;
    const dprs = <double>[1, 1.25, 1.5, 2, 3];

    SplitterPaneConstraints randConstraints() {
      final minExtent = r.nextDouble() * 600;
      final maxExtent = r.nextBool()
          ? double.infinity
          : minExtent + r.nextDouble() * 1500;
      return SplitterPaneConstraints(
        minExtent: minExtent,
        maxExtent: maxExtent,
        // Either non-collapsible, or a valid collapsedExtent in [0, minExtent].
        collapsedExtent: r.nextBool() ? r.nextDouble() * minExtent : null,
      );
    }

    SplitterPosition randPosition() {
      switch (r.nextInt(3)) {
        case 0:
          return SplitterPosition.fraction(r.nextDouble() * 1.4 - 0.2);
        case 1:
          return SplitterPosition.startPixels(r.nextDouble() * 4000);
        default:
          return SplitterPosition.endPixels(r.nextDouble() * 4000);
      }
    }

    for (var i = 0; i < iterations; i++) {
      // Mix of normal, tiny, and zero available space.
      final double available;
      final roll = r.nextInt(20);
      if (roll == 0) {
        available = 0;
      } else if (roll == 1) {
        available = r.nextDouble() * 12;
      } else {
        available = r.nextDouble() * 4000;
      }

      final a = r.nextDouble();
      final b = r.nextDouble();
      final minStartFraction = math.min(a, b);
      final maxStartFraction = math.max(a, b);
      final policy = SplitterConstraintPolicy
          .values[r.nextInt(SplitterConstraintPolicy.values.length)];
      final surplusPolicy = SplitterSurplusPolicy
          .values[r.nextInt(SplitterSurplusPolicy.values.length)];
      final startCollapsed = r.nextInt(8) == 0;
      final endCollapsed = !startCollapsed && r.nextInt(8) == 0;

      final dpr = dprs[r.nextInt(dprs.length)];
      final snap = r.nextBool();
      final start = randConstraints();
      final end = randConstraints();
      final solver = SplitterSolver(
        available: available,
        start: start,
        end: end,
        minStartFraction: minStartFraction,
        maxStartFraction: maxStartFraction,
        policy: policy,
        surplusPolicy: surplusPolicy,
        startCollapsed: startCollapsed,
        endCollapsed: endCollapsed,
        devicePixelRatio: dpr,
        snapToPhysicalPixels: snap,
      );

      final sol = solver.solve(randPosition());

      final expectedAvailable = available > 0 ? available : 0.0;
      final reason =
          'case $i (available=$available, policy=$policy, '
          'surplus=$surplusPolicy, resolution=${sol.resolution})';

      expect(sol.startExtent.isFinite, isTrue, reason: reason);
      expect(sol.endExtent.isFinite, isTrue, reason: reason);
      expect(sol.effectiveFraction.isFinite, isTrue, reason: reason);
      expect(sol.startExtent, greaterThanOrEqualTo(-1e-9), reason: reason);
      expect(sol.endExtent, greaterThanOrEqualTo(-1e-9), reason: reason);

      // The panes fill the space, except under leaveGap on a surplus, where the
      // sum is deliberately less (the remainder is an intentional gap).
      final leavesGap =
          sol.resolution == SplitterResolution.maxSurplus &&
          surplusPolicy == SplitterSurplusPolicy.leaveGap;
      if (leavesGap) {
        expect(
          sol.startExtent + sol.endExtent,
          lessThanOrEqualTo(expectedAvailable + 1e-6),
          reason: reason,
        );
      } else {
        expect(
          sol.startExtent + sol.endExtent,
          closeTo(expectedAvailable, 1e-6),
          reason: reason,
        );
      }

      expect(
        sol.effectiveFraction,
        greaterThanOrEqualTo(-1e-9),
        reason: reason,
      );
      expect(
        sol.effectiveFraction,
        lessThanOrEqualTo(1 + 1e-9),
        reason: reason,
      );

      // The reported band always contains the resolved extent.
      expect(
        sol.startExtent,
        greaterThanOrEqualTo(sol.minStartExtent - 1e-6),
        reason: reason,
      );
      expect(
        sol.startExtent,
        lessThanOrEqualTo(sol.maxStartExtent + 1e-6),
        reason: reason,
      );

      // The headline invariant: whenever the hard pixel band is non-empty, a
      // fractional cap can never push the start extent outside it. (Collapse and
      // zero-space layouts are governed separately.)
      if (available > 0 && !startCollapsed && !endCollapsed) {
        final pixLo = math
            .max(start.minExtent, available - end.maxExtent)
            .clamp(0.0, available);
        final pixHi = math
            .min(start.maxExtent, available - end.minExtent)
            .clamp(0.0, available);
        if (pixLo <= pixHi) {
          expect(
            sol.startExtent,
            greaterThanOrEqualTo(pixLo - 1e-6),
            reason: 'pixel band floor: $reason',
          );
          expect(
            sol.startExtent,
            lessThanOrEqualTo(pixHi + 1e-6),
            reason: 'pixel band ceiling: $reason',
          );
        }
      }
    }
  });
}
