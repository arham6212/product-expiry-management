import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard_controller.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock_controller.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final timestamp = DateTime.utc(2026, 9, 4, 8);

  test('loads and buckets the current Shop snapshot without writing', () async {
    final snapshot = _snapshot('shop-a', referenceDate: LocalDate(2026, 9, 4));
    final repository = _RecordingInventoryRepository((shopId) async => snapshot);
    final container = _container(repository, activeShop: _access('shop-a', timestamp));
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    final load = container.read(expiryDashboardActionsProvider).future;
    expect(container.read(expiryDashboardProvider), isA<AsyncLoading<ExpiryDashboardState>>());
    final state = await load;

    expect(repository.loadedShopIds, ['shop-a']);
    expect(repository.receiveCalls, 0);
    expect(state.shopId, 'shop-a');
    expect(state.referenceDate, LocalDate(2026, 9, 4));
    expect(state.items, hasLength(6));
    expect(state.expired.single.riskCategory, ExpiryRiskCategory.expired);
    expect(state.expiresToday.single.riskCategory, ExpiryRiskCategory.expiresToday);
    expect(state.next7Days.single.riskCategory, ExpiryRiskCategory.next7Days);
    expect(state.days8To30.single.riskCategory, ExpiryRiskCategory.days8To30);
    expect(state.later.single.riskCategory, ExpiryRiskCategory.later);
    expect(state.needsDate.single.riskCategory, isNull);
    expect(() => state.items.add(state.items.first), throwsUnsupportedError);
    expect(() => state.expired.clear(), throwsUnsupportedError);
  });

  test('treats an authorized empty snapshot as successful data', () async {
    final repository = _RecordingInventoryRepository(
      (shopId) async =>
          ExpiryDashboardSnapshot(referenceDate: LocalDate(2026, 9, 4), items: const []),
    );
    final container = _container(repository, activeShop: _access('shop-a', timestamp));
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    final state = await container.read(expiryDashboardActionsProvider).future;

    expect(state.referenceDate, LocalDate(2026, 9, 4));
    expect(state.items, isEmpty);
    expect(state.needsDate, isEmpty);
  });

  for (final failureKind in [
    InventoryRepositoryFailureKind.authorization,
    InventoryRepositoryFailureKind.unavailable,
    InventoryRepositoryFailureKind.invalidResponse,
  ]) {
    test('exposes a controlled ${failureKind.name} repository error', () async {
      final repository = _RecordingInventoryRepository(
        (shopId) => throw InventoryRepositoryException(failureKind, 'Controlled failure.'),
      );
      final container = _container(repository, activeShop: _access('shop-a', timestamp));
      addTearDown(container.dispose);
      final subscription = _listen(container);
      addTearDown(subscription.close);

      await expectLater(
        container.read(expiryDashboardActionsProvider).future,
        throwsA(
          isA<InventoryRepositoryException>().having((error) => error.kind, 'kind', failureKind),
        ),
      );
      expect(container.read(expiryDashboardProvider), isA<AsyncError<ExpiryDashboardState>>());
    });
  }

  test('retry after a failed load uses the current Shop and succeeds', () async {
    var attempts = 0;
    final repository = _RecordingInventoryRepository((shopId) async {
      attempts += 1;
      if (attempts == 1) {
        throw const InventoryRepositoryException(
          InventoryRepositoryFailureKind.unavailable,
          'Offline.',
        );
      }
      return _snapshot(shopId, referenceDate: LocalDate(2026, 9, 5));
    });
    final container = _container(repository, activeShop: _access('shop-a', timestamp));
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    await expectLater(
      container.read(expiryDashboardActionsProvider).future,
      throwsA(isA<InventoryRepositoryException>()),
    );
    await container.read(expiryDashboardActionsProvider).retry();

    expect(
      container.read(expiryDashboardProvider).requireValue.referenceDate,
      LocalDate(2026, 9, 5),
    );
    expect(repository.loadedShopIds, ['shop-a', 'shop-a']);
  });

  test('explicit refresh reloads without changing the authoritative date locally', () async {
    var calls = 0;
    final repository = _RecordingInventoryRepository((shopId) async {
      calls += 1;
      return _snapshot(shopId, referenceDate: LocalDate(2026, 9, 3 + calls));
    });
    final container = _container(repository, activeShop: _access('shop-a', timestamp));
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    expect(
      (await container.read(expiryDashboardActionsProvider).future).referenceDate,
      LocalDate(2026, 9, 4),
    );
    await container.read(expiryDashboardActionsProvider).refresh();

    expect(
      container.read(expiryDashboardProvider).requireValue.referenceDate,
      LocalDate(2026, 9, 5),
    );
    expect(repository.loadedShopIds, ['shop-a', 'shop-a']);
  });

  test('overlapping refreshes retain only the newest response', () async {
    final olderRefresh = Completer<ExpiryDashboardSnapshot>();
    final newerRefresh = Completer<ExpiryDashboardSnapshot>();
    var calls = 0;
    final repository = _RecordingInventoryRepository((shopId) {
      calls += 1;
      return switch (calls) {
        1 => Future.value(_snapshot(shopId, referenceDate: LocalDate(2026, 9, 4))),
        2 => olderRefresh.future,
        _ => newerRefresh.future,
      };
    });
    final container = _container(repository, activeShop: _access('shop-a', timestamp));
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    await container.read(expiryDashboardActionsProvider).future;
    container.read(expiryDashboardActionsProvider).refresh().ignore();
    await _flush();
    container.read(expiryDashboardActionsProvider).refresh().ignore();
    await _flush();

    newerRefresh.complete(_snapshot('shop-a', referenceDate: LocalDate(2026, 9, 6)));
    await container.read(expiryDashboardActionsProvider).future;
    olderRefresh.complete(_snapshot('shop-a', referenceDate: LocalDate(2026, 9, 5)));
    await _flush();

    expect(repository.loadedShopIds, ['shop-a', 'shop-a', 'shop-a']);
    expect(
      container.read(expiryDashboardProvider).requireValue.referenceDate,
      LocalDate(2026, 9, 6),
    );
  });

  test('switching from Shop A reloads and exposes only Shop B data', () async {
    final activeShop = _MutableActiveShop(_access('shop-a', timestamp));
    final repository = _RecordingInventoryRepository(
      (shopId) async => _snapshot(shopId, referenceDate: LocalDate(2026, 9, 4)),
    );
    final container = _container(repository, mutableActiveShop: activeShop);
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    expect((await container.read(expiryDashboardActionsProvider).future).shopId, 'shop-a');

    activeShop.value = _access('shop-b', timestamp);
    container.invalidate(activeShopProvider);
    final switchedFuture = container.read(expiryDashboardActionsProvider).future;
    expect(container.read(expiryDashboardProvider).value?.shopId, isNot('shop-a'));
    final switched = await switchedFuture;

    expect(switched.shopId, 'shop-b');
    expect(
      switched.items,
      everyElement(isA<ExpiryDashboardItem>().having((item) => item.shopId, 'shopId', 'shop-b')),
    );
    expect(repository.loadedShopIds, ['shop-a', 'shop-b']);
  });

  test('a stale Shop A response cannot overwrite Shop B state', () async {
    final activeShop = _MutableActiveShop(_access('shop-a', timestamp));
    final shopA = Completer<ExpiryDashboardSnapshot>();
    final shopB = Completer<ExpiryDashboardSnapshot>();
    final repository = _RecordingInventoryRepository(
      (shopId) => shopId == 'shop-a' ? shopA.future : shopB.future,
    );
    final container = _container(repository, mutableActiveShop: activeShop);
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    container.read(expiryDashboardActionsProvider).future.ignore();
    await _flush();
    expect(repository.loadedShopIds, ['shop-a']);

    activeShop.value = _access('shop-b', timestamp);
    container.invalidate(activeShopProvider);
    final shopBFuture = container.read(expiryDashboardActionsProvider).future;
    await _flush();
    expect(repository.loadedShopIds, ['shop-a', 'shop-b']);

    shopB.complete(_snapshot('shop-b', referenceDate: LocalDate(2026, 9, 5)));
    expect((await shopBFuture).shopId, 'shop-b');
    shopA.complete(_snapshot('shop-a', referenceDate: LocalDate(2026, 9, 3)));
    await _flush();

    expect(container.read(expiryDashboardProvider).requireValue.shopId, 'shop-b');
    expect(
      container.read(expiryDashboardProvider).requireValue.referenceDate,
      LocalDate(2026, 9, 5),
    );
  });

  test('does not call the repository when no Shop is selected', () async {
    final repository = _RecordingInventoryRepository(
      (shopId) async => _snapshot(shopId, referenceDate: LocalDate(2026, 9, 4)),
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    final subscription = _listen(container);
    addTearDown(subscription.close);

    await expectLater(
      container.read(expiryDashboardActionsProvider).future,
      throwsA(isA<ShopAccessException>()),
    );
    expect(container.read(expiryDashboardProvider), isA<AsyncError<ExpiryDashboardState>>());
    expect(repository.loadedShopIds, isEmpty);
  });

  test('a successful receive invalidates and reloads the active dashboard', () async {
    final product = _product('shop-a', timestamp);
    final repository = _RecordingInventoryRepository(
      (shopId) async => _snapshot(shopId, referenceDate: LocalDate(2026, 9, 4)),
      products: [product],
    );
    final receiveStock = ReceiveStock(
      repository: repository,
      idempotencyKeyGenerator: () => 'receive-1',
    );
    final container = ProviderContainer(
      overrides: [
        activeShopProvider.overrideWithValue(_access('shop-a', timestamp)),
        inventoryRepositoryProvider.overrideWithValue(repository),
        receiveStockProvider.overrideWithValue(receiveStock),
      ],
    );
    addTearDown(container.dispose);
    final dashboardSubscription = _listen(container);
    addTearDown(dashboardSubscription.close);
    final receiveProvider = receiveStockControllerProvider(
      ReceiveStockRouteArgs(shopId: 'shop-a', initialProduct: product),
    );
    final receiveSubscription = container.listen(receiveProvider, (_, _) {});
    addTearDown(receiveSubscription.close);

    await container.read(expiryDashboardActionsProvider).future;
    await container.read(receiveProvider.future);
    await container
        .read(receiveProvider.notifier)
        .submit(
          ReceiveStockInput(
            shopId: 'shop-a',
            productId: product.id,
            quantity: 2,
            sellingPriceMinor: 725,
            expiryDate: LocalDate(2026, 9, 20),
          ),
        );
    await container.read(expiryDashboardActionsProvider).future;

    expect(repository.receiveCalls, 1);
    expect(repository.loadedShopIds, ['shop-a', 'shop-a']);
  });

  test('a failed receive does not invalidate a loaded dashboard', () async {
    final product = _product('shop-a', timestamp);
    final repository = _RecordingInventoryRepository(
      (shopId) async => _snapshot(shopId, referenceDate: LocalDate(2026, 9, 4)),
      products: [product],
      failReceive: true,
    );
    final container = ProviderContainer(
      overrides: [
        activeShopProvider.overrideWithValue(_access('shop-a', timestamp)),
        inventoryRepositoryProvider.overrideWithValue(repository),
        receiveStockProvider.overrideWithValue(
          ReceiveStock(repository: repository, idempotencyKeyGenerator: () => 'receive-1'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final dashboardSubscription = _listen(container);
    addTearDown(dashboardSubscription.close);
    final receiveProvider = receiveStockControllerProvider(
      ReceiveStockRouteArgs(shopId: 'shop-a', initialProduct: product),
    );
    final receiveSubscription = container.listen(receiveProvider, (_, _) {});
    addTearDown(receiveSubscription.close);

    await container.read(expiryDashboardActionsProvider).future;
    await container.read(receiveProvider.future);
    await container
        .read(receiveProvider.notifier)
        .submit(
          ReceiveStockInput(
            shopId: 'shop-a',
            productId: product.id,
            quantity: 2,
            sellingPriceMinor: 725,
            expiryDate: LocalDate(2026, 9, 20),
          ),
        );
    await _flush();

    expect(repository.receiveCalls, 1);
    expect(repository.loadedShopIds, ['shop-a']);
  });
}

ProviderContainer _container(
  InventoryRepository repository, {
  ShopAccess? activeShop,
  _MutableActiveShop? mutableActiveShop,
}) {
  return ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(repository),
      activeShopProvider.overrideWith((ref) => mutableActiveShop?.value ?? activeShop),
    ],
  );
}

ProviderSubscription<AsyncValue<ExpiryDashboardState>> _listen(ProviderContainer container) {
  return container.listen(expiryDashboardProvider, (_, _) {});
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

ExpiryDashboardSnapshot _snapshot(String shopId, {required LocalDate referenceDate}) {
  return ExpiryDashboardSnapshot(
    referenceDate: referenceDate,
    items: [
      _item(shopId, 'expired', ExpiryRiskCategory.expired, referenceDate),
      _item(shopId, 'today', ExpiryRiskCategory.expiresToday, referenceDate),
      _item(shopId, 'next-7', ExpiryRiskCategory.next7Days, referenceDate),
      _item(shopId, '8-to-30', ExpiryRiskCategory.days8To30, referenceDate),
      _item(shopId, 'later', ExpiryRiskCategory.later, referenceDate),
      _item(shopId, 'unknown', null, null),
    ],
  );
}

ExpiryDashboardItem _item(
  String shopId,
  String id,
  ExpiryRiskCategory? category,
  LocalDate? expiryDate,
) {
  return ExpiryDashboardItem(
    shopId: shopId,
    batchId: '$shopId-$id-batch',
    productId: '$shopId-$id-product',
    productName: id,
    expiryDate: expiryDate,
    daysToExpiry: category == null ? null : 0,
    riskCategory: category,
    currentQuantity: 1,
    receivedAt: DateTime.utc(2026, 9, 1),
  );
}

ShopAccess _access(String shopId, DateTime timestamp) {
  return ShopAccess(
    shop: Shop(
      id: shopId,
      name: shopId,
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    membership: ShopMembership(
      shopId: shopId,
      userId: 'user-1',
      role: ShopMembershipRole.owner,
      createdAt: timestamp,
    ),
  );
}

Product _product(String shopId, DateTime timestamp) {
  return Product(
    id: 'product-1',
    shopId: shopId,
    name: 'Milk',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

final class _MutableActiveShop {
  _MutableActiveShop(this.value);

  ShopAccess value;
}

typedef _DashboardLoader = Future<ExpiryDashboardSnapshot> Function(String shopId);

final class _RecordingInventoryRepository implements InventoryRepository {
  _RecordingInventoryRepository(this.loader, {this.products = const [], this.failReceive = false});

  final _DashboardLoader loader;
  final List<Product> products;
  final bool failReceive;
  final List<String> loadedShopIds = [];
  var receiveCalls = 0;

  @override
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) {
    loadedShopIds.add(shopId);
    return loader(shopId);
  }

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    return products.where((product) => product.shopId == shopId).toList(growable: false);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) async {
    receiveCalls += 1;
    if (failReceive) {
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Injected receiving failure.',
      );
    }
    final batch = Batch(
      id: 'batch-$receiveCalls',
      shopId: request.shopId,
      productId: request.productId,
      expiryDate: request.expiryDate,
      currentQuantity: request.quantity,
      createdAt: DateTime.utc(2026, 9, 4),
      updatedAt: DateTime.utc(2026, 9, 4),
    );
    final movement = InventoryMovement(
      id: 'movement-$receiveCalls',
      shopId: request.shopId,
      batchId: batch.id,
      type: InventoryMovementType.received,
      quantityDelta: request.quantity,
      occurredAt: DateTime.utc(2026, 9, 4),
      createdAt: DateTime.utc(2026, 9, 4),
      idempotencyKey: request.idempotencyKey,
    );
    return ReceivingReceipt(batch: batch, movement: movement, wasDuplicate: false);
  }
}
