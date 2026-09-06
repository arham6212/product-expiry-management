import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_theme.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/home/presentation/home_page.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard.dart';
import 'package:product_expiry_management/features/inventory/application/inventory_repository_provider.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  testWidgets('initial load shows progress, then data', (tester) async {
    final completer = Completer<ExpiryDashboardSnapshot>();
    final repository = _DashboardRepository((_) => completer.future);
    await _pumpHome(tester, repository: repository);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(repository.receiveCalls, 0);

    completer.complete(_singleItemSnapshot('shop-a', 'Shop A milk'));
    await tester.pumpAndSettle();

    expect(find.text('Shop A milk'), findsOneWidget);
  });

  testWidgets('empty dashboard is a successful action-oriented state', (tester) async {
    final repository = _DashboardRepository((_) async => _emptySnapshot());
    await _pumpHome(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(find.text('Start tracking expiries'), findsOneWidget);
    expect(find.textContaining('Scan your first product'), findsOneWidget);
  });

  testWidgets('controls errors and Retry reloads through actions', (tester) async {
    int attempts = 0;
    final repository = _DashboardRepository((_) async {
      attempts += 1;
      if (attempts == 1) {
        throw const InventoryRepositoryException(
          InventoryRepositoryFailureKind.unavailable,
          'secret database endpoint leaked',
        );
      }
      return _emptySnapshot();
    });
    await _pumpHome(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(find.text('Could not load dashboard'), findsOneWidget);
    expect(find.textContaining('secret database'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Start tracking expiries'), findsOneWidget);
  });

  testWidgets('visible refresh reloads through actions', (tester) async {
    final repository = _DashboardRepository((_) async => _emptySnapshot());
    await _pumpHome(tester, repository: repository);
    await tester.pumpAndSettle();

    // Pull down to refresh since it's a RefreshIndicator
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(repository.loadedShopIds, ['shop-a', 'shop-a']);
  });

  testWidgets('Shop switch never renders stale data from the previous Shop', (tester) async {
    final activeShop = _MutableShopAccess(_access('shop-a', ShopMembershipRole.owner));
    final shopB = Completer<ExpiryDashboardSnapshot>();
    final repository = _DashboardRepository((shopId) {
      if (shopId == 'shop-a') return Future.value(_singleItemSnapshot('shop-a', 'Shop A milk'));
      return shopB.future;
    });
    await _pumpHome(tester, repository: repository, mutableAccess: activeShop);
    await tester.pumpAndSettle();
    expect(find.text('Shop A milk'), findsOneWidget);

    final context = tester.element(find.byType(HomePage));
    final container = ProviderScope.containerOf(context);
    activeShop.value = _access('shop-b', ShopMembershipRole.owner);
    container.invalidate(activeShopProvider);
    await tester.pump();

    expect(find.text('Shop A milk'), findsNothing);

    shopB.complete(_singleItemSnapshot('shop-b', 'Shop B yogurt'));
    await tester.pumpAndSettle();
    expect(find.text('Shop B yogurt'), findsOneWidget);
    expect(find.text('Shop A milk'), findsNothing);
  });

  testWidgets('dashboard has no overflow on a compact phone viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHome(
      tester,
      repository: _DashboardRepository((_) async => _populatedSnapshot('shop-a')),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
  });

  testWidgets('dashboard remains usable with large text on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpHome(
      tester,
      repository: _DashboardRepository((_) async => _populatedSnapshot('shop-a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock priorities'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required InventoryRepository repository,
  ShopAccess? access,
  _MutableShopAccess? mutableAccess,
}) {
  final currentAccess = access ?? _access('shop-a', ShopMembershipRole.owner);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(repository),
        activeShopProvider.overrideWith((ref) => mutableAccess?.value ?? currentAccess),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: const HomePage()),
      ),
    ),
  );
}

ExpiryDashboardSnapshot _emptySnapshot() {
  return ExpiryDashboardSnapshot(referenceDate: LocalDate(2026, 9, 4), items: const []);
}

