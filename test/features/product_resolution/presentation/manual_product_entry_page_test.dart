import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/create_manual_product_for_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/manual_product_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/presentation/manual_product_entry_page.dart';

void main() {
  const barcode = '5000112519945';

  testWidgets('validates, saves, and returns the persisted manual Product', (tester) async {
    final repository = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-1',
      clock: () => DateTime.utc(2026, 8, 31),
    );
    final creator = CreateManualProductForBarcode(shopId: 'shop-1', repository: repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [manualProductCreatorProvider.overrideWithValue(creator)],
        child: const MaterialApp(home: _ManualEntryLauncher(barcode: barcode)),
      ),
    );

    await tester.tap(find.byKey(const Key('openManualEntry')));
    await tester.pumpAndSettle();
    expect(find.text(barcode), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveManualProductButton')));
    await tester.pump();
    expect(find.text('Product name is required.'), findsOneWidget);
    expect(repository.products, isEmpty);

    await tester.enterText(find.byKey(const Key('manualProductName')), '  Manual   Cola  ');
    await tester.enterText(find.byKey(const Key('manualProductBrand')), '  Local Brand  ');
    await tester.tap(find.byKey(const Key('saveManualProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Manual Cola'), findsOneWidget);
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });

  testWidgets('network-style save failure preserves fields and retry succeeds', (tester) async {
    final repository = _FailOnceCatalogRepository(
      InMemoryProductCatalogRepository(
        idGenerator: (prefix) => '$prefix-1',
        clock: () => DateTime.utc(2026, 8, 31),
      ),
    );
    final creator = CreateManualProductForBarcode(shopId: 'shop-1', repository: repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [manualProductCreatorProvider.overrideWithValue(creator)],
        child: const MaterialApp(home: _ManualEntryLauncher(barcode: barcode)),
      ),
    );
    await tester.tap(find.byKey(const Key('openManualEntry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manualProductName')), 'Retry Product');
    await tester.enterText(find.byKey(const Key('manualProductBrand')), 'Retry Brand');

    await tester.tap(find.byKey(const Key('saveManualProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Retry Product'), findsOneWidget);
    expect(find.text('Retry Brand'), findsOneWidget);
    expect(find.byKey(const Key('manualProductError')), findsOneWidget);
    expect(repository.saveCalls, 1);

    await tester.tap(find.byKey(const Key('saveManualProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Retry Product'), findsOneWidget);
    expect(repository.saveCalls, 2);
  });
}

class _ManualEntryLauncher extends StatefulWidget {
  const _ManualEntryLauncher({required this.barcode});

  final String barcode;

  @override
  State<_ManualEntryLauncher> createState() => _ManualEntryLauncherState();
}

class _ManualEntryLauncherState extends State<_ManualEntryLauncher> {
  String? _productName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            key: const Key('openManualEntry'),
            onPressed: () async {
              final product = await Navigator.of(context).push<Product>(
                MaterialPageRoute<Product>(
                  builder: (_) => ManualProductEntryPage(barcode: widget.barcode),
                ),
              );
              if (!mounted || product == null) return;
              setState(() => _productName = product.name);
            },
            child: const Text('Open'),
          ),
          if (_productName != null) Text(_productName!),
        ],
      ),
    );
  }
}

final class _FailOnceCatalogRepository implements ProductCatalogRepository {
  _FailOnceCatalogRepository(this.delegate);

  final InMemoryProductCatalogRepository delegate;
  var saveCalls = 0;

  @override
  Future<Product> createManualProductWithoutBarcode({
    required String shopId,
    required ManualProductDraft product,
  }) => delegate.createManualProductWithoutBarcode(shopId: shopId, product: product);

  @override
  Future<Product?> findByBarcode({required String shopId, required NormalizedBarcode barcode}) =>
      delegate.findByBarcode(shopId: shopId, barcode: barcode);

  @override
  Future<ProductCatalogSaveResult> saveExternalProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ExternalProductDraft product,
  }) => delegate.saveExternalProduct(shopId: shopId, barcode: barcode, product: product);

  @override
  Future<ProductCatalogSaveResult> saveManualProduct({
    required String shopId,
    required NormalizedBarcode barcode,
    required ManualProductDraft product,
  }) {
    saveCalls += 1;
    if (saveCalls == 1) {
      throw const ProductCatalogException('network unavailable');
    }
    return delegate.saveManualProduct(shopId: shopId, barcode: barcode, product: product);
  }
}
