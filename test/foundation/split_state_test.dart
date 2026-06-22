import 'package:flutter_test/flutter_test.dart';
import 'package:resizable_splitter/src/split_pane_constraints.dart';
import 'package:resizable_splitter/src/split_position.dart';
import 'package:resizable_splitter/src/split_state.dart';

void main() {
  group('SplitterState', () {
    test('defaults to no collapsed pane', () {
      const state = SplitterState(position: SplitterPosition.fraction(0.5));
      expect(state.position, const SplitterPosition.fraction(0.5));
      expect(state.collapsedPane, isNull);
      expect(state.isCollapsed, isFalse);
    });

    test('carries a collapsed pane when set', () {
      const state = SplitterState(
        position: SplitterPosition.startPixels(280),
        collapsedPane: SplitterPane.start,
      );
      expect(state.position, const SplitterPosition.startPixels(280));
      expect(state.collapsedPane, SplitterPane.start);
      expect(state.isCollapsed, isTrue);
    });

    test('value equality covers both fields', () {
      const a = SplitterState(
        position: SplitterPosition.fraction(0.4),
        collapsedPane: SplitterPane.end,
      );
      expect(
        a,
        const SplitterState(
          position: SplitterPosition.fraction(0.4),
          collapsedPane: SplitterPane.end,
        ),
      );
      // Differs by collapse only.
      expect(
        a,
        isNot(const SplitterState(position: SplitterPosition.fraction(0.4))),
      );
      // Differs by position only.
      expect(
        a,
        isNot(
          const SplitterState(
            position: SplitterPosition.fraction(0.6),
            collapsedPane: SplitterPane.end,
          ),
        ),
      );
    });

    test('hashCode matches for equal states', () {
      const a = SplitterState(
        position: SplitterPosition.fraction(0.4),
        collapsedPane: SplitterPane.end,
      );
      const b = SplitterState(
        position: SplitterPosition.fraction(0.4),
        collapsedPane: SplitterPane.end,
      );
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith changes the position and preserves the collapse', () {
      const state = SplitterState(
        position: SplitterPosition.fraction(0.5),
        collapsedPane: SplitterPane.start,
      );
      final moved = state.copyWith(
        position: const SplitterPosition.fraction(0.7),
      );
      expect(moved.position, const SplitterPosition.fraction(0.7));
      expect(moved.collapsedPane, SplitterPane.start);
    });

    test('copyWith with no arguments returns an equal state', () {
      const state = SplitterState(
        position: SplitterPosition.fraction(0.5),
        collapsedPane: SplitterPane.start,
      );
      expect(state.copyWith(), state);
    });

    test('collapse sets the pane, keeping the position', () {
      const state = SplitterState(position: SplitterPosition.fraction(0.3));
      final collapsed = state.collapse(SplitterPane.start);
      expect(collapsed.collapsedPane, SplitterPane.start);
      expect(collapsed.position, const SplitterPosition.fraction(0.3));
    });

    test('collapse onto the same pane returns the identical instance', () {
      const state = SplitterState(
        position: SplitterPosition.fraction(0.3),
        collapsedPane: SplitterPane.start,
      );
      expect(identical(state.collapse(SplitterPane.start), state), isTrue);
    });

    test('collapse moves the collapse across panes', () {
      const state = SplitterState(
        position: SplitterPosition.fraction(0.3),
        collapsedPane: SplitterPane.start,
      );
      expect(state.collapse(SplitterPane.end).collapsedPane, SplitterPane.end);
    });

    test('expand clears the collapse, keeping the position', () {
      const state = SplitterState(
        position: SplitterPosition.startPixels(280),
        collapsedPane: SplitterPane.start,
      );
      final expanded = state.expand();
      expect(expanded.collapsedPane, isNull);
      expect(expanded.position, const SplitterPosition.startPixels(280));
    });

    test(
      'expand on an already-expanded state returns the identical instance',
      () {
        const state = SplitterState(position: SplitterPosition.fraction(0.3));
        expect(identical(state.expand(), state), isTrue);
      },
    );

    test('toString carries the position and collapse', () {
      const state = SplitterState(
        position: SplitterPosition.fraction(0.3),
        collapsedPane: SplitterPane.start,
      );
      expect(state.toString(), contains('0.3'));
      expect(state.toString(), contains('start'));
    });
  });
}
