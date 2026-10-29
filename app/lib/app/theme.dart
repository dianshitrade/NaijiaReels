import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const background = Color(0xFF0B0F0D);
  /// Nigerian green — brand / primary.
  static const primary = Color(0xFF00A859);
  static const green = primary;
  static const greenDark = Color(0xFF006B3A);
  /// Gold — coins / accents only.
  static const gold = Color(0xFFFFC533);
  static const surface = Color(0xFF161B19);
  static const surfaceHigh = Color(0xFF1F2623);
  static const muted = Color(0xFF9AA5A0);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.gold,
          onSecondary: Colors.black,
          tertiary: AppColors.gold,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.18),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceHigh,
          selectedColor: AppColors.primary,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        tabBarTheme: const TabBarThemeData(
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
        ),
      );
}
