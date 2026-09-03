import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../shops/application/shop_session_controller.dart';
import 'product_catalog_repository.dart';
import 'product_resolution_controller.dart';

final barcodeLessProductControllerProvider = NotifierProvider.autoDispose
    .family<BarcodeLessProductController, BarcodeLessProductState, String>(
      BarcodeLessProductController.new,
    );

final class BarcodeLessProductState {
  const BarcodeLessProductState({this.isSaving = false, this.error});

  final bool isSaving;
  final String? error;
}

final class BarcodeLessProductController extends Notifier<BarcodeLessProductState> {
  BarcodeLessProductController(this.shopId);

  final String shopId;

  @override
  BarcodeLessProductState build() => const BarcodeLessProductState();

  Future<Product?> save({required String name, String? brand}) async {
    if (state.isSaving) return null;
    final requestShopId = ref.read(activeShopProvider)?.shop.id;
    if (requestShopId == null || requestShopId != shopId) {
      state = const BarcodeLessProductState(
        error: 'The selected shop is no longer active. Return to receiving and try again.',
      );
      return null;
    }

    state = const BarcodeLessProductState(isSaving: true);
    try {
      final product = await ref
          .read(productCatalogRepositoryProvider)
          .createManualProductWithoutBarcode(
            shopId: requestShopId,
            product: ManualProductDraft(name: name, brand: brand),
          );
      if (!ref.mounted) return null;
      if (ref.read(activeShopProvider)?.shop.id != requestShopId ||
          product.shopId != requestShopId) {
        state = const BarcodeLessProductState(
          error: 'The active shop changed while saving. Return to receiving and try again.',
        );
        return null;
      }
      state = const BarcodeLessProductState();
      return product;
    } on ProductCatalogException catch (error) {
      if (ref.mounted) {
        state = BarcodeLessProductState(error: error.message);
      }
    } on Object {
      if (ref.mounted) {
        state = const BarcodeLessProductState(
          error: 'The product could not be saved right now. Nothing was saved.',
        );
      }
    }
    return null;
  }
}
