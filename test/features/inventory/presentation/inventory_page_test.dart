import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_theme.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/inventory_repository_provider.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';
import 'package:product_expiry_management/features/inventory/presentation/inventory_page.dart';
import 'package:product_expiry_management/features/inventory/presentation/product_details_page.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final timestamp = DateTime.utc(2026, 9, 1);
  final withBatch = Product(
    id: 'with-batch',
    shopId: 'shop-1',
    name: 'Milk',
    brand: 'Dairy Co',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final withoutBatch = Product(
    id: 'without-batch',
    shopId: 'shop-1',
    name: 'Cereal',
    brand: 'Grain Co',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  testWidgets('shows products with and without active batches and opens details', (tester) async {
    final repository = InMemoryInventoryRepository(
      products: [withBatch, withoutBatch],
      batches: [
        Batch(
          id: 'batch-1',
          shopId: 'shop-1',
          productId: withBatch.id,
          expiryDate: LocalDate(2026, 9, 6),
          currentQuantity: 4,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(repository),
          activeShopProvider.overrideWithValue(_access(timestamp)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const InventoryPage(shopId: 'shop-1', currencyCode: 'QAR'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Cereal'), findsOneWidget);
    expect(find.text('No active batch'), findsOneWidget);

    await tester.tap(find.text('Cereal'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsPage), findsOneWidget);
    expect(find.textContaining('Receive stock to begin tracking'), findsOneWidget);
  });

  testWidgets('search includes product brand and active-batch lot', (tester) async {
    final repository = InMemoryInventoryRepository(
      products: [withBatch, withoutBatch],
      batches: [
        Batch(
          id: 'batch-1',
          shopId: 'shop-1',
          productId: withBatch.id,
          expiryDate: LocalDate(2026, 9, 6),
          currentQuantity: 4,
          lotCode: 'LOT-DAIRY',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(repository),
          activeShopProvider.overrideWithValue(_access(timestamp)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const InventoryPage(shopId: 'shop-1', currencyCode: 'QAR'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'LOT-DAIRY');
    await tester.pump();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Cereal'), findsNothing);
  });
}

ShopAccess _access(DateTime timestamp) {
  return ShopAccess(
    shop: Shop(
      id: 'shop-1',
      name: 'Test Shop',
      timeZone: 'Asia/Qatar',
      currencyCode: 'QAR',
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    membership: ShopMembership(
      shopId: 'shop-1',
      userId: 'user-1',
      role: ShopMembershipRole.owner,
      createdAt: timestamp,
    ),
  );
}
