import 'package:flutter/material.dart';

/// Central colour palette — warm taupe. Two themes (dark & light) share the same
/// token names; widgets reference `AppColors.<token>` and the active palette is
/// swapped at runtime via [setDark] (driven by the theme provider). Because the
/// tokens are getters over a mutable palette, a widget rebuild re-reads the
/// current theme's colour — so flipping the theme repaints the whole app.
class AppColors {
  AppColors._();

  static _Palette _p = _dark;

  /// Swap the active palette. Call before building the MaterialApp theme.
  static void setDark(bool dark) => _p = dark ? _dark : _light;

  static bool get isDark => identical(_p, _dark);

  // ── Surfaces (Level 0 → highest) ──────────────────────────────────────────
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceContainerLow => _p.surfaceContainerLow;
  static Color get surfaceContainer => _p.surfaceContainer;
  static Color get surfaceContainerHigh => _p.surfaceContainerHigh;
  static Color get surfaceContainerHighest => _p.surfaceContainerHighest;
  static Color get surfaceBright => _p.surfaceBright;

  /// Elevated fill (inputs, own bubbles' neighbours) = surface-container.
  static Color get surfaceEl => _p.surfaceContainer;

  // Borders
  static Color get border => _p.border;
  static Color get borderStr => _p.borderStr;
  static Color get outline => _p.borderStr;
  static Color get outlineVariant => _p.border;

  // ── Brand (warm taupe) ──────────────────────────────────────────────────────
  // `primary` content sits on it via [onPrimary].
  static Color get primary => _p.primary;
  static Color get primaryLt => _p.primaryLt;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onPrimaryContainer => _p.onPrimaryContainer;
  static Color get onPrimary => _p.onPrimary;

  /// Warm-brown fill for the sender's own message bubbles.
  static Color get primaryDim => _p.primaryDim;

  // Secondary / tertiary (alias avatar chips, subtle accents).
  static Color get secondary => _p.secondary;
  static Color get secondaryContainer => _p.secondaryContainer;
  static Color get onSecondaryContainer => _p.onSecondaryContainer;
  static Color get tertiary => _p.tertiary;
  static Color get tertiaryContainer => _p.tertiaryContainer;
  static Color get onTertiaryContainer => _p.onTertiaryContainer;

  // ── Semantic accents ────────────────────────────────────────────────────────
  static Color get error => _p.error;
  static Color get errorDim => _p.errorDim;
  static Color get errorContainer => _p.errorContainer;
  static Color get onErrorContainer => _p.onErrorContainer;
  static Color get teal => _p.teal;
  static Color get amber => _p.amber;
  static Color get pink => _p.pink;

  /// Back-compat alias — `coral` was the old error/destructive token.
  static Color get coral => _p.error;

  // ── Text ────────────────────────────────────────────────────────────────────
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  /// Palette used to colour anonymous aliases (theme-independent; mirrors
  /// backend ALIAS.COLORS).
  static const aliasColors = <Color>[
    Color(0xFF7F77DD),
    Color(0xFF1D9E75),
    Color(0xFFD85A30),
    Color(0xFFBA7517),
    Color(0xFFD4537E),
    Color(0xFF378ADD),
    Color(0xFF639922),
    Color(0xFFE24B4A),
    Color(0xFF54C5F8),
    Color(0xFFF48120),
  ];

  /// Parse a "#RRGGBB" hex string into a [Color], falling back to [primary].
  static Color fromHex(String? hex) {
    if (hex == null || hex.isEmpty) return primary;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value == null ? primary : Color(value);
  }
}

