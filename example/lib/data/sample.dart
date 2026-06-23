import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Realistic, themed pane content. The demos compose these so the splitter is
/// shown furnishing real tool surfaces - an editor, a terminal, a file tree -
/// rather than empty colored boxes.

class _FileRow {
  const _FileRow(
    this.depth,
    this.name,
    this.icon, {
    this.active = false,
    this.tone,
  });
  final int depth;
  final String name;
  final IconData icon;
  final bool active;
  final Color? tone;
}

const _files = <_FileRow>[
  _FileRow(0, 'lib', Icons.folder_rounded, tone: _amberHint),
  _FileRow(1, 'resizable_splitter.dart', Icons.description_outlined),
  _FileRow(1, 'src', Icons.folder_outlined),
  _FileRow(2, 'solver', Icons.folder_outlined),
  _FileRow(3, 'split_solver.dart', Icons.description_outlined, active: true),
  _FileRow(3, 'split_snap_engine.dart', Icons.description_outlined),
  _FileRow(2, 'widget', Icons.folder_outlined),
  _FileRow(3, 'resizable_splitter.dart', Icons.description_outlined),
  _FileRow(3, 'split_handle.dart', Icons.description_outlined),
  _FileRow(2, 'model', Icons.folder_outlined),
  _FileRow(3, 'split_position.dart', Icons.description_outlined),
];

const _amberHint = Color(0xFFFFC15A);

/// A file explorer column.
class FileTreePane extends StatelessWidget {
  const FileTreePane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PaneShell(
      header: 'EXPLORER',
      icon: Icons.account_tree_outlined,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        itemCount: _files.length,
        itemBuilder: (context, i) {
          final f = _files[i];
          return Container(
            height: 26,
            padding: EdgeInsets.only(
              left: Insets.md + f.depth * 14.0,
              right: Insets.sm,
            ),
            color: f.active ? t.signalSoft : null,
            child: Row(
              children: [
                Icon(
                  f.icon,
                  size: 14,
                  color: f.tone ?? (f.active ? t.signalText : t.textLo),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    f.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.mono(
                      11.5,
                      color: f.active ? t.textHi : t.textLo,
                      w: f.active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Navigation rail content for sidebar demos.
class MiniNav extends StatelessWidget {
  const MiniNav({super.key, this.selected = 1});
  final int selected;

  static const _items = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.straighten_rounded, 'Solver'),
    (Icons.tune_rounded, 'Constraints'),
    (Icons.bolt_outlined, 'Snapping'),
    (Icons.unfold_less_rounded, 'Collapse'),
    (Icons.accessibility_new_rounded, 'Access'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PaneShell(
      header: 'NAVIGATE',
      icon: Icons.menu_rounded,
      child: ListView(
        padding: const EdgeInsets.all(Insets.sm),
        children: [
          for (var i = 0; i < _items.length; i++)
            Container(
              height: 34,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              decoration: BoxDecoration(
                color: i == selected ? t.signalSoft : null,
                borderRadius: BorderRadius.circular(Corner.xs),
                border: Border.all(
                  color: i == selected
                      ? t.signal.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _items[i].$1,
                    size: 15,
                    color: i == selected ? t.signalText : t.textLo,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _items[i].$2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text
                          .body(13)
                          .copyWith(
                            color: i == selected ? t.textHi : t.textLo,
                            fontWeight: i == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _editorCode = [
  "ResizableSplitter(",
  "  controller: controller,",
  "  startConstraints: const",
  "    SplitterPaneConstraints(minExtent: 240),",
  "  snap: const SplitterSnapBehavior(",
  "    points: [0.33, 0.5, 0.66],",
  "  ),",
  "  start: const Sidebar(),",
  "  end: const Editor(),",
  ");",
];

/// A line-numbered editor surface.
class EditorPane extends StatelessWidget {
  const EditorPane({super.key, this.title = 'split_view.dart'});
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PaneShell(
      header: title,
      icon: Icons.description_outlined,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        itemCount: _editorCode.length,
        itemBuilder: (context, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: 1.5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: context.text.mono(11, color: t.textFaint),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    _editorCode[i],
                    style: context.text.mono(
                      11.5,
                      color: _editorCode[i].trimLeft().startsWith('//')
                          ? t.textFaint
                          : t.textHi,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const _terminal = [
  ("\$", "flutter test", null),
  ("", "00:03 +214: All tests passed!", _good),
  ("\$", "flutter pub publish --dry-run", null),
  ("", "Package has 0 warnings.", _good),
  ("\$", "_", null),
];

const _good = Color(0xFF5FD08A);

/// A terminal surface with a blinking caret on the last line.
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key});

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PaneShell(
      header: 'TERMINAL',
      icon: Icons.terminal_rounded,
      // Scrollable so the lines never overflow when the pane is dragged small.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in _terminal)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (line.$1.isNotEmpty) ...[
                      Text(
                        line.$1,
                        style: context.text.mono(
                          11.5,
                          color: t.signalText,
                          w: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: line.$2 == '_'
                          ? AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => Opacity(
                                opacity: _c.value < 0.5 ? 1 : 0,
                                child: Container(
                                  width: 7,
                                  height: 14,
                                  color: t.textHi,
                                ),
                              ),
                            )
                          : Text(
                              line.$2,
                              style: context.text.mono(
                                11.5,
                                color: line.$3 ?? t.textLo,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A reading surface for prose/inspector demos.
class ProsePane extends StatelessWidget {
  const ProsePane({
    super.key,
    required this.title,
    required this.body,
    this.header = 'CONTENT',
    this.icon = Icons.article_outlined,
  });
  final String title;
  final String body;
  final String header;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      header: header,
      icon: icon,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Insets.md),
            Text(body, style: context.text.bodyLo),
          ],
        ),
      ),
    );
  }
}

/// Shared pane chrome: a thin header strip with an icon + label over content.
class _PaneShell extends StatelessWidget {
  const _PaneShell({
    required this.header,
    required this.icon,
    required this.child,
  });
  final String header;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: t.isDark ? 0.6 : 0.92),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 13, color: t.textFaint),
                const SizedBox(width: 8),
                Text(
                  header,
                  style: context.text.mono(10.5, color: t.textFaint, ls: 1.2),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
