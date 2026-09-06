import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import 'expiry_dashboard_controller.dart';
import 'inventory_repository_provider.dart';

final _inventoryCatalogForShopProvider = AsyncNotifierProvider.autoDispose
    .family<InventoryCatalogController, InventoryCatalogState, String>(
      InventoryCatalogController.new,
      retry: (retryCount, error) => null,
    );

final inventoryCatalogProvider = Provider.autoDispose<AsyncValue<InventoryCatalogState>>((ref) {
  final activeShop = ref.watch(activeShopProvider);
  if (activeShop == null) {
    return AsyncError(
      const ShopAccessException('Select a shop before loading inventory.'),
      StackTrace.current,
    );
  }
  return ref.watch(_inventoryCatalogForShopProvider(activeShop.shop.id));
});

final inventoryCatalogActionsProvider = Provider.autoDispose<InventoryCatalogActions>(
  InventoryCatalogActions.new,
);

final class InventoryCatalogState {
  InventoryCatalogState({required Iterable<Product> products, required this.dashboard})
    : products = List.unmodifiable(products);

  final List<Product> products;
  final ExpiryDashboardState dashboard;

  Product? productById(String productId) {
    for (final product in products) {
      if (product.id == productId) return product;
    }
    return null;
  }
}

final class InventoryCatalogController extends AsyncNotifier<InventoryCatalogState> {
  InventoryCatalogController(this.shopId);

  final String shopId;

  @override
  Future<InventoryCatalogState> build() async {
    final activeShop = ref.watch(activeShopProvider);
    if (activeShop == null || activeShop.shop.id != shopId) {
      throw const ShopAccessException('Select a shop before loading inventory.');
    }

    final productsFuture = ref.watch(inventoryRepositoryProvider).listProducts(shopId: shopId);
    final dashboardFuture = ref.watch(expiryDashboardActionsProvider).future;
    final results = await Future.wait<Object>([productsFuture, dashboardFuture]);

    if (ref.read(activeShopProvider)?.shop.id != shopId) {
      throw const ShopAccessException('The active shop changed while inventory was loading.');
    }

    return InventoryCatalogState(
      products: results[0] as List<Product>,
      dashboard: results[1] as ExpiryDashboardState,
    );
  }

  void retry() => ref.invalidateSelf();
}

final class InventoryCatalogActions {
  InventoryCatalogActions(this._ref);

  final Ref _ref;

  Future<void> retry() async {
    final shopId = _ref.read(activeShopProvider)?.shop.id;
    if (shopId == null) return;
    _ref.invalidate(_inventoryCatalogForShopProvider(shopId));
    await _ref.read(_inventoryCatalogForShopProvider(shopId).future);
  }

  void invalidateShop(String shopId) => _ref.invalidate(_inventoryCatalogForShopProvider(shopId));

  void invalidateCurrent() {
    final shopId = _ref.read(activeShopProvider)?.shop.id;
    if (shopId != null) _ref.invalidate(_inventoryCatalogForShopProvider(shopId));
  }
}
