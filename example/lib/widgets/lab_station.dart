import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'instrument.dart';

/// One numbered capability in the tour: a header, a live demo stage, and an
/// optional side column for controls, readout, or code. Collapses to a single
/// column below 900px.
class Station extends StatelessWidget {
  const Station({
    super.key,
    required this.index,
    required this.eyebrow,
    required this.title,
    required this.blurb,
    required this.demo,
    this.side,
    this.demoHeight = 360,
    this.sideWidth = 340,
  });

  final String index;
  final String eyebrow;
  final String title;
  final String blurb;
  final Widget demo;
  final Widget? side;
  final double demoHeight;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: index,
          eyebrow: eyebrow,
          title: title,
          blurb: blurb,
        ),
        const SizedBox(height: Insets.xl),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 900 || side == null;
            final stage = SizedBox(height: demoHeight, child: demo);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stage,
                  if (side != null) ...[
                    const SizedBox(height: Insets.lg),
                    side!,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: stage),
                const SizedBox(width: Insets.lg),
                SizedBox(width: sideWidth, child: side),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A framed canvas on the blueprint grid that hosts a live splitter. The corner
/// carries a small "LIVE" tag so the demo reads as an instrument, not a picture.
class DemoStage extends StatelessWidget {
  const DemoStage({
    super.key,
    required this.child,
    this.label = 'LIVE',
    this.padded = true,
  });

  final Widget child;
  final String label;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      raised: true,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(color: t.textFaint.withValues(alpha: 0.10)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(padded ? Insets.md : 0),
              child: child,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              children: [
                SignalDot(color: t.signal, live: true, size: 6),
                const SizedBox(width: 2),
                Text(
                  label,
                  style: context.text.mono(10, color: t.textFaint, ls: 1.5),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
