import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_position.dart';

void main() {
  group('SplitterPosition.fraction', () {
    test('returns the fraction independent of available space', () {
      expect(const SplitterPosition.fraction(0.3).resolveFraction(1000), 0.3);
      expect(const SplitterPosition.fraction(0.3).resolveFraction(10), 0.3);
    });

    test('clamps out-of-range values into [0, 1]', () {
      expect(const SplitterPosition.fraction(2).resolveFraction(1000), 1.0);
      expect(const SplitterPosition.fraction(-1).resolveFraction(1000), 0.0);
    });

    test('sanitizes non-finite values to 0', () {
      expect(
        const SplitterPosition.fraction(double.nan).resolveFraction(1000),
        0.0,
      );
      expect(
        const SplitterPosition.fraction(double.infinity).resolveFraction(1000),
        1.0,
      );
    });
  });

  group('SplitterPosition.startPixels', () {
    test('converts pixels to a start fraction', () {
      expect(
        const SplitterPosition.startPixels(280).resolveFraction(1000),
        closeTo(0.28, 1e-12),
      );
    });

    test('clamps when the pixels exceed the available space', () {
      expect(
        const SplitterPosition.startPixels(2000).resolveFraction(1000),
        1.0,
      );
      expect(const SplitterPosition.startPixels(-5).resolveFraction(1000), 0.0);
    });

    test('returns 0 when there is no available space', () {
      expect(const SplitterPosition.startPixels(280).resolveFraction(0), 0.0);
    });
  });

  group('SplitterPosition.endPixels', () {
    test('reserves pixels for the end panel', () {
      expect(
        const SplitterPosition.endPixels(320).resolveFraction(1000),
        closeTo(0.68, 1e-12),
      );
    });

    test('clamps when the end pixels exceed the available space', () {
      expect(const SplitterPosition.endPixels(2000).resolveFraction(1000), 0.0);
      expect(const SplitterPosition.endPixels(0).resolveFraction(1000), 1.0);
    });

    test('returns 0 when there is no available space', () {
      expect(const SplitterPosition.endPixels(320).resolveFraction(0), 0.0);
    });
  });

  group('value semantics', () {
    test('equal positions of the same kind are equal', () {
      expect(
        const SplitterPosition.fraction(0.5),
        const SplitterPosition.fraction(0.5),
      );
      expect(
        const SplitterPosition.startPixels(280),
        const SplitterPosition.startPixels(280),
      );
      expect(
        const SplitterPosition.fraction(0.5).hashCode,
        const SplitterPosition.fraction(0.5).hashCode,
      );
    });

    test('different kinds with the same number are not equal', () {
      expect(
        const SplitterPosition.fraction(0.5),
        isNot(const SplitterPosition.startPixels(0.5)),
      );
    });

    test('toString carries the value', () {
      expect(const SplitterPosition.fraction(0.5).toString(), contains('0.5'));
      expect(
        const SplitterPosition.startPixels(280).toString(),
        contains('280'),
      );
    });
  });
}
