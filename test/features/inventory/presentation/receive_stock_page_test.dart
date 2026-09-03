import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock_controller.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';
import 'package:product_expiry_management/features/inventory/presentation/receive_stock_page.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 30);
  late Product product;
  late InMemoryInventoryRepository repository;
  late ReceiveStock useCase;
  var id = 0;
  var key = 0;

  setUp(() {
    id = 0;
    key = 0;
    product = Product(
      id: 'P1',
      shopId: 'shop-1',
      name: 'Almarai Milk 1L',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    repository = InMemoryInventoryRepository(
      products: [product],
      idGenerator: (prefix) => '$prefix-${id++}',
      clock: () => timestamp,
    );
    useCase = ReceiveStock(
      repository: repository,
      idempotencyKeyGenerator: () => 'receive-${key++}',
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    InventoryRepository? displayedRepository,
    ReceiveStock? receiveStock,
    ProductCatalogRepository? productCatalogRepository,
    ShopAccess? activeShop,
    bool withInitialProduct = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(displayedRepository ?? repository),
          receiveStockProvider.overrideWithValue(receiveStock ?? useCase),
          if (productCatalogRepository != null)
            productCatalogRepositoryProvider.overrideWithValue(productCatalogRepository),
          if (activeShop != null) activeShopProvider.overrideWithValue(activeShop),
        ],
        child: MaterialApp(
          home: ReceiveStockPage(
            shopId: product.shopId,
            initialProduct: withInitialProduct ? product : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String quantity = '20',
    String expiry = '2026-09-12',
    String lot = 'LOT-7',
  }) async {
    await tester.enterText(find.byKey(const Key('quantityField')), quantity);
    if (expiry.isNotEmpty) {
      await tester.enterText(find.byKey(const Key('expiryField')), expiry);
    }
    if (lot.isNotEmpty) {
      await tester.enterText(find.byKey(const Key('lotNumberField')), lot);
    }
  }

  testWidgets('preselects resolved Product and records received stock', (tester) async {
    await pumpPage(tester);
    await fillForm(tester);

    final productField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('productField')),
    );
    expect(productField.initialValue, product.id);

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stock received'), findsOneWidget);
    expect(find.text(product.name), findsOneWidget);
    expect(find.text('2026-09-12'), findsOneWidget);
    expect(find.text('LOT-7'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(repository.batches, hasLength(1));
    expect(repository.movements, hasLength(1));
  });

  testWidgets('creates a barcode-less Product, preserves the draft, and receives it', (
    tester,
  ) async {
    final catalogRepository = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-created',
      clock: () => timestamp,
    );
    final receivingRepository = _AcceptCreatedProductInventoryRepository(
      products: const [],
      clock: () => timestamp,
    );
    final receivingUseCase = ReceiveStock(
      repository: receivingRepository,
      idempotencyKeyGenerator: () => 'barcode-less-receive',
    );
    await pumpPage(
      tester,
      displayedRepository: receivingRepository,
      receiveStock: receivingUseCase,
      productCatalogRepository: catalogRepository,
      activeShop: _workerAccess(timestamp),
      withInitialProduct: false,
    );
    await fillForm(tester);

    await tester.tap(find.byKey(const Key('addProductWithoutBarcodeButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeLessProductName')), '  Fresh   milk  ');
    await tester.enterText(find.byKey(const Key('barcodeLessProductBrand')), ' Local Dairy ');
    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'quantityField'), '20');
    expect(_fieldText(tester, 'expiryField'), '2026-09-12');
    expect(_fieldText(tester, 'lotNumberField'), 'LOT-7');
    final productField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('productField')),
    );
    expect(productField.initialValue, 'product-created');
    expect(catalogRepository.barcodes, isEmpty);

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stock received'), findsOneWidget);
    expect(find.text('Fresh milk'), findsOneWidget);
    expect(receivingRepository.lastRequest?.productId, 'product-created');
    expect(receivingRepository.lastRequest?.expiryDate, LocalDate(2026, 9, 12));
  });

  testWidgets('requires expiry while keeping lot number optional', (tester) async {
    await pumpPage(tester);
    await fillForm(tester, expiry: '', lot: '');

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pump();

    expect(find.text('Enter an expiry date.'), findsOneWidget);
    expect(repository.batches, isEmpty);
    expect(repository.movements, isEmpty);
    expect(_fieldText(tester, 'quantityField'), '20');
  });

  testWidgets('shows local quantity validation without writing inventory', (tester) async {
    await pumpPage(tester);
    await fillForm(tester, quantity: '0');

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pump();

    expect(find.text('Quantity must be greater than zero.'), findsOneWidget);
    expect(repository.batches, isEmpty);
    expect(repository.movements, isEmpty);
  });

  testWidgets('shows malformed expiry validation without writing inventory', (tester) async {
    await pumpPage(tester);
    await fillForm(tester, expiry: 'not-a-date');

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pump();

    expect(find.text('Enter a valid date using YYYY-MM-DD.'), findsOneWidget);
    expect(repository.batches, isEmpty);
  });

  testWidgets('loading disables the button and duplicate taps submit once', (tester) async {
    final gate = Completer<ReceivingReceipt>();
    final blockingRepository = _BlockingInventoryRepository(repository, gate.future);
    final blockingUseCase = ReceiveStock(
      repository: blockingRepository,
      idempotencyKeyGenerator: () => 'R1',
    );
    await pumpPage(tester, displayedRepository: blockingRepository, receiveStock: blockingUseCase);
    await fillForm(tester);

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byKey(const Key('saveReceivedStockButton')));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(blockingRepository.receiveCalls, 1);

    gate.complete(
      await repository.receive(
        ReceivingRequest(
          shopId: 'shop-1',
          productId: 'P1',
          quantity: 20,
          expiryDate: LocalDate(2026, 9, 12),
          lotNumber: null,
          idempotencyKey: 'gate-result',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stock received'), findsOneWidget);
  });

  testWidgets('failure preserves values and retry reuses the same key', (tester) async {
    final failOnceRepository = _FailOnceInventoryRepository(repository);
    final retryUseCase = ReceiveStock(
      repository: failOnceRepository,
      idempotencyKeyGenerator: () => 'logical-request-${key++}',
    );
    await pumpPage(tester, displayedRepository: failOnceRepository, receiveStock: retryUseCase);
    await fillForm(tester);

    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Stock may not have been saved. Your entries are still here; retry safely.'),
      findsOneWidget,
    );
    expect(_fieldText(tester, 'quantityField'), '20');
    expect(_fieldText(tester, 'expiryField'), '2026-09-12');
    expect(_fieldText(tester, 'lotNumberField'), 'LOT-7');

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Stock received'), findsOneWidget);
    expect(failOnceRepository.seenKeys, ['logical-request-0', 'logical-request-0']);
  });

  testWidgets('editing after failure starts a new logical submission key', (tester) async {
    final failOnceRepository = _FailOnceInventoryRepository(repository);
    final retryUseCase = ReceiveStock(
      repository: failOnceRepository,
      idempotencyKeyGenerator: () => 'logical-request-${key++}',
    );
    await pumpPage(tester, displayedRepository: failOnceRepository, receiveStock: retryUseCase);
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quantityField')), '21');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stock received'), findsOneWidget);
    expect(failOnceRepository.seenKeys, ['logical-request-0', 'logical-request-1']);
  });
}

