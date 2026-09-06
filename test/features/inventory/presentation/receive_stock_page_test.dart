import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock_controller.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';
import 'package:product_expiry_management/features/inventory/presentation/receive_stock_page.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
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
      catalogProductId: 'catalog-1',
      sellingPriceMinor: 725,
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
            currencyCode: 'USD',
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
    String? sellingPrice,
    String expiry = '2026-09-12',
    String lot = 'LOT-7',
  }) async {
    if (sellingPrice != null) {
      await tester.enterText(find.byKey(const Key('sellingPriceField')), sellingPrice);
    }
    await tester.enterText(find.byKey(const Key('quantityField')), quantity);
    if (expiry.isNotEmpty) {
      await tester.enterText(find.byKey(const Key('expiryField')), expiry);
    }
    if (lot.isNotEmpty) {
      if (find.byKey(const Key('lotNumberField')).evaluate().isEmpty) {
        await tester.ensureVisible(find.byKey(const Key('receivingMoreDetails')));
        await tester.tap(find.text('More details'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const Key('lotNumberField')), lot);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveReceivedStockButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('uses active shop currency and shows metadata below the product', (tester) async {
    product = product.withScanMetadata(barcode: '6281007000062', packagingDisplay: '1 L');
    await pumpPage(tester, activeShop: _workerAccess(timestamp));
    expect(find.text('Selling price (QAR) *'), findsOneWidget);
    expect(find.text('Price per selling unit'), findsOneWidget);
    expect(find.text('1 L · 6281007000062'), findsOneWidget);
    expect(find.text('Add stock'), findsNothing);
    expect(find.byKey(const Key('addProductWithoutBarcodeButton')), findsNothing);
    expect(find.byKey(const Key('lotNumberField')), findsNothing);
    expect(find.text('0/120'), findsNothing);
  });

  testWidgets('save remains above the keyboard and keyboards match input types', (tester) async {
    await pumpPage(tester);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('sellingPriceField')),
              matching: find.byType(TextField),
            ),
          )
          .keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('quantityField')),
              matching: find.byType(TextField),
            ),
          )
          .keyboardType,
      TextInputType.number,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('saveReceivedStockButton'));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(300));
    expect(save.hitTestable(), findsOneWidget);
  });

  testWidgets('preselects resolved Product and records received stock', (tester) async {
    await pumpPage(tester);
    await fillForm(tester);

    final productField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('productField')),
    );
    expect(productField.initialValue, product.id);
    expect(_fieldText(tester, 'sellingPriceField'), '7.25');

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

  testWidgets('blank quantity is saved as unknown without fabricating a count', (tester) async {
    await pumpPage(tester);
    await fillForm(tester, quantity: '', lot: '');
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();
    expect(find.text('Stock received'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(repository.batches.single.currentQuantity, isNull);
    expect(repository.movements.single.quantityDelta, isNull);
  });

  testWidgets('offers an optional product photo without blocking receiving', (tester) async {
    await pumpPage(tester);

    expect(find.text('Add photo'), findsOneWidget);
    expect(find.byKey(const Key('addProductWithoutBarcodeButton')), findsNothing);
    expect(find.text('Add stock'), findsNothing);
    await fillForm(tester);
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stock received'), findsOneWidget);
  });

  testWidgets('shows Shop currency and persists an edited existing Product price', (tester) async {
    await pumpPage(tester);

    expect(find.text('Selling price (USD) *'), findsOneWidget);
    expect(_fieldText(tester, 'sellingPriceField'), '7.25');
    await fillForm(tester, sellingPrice: '8.50');
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();

    final updated = (await repository.listProducts(shopId: product.shopId)).single;
    expect(updated.sellingPriceMinor, 850);
  });

  testWidgets('rejects missing, zero, negative, and malformed selling prices', (tester) async {
    await pumpPage(tester);

    for (final invalid in ['', '0', '-1', 'abc', 'NaN', 'Infinity']) {
      await tester.enterText(find.byKey(const Key('sellingPriceField')), invalid);
      await fillForm(tester);
      await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
      await tester.pump();
      expect(
        find.text(
          invalid.isEmpty
              ? 'Enter a selling price.'
              : 'Enter a price greater than zero with up to 2 decimal places.',
        ),
        findsOneWidget,
        reason: invalid,
      );
      expect(repository.batches, isEmpty);
    }
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
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('saveReceivedStockButton')), findsOneWidget);

    gate.complete(
      await repository.receive(
        ReceivingRequest(
          shopId: 'shop-1',
          productId: 'P1',
          quantity: 20,
          sellingPriceMinor: 725,
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

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
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
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
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
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) {
    return delegate.loadExpiryDashboard(shopId: shopId);
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
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) {
    return delegate.loadExpiryDashboard(shopId: shopId);
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
      currencyCode: 'QAR',
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
