import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 30, 12);
  late Product product;
  late Product otherShopProduct;
  late InMemoryInventoryRepository repository;
  late ReceiveStock useCase;
  var idSequence = 0;
  var keySequence = 0;

  setUp(() {
    idSequence = 0;
    keySequence = 0;
    product = Product(
      id: 'P1',
      shopId: 'shop-1',
      name: 'Almarai Milk 1L',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    otherShopProduct = Product(
      id: 'P2',
      shopId: 'shop-2',
      name: 'Other Shop Product',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    repository = InMemoryInventoryRepository(
      products: [product, otherShopProduct],
      idGenerator: (prefix) => '$prefix-${idSequence++}',
      clock: () => timestamp,
    );
    useCase = ReceiveStock(
      repository: repository,
      idempotencyKeyGenerator: () => 'receive-${keySequence++}',
    );
  });

  ReceiveStockInput input({
    int quantity = 20,
    String shopId = 'shop-1',
    String productId = 'P1',
    LocalDate? expiryDate,
    bool omitExpiry = false,
    String? lotNumber = 'LOT-7',
  }) {
    return ReceiveStockInput(
      shopId: shopId,
      productId: productId,
      quantity: quantity,
      expiryDate: omitExpiry ? null : expiryDate ?? LocalDate(2026, 9, 12),
      lotNumber: lotNumber,
    );
  }

  test('creates a new batch and initial RECEIVED movement', () async {
    final result = await useCase(input(expiryDate: LocalDate(2026, 9, 12)));

    expect(result, isA<ReceiveStockSuccess>());
    final success = result as ReceiveStockSuccess;
    expect(success.receipt.batch.shopId, 'shop-1');
    expect(success.receipt.batch.productId, product.id);
    expect(success.receipt.batch.expiryDate, LocalDate(2026, 9, 12));
    expect(success.receipt.batch.lotCode, 'LOT-7');
    expect(success.receipt.batch.currentQuantity, 20);
    expect(success.receipt.movement.type, InventoryMovementType.received);
    expect(success.receipt.movement.quantityDelta, 20);
    expect(success.receipt.wasDuplicate, isFalse);
    expect(repository.batches, hasLength(1));
    expect(repository.movements, hasLength(1));
  });

  test('accepts a nullable lot number with a required expiry', () async {
    final result = await useCase(input(lotNumber: null));

    final batch = (result as ReceiveStockSuccess).receipt.batch;
    expect(batch.expiryDate, LocalDate(2026, 9, 12));
    expect(batch.lotCode, isNull);
  });

  test('rejects missing expiry before key generation or repository I/O', () async {
    final result = await useCase(input(omitExpiry: true));

    expect(
      result,
      isA<ReceiveStockInvalidInput>()
          .having((value) => value.field, 'field', 'expiryDate')
          .having((value) => value.message, 'message', 'Enter an expiry date.'),
    );
    expect(keySequence, 0);
    expect(repository.batches, isEmpty);
    expect(repository.movements, isEmpty);
  });

  test('normalizes surrounding and repeated lot-number whitespace', () async {
    final result = await useCase(input(lotNumber: '  LOT   7  '));

    expect((result as ReceiveStockSuccess).receipt.batch.lotCode, 'LOT 7');
  });

  for (final invalidQuantity in [0, -1, ReceiveStock.maxQuantity + 1]) {
    test('rejects invalid quantity $invalidQuantity before repository I/O', () async {
      final result = await useCase(input(quantity: invalidQuantity));

      expect(result, isA<ReceiveStockInvalidInput>());
      expect(repository.batches, isEmpty);
      expect(repository.movements, isEmpty);
      expect(keySequence, 0);
    });
  }

  test('rejects blank selected shop and Product before repository I/O', () async {
    expect(await useCase(input(shopId: '  ')), isA<ReceiveStockInvalidInput>());
    expect(await useCase(input(productId: '')), isA<ReceiveStockInvalidInput>());
    expect(repository.batches, isEmpty);
  });

  test('rejects a Product owned by another shop', () async {
    final result = await useCase(input(productId: otherShopProduct.id));

    expect(result, isA<ReceiveStockProductUnavailable>());
    expect(repository.batches, isEmpty);
    expect(repository.movements, isEmpty);
  });

  test('passes the explicitly selected shop through to the repository', () async {
    final recording = _RecordingRepository(repository);
    final subject = ReceiveStock(repository: recording, idempotencyKeyGenerator: () => 'R1');

    await subject(input(shopId: 'shop-1'));

    expect(recording.lastRequest?.shopId, 'shop-1');
    expect(recording.lastRequest?.productId, 'P1');
  });

  test('an exact retry reuses one key and does not duplicate stock', () async {
    final first = await useCase(input(expiryDate: LocalDate(2026, 9, 12)));
    final retry = await useCase(
      input(expiryDate: LocalDate(2026, 9, 12)),
      retryIdempotencyKey: first.idempotencyKey,
    );

    expect((first as ReceiveStockSuccess).receipt.wasDuplicate, isFalse);
    expect((retry as ReceiveStockSuccess).receipt.wasDuplicate, isTrue);
    expect(retry.receipt.batch.id, first.receipt.batch.id);
    expect(repository.batches, hasLength(1));
    expect(repository.movements, hasLength(1));
    expect(keySequence, 1);
  });

  test('concurrent duplicate submissions converge on one logical receipt', () async {
    final results = await Future.wait([
      useCase(input(), retryIdempotencyKey: 'same-logical-request'),
      useCase(input(), retryIdempotencyKey: 'same-logical-request'),
    ]);

    expect(results, everyElement(isA<ReceiveStockSuccess>()));
    expect(
      results.cast<ReceiveStockSuccess>().map((result) => result.receipt.batch.id).toSet(),
      hasLength(1),
    );
    expect(repository.batches, hasLength(1));
    expect(repository.movements, hasLength(1));
  });

  test('conflicting idempotency reuse returns an explicit conflict', () async {
    final first = await useCase(input());
    final conflict = await useCase(input(quantity: 21), retryIdempotencyKey: first.idempotencyKey);

    expect(conflict, isA<ReceiveStockIdempotencyConflict>());
    expect(repository.batches, hasLength(1));
    expect(repository.movements, hasLength(1));
  });

  for (final entry in <InventoryRepositoryFailureKind, Matcher>{
    InventoryRepositoryFailureKind.authorization: isA<ReceiveStockAuthorizationFailure>(),
    InventoryRepositoryFailureKind.productUnavailable: isA<ReceiveStockProductUnavailable>(),
    InventoryRepositoryFailureKind.idempotencyConflict: isA<ReceiveStockIdempotencyConflict>(),
    InventoryRepositoryFailureKind.unavailable: isA<ReceiveStockBackendUnavailable>(),
    InventoryRepositoryFailureKind.invalidResponse: isA<ReceiveStockBackendUnavailable>(),
  }.entries) {
    test('maps ${entry.key.name} repository failure', () async {
      final subject = ReceiveStock(
        repository: _FailingRepository(entry.key),
        idempotencyKeyGenerator: () => 'R1',
      );

      expect(await subject(input()), entry.value);
    });
  }
}

final class _RecordingRepository implements InventoryRepository {
  _RecordingRepository(this.delegate);

  final InventoryRepository delegate;
  ReceivingRequest? lastRequest;

  @override
  Future<List<Product>> listProducts({required String shopId}) {
    return delegate.listProducts(shopId: shopId);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) {
    lastRequest = request;
    return delegate.receive(request);
  }
}

final class _FailingRepository implements InventoryRepository {
  const _FailingRepository(this.kind);

  final InventoryRepositoryFailureKind kind;

  @override
  Future<List<Product>> listProducts({required String shopId}) async => const [];

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) {
    throw InventoryRepositoryException(kind, 'Injected failure.');
  }
}
