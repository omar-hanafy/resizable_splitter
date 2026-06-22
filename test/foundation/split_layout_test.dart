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
      minStartExtent: 0,
      maxStartExtent: 1000,
      resolution: SplitterResolution.exact,
    );

    test('exposes the resolved geometry', () {
      expect(layout.effectiveFraction, 0.42);
      expect(layout.startExtent, 420);
      expect(layout.endExtent, 580);
      expect(layout.availableExtent, 1000);
      expect(layout.minStartExtent, 0);
      expect(layout.maxStartExtent, 1000);
      expect(layout.resolution, SplitterResolution.exact);
      expect(layout.collapsedPane, isNull);
    });

    test('canIncrease/canDecrease derive from the resolved band', () {
      expect(layout.canIncrease, isTrue);
      expect(layout.canDecrease, isTrue);

      const pinnedLow = SplitterLayout(
        effectiveFraction: 0,
        startExtent: 0,
        endExtent: 1000,
        availableExtent: 1000,
        minStartExtent: 0,
        maxStartExtent: 1000,
        resolution: SplitterResolution.clamped,
      );
      expect(pinnedLow.canDecrease, isFalse);
      expect(pinnedLow.canIncrease, isTrue);

      const pinnedPoint = SplitterLayout(
        effectiveFraction: 0.5,
        startExtent: 500,
        endExtent: 500,
        availableExtent: 1000,
        minStartExtent: 500,
        maxStartExtent: 500,
        resolution: SplitterResolution.minShortage,
      );
      expect(pinnedPoint.canIncrease, isFalse);
      expect(pinnedPoint.canDecrease, isFalse);
    });

    test('carries the collapsed pane when one is collapsed', () {
      const collapsed = SplitterLayout(
        effectiveFraction: 0,
        startExtent: 0,
        endExtent: 1000,
        availableExtent: 1000,
        minStartExtent: 0,
        maxStartExtent: 0,
        resolution: SplitterResolution.collapsed,
        collapsedPane: SplitterPane.start,
      );
      expect(collapsed.collapsedPane, SplitterPane.start);
      expect(collapsed.resolution, SplitterResolution.collapsed);
    });

    test('value equality covers every field', () {
      expect(
        layout,
        const SplitterLayout(
          effectiveFraction: 0.42,
          startExtent: 420,
          endExtent: 580,
          availableExtent: 1000,
          minStartExtent: 0,
          maxStartExtent: 1000,
          resolution: SplitterResolution.exact,
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
            minStartExtent: 0,
            maxStartExtent: 1000,
            resolution: SplitterResolution.exact,
          ),
        ),
      );
      // Differs by resolution only.
      expect(
        layout,
        isNot(
          const SplitterLayout(
            effectiveFraction: 0.42,
            startExtent: 420,
            endExtent: 580,
            availableExtent: 1000,
            minStartExtent: 0,
            maxStartExtent: 1000,
            resolution: SplitterResolution.clamped,
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
            minStartExtent: 0,
            maxStartExtent: 1000,
            resolution: SplitterResolution.exact,
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
          minStartExtent: 0,
          maxStartExtent: 1000,
          resolution: SplitterResolution.exact,
        ).hashCode,
      );
    });

    test('toString carries the effective fraction and extents', () {
      expect(layout.toString(), contains('0.42'));
      expect(layout.toString(), contains('420'));
    });
  });
}
