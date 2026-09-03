import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/presentation/barcode_less_product_entry_page.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2);

  testWidgets('shows validation and preserves fields after a backend failure', (tester) async {
    final repository = _FailOnceCatalogRepository(
      InMemoryProductCatalogRepository(clock: () => now),
    );
    await _pump(tester, repository, _access(now));

    await tester.tap(find.byKey(const Key('openBarcodeLessEntry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pump();
    expect(find.text('Product name is required.'), findsOneWidget);
    expect(repository.createCalls, 1);

    await tester.enterText(find.byKey(const Key('barcodeLessProductName')), 'Retry product');
    await tester.enterText(find.byKey(const Key('barcodeLessProductBrand')), 'Retry brand');
    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Retry product'), findsOneWidget);
    expect(find.text('Retry brand'), findsOneWidget);
    expect(find.text('Product could not be created.'), findsOneWidget);
    expect(repository.createCalls, 2);

    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pumpAndSettle();
    expect(find.text('Retry product'), findsOneWidget);
    expect(repository.createCalls, 3);
  });

  testWidgets('blocks duplicate taps while saving and returns success', (tester) async {
    final repository = _BlockingCatalogRepository(now);
    await _pump(tester, repository, _access(now));
    await tester.tap(find.byKey(const Key('openBarcodeLessEntry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeLessProductName')), 'Fresh milk');

    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pump();

    expect(repository.createCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.complete();
    await tester.pumpAndSettle();
    expect(find.text('Fresh milk'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ProductCatalogRepository repository,
  ShopAccess activeShop,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productCatalogRepositoryProvider.overrideWithValue(repository),
        activeShopProvider.overrideWithValue(activeShop),
      ],
      child: const MaterialApp(home: _Launcher()),
    ),
  );
}

ShopAccess _access(DateTime now) {
  return ShopAccess(
    shop: Shop(
      id: 'shop-1',
      name: 'Shop',
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: now,
      updatedAt: now,
    ),
    membership: ShopMembership(
      shopId: 'shop-1',
      userId: 'worker-1',
      role: ShopMembershipRole.worker,
      createdAt: now,
    ),
  );
}

class _Launcher extends StatefulWidget {
  const _Launcher();

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String? _createdName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            key: const Key('openBarcodeLessEntry'),
            onPressed: () async {
              final product = await Navigator.of(context).push<Product>(
                MaterialPageRoute<Product>(
                  builder: (_) => const BarcodeLessProductEntryPage(shopId: 'shop-1'),
                ),
              );
              if (!mounted || product == null) return;
              setState(() => _createdName = product.name);
            },
            child: const Text('Open'),
          ),
          if (_createdName != null) Text(_createdName!),
        ],
      ),
    );
  }
}

final class _BlockingCatalogRepository implements ProductCatalogRepository {
  _BlockingCatalogRepository(this.now);

  final DateTime now;
  final _result = Completer<Product>();
  var createCalls = 0;

  void complete() => _result.complete(
    Product(
      id: 'product-1',
      shopId: 'shop-1',
      name: 'Fresh milk',
      source: ProductSource.localManual,
      createdAt: now,
      updatedAt: now,
    ),
  );

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    createCalls += 1;
    return _result.future;
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode}) =>
      throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) => throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) => throw UnimplementedError();
}

final class _FailOnceCatalogRepository implements ProductCatalogRepository {
  _FailOnceCatalogRepository(this.delegate);

  final ProductCatalogRepository delegate;
  var createCalls = 0;

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) {
    createCalls += 1;
    if (createCalls == 2) {
      throw const ProductCatalogException('Product could not be created.');
    }
    return delegate.createManualProductWithoutBarcode(shopId: shopId, product: product);
  }

  @override
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode}) =>
      throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) => throw UnimplementedError();

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) => throw UnimplementedError();
}
