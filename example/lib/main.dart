import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stations/a11y.dart';
import 'stations/collapse.dart';
import 'stations/constraints.dart';
import 'stations/ide.dart';
import 'stations/pixel_pin.dart';
import 'stations/snapping.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/code_block.dart';
import 'widgets/hero_solver.dart';
import 'widgets/instrument.dart';
import 'widgets/top_bar.dart';

void main() {
  runApp(const SplitterShowcaseApp());
}

/// Root: owns the theme mode and feeds both light and dark [ThemeData] in so the
/// toggle lerps the whole palette.
class SplitterShowcaseApp extends StatefulWidget {
  const SplitterShowcaseApp({super.key});

  @override
  State<SplitterShowcaseApp> createState() => _SplitterShowcaseAppState();
}

class _SplitterShowcaseAppState extends State<SplitterShowcaseApp> {
  ThemeMode _mode = ThemeMode.dark;

  void _toggle() => setState(
    () => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'resizable_splitter',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      scrollBehavior: const _DesktopScrollBehavior(),
      home: ShowcasePage(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: _toggle,
      ),
    );
  }
}

/// Enables drag-to-scroll with mouse/trackpad on web and desktop.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class ShowcasePage extends StatefulWidget {
  const ShowcasePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const sections = <Widget>[
      PixelPinStation(),
      ConstraintsStation(),
      SnappingStation(),
      CollapseStation(),
      IdeStation(),
      A11yStation(),
    ];

    return Scaffold(
      backgroundColor: t.ink,
      body: Stack(
        children: [
          // Faint global drafting grid.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: GridPainter(
                  color: t.textFaint.withValues(alpha: 0.05),
                  step: 32,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    const HeroSection(),
                    for (var i = 0; i < sections.length; i++)
                      _SectionFrame(scroll: _scroll, child: sections[i]),
                    _SectionFrame(
                      scroll: _scroll,
                      child: const QuickStartSection(),
                    ),
                    const FooterSection(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TopBar(
              isDark: widget.isDark,
              onToggleTheme: widget.onToggleTheme,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps each section in a centered max-width frame and a scroll-reveal.
class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.scroll, required this.child});
  final ScrollController scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.section),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.maxContent),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
            child: Reveal(scroll: scroll, child: child),
          ),
        ),
      ),
    );
  }
}

