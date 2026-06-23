import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'instrument.dart';

const _keywords = {
  'const',
  'final',
  'var',
  'void',
  'return',
  'class',
  'extends',
  'with',
  'if',
  'else',
  'for',
  'switch',
  'case',
  'true',
  'false',
  'null',
  'new',
  'await',
  'async',
  'import',
  'export',
  'required',
  'this',
  'super',
  'get',
  'set',
  'static',
  'late',
  'enum',
  'bool',
  'double',
  'int',
  'String',
  'Widget',
};

/// A read-only code sample in the mono face, with a one-tap copy. Lightweight
/// Dart tinting keeps it on-theme without pulling in a highlighter dependency.
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.label = 'dart'});
  final String code;
  final String label;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      raised: false,
      color: t.isDark ? const Color(0xFF0E1116) : const Color(0xFFFAFBFC),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                _dot(t.danger),
                const SizedBox(width: 6),
                _dot(t.signal),
                const SizedBox(width: 6),
                _dot(t.good),
                const SizedBox(width: Insets.md),
                Text(widget.label, style: context.text.monoKey),
                const Spacer(),
                _CopyButton(copied: _copied, onTap: _copy),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.md,
              Insets.lg,
              Insets.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SelectionArea(
                child: RichText(
                  text: TextSpan(
                    style: context.text
                        .mono(12.5, color: t.textHi, w: FontWeight.w400)
                        .copyWith(height: 1.65),
                    children: _highlight(context, widget.code),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.7),
      shape: BoxShape.circle,
    ),
  );

  List<TextSpan> _highlight(BuildContext context, String code) {
    final t = context.tokens;
    final spans = <TextSpan>[];
    final lines = code.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final commentIdx = _commentIndex(line);
      final codePart = commentIdx == -1 ? line : line.substring(0, commentIdx);
      final comment = commentIdx == -1 ? null : line.substring(commentIdx);

      final token = RegExp(
        "('[^']*'|\"[^\"]*\"|[A-Za-z_][A-Za-z0-9_]*|[0-9]+\\.?[0-9]*|\\s+|.)",
      );
      for (final m in token.allMatches(codePart)) {
        final s = m.group(0)!;
        Color? c;
        if (s.startsWith("'") || s.startsWith('"')) {
          c = t.good;
        } else if (RegExp(r'^[0-9]').hasMatch(s)) {
          c = t.good;
        } else if (_keywords.contains(s)) {
          c = t.signalText;
        } else if (RegExp(r'^[A-Z]').hasMatch(s)) {
          c = t.request;
        }
        spans.add(
          TextSpan(
            text: s,
            style: c == null ? null : TextStyle(color: c),
          ),
        );
      }
      if (comment != null) {
        spans.add(
          TextSpan(
            text: comment,
            style: TextStyle(color: t.textFaint, fontStyle: FontStyle.italic),
          ),
        );
      }
      if (i != lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  int _commentIndex(String line) {
    var inStr = false;
    String? quote;
    for (var i = 0; i < line.length - 1; i++) {
      final ch = line[i];
      if (inStr) {
        if (ch == quote) inStr = false;
      } else if (ch == "'" || ch == '"') {
        inStr = true;
        quote = ch;
      } else if (ch == '/' && line[i + 1] == '/') {
        return i;
      }
    }
    return -1;
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onTap});
  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              copied ? Icons.check_rounded : Icons.content_copy_rounded,
              size: 13,
              color: copied ? t.good : t.textLo,
            ),
            const SizedBox(width: 5),
            Text(
              copied ? 'copied' : 'copy',
              style: context.text.mono(11, color: copied ? t.good : t.textLo),
            ),
          ],
        ),
      ),
    );
  }
}
