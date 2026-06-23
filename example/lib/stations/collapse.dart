import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../data/sample.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/code_block.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

const _code = '''final controller = SplitterController();

ResizableSplitter(
  controller: controller,
  startConstraints: SplitterPaneConstraints(
    minExtent: 220,
    collapsedExtent: 0, // set => collapsible
  ),
  start: Sidebar(), end: Content(),
);

// Collapse remembers the position; expand restores it.
controller.toggleCollapse(SplitterPane.start);
await controller.animateTo(0.5);''';

/// Collapse and expand with automatic restore, plus vsync `animateTo`.
class CollapseStation extends StatefulWidget {
  const CollapseStation({super.key});

  @override
  State<CollapseStation> createState() => _CollapseStationState();
}

class _CollapseStationState extends State<CollapseStation> {
  final GlobalKey _splitterKey = GlobalKey();
  final _controller = SplitterController(
    initialPosition: const SplitterPosition.fraction(0.3),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Station(
      index: '04',
      eyebrow: 'COLLAPSE & ANIMATE',
      title: 'A sidebar that folds and remembers',
      blurb:
          'Give a pane a collapsedExtent and it becomes collapsible. Collapsing '
          'bundles into the atomic state - it can never silently disagree with the '
          'UI - and expand restores the exact position it held before. animateTo '
          'rides the platform vsync and honors reduced-motion.',
      demoHeight: 360,
      demo: DemoStage(
        child: ResizableSplitter(
          key: _splitterKey,
          controller: _controller,
          startConstraints: const SplitterPaneConstraints(
            minExtent: 220,
            collapsedExtent: 0,
          ),
          endConstraints: const SplitterPaneConstraints(minExtent: 200),
          start: const Padding(
            padding: EdgeInsets.all(6),
            child: MiniNav(selected: 4),
          ),
          end: Padding(
            padding: const EdgeInsets.all(6),
            child: _ContentWithToggle(controller: _controller),
          ),
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
                ValueListenableBuilder<SplitterState>(
                  valueListenable: _controller,
                  builder: (context, state, _) {
                    return ValueListenableBuilder<SplitterLayout?>(
                      valueListenable: _controller.layoutListenable,
                      builder: (context, layout, _) {
                        return Row(
                          children: [
                            Expanded(
                              child: StatCell(
                                label: 'COLLAPSED',
                                value: state.collapsedPane?.name ?? 'none',
                                valueColor: state.isCollapsed
                                    ? t.request
                                    : null,
                              ),
                            ),
                            Expanded(
                              child: StatCell(
                                label: 'EFFECTIVE',
                                value: layout == null
                                    ? '—'
                                    : (layout.effectiveFraction * 100)
                                          .toStringAsFixed(0),
                                unit: '%',
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: Insets.lg),
                Row(
                  children: [
                    Expanded(
                      child: _Btn(
                        label: 'Toggle',
                        icon: Icons.unfold_less_rounded,
                        onTap: () =>
                            _controller.toggleCollapse(SplitterPane.start),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: _Btn(
                        label: 'Expand',
                        icon: Icons.unfold_more_rounded,
                        onTap: _controller.expand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Text('ANIMATE TO', style: context.text.monoKey),
                const SizedBox(height: Insets.sm),
                Row(
                  children: [
                    for (final f in const [0.0, 0.3, 0.5, 0.7])
                      Padding(
                        padding: const EdgeInsets.only(right: Insets.sm),
                        child: _MiniBtn(
                          label: '${(f * 100).round()}%',
                          onTap: () => _controller.animateTo(f),
                        ),
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

class _ContentWithToggle extends StatelessWidget {
  const _ContentWithToggle({required this.controller});
  final SplitterController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.6 : 0.92),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                _IconToggle(
                  onTap: () => controller.toggleCollapse(SplitterPane.start),
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  'WORKSPACE',
                  style: context.text.mono(11, color: t.textLo, ls: 1.2),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Insets.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_open_rounded, size: 26, color: t.textFaint),
                    const SizedBox(height: Insets.md),
                    Text(
                      'Toggle the sidebar from the menu, the buttons,\nor by dragging the divider to its edge.',
                      textAlign: TextAlign.center,
                      style: context.text
                          .mono(11.5, color: t.textFaint)
                          .copyWith(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.xs),
            border: Border.all(color: t.line),
          ),
          child: Icon(Icons.menu_rounded, size: 14, color: t.textHi),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.sm),
            border: Border.all(color: t.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: t.textHi),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.mono(
                  12,
                  color: t.textHi,
                  w: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: t.ink.withValues(alpha: t.isDark ? 0.45 : 0.03),
            borderRadius: BorderRadius.circular(Corner.xs),
            border: Border.all(color: t.line),
          ),
          child: Text(
            label,
            style: context.text.mono(11.5, color: t.textLo, w: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
