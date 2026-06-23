import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A horizontal instrument that plots the start pane's extent against the legal
/// band the solver computed for this layout.
///
/// The full track is `[0 .. available]`. The brighter segment is the legal band
/// `[minStartExtent .. maxStartExtent]`; outside it is hatched as "illegal". A
/// solid amber needle marks the resolved [SplitterLayout.startExtent]; an
/// optional dashed tick marks where the *request* asks for, and the gap between
/// them is filled when intent overshoots the band. The band edge flares in the
/// danger color when the divider can no longer move that way.
class BandMeter extends StatelessWidget {
  const BandMeter({super.key, required this.layout, this.requestFraction});

  final SplitterLayout? layout;

  /// The requested start fraction in `[0, 1]`, if a separate intent is driving
  /// the divider (null hides the ghost tick).
  final double? requestFraction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: 'Constraint band meter',
      child: SizedBox(
        height: 58,
        child: CustomPaint(
          painter: _BandPainter(
            layout: layout,
            requestFraction: requestFraction,
            t: t,
            monoStyle: context.text.mono(10.5, color: t.textFaint),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.layout,
    required this.requestFraction,
    required this.t,
    required this.monoStyle,
  });

  final SplitterLayout? layout;
  final double? requestFraction;
  final AppTokens t;
  final TextStyle monoStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const trackY = 22.0;
    const trackH = 12.0;
    final w = size.width;
    final l = layout;

    // Baseline track.
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, w, trackH),
      const Radius.circular(3),
    );
    canvas.drawRRect(trackRect, Paint()..color = t.line);

    if (l == null || l.availableExtent <= 0) {
      _label(
        canvas,
        '— no layout —',
        Offset(0, trackY + trackH + 8),
        t.textFaint,
      );
      return;
    }

    final avail = l.availableExtent;
    double x(double extent) => (extent / avail).clamp(0.0, 1.0) * w;

    final minX = x(l.minStartExtent);
    final maxX = x(l.maxStartExtent);
    final curX = x(l.startExtent);

    // Illegal zones (outside the band) - hatched, faint.
    _hatch(
      canvas,
      Rect.fromLTWH(0, trackY, minX, trackH),
      t.textFaint.withValues(alpha: 0.22),
    );
    _hatch(
      canvas,
      Rect.fromLTWH(maxX, trackY, w - maxX, trackH),
      t.textFaint.withValues(alpha: 0.22),
    );

    // Legal band.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(minX, trackY, math.max(0, maxX - minX), trackH),
        const Radius.circular(3),
      ),
      Paint()..color = t.signal.withValues(alpha: 0.18),
    );

    // Request ghost: a dashed tick, plus a hatched overshoot bridge to the
    // needle when intent lands outside the band.
    if (requestFraction != null) {
      final reqX = (requestFraction!.clamp(0.0, 1.0)) * w;
      // Bridge the intent tick to where the band actually clamps it - using the
      // stable band edges (not the frame-lagged needle) so an in-band drag never
      // shows a phantom overshoot.
      final clampedReqX = reqX.clamp(minX, maxX);
      if ((reqX - clampedReqX).abs() > 1.5) {
        _hatch(
          canvas,
          Rect.fromLTWH(
            math.min(reqX, clampedReqX),
            trackY,
            (reqX - clampedReqX).abs(),
            trackH,
          ),
          t.danger.withValues(alpha: 0.28),
        );
      }
      _dashedV(canvas, reqX, trackY - 6, trackY + trackH + 6, t.request);
      _tickLabel(canvas, 'intent', reqX, trackY - 9, t.request, above: true);
    }

    // Band edges - flare danger when the divider is pinned that way.
    _edge(
      canvas,
      minX,
      trackY,
      trackH,
      l.canDecrease ? t.lineStrong : t.danger,
    );
    _edge(
      canvas,
      maxX,
      trackY,
      trackH,
      l.canIncrease ? t.lineStrong : t.danger,
    );

    // The needle: resolved start extent.
    final needle = Paint()..color = t.signal;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(curX, trackY + trackH / 2),
          width: 3,
          height: trackH + 12,
        ),
        const Radius.circular(2),
      ),
      needle,
    );
    canvas.drawCircle(Offset(curX, trackY + trackH / 2), 4.5, needle);

    // Scale labels: 0, min, max, available.
    _label(canvas, '0', Offset(0, trackY + trackH + 8), t.textFaint);
    _label(
      canvas,
      '${l.availableExtent.round()}px',
      Offset(w, trackY + trackH + 8),
      t.textFaint,
      alignRight: true,
    );
    _tickLabel(
      canvas,
      '${l.minStartExtent.round()}',
      minX,
      trackY + trackH + 8,
      l.canDecrease ? t.textLo : t.danger,
    );
    _tickLabel(
      canvas,
      '${l.maxStartExtent.round()}',
      maxX,
      trackY + trackH + 8,
      l.canIncrease ? t.textLo : t.danger,
    );
  }

  void _edge(Canvas canvas, double cx, double y, double h, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 1, y - 3, 2, h + 6),
        const Radius.circular(1),
      ),
      Paint()..color = color,
    );
  }

  void _dashedV(
    Canvas canvas,
    double x,
    double top,
    double bottom,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double y = top;
    while (y < bottom) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, bottom)), paint);
      y += 7;
    }
  }

  void _hatch(Canvas canvas, Rect rect, Color color) {
    if (rect.width <= 0) return;
    canvas.save();
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = rect.left - rect.height; x < rect.right; x += 6) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool alignRight = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: monoStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - tp.width : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  void _tickLabel(
    Canvas canvas,
    String text,
    double cx,
    double y,
    Color color, {
    bool above = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: monoStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, above ? y - tp.height : y));
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.layout != layout ||
      old.requestFraction != requestFraction ||
      old.t != t;
}
