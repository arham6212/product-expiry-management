import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/normalized_barcode.dart';
import '../application/product_catalog_repository.dart';

typedef ProductCatalogIdGenerator = String Function(String prefix);
typedef ProductCatalogClock = DateTime Function();

final class InMemoryProductCatalogRepository implements ProductCatalogRepository {
  InMemoryProductCatalogRepository({
    Iterable<Product> products = const [],
    Iterable<ProductBarcode> barcodes = const [],
    ProductCatalogIdGenerator? idGenerator,
    ProductCatalogClock? clock,
  }) : _products = {for (final product in products) product.id: product},
       _barcodes = {for (final barcode in barcodes) _key(barcode.shopId, barcode.value): barcode},
       _idGenerator = idGenerator ?? _defaultIdGenerator,
       _clock = clock ?? _defaultClock;

  final Map<String, Product> _products;
  final Map<String, ProductBarcode> _barcodes;
  final ProductCatalogIdGenerator _idGenerator;
  final ProductCatalogClock _clock;

  List<Product> get products => List.unmodifiable(_products.values);
  List<ProductBarcode> get barcodes => List.unmodifiable(_barcodes.values);

  @override
  Future<Product?> findByBarcode({
    required String shopId,
    required NormalizedBarcode barcode,
  }) async {
    final mapping = _barcodes[_key(shopId, barcode.value)];
    return mapping == null ? null : _products[mapping.productId];
  }

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) async {
    return _saveProduct(
      shopId: shopId,
      barcode: barcode,
      name: product.name,
      brand: product.brand,
      imageUrl: product.imageUrl,
      source: ProductSource.openFoodFacts,
      sourceReference: product.sourceReference,
    );
  }

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) async {
    return _saveProduct(
      shopId: shopId,
      barcode: barcode,
      name: product.name,
      brand: product.brand,
      source: ProductSource.localManual,
    );
  }

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) async {
    final normalizedShopId = normalizedProductShopId(shopId);
    final normalizedProduct = product.normalized();
    final now = _clock().toUtc();
    final createdProduct = Product(
      id: _idGenerator('product'),
      shopId: normalizedShopId,
      name: normalizedProduct.name,
      brand: normalizedProduct.brand,
      source: ProductSource.localManual,
      createdAt: now,
      updatedAt: now,
    );
    _products[createdProduct.id] = createdProduct;
    return createdProduct;
  }

  ProductCatalogSaveResult _saveProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required String name,
    required ProductSource source,
    String? brand,
    Uri? imageUrl,
    String? sourceReference,
  }) {
    final key = _key(shopId, barcode.value);
    final existingMapping = _barcodes[key];
    if (existingMapping != null) {
      final existingProduct = _products[existingMapping.productId];
      if (existingProduct == null) {
        throw const ProductCatalogException('Barcode mapping references a missing product.');
      }
      return ProductCatalogSaveResult(product: existingProduct, wasCreated: false);
    }

    final now = _clock().toUtc();
    final createdProduct = Product(
      id: _idGenerator('product'),
      shopId: shopId,
      name: name,
      brand: brand,
      imageUrl: imageUrl,
      source: source,
      sourceReference: sourceReference,
      createdAt: now,
      updatedAt: now,
    );
    final mapping = ProductBarcode(
      id: _idGenerator('barcode'),
      shopId: shopId,
      productId: createdProduct.id,
      value: barcode.value,
      format: barcode.format,
      isPrimary: true,
      createdAt: now,
    );

    _products[createdProduct.id] = createdProduct;
    _barcodes[key] = mapping;
    return ProductCatalogSaveResult(product: createdProduct, wasCreated: true);
  }
}

String _key(String shopId, String barcode) => '$shopId:$barcode';

var _nextId = 0;
String _defaultIdGenerator(String prefix) => '$prefix-${_nextId++}';
DateTime _defaultClock() => DateTime.now().toUtc();
