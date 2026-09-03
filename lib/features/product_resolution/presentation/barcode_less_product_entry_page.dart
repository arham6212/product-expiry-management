import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../application/barcode_less_product_controller.dart';

class BarcodeLessProductEntryPage extends ConsumerStatefulWidget {
  const BarcodeLessProductEntryPage({required this.shopId, super.key});

  final String shopId;

  @override
  ConsumerState<BarcodeLessProductEntryPage> createState() => _BarcodeLessProductEntryPageState();
}

class _BarcodeLessProductEntryPageState extends ConsumerState<BarcodeLessProductEntryPage> {
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
    final state = ref.watch(barcodeLessProductControllerProvider(widget.shopId));
    return Scaffold(
      appBar: AppBar(title: const Text('Add product without barcode')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Product details', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Enter a name for this shop. No barcode will be created.'),
            const SizedBox(height: 24),
            TextField(
              key: const Key('barcodeLessProductName'),
              controller: _nameController,
              autofocus: true,
              enabled: !state.isSaving,
              textInputAction: TextInputAction.next,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Product name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('barcodeLessProductBrand'),
              controller: _brandController,
              enabled: !state.isSaving,
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
                key: const Key('barcodeLessProductError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('saveBarcodeLessProductButton'),
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
        .read(barcodeLessProductControllerProvider(widget.shopId).notifier)
        .save(name: _nameController.text, brand: _brandController.text);
    if (!mounted || product == null) return;
    Navigator.of(context).pop<Product>(product);
  }
}
