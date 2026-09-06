import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 30);

  for (final failureStage in ReceivingTransactionStage.values) {
    test('failure at ${failureStage.name} publishes neither record', () async {
      final product = Product(
        id: 'P1',
        shopId: 'shop-1',
        name: 'Milk',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final repository = InMemoryInventoryRepository(
        products: [product],
        onTransactionStage: (stage) {
          if (stage == failureStage) throw StateError('Injected transaction failure');
        },
        idGenerator: (prefix) => '$prefix-1',
        clock: () => timestamp,
      );
      final useCase = ReceiveStock(repository: repository, idempotencyKeyGenerator: () => 'R1');

      final result = await useCase(
        ReceiveStockInput(
          shopId: product.shopId,
          productId: product.id,
          sellingPriceMinor: 725,
          expiryDate: LocalDate(2026, 9, 12),
          quantity: 20,
        ),
      );

      expect(result, isA<ReceiveStockBackendUnavailable>());
      expect(repository.batches, isEmpty);
      expect(repository.movements, isEmpty);
      expect(await repository.listProducts(shopId: product.shopId), [product]);
    });
  }

  test('product listing is scoped to the selected shop', () async {
    final first = Product(
      id: 'P1',
      shopId: 'shop-1',
      name: 'Milk',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final second = Product(
      id: 'P2',
      shopId: 'shop-2',
      name: 'Yogurt',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final repository = InMemoryInventoryRepository(products: [first, second]);

    expect(await repository.listProducts(shopId: 'shop-1'), [first]);
    expect(await repository.listProducts(shopId: 'shop-2'), [second]);
  });

  test('loads a deterministic active dashboard with B08 classifications', () async {
    final product = Product(
      id: 'P1',
      shopId: 'shop-1',
      name: 'Milk',
      brand: 'Pilot Brand',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final repository = InMemoryInventoryRepository(
      products: [product],
      batches: [
        Batch(
          id: 'B-unknown',
          shopId: 'shop-1',
          productId: product.id,
          currentQuantity: 3,
          createdAt: timestamp.add(const Duration(hours: 1)),
          updatedAt: timestamp.add(const Duration(hours: 1)),
        ),
        Batch(
          id: 'B-expired',
          shopId: 'shop-1',
          productId: product.id,
          expiryDate: LocalDate(2026, 9, 2),
          currentQuantity: 5,
          lotCode: 'LOT-7',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        Batch(
          id: 'B-closed',
          shopId: 'shop-1',
          productId: product.id,
          expiryDate: LocalDate(2026, 9, 1),
          currentQuantity: 0,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 3),
    );

    final snapshot = await repository.loadExpiryDashboard(shopId: 'shop-1');

    expect(snapshot.referenceDate, LocalDate(2026, 9, 3));
    expect(snapshot.items.map((item) => item.batchId), ['B-expired', 'B-unknown']);
    expect(snapshot.items.first.productName, 'Milk');
    expect(snapshot.items.first.productBrand, 'Pilot Brand');
    expect(snapshot.items.first.daysToExpiry, -1);
    expect(snapshot.items.first.riskCategory, ExpiryRiskCategory.expired);
    expect(snapshot.items.first.currentQuantity, 5);
    expect(snapshot.items.first.lotNumber, 'LOT-7');
    expect(snapshot.items.last.expiryDate, isNull);
    expect(snapshot.items.last.daysToExpiry, isNull);
    expect(snapshot.items.last.riskCategory, isNull);
  });

  test('returns an explicit reference date for an empty in-memory dashboard', () async {
    final repository = InMemoryInventoryRepository(
      expiryDashboardReferenceDate: LocalDate(2026, 9, 3),
    );

    final snapshot = await repository.loadExpiryDashboard(shopId: 'shop-1');

    expect(snapshot.referenceDate, LocalDate(2026, 9, 3));
    expect(snapshot.items, isEmpty);
  });

  test('fails closed when an in-memory Batch references an unavailable Product', () async {
    final repository = InMemoryInventoryRepository(
      batches: [
        Batch(
          id: 'B1',
          shopId: 'shop-1',
          productId: 'missing-product',
          expiryDate: LocalDate(2026, 9, 4),
          currentQuantity: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 3),
    );

    await expectLater(
      repository.loadExpiryDashboard(shopId: 'shop-1'),
      throwsA(
        isA<InventoryRepositoryException>().having(
          (error) => error.kind,
          'kind',
          InventoryRepositoryFailureKind.invalidResponse,
        ),
      ),
    );
  });
}
