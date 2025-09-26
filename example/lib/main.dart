import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const ResizableSplitterExampleApp());
}

class ResizableSplitterExampleApp extends StatelessWidget {
  const ResizableSplitterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resizable Splitter Example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const SplitterDemoPage(),
    );
  }
}

class SplitterDemoPage extends StatefulWidget {
  const SplitterDemoPage({super.key});

  @override
  State<SplitterDemoPage> createState() => _SplitterDemoPageState();
}

class _SplitterDemoPageState extends State<SplitterDemoPage> {
  late final SplitterController _controller;
  late final List<_Demo> _demos;
  int _selectedDemo = 0;
  int? _webViewDemoIndex;

  static final List<_Demo> _baseDemos = <_Demo>[
    _Demo(
      title: 'Overview',
      subtitle: 'Tour the basics and see live metrics',
      builder: (context) => const _OverviewDemo(),
    ),
    _Demo(
      title: 'Custom handle & theming',
      subtitle: 'Style the divider and supply your own grip',
      builder: (context) => const _StylingDemo(),
    ),
    _Demo(
      title: 'Keyboard & snapping',
      subtitle: 'Arrow/Page keys + snap points in action',
      builder: (context) => const _KeyboardDemo(),
    ),
    _Demo(
      title: 'Vertical layouts',
      subtitle: 'Axis.vertical with asymmetric min sizes',
      builder: (context) => const _VerticalDemo(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = SplitterController(initialRatio: 0.32);
    _demos = List<_Demo>.of(_baseDemos);
    if (_supportsPlatformViewDemo) {
      _webViewDemoIndex = _demos.length;
      _demos.add(
        _Demo(
          title: 'Platform WebView',
          subtitle: 'Embed a Flutter WebView inside the splitter',
          builder: (context) => const _WebViewDemo(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectDemo(int index) {
    if (_selectedDemo == index) return;
    setState(() => _selectedDemo = index);
  }

  bool get _supportsPlatformViewDemo {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final demo = _demos[_selectedDemo];
    final useOverlay =
        _webViewDemoIndex != null && _selectedDemo == _webViewDemoIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('Resizable Splitter demo')),
      body: ResizableSplitter(
        axis: Axis.horizontal,
        controller: _controller,
        dividerThickness: 10,
        dividerColor: colorScheme.primary.withAlpha(60),
        dividerHoverColor: colorScheme.primary.withAlpha(90),
        dividerActiveColor: colorScheme.primary.withAlpha(130),
        enableKeyboard: true,
        overlayEnabled: useOverlay,
        minStartPanelSize: 220,
        snapPoints: const <double>[0.26, 0.32, 0.45],
        snapTolerance: 0.04,
        startPanel: _NavigationPane(
          demos: _demos,
          selectedIndex: _selectedDemo,
          onSelect: _selectDemo,
        ),
        endPanel: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Builder(
            key: ValueKey<int>(_selectedDemo),
            builder: demo.builder,
          ),
        ),
      ),
    );
  }
}

class _Demo {
  const _Demo({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({
    required this.demos,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Demo> demos;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemBuilder: (context, index) {
            final demo = demos[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withAlpha(40),
                child: Text('${index + 1}'),
              ),
              title: Text(demo.title),
              subtitle: Text(demo.subtitle),
              selected: index == selectedIndex,
              selectedTileColor: theme.colorScheme.primary.withAlpha(30),
              onTap: () => onSelect(index),
            );
          },
          separatorBuilder: (context, index) => const Divider(height: 0),
          itemCount: demos.length,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.color, required this.child});

  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: color,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(title, style: textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _OverviewDemo extends StatelessWidget {
  const _OverviewDemo();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        Text('Meet ResizableSplitter', style: textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Drag the divider, use the arrow keys when it has focus, or press PageUp/PageDown '
          'for larger jumps. The overlay prevents embedded platform views from stealing '
          'pointer events mid-drag.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const _ExampleCard(child: _OverviewExample()),
        const SizedBox(height: 24),
        Text('Highlights', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        const _Bullet('Pointer, keyboard, and accessibility out of the box'),
        const _Bullet('Snap points keep layouts tidy at key ratios'),
        const _Bullet('Controller API for programmatic updates and animations'),
        const _Bullet('Robust overlay shields embedded platform views'),
      ],
    );
  }
}

class _StylingDemo extends StatelessWidget {
  const _StylingDemo();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text('Custom handle & theming', style: textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Use the styling hooks to blend into any design system. Supply custom colors or a '
          'handleBuilder to render your own grip UI. Hover and drag states are easy to brand.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const _ExampleCard(child: _StylingExample()),
        const SizedBox(height: 24),
        const _Bullet('dividerColor / hover / active control the rail colors'),
        const _Bullet('handleBuilder receives hover/drag state and axis info'),
        const _Bullet(
          'Try long-pressing or focusing the handle to inspect semantics',
        ),
      ],
    );
  }
}

class _KeyboardDemo extends StatelessWidget {
  const _KeyboardDemo();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text('Keyboard & snapping', style: textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Focus the divider (Tab or click) and use arrow keys for 5% nudges, PageUp/PageDown '
          'for bigger jumps, or Home/End to snap to the bounds. Snapping keeps the layout '
          'aligned with preferred ratios.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const _ExampleCard(child: _KeyboardExample()),
        const SizedBox(height: 24),
        const _Bullet('keyboardStep and pageStep tune the control feel'),
        const _Bullet('Snap reports through onRatioChanged when it activates'),
      ],
    );
  }
}

class _VerticalDemo extends StatefulWidget {
  const _VerticalDemo();

  @override
  State<_VerticalDemo> createState() => _VerticalDemoState();
}

class _VerticalDemoState extends State<_VerticalDemo> {
  late final SplitterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitterController(initialRatio: 0.48);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text('Vertical layouts', style: textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Stack content top-to-bottom when toolbars and notes need to share the same column. '
          'Define minimum heights and let each panel scroll on its own.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        _ExampleCard(
          height: 420,
          child: _VerticalWorkspacePreview(controller: _controller),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<double>(
          valueListenable: _controller,
          builder: (context, ratio, _) {
            final topPercent = (ratio * 100).round();
            final bottomPercent = 100 - topPercent;
            return Text(
              'Top panel $topPercent% · Bottom panel $bottomPercent%',
              style: textTheme.labelLarge,
            );
          },
        ),
        const SizedBox(height: 24),
        Text('Why it works', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        const _Bullet(
          'minStartPanelSize/minEndPanelSize keep headers pinned while dragging.',
        ),
        const _Bullet(
          'Each panel hosts its own ListView to show independent scrolling.',
        ),
        const _Bullet(
          'Ratio bounds steady the layout on ultra-short or tall screens.',
        ),
      ],
    );
  }
}

class _VerticalWorkspacePreview extends StatelessWidget {
  const _VerticalWorkspacePreview({required this.controller});

