import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Apple-like palette with the Bearch accent.
abstract final class BearchColors {
  static const accent = Color(0xFF0071E3);
  static const lightBackground = Color(0xFFF5F5F7);
  static const darkBackground = Color(0xFF000000);
  static const darkSurface = Color(0xFF1C1C1E);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const danger = Color(0xFFFF3B30);
  static const purple = Color(0xFFAF52DE);
}

/// Glassmorphism tokens, read with `GlassTokens.of(context)`.
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.fill,
    required this.border,
    required this.blur,
    required this.shadow,
    required this.blobs,
  });

  final Color fill;
  final Color border;
  final double blur;
  final Color shadow;

  /// Soft background blob colours (top-left, top-right, bottom).
  final List<Color> blobs;

  static GlassTokens of(BuildContext context) => Theme.of(context).extension<GlassTokens>()!;

  static const light = GlassTokens(
    fill: Color(0xA6FFFFFF),
    border: Color(0x99FFFFFF),
    blur: 24,
    shadow: Color(0x14000000),
    blobs: [Color(0x553D9BFF), Color(0x40AF52DE), Color(0x3364D2FF)],
  );

  static const dark = GlassTokens(
    fill: Color(0x991C1C1E),
    border: Color(0x1FFFFFFF),
    blur: 24,
    shadow: Color(0x66000000),
    blobs: [Color(0x400071E3), Color(0x33AF52DE), Color(0x2664D2FF)],
  );

  @override
  GlassTokens copyWith({Color? fill, Color? border, double? blur, Color? shadow, List<Color>? blobs}) =>
      GlassTokens(
        fill: fill ?? this.fill,
        border: border ?? this.border,
        blur: blur ?? this.blur,
        shadow: shadow ?? this.shadow,
        blobs: blobs ?? this.blobs,
      );

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      fill: Color.lerp(fill, other.fill, t)!,
      border: Color.lerp(border, other.border, t)!,
      blur: blur + (other.blur - blur) * t,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      blobs: [for (var i = 0; i < blobs.length; i++) Color.lerp(blobs[i], other.blobs[i], t)!],
    );
  }
}

ThemeData buildBearchTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: BearchColors.accent, brightness: brightness).copyWith(
    primary: BearchColors.accent,
    onPrimary: Colors.white,
    surface: isDark ? BearchColors.darkSurface : Colors.white,
    error: BearchColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? BearchColors.darkBackground : BearchColors.lightBackground,
    splashFactory: InkSparkle.splashFactory,
  );
  final text = GoogleFonts.montserratTextTheme(base.textTheme).apply(
    bodyColor: isDark ? Colors.white : const Color(0xFF1D1D1F),
    displayColor: isDark ? Colors.white : const Color(0xFF1D1D1F),
  );
  final radius = BorderRadius.circular(14);

  return base.copyWith(
    textTheme: text,
    extensions: [isDark ? GlassTokens.dark : GlassTokens.light],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: Colors.transparent, elevation: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BearchColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0x14FFFFFF) : const Color(0xCCFFFFFF),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: BearchColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: isDark ? Colors.white12 : Colors.black12, space: 1),
  );
}
