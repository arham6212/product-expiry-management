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

String normalizedProductShopId(String shopId) {
  final normalized = shopId.trim();
  if (normalized.isEmpty) {
    throw const ProductCatalogException('Select a shop before creating a Product.');
  }
  return normalized;
}
