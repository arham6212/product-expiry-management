import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/ports/external_providers.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import 'product_catalog_repository.dart';
import 'resolve_product_by_barcode.dart';

final productCatalogRepositoryProvider = Provider<ProductCatalogRepository>((ref) {
  throw StateError('productCatalogRepositoryProvider must be overridden at the application root.');
});

final productLookupProviderProvider = Provider<ProductLookupProvider>((ref) {
  throw StateError('productLookupProviderProvider must be overridden at the application root.');
});

final productResolverProvider = Provider<ProductResolver>((ref) {
  final activeShop = ref.watch(activeShopProvider);
  if (activeShop == null) {
    throw const ShopAccessException('Select a shop before resolving a Product.');
  }
  return ResolveProductByBarcode(
    shopId: activeShop.shop.id,
    repository: ref.watch(productCatalogRepositoryProvider),
    externalProvider: ref.watch(productLookupProviderProvider),
  );
});

final productResolutionControllerProvider =
    NotifierProvider.autoDispose<ProductResolutionController, ProductResolutionState>(
      ProductResolutionController.new,
    );

final class ProductResolutionState {
  const ProductResolutionState({this.stage, this.result, this.isResolving = false});

  final ProductResolutionStage? stage;
  final ProductResolutionResult? result;
  final bool isResolving;
}

final class ProductResolutionController extends Notifier<ProductResolutionState> {
  @override
  ProductResolutionState build() => const ProductResolutionState();

  Future<void> resolve(String barcode) async {
    if (state.isResolving) return;
    final requestShopId = ref.read(activeShopProvider)?.shop.id;
    state = const ProductResolutionState(
      stage: ProductResolutionStage.checkingLocal,
      isResolving: true,
    );
    late final ProductResolutionResult result;
    try {
      result = await ref
          .read(productResolverProvider)
          .resolve(
            barcode,
            onStage: (stage) {
              if (!ref.mounted || !state.isResolving || !_isCurrentShop(requestShopId)) return;
              state = ProductResolutionState(stage: stage, isResolving: true);
            },
          );
    } on Object {
      result = ProductResolutionUnavailable(
        barcode: barcode.trim(),
        stage: ProductResolutionFailureStage.database,
      );
    }
    if (!ref.mounted) return;
    if (!_isCurrentShop(requestShopId)) {
      state = const ProductResolutionState();
      return;
    }
    state = ProductResolutionState(result: result);
  }

  void reset() => state = const ProductResolutionState();

  bool _isCurrentShop(String? requestShopId) {
    if (requestShopId == null) return true;
    return ref.read(activeShopProvider)?.shop.id == requestShopId;
  }
}
