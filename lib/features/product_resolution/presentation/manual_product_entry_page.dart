import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../application/manual_product_controller.dart';
import '../application/product_catalog_repository.dart';
import '../../../design_system/components/app_components.dart';

class ManualProductEntryPage extends ConsumerStatefulWidget {
  const ManualProductEntryPage({required this.barcode, this.suggestion, super.key});

  final String barcode;
  final CatalogProductSuggestion? suggestion;

  @override
  ConsumerState<ManualProductEntryPage> createState() => _ManualProductEntryPageState();
}

class _ManualProductEntryPageState extends ConsumerState<ManualProductEntryPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final suggestion = widget.suggestion;
    if (suggestion != null) {
      _nameController.text = suggestion.name;
      _brandController.text = suggestion.brand ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualProductControllerProvider);
    final savedProduct = state.savedProduct;
    final canonicalImageUrl = widget.suggestion?.imageUrl ?? savedProduct?.imageUrl;
    return PopScope(
      canPop: !state.isSaving,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.suggestion == null ? 'Add product' : 'Confirm product')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.suggestion == null
                    ? (widget.barcode.isEmpty
                          ? 'Enter the product name.'
                          : 'New barcode. Enter the product name.')
                    : 'Check the name, then continue to receive stock.',
              ),
              if (widget.suggestion case final suggestion?) ...[
                const SizedBox(height: 16),
                if (suggestion.packagingDisplay != null)
                  Text('Packaging: ${suggestion.packagingDisplay}'),
                if (suggestion.category != null) Text('Category: ${suggestion.category}'),
                if (suggestion.manufacturer != null)
                  Text('Manufacturer: ${suggestion.manufacturer}'),
              ],
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('manualProductBarcode'),
                initialValue: widget.barcode,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Barcode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('manualProductName'),
                controller: _nameController,
                enabled: !state.isSaving,
                autofocus: true,
                textInputAction: TextInputAction.next,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('manualProductBrand'),
                controller: _brandController,
                enabled: !state.isSaving,
                textInputAction: TextInputAction.done,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Brand (optional)',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: state.isSaving ? null : (_) => _save(),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  key: const Key('manualProductError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('saveManualProductButton'),
                onPressed: state.isSaving ? null : _save,
                child: state.isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(state.savedProduct == null ? 'Use product' : 'Continue'),
              ),
              if (canonicalImageUrl != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppProductImage(imageUrl: canonicalImageUrl),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final existing = ref.read(manualProductControllerProvider).savedProduct;
    if (existing != null) {
      Navigator.of(context).pop<Product>(existing);
      return;
    }
    final product = await ref
        .read(manualProductControllerProvider.notifier)
        .save(
          barcode: widget.barcode,
          name: _nameController.text,
          brand: _brandController.text,
          suggestion: widget.suggestion,
        );
    if (!mounted || product == null) return;
    Navigator.of(context).pop<Product>(product);
  }
}
