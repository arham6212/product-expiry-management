import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/ports/external_providers.dart';
import 'package:product_expiry_management/features/product_resolution/application/create_manual_product_for_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/manual_product_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_resolution_controller.dart';
import 'package:product_expiry_management/features/product_resolution/application/resolve_product_by_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/data/in_memory_product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/presentation/product_resolution_page.dart';

void main() {
  const barcode = '5000112519945';
  final now = DateTime.utc(2026, 8, 29);

  Product product({Uri? imageUrl, ProductSource source = ProductSource.openFoodFacts}) {
    return Product(
      id: 'product-1',
      shopId: 'shop-1',
      name: 'Coca Cola Zero',
      brand: 'Coca-Cola',
      imageUrl: imageUrl,
      source: source,
      sourceReference: source == ProductSource.openFoodFacts ? barcode : null,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProductResolver resolver, {
    ValueChanged<String>? onManualAdd,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [productResolverProvider.overrideWithValue(resolver)],
        child: MaterialApp(home: ProductResolutionPage(onManualAdd: onManualAdd)),
      ),
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('barcodeInput')), barcode);
    await tester.tap(find.byKey(const Key('resolveBarcodeButton')));
    await tester.pump();
  }

  testWidgets('shows local database loading state while lookup is pending', (tester) async {
    final resolver = _ControlledResolver();
    await pumpPage(tester, resolver);

    await submit(tester);

    expect(find.byKey(const Key('localLookupState')), findsOneWidget);
    expect(find.text('Checking our database…'), findsOneWidget);

    resolver.complete(ProductResolutionNotFound(barcode: barcode));
    await tester.pumpAndSettle();
  });

  testWidgets('shows external lookup state when the resolver reports it', (tester) async {
    final resolver = _ControlledResolver(externalStage: true);
    await pumpPage(tester, resolver);

    await submit(tester);

    expect(find.byKey(const Key('externalLookupState')), findsOneWidget);
    expect(find.text('Looking up product…'), findsOneWidget);

    resolver.complete(ProductResolutionNotFound(barcode: barcode));
    await tester.pumpAndSettle();
  });

  testWidgets('shows a found product and missing-image placeholder', (tester) async {
    final resolver = _ImmediateResolver(
      ProductFoundExternally(barcode: barcode, product: product()),
    );
    await pumpPage(tester, resolver);

    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('productFoundState')), findsOneWidget);
    expect(find.text('Coca Cola Zero'), findsOneWidget);
    expect(find.text('Open Food Facts'), findsOneWidget);
    expect(find.byKey(const Key('productImagePlaceholder')), findsOneWidget);
  });

  testWidgets('shows the persisted winner source after an external-save race', (tester) async {
    final resolver = _ImmediateResolver(
      ProductFoundExternally(
        barcode: barcode,
        product: product(source: ProductSource.localManual),
      ),
    );
    await pumpPage(tester, resolver);

    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Manual entry'), findsOneWidget);
    expect(find.text('Open Food Facts'), findsNothing);
  });

  testWidgets('shows not-found with retry and manual-add actions', (tester) async {
    String? manualBarcode;
    final resolver = _ImmediateResolver(ProductResolutionNotFound(barcode: barcode));
    await pumpPage(tester, resolver, onManualAdd: (value) => manualBarcode = value);

    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('productNotFoundState')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const Key('manualAddButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('manualAddButton')));
    expect(manualBarcode, barcode);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byKey(const Key('barcodeInput')), findsOneWidget);
  });

  testWidgets('failure state does not crash and retry reruns lookup', (tester) async {
    final resolver = _SequenceResolver([
      const ProductResolutionUnavailable(
        barcode: barcode,
        stage: ProductResolutionFailureStage.externalProvider,
        providerFailure: ProductLookupFailureKind.network,
      ),
      ProductFoundLocally(barcode: barcode, product: product()),
    ]);
    await pumpPage(tester, resolver);

    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lookupUnavailableState')), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('productFoundState')), findsOneWidget);
    expect(resolver.calls, 2);
  });

  testWidgets('invalid barcode leaves loading and shows actionable message', (tester) async {
    final resolver = _ImmediateResolver(
      const ProductResolutionInvalidBarcode(barcode: '', message: 'Enter or scan a barcode.'),
    );
    await pumpPage(tester, resolver);

    await tester.tap(find.byKey(const Key('resolveBarcodeButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invalidBarcodeState')), findsOneWidget);
    expect(find.text('Enter or scan a barcode.'), findsOneWidget);
  });

  testWidgets('default manual fallback saves and returns the persisted Product', (tester) async {
    final repository = InMemoryProductCatalogRepository(
      idGenerator: (prefix) => '$prefix-1',
      clock: () => now,
    );
    final creator = CreateManualProductForBarcode(shopId: 'shop-1', repository: repository);
    final resolver = _ImmediateResolver(ProductResolutionNotFound(barcode: barcode));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productResolverProvider.overrideWithValue(resolver),
          manualProductCreatorProvider.overrideWithValue(creator),
        ],
        child: const MaterialApp(home: _ResolutionLauncher()),
      ),
    );

    await tester.tap(find.byKey(const Key('openProductResolution')));
    await tester.pumpAndSettle();
    await submit(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manualAddButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manualProductName')), 'Manual Cola');
    await tester.tap(find.byKey(const Key('saveManualProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Manual Cola'), findsOneWidget);
    expect(repository.products, hasLength(1));
    expect(repository.barcodes, hasLength(1));
  });
}

final class _ImmediateResolver implements ProductResolver {
  const _ImmediateResolver(this.result);

  final ProductResolutionResult result;

  @override
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  }) async {
    onStage?.call(ProductResolutionStage.checkingLocal);
    return result;
  }
}

final class _ControlledResolver implements ProductResolver {
  _ControlledResolver({this.externalStage = false});

  final bool externalStage;
  final _completer = Completer<ProductResolutionResult>();

  void complete(ProductResolutionResult result) => _completer.complete(result);

  @override
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  }) {
    onStage?.call(ProductResolutionStage.checkingLocal);
    if (externalStage) onStage?.call(ProductResolutionStage.lookingUpExternal);
    return _completer.future;
  }
}

final class _SequenceResolver implements ProductResolver {
  _SequenceResolver(this.results);

  final List<ProductResolutionResult> results;
  var calls = 0;

  @override
  Future<ProductResolutionResult> resolve(
    String barcode, {
    ProductResolutionStageObserver? onStage,
  }) async {
    onStage?.call(ProductResolutionStage.checkingLocal);
    return results[calls++];
  }
}

class _ResolutionLauncher extends StatefulWidget {
  const _ResolutionLauncher();

  @override
  State<_ResolutionLauncher> createState() => _ResolutionLauncherState();
}

class _ResolutionLauncherState extends State<_ResolutionLauncher> {
  Product? _product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            key: const Key('openProductResolution'),
            onPressed: () async {
              final product = await Navigator.of(context).push<Product>(
                MaterialPageRoute<Product>(builder: (_) => const ProductResolutionPage()),
              );
              if (!mounted || product == null) return;
              setState(() => _product = product);
            },
            child: const Text('Resolve'),
          ),
          if (_product != null) Text(_product!.name),
        ],
      ),
    );
  }
}
