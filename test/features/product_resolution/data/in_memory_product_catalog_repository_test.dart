import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';

void main() {
  final now = DateTime.utc(2026, 8, 29);
  var nextId = 0;
  late InMemoryProductCatalogRepository repository;

  setUp(() {
    nextId = 0;
    repository = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-${nextId++}',
      clock: () => now,
    );
  });

  test('persists a Product and ProductBarcode for one shop', () async {
    final result = await repository.saveExternalProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse('5000112519945'),
      product: const ExternalProductDraft(
        name: 'Coca Cola',
        brand: 'Coca-Cola',
        sourceReference: '5000112519945',
      ),
    );

    expect(result.wasCreated, isTrue);
    expect(result.product.source, ProductSource.openFoodFacts);
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
    expect(repository.barcodes.single.productId, result.product.id);
    expect(
      await repository.findByBarcode(
        shopId: 'shop-1',
        barcode: NormalizedBarcode.parse('5000112519945'),
      ),
      same(result.product),
    );
  });

  test('same barcode is isolated between shops', () async {
    for (final shopId in ['shop-1', 'shop-2']) {
      await repository.saveExternalProduct(
        shopId: shopId,
        barcode: NormalizedBarcode.parse('5000112519945'),
        product: ExternalProductDraft(name: 'Product $shopId', sourceReference: shopId),
      );
    }

    expect(repository.products, hasLength(2));
    expect(repository.barcodes, hasLength(2));
  });

  test('duplicate save returns the existing product without duplicates', () async {
    final first = await repository.saveExternalProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse('5000112519945'),
      product: const ExternalProductDraft(name: 'First', sourceReference: 'first'),
    );
    final duplicate = await repository.saveExternalProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse('5000112519945'),
      product: const ExternalProductDraft(name: 'Second', sourceReference: 'second'),
    );

    expect(duplicate.wasCreated, isFalse);
    expect(duplicate.product, same(first.product));
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });

  test('manual save is shop-scoped and returns an existing barcode winner', () async {
    final first = await repository.saveManualProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse('5000112519945'),
      product: const ManualProductDraft(name: 'Manual product', brand: 'Brand'),
    );
    final duplicate = await repository.saveExternalProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse('5000112519945'),
      product: const ExternalProductDraft(name: 'External product', sourceReference: 'source'),
    );

    expect(first.product.source, ProductSource.localManual);
    expect(duplicate.wasCreated, isFalse);
    expect(duplicate.product, same(first.product));
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });

  test('creates a normalized manual Product without a barcode', () async {
    final product = await repository.createManualProductWithoutBarcode(
      shopId: ' shop-1 ',
      product: const ManualProductDraft(name: '  Fresh   milk  ', brand: ' Local   Dairy '),
    );

    expect(product.shopId, 'shop-1');
    expect(product.name, 'Fresh milk');
    expect(product.brand, 'Local Dairy');
    expect(product.source, ProductSource.localManual);
    expect(product.sourceReference, isNull);
    expect(product.catalogProductId, isNull);
    expect(product.imageUrl, isNull);
    expect(product.createdAt, now);
    expect(product.updatedAt, now);
    expect(repository.products, [same(product)]);
    expect(repository.barcodes, isEmpty);
  });

  test('does not deduplicate barcode-less Products by name', () async {
    for (var index = 0; index < 2; index++) {
      await repository.createManualProductWithoutBarcode(
        shopId: 'shop-1',
        product: const ManualProductDraft(name: 'Fresh milk'),
      );
    }

    expect(repository.products, hasLength(2));
    expect(repository.barcodes, isEmpty);
  });

  test('rejects invalid barcode-less Product input before persistence', () async {
    Future<void> expectRejected({
      required String shopId,
      required ManualProductDraft product,
    }) async {
      await expectLater(
        repository.createManualProductWithoutBarcode(shopId: shopId, product: product),
        throwsA(isA<ProductCatalogException>()),
      );
      expect(repository.products, isEmpty);
      expect(repository.barcodes, isEmpty);
    }

    await expectRejected(
      shopId: '   ',
      product: const ManualProductDraft(name: 'Milk'),
    );
    await expectRejected(
      shopId: 'shop-1',
      product: const ManualProductDraft(name: '  '),
    );
    await expectRejected(
      shopId: 'shop-1',
      product: ManualProductDraft(name: List.filled(241, 'x').join()),
    );
    await expectRejected(
      shopId: 'shop-1',
      product: ManualProductDraft(name: 'Milk', brand: List.filled(241, 'x').join()),
    );
  });
}
