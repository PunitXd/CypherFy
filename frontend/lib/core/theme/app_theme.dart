import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Builds the [ThemeData] for a given [Brightness]. Reads the currently-active
/// [AppColors] palette, so the caller must call `AppColors.setDark(...)` to match
/// [b] before building.
/// Design rules: 8px inputs/buttons, 12px cards, 0.5px borders, no shadows.
class AppTheme {
  AppTheme._();

  static ThemeData build(Brightness b) {
    final isDark = b == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final scheme =
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
      surface: AppColors.surface,
      primary: AppColors.primary,
      secondary: AppColors.primaryLt,
      error: AppColors.error,
      onPrimary: AppColors.onPrimary,
      onSurface: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.subheading,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      // Inputs — 8px radius, 0.5px borders.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceEl,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTextStyles.bodySecondary,
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.primary),
        errorBorder: _inputBorder(AppColors.error),
        focusedErrorBorder: _inputBorder(AppColors.error),
      ),
      // Primary buttons — 8px radius, no elevation.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          // Without these, a disabled ElevatedButton falls back to Flutter's
          // washed-out default (onSurface @12%), which clashes with the palette.
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
        space: 0.5,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceEl,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: 0.5),
      );
}
