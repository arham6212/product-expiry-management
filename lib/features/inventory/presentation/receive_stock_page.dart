import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/domain_validation_exception.dart';
import '../../../domain/value_objects/local_date.dart';
import '../../product_resolution/application/product_image_contribution.dart';
import '../../product_resolution/application/product_image_controller.dart';
import '../../product_resolution/presentation/product_image_card.dart';
import '../../product_resolution/presentation/product_resolution_page.dart';
import '../../shops/application/shop_session_controller.dart';
import '../application/receive_stock.dart';
import '../application/receive_stock_controller.dart';
import 'product_details_page.dart';

class ReceiveStockPage extends ConsumerStatefulWidget {
  const ReceiveStockPage({
    required this.shopId,
    required this.currencyCode,
    this.initialProduct,
    super.key,
  });

  final String shopId;
  final String currencyCode;
  final Product? initialProduct;

  @override
  ConsumerState<ReceiveStockPage> createState() => _ReceiveStockPageState();
}

class _ReceiveStockPageState extends ConsumerState<ReceiveStockPage> {
  final _formKey = GlobalKey<FormState>();
  final _expiryController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _lotNumberController = TextEditingController();
  late final ReceiveStockRouteArgs _routeArgs;
  String? _sellingPriceProductId;

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
    _sellingPriceController.dispose();
    _quantityController.dispose();
    _lotNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiving = ref.watch(receiveStockControllerProvider(_routeArgs));
    final current = receiving.asData?.value;
    final selected = current?.products.where((p) => p.id == current.selectedProductId).firstOrNull;
    if (selected case final Product selectedProduct) {
      // Keep the selection and upload alive through sheets and the receipt state.
      ref.watch(
        productImageControllerProvider(
          ProductImageTarget(shopId: widget.shopId, productId: selectedProduct.id),
        ),
      );
    }
    return PopScope(
      canPop: !(current?.isSubmitting ?? false),
      child: Scaffold(
        appBar: AppBar(title: const Text('Receive stock')),
        body: SafeArea(
          child: switch (receiving) {
            AsyncLoading() => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: AppStatePanel(
                  icon: Icons.inventory_2_outlined,
                  title: 'Loading products',
                  message: 'Preparing this shop for receiving.',
                  showProgress: true,
                ),
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
      ),
    );
  }

  Widget _buildData(BuildContext context, ReceiveStockViewState state) {
    final success = state.success;
    if (success != null) return _buildSuccess(context, state.products, success);
    return _buildForm(context, state);
  }

  Widget _buildForm(BuildContext context, ReceiveStockViewState state) {
    _syncSellingPrice(state);
    final product = state.products.where((p) => p.id == state.selectedProductId).firstOrNull;
    final activeShop = ref.watch(activeShopProvider)?.shop;
    final currency = activeShop?.id == widget.shopId
        ? activeShop!.currencyCode
        : widget.currencyCode;
    final metadata = product == null
        ? null
        : ref.watch(receivingProductMetadataProvider(product)).asData?.value;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.products.length == 1 && product != null)
                    Text(product.name, style: Theme.of(context).textTheme.titleLarge)
                  else
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
                        onChanged: state.isSubmitting
                            ? null
                            : (value) => _notifier.selectProduct(value),
                        validator: (value) => value == null ? 'Select or add a product.' : null,
                      ),
                    ),
                  if (product != null) ...[
                    const SizedBox(height: 8),
                    if ([
                      product.brand ?? metadata?.brand,
                      product.packagingDisplay ?? metadata?.packagingDisplay,
                      product.barcode,
                    ].whereType<String>().any((value) => value.trim().isNotEmpty))
                      Text(
                        [
                          product.brand ?? metadata?.brand,
                          product.packagingDisplay ?? metadata?.packagingDisplay,
                          product.barcode,
                        ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · '),
                        key: const Key('receivingProductMetadata'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ProductImageCard(
                      shopId: widget.shopId,
                      productId: product.id,
                      imageUrl: product.imageUrl,
                      compact: true,
                      uploadEnabled: !state.isSubmitting,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('sellingPriceField'),
                    controller: _sellingPriceController,
                    enabled: !state.isSubmitting,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Selling price ($currency) *',
                      hintText: '0.00',
                      helperText: 'Price per selling unit',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.sell_outlined),
                    ),
                    validator: _validateSellingPrice,
                    onChanged: (_) => _notifier.draftChanged(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('expiryField'),
                    controller: _expiryController,
                    enabled: !state.isSubmitting,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
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
                    key: const Key('quantityField'),
                    controller: _quantityController,
                    enabled: !state.isSubmitting,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Quantity (optional)',
                      helperText: 'Leave blank if unknown',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    validator: _validateQuantity,
                    onChanged: (_) => _notifier.draftChanged(),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    key: const Key('receivingMoreDetails'),
                    title: const Text('More details'),
                    tilePadding: EdgeInsets.zero,
                    maintainState: true,
                    children: [
                      TextFormField(
                        key: const Key('lotNumberField'),
                        controller: _lotNumberController,
                        enabled: !state.isSubmitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textInputAction: TextInputAction.done,
                        maxLength: ReceiveStock.maxLotNumberLength,
                        decoration: const InputDecoration(
                          labelText: 'Batch / lot number (optional)',
                          counterText: '',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                        onChanged: (_) => _notifier.draftChanged(),
                        onFieldSubmitted: (_) => _submit(state),
                      ),
                    ],
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
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const Key('saveReceivedStockButton'),
              onPressed: state.isSubmitting ? null : () => _submit(state),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: state.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save stock'),
              ),
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
                      : 'Your stock is saved. Ready for the next product.',
                ),
                const Divider(height: 32),
                _ResultRow(label: 'Product', value: product.name),
                _ResultRow(
                  label: 'Expiry',
                  value: receipt.batch.expiryDate?.toString() ?? 'Not provided',
                ),
                if (receipt.batch.lotCode != null)
                  _ResultRow(label: 'Lot', value: receipt.batch.lotCode!),
                _ResultRow(
                  label: 'Quantity',
                  value: receipt.batch.currentQuantity?.toString() ?? 'Unknown',
                ),
              ],
            ),
          ),
        ),
        if (ref
                .watch(
                  productImageControllerProvider(
                    ProductImageTarget(shopId: widget.shopId, productId: product.id),
                  ),
                )
                .stage
            case ProductImageStage.error || ProductImageStage.uploading)
          ProductImageCard(
            shopId: widget.shopId,
            productId: product.id,
            imageUrl: product.imageUrl,
            compact: true,
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('scanNextProductButton'),
          onPressed: _scanNext,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan next product'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('viewReceivedProductButton'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ProductDetailsPage(productId: product.id, highlightBatchId: receipt.batch.id),
            ),
          ),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('View product details'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          key: const Key('receiveAnotherButton'),
          onPressed: _receiveAnother,
          icon: const Icon(Icons.add),
          label: const Text('Receive another batch'),
        ),
      ],
    );
  }

  ReceiveStockController get _notifier =>
      ref.read(receiveStockControllerProvider(_routeArgs).notifier);

  Future<void> _pickExpiryDate() async {
    FocusScope.of(context).unfocus();
    final today = DateTime.now();
    final entered = DateTime.tryParse(_expiryController.text.trim());
    final selected = await showDatePicker(
      context: context,
      initialDate: entered != null && entered.year >= 2000 && entered.year <= 2100
          ? entered
          : today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Select expiry date',
    );
    if (!mounted || selected == null) return;
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
        sellingPriceMinor: parseSellingPriceMinor(_sellingPriceController.text),
        expiryDate: expiryText.isEmpty ? null : LocalDate.parseIso8601(expiryText),
        quantity: _quantityController.text.trim().isEmpty
            ? null
            : int.parse(_quantityController.text.trim()),
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

  String? _validateSellingPrice(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a selling price.';
    if (parseSellingPriceMinor(value) == null) {
      return 'Enter a price greater than zero with up to 2 decimal places.';
    }
    return null;
  }

  String? _validateQuantity(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final quantity = int.tryParse(value);
    if (quantity == null || quantity <= 0) return 'Quantity must be greater than zero.';
    if (quantity > ReceiveStock.maxQuantity) return 'Quantity must be 2,147,483,647 or less.';
    return null;
  }

  Future<void> _scanNext() async {
    final product = await Navigator.of(
      context,
    ).push<Product>(MaterialPageRoute<Product>(builder: (_) => const ProductResolutionPage()));
    if (!mounted || product == null || product.shopId != widget.shopId) return;
    _receiveAnother();
    _sellingPriceProductId = null;
    _sellingPriceController.clear();
    _notifier.selectCreatedProduct(product);
  }

  void _receiveAnother() {
    final sellingPrice = _sellingPriceController.text;
    _formKey.currentState?.reset();
    _expiryController.clear();
    _quantityController.clear();
    _lotNumberController.clear();
    _sellingPriceController.text = sellingPrice;
    _notifier.receiveAnother();
  }

  void _syncSellingPrice(ReceiveStockViewState state) {
    final productId = state.selectedProductId;
    if (_sellingPriceProductId == productId) return;
    final previousProductId = _sellingPriceProductId;
    _sellingPriceProductId = productId;
    final selected = state.products.where((product) => product.id == productId);
    final price = selected.isEmpty ? null : selected.single.sellingPriceMinor;
    if (price != null) {
      _sellingPriceController.text = formatSellingPriceMinor(price);
    } else if (previousProductId != null || productId == null) {
      _sellingPriceController.clear();
    }
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