  final SplitterController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ResizableSplitter(
        axis: Axis.vertical,
        controller: controller,
        minStartPanelSize: 120,
        minEndPanelSize: 160,
        minRatio: 0.2,
        maxRatio: 0.8,
        dividerThickness: 8,
        dividerColor: colorScheme.primary.withAlpha(70),
        dividerHoverColor: colorScheme.primary.withAlpha(100),
        dividerActiveColor: colorScheme.primary.withAlpha(140),
        startPanel: _Panel(
          title: 'Today\'s schedule',
          color: colorScheme.surfaceContainerHighest,
          child: const _ScheduleList(),
        ),
        endPanel: _Panel(
          title: 'Team notes',
          color: colorScheme.surface,
          child: const _NotesList(),
        ),
      ),
    );
  }
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList();

  static const List<_ScheduleEntry> _entries = <_ScheduleEntry>[
    _ScheduleEntry(
      title: 'Design sync',
      subtitle: '9:30 AM · Room Atlas',
      trailing: '45 min',
      icon: Icons.palette_outlined,
    ),
    _ScheduleEntry(
      title: 'Sprint planning',
      subtitle: '11:00 AM · Video call',
      trailing: '30 min',
      icon: Icons.view_week_outlined,
    ),
    _ScheduleEntry(
      title: 'Client feedback',
      subtitle: '1:30 PM · Horizon Studio',
      trailing: '60 min',
      icon: Icons.headset_mic_outlined,
    ),
    _ScheduleEntry(
      title: 'Bug triage',
      subtitle: '3:00 PM · #proj-splitter',
      trailing: '25 min',
      icon: Icons.rule_folder_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withAlpha(32),
              foregroundColor: colorScheme.primary,
              child: Icon(entry.icon),
            ),
            title: Text(entry.title, style: theme.textTheme.bodyLarge),
            subtitle: Text(entry.subtitle, style: theme.textTheme.bodyMedium),
            trailing: Text(entry.trailing, style: theme.textTheme.labelMedium),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        );
      },
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList();

  static const List<_NoteEntry> _notes = <_NoteEntry>[
    _NoteEntry(
      title: 'Polish the grip hover state',
      body:
          'Align the hover color with the new secondary tone so it matches the keyboard focus outline.',
      tag: 'Design',
    ),
    _NoteEntry(
      title: 'Collect QA findings',
      body:
          'The Android team hit a few overscroll edge cases when the bottom panel is very small.',
      tag: 'QA',
    ),
    _NoteEntry(
      title: 'Prep release notes',
      body:
          'Call out keyboard shortcuts, overlay support, and the new dividerBuilder hook.',
      tag: 'Docs',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _notes.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final note = _notes[index];
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(note.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(note.body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(note.tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: colorScheme.secondary.withAlpha(28),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScheduleEntry {
  const _ScheduleEntry({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final IconData icon;
}

class _NoteEntry {
  const _NoteEntry({
    required this.title,
    required this.body,
    required this.tag,
  });

  final String title;
  final String body;
  final String tag;
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.child, this.height = 260});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(height: height, child: child),
    );
  }
}

class _OverviewExample extends StatefulWidget {
  const _OverviewExample();

  @override
  State<_OverviewExample> createState() => _OverviewExampleState();
}

class _OverviewExampleState extends State<_OverviewExample> {
  late final SplitterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitterController(initialRatio: 0.58);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ResizableSplitter(
              controller: _controller,
              dividerThickness: 8,
              dividerColor: colorScheme.secondary.withAlpha(70),
              dividerHoverColor: colorScheme.secondary.withAlpha(100),
              dividerActiveColor: colorScheme.secondary.withAlpha(150),
              snapPoints: const <double>[0.35, 0.5, 0.7],
              startPanel: const _Panel(
                title: 'Navigation',
                color: Colors.transparent,
                child: _NavigationListPreview(itemCount: 5),
              ),
              endPanel: const _Panel(
                title: 'Document preview',
                color: Colors.transparent,
                child: _DocumentPreview(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<double>(
            valueListenable: _controller,
            builder: (context, value, _) => Text(
              'Current ratio: ${(value * 100).round()}%',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _StylingExample extends StatefulWidget {
  const _StylingExample();

  @override
  State<_StylingExample> createState() => _StylingExampleState();
}

class _StylingExampleState extends State<_StylingExample> {
  late final SplitterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitterController(initialRatio: 0.5);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ResizableSplitter(
        controller: _controller,
        dividerThickness: 14,
        dividerColor: colorScheme.tertiaryContainer,
        dividerHoverColor: colorScheme.tertiary,
        dividerActiveColor: colorScheme.error,
        handleBuilder: (context, details) {
          final accent = details.isDragging
              ? colorScheme.onTertiary
              : colorScheme.onTertiaryContainer;
          final gripColor = Theme.of(context).colorScheme.onPrimaryContainer;
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: accent.withAlpha(details.isDragging ? 80 : 40),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withAlpha(120), width: 1),
              ),
              child: _HandleGripDots(axis: details.axis, color: gripColor),
            ),
          );
        },
        startPanel: _GradientPanel(
          title: 'Theme preview',
          colors: [colorScheme.tertiaryContainer, colorScheme.primaryContainer],
          child: const _Bullet(
            'Drop your own handleBuilder to match any brand',
          ),
        ),
        endPanel: _GradientPanel(
          title: 'Palette',
          colors: [colorScheme.surfaceContainerHighest, colorScheme.surface],
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _ColorSwatchChip(
                label: 'Idle',
                color: colorScheme.tertiaryContainer,
              ),
              _ColorSwatchChip(label: 'Hover', color: colorScheme.tertiary),
              _ColorSwatchChip(label: 'Active', color: colorScheme.error),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardExample extends StatefulWidget {
  const _KeyboardExample();

  @override
  State<_KeyboardExample> createState() => _KeyboardExampleState();
}

class _KeyboardExampleState extends State<_KeyboardExample> {
  late final SplitterController _controller;
  double _lastSnap = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = SplitterController(initialRatio: 0.4);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ResizableSplitter(
              controller: _controller,
              keyboardStep: 0.05,
              pageStep: 0.2,
              snapPoints: const <double>[0.25, 0.5, 0.75],
              snapTolerance: 0.06,
              minStartPanelSize: 120,
              minEndPanelSize: 160,
              startPanel: const _Panel(
                title: 'Notes',
                color: Colors.transparent,
                child: _NavigationListPreview(itemCount: 6),
              ),
              endPanel: const _Panel(
                title: 'Canvas',
                color: Colors.transparent,
                child: _TimelinePreview(),
              ),
              onRatioChanged: (value) => setState(() => _lastSnap = value),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<double>(
            valueListenable: _controller,
            builder: (context, value, _) => Text(
              'Arrow/Page keys adjust ratio · Current ${(value * 100).round()}%',
              style: theme.textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Last change emitted ${(_lastSnap * 100).round()}%',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _GradientPanel extends StatelessWidget {
  const _GradientPanel({
    required this.title,
    required this.colors,
    required this.child,
  });

  final String title;
  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatchChip extends StatelessWidget {
  const _ColorSwatchChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(40),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _HandleGripDots extends StatelessWidget {
  const _HandleGripDots({required this.axis, required this.color});

  final Axis axis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const double dotSize = 3;
    const double spacing = 2;

    Widget buildDot() => Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    if (axis == Axis.horizontal) {
      return SizedBox(
        width: dotSize,
        height: dotSize * 3 + spacing * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            buildDot(),
            const SizedBox(height: spacing),
            buildDot(),
            const SizedBox(height: spacing),
            buildDot(),
          ],
        ),
      );
    }

    return SizedBox(
      width: dotSize * 3 + spacing * 2,
      height: dotSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          buildDot(),
          const SizedBox(width: spacing),
          buildDot(),
          const SizedBox(width: spacing),
          buildDot(),
        ],
      ),
    );
  }
}

class _NavigationListPreview extends StatelessWidget {
  const _NavigationListPreview({this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 96;
            return Card(
              elevation: 0,
              child: ListTile(
                dense: true,
                minLeadingWidth: isCompact ? 0 : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                leading: isCompact
                    ? null
                    : SizedBox.square(
                        dimension: 32,
                        child: CircleAvatar(child: Text('${index + 1}')),
                      ),
                title: Text(
                  'Item ${index + 1}',
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: isCompact ? null : const Text('Preview', maxLines: 1),
              ),
            );
          },
        );
      },
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: <Widget>[
        Text('Keep your content adaptive', style: theme.titleLarge),
        const SizedBox(height: 12),
        Text(
          'ResizableSplitter lets you build productivity UIs, dashboards, and creative '
          'tools that scale to every screen size.',
          style: theme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Text('Features', style: theme.titleMedium),
        const SizedBox(height: 8),
        const _Bullet('Smooth dragging with an overlay shield'),
        const _Bullet('Keyboard navigation and snapping'),
        const _Bullet('Custom handleBuilder and color hooks'),
      ],
    );
  }
}

class _TimelinePreview extends StatelessWidget {
  const _TimelinePreview();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text('Milestone ${index + 1}'),
          subtitle: const Text('Use PageUp/PageDown to jump 20%'),
        );
      },
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('• ', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _WebViewDemo extends StatefulWidget {
  const _WebViewDemo();

  @override
  State<_WebViewDemo> createState() => _WebViewDemoState();
}

class _WebViewDemoState extends State<_WebViewDemo> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://flutter.dev'));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