/// One theme's concrete colour values. Field names mirror [AppColors] tokens.
class _Palette {
  final Color bg,
      surface,
      surfaceContainerLow,
      surfaceContainer,
      surfaceContainerHigh,
      surfaceContainerHighest,
      surfaceBright,
      border,
      borderStr,
      primary,
      primaryLt,
      primaryContainer,
      onPrimaryContainer,
      onPrimary,
      primaryDim,
      secondary,
      secondaryContainer,
      onSecondaryContainer,
      tertiary,
      tertiaryContainer,
      onTertiaryContainer,
      error,
      errorDim,
      errorContainer,
      onErrorContainer,
      teal,
      amber,
      pink,
      textPrimary,
      textSecondary,
      textMuted;

  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceBright,
    required this.border,
    required this.borderStr,
    required this.primary,
    required this.primaryLt,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.onPrimary,
    required this.primaryDim,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.errorDim,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.teal,
    required this.amber,
    required this.pink,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
}

// ── Dark theme (original CypherFy values) ───────────────────────────────────
const _Palette _dark = _Palette(
  bg: Color(0xFF100E0C),
  surface: Color(0xFF151311),
  surfaceContainerLow: Color(0xFF1D1B19),
  surfaceContainer: Color(0xFF211F1D),
  surfaceContainerHigh: Color(0xFF2C2927),
  surfaceContainerHighest: Color(0xFF373432),
  surfaceBright: Color(0xFF3C3936),
  border: Color(0xFF4E453D),
  borderStr: Color(0xFF9A8F85),
  primary: Color(0xFFDCC2A8),
  primaryLt: Color(0xFFF9DEC2),
  primaryContainer: Color(0xFFA48D75),
  onPrimaryContainer: Color(0xFF362715),
  onPrimary: Color(0xFF3D2D1B),
  primaryDim: Color(0xFF4D3E2C),
  secondary: Color(0xFFD2C4B7),
  secondaryContainer: Color(0xFF4F453B),
  onSecondaryContainer: Color(0xFFC1B3A6),
  tertiary: Color(0xFFC8C8AB),
  tertiaryContainer: Color(0xFF929377),
  onTertiaryContainer: Color(0xFF2A2B17),
  error: Color(0xFFFFB4AB),
  errorDim: Color(0xFFBA573F),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  teal: Color(0xFF1D9E75),
  amber: Color(0xFFBA7517),
  pink: Color(0xFFD4537E),
  textPrimary: Color(0xFFE8E1DE),
  textSecondary: Color(0xFFD1C4BA),
  textMuted: Color(0xFF9A8F85),
);

// ── Light theme (warm taupe on cream — same aesthetic, inverted tone) ─────────
const _Palette _light = _Palette(
  bg: Color(0xFFF4EEE6), // base / lowest
  surface: Color(0xFFFBF7F1), // cards, scaffold
  surfaceContainerLow: Color(0xFFF3EDE4),
  surfaceContainer: Color(0xFFEDE6DB),
  surfaceContainerHigh: Color(0xFFE6DED1),
  surfaceContainerHighest: Color(0xFFDED4C5),
  surfaceBright: Color(0xFFFFFFFF),
  border: Color(0xFFDDD2C4), // default border (outline-variant)
  borderStr: Color(0xFF8C7F70), // stronger border (outline)
  primary: Color(0xFF7C5B37), // deep taupe accent, reads on light
  primaryLt: Color(0xFF9A7549),
  primaryContainer: Color(0xFFEAD8C2),
  onPrimaryContainer: Color(0xFF2C1D0B),
  onPrimary: Color(0xFFFFFFFF), // content on the accent
  primaryDim: Color(0xFFEADBC8), // own-bubble fill (light warm)
  secondary: Color(0xFF6E6155),
  secondaryContainer: Color(0xFFE7DCCE),
  onSecondaryContainer: Color(0xFF362E24),
  tertiary: Color(0xFF5E5D3E),
  tertiaryContainer: Color(0xFFE5E4C4),
  onTertiaryContainer: Color(0xFF1B1B06),
  error: Color(0xFFB3261E), // destructive text/borders
  errorDim: Color(0xFFBA573F),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  teal: Color(0xFF127A59), // online / success (darker for light bg)
  amber: Color(0xFF8A570F),
  pink: Color(0xFFB03D66),
  textPrimary: Color(0xFF221D18), // on-surface
  textSecondary: Color(0xFF544B41), // on-surface-variant
  textMuted: Color(0xFF8C7F70), // outline
);
