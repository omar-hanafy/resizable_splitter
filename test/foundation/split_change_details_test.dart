import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_change_details.dart';
import 'package:resizable_splitter/src/split_position.dart';

void main() {
  group('SplitterChangeDetails', () {
    const details = SplitterChangeDetails(
      requestedPosition: SplitterPosition.fraction(0.4),
      effectiveFraction: 0.42,
      startExtent: 420,
      endExtent: 580,
      availableExtent: 1000,
      source: SplitterChangeSource.drag,
    );

    test(
      'reports both the request and the effective layout, plus the source',
      () {
        expect(details.requestedPosition, const SplitterPosition.fraction(0.4));
        expect(details.effectiveFraction, 0.42);
        expect(details.startExtent, 420);
        expect(details.endExtent, 580);
        expect(details.availableExtent, 1000);
        expect(details.source, SplitterChangeSource.drag);
      },
    );

    test('equality includes every field and the source', () {
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
      // A different source alone makes it unequal.
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
      // A different effective layout alone makes it unequal.
      expect(
        details,
        isNot(
          const SplitterChangeDetails(
            requestedPosition: SplitterPosition.fraction(0.4),
            effectiveFraction: 0.5,
            startExtent: 500,
            endExtent: 500,
            availableExtent: 1000,
            source: SplitterChangeSource.drag,
          ),
        ),
      );
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
        SplitterChangeSource.doubleTapReset,
        SplitterChangeSource.snap,
        SplitterChangeSource.collapse,
        SplitterChangeSource.restore,
      ]),
    );
  });
}
