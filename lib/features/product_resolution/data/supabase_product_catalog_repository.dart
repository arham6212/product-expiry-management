import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import '../application/product_catalog_repository.dart';

final class SupabaseProductCatalogRepository implements ProductCatalogRepository {
  const SupabaseProductCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Product?> findByBarcode({
    required String shopId,
    required NormalizedBarcode barcode,
  }) async {
    try {
      final row = await _client
          .from('product_barcodes')
          .select(
            'products!inner('
            'id,shop_id,name,brand,image_url,source,source_reference,catalog_product_id,'
            'created_at,updated_at'
            ')',
          )
          .eq('shop_id', shopId)
          .eq('barcode', barcode.value)
          .maybeSingle();
      if (row == null) return null;
      final product = _mapProduct(_requiredMap(row, 'products'));
      if (product.shopId != shopId) {
        throw const FormatException('Resolved Product belongs to another shop.');
      }
      return product;
    } on PostgrestException catch (error) {
      throw ProductCatalogException('Product lookup failed.', cause: error);
    } on FormatException catch (error) {
      throw ProductCatalogException('Product lookup returned invalid data.', cause: error);
    }
  }

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) async {
    return _saveProduct(
      rpcName: 'create_product_for_barcode',
      shopId: shopId,
      barcode: barcode,
      params: {
        'product_name': product.name,
        'product_brand': product.brand,
        'product_image_url': product.imageUrl?.toString(),
        'product_source_reference': product.sourceReference,
      },
    );
  }

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) {
    return _saveProduct(
      rpcName: 'create_manual_product_for_barcode',
      shopId: shopId,
      barcode: barcode,
      params: {'product_name': product.name, 'product_brand': product.brand},
    );
  }

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) async {
    final normalizedShopId = normalizedProductShopId(shopId);
    final normalizedProduct = product.normalized();
    try {
      final row = await _client
          .from('products')
          .insert({
            'shop_id': normalizedShopId,
            'name': normalizedProduct.name,
            'brand': normalizedProduct.brand,
            'source': 'local_manual',
          })
          .select('id,shop_id,name,brand,image_url,source,source_reference,created_at,updated_at')
          .single();
      final createdProduct = _mapProduct(row);
      if (createdProduct.shopId != normalizedShopId ||
          createdProduct.name != normalizedProduct.name ||
          createdProduct.brand != normalizedProduct.brand ||
          createdProduct.source != ProductSource.localManual ||
          createdProduct.sourceReference != null ||
          createdProduct.catalogProductId != null ||
          createdProduct.imageUrl != null) {
        throw const FormatException('Created Product does not match the request.');
      }
      return createdProduct;
    } on PostgrestException catch (error) {
      throw ProductCatalogException('Product could not be created.', cause: error);
    } on FormatException catch (error) {
      throw ProductCatalogException('Product creation returned invalid data.', cause: error);
    }
  }

  Future<ProductCatalogSaveResult> _saveProduct({
    required String rpcName,
    required String shopId,
    required NormalizedBarcode barcode,
    required Map<String, Object?> params,
  }) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        rpcName,
        params: {
          'target_shop_id': shopId,
          'normalized_barcode': barcode.value,
          'barcode_format': _databaseFormat(barcode.format),
          ...params,
        },
      );
      if (rows.length != 1 || rows.single is! Map<String, dynamic>) {
        throw const FormatException('Expected one saved product.');
      }
      final row = rows.single! as Map<String, dynamic>;
      final wasCreated = row['was_created'];
      if (wasCreated is! bool) throw const FormatException('Missing save outcome.');
      final product = _mapProduct(row);
      if (product.shopId != shopId) {
        throw const FormatException('Saved Product belongs to another shop.');
      }
      return ProductCatalogSaveResult(product: product, wasCreated: wasCreated);
    } on PostgrestException catch (error) {
      throw ProductCatalogException('Product could not be saved.', cause: error);
    } on FormatException catch (error) {
      throw ProductCatalogException('Product save returned invalid data.', cause: error);
    }
  }
}

Product _mapProduct(Map<String, dynamic> row) {
  final imageValue = row['image_url'];
  final imageUrl = imageValue is String && imageValue.isNotEmpty ? Uri.parse(imageValue) : null;
  return Product(
    id: _requiredString(row, 'id'),
    shopId: _requiredString(row, 'shop_id'),
    name: _requiredString(row, 'name'),
    brand: _optionalString(row, 'brand'),
    imageUrl: imageUrl,
    source: switch (_requiredString(row, 'source')) {
      'local_manual' => ProductSource.localManual,
      'open_food_facts' => ProductSource.openFoodFacts,
      _ => throw const FormatException('Unknown product source.'),
    },
    sourceReference: _optionalString(row, 'source_reference'),
    catalogProductId: _optionalString(row, 'catalog_product_id'),
    createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
    updatedAt: DateTime.parse(_requiredString(row, 'updated_at')).toUtc(),
  );
}

String _databaseFormat(BarcodeFormat format) {
  return switch (format) {
    BarcodeFormat.ean8 => 'ean8',
    BarcodeFormat.upcA => 'upc_a',
    BarcodeFormat.ean13 => 'ean13',
    BarcodeFormat.gtin14 => 'gtin14',
    _ => 'unknown',
  };
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! Map<String, dynamic>) throw FormatException('Missing $key.');
  return value;
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key.');
  return value;
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}
