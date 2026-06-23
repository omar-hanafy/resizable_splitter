import 'package:flutter/material.dart';

/// Typeface family names. Bundled as variable fonts in `assets/fonts/`.
abstract final class Fonts {
  /// Characterful, drafted display face. Used with restraint, tight tracking.
  static const display = 'Bricolage Grotesque';

  /// Calm neutral grotesk for UI and prose.
  static const body = 'Hanken Grotesk';

  /// Tabular-figure monospace - the instrument readout face.
  static const mono = 'JetBrains Mono';
}

/// 4pt spacing rhythm. Named so layout reads as intent, not magic numbers.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 40;
  static const double section = 96;
  static const double maxContent = 1180;
}

/// Corner radii. The instrument language is crisp - small radii only.
abstract final class Corner {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const Radius rXs = Radius.circular(xs);
  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
}

/// Motion timings. Micro-interactions stay in the 150-300ms band.
abstract final class Motion {
  static const Duration micro = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;
}

/// Semantic color tokens, themed per [Brightness]. Registered as a
/// [ThemeExtension] so a theme switch lerps every surface and signal smoothly,
/// and any widget can read them through [AppTokensX.tokens].
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.ink,
    required this.surface,
    required this.surfaceHi,
    required this.line,
    required this.lineStrong,
    required this.textHi,
    required this.textLo,
    required this.textFaint,
    required this.signal,
    required this.signalText,
    required this.signalSoft,
    required this.request,
    required this.requestSoft,
    required this.danger,
    required this.good,
  });

  final Brightness brightness;

  /// Page background - graphite, never pure black.
  final Color ink;

  /// Panel background.
  final Color surface;

  /// Raised pane / card background.
  final Color surfaceHi;

  /// Hairline borders and dividers.
  final Color line;

  /// Stronger border for focus / active framing.
  final Color lineStrong;

  final Color textHi;
  final Color textLo;
  final Color textFaint;

  /// The one bold color: the "resolved truth" phosphor amber. Use for fills,
  /// handles, and large glyphs.
  final Color signal;

  /// Amber tuned for legible text / small glyphs on the page background.
  final Color signalText;

  /// Faint amber wash for active backgrounds and glows.
  final Color signalSoft;

  /// The intent / request channel - a cool muted slate so amber stays dominant.
  final Color request;

  /// Faint request wash.
  final Color requestSoft;

  /// Constraint bite: a request that cannot be honored.
  final Color danger;

  /// Exact resolution / healthy confirmation. Used sparingly.
  final Color good;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppTokens(
    brightness: Brightness.dark,
    ink: Color(0xFF0C0E12),
    surface: Color(0xFF14171D),
    surfaceHi: Color(0xFF1B2029),
    line: Color(0xFF2A2F3A),
    lineStrong: Color(0xFF3B424F),
    textHi: Color(0xFFECEFF4),
    textLo: Color(0xFF98A2B3),
    textFaint: Color(0xFF5C6473),
    signal: Color(0xFFFFC15A),
    signalText: Color(0xFFFFC76A),
    signalSoft: Color(0x1AFFC15A),
    request: Color(0xFF7FA0C0),
    requestSoft: Color(0x1A7FA0C0),
    danger: Color(0xFFFF6B5C),
    good: Color(0xFF5FD08A),
  );

  static const light = AppTokens(
    brightness: Brightness.light,
    ink: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFFBFBFD),
    line: Color(0xFFE2E5EA),
    lineStrong: Color(0xFFCBD1DA),
    textHi: Color(0xFF161A20),
    textLo: Color(0xFF5A6271),
    textFaint: Color(0xFF8C93A1),
    signal: Color(0xFFF2A52A),
    signalText: Color(0xFF8A5310),
    signalSoft: Color(0x1FF2A52A),
    request: Color(0xFF3E5C7A),
    requestSoft: Color(0x143E5C7A),
    danger: Color(0xFFC2422F),
    good: Color(0xFF2E8B57),
  );

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? ink,
    Color? surface,
    Color? surfaceHi,
    Color? line,
    Color? lineStrong,
    Color? textHi,
    Color? textLo,
    Color? textFaint,
    Color? signal,
    Color? signalText,
    Color? signalSoft,
    Color? request,
    Color? requestSoft,
    Color? danger,
    Color? good,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      ink: ink ?? this.ink,
      surface: surface ?? this.surface,
      surfaceHi: surfaceHi ?? this.surfaceHi,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      textHi: textHi ?? this.textHi,
      textLo: textLo ?? this.textLo,
      textFaint: textFaint ?? this.textFaint,
      signal: signal ?? this.signal,
      signalText: signalText ?? this.signalText,
      signalSoft: signalSoft ?? this.signalSoft,
      request: request ?? this.request,
      requestSoft: requestSoft ?? this.requestSoft,
      danger: danger ?? this.danger,
      good: good ?? this.good,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      ink: Color.lerp(ink, other.ink, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      textHi: Color.lerp(textHi, other.textHi, t)!,
      textLo: Color.lerp(textLo, other.textLo, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
      signalText: Color.lerp(signalText, other.signalText, t)!,
      signalSoft: Color.lerp(signalSoft, other.signalSoft, t)!,
      request: Color.lerp(request, other.request, t)!,
      requestSoft: Color.lerp(requestSoft, other.requestSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      good: Color.lerp(good, other.good, t)!,
    );
  }
}

/// Ergonomic access: `context.tokens.signal`.
extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}
