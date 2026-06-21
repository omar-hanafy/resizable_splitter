import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
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
        collapsible: r.nextBool(),
        collapsedExtent: r.nextDouble() * 120,
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
      final startCollapsed = r.nextInt(8) == 0;
      final endCollapsed = !startCollapsed && r.nextInt(8) == 0;

      final dpr = dprs[r.nextInt(dprs.length)];
      final snap = r.nextBool();
      final solver = SplitterSolver(
        available: available,
        start: randConstraints(),
        end: randConstraints(),
        minStartFraction: minStartFraction,
        maxStartFraction: maxStartFraction,
        policy: policy,
        startCollapsed: startCollapsed,
        endCollapsed: endCollapsed,
        devicePixelRatio: dpr,
        snapToDevicePixels: snap,
      );

      final sol = solver.solve(randPosition());

      final expectedAvailable = available > 0 ? available : 0.0;
      final reason = 'case $i (available=$available, policy=$policy)';

      expect(sol.startExtent.isFinite, isTrue, reason: reason);
      expect(sol.endExtent.isFinite, isTrue, reason: reason);
      expect(sol.effectiveFraction.isFinite, isTrue, reason: reason);
      expect(sol.startExtent, greaterThanOrEqualTo(-1e-9), reason: reason);
      expect(sol.endExtent, greaterThanOrEqualTo(-1e-9), reason: reason);
      expect(
        sol.startExtent + sol.endExtent,
        closeTo(expectedAvailable, 1e-6),
        reason: reason,
      );
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

      // When the layout is feasible the start extent stays inside the legal
      // interval the solver reports.
      if (!sol.isCramped) {
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
      }
    }
  });
}
