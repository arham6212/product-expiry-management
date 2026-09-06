import 'dart:typed_data';

enum ProductImageSource { camera, gallery }

enum ProductImageStage { idle, selecting, processing, ready, uploading, success, error }

enum ProductImageFailureKind {
  permissionDenied,
  invalidType,
  tooLarge,
  offline,
  upload,
  verification,
}

final class RawProductImage {
  const RawProductImage({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

final class ProcessedProductImage {
  const ProcessedProductImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

final class ProductImageContribution {
  const ProductImageContribution({
    required this.id,
    required this.status,
    required this.deliveryUrl,
  });
  final String id;
  final String status;
  final Uri deliveryUrl;
}

final class ProductImageException implements Exception {
  const ProductImageException(this.kind, this.message, {this.cause});
  final ProductImageFailureKind kind;
  final String message;
  final Object? cause;
}

abstract interface class ProductImagePicker {
  Future<RawProductImage?> pick(ProductImageSource source);
}

abstract interface class ProductImageProcessor {
  Future<ProcessedProductImage> process(RawProductImage image);
}

abstract interface class ProductImageContributionRepository {
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  });
}

final class ProductImageTarget {
  const ProductImageTarget({required this.shopId, required this.productId});
  final String shopId;
  final String productId;

  @override
  bool operator ==(Object other) =>
      other is ProductImageTarget && other.shopId == shopId && other.productId == productId;
  @override
  int get hashCode => Object.hash(shopId, productId);
}
