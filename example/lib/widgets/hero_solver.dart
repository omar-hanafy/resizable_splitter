import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'band_meter.dart';
import 'instrument.dart';

/// The hero instrument: one live splitter whose two channels - the *request*
/// (your intent) and the *result* (what the solver draws) - are made visible
/// side by side.
///
/// Drag the handle and the two channels stay locked (the solver's correctness
/// guarantee). Drive the intent slider or a pixel pin past the legal band and
/// the dashed "request ghost" separates from the resolved divider, a hatched
/// clamp zone lights between them, and the resolution badge flips.
class HeroSolver extends StatefulWidget {
  const HeroSolver({super.key});

  @override
  State<HeroSolver> createState() => _HeroSolverState();
}

class _HeroSolverState extends State<HeroSolver> {
  final SplitterController _controller = SplitterController(
    initialPosition: const SplitterPosition.fraction(0.42),
  );

  SplitterChangeSource? _lastSource;
  bool _interacting = false;

  // A stable identity for the splitter subtree so the responsive Row<->Column
  // flip (and any layout-time rebuild) moves it instead of re-inflating it -
  // re-inflation would attach a second splitter to this controller mid-layout.
  final GlobalKey _stageKey = GlobalKey();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setSource(SplitterChangeDetails d, {bool? interacting}) {
    setState(() {
      _lastSource = d.source;
      if (interacting != null) _interacting = interacting;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 920;
        final stage = _Stage(
          key: _stageKey,
          controller: _controller,
          onStart: (d) => _setSource(d, interacting: true),
          onChanged: _setSource,
          onEnd: (d) => _setSource(d, interacting: false),
        );
        final readout = _SidePanel(
          controller: _controller,
          lastSource: _lastSource,
          interacting: _interacting,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 320, child: stage),
              const SizedBox(height: Insets.lg),
              readout,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SizedBox(height: 416, child: stage)),
            const SizedBox(width: Insets.lg),
            SizedBox(width: 372, child: readout),
          ],
        );
      },
    );
  }
}

