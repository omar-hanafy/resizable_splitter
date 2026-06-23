import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/solver/split_snap_behavior.dart';

void main() {
  group('backward-compatible release factory', () {
    test('unnamed factory builds a ReleaseSnap with the legacy defaults', () {
      final snap = SplitterSnapBehavior(points: const [0.5]);
      expect(snap, isA<ReleaseSnap>());
      expect(snap.points, const [0.5]);
      expect(snap.tolerance, 0.02);
      expect(snap.pixelTolerance, isNull);
    });

    test('the .release factory is equivalent to the unnamed one', () {
      expect(
        SplitterSnapBehavior.release(points: const [0.25, 0.75]),
        SplitterSnapBehavior(points: const [0.25, 0.75]),
      );
    });

    test('the SplitterSnapBehavior.new tear-off still constructs', () {
      final make = SplitterSnapBehavior.new;
      final snap = make(points: const [0.5]);
      expect(snap, isA<ReleaseSnap>());
    });
  });

  group('magnetic factory', () {
    test('defaults strength to 0.5 and is a MagneticSnap', () {
      final snap = SplitterSnapBehavior.magnetic(points: const [0.5]);
      expect(snap, isA<MagneticSnap>());
      expect((snap as MagneticSnap).strength, 0.5);
      expect(snap.tolerance, 0.02);
    });

    test('rejects a strength outside (0, 1]', () {
      expect(
        () => SplitterSnapBehavior.magnetic(points: const [0.5], strength: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SplitterSnapBehavior.magnetic(points: const [0.5], strength: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('sticky factory', () {
    test('defaults escapeFactor to 1.5 and is a StickySnap', () {
      final snap = SplitterSnapBehavior.sticky(points: const [0, 1]);
      expect(snap, isA<StickySnap>());
      expect((snap as StickySnap).escapeFactor, 1.5);
    });

    test('rejects an escapeFactor that does not exceed 1', () {
      expect(
        () => SplitterSnapBehavior.sticky(points: const [0.5], escapeFactor: 1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('copyWith stays on the sealed base and keeps the subtype', () {
    test('a base-typed magnetic behavior copies into a MagneticSnap', () {
      final SplitterSnapBehavior base = SplitterSnapBehavior.magnetic(
        points: const [0.5],
        strength: 0.4,
      );
      final copy = base.copyWith(tolerance: 0.1);
      expect(copy, isA<MagneticSnap>());
      expect(copy.tolerance, 0.1);
      expect((copy as MagneticSnap).strength, 0.4);
    });

    test('MagneticSnap.copyWith can change strength', () {
      final snap = SplitterSnapBehavior.magnetic(points: const [0.5]);
      expect((snap as MagneticSnap).copyWith(strength: 0.8).strength, 0.8);
    });

    test('StickySnap.copyWith can change escapeFactor', () {
      final snap =
          SplitterSnapBehavior.sticky(points: const [0.5]) as StickySnap;
      expect(snap.copyWith(escapeFactor: 2).escapeFactor, 2);
    });

    test('release copyWith can still clear pixelTolerance', () {
      final snap = SplitterSnapBehavior(
        points: const [0.5],
        pixelTolerance: 24,
      );
      expect(snap.copyWith(pixelTolerance: null).pixelTolerance, isNull);
    });
  });

  group('equality is per concrete subtype', () {
    test('a release and a magnetic with identical points are not equal', () {
      expect(
        SplitterSnapBehavior(points: const [0.5]),
        isNot(SplitterSnapBehavior.magnetic(points: const [0.5])),
      );
    });

    test('two magnetics differing only by strength are not equal', () {
      expect(
        SplitterSnapBehavior.magnetic(points: const [0.5], strength: 0.5),
        isNot(
          SplitterSnapBehavior.magnetic(points: const [0.5], strength: 0.6),
        ),
      );
    });

    test('equal magnetics share a hashCode', () {
      expect(
        SplitterSnapBehavior.magnetic(points: const [0.5]).hashCode,
        SplitterSnapBehavior.magnetic(points: const [0.5]).hashCode,
      );
    });
  });
}