String _fieldText(WidgetTester tester, String key) {
  return tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
}

final class _BlockingInventoryRepository implements InventoryRepository {
  _BlockingInventoryRepository(this.delegate, this.receipt);

  final InventoryRepository delegate;
  final Future<ReceivingReceipt> receipt;
  var receiveCalls = 0;

  @override
  Future<List<Product>> listProducts({required String shopId}) {
    return delegate.listProducts(shopId: shopId);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) {
    receiveCalls += 1;
    return receipt;
  }
}

final class _FailOnceInventoryRepository implements InventoryRepository {
  _FailOnceInventoryRepository(this.delegate);

  final InventoryRepository delegate;
  final List<String> seenKeys = [];
  var _shouldFail = true;

  @override
  Future<List<Product>> listProducts({required String shopId}) {
    return delegate.listProducts(shopId: shopId);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) {
    seenKeys.add(request.idempotencyKey);
    if (_shouldFail) {
      _shouldFail = false;
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Injected network failure.',
      );
    }
    return delegate.receive(request);
  }
}

ShopAccess _workerAccess(DateTime timestamp) {
  return ShopAccess(
    shop: Shop(
      id: 'shop-1',
      name: 'Shop',
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    membership: ShopMembership(
      shopId: 'shop-1',
      userId: 'worker-1',
      role: ShopMembershipRole.worker,
      createdAt: timestamp,
    ),
  );
}

final class _AcceptCreatedProductInventoryRepository implements InventoryRepository {
  _AcceptCreatedProductInventoryRepository({required this.products, required this.clock});

  final List<Product> products;
  final DateTime Function() clock;
  ReceivingRequest? lastRequest;

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    return products.where((product) => product.shopId == shopId).toList();
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) async {
    lastRequest = request;
    final timestamp = clock();
    final batch = Batch(
      id: 'batch-created',
      shopId: request.shopId,
      productId: request.productId,
      expiryDate: request.expiryDate,
      currentQuantity: request.quantity,
      lotCode: request.lotNumber,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    return ReceivingReceipt(
      batch: batch,
      movement: InventoryMovement(
        id: 'movement-created',
        shopId: request.shopId,
        batchId: batch.id,
        type: InventoryMovementType.received,
        quantityDelta: request.quantity,
        occurredAt: timestamp,
        createdAt: timestamp,
        idempotencyKey: request.idempotencyKey,
      ),
      wasDuplicate: false,
    );
  }
}
