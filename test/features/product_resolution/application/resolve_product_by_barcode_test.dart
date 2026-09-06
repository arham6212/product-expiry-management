import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/resolve_product_by_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';

void main() {
  const shopId = 'shop-1';
  const barcode = '123456789012';
  final now = DateTime.utc(2026, 9, 3, 10);

  test('returns local product if it exists', () async {
    final product = Product(
      id: 'product-1',
      shopId: shopId,
      name: 'Test Product',
      category: null,
      brand: null,
      imageUrl: null,
      createdAt: now,
      updatedAt: now,
    );
    final repo = InMemoryProductCatalogRepository(
      products: [product],
      barcodes: [
        ProductBarcode(
          id: 'barcode-1',
          shopId: shopId,
          productId: product.id,
          value: barcode,
          format: BarcodeFormat.ean13,
          isPrimary: true,
          createdAt: now,
        ),
      ],
      idGenerator: (prefix) => '$prefix-1',
      clock: () => now,
    );
    final resolver = ResolveProductByBarcode(shopId: shopId, repository: repo);

    final result = await resolver.resolve(barcode);
    expect(result, isA<ProductFoundLocally>());
    expect((result as ProductFoundLocally).product.id, product.id);
  });

  test('returns not found if local product missing', () async {
    final repo = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-1',
      clock: () => now,
    );
    final resolver = ResolveProductByBarcode(shopId: shopId, repository: repo);
    final result = await resolver.resolve('8690101368943');
    expect(result, isA<ProductResolutionNotFound>());
  });

  test('returns a global suggestion without creating a shop product', () async {
    const globalBarcode = '5000112519945';
    const suggestion = CatalogProductSuggestion(
      id: 'catalog-1',
      name: 'Global Cola',
      brand: 'Global Brand',
      packagingDisplay: '6 x 330ml',
    );
    final repo = InMemoryProductCatalogRepository(
      globalProducts: const [MapEntry(globalBarcode, suggestion)],
      idGenerator: (prefix) => '$prefix-1',
      clock: () => now,
    );
    final stages = <ProductResolutionStage>[];

    final result = await ResolveProductByBarcode(
      shopId: shopId,
      repository: repo,
    ).resolve(globalBarcode, onStage: stages.add);

    expect(result, isA<ProductFoundGlobally>());
    expect((result as ProductFoundGlobally).suggestion, same(suggestion));
    expect(stages, [ProductResolutionStage.checkingLocal, ProductResolutionStage.checkingGlobal]);
    expect(repo.products, isEmpty);
    expect(repo.barcodes, isEmpty);
  });

  test('returns invalid barcode for malformed barcode', () async {
    final repo = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-1',
      clock: () => now,
    );
    final resolver = ResolveProductByBarcode(shopId: shopId, repository: repo);
    final result = await resolver.resolve('abc');
    expect(result, isA<ProductResolutionInvalidBarcode>());
  });
}