/// The framed splitter with the request-ghost overlay and the band meter below.
class _Stage extends StatelessWidget {
  const _Stage({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final SplitterController controller;
  final ValueChanged<SplitterChangeDetails> onStart;
  final ValueChanged<SplitterChangeDetails> onChanged;
  final ValueChanged<SplitterChangeDetails> onEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Panel(
            raised: true,
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GridPainter(
                      color: t.textFaint.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ResizableSplitter(
                    controller: controller,
                    startConstraints: const SplitterPaneConstraints(
                      minExtent: 150,
                    ),
                    endConstraints: const SplitterPaneConstraints(
                      minExtent: 190,
                    ),
                    minStartFraction: 0.16,
                    maxStartFraction: 0.74,
                    doubleTapResetTo: 0.5,
                    onChangeStart: onStart,
                    onChanged: onChanged,
                    onChangeEnd: onEnd,
                    divider: SplitterDividerStyle(
                      thickness: 2,
                      interactiveExtent: 40,
                      color: WidgetStateProperty.resolveWith((s) {
                        if (s.contains(WidgetState.dragged)) return t.signal;
                        if (s.contains(WidgetState.hovered) ||
                            s.contains(WidgetState.focused)) {
                          return t.signal.withValues(alpha: 0.6);
                        }
                        return t.lineStrong;
                      }),
                      builder: (context, d) => _HeroHandle(details: d),
                    ),
                    start: _MeasuredPane(
                      controller: controller,
                      pane: SplitterPane.start,
                      label: 'START',
                    ),
                    end: _MeasuredPane(
                      controller: controller,
                      pane: SplitterPane.end,
                      label: 'END',
                    ),
                  ),
                ),
                // Request ghost overlay - never intercepts the divider.
                Positioned.fill(
                  child: IgnorePointer(
                    child: _GhostOverlay(controller: controller),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 12,
                  child: Row(
                    children: [
                      SignalDot(color: t.signal, live: true, size: 6),
                      const SizedBox(width: 4),
                      Text(
                        'LIVE SOLVER',
                        style: context.text.mono(
                          10,
                          color: t.textFaint,
                          ls: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.md),
        ValueListenableBuilder<SplitterLayout?>(
          valueListenable: controller.layoutListenable,
          builder: (context, layout, _) {
            return ValueListenableBuilder<SplitterState>(
              valueListenable: controller,
              builder: (context, state, _) {
                final avail = layout?.availableExtent;
                final reqF = (avail != null && avail > 0)
                    ? state.position.resolveFraction(avail)
                    : null;
                return BandMeter(layout: layout, requestFraction: reqF);
              },
            );
          },
        ),
      ],
    );
  }
}

/// Custom grip: a rounded bar of three nubs that warms from line -> amber as it
/// is hovered, focused, or dragged. Stable bounds (no layout shift on press).
class _HeroHandle extends StatelessWidget {
  const _HeroHandle({required this.details});
  final SplitterHandleDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active =
        details.isDragging || details.isHovering || details.isFocused;
    final color = details.isDragging
        ? t.signal
        : active
        ? t.signal.withValues(alpha: 0.75)
        : t.lineStrong;
    final horizontal = details.axis == Axis.horizontal;
    return Center(
      child: AnimatedContainer(
        duration: Motion.micro,
        width: horizontal ? 6 : 40,
        height: horizontal ? 40 : 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          boxShadow: details.isDragging
              ? [
                  BoxShadow(
                    color: t.signal.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// A pane that reports its own resolved extent in logical pixels - the layout's
/// result, surfaced where it is measured.
class _MeasuredPane extends StatelessWidget {
  const _MeasuredPane({
    required this.controller,
    required this.pane,
    required this.label,
  });

  final SplitterController controller;
  final SplitterPane pane;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isStart = pane == SplitterPane.start;
    return Container(
      margin: const EdgeInsets.all(Insets.sm),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.5 : 0.8),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      child: Center(
        child: ValueListenableBuilder<SplitterLayout?>(
          valueListenable: controller.layoutListenable,
          builder: (context, layout, _) {
            final ext = layout == null
                ? null
                : (isStart ? layout.startExtent : layout.endExtent);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.text.mono(11, color: t.textFaint, ls: 2),
                ),
                const SizedBox(height: 6),
                Text(
                  ext == null ? '—' : '${ext.round()}',
                  style: context.text.mono(
                    26,
                    color: t.textHi,
                    w: FontWeight.w600,
                  ),
                ),
                Text('px', style: context.text.mono(11, color: t.textFaint)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Paints the dashed request line and, when intent leaves the legal band, a
/// hatched clamp bridge to the resolved divider with the gap in pixels.
class _GhostOverlay extends StatelessWidget {
  const _GhostOverlay({required this.controller});
  final SplitterController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<SplitterLayout?>(
      valueListenable: controller.layoutListenable,
      builder: (context, layout, _) {
        return ValueListenableBuilder<SplitterState>(
          valueListenable: controller,
          builder: (context, state, _) {
            if (layout == null || layout.availableExtent <= 0) {
              return const SizedBox.shrink();
            }
            final avail = layout.availableExtent;
            final reqF = state.position.resolveFraction(avail);
            final ghostX = reqF * avail;
            // The resolved divider is the request clamped to the legal band.
            // Deriving it from the (stable) band rather than the separately-
            // published startExtent keeps the two in lock-step during a drag,
            // so a moving divider never reads as a one-frame "clamp".
            final solidX = ghostX
                .clamp(layout.minStartExtent, layout.maxStartExtent)
                .toDouble();
            return CustomPaint(
              painter: _GhostPainter(
                ghostX: ghostX,
                solidX: solidX,
                request: t.request,
                danger: t.danger,
                labelStyle: context.text.mono(
                  10,
                  color: t.danger,
                  w: FontWeight.w700,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.ghostX,
    required this.solidX,
    required this.request,
    required this.danger,
    required this.labelStyle,
  });

  final double ghostX;
  final double solidX;
  final Color request;
  final Color danger;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = (ghostX - solidX).abs();
    final diverged = gap > 2.5;

    // Hatched clamp zone between intent and result.
    if (diverged) {
      final rect = Rect.fromLTRB(
        ghostX < solidX ? ghostX : solidX,
        0,
        ghostX < solidX ? solidX : ghostX,
        size.height,
      );
      canvas.save();
      canvas.clipRect(rect);
      final hatch = Paint()
        ..color = danger.withValues(alpha: 0.20)
        ..strokeWidth = 1;
      for (double x = rect.left - size.height; x < rect.right; x += 7) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          hatch,
        );
      }
      canvas.restore();

      // Gap label.
      final tp = TextPainter(
        text: TextSpan(text: 'Δ ${gap.round()}px clamped', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = (ghostX + solidX) / 2;
      final bg = Rect.fromCenter(
        center: Offset(cx, 20),
        width: tp.width + 12,
        height: tp.height + 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(4)),
        Paint()..color = danger.withValues(alpha: 0.14),
      );
      tp.paint(canvas, Offset(cx - tp.width / 2, 20 - tp.height / 2));
    }

    // Dashed request line.
    final paint = Paint()
      ..color = diverged ? request : request.withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(ghostX, y), Offset(ghostX, y + 5), paint);
      y += 9;
    }
    // Intent cap markers.
    final cap = Paint()
      ..color = diverged ? request : request.withValues(alpha: 0.55);
    canvas.drawCircle(Offset(ghostX, 3), 2.5, cap);
    canvas.drawCircle(Offset(ghostX, size.height - 3), 2.5, cap);
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.ghostX != ghostX ||
      old.solidX != solidX ||
      old.request != request ||
      old.danger != danger;
}

/// The readout + intent controls beside the stage.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.controller,
    required this.lastSource,
    required this.interacting,
  });

  final SplitterController controller;
  final SplitterChangeSource? lastSource;
  final bool interacting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadoutCard(
          controller: controller,
          lastSource: lastSource,
          interacting: interacting,
        ),
        const SizedBox(height: Insets.md),
        _IntentControls(controller: controller),
      ],
    );
  }
}

class _ReadoutCard extends StatelessWidget {
  const _ReadoutCard({
    required this.controller,
    required this.lastSource,
    required this.interacting,
  });

  final SplitterController controller;
  final SplitterChangeSource? lastSource;
  final bool interacting;

  String _requestLabel(SplitterPosition p) => switch (p) {
    FractionSplitterPosition(:final value) =>
      'fraction · ${(value.clamp(0, 1) * 100).toStringAsFixed(0)}%',
    StartPixelsSplitterPosition(:final extent) => 'start · ${extent.round()}px',
    EndPixelsSplitterPosition(:final extent) => 'end · ${extent.round()}px',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      raised: true,
      padding: const EdgeInsets.all(Insets.lg),
      child: ValueListenableBuilder<SplitterState>(
        valueListenable: controller,
        builder: (context, state, _) {
          return ValueListenableBuilder<SplitterLayout?>(
            valueListenable: controller.layoutListenable,
            builder: (context, layout, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // REQUEST channel.
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.request,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'REQUEST',
                        style: context.text.monoKey.copyWith(color: t.request),
                      ),
                      const Spacer(),
                      Text(
                        _requestLabel(state.position),
                        style: context.text.mono(
                          12.5,
                          color: t.request,
                          w: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.md),
                  Divider(height: 1, color: t.line),
                  const SizedBox(height: Insets.md),
                  // RESULT channel.
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.signal,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RESULT',
                        style: context.text.monoKey.copyWith(
                          color: t.signalText,
                        ),
                      ),
                      const Spacer(),
                      if (layout != null) ResolutionBadge(layout.resolution),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  Row(
                    children: [
                      Expanded(
                        child: StatCell(
                          label: 'EFFECTIVE',
                          value: layout == null
                              ? '—'
                              : (layout.effectiveFraction * 100)
                                    .toStringAsFixed(1),
                          unit: '%',
                          valueColor: t.signal,
                          big: true,
                        ),
                      ),
                      Expanded(
                        child: StatCell(
                          label: 'AVAILABLE',
                          value: layout == null
                              ? '—'
                              : '${layout.availableExtent.round()}',
                          unit: 'px',
                        ),
                      ),
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
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  _SourceRow(lastSource: lastSource, interacting: interacting),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.lastSource, required this.interacting});
  final SplitterChangeSource? lastSource;
  final bool interacting;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = lastSource?.name ?? 'idle';
    return Row(
      children: [
        Text('SOURCE', style: context.text.monoKey),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: Motion.micro,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: interacting ? t.signalSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.xs),
            border: Border.all(
              color: interacting ? t.signal.withValues(alpha: 0.5) : t.line,
            ),
          ),
          child: Text(
            name,
            style: context.text.mono(
              11.5,
              color: interacting ? t.signalText : t.textLo,
              w: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        Icon(
          Icons.bolt_rounded,
          size: 13,
          color: interacting ? t.signal : t.textFaint,
        ),
      ],
    );
  }
}

class _IntentControls extends StatelessWidget {
  const _IntentControls({required this.controller});
  final SplitterController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      raised: true,
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: t.request),
              const SizedBox(width: 8),
              Text(
                'DRIVE THE INTENT',
                style: context.text.monoKey.copyWith(color: t.request),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Set a request directly. Push past the band - the divider holds, the ghost runs ahead.',
            style: context.text
                .mono(11, color: t.textFaint)
                .copyWith(height: 1.5),
          ),
          const SizedBox(height: Insets.md),
          ValueListenableBuilder<SplitterState>(
            valueListenable: controller,
            builder: (context, state, _) {
              return ValueListenableBuilder<SplitterLayout?>(
                valueListenable: controller.layoutListenable,
                builder: (context, layout, _) {
                  final avail = layout?.availableExtent ?? 1;
                  final reqF = state.position.resolveFraction(
                    avail > 0 ? avail : 1,
                  );
                  return SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: t.request,
                      inactiveTrackColor: t.line,
                      thumbColor: t.request,
                      overlayColor: t.request.withValues(alpha: 0.16),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    child: Slider(
                      value: reqF.clamp(0.0, 1.0),
                      onChanged: (v) =>
                          controller.jumpTo(SplitterPosition.fraction(v)),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: Insets.xs),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              _ChipButton(
                label: 'fraction 50%',
                onTap: () =>
                    controller.jumpTo(const SplitterPosition.fraction(0.5)),
              ),
              _ChipButton(
                label: 'pin start 280px',
                onTap: () =>
                    controller.jumpTo(const SplitterPosition.startPixels(280)),
              ),
              _ChipButton(
                label: 'pin end 320px',
                onTap: () =>
                    controller.jumpTo(const SplitterPosition.endPixels(320)),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  onTap: () => controller.reset(),
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: _ActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Animate → 70%',
                  primary: true,
                  onTap: () => controller.animateTo(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.onTap});
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

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
            color: primary ? t.signal : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.sm),
            border: Border.all(color: primary ? t.signal : t.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: primary ? const Color(0xFF1A1206) : t.textHi,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.mono(
                  12,
                  color: primary ? const Color(0xFF1A1206) : t.textHi,
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
