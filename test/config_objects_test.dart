import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Stage 4: configuration objects compose and behave as value types - nested
/// themes merge, snap points are immutable, and copyWith can clear a nullable.
void main() {
  group('ResizableSplitterTheme nesting (review C#8)', () {
    testWidgets('nested theme scopes compose field by field', (tester) async {
      late ResizableSplitterThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: ResizableSplitterTheme(
            data: const ResizableSplitterThemeData(
              blockerColor: Color(0xFF0000FF),
              enableHaptics: true,
            ),
            child: ResizableSplitterTheme(
              // Inner overrides only enableHaptics; the outer blockerColor must
              // still show through.
              data: const ResizableSplitterThemeData(enableHaptics: false),
              child: Builder(
                builder: (context) {
                  resolved = ResizableSplitterTheme.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      expect(resolved.blockerColor, const Color(0xFF0000FF)); // from the outer
      expect(resolved.enableHaptics, isFalse); // from the inner
    });
  });

  group('SplitterSnapBehavior is a value type (review A#11)', () {
    test('does not alias the caller list', () {
      final points = <double>[0.25, 0.5];
      final snap = SplitterSnapBehavior(points: points);
      points.add(0.75);
      expect(snap.points, <double>[0.25, 0.5]);
    });

    test('exposes an unmodifiable list', () {
      final snap = SplitterSnapBehavior(points: <double>[0.5]);
      expect(() => snap.points.add(0.75), throwsUnsupportedError);
    });

    test('copyWith can clear pixelTolerance', () {
      final snap = SplitterSnapBehavior(points: [0.5], pixelTolerance: 24);
      expect(snap.copyWith(pixelTolerance: null).pixelTolerance, isNull);
    });
  });

  group('copyWith can clear nullables (review C)', () {
    test('ResizableSplitterThemeData clears a color', () {
      const data = ResizableSplitterThemeData(blockerColor: Color(0xFF000000));
      expect(data.copyWith(blockerColor: null).blockerColor, isNull);
    });

    test('SplitterDividerStyle clears thickness and hitSlop', () {
      const style = SplitterDividerStyle(thickness: 12, hitSlop: 8);
      final cleared = style.copyWith(thickness: null, hitSlop: null);
      expect(cleared.thickness, isNull);
      expect(cleared.hitSlop, isNull);
    });
  });
}
