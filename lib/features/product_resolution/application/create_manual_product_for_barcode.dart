import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import 'product_catalog_repository.dart';

final class ManualProductValidationException implements Exception {
  const ManualProductValidationException(this.message);

  final String message;

  @override
  String toString() => 'ManualProductValidationException: $message';
}

final class CreateManualProductForBarcode {
  const CreateManualProductForBarcode({required this.shopId, required this.repository});

  final String shopId;
  final ProductCatalogRepository repository;

  Future<Product> call({
    required String barcode,
    required String name,
    String? brand,
    CatalogProductSuggestion? suggestion,
  }) async {
    final normalizedBarcode = NormalizedBarcode.parse(barcode);
    final normalizedName = _normalizeRequired(name, field: 'Product name', maximumLength: 240);
    final normalizedBrand = _normalizeOptional(brand, field: 'Brand', maximumLength: 240);
    final draft = ManualProductDraft(name: normalizedName, brand: normalizedBrand);
    final result = suggestion != null && repository is GlobalCatalogProductRepository
        ? await (repository as GlobalCatalogProductRepository).saveCatalogProduct(
            shopId: shopId,
            barcode: normalizedBarcode,
            product: draft,
            suggestion: suggestion,
          )
        : await repository.saveManualProduct(
            shopId: shopId,
            barcode: normalizedBarcode,
            product: draft,
          );
    final product = result.product.catalogProductId != null
        ? result.product
        : await repository.findByBarcode(shopId: shopId, barcode: normalizedBarcode) ??
              result.product;
    return product.withScanMetadata(
      barcode: normalizedBarcode.value,
      packagingDisplay: product.catalogProductId == suggestion?.id
          ? suggestion?.packagingDisplay
          : null,
    );
  }
}

String _normalizeRequired(String value, {required String field, required int maximumLength}) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    throw ManualProductValidationException('$field is required.');
  }
  if (normalized.length > maximumLength) {
    throw ManualProductValidationException('$field must be $maximumLength characters or fewer.');
  }
  return normalized;
}

String? _normalizeOptional(String? value, {required String field, required int maximumLength}) {
  if (value == null) return null;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return null;
  if (normalized.length > maximumLength) {
    throw ManualProductValidationException('$field must be $maximumLength characters or fewer.');
  }
  return normalized;
}
