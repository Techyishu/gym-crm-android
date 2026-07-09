import 'package:flutter/material.dart';

class AppTheme {
  /// Bundled font family (see pubspec `fonts:`). Replaces the old runtime
  /// google_fonts fetch so text renders instantly on first/cold launch.
  static const String _fontFamily = 'Manrope';
  static const String fontFamily = _fontFamily;

  // ── Brand palette ("calmer, more confident" redesign) ───────────────────
  // Warm neutrals, a single energetic orange accent, deep green-black hero
  // surfaces, tabular numbers.
  static const Color ink        = Color(0xFF1D1B16); // primary text
  static const Color inkDark    = Color(0xFF12110D); // hover/pressed
  static const Color inkSoft    = Color(0xFF7A756A); // secondary text
  static const Color inkHint    = Color(0xFFA39E93); // placeholder/hint
  static const Color accent     = Color(0xFF2C6E7A); // teal accent
  static const Color accentDark = Color(0xFF255D68); // pressed teal
  static const Color accentFg   = Color(0xFFFFFFFF); // text on teal
  static const Color accentSoft = Color(0xFFE6EEEF); // soft teal tint bg

  // ── Surfaces ────────────────────────────────────────────────────────────
  static const Color surface    = Color(0xFFFFFFFF); // card/modal
  static const Color background = Color(0xFFEFECE4); // warm cream canvas
  static const Color surface2   = Color(0xFFE7E3D9); // input fills, skeletons
  static const Color activeBg   = Color(0xFFE7E3D9); // selected/active nav bg
  static const Color darkCard   = Color(0xFF182720); // deep green-black hero card
  static const Color darkCard2  = Color(0xFF223529); // raised element on darkCard
  static const Color onDark     = Color(0xFFF4F2EC); // primary text on darkCard
  static const Color onDarkSoft = Color(0xFF9DAA9F); // secondary text on darkCard
  static const Color mintOnDark = Color(0xFF7FD6A2); // positive numbers on darkCard

  // ── Borders ─────────────────────────────────────────────────────────────
  static const Color border     = Color(0xFFE2DED4);

  // ── Status ──────────────────────────────────────────────────────────────
  static const Color statusActive   = Color(0xFF2E7D4F);
  static const Color statusActiveBg = Color(0xFFDDEFE2);
  static const Color statusWarn     = Color(0xFFB07C1F);
  static const Color statusWarnBg   = Color(0xFFF4E8CD);
  static const Color statusDanger   = Color(0xFFC2492F);
  static const Color statusDangerBg = Color(0xFFF8DFD7);
  static const Color statusNeutral  = Color(0xFF6E6A60);
  static const Color statusNeutralBg= Color(0xFFE9E6DD);

  // ── Legacy aliases (used throughout existing screens) ───────────────────
  static const Color primary        = ink;
  static const Color primaryDark    = inkDark;
  static const Color primaryLight   = activeBg;
  static const Color primarySurface = activeBg;
  static const Color textPrimary    = ink;
  static const Color textSecondary  = inkSoft;
  static const Color textTertiary   = inkHint;
  static const Color error          = statusDanger;
  static const Color warning        = statusWarn;
  static const Color success        = statusActive;
  static const Color info           = Color(0xFF6E6A60);

  // ── Numbers ──────────────────────────────────────────────────────────────
  /// Tabular figures for all money/stat text so digits align.
  static const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

  static TextStyle numberStyle({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w800,
    Color color = ink,
    double? height,
  }) => TextStyle(
    fontFamily: _fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    fontFeatures: tabularFigures,
    letterSpacing: -0.5,
  );

  // ── Card decoration ─────────────────────────────────────────────────────
  static BoxDecoration cardDecoration({double radius = 16}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
  );

  static BoxDecoration darkCardDecoration({double radius = 20}) => BoxDecoration(
    color: darkCard,
    borderRadius: BorderRadius.circular(radius),
  );

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: ink,
        secondary: accent,
        surface: surface,
        error: error,
      ),
      textTheme: base.textTheme.apply(fontFamily: _fontFamily, bodyColor: ink, displayColor: ink),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        iconTheme: IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: border, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: border, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ink, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: error)),
        labelStyle: const TextStyle(color: inkSoft, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: ink, fontSize: 12),
        hintStyle: const TextStyle(color: inkHint, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentFg,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: const BorderSide(color: border),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 60,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w700, color: accent);
          }
          return const TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w600, color: inkHint);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent, size: 22);
          }
          return const IconThemeData(color: inkHint, size: 22);
        }),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: ink,
        labelStyle: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: const ListTileThemeData(iconColor: inkSoft),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkHint,
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w500, fontSize: 13),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: accentFg,
        elevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    );
  }
}
