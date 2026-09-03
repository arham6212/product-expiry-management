import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/domain_validation_exception.dart';
import '../../../domain/value_objects/local_date.dart';
import '../../product_resolution/presentation/barcode_less_product_entry_page.dart';
import '../application/receive_stock.dart';
import '../application/receive_stock_controller.dart';

class ReceiveStockPage extends ConsumerStatefulWidget {
  const ReceiveStockPage({required this.shopId, this.initialProduct, super.key});

  final String shopId;
  final Product? initialProduct;

  @override
  ConsumerState<ReceiveStockPage> createState() => _ReceiveStockPageState();
}

class _ReceiveStockPageState extends ConsumerState<ReceiveStockPage> {
  final _formKey = GlobalKey<FormState>();
  final _expiryController = TextEditingController();
  final _quantityController = TextEditingController();
  final _lotNumberController = TextEditingController();
  late final ReceiveStockRouteArgs _routeArgs;

  @override
  void initState() {
    super.initState();
    _routeArgs = ReceiveStockRouteArgs(
      shopId: widget.shopId,
      initialProduct: widget.initialProduct,
    );
  }

  @override
  void dispose() {
    _expiryController.dispose();
    _quantityController.dispose();
    _lotNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiving = ref.watch(receiveStockControllerProvider(_routeArgs));
    return Scaffold(
      appBar: AppBar(title: const Text('Receive stock')),
      body: SafeArea(
        child: switch (receiving) {
          AsyncLoading() => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading products…'),
              ],
            ),
          ),
          AsyncError() => _CenteredMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Products could not be loaded',
            message: 'Check the connection and try again. No receiving data was changed.',
            actionLabel: 'Try again',
            onAction: () =>
                ref.read(receiveStockControllerProvider(_routeArgs).notifier).retryProductLoad(),
          ),
          AsyncData(:final value) => _buildData(context, value),
        },
      ),
    );
  }

  Widget _buildData(BuildContext context, ReceiveStockViewState state) {
    final success = state.success;
    if (success != null) return _buildSuccess(context, state.products, success);
    return _buildForm(context, state);
  }

  Widget _buildForm(BuildContext context, ReceiveStockViewState state) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Receive product stock',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('This creates a new batch and its received movement together.'),
          const SizedBox(height: 24),
          KeyedSubtree(
            key: ValueKey(state.selectedProductId),
            child: DropdownButtonFormField<String>(
              key: const Key('productField'),
              initialValue: state.selectedProductId,
              decoration: const InputDecoration(
                labelText: 'Product',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: [
                for (final product in state.products)
                  DropdownMenuItem(value: product.id, child: Text(product.name)),
              ],
              onChanged: state.isSubmitting ? null : (value) => _notifier.selectProduct(value),
              validator: (value) => value == null ? 'Select or add a product.' : null,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('addProductWithoutBarcodeButton'),
              onPressed: state.isSubmitting ? null : () => _addProductWithoutBarcode(context),
              icon: const Icon(Icons.add),
              label: const Text('Add product without barcode'),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('quantityField'),
            controller: _quantityController,
            enabled: !state.isSubmitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.numbers),
            ),
            validator: _validateQuantity,
            onChanged: (_) => _notifier.draftChanged(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('expiryField'),
            controller: _expiryController,
            enabled: !state.isSubmitting,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Expiry date *',
              hintText: 'YYYY-MM-DD',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.event_outlined),
              suffixIcon: IconButton(
                tooltip: 'Choose expiry date',
                onPressed: state.isSubmitting ? null : _pickExpiryDate,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ),
            validator: _validateExpiry,
            onChanged: (_) => _notifier.draftChanged(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('lotNumberField'),
            controller: _lotNumberController,
            enabled: !state.isSubmitting,
            textInputAction: TextInputAction.done,
            maxLength: ReceiveStock.maxLotNumberLength,
            decoration: const InputDecoration(
              labelText: 'Batch / lot number (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag_outlined),
            ),
            onChanged: (_) => _notifier.draftChanged(),
            onFieldSubmitted: (_) => _submit(state),
          ),
          if (state.saveError != null) ...[
            const SizedBox(height: 8),
            _ErrorNotice(
              message: state.saveError!,
              actionLabel: state.hasIdempotencyConflict ? 'Start new request' : 'Retry',
              onAction: state.hasIdempotencyConflict
                  ? _notifier.startNewRequest
                  : () => _submit(state),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('saveReceivedStockButton'),
            onPressed: state.isSubmitting ? null : () => _submit(state),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: state.isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Confirm received stock'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, List<Product> products, ReceiveStockSuccess result) {
    final receipt = result.receipt;
    final product = products.firstWhere((item) => item.id == receipt.batch.productId);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 18),
                Text(
                  'Stock received',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  receipt.wasDuplicate
                      ? 'This request was already recorded. No stock was added twice.'
                      : 'The batch and received movement were recorded together.',
                ),
                const Divider(height: 32),
                _ResultRow(label: 'Product', value: product.name),
                _ResultRow(
                  label: 'Expiry',
                  value: receipt.batch.expiryDate?.toString() ?? 'Not provided',
                ),
                _ResultRow(label: 'Lot', value: receipt.batch.lotCode ?? 'Not provided'),
                _ResultRow(label: 'Quantity', value: receipt.batch.currentQuantity.toString()),
                _ResultRow(label: 'Batch', value: receipt.batch.id),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('receiveAnotherButton'),
          onPressed: _receiveAnother,
          icon: const Icon(Icons.add),
          label: const Text('Receive another'),
        ),
      ],
    );
  }

  ReceiveStockController get _notifier =>
      ref.read(receiveStockControllerProvider(_routeArgs).notifier);

  Future<void> _addProductWithoutBarcode(BuildContext context) async {
    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute<Product>(
        builder: (_) => BarcodeLessProductEntryPage(shopId: widget.shopId),
      ),
    );
    if (!mounted || product == null) return;
    _notifier.selectCreatedProduct(product);
  }

  Future<void> _pickExpiryDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Select expiry date',
    );
    if (selected == null) return;
    _expiryController.text = LocalDate(selected.year, selected.month, selected.day).toString();
    _notifier.draftChanged();
  }

  Future<void> _submit(ReceiveStockViewState state) async {
    if (state.isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final expiryText = _expiryController.text.trim();
    await _notifier.submit(
      ReceiveStockInput(
        shopId: widget.shopId,
        productId: state.selectedProductId!,
        expiryDate: expiryText.isEmpty ? null : LocalDate.parseIso8601(expiryText),
        quantity: int.parse(_quantityController.text),
        lotNumber: _lotNumberController.text,
      ),
    );
  }

  String? _validateExpiry(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter an expiry date.';
    try {
      LocalDate.parseIso8601(value.trim());
      return null;
    } on DomainValidationException {
      return 'Enter a valid date using YYYY-MM-DD.';
    }
  }

  String? _validateQuantity(String? value) {
    if (value == null || value.isEmpty) return 'Enter a quantity.';
    final quantity = int.tryParse(value);
    if (quantity == null || quantity <= 0) return 'Quantity must be greater than zero.';
    if (quantity > ReceiveStock.maxQuantity) return 'Quantity must be 2,147,483,647 or less.';
    return null;
  }

  void _receiveAnother() {
    _formKey.currentState?.reset();
    _expiryController.clear();
    _quantityController.clear();
    _lotNumberController.clear();
    _notifier.receiveAnother();
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.actionLabel, required this.onAction});

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: TextStyle(color: colors.onErrorContainer)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: onAction, child: Text(actionLabel)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
