import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_divider_style.dart';

void main() {
  group('SplitterDividerStyle', () {
    test('every field defaults to unset', () {
      const style = SplitterDividerStyle();
      expect(style.thickness, isNull);
      expect(style.color, isNull);
      expect(style.interactiveExtent, isNull);
      expect(style.builder, isNull);
    });

    test('rejects negative thickness and interactiveExtent', () {
      expect(() => SplitterDividerStyle(thickness: -1), throwsAssertionError);
      expect(
        () => SplitterDividerStyle(interactiveExtent: -1),
        throwsAssertionError,
      );
    });

    test('copyWith replaces only the given fields', () {
      const style = SplitterDividerStyle(thickness: 8, interactiveExtent: 4);
      final updated = style.copyWith(thickness: 12);
      expect(updated.thickness, 12);
      expect(updated.interactiveExtent, 4);
    });

    group('merge', () {
      test('other wins where set; the base falls through', () {
        const base = SplitterDividerStyle(thickness: 8, interactiveExtent: 4);
        const other = SplitterDividerStyle(thickness: 12);
        final merged = base.merge(other);
        expect(merged.thickness, 12);
        expect(merged.interactiveExtent, 4);
      });

      test('a null override returns the base unchanged', () {
        const base = SplitterDividerStyle(thickness: 8);
        expect(base.merge(null), base);
      });

      test('does not clobber base fields the override leaves unset', () {
        const base = SplitterDividerStyle(thickness: 20);
        const colorOnly = SplitterDividerStyle(
          color: WidgetStatePropertyAll<Color?>(Color(0xFF112233)),
        );
        final merged = base.merge(colorOnly);
        expect(merged.thickness, 20);
        expect(merged.color, isNotNull);
      });
    });

    group('value equality', () {
      test('equal field for field', () {
        expect(
          const SplitterDividerStyle(thickness: 8, interactiveExtent: 4),
          const SplitterDividerStyle(thickness: 8, interactiveExtent: 4),
        );
        expect(
          const SplitterDividerStyle(thickness: 8).hashCode,
          const SplitterDividerStyle(thickness: 8).hashCode,
        );
      });

      test('differing thickness is unequal', () {
        expect(
          const SplitterDividerStyle(thickness: 8),
          isNot(const SplitterDividerStyle(thickness: 9)),
        );
      });
    });

    group('lerp', () {
      test('interpolates thickness and interactiveExtent', () {
        const a = SplitterDividerStyle(thickness: 0, interactiveExtent: 0);
        const b = SplitterDividerStyle(thickness: 10, interactiveExtent: 4);
        final mid = SplitterDividerStyle.lerp(a, b, 0.5)!;
        expect(mid.thickness, closeTo(5, 1e-9));
        expect(mid.interactiveExtent, closeTo(2, 1e-9));
      });

      test('null endpoints pass through', () {
        const b = SplitterDividerStyle(thickness: 10);
        expect(SplitterDividerStyle.lerp(null, b, 0.5), b);
        expect(SplitterDividerStyle.lerp(b, null, 0.5), b);
        expect(SplitterDividerStyle.lerp(null, null, 0.5), isNull);
      });

      test('resolves a color between the endpoints', () {
        const a = SplitterDividerStyle(
          color: WidgetStatePropertyAll<Color?>(Color(0xFF000000)),
        );
        const b = SplitterDividerStyle(
          color: WidgetStatePropertyAll<Color?>(Color(0xFFFFFFFF)),
        );
        final mid = SplitterDividerStyle.lerp(a, b, 0.5)!;
        final color = mid.color!.resolve(<WidgetState>{});
        expect(color, isNotNull);
        expect(color, isNot(const Color(0xFF000000)));
        expect(color, isNot(const Color(0xFFFFFFFF)));
      });
    });
  });
}
