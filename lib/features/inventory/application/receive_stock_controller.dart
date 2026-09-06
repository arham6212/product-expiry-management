import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import '../../product_resolution/application/product_catalog_repository.dart';
import '../../product_resolution/application/product_resolution_controller.dart';
import 'expiry_dashboard_controller.dart';
import 'inventory_catalog_controller.dart';
import 'inventory_repository_provider.dart';
import 'receive_stock.dart';

export 'inventory_repository_provider.dart';

final receivingProductMetadataProvider = FutureProvider.autoDispose
    .family<CatalogProductSuggestion?, Product>((ref, product) async {
      if (product.barcode == null || product.packagingDisplay != null) return null;
      final repository = ref.read(productCatalogRepositoryProvider);
      if (repository is! GlobalCatalogProductRepository) return null;
      try {
        final metadata = await (repository as GlobalCatalogProductRepository).findGlobalByBarcode(
          barcode: NormalizedBarcode.parse(product.barcode!),
        );
        if (product.catalogProductId != null && metadata?.id != product.catalogProductId) {
          return null;
        }
        return metadata;
      } on Object {
        return null; // Missing optional metadata never blocks stock entry.
      }
    });

final receiveStockProvider = Provider<ReceiveStock>((ref) {
  throw StateError('receiveStockProvider must be overridden at the application root.');
});

final receiveStockControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReceiveStockController, ReceiveStockViewState, ReceiveStockRouteArgs>(
      ReceiveStockController.new,
      retry: (retryCount, error) => null,
    );

final class ReceiveStockRouteArgs {
  const ReceiveStockRouteArgs({required this.shopId, this.initialProduct});

  final String shopId;
  final Product? initialProduct;

  // Route identity deliberately isolates simultaneous receipts for the same product.
}

final class ReceiveStockViewState {
  const ReceiveStockViewState({
    required this.products,
    this.selectedProductId,
    this.isSubmitting = false,
    this.saveError,
    this.success,
    this.hasIdempotencyConflict = false,
    this.retryIdempotencyKey,
  });

  final List<Product> products;
  final String? selectedProductId;
  final bool isSubmitting;
  final String? saveError;
  final ReceiveStockSuccess? success;
  final bool hasIdempotencyConflict;
  final String? retryIdempotencyKey;

  ReceiveStockViewState copyWith({
    List<Product>? products,
    String? selectedProductId,
    bool clearSelectedProduct = false,
    bool? isSubmitting,
    String? saveError,
    bool clearSaveError = false,
    ReceiveStockSuccess? success,
    bool clearSuccess = false,
    bool? hasIdempotencyConflict,
    String? retryIdempotencyKey,
    bool clearRetryIdempotencyKey = false,
  }) {
    return ReceiveStockViewState(
      products: products ?? this.products,
      selectedProductId: clearSelectedProduct ? null : selectedProductId ?? this.selectedProductId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      saveError: clearSaveError ? null : saveError ?? this.saveError,
      success: clearSuccess ? null : success ?? this.success,
      hasIdempotencyConflict: hasIdempotencyConflict ?? this.hasIdempotencyConflict,
      retryIdempotencyKey: clearRetryIdempotencyKey
          ? null
          : retryIdempotencyKey ?? this.retryIdempotencyKey,
    );
  }
}

final class ReceiveStockController extends AsyncNotifier<ReceiveStockViewState> {
  ReceiveStockController(this.args);

  final ReceiveStockRouteArgs args;

  @override
  Future<ReceiveStockViewState> build() async {
    final initialProduct = args.initialProduct;
    if (initialProduct != null && initialProduct.shopId == args.shopId) {
      return ReceiveStockViewState(
        products: [initialProduct],
        selectedProductId: initialProduct.id,
      );
    }
    final products = await ref.watch(inventoryRepositoryProvider).listProducts(shopId: args.shopId);
    return ReceiveStockViewState(products: products);
  }

  void retryProductLoad() => ref.invalidateSelf();

  void selectProduct(String? productId) {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        selectedProductId: productId,
        clearSelectedProduct: productId == null,
        clearRetryIdempotencyKey: true,
        clearSaveError: true,
        hasIdempotencyConflict: false,
      ),
    );
  }

  void selectCreatedProduct(Product product) {
    if (product.shopId != args.shopId) return;
    final current = state.requireValue;
    final products = [
      product,
      ...current.products.where((candidate) => candidate.id != product.id),
    ];
    state = AsyncData(
      current.copyWith(
        products: products,
        selectedProductId: product.id,
        clearRetryIdempotencyKey: true,
        clearSaveError: true,
        hasIdempotencyConflict: false,
      ),
    );
  }

  void draftChanged() {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        clearRetryIdempotencyKey: true,
        clearSaveError: true,
        hasIdempotencyConflict: false,
      ),
    );
  }

  Future<void> submit(ReceiveStockInput input) async {
    final current = state.requireValue;
    if (current.isSubmitting) return;
    state = AsyncData(current.copyWith(isSubmitting: true, clearSaveError: true));

    final result = await ref.read(receiveStockProvider)(
      ReceiveStockInput(
        shopId: args.shopId,
        productId: input.productId,
        quantity: input.quantity,
        sellingPriceMinor: input.sellingPriceMinor,
        expiryDate: input.expiryDate,
        lotNumber: input.lotNumber,
      ),
      retryIdempotencyKey: current.retryIdempotencyKey,
    );
    if (!ref.mounted) return;

    if (result is ReceiveStockSuccess) {
      ref.read(expiryDashboardActionsProvider).invalidateCurrent();
      ref.read(inventoryCatalogActionsProvider).invalidateCurrent();
    }

    state = AsyncData(
      current.copyWith(
        isSubmitting: false,
        retryIdempotencyKey: result.idempotencyKey,
        clearRetryIdempotencyKey: result.idempotencyKey == null,
        hasIdempotencyConflict: result is ReceiveStockIdempotencyConflict,
        success: result is ReceiveStockSuccess ? result : null,
        saveError: _messageFor(result),
        clearSaveError: result is ReceiveStockSuccess,
      ),
    );
  }

  void receiveAnother() {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        selectedProductId: current.selectedProductId,
        clearRetryIdempotencyKey: true,
        clearSaveError: true,
        clearSuccess: true,
        hasIdempotencyConflict: false,
      ),
    );
  }

  void startNewRequest() {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        clearRetryIdempotencyKey: true,
        clearSaveError: true,
        hasIdempotencyConflict: false,
      ),
    );
  }
}

String? _messageFor(ReceiveStockResult result) {
  return switch (result) {
    ReceiveStockSuccess() => null,
    ReceiveStockInvalidInput(:final message) => message,
    ReceiveStockAuthorizationFailure() =>
      'You no longer have access to receive stock for this shop.',
    ReceiveStockProductUnavailable() => 'That Product is no longer available in the selected shop.',
    ReceiveStockIdempotencyConflict() =>
      'This request key was already used for different stock details.',
    ReceiveStockBackendUnavailable() =>
      'Stock may not have been saved. Your entries are still here; retry safely.',
  };
}
