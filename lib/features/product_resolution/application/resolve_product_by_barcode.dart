import '../../../domain/entities/domain_models.dart';
import '../../../domain/ports/external_providers.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import 'product_catalog_repository.dart';

enum ProductResolutionStage { checkingLocal, lookingUpExternal, saving }

enum ProductResolutionFailureStage { database, externalProvider, persistence }

typedef ProductResolutionStageObserver = void Function(ProductResolutionStage stage);

sealed class ProductResolutionResult {
  const ProductResolutionResult({required this.barcode});

  final String barcode;
}

final class ProductFoundLocally extends ProductResolutionResult {
  const ProductFoundLocally({required super.barcode, required this.product});

  final Product product;
}

final class ProductFoundExternally extends ProductResolutionResult {
  const ProductFoundExternally({required super.barcode, required this.product});

  final Product product;
}

final class ProductResolutionNotFound extends ProductResolutionResult {
  const ProductResolutionNotFound({required super.barcode});
}

final class ProductResolutionInvalidBarcode extends ProductResolutionResult {
  const ProductResolutionInvalidBarcode({required super.barcode, required this.message});

  final String message;
}

final class ProductResolutionUnavailable extends ProductResolutionResult {
  const ProductResolutionUnavailable({
    required super.barcode,
    required this.stage,
    this.providerFailure,
  });

  final ProductResolutionFailureStage stage;
  final ProductLookupFailureKind? providerFailure;
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
    required ProductLookupProvider externalProvider,
  }) : _repository = repository,
       _externalProvider = externalProvider;

  final String shopId;
  final ProductCatalogRepository _repository;
  final ProductLookupProvider _externalProvider;

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
      return ProductFoundLocally(barcode: normalized.value, product: localProduct);
    }

    onStage?.call(ProductResolutionStage.lookingUpExternal);
    final ProductLookupResult externalResult;
    try {
      externalResult = await _externalProvider.findByBarcode(normalized.value);
    } on Object {
      return ProductResolutionUnavailable(
        barcode: normalized.value,
        stage: ProductResolutionFailureStage.externalProvider,
        providerFailure: ProductLookupFailureKind.unknown,
      );
    }

    return switch (externalResult) {
      ProductLookupNotFound() => ProductResolutionNotFound(barcode: normalized.value),
      ProductLookupUnavailable(:final kind) => ProductResolutionUnavailable(
        barcode: normalized.value,
        stage: ProductResolutionFailureStage.externalProvider,
        providerFailure: kind,
      ),
      ProductLookupFound(:final candidate) => _saveCandidate(
        normalized,
        candidate,
        onStage: onStage,
      ),
    };
  }

  Future<ProductResolutionResult> _saveCandidate(
    NormalizedBarcode barcode,
    ProductLookupCandidate candidate, {
    ProductResolutionStageObserver? onStage,
  }) async {
    if (candidate.barcode != barcode.value) {
      return ProductResolutionUnavailable(
        barcode: barcode.value,
        stage: ProductResolutionFailureStage.externalProvider,
        providerFailure: ProductLookupFailureKind.malformed,
      );
    }

    final name = _normalizeText(candidate.name);
    if (name == null) {
      return ProductResolutionNotFound(barcode: barcode.value);
    }

    onStage?.call(ProductResolutionStage.saving);
    try {
      final saved = await _repository.saveExternalProduct(
        shopId: shopId,
        barcode: barcode,
        product: ExternalProductDraft(
          name: name,
          brand: _normalizeText(candidate.brand),
          imageUrl: candidate.imageUrl,
          sourceReference: candidate.providerReference,
        ),
      );
      return ProductFoundExternally(barcode: barcode.value, product: saved.product);
    } on Object {
      return ProductResolutionUnavailable(
        barcode: barcode.value,
        stage: ProductResolutionFailureStage.persistence,
      );
    }
  }
}

String? _normalizeText(String? value) {
  if (value == null) return null;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}
