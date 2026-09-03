import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/ports/external_providers.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/resolve_product_by_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';

void main() {
  const shopId = 'shop-1';
  const localBarcode = '1234567890123';
  const externalBarcode = '5000112519945';
  final now = DateTime.utc(2026, 8, 29);
  late Product localProduct;
  late InMemoryProductCatalogRepository repository;
  late _FakeProductLookupProvider provider;
  var nextId = 0;

  setUp(() {
    nextId = 0;
    localProduct = Product(
      id: 'product-local',
      shopId: shopId,
      name: 'Local Milk',
      createdAt: now,
      updatedAt: now,
    );
    final mapping = ProductBarcode(
      id: 'barcode-local',
      shopId: shopId,
      productId: localProduct.id,
      value: localBarcode,
      format: BarcodeFormat.ean13,
      createdAt: now,
    );
    repository = InMemoryProductCatalogRepository(
      products: [localProduct],
      barcodes: [mapping],
      idGenerator: (prefix) => '$prefix-${nextId++}',
      clock: () => now,
    );
    provider = _FakeProductLookupProvider(const ProductLookupNotFound());
  });

  ResolveProductByBarcode resolver({
    ProductCatalogRepository? catalog,
    ProductLookupProvider? lookup,
  }) {
    return ResolveProductByBarcode(
      shopId: shopId,
      repository: catalog ?? repository,
      externalProvider: lookup ?? provider,
    );
  }

  ProductLookupFound externalProduct({String name = 'External Cola', Uri? imageUrl}) {
    return ProductLookupFound(
      ProductLookupCandidate(
        barcode: externalBarcode,
        name: name,
        brand: 'Brand',
        imageUrl: imageUrl,
        providerReference: externalBarcode,
      ),
    );
  }

  test('existing barcode returns local Product without calling provider', () async {
    final result = await resolver().resolve(localBarcode);

    expect(result, isA<ProductFoundLocally>());
    expect((result as ProductFoundLocally).product, same(localProduct));
    expect(provider.calls, 0);
  });

  test('missing local barcode triggers external lookup and persists result', () async {
    provider.result = externalProduct(imageUrl: Uri.parse('https://images.example.test/cola.jpg'));
    final stages = <ProductResolutionStage>[];

    final result = await resolver().resolve(externalBarcode, onStage: stages.add);

    expect(result, isA<ProductFoundExternally>());
    final product = (result as ProductFoundExternally).product;
    expect(product.name, 'External Cola');
    expect(product.source, ProductSource.openFoodFacts);
    expect(product.sourceReference, externalBarcode);
    expect(repository.products, hasLength(2));
    expect(repository.barcodes, hasLength(2));
    expect(stages, [
      ProductResolutionStage.checkingLocal,
      ProductResolutionStage.lookingUpExternal,
      ProductResolutionStage.saving,
    ]);
  });

  test('second resolution uses database and skips external provider', () async {
    provider.result = externalProduct();
    await resolver().resolve(externalBarcode);
    final second = await resolver().resolve(externalBarcode);

    expect(second, isA<ProductFoundLocally>());
    expect(provider.calls, 1);
  });

  test('external not-found returns NotFound without writing', () async {
    final result = await resolver().resolve(externalBarcode);

    expect(result, isA<ProductResolutionNotFound>());
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });

  for (final failure in ProductLookupFailureKind.values) {
    test('external ${failure.name} returns controlled unavailable state', () async {
      provider.result = ProductLookupUnavailable(failure);

      final result = await resolver().resolve(externalBarcode);

      expect(result, isA<ProductResolutionUnavailable>());
      expect((result as ProductResolutionUnavailable).providerFailure, failure);
      expect(repository.products, hasLength(1));
    });
  }

  test('provider exception is contained', () async {
    final result = await resolver(lookup: _ThrowingProvider()).resolve(externalBarcode);

    expect(result, isA<ProductResolutionUnavailable>());
  });

  test('external product without image is accepted', () async {
    provider.result = externalProduct();

    final result = await resolver().resolve(externalBarcode) as ProductFoundExternally;

    expect(result.product.imageUrl, isNull);
  });

  test('external product without required name is not auto-created', () async {
    provider.result = externalProduct(name: '   ');

    final result = await resolver().resolve(externalBarcode);

    expect(result, isA<ProductResolutionNotFound>());
    expect(repository.products, hasLength(1));
  });

  test('mismatched provider barcode is treated as malformed', () async {
    provider.result = const ProductLookupFound(
      ProductLookupCandidate(
        barcode: localBarcode,
        name: 'Wrong product',
        providerReference: localBarcode,
      ),
    );

    final result = await resolver().resolve(externalBarcode) as ProductResolutionUnavailable;

    expect(result.providerFailure, ProductLookupFailureKind.malformed);
    expect(repository.products, hasLength(1));
  });

  test('blank barcode is rejected before database or provider lookup', () async {
    final countingRepository = _CountingRepository(repository);

    final result = await resolver(catalog: countingRepository).resolve('   ');

    expect(result, isA<ProductResolutionInvalidBarcode>());
    expect(countingRepository.findCalls, 0);
    expect(provider.calls, 0);
  });

  test('barcode whitespace is normalized safely', () async {
    final result = await resolver().resolve('  $localBarcode  ');

    expect(result, isA<ProductFoundLocally>());
    expect(result.barcode, localBarcode);
  });

  test('database failure returns controlled state without external lookup', () async {
    final result = await resolver(catalog: _ThrowingRepository()).resolve(externalBarcode);

    expect(result, isA<ProductResolutionUnavailable>());
    expect((result as ProductResolutionUnavailable).stage, ProductResolutionFailureStage.database);
    expect(provider.calls, 0);
  });

  test('concurrent duplicate resolutions return one persisted product', () async {
    final concurrentProvider = _BarrierProvider(externalProduct());
    final useCase = resolver(lookup: concurrentProvider);

    final results = await Future.wait([
      useCase.resolve(externalBarcode),
      useCase.resolve(externalBarcode),
    ]);

    expect(results, everyElement(isA<ProductFoundExternally>()));
    final productIds = results
        .map((result) => (result as ProductFoundExternally).product.id)
        .toSet();
    expect(productIds, hasLength(1));
    expect(concurrentProvider.calls, 2);
    expect(repository.products.where((product) => product.id != localProduct.id), hasLength(1));
    expect(repository.barcodes.where((mapping) => mapping.value == externalBarcode), hasLength(1));
  });
}

