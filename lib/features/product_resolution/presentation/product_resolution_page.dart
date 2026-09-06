import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../shops/application/shop_session_controller.dart';
import '../application/product_catalog_repository.dart';
import '../application/product_resolution_controller.dart';
import '../application/resolve_product_by_barcode.dart';
import 'barcode_less_product_entry_page.dart';
import 'manual_product_entry_page.dart';
import 'product_barcode_scanner_screen.dart';
import 'product_image_card.dart';

class ProductResolutionPage extends ConsumerStatefulWidget {
  const ProductResolutionPage({this.onManualAdd, this.onResolved, super.key});

  final ValueChanged<String>? onManualAdd;
  final ValueChanged<Product>? onResolved;

  @override
  ConsumerState<ProductResolutionPage> createState() => _ProductResolutionPageState();
}

class _ProductResolutionPageState extends ConsumerState<ProductResolutionPage> {
  final _barcodeController = TextEditingController();

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(productResolutionControllerProvider, (previous, current) {
      if (current.isResolving || identical(previous?.result, current.result)) return;
      final result = current.result;
      if (result is ProductFoundLocally && Navigator.of(context).canPop()) {
        _complete(result.product);
      } else if (result is ProductFoundGlobally) {
        _openManualEntry(result.barcode, suggestion: result.suggestion);
      } else if (result is ProductResolutionNotFound) {
        _manualAdd(result.barcode);
      }
    });

    final resolution = ref.watch(productResolutionControllerProvider);
    final isInitial = !resolution.isResolving && resolution.result == null;

    if (isInitial && !resolution.manualEntry) {
      return ProductBarcodeScannerScreen(
        onWithoutBarcode: _openWithoutBarcode,
        onDetect: (barcode) {
          _barcodeController.text = barcode;
          _resolve();
        },
        onManualEntry: () {
          ref.read(productResolutionControllerProvider.notifier).showManualEntry();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan product')),
      body: SafeArea(child: _buildBody(context, resolution)),
    );
  }

  Widget _buildBody(BuildContext context, ProductResolutionState resolution) {
    if (resolution.isResolving) return _buildLoading(resolution.stage);
    final result = resolution.result;
    if (result is ProductFoundLocally) {
      return _FoundProduct(
        product: result.product,
        barcode: result.barcode,
        sourceLabel: 'Our database',
      );
    }
    if (result is ProductResolutionUnavailable) {
      return _ResultMessage(
        key: const Key('lookupUnavailableState'),
        icon: Icons.cloud_off_outlined,
        title: 'Couldn’t look up this barcode',
        message: 'Check your connection and retry. Your barcode is kept.',
        primaryLabel: 'Retry lookup',
        onPrimary: _resolve,
      );
    }
    if (result is ProductFoundGlobally || result is ProductResolutionNotFound) {
      return _ResultMessage(
        icon: Icons.edit_outlined,
        title: 'Review product details',
        message: 'Barcode: ${result!.barcode}',
        primaryLabel: 'Continue',
        onPrimary: () => result is ProductFoundGlobally
            ? _openManualEntry(result.barcode, suggestion: result.suggestion)
            : _manualAdd(result.barcode),
      );
    }

    if (result is ProductResolutionInvalidBarcode) {
      return _ResultMessage(
        key: const Key('invalidBarcodeState'),
        icon: Icons.qr_code_2,
        title: 'Invalid barcode',
        message: result.message,
        primaryLabel: 'Try again',
        onPrimary: _reset,
      );
    }
    return _buildEntry(context);
  }

  Widget _buildEntry(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.keyboard_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          'Enter barcode manually',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Enter the barcode exactly as it appears.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          key: const Key('barcodeInput'),
          controller: _barcodeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Barcode',
            hintText: 'EAN, UPC, or GTIN',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _resolve(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('resolveBarcodeButton'),
          onPressed: _resolve,
          icon: const Icon(Icons.search),
          label: const Text('Look up product'),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('scanProductBarcodeButton'),
          onPressed: _reset,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Back to camera'),
        ),
      ],
    );
  }

  Widget _buildLoading(ProductResolutionStage? stage) {
    return Center(
      key: const Key('localLookupState'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storage_outlined, size: 48),
          const SizedBox(height: 18),
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            stage == ProductResolutionStage.checkingGlobal
                ? 'Checking the global catalog…'
                : 'Checking this shop…',
            key: const Key('resolutionStageText'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve() async {
    FocusScope.of(context).unfocus();
    await ref.read(productResolutionControllerProvider.notifier).resolve(_barcodeController.text);
  }

  void _reset() {
    ref.read(productResolutionControllerProvider.notifier).reset();
  }

  void _manualAdd(String barcode) {
    final handler = widget.onManualAdd;
    if (handler != null) {
      handler(barcode);
      return;
    }
    _openManualEntry(barcode);
  }

  Future<void> _openWithoutBarcode() async {
    final shop = ref.read(activeShopProvider)?.shop;
    if (shop == null) return;
    ref.read(productResolutionControllerProvider.notifier).showManualEntry();
    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute<Product>(builder: (_) => BarcodeLessProductEntryPage(shopId: shop.id)),
    );
    if (!mounted) return;
    if (product == null) {
      _reset();
      return;
    }
    _complete(product);
  }

  void _complete(Product product) {
    final handler = widget.onResolved;
    if (handler != null) {
      handler(product);
    } else {
      Navigator.of(context).pop<Product>(product);
    }
  }

  Future<void> _openManualEntry(String barcode, {CatalogProductSuggestion? suggestion}) async {
    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute<Product>(
        builder: (_) => ManualProductEntryPage(barcode: barcode, suggestion: suggestion),
      ),
    );
    if (!mounted) return;
    if (product == null) {
      _reset();
      return;
    }
    _complete(product);
  }
}

class _FoundProduct extends StatelessWidget {
  const _FoundProduct({required this.product, required this.barcode, required this.sourceLabel});

  final Product product;
  final String barcode;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('productFoundState'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          product.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (product.brand != null) ...[
          const SizedBox(height: 6),
          Text(product.brand!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        _DetailRow(label: 'Source', value: sourceLabel),
        _DetailRow(label: 'Barcode', value: barcode),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('continueWithProductButton'),
          onPressed: () => Navigator.of(context).pop(product),
          child: const Text('Continue'),
        ),
        const SizedBox(height: 20),
        ProductImageCard(shopId: product.shopId, productId: product.id, imageUrl: product.imageUrl),
      ],
    );
  }
}

class _ResultMessage extends StatelessWidget {
  const _ResultMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
