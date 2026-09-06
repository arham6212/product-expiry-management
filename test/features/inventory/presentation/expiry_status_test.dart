import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard.dart';
import 'package:product_expiry_management/features/inventory/presentation/expiry_status.dart';

void main() {
  test('alerts rank expired before today and approaching expiry', () {
    final sorted = sortedExpiryAlerts([
      _item('soon', 4, ExpiryRiskCategory.next7Days),
      _item('expired', -2, ExpiryRiskCategory.expired),
      _item('today', 0, ExpiryRiskCategory.expiresToday),
    ]);

    expect(sorted.map((item) => item.productName), ['expired', 'today', 'soon']);
  });
}

ExpiryDashboardItem _item(String name, int days, ExpiryRiskCategory category) {
  return ExpiryDashboardItem(
    shopId: 'shop-1',
    batchId: 'batch-$name',
    productId: 'product-$name',
    productName: name,
    expiryDate: LocalDate(2026, 9, 10),
    daysToExpiry: days,
    riskCategory: category,
    currentQuantity: 1,
    receivedAt: DateTime.utc(2026, 9, 1),
  );
}
