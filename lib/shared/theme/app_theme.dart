import 'package:flutter/material.dart';

// AgentMux dark palette — mirrors desktop CSS tokens.
abstract final class AppColors {
  static const background = Color(0xFF0F0F0F);
  static const surface = Color(0xFF1A1A1A);
  static const surfaceVariant = Color(0xFF242424);
  static const border = Color(0xFF2E2E2E);
  static const primary = Color(0xFF3B82F6);   // --accent-color
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFEAB308);
  static const error = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFE5E5E5);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF4B5563);
}

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.surface,
          primary: AppColors.primary,
          error: AppColors.error,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        dividerColor: AppColors.border,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 11),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
          hintStyle: const TextStyle(color: AppColors.textMuted),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        useMaterial3: true,
      );
}
