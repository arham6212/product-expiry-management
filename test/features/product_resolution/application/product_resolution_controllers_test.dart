import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/auth/application/auth_controller.dart';
import 'package:product_expiry_management/features/auth/application/auth_service.dart';
import 'package:product_expiry_management/features/auth/data/in_memory_auth_service.dart';
import 'package:product_expiry_management/features/product_resolution/application/create_manual_product_for_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/manual_product_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/resolve_product_by_barcode.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';
import 'package:product_expiry_management/features/shops/data/in_memory_shop_repository.dart';

void main() {
  const barcode = '5000112519945';
  final now = DateTime.utc(2026, 8, 31);
  late ShopAccess shopA;
  late ShopAccess shopB;

  setUp(() {
    shopA = _access('shop-a', now);
    shopB = _access('shop-b', now);
  });

  test('lookup result is discarded when the selected shop changes in flight', () async {
    final resolver = _ControlledResolver();
    final container = _container(shopA: shopA, shopB: shopB, resolver: resolver);
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(shopSessionControllerProvider, (_, _) {});
    addTearDown(sessionSubscription.close);
    await container.read(shopSessionControllerProvider.future);
    final subscription = container.listen(productResolutionControllerProvider, (_, _) {});
    addTearDown(subscription.close);

    final pending = container.read(productResolutionControllerProvider.notifier).resolve(barcode);
    await resolver.called.future;
    _selectShop(container, shopB);
    resolver.complete(ProductFoundLocally(barcode: barcode, product: _product(shopA, now)));
    await pending;

    final state = container.read(productResolutionControllerProvider);
    expect(state.isResolving, isFalse);
    expect(state.result, isNull);
  });

  test('manual save blocks double submit and does not return an old-shop Product', () async {
    final repository = _ControlledCatalogRepository();
    final creator = CreateManualProductForBarcode(shopId: shopA.shop.id, repository: repository);
    final container = _container(
      shopA: shopA,
      shopB: shopB,
      resolver: _ControlledResolver(),
      manualCreator: creator,
    );
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(shopSessionControllerProvider, (_, _) {});
    addTearDown(sessionSubscription.close);
    await container.read(shopSessionControllerProvider.future);
    final subscription = container.listen(manualProductControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(manualProductControllerProvider.notifier);

    final pending = controller.save(barcode: barcode, name: 'Manual Product');
    await repository.called.future;
    expect(await controller.save(barcode: barcode, name: 'Duplicate tap'), isNull);
    expect(repository.saveCalls, 1);

    _selectShop(container, shopB);
    repository.complete(ProductCatalogSaveResult(product: _product(shopA, now), wasCreated: true));
    expect(await pending, isNull);

    final state = container.read(manualProductControllerProvider);
    expect(state.isSaving, isFalse);
    expect(state.error, contains('active shop changed'));
  });

  test('lookup result is discarded when the authenticated shop session ends', () async {
    const user = AuthenticatedUser(id: 'user-1', email: 'owner@example.test');
    final auth = InMemoryAuthService(currentUser: user);
    final resolver = _ControlledResolver();
    final container = _container(shopA: shopA, shopB: shopB, resolver: resolver, auth: auth);
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(shopSessionControllerProvider, (_, _) {});
    addTearDown(sessionSubscription.close);
    await container.read(shopSessionControllerProvider.future);
    final controllerSubscription = container.listen(productResolutionControllerProvider, (_, _) {});
    addTearDown(controllerSubscription.close);

    final pending = container.read(productResolutionControllerProvider.notifier).resolve(barcode);
    await resolver.called.future;
    final signedOut = Completer<void>();
    final activeShopSubscription = container.listen(activeShopProvider, (_, next) {
      if (next == null && !signedOut.isCompleted) signedOut.complete();
    });
    addTearDown(activeShopSubscription.close);
    await auth.signOut();
    await signedOut.future;

    resolver.complete(ProductFoundLocally(barcode: barcode, product: _product(shopA, now)));
    await pending;

    expect(container.read(productResolutionControllerProvider).result, isNull);
  });
}

ProviderContainer _container({
  required ShopAccess shopA,
  required ShopAccess shopB,
  required ProductResolver resolver,
  CreateManualProductForBarcode? manualCreator,
  InMemoryAuthService? auth,
}) {
  const user = AuthenticatedUser(id: 'user-1', email: 'owner@example.test');
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(auth ?? InMemoryAuthService(currentUser: user)),
      shopRepositoryProvider.overrideWithValue(
        InMemoryShopRepository(userId: user.id, shops: [shopA, shopB]),
      ),
      productResolverProvider.overrideWithValue(resolver),
      if (manualCreator != null) manualProductCreatorProvider.overrideWithValue(manualCreator),
    ],
  );
}

void _selectShop(ProviderContainer container, ShopAccess shop) {
  final controller = container.read(shopSessionControllerProvider.notifier);
  controller.chooseAnotherShop();
  controller.selectShop(shop);
}

ShopAccess _access(String id, DateTime now) {
  return ShopAccess(
    shop: Shop(
      id: id,
      name: id,
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: now,
      updatedAt: now,
    ),
    membership: ShopMembership(
      shopId: id,
      userId: 'user-1',
      role: ShopMembershipRole.owner,
      createdAt: now,
    ),
  );
}

Product _product(ShopAccess access, DateTime now) {
  return Product(
    id: 'product-${access.shop.id}',
    shopId: access.shop.id,
    name: 'Product from ${access.shop.id}',
    createdAt: now,
    updatedAt: now,
  );
}

final class _ControlledResolver implements ProductResolver {
  final called = Completer<void>();
  final _result = Completer<ProductResolutionResult>();

  void complete(ProductResolutionResult result) => _result.complete(result);

  @override
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  }) {
    if (!called.isCompleted) called.complete();
    return _result.future;
  }
}

final class _ControlledCatalogRepository implements ProductCatalogRepository {
  final called = Completer<void>();
  final _result = Completer<ProductCatalogSaveResult>();
  var saveCalls = 0;

  void complete(ProductCatalogSaveResult result) => _result.complete(result);

  @override
  Future<Product?> findByBarcode({
    required String shopId,
    required NormalizedBarcode barcode,
  }) async => null;

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) => throw UnimplementedError();

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
  }) {
    saveCalls += 1;
    if (!called.isCompleted) called.complete();
    return _result.future;
  }
}
