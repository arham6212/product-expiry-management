import '../../../domain/services/expiry_risk_service.dart';
import '../../../domain/value_objects/local_date.dart';

final class ExpiryDashboardSnapshot {
  ExpiryDashboardSnapshot({
    required this.referenceDate,
    required Iterable<ExpiryDashboardItem> items,
  }) : items = List.unmodifiable(items);

  final LocalDate referenceDate;
  final List<ExpiryDashboardItem> items;
}

final class ExpiryDashboardItem {
  const ExpiryDashboardItem({
    required this.shopId,
    required this.batchId,
    required this.productId,
    required this.productName,
    required this.expiryDate,
    required this.daysToExpiry,
    required this.riskCategory,
    required this.currentQuantity,
    required this.receivedAt,
    this.productBrand,
    this.lotNumber,
  });

  final String shopId;
  final String batchId;
  final String productId;
  final String productName;
  final String? productBrand;
  final LocalDate? expiryDate;
  final int? daysToExpiry;
  final ExpiryRiskCategory? riskCategory;
  final int? currentQuantity;
  String get quantityLabel => currentQuantity?.toString() ?? 'Unknown';
  final String? lotNumber;
  final DateTime receivedAt;
}
