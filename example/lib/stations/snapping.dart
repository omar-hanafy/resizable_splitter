import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/code_block.dart';
import '../widgets/instrument.dart';
import '../widgets/lab_station.dart';

const _points = [0.25, 0.5, 0.75];

enum _Snap { release, magnetic, sticky }

const _codes = {
  _Snap.release: '''// Settle onto the nearest point when the drag ends.
snap: SplitterSnapBehavior(
  points: [0.25, 0.5, 0.75],
  tolerance: 0.04,
),''',
  _Snap.magnetic: '''// Draw the divider in, then settle it exactly
// onto the point once close (still pushable).
snap: SplitterSnapBehavior.magnetic(
  points: [0.25, 0.5, 0.75],
  tolerance: 0.1, strength: 0.85,
  falloff: Curves.easeInQuad,
  settleFactor: 0.18,
),''',
  _Snap.sticky: '''// Capture and hold until the pointer escapes
// past escapeFactor * tolerance (hysteresis).
snap: SplitterSnapBehavior.sticky(
  points: [0.25, 0.5, 0.75],
  tolerance: 0.04, escapeFactor: 1.6,
),''',
};

const _blurbs = {
  _Snap.release:
      'Drag freely; on release the divider settles onto the nearest detent.',
  _Snap.magnetic:
      'A light pull draws the divider in, then it settles exactly onto the '
      'detent once you are close - keep dragging to pull free.',
  _Snap.sticky:
      'The divider captures a detent and holds, with hysteresis so it never flickers.',
};

/// Compares the three snap modes against a shared set of detents.
class SnappingStation extends StatefulWidget {
  const SnappingStation({super.key});

  @override
  State<SnappingStation> createState() => _SnappingStationState();
}

class _SnappingStationState extends State<SnappingStation> {
  final GlobalKey _splitterKey = GlobalKey();
  final _controller = SplitterController(
    initialPosition: const SplitterPosition.fraction(0.5),
  );
  _Snap _mode = _Snap.magnetic;

  // The divider is "on a detent" when its effective fraction lands within this
  // band of a point. Drives the live feedback for every mode (magnetic never
  // reports source == snap, so proximity is the honest signal).
  static const double _onDetentBand = 0.012;

