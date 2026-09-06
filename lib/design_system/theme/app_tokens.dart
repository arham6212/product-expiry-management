import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: md);
}

abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double pill = 999;
}

abstract final class AppColors {
  static const Color brand = Color(0xFF126B59);
  static const Color canvas = Color(0xFFF7F9F8);
  static const Color expired = Color(0xFFB42318);
  static const Color urgent = Color(0xFFB54708);
  static const Color soon = Color(0xFF8A6100);
  static const Color safe = Color(0xFF067647);
  static const Color unknown = Color(0xFF475467);
}

enum AppStatusTone { critical, warning, caution, positive, neutral }

extension AppStatusToneColors on AppStatusTone {
  Color foreground(ColorScheme colors) => switch (this) {
    AppStatusTone.critical => AppColors.expired,
    AppStatusTone.warning => AppColors.urgent,
    AppStatusTone.caution => AppColors.soon,
    AppStatusTone.positive => AppColors.safe,
    AppStatusTone.neutral => colors.onSurfaceVariant,
  };

  Color background(ColorScheme colors) => foreground(colors).withValues(alpha: 0.10);
}