ExpiryDashboardSnapshot _singleItemSnapshot(String shopId, String productName) {
  return ExpiryDashboardSnapshot(
    referenceDate: LocalDate(2026, 9, 4),
    items: [
      _item(
        shopId: shopId,
        id: 'one',
        productName: productName,
        expiryDate: LocalDate(2026, 9, 3),
        category: ExpiryRiskCategory.expiresToday,
      ),
    ],
  );
}

ExpiryDashboardSnapshot _populatedSnapshot(String shopId) {
  return ExpiryDashboardSnapshot(
    referenceDate: LocalDate(2026, 9, 4),
    items: [
      _item(
        shopId: shopId,
        id: 'expired',
        productName: 'Expired milk',
        productBrand: 'Almarai',
        lotNumber: 'LOT-1',
        expiryDate: LocalDate(2026, 9, 3),
        category: ExpiryRiskCategory.expiresToday,
        quantity: 4,
      ),
      _item(
        shopId: shopId,
        id: 'today',
        productName: 'Today yogurt',
        expiryDate: LocalDate(2026, 9, 4),
        category: ExpiryRiskCategory.expiresToday,
      ),
      _item(
        shopId: shopId,
        id: 'next7',
        productName: 'Soon cheese',
        expiryDate: LocalDate(2026, 9, 11),
        category: ExpiryRiskCategory.next7Days,
      ),
      _item(
        shopId: shopId,
        id: 'days8To30',
        productName: 'Near juice',
        expiryDate: LocalDate(2026, 10, 4),
        category: ExpiryRiskCategory.days8To30,
      ),
      _item(
        shopId: shopId,
        id: 'later',
        productName: 'Later cereal',
        expiryDate: LocalDate(2026, 10, 5),
        category: ExpiryRiskCategory.later,
      ),
      _item(
        shopId: shopId,
        id: 'unknown',
        productName: 'Legacy bread',
        expiryDate: null,
        category: null,
      ),
    ],
  );
}

ExpiryDashboardItem _item({
  required String shopId,
  required String id,
  required String productName,
  required LocalDate? expiryDate,
  required ExpiryRiskCategory? category,
  String? productBrand,
  String? lotNumber,
  int quantity = 1,
}) {
  return ExpiryDashboardItem(
    shopId: shopId,
    batchId: '$shopId-$id-batch',
    productId: '$shopId-$id-product',
    productName: productName,
    productBrand: productBrand,
    expiryDate: expiryDate,
    daysToExpiry: category == ExpiryRiskCategory.expired
        ? -1
        : (category == ExpiryRiskCategory.expiresToday ? 0 : 2),
    riskCategory: category,
    currentQuantity: quantity,
    lotNumber: lotNumber,
    receivedAt: DateTime.utc(2026, 8, 30, 23, 45),
  );
}

ShopAccess _access(String shopId, ShopMembershipRole role) {
  final timestamp = DateTime.utc(2026, 9, 1);
  return ShopAccess(
    shop: Shop(
      id: shopId,
      name: shopId == 'shop-a' ? 'Shop A' : 'Shop B',
      timeZone: 'Asia/Qatar',
      currencyCode: 'QAR',
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    membership: ShopMembership(shopId: shopId, userId: 'user-1', role: role, createdAt: timestamp),
  );
}

final class _MutableShopAccess {
  _MutableShopAccess(this.value);

  ShopAccess value;
}

typedef _DashboardLoader = Future<ExpiryDashboardSnapshot> Function(String shopId);

final class _DashboardRepository implements InventoryRepository {
  _DashboardRepository(this.loader);

  final _DashboardLoader loader;
  final List<String> loadedShopIds = [];
  int receiveCalls = 0;

  @override
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) {
    loadedShopIds.add(shopId);
    return loader(shopId);
  }

  @override
  Future<List<Product>> listProducts({required String shopId}) async => const [];

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) {
    receiveCalls += 1;
    throw StateError('The Home presentation must not receive stock directly.');
  }
}