  // The active capture tolerance, which also sizes the magnetic-field glow so
  // the affordance matches each mode's real influence zone.
  double get _influence => switch (_mode) {
    _Snap.release => 0.04,
    _Snap.magnetic => 0.1,
    _Snap.sticky => 0.04,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SplitterSnapBehavior get _behavior => switch (_mode) {
    _Snap.release => SplitterSnapBehavior(points: _points, tolerance: 0.04),
    _Snap.magnetic => SplitterSnapBehavior.magnetic(
      points: _points,
      tolerance: 0.1,
      strength: 0.85,
      falloff: Curves.easeInQuad,
      settleFactor: 0.18,
    ),
    _Snap.sticky => SplitterSnapBehavior.sticky(
      points: _points,
      tolerance: 0.04,
      escapeFactor: 1.6,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Station(
      index: '03',
      eyebrow: 'SNAPPING',
      title: 'Three ways to land on a detent',
      blurb:
          'Snap points are start fractions, matched in effective space so a point a '
          'constraint pushes aside is measured where it actually lands. Pick a mode '
          'and drag through the three detents to feel the difference.',
      demoHeight: 360,
      demo: DemoStage(
        child: Stack(
          children: [
            ResizableSplitter(
              key: _splitterKey,
              controller: _controller,
              snap: _behavior,
              start: const _SnapPane(label: 'PANE A', tone: true),
              end: const _SnapPane(label: 'PANE B', tone: false),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<SplitterLayout?>(
                  valueListenable: _controller.layoutListenable,
                  builder: (context, layout, _) {
                    return CustomPaint(
                      painter: _DetentPainter(
                        points: _points,
                        layout: layout,
                        mode: _mode,
                        signal: t.signal,
                        line: t.lineStrong,
                        band: _onDetentBand,
                        influence: _influence,
                        labelStyle: context.text.mono(9.5, color: t.textFaint),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
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
                SegToggle<_Snap>(
                  segments: const [
                    (value: _Snap.release, label: 'Release', icon: null),
                    (value: _Snap.magnetic, label: 'Magnetic', icon: null),
                    (value: _Snap.sticky, label: 'Sticky', icon: null),
                  ],
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: Insets.md),
                ValueListenableBuilder<SplitterLayout?>(
                  valueListenable: _controller.layoutListenable,
                  builder: (context, layout, _) {
                    final eff = layout?.effectiveFraction;
                    final onDetent =
                        eff != null &&
                        _points.any((p) => (eff - p).abs() < _onDetentBand);
                    return Row(
                      children: [
                        AnimatedContainer(
                          duration: Motion.micro,
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: onDetent ? t.signal : t.textFaint,
                            shape: BoxShape.circle,
                            boxShadow: onDetent
                                ? [
                                    BoxShadow(
                                      color: t.signal.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          onDetent ? 'on detent' : 'free',
                          style: context.text.mono(
                            12,
                            color: onDetent ? t.signalText : t.textLo,
                            w: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Tag('detents · ${_points.length}', color: t.textLo),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Insets.md),
                Text(
                  _blurbs[_mode]!,
                  style: context.text
                      .mono(11, color: t.textFaint)
                      .copyWith(height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          CodeBlock(code: _codes[_mode]!),
        ],
      ),
    );
  }
}

class _SnapPane extends StatelessWidget {
  const _SnapPane({required this.label, required this.tone});
  final String label;
  final bool tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = tone ? t.signal : t.request;
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      child: Center(
        child: Text(
          label,
          style: context.text.mono(12, color: c, w: FontWeight.w700, ls: 1.5),
        ),
      ),
    );
  }
}

class _DetentPainter extends CustomPainter {
  _DetentPainter({
    required this.points,
    required this.layout,
    required this.mode,
    required this.signal,
    required this.line,
    required this.band,
    required this.influence,
    required this.labelStyle,
  });

  final List<double> points;
  final SplitterLayout? layout;
  final _Snap mode;
  final Color signal;
  final Color line;
  final double band;
  final double influence;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    if (l == null || l.availableExtent <= 0) return;
    final avail = l.availableExtent;
    final cur = l.effectiveFraction;

    // Magnetic-field affordance: only Magnetic exerts a continuous live pull,
    // so only it shows the glow + tension line. Release settles on release and
    // Sticky captures discretely; giving them a pull cue reads as false
    // stickiness, so they keep just the on-detent highlight drawn below.
    if (mode == _Snap.magnetic && influence > 0) {
      double? nearest;
      var best = double.infinity;
      for (final p in points) {
        final d = (cur - p).abs();
        if (d < best) {
          best = d;
          nearest = p;
        }
      }
      if (nearest != null) {
        final prox = (1 - best / influence).clamp(0.0, 1.0);
        if (prox > 0) {
          final detentX = (nearest * avail).clamp(0.0, size.width);
          final curX = (cur * avail).clamp(0.0, size.width);
          final midY = (size.height - 10) / 2;
          // Soft glow column on the target detent.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(detentX - 7, 4, 14, size.height - 22),
              const Radius.circular(7),
            ),
            Paint()
              ..color = signal.withValues(alpha: 0.16 * prox)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
          );
          // Tension line from the divider to the detent it is being drawn to.
          canvas.drawLine(
            Offset(curX, midY),
            Offset(detentX, midY),
            Paint()
              ..color = signal.withValues(alpha: 0.5 * prox)
              ..strokeWidth = 1.5
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    for (final p in points) {
      final x = (p * avail).clamp(0.0, size.width);
      // Proximity-based: the detent the divider is parked on glows amber, in
      // every mode - so the magnetic pull and the sticky capture both read.
      final near = (cur - p).abs() < band;
      final color = near ? signal : line.withValues(alpha: 0.5);
      final paint = Paint()
        ..color = color
        ..strokeWidth = near ? 2 : 1.2;
      // Dashed detent guide.
      double y = 8;
      while (y < size.height - 18) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 4, size.height - 18)),
          paint,
        );
        y += 8;
      }
      // Detent cap + label.
      canvas.drawCircle(
        Offset(x, size.height - 14),
        near ? 3.5 : 2.5,
        Paint()..color = color,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${(p * 100).round()}%',
          style: labelStyle.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 10));
    }
  }

  @override
  bool shouldRepaint(_DetentPainter old) =>
      old.layout != layout ||
      old.mode != mode ||
      old.band != band ||
      old.influence != influence;
}
