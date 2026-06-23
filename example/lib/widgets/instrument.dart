import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A framed surface in the instrument language: crisp border, small radius,
/// optional raised fill. The basic container every panel is built from.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.raised = false,
    this.color,
    this.border,
    this.radius = Corner.md,
    this.clip = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool raised;
  final Color? color;
  final Color? border;
  final double radius;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      clipBehavior: clip,
      decoration: BoxDecoration(
        color: color ?? (raised ? t.surfaceHi : t.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? t.line),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A faint blueprint grid - the drafting-table backdrop. Draws a dot at each
/// grid intersection plus optional axis rules.
class GridPainter extends CustomPainter {
  const GridPainter({required this.color, this.step = 28, this.dot = 1.1});

  final Color color;
  final double step;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = step; y < size.height; y += step) {
      for (double x = step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), dot, paint);
      }
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.color != color || old.step != step || old.dot != dot;
}

/// The brand mark: two panes split by a divider, drawn as a glyph so it scales
/// crisply and themes with the palette. No emoji, no raster.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CustomPaint(
      size: Size.square(size),
      painter: _BrandPainter(t.textHi, t.signal),
    );
  }
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.frame, this.signal);
  final Color frame;
  final Color signal;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..color = frame;
    canvas.drawRRect(r.deflate(size.width * 0.05), stroke);

    // Divider, offset off-center to read as "resizable".
    final x = size.width * 0.62;
    canvas.drawLine(
      Offset(x, size.height * 0.12),
      Offset(x, size.height * 0.88),
      Paint()
        ..color = signal
        ..strokeWidth = size.width * 0.085
        ..strokeCap = StrokeCap.round,
    );
    // Grab nub on the divider.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height * 0.5),
          width: size.width * 0.085,
          height: size.height * 0.26,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = signal,
    );
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.frame != frame || old.signal != signal;
}

/// A small status dot, optionally pulsing to signal "live".
class SignalDot extends StatefulWidget {
  const SignalDot({
    super.key,
    required this.color,
    this.live = false,
    this.size = 7,
  });
  final Color color;
  final bool live;
  final double size;

  @override
  State<SignalDot> createState() => _SignalDotState();
}

class _SignalDotState extends State<SignalDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live) _c.repeat();
  }

  @override
  void didUpdateWidget(SignalDot old) {
    super.didUpdateWidget(old);
    if (widget.live && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.live && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final glow = widget.live
              ? (0.5 + 0.5 * math.sin(_c.value * math.pi * 2))
              : 0.0;
          return SizedBox(
            width: widget.size + 8,
            height: widget.size + 8,
            child: Center(
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: widget.live
                      ? [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.55 * glow),
                            blurRadius: 8 + 4 * glow,
                            spreadRadius: 1 + glow,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A compact mono label pill - a measurement tag.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.filled = false, this.icon});
  final String text;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = color ?? t.textLo;
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 3.5, 8, 3.5),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(Corner.xs),
        border: Border.all(color: c.withValues(alpha: filled ? 0.0 : 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: context.text.mono(11, color: c, w: FontWeight.w600, ls: 0.4),
          ),
        ],
      ),
    );
  }
}

/// A labelled instrument readout cell: a small uppercase key over a mono value.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.unit,
    this.big = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? unit;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.text.monoKey),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.mono(
                  big ? 22 : 15,
                  color: valueColor ?? t.textHi,
                  w: big ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(unit!, style: context.text.mono(11, color: t.textFaint)),
            ],
          ],
        ),
      ],
    );
  }
}

