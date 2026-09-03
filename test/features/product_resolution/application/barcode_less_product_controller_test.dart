import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/barcode_less_product_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2);

  test('validates and normalizes through the repository boundary', () async {
    final repository = InMemoryProductCatalogRepository(clock: () => now);
    final container = _container(repository, _access('shop-1', now));
    addTearDown(container.dispose);
    final subscription = container.listen(
      barcodeLessProductControllerProvider('shop-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(barcodeLessProductControllerProvider('shop-1').notifier);

    expect(await controller.save(name: '   '), isNull);
    expect(
      container.read(barcodeLessProductControllerProvider('shop-1')).error,
      'Product name is required.',
    );
    expect(repository.products, isEmpty);

    final product = await controller.save(name: ' Fresh   milk ', brand: ' Local   Dairy ');

    expect(product?.name, 'Fresh milk');
    expect(product?.brand, 'Local Dairy');
    expect(repository.barcodes, isEmpty);
    expect(container.read(barcodeLessProductControllerProvider('shop-1')).error, isNull);
  });

  test('blocks duplicate submissions and discards a stale-shop result', () async {
    final repository = _ControlledCatalogRepository();
    final activeShop = _MutableActiveShop(_access('shop-1', now));
    final container = ProviderContainer(
      overrides: [
        productCatalogRepositoryProvider.overrideWithValue(repository),
        activeShopProvider.overrideWith((ref) => activeShop.value),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      barcodeLessProductControllerProvider('shop-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(barcodeLessProductControllerProvider('shop-1').notifier);

    final pending = controller.save(name: 'Milk');
    await repository.called.future;
    expect(await controller.save(name: 'Duplicate'), isNull);
    expect(repository.createCalls, 1);

    activeShop.value = _access('shop-2', now);
    container.invalidate(activeShopProvider);
    repository.complete(_product('shop-1', now));
    expect(await pending, isNull);
    expect(
      container.read(barcodeLessProductControllerProvider('shop-1')).error,
      contains('active shop changed'),
    );
  });

  test('shows a backend failure and permits a successful retry', () async {
    final repository = _FailOnceCatalogRepository(
      InMemoryProductCatalogRepository(clock: () => now),
    );
    final container = _container(repository, _access('shop-1', now));
    addTearDown(container.dispose);
    final subscription = container.listen(
      barcodeLessProductControllerProvider('shop-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(barcodeLessProductControllerProvider('shop-1').notifier);

    expect(await controller.save(name: 'Retry product'), isNull);
    expect(
      container.read(barcodeLessProductControllerProvider('shop-1')).error,
      'Product could not be created.',
    );

    expect(await controller.save(name: 'Retry product'), isNotNull);
    expect(repository.createCalls, 2);
  });
}

ProviderContainer _container(ProductCatalogRepository repository, ShopAccess activeShop) {
  return ProviderContainer(
    overrides: [
      productCatalogRepositoryProvider.overrideWithValue(repository),
      activeShopProvider.overrideWithValue(activeShop),
    ],
  );
}

ShopAccess _access(String shopId, DateTime now) {
  return ShopAccess(
    shop: Shop(
      id: shopId,
      name: shopId,
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: now,
      updatedAt: now,
    ),
    membership: ShopMembership(
      shopId: shopId,
      userId: 'worker-1',
      role: ShopMembershipRole.worker,
      createdAt: now,
    ),
  );
}

Product _product(String shopId, DateTime now) {
  return Product(
    id: 'product-1',
    shopId: shopId,
    name: 'Milk',
    source: ProductSource.localManual,
    createdAt: now,
    updatedAt: now,
  );
}

final class _MutableActiveShop {
  _MutableActiveShop(this.value);

  ShopAccess value;
}

final class _ControlledCatalogRepository implements ProductCatalogRepository {
  final called = Completer<void>();
  final _result = Completer<Product>();
  var createCalls = 0;

  void complete(Product product) => _result.complete(product);

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    createCalls += 1;
    if (!called.isCompleted) called.complete();
    return _result.future;
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode}) =>
      throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) => throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) => throw UnimplementedError();
}

final class _FailOnceCatalogRepository implements ProductCatalogRepository {
  _FailOnceCatalogRepository(this.delegate);

  final ProductCatalogRepository delegate;
  var createCalls = 0;

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    createCalls += 1;
    if (createCalls == 1) {
      throw const ProductCatalogException('Product could not be created.');
    }
    return delegate.createManualProductWithoutBarcode(shopId: shopId, product: product);
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode}) =>
      throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) => throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) => throw UnimplementedError();
}
