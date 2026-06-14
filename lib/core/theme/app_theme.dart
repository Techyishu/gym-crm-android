import 'package:flutter/material.dart';

class AppTheme {
  /// Bundled font family (see pubspec `fonts:`). Replaces the old runtime
  /// google_fonts fetch so text renders instantly on first/cold launch.
  static const String _fontFamily = 'Manrope';
  // ── Brand palette (mirrors gym-crm web design system) ──────────────────
  static const Color ink        = Color(0xFF1A1A1A); // primary text + buttons
  static const Color inkDark    = Color(0xFF0D0D0D); // hover/pressed
  static const Color inkSoft    = Color(0xFF6B6B6B); // secondary text
  static const Color inkHint    = Color(0xFF9E9E9E); // placeholder/hint
  static const Color accent     = Color(0xFFF5C842); // gold accent
  static const Color accentFg   = Color(0xFF0E0E0C); // text on gold

  // ── Surfaces ────────────────────────────────────────────────────────────
  static const Color surface    = Color(0xFFFFFFFF); // card/modal
  static const Color background = Color(0xFFF5F5F5); // app canvas
  static const Color surface2   = Color(0xFFEEEEEE); // input fills, skeletons
  static const Color activeBg   = Color(0xFFF0F0F0); // selected/active nav bg

  // ── Borders ─────────────────────────────────────────────────────────────
  static const Color border     = Color(0xFFE0E0E0);

  // ── Status ──────────────────────────────────────────────────────────────
  static const Color statusActive   = Color(0xFF2E7D32);
  static const Color statusActiveBg = Color(0xFFE8F5E9);
  static const Color statusWarn     = Color(0xFFE65100);
  static const Color statusWarnBg   = Color(0xFFFFF3E0);
  static const Color statusDanger   = Color(0xFFC62828);
  static const Color statusDangerBg = Color(0xFFFFEBEE);
  static const Color statusNeutral  = Color(0xFF546E7A);
  static const Color statusNeutralBg= Color(0xFFECEFF1);

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
  static const Color info           = Color(0xFF546E7A);

  // ── Card decoration ─────────────────────────────────────────────────────
  static BoxDecoration cardDecoration({double radius = 12}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
  );

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        brightness: Brightness.light,
        primary: ink,
        surface: surface,
        error: error,
      ),
      textTheme: base.textTheme.apply(fontFamily: _fontFamily),
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        iconTheme: const IconThemeData(color: ink),
        shape: const Border(bottom: BorderSide(color: border, width: 1)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ink, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: error)),
        labelStyle: const TextStyle(color: inkSoft, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: ink, fontSize: 12),
        hintStyle: const TextStyle(color: inkHint, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: const BorderSide(color: border),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600),
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
            return const TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w700, color: ink);
          }
          return const TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w600, color: inkHint);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: ink, size: 22);
          }
          return const IconThemeData(color: inkHint, size: 22);
        }),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: activeBg,
        selectedColor: ink,
        labelStyle: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      listTileTheme: const ListTileThemeData(iconColor: inkSoft),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkHint,
        indicatorColor: ink,
        dividerColor: border,
        labelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w500, fontSize: 13),
      ),
    );
  }
}
