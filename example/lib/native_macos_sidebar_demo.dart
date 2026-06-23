import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// Fixed pixel widths the sidebar "clicks" onto. macOS sidebars feel like they
/// snap to a few set widths regardless of window size, so we express the detents
/// in pixels and convert to fractions per layout.
const List<double> _detentPixels = <double>[220, 280, 340];

/// Converts the fixed pixel detents to start-fractions for the given available
/// main extent.
///
/// `SplitterSnapBehavior` points are fractions in `[0, 1]`, but a sidebar wants
/// fixed-pixel stops. Recomputing this per layout (inside a [LayoutBuilder])
/// keeps the detents feeling pixel-anchored as the window resizes. A
/// non-positive or non-finite extent yields safe zeros instead of NaN.
List<double> macosSidebarDetentFractions(double availableExtent) {
  if (!availableExtent.isFinite || availableExtent <= 0) {
    return const <double>[0, 0, 0];
  }
  return _detentPixels
      .map((px) => (px / availableExtent).clamp(0.0, 1.0).toDouble())
      .toList(growable: false);
}

/// A full-screen demo that dresses [ResizableSplitter] in native macOS chrome
/// (macos_ui): a real [ToolBar] over a sidebar | content split, with sticky
/// pixel detents and a collapsible sidebar driven by [SplitterController].
///
/// Rooted under [MacosTheme] + [MacosScaffold] (not [MacosWindow]): this is an
/// embedded route inside a Material app, not the OS window root, so the
/// window-level chrome stays out of scope.
class NativeMacosSplitterDemo extends StatefulWidget {
  const NativeMacosSplitterDemo({super.key, this.controller});

  /// Optional injected controller. When null, the demo creates and owns one.
  /// Injection lets tests assert on [SplitterController.collapsedPane].
  final SplitterController? controller;

  @override
  State<NativeMacosSplitterDemo> createState() =>
      _NativeMacosSplitterDemoState();
}

class _NativeMacosSplitterDemoState extends State<NativeMacosSplitterDemo> {
  late final SplitterController _controller;
  late final bool _ownsController;
  final ScrollController _sidebarScroll = ScrollController();
  final ScrollController _detailScroll = ScrollController();

  Brightness _brightness = Brightness.light;
  bool _brightnessInitialized = false;
  int _selectedSidebarIndex = 0;
  bool _switchValue = true;
  double _sliderValue = 0.5;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        SplitterController(
          initialPosition: const SplitterPosition.startPixels(280),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed from the platform once; after that the toolbar toggle owns it.
    if (!_brightnessInitialized) {
      _brightness = MediaQuery.platformBrightnessOf(context);
      _brightnessInitialized = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _sidebarScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _toggleBrightness() {
    setState(() {
      _brightness = _brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _brightness == Brightness.dark;
    return MacosTheme(
      data: isDark ? MacosThemeData.dark() : MacosThemeData.light(),
      child: MacosScaffold(
        toolBar: _buildToolBar(context, isDark),
        children: <Widget>[
          ContentArea(builder: (context, _) => _buildSplitter(context)),
        ],
      ),
    );
  }

  ToolBar _buildToolBar(BuildContext context, bool isDark) {
    return ToolBar(
      automaticallyImplyLeading: false,
      title: const Text('ResizableSplitter - macOS'),
      leading: MacosBackButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
      ),
      actions: <ToolbarItem>[
        ToolBarIconButton(
          label: 'Toggle sidebar',
          icon: const MacosIcon(CupertinoIcons.sidebar_left),
          showLabel: false,
          tooltipMessage: 'Toggle sidebar',
          onPressed: () => _controller.toggleCollapse(SplitterPane.start),
        ),
        ToolBarIconButton(
          label: 'Toggle appearance',
          icon: MacosIcon(
            isDark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
          ),
          showLabel: false,
          tooltipMessage: 'Toggle appearance',
          onPressed: _toggleBrightness,
        ),
      ],
    );
  }

  Widget _buildSplitter(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final detents = macosSidebarDetentFractions(constraints.maxWidth);
        return ResizableSplitter(
          axis: Axis.horizontal,
          controller: _controller,
          startConstraints: const SplitterPaneConstraints(
            minExtent: 200,
            maxExtent: 360,
            collapsedExtent: 0,
          ),
          snap: SplitterSnapBehavior.sticky(
            points: detents,
            pixelTolerance: 16,
          ),
          divider: _dividerStyle(context),
          start: _buildSidebar(context),
          end: _buildDetail(context),
        );
      },
    );
  }

  SplitterDividerStyle _dividerStyle(BuildContext context) {
    final base = MacosTheme.of(context).dividerColor;
    return SplitterDividerStyle(
      thickness: 1,
      interactiveExtent: 12,
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.dragged)) {
          return base.withValues(alpha: 0.7);
        }
        if (states.contains(WidgetState.hovered)) {
          return base.withValues(alpha: 0.4);
        }
        return base;
      }),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    // SidebarItems hosts its own ListView; feed it the controller directly
    // (do NOT wrap in another scroll view, which would unbound its height).
    return ColoredBox(
      color: MacosTheme.of(context).canvasColor,
      child: MacosScrollbar(
        controller: _sidebarScroll,
        child: SidebarItems(
          scrollController: _sidebarScroll,
          currentIndex: _selectedSidebarIndex,
          onChanged: (index) => setState(() => _selectedSidebarIndex = index),
          items: const <SidebarItem>[
            SidebarItem(section: true, label: Text('Showcase')),
            SidebarItem(
              leading: MacosIcon(CupertinoIcons.square_split_2x1),
              label: Text('Splitter'),
            ),
            SidebarItem(
              leading: MacosIcon(CupertinoIcons.slider_horizontal_3),
              label: Text('Controls'),
            ),
            SidebarItem(
              leading: MacosIcon(CupertinoIcons.textformat),
              label: Text('Typography'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final typography = MacosTypography.of(context);
    return ColoredBox(
      color: MacosTheme.of(context).canvasColor,
      child: MacosScrollbar(
        controller: _detailScroll,
        child: SingleChildScrollView(
          controller: _detailScroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ResizableSplitter, macOS dressed',
                style: typography.title1,
              ),
              const SizedBox(height: 8),
              Text(
                'Drag the divider to feel the sticky pixel detents, or toggle '
                'the sidebar from the toolbar. The chrome is macos_ui; the '
                'resize is resizable_splitter. Pane content is intentionally '
                'minimal - the splitter is the point.',
                style: typography.body,
              ),
              const SizedBox(height: 24),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: () {},
                child: const Text('Primary action'),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Text('Enabled', style: typography.body),
                  const SizedBox(width: 12),
                  MacosSwitch(
                    value: _switchValue,
                    onChanged: (value) => setState(() => _switchValue = value),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Adjust', style: typography.body),
              const SizedBox(height: 8),
              MacosSlider(
                value: _sliderValue,
                onChanged: (value) => setState(() => _sliderValue = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
