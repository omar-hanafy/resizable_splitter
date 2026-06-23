import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../data/sample.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/code_block.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

const _code = '''ResizableSplitter(
  // Pixels: the sidebar keeps 260px as the window grows.
  initialPosition: SplitterPosition.startPixels(260),
  startConstraints:
    SplitterPaneConstraints(minExtent: 180),
  start: Sidebar(),
  end: Content(),
);''';

/// Contrasts a pixel pin against a fraction as the container width changes:
/// the pinned pane holds its pixels (fraction drifts); the fraction holds its
/// ratio (pixels drift).
class PixelPinStation extends StatefulWidget {
  const PixelPinStation({super.key});

  @override
  State<PixelPinStation> createState() => _PixelPinStationState();
}

enum _Mode { pixels, fraction }

class _PixelPinStationState extends State<PixelPinStation> {
  final GlobalKey _splitterKey = GlobalKey();
  final _controller = SplitterController(
    initialPosition: const SplitterPosition.startPixels(260),
  );
  _Mode _mode = _Mode.pixels;
  double _widthT = 1.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setMode(_Mode m) {
    setState(() => _mode = m);
    _controller.jumpTo(
      m == _Mode.pixels
          ? const SplitterPosition.startPixels(260)
          : const SplitterPosition.fraction(0.42),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Station(
      index: '01',
      eyebrow: 'POSITION MODEL',
      title: 'A pin is a promise the layout keeps',
      blurb:
          'Most split views store one number and hope it matches the screen. Here '
          'the request is a unit: a fraction, or a pixel pin. Drag the container '
          'width - the pinned sidebar holds 260px while its fraction drifts; a '
          'fractional request does the opposite.',
      demoHeight: 380,
      demo: DemoStage(
        padded: true,
        child: LayoutBuilder(
          builder: (context, c) {
            // Sweep the frame from a sensible minimum up to the full stage,
            // staying within [minW, maxW] even when the stage is very narrow.
            final maxW = c.maxWidth;
            final minW = 320.0 < maxW ? 320.0 : maxW;
            final w = minW + (maxW - minW) * _widthT;
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: Motion.micro,
                      width: w.toDouble(),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Corner.sm),
                        border: Border.all(color: t.lineStrong),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ResizableSplitter(
                        key: _splitterKey,
                        controller: _controller,
                        startConstraints: const SplitterPaneConstraints(
                          minExtent: 180,
                        ),
                        endConstraints: const SplitterPaneConstraints(
                          minExtent: 140,
                        ),
                        start: const Padding(
                          padding: EdgeInsets.all(6),
                          child: MiniNav(),
                        ),
                        end: const Padding(
                          padding: EdgeInsets.all(6),
                          child: ProsePane(
                            header: 'CONTENT',
                            title: 'Editor',
                            body:
                                'The sidebar on the left is pinned. Resize the '
                                'frame with the control below and watch which '
                                'number stays put.',
                          ),
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
                    Text('CONTAINER', style: context.text.monoKey),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          activeTrackColor: t.request,
                          inactiveTrackColor: t.line,
                          thumbColor: t.request,
                          overlayColor: t.request.withValues(alpha: 0.16),
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
                SegToggle<_Mode>(
                  segments: const [
                    (
                      value: _Mode.pixels,
                      label: 'Pixel pin',
                      icon: Icons.push_pin_outlined,
                    ),
                    (
                      value: _Mode.fraction,
                      label: 'Fraction',
                      icon: Icons.percent_rounded,
                    ),
                  ],
                  selected: _mode,
                  onChanged: _setMode,
                ),
                const SizedBox(height: Insets.lg),
                ValueListenableBuilder<SplitterLayout?>(
                  valueListenable: _controller.layoutListenable,
                  builder: (context, layout, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: StatCell(
                            label: 'START',
                            value: layout == null
                                ? '—'
                                : '${layout.startExtent.round()}',
                            unit: 'px',
                            valueColor: _mode == _Mode.pixels ? t.signal : null,
                          ),
                        ),
                        Expanded(
                          child: StatCell(
                            label: 'EFFECTIVE',
                            value: layout == null
                                ? '—'
                                : (layout.effectiveFraction * 100)
                                      .toStringAsFixed(1),
                            unit: '%',
                            valueColor: _mode == _Mode.fraction
                                ? t.signal
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Insets.md),
                Text(
                  _mode == _Mode.pixels
                      ? 'Pixels stay fixed · the fraction is whatever the width makes it.'
                      : 'The fraction stays fixed · pixels follow the width.',
                  style: context.text
                      .mono(11, color: t.textFaint)
                      .copyWith(height: 1.5),
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
