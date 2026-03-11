import 'package:flutter/material.dart';

/// App theme matching the AgentMux desktop dark theme.
class AppTheme {
  static const _bgColor = Color(0xFF1B1B1D);
  static const _surfaceColor = Color(0xFF232325);
  static const _accentColor = Color(0xFF58C142);
  static const _textColor = Color(0xFFE0E0E0);
  static const _secondaryText = Color(0xFF8A8A8E);
  static const _errorColor = Color(0xFFE55353);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bgColor,
    colorScheme: const ColorScheme.dark(
      primary: _accentColor,
      secondary: _accentColor,
      surface: _surfaceColor,
      error: _errorColor,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: _textColor,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceColor,
      foregroundColor: _textColor,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: _surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _bgColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _secondaryText.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _secondaryText.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accentColor),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _accentColor,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(color: _textColor, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: _textColor, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: _textColor),
      bodyMedium: TextStyle(color: _secondaryText),
      labelLarge: TextStyle(color: _textColor),
    ),
  );
}
