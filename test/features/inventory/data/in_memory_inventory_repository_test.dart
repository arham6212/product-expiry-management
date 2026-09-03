import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
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
}
