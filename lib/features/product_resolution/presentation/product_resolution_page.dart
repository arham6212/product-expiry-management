import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/ports/external_providers.dart';
import '../application/product_resolution_controller.dart';
import '../application/resolve_product_by_barcode.dart';
import 'manual_product_entry_page.dart';
import 'product_barcode_scanner_screen.dart';

class ProductResolutionPage extends ConsumerStatefulWidget {
  const ProductResolutionPage({this.onManualAdd, super.key});

  final ValueChanged<String>? onManualAdd;

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
    final resolution = ref.watch(productResolutionControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Resolve product')),
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
    if (result is ProductFoundExternally) {
      return _FoundProduct(
        product: result.product,
        barcode: result.barcode,
        sourceLabel: switch (result.product.source) {
          ProductSource.openFoodFacts => 'Open Food Facts',
          ProductSource.localManual => 'Manual entry',
        },
      );
    }
    if (result is ProductResolutionNotFound) {
      return _ResultMessage(
        key: const Key('productNotFoundState'),
        icon: Icons.search_off_outlined,
        title: 'Product not found',
        message: "We couldn't find this product in your shop or Open Food Facts.",
        primaryLabel: 'Try again',
        onPrimary: _reset,
        secondaryLabel: 'Add product manually',
        onSecondary: () => _manualAdd(result.barcode),
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
    if (result is ProductResolutionUnavailable) {
      final offline = result.providerFailure == ProductLookupFailureKind.network;
      return _ResultMessage(
        key: const Key('lookupUnavailableState'),
        icon: offline ? Icons.cloud_off_outlined : Icons.warning_amber_rounded,
        title: offline ? 'No internet connection' : 'Lookup unavailable',
        message: offline
            ? 'Check your connection and try again.'
            : 'The product could not be resolved right now. Nothing was saved.',
        primaryLabel: 'Try again',
        onPrimary: _resolve,
        secondaryLabel: 'Add product manually',
        onSecondary: () => _manualAdd(result.barcode),
      );
    }
    return _buildEntry(context);
  }

  Widget _buildEntry(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.qr_code_scanner, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          'Scan or enter a barcode',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your current shop is checked before Open Food Facts.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('scanProductBarcodeButton'),
          onPressed: _scanBarcode,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan barcode'),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or enter it manually'),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
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
      ],
    );
  }

  Widget _buildLoading(ProductResolutionStage? stage) {
    final lookingExternal = stage == ProductResolutionStage.lookingUpExternal;
    final saving = stage == ProductResolutionStage.saving;
    return Center(
      key: Key(
        saving
            ? 'savingProductState'
            : lookingExternal
            ? 'externalLookupState'
            : 'localLookupState',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            saving
                ? Icons.cloud_upload_outlined
                : lookingExternal
                ? Icons.public
                : Icons.storage_outlined,
            size: 48,
          ),
          const SizedBox(height: 18),
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            saving
                ? 'Saving product…'
                : lookingExternal
                ? 'Looking up product…'
                : 'Checking our database…',
            key: const Key('resolutionStageText'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve() async {
    await ref.read(productResolutionControllerProvider.notifier).resolve(_barcodeController.text);
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute<String>(builder: (_) => const ProductBarcodeScannerScreen()));
    if (!mounted || barcode == null) return;
    _barcodeController.text = barcode;
    await _resolve();
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

  Future<void> _openManualEntry(String barcode) async {
    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute<Product>(builder: (_) => ManualProductEntryPage(barcode: barcode)),
    );
    if (!mounted || product == null) return;
    Navigator.of(context).pop<Product>(product);
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
        Center(child: _ProductImage(imageUrl: product.imageUrl)),
        const SizedBox(height: 20),
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
      ],
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final Uri? imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const Key('productImagePlaceholder'),
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.inventory_2_outlined, size: 48),
    );
    if (imageUrl == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        imageUrl.toString(),
        key: const Key('productImage'),
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => placeholder,
      ),
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
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

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
            if (secondaryLabel != null && onSecondary != null)
              OutlinedButton(
                key: const Key('manualAddButton'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
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
