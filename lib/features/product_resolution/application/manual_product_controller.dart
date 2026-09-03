import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import 'create_manual_product_for_barcode.dart';
import 'product_catalog_repository.dart';
import 'product_resolution_controller.dart';

final manualProductCreatorProvider = Provider<CreateManualProductForBarcode>((ref) {
  final activeShop = ref.watch(activeShopProvider);
  if (activeShop == null) {
    throw const ShopAccessException('Select a shop before creating a Product.');
  }
  return CreateManualProductForBarcode(
    shopId: activeShop.shop.id,
    repository: ref.watch(productCatalogRepositoryProvider),
  );
});

final manualProductControllerProvider =
    NotifierProvider.autoDispose<ManualProductController, ManualProductState>(
      ManualProductController.new,
    );

final class ManualProductState {
  const ManualProductState({this.isSaving = false, this.error});

  final bool isSaving;
  final String? error;
}

final class ManualProductController extends Notifier<ManualProductState> {
  @override
  ManualProductState build() => const ManualProductState();

  Future<Product?> save({required String barcode, required String name, String? brand}) async {
    if (state.isSaving) return null;
    final requestShopId = ref.read(activeShopProvider)?.shop.id;
    state = const ManualProductState(isSaving: true);
    try {
      final product = await ref
          .read(manualProductCreatorProvider)
          .call(barcode: barcode, name: name, brand: brand);
      if (!ref.mounted) return null;
      if (!_isCurrentShop(requestShopId)) {
        state = const ManualProductState(
          error: 'The active shop changed while saving. Reopen Scan Product and try again.',
        );
        return null;
      }
      state = const ManualProductState();
      return product;
    } on BarcodeValidationException catch (error) {
      if (ref.mounted) state = ManualProductState(error: error.message);
    } on ManualProductValidationException catch (error) {
      if (ref.mounted) state = ManualProductState(error: error.message);
    } on ProductCatalogException {
      if (ref.mounted) {
        state = const ManualProductState(
          error: 'The product could not be saved. Check your connection and try again.',
        );
      }
    } on Object {
      if (ref.mounted) {
        state = const ManualProductState(
          error: 'The product could not be saved right now. Nothing was saved.',
        );
      }
    }
    return null;
  }

  bool _isCurrentShop(String? requestShopId) {
    if (requestShopId == null) return true;
    return ref.read(activeShopProvider)?.shop.id == requestShopId;
  }
}