/// Maps a [SplitterResolution] to its display color, label, and one-line
/// meaning - the solver's verdict, surfaced honestly.
({Color color, String label, String hint}) describeResolution(
  AppTokens t,
  SplitterResolution r,
) {
  switch (r) {
    case SplitterResolution.exact:
      return (color: t.good, label: 'EXACT', hint: 'Request honored as-is.');
    case SplitterResolution.clamped:
      return (
        color: t.signal,
        label: 'CLAMPED',
        hint: 'Request clamped to the legal band.',
      );
    case SplitterResolution.minShortage:
      return (
        color: t.danger,
        label: 'MIN SHORTAGE',
        hint: "Both minimums can't fit - policy decided the split.",
      );
    case SplitterResolution.maxSurplus:
      return (
        color: t.request,
        label: 'MAX SURPLUS',
        hint: "Both maximums can't fill - surplus policy applied.",
      );
    case SplitterResolution.fractionConflict:
      return (
        color: t.danger,
        label: 'FRACTION CONFLICT',
        hint: 'Fractional caps emptied the band - pixel limits won.',
      );
    case SplitterResolution.collapsed:
      return (
        color: t.request,
        label: 'COLLAPSED',
        hint: 'A pane is collapsed in this layout.',
      );
    case SplitterResolution.inactive:
      return (
        color: t.textFaint,
        label: 'INACTIVE',
        hint: 'No usable space yet.',
      );
  }
}

/// A pill that reports how the solver resolved the current request.
class ResolutionBadge extends StatelessWidget {
  const ResolutionBadge(this.resolution, {super.key});
  final SplitterResolution resolution;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = describeResolution(t, resolution);
    return Tooltip(
      message: d.hint,
      child: AnimatedContainer(
        duration: Motion.micro,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
          color: d.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Corner.xs),
          border: Border.all(color: d.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: d.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              d.label,
              style: context.text.mono(
                11,
                color: d.color,
                w: FontWeight.w700,
                ls: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a dashed line along an axis - the "request ghost" marker.
class DashedLinePainter extends CustomPainter {
  const DashedLinePainter({
    required this.color,
    this.axis = Axis.vertical,
    this.dash = 5,
    this.gap = 4,
    this.thickness = 1.5,
  });

  final Color color;
  final Axis axis;
  final double dash;
  final double gap;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final total = axis == Axis.vertical ? size.height : size.width;
    double pos = 0;
    while (pos < total) {
      final end = math.min(pos + dash, total);
      if (axis == Axis.vertical) {
        canvas.drawLine(
          Offset(size.width / 2, pos),
          Offset(size.width / 2, end),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(pos, size.height / 2),
          Offset(end, size.height / 2),
          paint,
        );
      }
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(DashedLinePainter old) =>
      old.color != color ||
      old.axis != axis ||
      old.dash != dash ||
      old.gap != gap ||
      old.thickness != thickness;
}

/// Diagonal hatching - fills the "clamped" zone between intent and result.
class HatchPainter extends CustomPainter {
  const HatchPainter({
    required this.color,
    this.spacing = 7,
    this.thickness = 1,
  });
  final Color color;
  final double spacing;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HatchPainter old) =>
      old.color != color || old.spacing != spacing;
}

/// A lightweight segmented toggle in the instrument style. One primary choice,
/// the active segment carried by the amber signal.
class SegToggle<T> extends StatelessWidget {
  const SegToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label, IconData? icon})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.ink.withValues(alpha: t.isDark ? 0.5 : 0.04),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in segments)
            _Segment(
              label: s.label,
              icon: s.icon,
              active: s.value == selected,
              onTap: () => onChanged(s.value),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

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
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? t.signalSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.xs),
            border: Border.all(
              color: active
                  ? t.signal.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: active ? t.signalText : t.textLo),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: context.text.mono(
                  12,
                  color: active ? t.signalText : t.textLo,
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

/// Section header: a numbered eyebrow, a display title, and a lead paragraph.
/// The numbering is real - the page is an ordered tour of capabilities.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.index,
    required this.eyebrow,
    required this.title,
    required this.blurb,
  });

  final String index;
  final String eyebrow;
  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              index,
              style: context.text.mono(
                13,
                color: t.signalText,
                w: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 22, height: 1.5, color: t.lineStrong),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.eyebrow.copyWith(color: t.textLo),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        Text(title, style: context.text.sectionTitle),
        const SizedBox(height: Insets.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(blurb, style: context.text.bodyLo),
        ),
      ],
    );
  }
}
