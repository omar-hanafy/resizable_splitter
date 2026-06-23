import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

/// Keyboard, screen-reader semantics, RTL, and the double-tap reset - the
/// divider as a first-class control, not a decoration.
class A11yStation extends StatefulWidget {
  const A11yStation({super.key});

  @override
  State<A11yStation> createState() => _A11yStationState();
}

class _A11yStationState extends State<A11yStation> {
  final GlobalKey _splitterKey = GlobalKey();
  final _controller = SplitterController(
    initialPosition: const SplitterPosition.fraction(0.5),
  );
  TextDirection _dir = TextDirection.ltr;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rtl = _dir == TextDirection.rtl;
    return Station(
      index: '06',
      eyebrow: 'ACCESSIBLE BY DEFAULT',
      title: 'A control you can drive without a mouse',
      blurb:
          'The divider ships as a slider: a 48px touch target, a focus ring, '
          'arrow / page / home-end keys, spoken value semantics that only offer '
          'the moves it can actually make, RTL, and haptics. Tab to it and steer '
          'with the keyboard.',
      demoHeight: 340,
      demo: DemoStage(
        child: Directionality(
          textDirection: _dir,
          child: ResizableSplitter(
            key: _splitterKey,
            controller: _controller,
            keyboardStep: 0.02,
            pageStep: 0.1,
            doubleTapResetTo: 0.5,
            semanticsLabel: 'Demo panel divider',
            startConstraints: const SplitterPaneConstraints(minExtent: 140),
            endConstraints: const SplitterPaneConstraints(minExtent: 140),
            start: _KeyPane(
              label: rtl ? 'START (right)' : 'START (left)',
              controller: _controller,
            ),
            end: _HintPane(rtl: rtl),
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
                Text('KEYBOARD MAP', style: context.text.monoKey),
                const SizedBox(height: Insets.md),
                _Key(keys: const ['Tab'], desc: 'focus the divider'),
                _Key(keys: const ['←', '→'], desc: 'move by 2%'),
                _Key(keys: const ['PgUp', 'PgDn'], desc: 'move by 10%'),
                _Key(keys: const ['Home', 'End'], desc: 'jump to bounds'),
                _Key(keys: const ['double-tap'], desc: 'reset to 50%'),
                const SizedBox(height: Insets.md),
                Divider(height: 1, color: t.line),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Icon(
                      Icons.record_voice_over_outlined,
                      size: 14,
                      color: t.textLo,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Screen readers announce the value and only the moves it can make.',
                        style: context.text
                            .mono(10.5, color: t.textFaint)
                            .copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          Panel(
            raised: true,
            child: Row(
              children: [
                Icon(
                  Icons.format_textdirection_r_to_l_rounded,
                  size: 16,
                  color: t.request,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    'Direction',
                    style: context.text.body(13, w: FontWeight.w600),
                  ),
                ),
                SegToggle<TextDirection>(
                  segments: const [
                    (value: TextDirection.ltr, label: 'LTR', icon: null),
                    (value: TextDirection.rtl, label: 'RTL', icon: null),
                  ],
                  selected: _dir,
                  onChanged: (d) => setState(() => _dir = d),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyPane extends StatelessWidget {
  const _KeyPane({required this.label, required this.controller});
  final String label;
  final SplitterController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.mono(11, color: t.textFaint, ls: 1.2),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<SplitterLayout?>(
              valueListenable: controller.layoutListenable,
              builder: (context, layout, _) => Text(
                layout == null
                    ? '—'
                    : '${(layout.effectiveFraction * 100).toStringAsFixed(0)}%',
                style: context.text.mono(
                  28,
                  color: t.signal,
                  w: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintPane extends StatelessWidget {
  const _HintPane({required this.rtl});
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_outlined, size: 24, color: t.textFaint),
              const SizedBox(height: Insets.md),
              Text(
                rtl
                    ? 'RTL: arrows are mirrored so the divider always follows the key.'
                    : 'Click the divider or press Tab, then steer with the arrow keys.',
                textAlign: TextAlign.center,
                style: context.text
                    .mono(11.5, color: t.textFaint)
                    .copyWith(height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.keys, required this.desc});
  final List<String> keys;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        children: [
          for (final k in keys) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: t.ink.withValues(alpha: t.isDark ? 0.5 : 0.04),
                borderRadius: BorderRadius.circular(Corner.xs),
                border: Border.all(color: t.lineStrong),
              ),
              child: Text(
                k,
                style: context.text.mono(
                  11,
                  color: t.textHi,
                  w: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          const SizedBox(width: 4),
          Expanded(
            child: Text(desc, style: context.text.body(12.5, color: t.textLo)),
          ),
        ],
      ),
    );
  }
}
