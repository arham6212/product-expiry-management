import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_theme.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/expiry_dashboard.dart';
import 'package:product_expiry_management/features/inventory/application/inventory_repository_provider.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';
import 'package:product_expiry_management/features/inventory/presentation/product_details_page.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final timestamp = DateTime.utc(2026, 9, 1);
  final product = Product(
    id: 'product-1',
    shopId: 'shop-1',
    name: 'A very long premium full-fat fresh milk product name',
    brand: 'Local Dairy',
    category: 'Dairy',
    catalogProductId: 'catalog-1',
    sellingPriceMinor: 725,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final access = ShopAccess(
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

  testWidgets('renders identity, price, catalog metadata, and urgent batches first', (
    tester,
  ) async {
    final repository = InMemoryInventoryRepository(
      products: [product],
      batches: [
        _batch('later', LocalDate(2026, 9, 20), quantity: 8, lot: 'LOT-LATER'),
        _batch('expired', LocalDate(2026, 9, 4), quantity: 3, lot: 'LOT-URGENT'),
      ],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    await _pump(tester, repository: repository, access: access);

    expect(find.text(product.name), findsWidgets);
    expect(find.text('Local Dairy'), findsWidgets);
    expect(find.text('QAR 7.25'), findsOneWidget);
    expect(find.text('Expired'), findsWidgets);
    expect(find.text('Qty 3'), findsOneWidget);
    expect(find.text('Lot / batch: LOT-URGENT'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Lot / batch: LOT-URGENT').first).dy,
      lessThan(tester.getTopLeft(find.text('Lot / batch: LOT-LATER').first).dy),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('catalog-1'), findsOneWidget);
  });

  testWidgets('shows a truthful no-active-batch state', (tester) async {
    final repository = InMemoryInventoryRepository(
      products: [product],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    await _pump(tester, repository: repository, access: access);

    expect(find.text('No active batch'), findsWidgets);
    expect(find.textContaining('Receive stock to begin tracking'), findsOneWidget);
    expect(find.text('QAR 7.25'), findsOneWidget);
  });

  testWidgets('long identity remains usable on a compact large-text viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = InMemoryInventoryRepository(
      products: [product],
      batches: [_batch('soon', LocalDate(2026, 9, 6), quantity: 2, lot: 'LOT-1')],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    await _pump(tester, repository: repository, access: access);

    expect(find.text(product.name), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
  });

  testWidgets('load error offers a working retry', (tester) async {
    final delegate = InMemoryInventoryRepository(
      products: [product],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 5),
    );
    final repository = _RetryInventoryRepository(delegate);
    await _pump(tester, repository: repository, access: access);

    expect(find.text('Product could not be loaded'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text(product.name), findsWidgets);
    expect(repository.productLoadAttempts, 2);
  });
}

Batch _batch(String id, LocalDate expiry, {required int quantity, required String lot}) {
  final timestamp = DateTime.utc(2026, 9, 1);
  return Batch(
    id: id,
    shopId: 'shop-1',
    productId: 'product-1',
    expiryDate: expiry,
    currentQuantity: quantity,
    lotCode: lot,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required InventoryRepository repository,
  required ShopAccess access,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(repository),
        activeShopProvider.overrideWithValue(access),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProductDetailsPage(productId: 'product-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _RetryInventoryRepository implements InventoryRepository {
  _RetryInventoryRepository(this.delegate);

  final InMemoryInventoryRepository delegate;
  int productLoadAttempts = 0;

  @override
  Future<List<Product>> listProducts({required String shopId}) {
    productLoadAttempts += 1;
    if (productLoadAttempts == 1) {
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Temporary failure',
      );
    }
    return delegate.listProducts(shopId: shopId);
  }

  @override
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) {
    return delegate.loadExpiryDashboard(shopId: shopId);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) => delegate.receive(request);
}
