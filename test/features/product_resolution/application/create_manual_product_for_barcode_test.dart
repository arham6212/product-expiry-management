import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/create_manual_product_for_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';

void main() {
  const barcode = '5000112519945';
  final now = DateTime.utc(2026, 8, 31);
  late InMemoryProductCatalogRepository repository;
  late CreateManualProductForBarcode createManual;
  var nextId = 0;

  setUp(() {
    nextId = 0;
    repository = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-${nextId++}',
      clock: () => now,
    );
    createManual = CreateManualProductForBarcode(shopId: 'shop-1', repository: repository);
  });

  test('normalizes and saves a manual Product plus barcode', () async {
    final product = await createManual(
      barcode: '  $barcode  ',
      name: '  Sparkling   Water ',
      brand: ' Local   Brand ',
    );

    expect(product.name, 'Sparkling Water');
    expect(product.brand, 'Local Brand');
    expect(product.source, ProductSource.localManual);
    expect(product.sourceReference, isNull);
    expect(repository.products, hasLength(1));
    expect(repository.barcodes.single.value, barcode);
  });

  test('blank name is rejected without persistence', () async {
    await expectLater(
      createManual(barcode: barcode, name: '   '),
      throwsA(isA<ManualProductValidationException>()),
    );

    expect(repository.products, isEmpty);
    expect(repository.barcodes, isEmpty);
  });

  test('manual retry returns an existing external winner without duplicates', () async {
    final external = await repository.saveExternalProduct(
      shopId: 'shop-1',
      barcode: NormalizedBarcode.parse(barcode),
      product: const ExternalProductDraft(name: 'External winner', sourceReference: barcode),
    );

    final result = await createManual(barcode: barcode, name: 'Manual retry');

    expect(result, same(external.product));
    expect(result.source, ProductSource.openFoodFacts);
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });
}
