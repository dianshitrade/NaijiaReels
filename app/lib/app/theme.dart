import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const background = Color(0xFF0E0E12);
  static const primary = Color(0xFFFF8A00);
  static const gold = Color(0xFFFFC533);
  static const green = Color(0xFF00A859);
  static const surface = Color(0xFF1A1A20);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.gold,
          tertiary: AppColors.green,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
        ),
      );
}
