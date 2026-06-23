import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'instrument.dart';

/// The only page chrome: brand, version, external links, and the theme toggle.
/// Stays pinned with a blurred translucent backdrop so content scrolls under it.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: t.ink.withValues(alpha: 0.72),
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Insets.maxContent),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final showWordmark = c.maxWidth >= 440;
                    final showTag = c.maxWidth >= 560;
                    final compactLinks = c.maxWidth < 680;
                    return Row(
                      children: [
                        const BrandMark(size: 24),
                        if (showWordmark) ...[
                          const SizedBox(width: Insets.md),
                          Text(
                            'resizable_splitter',
                            style: context.text.mono(
                              15,
                              color: t.textHi,
                              w: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (showTag) ...[
                          const SizedBox(width: Insets.md),
                          Tag('v2.0.0', color: t.signalText, filled: true),
                        ],
                        const Spacer(),
                        _BarLink(
                          label: 'pub.dev',
                          icon: Icons.inventory_2_outlined,
                          compact: compactLinks,
                          onTap: () => _open(
                            'https://pub.dev/packages/resizable_splitter',
                          ),
                        ),
                        _BarLink(
                          label: 'GitHub',
                          icon: Icons.code_rounded,
                          compact: compactLinks,
                          onTap: () => _open(
                            'https://github.com/omar-hanafy/resizable_splitter',
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        _ThemeToggle(isDark: isDark, onTap: onToggleTheme),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarLink extends StatelessWidget {
  const _BarLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: compact ? label : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 8,
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: t.textLo),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: context.text.mono(
                      12.5,
                      color: t.textLo,
                      w: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.isDark, required this.onTap});
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: isDark ? 'Switch to light' : 'Switch to dark',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(Corner.sm),
              border: Border.all(color: t.line),
            ),
            child: AnimatedSwitcher(
              duration: Motion.base,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween(begin: 0.6, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                key: ValueKey(isDark),
                size: 17,
                color: t.signalText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
