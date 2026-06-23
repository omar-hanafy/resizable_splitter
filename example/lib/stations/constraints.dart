import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/code_block.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

const _code = '''ResizableSplitter(
  startConstraints: SplitterPaneConstraints(
    minExtent: 160, maxExtent: 340),
  endConstraints: SplitterPaneConstraints(
    minExtent: 160, maxExtent: 340),
  // Shortage: both minimums cannot fit.
  constraintPolicy: SplitterConstraintPolicy.favorStart,
  // Surplus: both maximums cannot fill - leave a gap.
  surplusPolicy: SplitterSurplusPolicy.leaveGap,
  start: Start(), end: End(),
);''';

/// Min/max bands plus the two ways constraints conflict - a shortage (decided by
/// [SplitterConstraintPolicy]) and a surplus (decided by [SplitterSurplusPolicy],
/// whose `leaveGap` renders a real gap between the panes).
class ConstraintsStation extends StatefulWidget {
  const ConstraintsStation({super.key});

  @override
  State<ConstraintsStation> createState() => _ConstraintsStationState();
}

class _ConstraintsStationState extends State<ConstraintsStation> {
  final GlobalKey _splitterKey = GlobalKey();
  final _controller = SplitterController(
    initialPosition: const SplitterPosition.fraction(0.5),
  );
  double _widthT = 1.0;
  SplitterConstraintPolicy _shortage = SplitterConstraintPolicy.favorStart;
  SplitterSurplusPolicy _surplus = SplitterSurplusPolicy.leaveGap;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Station(
      index: '02',
      eyebrow: 'CONSTRAINTS & POLICIES',
      title: 'When limits collide, you decide who wins',
      blurb:
          'Per-pane minimums and maximums are hard pixel limits. Sweep the width: '
          'too small and both minimums cannot fit (a shortage); too large and both '
          'maximums cannot fill it (a surplus). Two policies pick the outcome - and '
          'leaveGap renders the surplus as honest empty space, never an overflow.',
      demoHeight: 360,
      sideWidth: 320,
      demo: DemoStage(
        child: LayoutBuilder(
          builder: (context, c) {
            // Sweep through shortage -> feasible -> surplus, clamped to the
            // stage so a narrow viewport never inverts the range.
            final maxW = c.maxWidth;
            final minW = 280.0 < maxW ? 280.0 : maxW;
            final w = minW + (maxW - minW) * _widthT;
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: Motion.micro,
                      width: w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Corner.sm),
                        border: Border.all(color: t.lineStrong),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ResizableSplitter(
                        key: _splitterKey,
                        controller: _controller,
                        startConstraints: const SplitterPaneConstraints(
                          minExtent: 160,
                          maxExtent: 340,
                        ),
                        endConstraints: const SplitterPaneConstraints(
                          minExtent: 160,
                          maxExtent: 340,
                        ),
                        constraintPolicy: _shortage,
                        surplusPolicy: _surplus,
                        start: const _PaneFill(
                          label: 'START',
                          pane: SplitterPane.start,
                        ),
                        end: const _PaneFill(
                          label: 'END',
                          pane: SplitterPane.end,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 15,
                      color: t.textFaint,
                    ),
                    const SizedBox(width: 8),
                    Text('WIDTH', style: context.text.monoKey),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          activeTrackColor: t.request,
                          inactiveTrackColor: t.line,
                          thumbColor: t.request,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: _widthT,
                          onChanged: (v) => setState(() => _widthT = v),
                        ),
                      ),
                    ),
                    Text(
                      '${w.round()}px',
                      style: context.text.mono(11.5, color: t.textLo),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      side: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<SplitterLayout?>(
                  valueListenable: _controller.layoutListenable,
                  builder: (context, layout, _) {
                    final gap = layout == null
                        ? 0.0
                        : (layout.availableExtent -
                              layout.startExtent -
                              layout.endExtent);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('RESOLUTION', style: context.text.monoKey),
                            const Spacer(),
                            if (layout != null)
                              ResolutionBadge(layout.resolution),
                          ],
                        ),
                        const SizedBox(height: Insets.lg),
                        Row(
                          children: [
                            Expanded(
                              child: StatCell(
                                label: 'START',
                                value: layout == null
                                    ? '—'
                                    : '${layout.startExtent.round()}',
                                unit: 'px',
                              ),
                            ),
                            Expanded(
                              child: StatCell(
                                label: 'END',
                                value: layout == null
                                    ? '—'
                                    : '${layout.endExtent.round()}',
                                unit: 'px',
                              ),
                            ),
                            Expanded(
                              child: StatCell(
                                label: 'GAP',
                                value: layout == null ? '—' : '${gap.round()}',
                                unit: 'px',
                                valueColor: gap > 1 ? t.signal : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Insets.lg),
                Text('SURPLUS POLICY', style: context.text.monoKey),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final p in SplitterSurplusPolicy.values)
                      _PolicyChip(
                        label: p.name,
                        active: _surplus == p,
                        onTap: () => setState(() => _surplus = p),
                      ),
                  ],
                ),
                const SizedBox(height: Insets.lg),
                Text('SHORTAGE POLICY', style: context.text.monoKey),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final p in SplitterConstraintPolicy.values)
                      _PolicyChip(
                        label: p.name,
                        active: _shortage == p,
                        onTap: () => setState(() => _shortage = p),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          CodeBlock(code: _code),
        ],
      ),
    );
  }
}

class _PaneFill extends StatelessWidget {
  const _PaneFill({required this.label, required this.pane});
  final String label;
  final SplitterPane pane;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tone = pane == SplitterPane.start ? t.signal : t.request;
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Center(
        child: Text(
          label,
          style: context.text.mono(
            12,
            color: tone,
            w: FontWeight.w700,
            ls: 1.5,
          ),
        ),
      ),
    );
  }
}

class _PolicyChip extends StatelessWidget {
  const _PolicyChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.micro,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? t.signalSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.xs),
            border: Border.all(
              color: active ? t.signal.withValues(alpha: 0.5) : t.line,
            ),
          ),
          child: Text(
            label,
            style: context.text.mono(
              11,
              color: active ? t.signalText : t.textLo,
              w: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