/// The thesis hero: the package's idea in a sentence, then the live solver.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: [
        // Soft amber glow behind the hero.
        Positioned(
          top: -120,
          left: 0,
          right: 0,
          height: 460,
          child: IgnorePointer(
            child: Center(
              child: Container(
                width: 720,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      t.signal.withValues(alpha: t.isDark ? 0.10 : 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Insets.maxContent),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, 64, Insets.xl, 0),
              child: LayoutBuilder(
                builder: (context, c) {
                  final headSize = c.maxWidth < 560
                      ? 40.0
                      : c.maxWidth < 820
                      ? 54.0
                      : 68.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RevealOnLoad(
                        order: 0,
                        child: Row(
                          children: [
                            SignalDot(color: t.signal, live: true, size: 7),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'ONE SOLVER BEHIND DRAG · KEYS · SNAP · A11Y',
                                style: context.text.eyebrow.copyWith(
                                  color: t.textLo,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Insets.lg),
                      _RevealOnLoad(
                        order: 1,
                        child: RichText(
                          text: TextSpan(
                            style: context.text.hero(headSize),
                            children: [
                              const TextSpan(text: 'Store the '),
                              TextSpan(
                                text: 'intent',
                                style: TextStyle(color: t.request),
                              ),
                              const TextSpan(text: '.\nResolve '),
                              TextSpan(
                                text: 'every frame',
                                style: TextStyle(color: t.signal),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Insets.xl),
                      _RevealOnLoad(
                        order: 2,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Text(
                            'A two-pane splitter built on one pure constraint solver. You store a '
                            'request - a fraction or a pixel pin. It resolves the on-screen geometry '
                            'every layout pass, so the position you keep can never disagree with the '
                            'pixels you see.',
                            style: context.text.body(
                              16.5,
                              color: t.textLo,
                              h: 1.65,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Insets.xl),
                      _RevealOnLoad(order: 3, child: const _InstallRow()),
                      const SizedBox(height: Insets.xxl),
                      _RevealOnLoad(order: 4, child: const HeroSolver()),
                      const SizedBox(height: Insets.xl),
                      _RevealOnLoad(order: 5, child: const _ClaimsStrip()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InstallRow extends StatelessWidget {
  const _InstallRow();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InstallChip(),
        const SizedBox(height: Insets.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'drag the divider below',
              style: context.text.mono(12, color: t.textFaint),
            ),
            const SizedBox(width: 6),
            Icon(Icons.south_rounded, size: 13, color: t.textFaint),
          ],
        ),
      ],
    );
  }
}

class _InstallChip extends StatefulWidget {
  @override
  State<_InstallChip> createState() => _InstallChipState();
}

class _InstallChipState extends State<_InstallChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      const ClipboardData(text: 'flutter pub add resizable_splitter'),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _copy,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(Corner.sm),
              border: Border.all(color: t.lineStrong),
            ),
            child: Row(
              children: [
                Text(
                  '\$',
                  style: context.text.mono(
                    13,
                    color: t.signalText,
                    w: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'flutter pub add resizable_splitter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.mono(13, color: t.textHi),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Icon(
                  _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                  size: 13,
                  color: _copied ? t.good : t.textLo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClaimsStrip extends StatelessWidget {
  const _ClaimsStrip();

  static const _claims = [
    (
      Icons.straighten_rounded,
      'Pixel-pinned sidebars',
      'survive container resizes',
    ),
    (
      Icons.account_tree_outlined,
      'RenderObject-backed',
      'intrinsic sizing, dry layout',
    ),
    (
      Icons.unfold_less_rounded,
      "Collapse that can't desync",
      'part of the atomic state',
    ),
    (
      Icons.accessibility_new_rounded,
      'Accessible by default',
      'keys, semantics, RTL, haptics',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 560 ? 1 : (c.maxWidth < 900 ? 2 : 4);
        return Wrap(
          spacing: Insets.md,
          runSpacing: Insets.md,
          children: [
            for (final claim in _claims)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * Insets.md) / cols,
                child: Container(
                  padding: const EdgeInsets.all(Insets.md),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: t.lineStrong, width: 1.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(claim.$1, size: 18, color: t.signalText),
                      const SizedBox(height: Insets.sm),
                      Text(
                        claim.$2,
                        style: context.text.body(14, w: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        claim.$3,
                        style: context.text.mono(11, color: t.textFaint),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Closing get-started: install, the minimum usage, and what was on show.
class QuickStartSection extends StatelessWidget {
  const QuickStartSection({super.key});

  static const _yaml = '''dependencies:
  resizable_splitter: ^2.0.0''';

  static const _dart = '''ResizableSplitter(
  start: const Center(child: Text('Navigation')),
  end: const Center(child: Text('Content')),
  onChanged: (d) =>
      debugPrint('ratio: \${d.effectiveFraction}'),
);''';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          index: '07',
          eyebrow: 'GET STARTED',
          title: 'Two panes and a callback',
          blurb:
              'That is the whole minimum. The divider starts centered, is keyboard '
              'focusable, exposes slider semantics, and shields platform views '
              'during a drag - with no extra configuration.',
        ),
        const SizedBox(height: Insets.xl),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 820;
            final yaml = CodeBlock(code: _yaml, label: 'pubspec.yaml');
            final dart = CodeBlock(code: _dart, label: 'main.dart');
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  yaml,
                  const SizedBox(height: Insets.md),
                  dart,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: yaml),
                const SizedBox(width: Insets.lg),
                Expanded(flex: 3, child: dart),
              ],
            );
          },
        ),
      ],
    );
  }
}

class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.section),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Insets.maxContent),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xl,
                vertical: Insets.xl,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                runSpacing: Insets.md,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(size: 22),
                      const SizedBox(width: Insets.md),
                      Text(
                        'resizable_splitter',
                        style: context.text.mono(
                          13,
                          color: t.textHi,
                          w: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Text(
                        'MIT licensed',
                        style: context.text.mono(11.5, color: t.textFaint),
                      ),
                    ],
                  ),
                  Text(
                    'Every divider on this page is the package itself.',
                    style: context.text.mono(11, color: t.textFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Reveal animations - respect reduced motion, never hide content permanently.
// ===========================================================================

/// A page-load reveal that fades and lifts its child, staggered by [order].
class _RevealOnLoad extends StatefulWidget {
  const _RevealOnLoad({required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  State<_RevealOnLoad> createState() => _RevealOnLoadState();
}

class _RevealOnLoadState extends State<_RevealOnLoad> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(Duration(milliseconds: 70 * widget.order), () {
        if (mounted) setState(() => _shown = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.06),
      duration: Motion.slow,
      curve: Motion.enter,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: Motion.slow,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

/// Reveals its child the first time it scrolls within viewport. Defaults to
/// visible if motion is disabled or the geometry can't be measured.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.scroll, required this.child});
  final ScrollController scroll;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  final GlobalKey _key = GlobalKey();
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_shown || !mounted) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero).dy;
    final viewport = MediaQuery.of(context).size.height;
    if (pos < viewport - 80) {
      setState(() => _shown = true);
      widget.scroll.removeListener(_check);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return KeyedSubtree(key: _key, child: widget.child);
    }
    return KeyedSubtree(
      key: _key,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.04),
        duration: Motion.slow,
        curve: Motion.enter,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: Motion.slow,
          curve: Motion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}
