import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../application/manual_product_controller.dart';

class ManualProductEntryPage extends ConsumerStatefulWidget {
  const ManualProductEntryPage({required this.barcode, super.key});

  final String barcode;

  @override
  ConsumerState<ManualProductEntryPage> createState() => _ManualProductEntryPageState();
}

class _ManualProductEntryPageState extends ConsumerState<ManualProductEntryPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualProductControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add product manually')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Product details', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('This barcode was not found. Enter a name to save it to this shop.'),
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('manualProductBarcode'),
              initialValue: widget.barcode,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Barcode', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('manualProductName'),
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Product name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('manualProductBrand'),
              controller: _brandController,
              textInputAction: TextInputAction.done,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Brand (optional)',
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
                  : const Text('Save product'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final product = await ref
        .read(manualProductControllerProvider.notifier)
        .save(barcode: widget.barcode, name: _nameController.text, brand: _brandController.text);
    if (!mounted || product == null) return;
    Navigator.of(context).pop<Product>(product);
  }
}
