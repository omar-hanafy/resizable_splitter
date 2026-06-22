import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_layout.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_solver.dart';

void main() {
  group('feasible layouts clamp the request', () {
    test('honors a fractional request inside the legal interval', () {
      const solver = SplitterSolver(
        available: 1000,
        start: SplitterPaneConstraints(),
        end: SplitterPaneConstraints(),
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.4));
      expect(sol.startExtent, closeTo(400, 1e-9));
      expect(sol.endExtent, closeTo(600, 1e-9));
      expect(sol.effectiveFraction, closeTo(0.4, 1e-9));
      expect(sol.resolution, SplitterResolution.exact);
    });

    test('caps the start pane at its maxExtent', () {
      const solver = SplitterSolver(
        available: 1000,
        start: SplitterPaneConstraints(maxExtent: 300),
        end: SplitterPaneConstraints(),
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.9));
      expect(sol.startExtent, closeTo(300, 1e-9));
    });

    test('keeps a pixel-pinned start panel fixed as space grows', () {
      const small = SplitterSolver(
        available: 800,
        start: SplitterPaneConstraints(),
        end: SplitterPaneConstraints(),
      );
      const big = SplitterSolver(
        available: 1600,
        start: SplitterPaneConstraints(),
        end: SplitterPaneConstraints(),
      );
      const pinned = SplitterPosition.startPixels(280);
      expect(small.solve(pinned).startExtent, closeTo(280, 1e-9));
      expect(big.solve(pinned).startExtent, closeTo(280, 1e-9));
    });
  });

  group('cramped layouts apply the policy (no inverted clamp)', () {
    // available = 180 - 6 = 174 < 100 + 100. The old code threw here.
    const start = SplitterPaneConstraints(minExtent: 100);
    const end = SplitterPaneConstraints(minExtent: 100);

    test('favorStart pins the start pane at its minimum', () {
      const solver = SplitterSolver(available: 174, start: start, end: end);
      final sol = solver.solve(const SplitterPosition.fraction(0.5));
      expect(sol.startExtent, closeTo(100, 1e-9));
      expect(sol.effectiveFraction, closeTo(100 / 174, 1e-9));
      expect(sol.resolution, SplitterResolution.minShortage);
      expect(sol.startExtent + sol.endExtent, closeTo(174, 1e-9));
    });

    test('favorEnd pins the end pane at its minimum', () {
      const solver = SplitterSolver(
        available: 174,
        start: start,
        end: end,
        policy: SplitterConstraintPolicy.favorEnd,
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.5));
      expect(sol.startExtent, closeTo(74, 1e-9));
    });

    test(
      'proportional preserves configured proportions (83/17, not 50/50)',
      () {
        const solver = SplitterSolver(
          available: 100,
          start: SplitterPaneConstraints(minExtent: 1000),
          end: SplitterPaneConstraints(minExtent: 200),
          policy: SplitterConstraintPolicy.proportional,
        );
        final sol = solver.solve(const SplitterPosition.fraction(0.5));
        expect(sol.startExtent, closeTo(100 * 1000 / 1200, 1e-9));
        expect(sol.startExtent, isNot(closeTo(50, 1)));
      },
    );
  });

  group('collapse', () {
    test('a collapsed start pane takes its collapsedExtent', () {
      const solver = SplitterSolver(
        available: 1000,
        start: SplitterPaneConstraints(minExtent: 100, collapsedExtent: 48),
        end: SplitterPaneConstraints(),
        startCollapsed: true,
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.5));
      expect(sol.startExtent, closeTo(48, 1e-9));
      expect(sol.endExtent, closeTo(952, 1e-9));
      expect(sol.startCollapsed, isTrue);
    });
  });

  group('device-pixel snapping', () {
    test('lands the start extent on a physical pixel at dpr 1.5', () {
      const solver = SplitterSolver(
        available: 1000,
        start: SplitterPaneConstraints(),
        end: SplitterPaneConstraints(),
        devicePixelRatio: 1.5,
        snapToPhysicalPixels: true,
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.3337));
      final physical = sol.startExtent * 1.5;
      expect((physical - physical.roundToDouble()).abs(), lessThan(1e-9));
    });
  });

  group('surplus (both maximums too small to fill)', () {
    // available 1000, maxes 200 + 300 = 500 < 1000 => 500 of slack.
    SplitterSolution solveWith(SplitterSurplusPolicy policy) => SplitterSolver(
      available: 1000,
      start: const SplitterPaneConstraints(maxExtent: 200),
      end: const SplitterPaneConstraints(maxExtent: 300),
      surplusPolicy: policy,
    ).solve(const SplitterPosition.fraction(0.5));

    test('giveToStart grows the start pane to fill', () {
      final sol = solveWith(SplitterSurplusPolicy.giveToStart);
      expect(sol.startExtent, closeTo(700, 1e-9));
      expect(sol.endExtent, closeTo(300, 1e-9));
      expect(sol.resolution, SplitterResolution.maxSurplus);
    });

    test('giveToEnd grows the end pane to fill', () {
      final sol = solveWith(SplitterSurplusPolicy.giveToEnd);
      expect(sol.startExtent, closeTo(200, 1e-9));
      expect(sol.endExtent, closeTo(800, 1e-9));
    });

    test('proportional splits by the two maximums', () {
      final sol = solveWith(SplitterSurplusPolicy.proportional);
      expect(sol.startExtent, closeTo(400, 1e-9)); // 1000 * 200/500
      expect(sol.endExtent, closeTo(600, 1e-9));
    });

    test('leaveGap keeps both panes at their maximum, leaving a gap', () {
      final sol = solveWith(SplitterSurplusPolicy.leaveGap);
      expect(sol.startExtent, closeTo(200, 1e-9));
      expect(sol.endExtent, closeTo(300, 1e-9));
      expect(sol.startExtent + sol.endExtent, lessThan(1000));
    });

    test('the default policy keeps maxExtent a true maximum (leaveGap)', () {
      final sol = const SplitterSolver(
        available: 1000,
        start: SplitterPaneConstraints(maxExtent: 200),
        end: SplitterPaneConstraints(maxExtent: 300),
      ).solve(const SplitterPosition.fraction(0.5));
      // Neither pane overflows past its maximum; the leftover is a gap.
      expect(sol.startExtent, closeTo(200, 1e-9));
      expect(sol.endExtent, closeTo(300, 1e-9));
      expect(sol.startExtent + sol.endExtent, lessThan(1000));
      expect(sol.resolution, SplitterResolution.maxSurplus);
    });
  });

  group('pixel limits beat fractional caps (review C#2)', () {
    test(
      'a feasible pixel minimum wins over a conflicting maxStartFraction',
      () {
        // maxStartFraction 0.5 would cap the start at 200, below its 300px
        // minimum. The hard pixel minimum must win.
        const solver = SplitterSolver(
          available: 400,
          start: SplitterPaneConstraints(minExtent: 300),
          end: SplitterPaneConstraints(),
          maxStartFraction: 0.5,
          policy: SplitterConstraintPolicy.favorEnd,
        );
        final sol = solver.solve(const SplitterPosition.fraction(0.5));
        expect(sol.startExtent, closeTo(300, 1e-9));
        expect(sol.resolution, SplitterResolution.fractionConflict);
      },
    );

    test(
      'a feasible pixel maximum wins over a conflicting minStartFraction',
      () {
        // minStartFraction 0.5 would force the start to 200, above its 100px
        // maximum. The hard pixel maximum must win.
        const solver = SplitterSolver(
          available: 400,
          start: SplitterPaneConstraints(maxExtent: 100),
          end: SplitterPaneConstraints(),
          minStartFraction: 0.5,
        );
        final sol = solver.solve(const SplitterPosition.fraction(0.5));
        expect(sol.startExtent, closeTo(100, 1e-9));
        expect(sol.resolution, SplitterResolution.fractionConflict);
      },
    );
  });

  group('degenerate inputs never throw', () {
    test('zero available space yields zero extents', () {
      const solver = SplitterSolver(
        available: 0,
        start: SplitterPaneConstraints(minExtent: 100),
        end: SplitterPaneConstraints(minExtent: 100),
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.5));
      expect(sol.startExtent, 0);
      expect(sol.endExtent, 0);
    });

    test('non-finite available is treated as zero', () {
      const solver = SplitterSolver(
        available: double.infinity,
        start: SplitterPaneConstraints(),
        end: SplitterPaneConstraints(),
      );
      final sol = solver.solve(const SplitterPosition.fraction(0.5));
      expect(sol.startExtent, 0);
      expect(sol.endExtent, 0);
    });
  });
}
