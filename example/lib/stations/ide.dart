import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../data/sample.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/code_block.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

const _code = '''ResizableSplitter(
  initialPosition: SplitterPosition.startPixels(240),
  start: FileTree(),
  end: ResizableSplitter(            // nested
    axis: Axis.vertical,
    initialPosition: SplitterPosition.fraction(0.64),
    start: Editor(),
    end: Terminal(),
  ),
);''';

/// Nesting in practice: a pinned explorer beside a vertically split editor and
/// terminal. Every divider here is a ResizableSplitter - the demo furniture is
/// the product.
class IdeStation extends StatelessWidget {
  const IdeStation({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          index: '05',
          eyebrow: 'COMPOSITION',
          title: 'Nest them into a workspace',
          blurb:
              'A splitter pane can hold another splitter. Backed by a real '
              'RenderObject, nesting stays correct under intrinsic sizing and '
              'unbounded constraints - so an editor over a terminal, beside a '
              'pinned explorer, is just three splitters.',
        ),
        const SizedBox(height: Insets.xl),
        SizedBox(
          height: 460,
          child: DemoStage(
            padded: false,
            label: 'WORKSPACE',
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Corner.sm),
                child: ResizableSplitter(
                  initialPosition: const SplitterPosition.startPixels(240),
                  startConstraints: const SplitterPaneConstraints(
                    minExtent: 170,
                  ),
                  endConstraints: const SplitterPaneConstraints(minExtent: 280),
                  start: const Padding(
                    padding: EdgeInsets.all(4),
                    child: FileTreePane(),
                  ),
                  end: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ResizableSplitter(
                      axis: Axis.vertical,
                      initialPosition: const SplitterPosition.fraction(0.64),
                      startConstraints: const SplitterPaneConstraints(
                        minExtent: 120,
                      ),
                      endConstraints: const SplitterPaneConstraints(
                        minExtent: 96,
                      ),
                      start: const Padding(
                        padding: EdgeInsets.all(4),
                        child: EditorPane(),
                      ),
                      end: const Padding(
                        padding: EdgeInsets.all(4),
                        child: TerminalPane(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 820;
            final note = _Note();
            final code = CodeBlock(code: _code);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  note,
                  const SizedBox(height: Insets.md),
                  code,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: note),
                const SizedBox(width: Insets.lg),
                Expanded(child: code),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dataset_outlined, size: 15, color: t.signalText),
              const SizedBox(width: 8),
              Text(
                'THREE DIVIDERS',
                style: context.text.monoKey.copyWith(color: t.signalText),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          _bullet(
            context,
            'The explorer is pinned to 240px - it survives every outer resize.',
          ),
          _bullet(
            context,
            'The right pane is a vertical splitter: editor over terminal.',
          ),
          _bullet(
            context,
            'Drag any divider; each owns its own controller and state.',
          ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: t.signal,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: context.text.body(13, color: t.textLo, h: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
