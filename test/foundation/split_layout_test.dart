import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_layout.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';

void main() {
  group('SplitterLayout', () {
    const layout = SplitterLayout(
      effectiveFraction: 0.42,
      startExtent: 420,
      endExtent: 580,
      availableExtent: 1000,
      isConstrained: false,
    );

    test('exposes the resolved geometry', () {
      expect(layout.effectiveFraction, 0.42);
      expect(layout.startExtent, 420);
      expect(layout.endExtent, 580);
      expect(layout.availableExtent, 1000);
      expect(layout.isConstrained, isFalse);
      expect(layout.collapsedPane, isNull);
    });

    test('carries the collapsed pane when one is collapsed', () {
      const collapsed = SplitterLayout(
        effectiveFraction: 0,
        startExtent: 0,
        endExtent: 1000,
        availableExtent: 1000,
        isConstrained: false,
        collapsedPane: SplitterPane.start,
      );
      expect(collapsed.collapsedPane, SplitterPane.start);
    });

    test('value equality covers every field', () {
      expect(
        layout,
        const SplitterLayout(
          effectiveFraction: 0.42,
          startExtent: 420,
          endExtent: 580,
          availableExtent: 1000,
          isConstrained: false,
        ),
      );
      expect(
        layout,
        isNot(
          const SplitterLayout(
            effectiveFraction: 0.5,
            startExtent: 500,
            endExtent: 500,
            availableExtent: 1000,
            isConstrained: false,
          ),
        ),
      );
      // Differs by isConstrained only.
      expect(
        layout,
        isNot(
          const SplitterLayout(
            effectiveFraction: 0.42,
            startExtent: 420,
            endExtent: 580,
            availableExtent: 1000,
            isConstrained: true,
          ),
        ),
      );
      // Differs by collapsedPane only.
      expect(
        layout,
        isNot(
          const SplitterLayout(
            effectiveFraction: 0.42,
            startExtent: 420,
            endExtent: 580,
            availableExtent: 1000,
            isConstrained: false,
            collapsedPane: SplitterPane.end,
          ),
        ),
      );
    });

    test('hashCode matches for equal layouts', () {
      expect(
        layout.hashCode,
        const SplitterLayout(
          effectiveFraction: 0.42,
          startExtent: 420,
          endExtent: 580,
          availableExtent: 1000,
          isConstrained: false,
        ).hashCode,
      );
    });

    test('toString carries the effective fraction and extents', () {
      expect(layout.toString(), contains('0.42'));
      expect(layout.toString(), contains('420'));
    });
  });
}
