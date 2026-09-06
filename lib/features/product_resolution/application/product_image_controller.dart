import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'product_image_contribution.dart';
import '../../inventory/application/inventory_catalog_controller.dart';

final productImagePickerProvider = Provider<ProductImagePicker>(
  (ref) => throw StateError('productImagePickerProvider must be overridden.'),
);
final productImageProcessorProvider = Provider<ProductImageProcessor>(
  (ref) => throw StateError('productImageProcessorProvider must be overridden.'),
);
final productImageContributionRepositoryProvider = Provider<ProductImageContributionRepository>(
  (ref) => throw StateError('productImageContributionRepositoryProvider must be overridden.'),
);

final productImageControllerProvider = NotifierProvider.autoDispose
    .family<ProductImageController, ProductImageState, ProductImageTarget>(
      ProductImageController.new,
    );

final class ProductImageState {
  const ProductImageState({
    this.stage = ProductImageStage.idle,
    this.selected,
    this.contribution,
    this.failureKind,
    this.message,
  });
  final ProductImageStage stage;
  final ProcessedProductImage? selected;
  final ProductImageContribution? contribution;
  final ProductImageFailureKind? failureKind;
  final String? message;
  bool get isBusy =>
      stage == ProductImageStage.selecting ||
      stage == ProductImageStage.processing ||
      stage == ProductImageStage.uploading;
}

final class ProductImageController extends Notifier<ProductImageState> {
  ProductImageController(this._target);

  final ProductImageTarget _target;
  int _operation = 0;

  @override
  ProductImageState build() {
    ref.onDispose(() => _operation++);
    return const ProductImageState();
  }

  Future<void> select(ProductImageSource source) async {
    if (state.isBusy) return;
    final operation = ++_operation;
    final previousState = state;
    final previous = state.selected;
    state = ProductImageState(stage: ProductImageStage.selecting, selected: previous);
    try {
      final picked = await ref.read(productImagePickerProvider).pick(source);
      if (!_current(operation)) return;
      if (picked == null) {
        state = previousState;
        return;
      }
      state = ProductImageState(stage: ProductImageStage.processing, selected: previous);
      final processed = await ref.read(productImageProcessorProvider).process(picked);
      if (!_current(operation)) return;
      state = ProductImageState(stage: ProductImageStage.ready, selected: processed);
    } on ProductImageException catch (error) {
      if (_current(operation)) {
        state = ProductImageState(
          stage: ProductImageStage.error,
          selected: previous,
          contribution: previousState.contribution,
          failureKind: error.kind,
          message: error.message,
        );
      }
    } on Object {
      if (_current(operation)) {
        state = ProductImageState(
          stage: ProductImageStage.error,
          selected: previous,
          contribution: previousState.contribution,
          failureKind: ProductImageFailureKind.upload,
          message: 'The photo could not be prepared. Try another image.',
        );
      }
    }
  }

  Future<void> selectAndUpload(ProductImageSource source) async {
    final previous = state.selected;
    await select(source);
    if (!ref.mounted ||
        state.stage != ProductImageStage.ready ||
        identical(previous, state.selected)) {
      return;
    }
    await upload();
  }

  Future<ProductImageContribution?> upload() async {
    final selected = state.selected;
    if (selected == null || state.isBusy || state.contribution != null) return null;
    final keepAlive = ref.keepAlive();
    final operation = ++_operation;
    state = ProductImageState(stage: ProductImageStage.uploading, selected: selected);
    try {
      final result = await ref
          .read(productImageContributionRepositoryProvider)
          .upload(shopId: _target.shopId, productId: _target.productId, image: selected);
      if (!_current(operation)) return null;
      ref.read(savedShopPhotosProvider.notifier).save(_target, result.deliveryUrl);
      ref.read(inventoryCatalogActionsProvider).invalidateShop(_target.shopId);
      state = ProductImageState(
        stage: ProductImageStage.success,
        selected: selected,
        contribution: result,
        message: 'Saved to your shop',
      );
      return result;
    } on ProductImageException catch (error) {
      if (_current(operation)) {
        state = ProductImageState(
          stage: ProductImageStage.error,
          selected: selected,
          failureKind: error.kind,
          message: error.message,
        );
      }
    } on Object {
      if (_current(operation)) {
        state = ProductImageState(
          stage: ProductImageStage.error,
          selected: selected,
          failureKind: ProductImageFailureKind.upload,
          message: 'The photo could not be uploaded. Check your connection and retry.',
        );
      }
    } finally {
      keepAlive.close();
    }
    return null;
  }

  void removeSelection() {
    if (state.isBusy || state.contribution != null) return;
    _operation++;
    state = const ProductImageState();
  }

  bool _current(int operation) => ref.mounted && operation == _operation;
}

// URLs only: route-local previews are released when the image controller disposes.
// Keys include shop identity so a shared catalog product never shares an override.
final savedShopPhotosProvider = NotifierProvider<SavedShopPhotos, Map<ProductImageTarget, Uri>>(
  SavedShopPhotos.new,
);

final class SavedShopPhotos extends Notifier<Map<ProductImageTarget, Uri>> {
  @override
  Map<ProductImageTarget, Uri> build() => {};
  void save(ProductImageTarget target, Uri url) => state = {...state, target: url};
}
