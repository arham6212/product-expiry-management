import '../application/product_image_contribution.dart';

final class UnavailableProductImageRepository implements ProductImageContributionRepository {
  const UnavailableProductImageRepository();
  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) {
    throw const ProductImageException(
      ProductImageFailureKind.offline,
      'Photo upload is unavailable in this build. The product can still be saved.',
    );
  }
}
