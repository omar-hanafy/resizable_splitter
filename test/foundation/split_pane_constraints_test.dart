import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';

void main() {
  group('SplitterPaneConstraints', () {
    test('has permissive defaults', () {
      const c = SplitterPaneConstraints();
      expect(c.minExtent, 0);
      expect(c.maxExtent, double.infinity);
      expect(c.collapsible, isFalse);
      expect(c.collapsedExtent, 0);
    });

    test('stores provided values', () {
      const c = SplitterPaneConstraints(
        minExtent: 100,
        maxExtent: 400,
        collapsible: true,
        collapsedExtent: 48,
      );
      expect(c.minExtent, 100);
      expect(c.maxExtent, 400);
      expect(c.collapsible, isTrue);
      expect(c.collapsedExtent, 48);
    });

    test('rejects invalid values', () {
      expect(
        () => SplitterPaneConstraints(minExtent: -1),
        throwsAssertionError,
      );
      expect(
        () => SplitterPaneConstraints(minExtent: 200, maxExtent: 100),
        throwsAssertionError,
      );
      expect(
        () => SplitterPaneConstraints(collapsedExtent: -1),
        throwsAssertionError,
      );
    });

    test('copyWith replaces only the given fields', () {
      const c = SplitterPaneConstraints(minExtent: 100, maxExtent: 400);
      final updated = c.copyWith(maxExtent: 500);
      expect(updated.minExtent, 100);
      expect(updated.maxExtent, 500);
    });

    test('has value equality', () {
      expect(
        const SplitterPaneConstraints(minExtent: 100),
        const SplitterPaneConstraints(minExtent: 100),
      );
      expect(
        const SplitterPaneConstraints(minExtent: 100).hashCode,
        const SplitterPaneConstraints(minExtent: 100).hashCode,
      );
      expect(
        const SplitterPaneConstraints(minExtent: 100),
        isNot(const SplitterPaneConstraints(minExtent: 120)),
      );
    });

    test('toString carries the extents', () {
      expect(
        const SplitterPaneConstraints(
          minExtent: 100,
          maxExtent: 400,
        ).toString(),
        allOf(contains('100'), contains('400')),
      );
    });
  });

  group('SplitterConstraintPolicy', () {
    test('exposes the three resolution modes', () {
      expect(SplitterConstraintPolicy.values, hasLength(3));
      expect(
        SplitterConstraintPolicy.values,
        containsAll(<SplitterConstraintPolicy>[
          SplitterConstraintPolicy.favorStart,
          SplitterConstraintPolicy.favorEnd,
          SplitterConstraintPolicy.proportional,
        ]),
      );
    });
  });
}
