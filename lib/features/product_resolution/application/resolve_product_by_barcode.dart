import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import 'product_catalog_repository.dart';

enum ProductResolutionStage { checkingLocal, checkingGlobal }

enum ProductResolutionFailureStage { database }

typedef ProductResolutionStageObserver = void Function(ProductResolutionStage stage);

sealed class ProductResolutionResult {
  const ProductResolutionResult({required this.barcode});

  final String barcode;
}

final class ProductFoundLocally extends ProductResolutionResult {
  const ProductFoundLocally({required super.barcode, required this.product});

  final Product product;
}

final class ProductFoundGlobally extends ProductResolutionResult {
  const ProductFoundGlobally({required super.barcode, required this.suggestion});

  final CatalogProductSuggestion suggestion;
}

final class ProductResolutionNotFound extends ProductResolutionResult {
  const ProductResolutionNotFound({required super.barcode});
}

final class ProductResolutionInvalidBarcode extends ProductResolutionResult {
  const ProductResolutionInvalidBarcode({required super.barcode, required this.message});

  final String message;
}

final class ProductResolutionUnavailable extends ProductResolutionResult {
  const ProductResolutionUnavailable({required super.barcode, required this.stage});

  final ProductResolutionFailureStage stage;
}

abstract interface class ProductResolver {
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  });
}

final class ResolveProductByBarcode implements ProductResolver {
  const ResolveProductByBarcode({
    required this.shopId,
    required ProductCatalogRepository repository,
  }) : _repository = repository;

  final String shopId;
  final ProductCatalogRepository _repository;

  @override
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  }) async {
    final NormalizedBarcode normalized;
    try {
      normalized = NormalizedBarcode.parse(barcode);
    } on BarcodeValidationException catch (error) {
      return ProductResolutionInvalidBarcode(barcode: barcode.trim(), message: error.message);
    }

    onStage?.call(ProductResolutionStage.checkingLocal);
    final Product? localProduct;
    try {
      localProduct = await _repository.findByBarcode(shopId: shopId, barcode: normalized);
    } on Object {
      return ProductResolutionUnavailable(
        barcode: normalized.value,
        stage: ProductResolutionFailureStage.database,
      );
    }

    if (localProduct != null) {
      return ProductFoundLocally(
        barcode: normalized.value,
        product: localProduct.withScanMetadata(barcode: normalized.value),
      );
    }

    final repository = _repository;
    if (repository is GlobalCatalogProductRepository) {
      onStage?.call(ProductResolutionStage.checkingGlobal);
      try {
        final suggestion = await (repository as GlobalCatalogProductRepository).findGlobalByBarcode(
          barcode: normalized,
        );
        if (suggestion != null) {
          return ProductFoundGlobally(barcode: normalized.value, suggestion: suggestion);
        }
      } on Object {
        return ProductResolutionUnavailable(
          barcode: normalized.value,
          stage: ProductResolutionFailureStage.database,
        );
      }
    }

    return ProductResolutionNotFound(barcode: normalized.value);
  }
}
