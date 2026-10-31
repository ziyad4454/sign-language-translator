import 'package:flutter/material.dart';

/// Colours that are the same in light and dark mode. The badges on the camera picture
/// sit on the video, not on the page, so they don't follow the theme.
abstract final class Palette {
  static const accent = Color(0xFF0F766E);
  static const good = Color(0xFF15803D);
  static const bad = Color(0xFFB42318);
  static const warn = Color(0xFFB54708);
}

/// The page's colours, in a light and a dark version. Widgets read the current ones
/// with [AppColors.of].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.bubble,
    required this.good,
    required this.bad,
    required this.warn,
  });

  static const light = AppColors(
    background: Color(0xFFF4F6F8),
    panel: Color(0xFFFFFFFF),
    ink: Color(0xFF1F2933),
    muted: Color(0xFF697586),
    line: Color(0xFFE3E8EF),
    accent: Palette.accent,
    onAccent: Color(0xFFFFFFFF),
    bubble: Color(0xFFE6F4F1),
    good: Palette.good,
    bad: Palette.bad,
    warn: Palette.warn,
  );

  static const dark = AppColors(
    background: Color(0xFF0E1116),
    panel: Color(0xFF171B22),
    ink: Color(0xFFE6EAF0),
    muted: Color(0xFF9AA4B2),
    line: Color(0xFF2A313C),
    accent: Color(0xFF2DD4BF),
    onAccent: Color(0xFF04201E),
    bubble: Color(0xFF12302C),
    good: Color(0xFF4ADE80),
    bad: Color(0xFFF87171),
    warn: Color(0xFFFBBF24),
  );

  final Color background;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color bubble;
  final Color good;
  final Color bad;
  final Color warn;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      panel: mix(panel, other.panel),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      bubble: mix(bubble, other.bubble),
      good: mix(good, other.good),
      bad: mix(bad, other.bad),
      warn: mix(warn, other.warn),
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final base = ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      surface: colors.panel,
      onSurface: colors.ink,
    ),
    scaffoldBackgroundColor: colors.background,
    extensions: const [],
  );
  return base.copyWith(
    extensions: [colors],
    textTheme: base.textTheme.apply(
      bodyColor: colors.ink,
      displayColor: colors.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.line),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(color: colors.panel),
  );
}

/// The rounded, thinly bordered box behind each part of the page.
BoxDecoration panelDecoration(
  AppColors colors, {
  Color? borderColor,
  double borderWidth = 1,
}) {
  return BoxDecoration(
    color: colors.panel,
    border: Border.all(color: borderColor ?? colors.line, width: borderWidth),
    borderRadius: BorderRadius.circular(12),
  );
}

/// A thin bar filled from the start side (the right in Arabic).
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Container(
      height: height,
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: AppColors.of(context).line,
        borderRadius: radius,
      ),
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, borderRadius: radius),
        ),
      ),
    );
  }
}
