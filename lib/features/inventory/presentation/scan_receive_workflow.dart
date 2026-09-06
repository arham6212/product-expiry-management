import 'package:flutter/material.dart';

import '../../../domain/entities/domain_models.dart';
import '../../product_resolution/presentation/product_resolution_page.dart';
import 'receive_stock_page.dart';

/// Replace resolution with receiving so back returns to the original entry point.
Future<void> openScanReceiveWorkflow(
  BuildContext context, {
  required String shopId,
  required String currencyCode,
}) async {
  await Navigator.of(context).push<Product>(
    MaterialPageRoute<Product>(
      builder: (routeContext) => ProductResolutionPage(
        onResolved: (product) {
          if (product.shopId != shopId) return;
          Navigator.of(routeContext).pushReplacement<void, Product>(
            MaterialPageRoute<void>(
              builder: (_) => ReceiveStockPage(
                shopId: shopId,
                currencyCode: currencyCode,
                initialProduct: product,
              ),
            ),
          );
        },
      ),
    ),
  );
}
