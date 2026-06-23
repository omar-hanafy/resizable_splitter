import 'package:flutter/material.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import 'tokens.dart';

/// Builds the app [ThemeData] for a [brightness], wiring the semantic
/// [AppTokens], a type scale on the bundled fonts, and a package-wide
/// [ResizableSplitterThemeData] default (which itself demonstrates the
/// splitter's theming as a [ThemeExtension]).
ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.signal,
    onPrimary: const Color(0xFF1A1206),
    secondary: t.request,
    onSecondary: t.isDark ? const Color(0xFF0B1018) : Colors.white,
    error: t.danger,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.textHi,
    surfaceContainerHighest: t.surfaceHi,
    onSurfaceVariant: t.textLo,
    outline: t.line,
    outlineVariant: t.line,
  );

  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.ink,
    canvasColor: t.surface,
    textTheme: _textTheme(t),
    splashFactory: NoSplash.splashFactory,
    extensions: [
      t,
      // The package theme, derived from our tokens. Demonstrates registering
      // ResizableSplitterThemeData as a ThemeExtension for app-wide defaults.
      ResizableSplitterThemeData(
        keyboardStep: 0.02,
        pageStep: 0.1,
        divider: SplitterDividerStyle(
          thickness: 2,
          interactiveExtent: 28,
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.dragged)) return t.signal;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return t.lineStrong;
            }
            return t.line;
          }),
        ),
      ),
    ],
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF222833) : const Color(0xFF1B2029),
        borderRadius: BorderRadius.circular(Corner.sm),
        border: Border.all(color: t.lineStrong),
      ),
      textStyle: const TextStyle(
        fontFamily: Fonts.mono,
        fontSize: 11.5,
        color: Color(0xFFECEFF4),
        height: 1.3,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}

TextTheme _textTheme(AppTokens t) {
  TextStyle body(
    double size, {
    FontWeight w = FontWeight.w400,
    double h = 1.5,
  }) => TextStyle(
    fontFamily: Fonts.body,
    fontSize: size,
    fontWeight: w,
    height: h,
    color: t.textHi,
    letterSpacing: 0,
  );
  TextStyle display(
    double size, {
    FontWeight w = FontWeight.w700,
    double ls = -0.6,
  }) => TextStyle(
    fontFamily: Fonts.display,
    fontSize: size,
    fontWeight: w,
    height: 1.04,
    letterSpacing: ls,
    color: t.textHi,
  );

  return TextTheme(
    displayLarge: display(56, ls: -1.6),
    displayMedium: display(44, ls: -1.2),
    displaySmall: display(34, ls: -0.9),
    headlineMedium: display(26, w: FontWeight.w600, ls: -0.5),
    headlineSmall: display(21, w: FontWeight.w600, ls: -0.3),
    titleLarge: body(18, w: FontWeight.w600, h: 1.3),
    titleMedium: body(15, w: FontWeight.w600, h: 1.3),
    bodyLarge: body(16, h: 1.6),
    bodyMedium: body(14.5, h: 1.55),
    bodySmall: TextStyle(
      fontFamily: Fonts.body,
      fontSize: 13,
      height: 1.5,
      color: t.textLo,
    ),
    labelLarge: body(14, w: FontWeight.w600, h: 1.2),
    labelMedium: body(12.5, w: FontWeight.w600, h: 1.2),
  );
}

/// Named, color-resolved text styles for the instrument language - the bits the
/// Material [TextTheme] does not cover (eyebrows, mono data, hero).
extension AppTextX on BuildContext {
  AppText get text => AppText(tokens);
}

class AppText {
  const AppText(this.t);
  final AppTokens t;

  /// Oversized hero headline. Caller may scale down on small viewports.
  TextStyle hero(double size) => TextStyle(
    fontFamily: Fonts.display,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: size * -0.028,
    color: t.textHi,
  );

  /// The technical eyebrow: spaced, uppercase mono.
  TextStyle get eyebrow => TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.2,
    height: 1.2,
    color: t.signalText,
  );

  TextStyle get sectionTitle => TextStyle(
    fontFamily: Fonts.display,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.05,
    color: t.textHi,
  );

  /// Instrument readout - tabular figures, tight, technical.
  TextStyle mono(
    double size, {
    Color? color,
    FontWeight w = FontWeight.w500,
    double ls = 0,
  }) => TextStyle(
    fontFamily: Fonts.mono,
    fontSize: size,
    fontWeight: w,
    letterSpacing: ls,
    height: 1.25,
    color: color ?? t.textHi,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small uppercase mono key/caption.
  TextStyle get monoKey => TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    height: 1.2,
    color: t.textFaint,
  );

  TextStyle get bodyLo => TextStyle(
    fontFamily: Fonts.body,
    fontSize: 14.5,
    height: 1.6,
    color: t.textLo,
  );

  /// General body text at an arbitrary size, in the UI face.
  TextStyle body(
    double size, {
    FontWeight w = FontWeight.w400,
    double h = 1.5,
    Color? color,
  }) => TextStyle(
    fontFamily: Fonts.body,
    fontSize: size,
    fontWeight: w,
    height: h,
    color: color ?? t.textHi,
  );
}
