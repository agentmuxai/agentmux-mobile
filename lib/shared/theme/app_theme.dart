import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's colours, in a dark and a light set. Screens read them with
/// `context.palette` so they follow the OS colour mode (see
/// `docs/specs/SPEC_FORM_FACTORS_AND_EDGES_2026_11_04.md`, I6 and A3).
///
/// The dark set mirrors the desktop CSS tokens and is what the app has always
/// shown. The light set keeps the same roles; its text colours reach 4.5:1 on
/// its backgrounds and its status colours are the darker shades that stay
/// readable on white.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.primary,
    required this.success,
    required this.warning,
    required this.error,
    required this.live,
    required this.teal,
    required this.violet,
    required this.amber,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSoft,
    required this.textDim,
    required this.textFaint,
    required this.textGhost,
    required this.hairline,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color border;

  /// `--accent-color`.
  final Color primary;
  final Color success;
  final Color warning;
  final Color error;

  /// The "reachable now" dot on a computer.
  final Color live;

  /// Tag colours: LAN + Cloud, Direct, and the HOST tag.
  final Color teal;
  final Color violet;
  final Color amber;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Secondary text in graded strengths, from the strongest to the faintest:
  /// what was `Colors.white70`, `white54`, `white38` and `white24` on dark.
  final Color textSoft;
  final Color textDim;
  final Color textFaint;
  final Color textGhost;

  /// A thin rule or the track of a chart (`white12` on dark).
  final Color hairline;

  static const dark = AppPalette(
    background: Color(0xFF0F0F0F),
    surface: Color(0xFF1A1A1A),
    surfaceVariant: Color(0xFF242424),
    border: Color(0xFF2E2E2E),
    primary: Color(0xFF3B82F6),
    success: Color(0xFF22C55E),
    warning: Color(0xFFEAB308),
    error: Color(0xFFEF4444),
    live: Colors.greenAccent,
    teal: Color(0xFF2DD4BF),
    violet: Color(0xFFA78BFA),
    amber: Color(0xFFF59E0B),
    textPrimary: Color(0xFFE5E5E5),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF4B5563),
    textSoft: Colors.white70,
    textDim: Colors.white54,
    textFaint: Colors.white38,
    textGhost: Colors.white24,
    hairline: Colors.white12,
  );

  static const light = AppPalette(
    background: Color(0xFFF4F4F5),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEDEDEF),
    border: Color(0xFFD8D8DC),
    primary: Color(0xFF2563EB),
    success: Color(0xFF15803D),
    warning: Color(0xFF8F5B00),
    error: Color(0xFFB91C1C),
    live: Color(0xFF15803D),
    teal: Color(0xFF0F766E),
    violet: Color(0xFF6D28D9),
    amber: Color(0xFFB45309),
    textPrimary: Color(0xFF18181B),
    textSecondary: Color(0xFF52525B),
    textMuted: Color(0xFF63636B),
    textSoft: Color(0xCC000000),
    textDim: Color(0xAD000000),
    textFaint: Color(0x94000000),
    textGhost: Color(0x4D000000),
    hairline: Color(0x1F000000),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? border,
    Color? primary,
    Color? success,
    Color? warning,
    Color? error,
    Color? live,
    Color? teal,
    Color? violet,
    Color? amber,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textSoft,
    Color? textDim,
    Color? textFaint,
    Color? textGhost,
    Color? hairline,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    live: live ?? this.live,
    teal: teal ?? this.teal,
    violet: violet ?? this.violet,
    amber: amber ?? this.amber,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textSoft: textSoft ?? this.textSoft,
    textDim: textDim ?? this.textDim,
    textFaint: textFaint ?? this.textFaint,
    textGhost: textGhost ?? this.textGhost,
    hairline: hairline ?? this.hairline,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceVariant: mix(surfaceVariant, other.surfaceVariant),
      border: mix(border, other.border),
      primary: mix(primary, other.primary),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      live: mix(live, other.live),
      teal: mix(teal, other.teal),
      violet: mix(violet, other.violet),
      amber: mix(amber, other.amber),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textSoft: mix(textSoft, other.textSoft),
      textDim: mix(textDim, other.textDim),
      textFaint: mix(textFaint, other.textFaint),
      textGhost: mix(textGhost, other.textGhost),
      hairline: mix(hairline, other.hairline),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The colours for the current (OS-chosen) colour mode.
  AppPalette get palette => AppPalette.of(this);
}

/// `MaterialApp.builder`: sets the system bars' icon colours from the theme
/// for screens that have no app bar to do it (the status-bar icons would stay
/// light on a light page), and caps a floating snack bar's width on a wide
/// window.
Widget appThemeBuilder(BuildContext context, Widget? child) {
  final theme = Theme.of(context);
  final wide = MediaQuery.sizeOf(context).width >
      AppTheme.snackBarMaxWidth + 24;
  // The same widgets at every width: a different wrapper above the router would
  // remount it when the window crosses the threshold (a rotation or a fold) and
  // lose every screen's state. Only the theme's value changes.
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: AppTheme.overlayStyle(theme.brightness),
    child: Theme(
      data: wide
          ? theme.copyWith(
              snackBarTheme: theme.snackBarTheme.copyWith(
                width: AppTheme.snackBarMaxWidth,
              ),
            )
          : theme,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

abstract final class AppTheme {
  static ThemeData get dark => _build(
    AppPalette.dark,
    ColorScheme.dark(
      surface: AppPalette.dark.surface,
      primary: AppPalette.dark.primary,
      error: AppPalette.dark.error,
    ),
  );

  static ThemeData get light => _build(
    AppPalette.light,
    ColorScheme.light(
      surface: AppPalette.light.surface,
      onSurface: AppPalette.light.textPrimary,
      primary: AppPalette.light.primary,
      onPrimary: Colors.white,
      error: AppPalette.light.error,
      outline: const Color(0xFFA1A1AA),
    ),
  );

  /// The status-bar icons and the system navigation bar for a screen drawn in
  /// [brightness]: dark icons on a light app, light icons on a dark one, and a
  /// transparent navigation bar so the app's own colour runs to the bottom
  /// edge (edge-to-edge). On iOS `statusBarBrightness` is the brightness of the
  /// bar's background, the opposite of the icons.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Widest a floating snack bar gets: on a tablet or an unfolded foldable a
  /// full-width one would run across the whole screen.
  static const snackBarMaxWidth = 480.0;

  static ThemeData _build(AppPalette p, ColorScheme scheme) {
    return ThemeData(
      brightness: scheme.brightness,
      scaffoldBackgroundColor: p.background,
      colorScheme: scheme,
      extensions: [p],
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerColor: p.border,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: p.textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: p.textSecondary, fontSize: 13),
        labelSmall: TextStyle(color: p.textMuted, fontSize: 11),
        titleMedium: TextStyle(
          color: p.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        elevation: 0,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle(scheme.brightness),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textMuted,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.primary),
        ),
        hintStyle: TextStyle(color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      // A message floats above the bottom bar, rounded, in the surface colour
      // of the mode: Material's default is an inverse (light-on-dark) bar that
      // fights the app's own surfaces.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceVariant,
        contentTextStyle: TextStyle(color: p.textPrimary, fontSize: 14),
        actionTextColor: p.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: p.border),
        ),
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
      useMaterial3: true,
    );
  }
}
