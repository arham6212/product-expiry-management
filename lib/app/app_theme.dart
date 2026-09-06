import 'package:flutter/material.dart';

import '../design_system/theme/app_tokens.dart';

abstract final class AppTheme {
  static const _seedColor = AppColors.brand;

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 56,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      ),
    );
  }
}
