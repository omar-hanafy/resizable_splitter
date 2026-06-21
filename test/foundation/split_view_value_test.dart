import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_view_value.dart';

void main() {
  const value = SplitterValue(
    requestedPosition: SplitterPosition.fraction(0.4),
    effectiveFraction: 0.42,
    startExtent: 420,
    endExtent: 580,
    availableExtent: 1000,
  );

  group('SplitterValue', () {
    test('reports both the request and the effective layout', () {
      expect(value.requestedPosition, const SplitterPosition.fraction(0.4));
      expect(value.effectiveFraction, 0.42);
      expect(value.startExtent, 420);
      expect(value.endExtent, 580);
      expect(value.availableExtent, 1000);
    });

    test('has value equality', () {
      expect(
        value,
        const SplitterValue(
          requestedPosition: SplitterPosition.fraction(0.4),
          effectiveFraction: 0.42,
          startExtent: 420,
          endExtent: 580,
          availableExtent: 1000,
        ),
      );
      expect(
        value,
        isNot(
          const SplitterValue(
            requestedPosition: SplitterPosition.fraction(0.4),
            effectiveFraction: 0.5,
            startExtent: 500,
            endExtent: 500,
            availableExtent: 1000,
          ),
        ),
      );
    });
  });

  group('SplitterChangeDetails', () {
    const details = SplitterChangeDetails(
      requestedPosition: SplitterPosition.fraction(0.4),
      effectiveFraction: 0.42,
      startExtent: 420,
      endExtent: 580,
      availableExtent: 1000,
      source: SplitterChangeSource.drag,
    );

    test('carries the change source on top of the value fields', () {
      expect(details.source, SplitterChangeSource.drag);
      expect(details.startExtent, 420);
    });

    test('equality includes the source', () {
      expect(
        details,
        const SplitterChangeDetails(
          requestedPosition: SplitterPosition.fraction(0.4),
          effectiveFraction: 0.42,
          startExtent: 420,
          endExtent: 580,
          availableExtent: 1000,
          source: SplitterChangeSource.drag,
        ),
      );
      expect(
        details,
        isNot(
          const SplitterChangeDetails(
            requestedPosition: SplitterPosition.fraction(0.4),
            effectiveFraction: 0.42,
            startExtent: 420,
            endExtent: 580,
            availableExtent: 1000,
            source: SplitterChangeSource.keyboard,
          ),
        ),
      );
    });

    test('is type-distinct from a plain SplitterValue', () {
      expect(details, isNot(value));
      expect(value, isNot(details));
    });

    test('toString carries the source', () {
      expect(details.toString(), contains('drag'));
    });
  });

  test('SplitterChangeSource enumerates every interaction origin', () {
    expect(
      SplitterChangeSource.values,
      containsAll(<SplitterChangeSource>[
        SplitterChangeSource.drag,
        SplitterChangeSource.keyboard,
        SplitterChangeSource.semantics,
        SplitterChangeSource.programmatic,
        SplitterChangeSource.snap,
        SplitterChangeSource.collapse,
        SplitterChangeSource.restore,
      ]),
    );
  });
}
