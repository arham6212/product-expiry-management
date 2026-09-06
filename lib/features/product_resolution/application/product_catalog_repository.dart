import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';

final class ExternalProductDraft {
  const ExternalProductDraft({
    required this.name,
    required this.sourceReference,
    this.brand,
    this.imageUrl,
  });

  final String name;
  final String? brand;
  final Uri? imageUrl;
  final String sourceReference;
}

final class ManualProductDraft {
  const ManualProductDraft({required this.name, this.brand});

  final String name;
  final String? brand;

  ManualProductDraft normalized() {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw const ProductCatalogException('Product name is required.');
    }
    if (normalizedName.length > 240) {
      throw const ProductCatalogException('Product name must be 240 characters or fewer.');
    }
    final normalizedBrand = brand?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedBrand != null && normalizedBrand.length > 240) {
      throw const ProductCatalogException('Brand must be 240 characters or fewer.');
    }
    return ManualProductDraft(
      name: normalizedName,
      brand: normalizedBrand == null || normalizedBrand.isEmpty ? null : normalizedBrand,
    );
  }
}

final class ProductCatalogSaveResult {
  const ProductCatalogSaveResult({required this.product, required this.wasCreated});

  final Product product;
  final bool wasCreated;
}

final class CatalogProductSuggestion {
  const CatalogProductSuggestion({
    required this.id,
    required this.name,
    this.brand,
    this.imageUrl,
    this.productFamily,
    this.variantName,
    this.productType,
    this.packCount,
    this.unitQuantity,
    this.unitQuantityUnit,
    this.totalQuantity,
    this.totalQuantityUnit,
    this.packagingDisplay,
    this.category,
    this.subcategory,
    this.countryOfOrigin,
    this.manufacturer,
  });

  final String id;
  final String name;
  final String? brand;
  final Uri? imageUrl;
  final String? productFamily;
  final String? variantName;
  final String? productType;
  final int? packCount;
  final num? unitQuantity;
  final String? unitQuantityUnit;
  final num? totalQuantity;
  final String? totalQuantityUnit;
  final String? packagingDisplay;
  final String? category;
  final String? subcategory;
  final String? countryOfOrigin;
  final String? manufacturer;
}

final class ProductCatalogException implements Exception {
  const ProductCatalogException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ProductCatalogException: $message';
}

abstract interface class ProductCatalogRepository {
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode});

  /// Atomically returns an existing barcode owner or creates Product plus
  /// ProductBarcode. The persistence implementation owns race protection.
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  });

  /// Atomically returns an existing barcode owner or creates a manually
  /// entered Product plus ProductBarcode. The persistence implementation owns
  /// race protection.
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  });

  /// Creates one shop-owned manual Product without creating or guessing a
  /// ProductBarcode or platform-wide catalog identity.
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  });
}

/// Optional global-catalog capability. Keeping it separate preserves adapters
/// that intentionally implement only the shop-owned Product boundary.
abstract interface class GlobalCatalogProductRepository {
  Future<CatalogProductSuggestion?> findGlobalByBarcode({required NormalizedBarcode barcode});

  /// Creates or attaches the shop-owned Product only after user confirmation.
  Future<ProductCatalogSaveResult> saveCatalogProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
    required CatalogProductSuggestion suggestion,
  });
}

String normalizedProductShopId(String shopId) {
  final normalized = shopId.trim();
  if (normalized.isEmpty) {
    throw const ProductCatalogException('Select a shop before creating a Product.');
  }
  return normalized;
}
