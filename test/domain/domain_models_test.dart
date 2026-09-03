import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/entities/domain_validation_exception.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 29);

  group('batch ownership of expiry', () {
    test('one product can retain two independent expiry batches', () {
      final product = Product(
        id: 'product-1',
        shopId: 'shop-1',
        name: 'Almarai Milk 1L',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final firstBatch = Batch(
        id: 'batch-a',
        shopId: product.shopId,
        productId: product.id,
        expiryDate: LocalDate(2026, 9, 3),
        currentQuantity: 5,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final secondBatch = Batch(
        id: 'batch-b',
        shopId: product.shopId,
        productId: product.id,
        expiryDate: LocalDate(2026, 9, 12),
        currentQuantity: 20,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(firstBatch.productId, product.id);
      expect(secondBatch.productId, product.id);
      expect(firstBatch.expiryDate, LocalDate(2026, 9, 3));
      expect(secondBatch.expiryDate, LocalDate(2026, 9, 12));
    });

    test('keeps a historical batch without a known expiry readable', () {
      final batch = Batch(
        id: 'batch-without-expiry',
        shopId: 'shop-1',
        productId: 'product-1',
        currentQuantity: 4,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(batch.expiryDate, isNull);
    });

    test('rejects negative current quantity', () {
      expect(
        () => Batch(
          id: 'batch-a',
          shopId: 'shop-1',
          productId: 'product-1',
          expiryDate: LocalDate(2026, 9, 3),
          currentQuantity: -1,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });
  });

  group('inventory movements', () {
    test('accepts received stock as a positive delta', () {
      final movement = InventoryMovement(
        id: 'movement-1',
        shopId: 'shop-1',
        batchId: 'batch-a',
        type: InventoryMovementType.received,
        quantityDelta: 5,
        occurredAt: timestamp,
        createdAt: timestamp,
        idempotencyKey: 'receive-1',
      );

      expect(movement.quantityDelta, 5);
    });

    test('rejects sold stock as a positive delta', () {
      expect(
        () => InventoryMovement(
          id: 'movement-1',
          shopId: 'shop-1',
          batchId: 'batch-a',
          type: InventoryMovementType.sold,
          quantityDelta: 1,
          occurredAt: timestamp,
          createdAt: timestamp,
          idempotencyKey: 'sale-1',
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('rejects zero deltas', () {
      expect(
        () => InventoryMovement(
          id: 'movement-1',
          shopId: 'shop-1',
          batchId: 'batch-a',
          type: InventoryMovementType.adjusted,
          quantityDelta: 0,
          occurredAt: timestamp,
          createdAt: timestamp,
          idempotencyKey: 'adjust-1',
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });
  });

  group('shop invites', () {
    test('requires expiry to be after creation', () {
      expect(
        () => ShopInvite(
          id: 'invite-1',
          shopId: 'shop-1',
          code: 'ABC123',
          isActive: true,
          createdAt: timestamp,
          createdBy: 'owner-1',
          expiresAt: timestamp,
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });
  });
}