final class _FakeProductLookupProvider implements ProductLookupProvider {
  _FakeProductLookupProvider(this.result);

  ProductLookupResult result;
  var calls = 0;

  @override
  Future<ProductLookupResult> findByBarcode(String barcode) async {
    calls += 1;
    return result;
  }
}

final class _ThrowingProvider implements ProductLookupProvider {
  @override
  Future<ProductLookupResult> findByBarcode(String barcode) {
    throw StateError('provider failed');
  }
}

final class _BarrierProvider implements ProductLookupProvider {
  _BarrierProvider(this.result);

  final ProductLookupResult result;
  final _gate = Completer<void>();
  var calls = 0;

  @override
  Future<ProductLookupResult> findByBarcode(String barcode) async {
    calls += 1;
    if (calls == 2) _gate.complete();
    await _gate.future;
    return result;
  }
}

final class _CountingRepository implements ProductCatalogRepository {
  _CountingRepository(this.delegate);

  final ProductCatalogRepository delegate;
  var findCalls = 0;

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    return delegate.createManualProductWithoutBarcode(shopId: shopId, product: product);
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required barcode}) {
    findCalls += 1;
    return delegate.findByBarcode(shopId: shopId, barcode: barcode);
  }

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required barcode,
    required ExternalProductDraft product,
  }) {
    return delegate.saveExternalProduct(shopId: shopId, barcode: barcode, product: product);
  }

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required barcode,
    required ManualProductDraft product,
  }) {
    return delegate.saveManualProduct(shopId: shopId, barcode: barcode, product: product);
  }
}

final class _ThrowingRepository implements ProductCatalogRepository {
  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    throw const ProductCatalogException('database offline');
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required barcode}) {
    throw const ProductCatalogException('database offline');
  }

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required barcode,
    required ExternalProductDraft product,
  }) {
    throw const ProductCatalogException('database offline');
  }

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required barcode,
    required ManualProductDraft product,
  }) {
    throw const ProductCatalogException('database offline');
  }
}
