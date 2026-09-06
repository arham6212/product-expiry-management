import 'package:flutter/material.dart';

import '../../../design_system/theme/app_tokens.dart';
import '../application/expiry_dashboard.dart';

final class ExpiryStatusPresentation {
  const ExpiryStatusPresentation({required this.label, required this.tone, required this.color});

  final String label;
  final AppStatusTone tone;
  final Color color;
}

ExpiryStatusPresentation expiryStatusForDays(int? days) {
  if (days == null) {
    return const ExpiryStatusPresentation(
      label: 'Date needed',
      tone: AppStatusTone.neutral,
      color: AppColors.unknown,
    );
  }
  if (days < 0) {
    return const ExpiryStatusPresentation(
      label: 'Expired',
      tone: AppStatusTone.critical,
      color: AppColors.expired,
    );
  }
  if (days == 0) {
    return const ExpiryStatusPresentation(
      label: 'Expires today',
      tone: AppStatusTone.warning,
      color: AppColors.urgent,
    );
  }
  if (days <= 7) {
    return ExpiryStatusPresentation(
      label: days == 1 ? '1 day left' : '$days days left',
      tone: AppStatusTone.caution,
      color: AppColors.soon,
    );
  }
  return ExpiryStatusPresentation(
    label: '$days days left',
    tone: AppStatusTone.positive,
    color: AppColors.safe,
  );
}

List<ExpiryDashboardItem> sortedExpiryAlerts(Iterable<ExpiryDashboardItem> items) {
  final sorted = List<ExpiryDashboardItem>.of(items);
  sorted.sort((a, b) {
    final days = (a.daysToExpiry ?? 999999).compareTo(b.daysToExpiry ?? 999999);
    return days != 0 ? days : a.productName.compareTo(b.productName);
  });
  return List.unmodifiable(sorted);
}
