import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/app_components.dart';
import '../../inventory/application/inventory_catalog_controller.dart';
import '../../shops/application/shop_session_controller.dart';
import '../application/product_image_contribution.dart';
import '../application/product_image_controller.dart';

/// Uses the saved shop override immediately, even if a route holds older Product data.
class ShopProductImage extends ConsumerWidget {
  const ShopProductImage({
    required this.productId,
    this.shopId,
    this.imageUrl,
    this.size = 48,
    super.key,
  });
  final String productId;
  final String? shopId;
  final Uri? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = shopId ?? ref.watch(activeShopProvider)?.shop.id;
    final override = owner == null
        ? null
        : ref.watch(
            savedShopPhotosProvider.select(
              (photos) => photos[ProductImageTarget(shopId: owner, productId: productId)],
            ),
          );
    final fallback =
        imageUrl ??
        ref.watch(inventoryCatalogProvider).asData?.value.productById(productId)?.imageUrl;
    return AppProductImage(imageUrl: override ?? fallback, size: size);
  }
}
