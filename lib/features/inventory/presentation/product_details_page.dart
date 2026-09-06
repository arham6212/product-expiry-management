import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../../../domain/entities/domain_models.dart';
import '../../shops/application/shop_session_controller.dart';
import '../../product_resolution/presentation/product_image_card.dart';
import '../application/expiry_dashboard.dart';
import '../application/inventory_catalog_controller.dart';
import '../application/receive_stock.dart';
import 'expiry_status.dart';
import 'receive_stock_page.dart';

class ProductDetailsPage extends ConsumerWidget {
  const ProductDetailsPage({required this.productId, this.highlightBatchId, super.key});

  final String productId;
  final String? highlightBatchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(inventoryCatalogProvider);
    final product = catalog.asData?.value.productById(productId);
    return Scaffold(
      bottomNavigationBar: product == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ReceiveStockPage(
                        shopId: product.shopId,
                        currencyCode: ref.read(activeShopProvider)?.shop.currencyCode ?? '',
                        initialProduct: product,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Receive stock'),
                ),
              ),
            ),
      appBar: AppBar(title: const Text('Product details')),
      body: SafeArea(
        child: switch (catalog) {
          AsyncData(:final value) => _buildProduct(context, ref, value),
          AsyncError() => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              AppStatePanel(
                icon: Icons.cloud_off_outlined,
                title: 'Product could not be loaded',
                message: 'Check the connection and try again. No product data was changed.',
                actionLabel: 'Try again',
                onAction: () => ref.read(inventoryCatalogActionsProvider).retry(),
              ),
            ],
          ),
          _ => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: const [
              AppStatePanel(
                icon: Icons.inventory_2_outlined,
                title: 'Loading product',
                message: 'Checking product and active batch details.',
                showProgress: true,
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _buildProduct(BuildContext context, WidgetRef ref, InventoryCatalogState state) {
    final product = state.productById(productId);
    if (product == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          AppStatePanel(
            icon: Icons.inventory_2_outlined,
            title: 'Product is unavailable',
            message: 'It may have been archived or removed from this shop.',
          ),
        ],
      );
    }
    final batches = state.dashboard.items.where((item) => item.productId == productId).toList()
      ..sort((a, b) => (a.daysToExpiry ?? 999999).compareTo(b.daysToExpiry ?? 999999));
    final currency = ref.read(activeShopProvider)?.shop.currencyCode ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _ProductIdentity(product: product, batches: batches, currencyCode: currency),
        ProductImageCard(shopId: product.shopId, productId: product.id, imageUrl: product.imageUrl),
        const SizedBox(height: AppSpacing.lg),
        AppSectionHeader(
          title: 'Active batches',
          subtitle: batches.isEmpty
              ? 'No active batch is currently tracked'
              : '${batches.length} active ${batches.length == 1 ? 'batch' : 'batches'}, most urgent first',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (batches.isEmpty)
          const AppStatePanel(
            icon: Icons.inventory_2_outlined,
            title: 'No active batch',
            message: 'Receive stock to begin tracking an expiry for this product.',
          )
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < batches.length; index++) ...[
                  _BatchRow(
                    item: batches[index],
                    highlighted: batches[index].batchId == highlightBatchId,
                  ),
                  if (index < batches.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _ProductIdentity extends StatelessWidget {
  const _ProductIdentity({
    required this.product,
    required this.batches,
    required this.currencyCode,
  });

  final Product product;
  final List<ExpiryDashboardItem> batches;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final mostUrgent = batches.isEmpty ? null : expiryStatusForDays(batches.first.daysToExpiry);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
              if (product.brand != null ||
                  product.packagingDisplay != null ||
                  product.barcode != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    product.brand,
                    product.packagingDisplay,
                    product.barcode,
                  ].whereType<String>().join(' · '),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppStatusChip(
                label: mostUrgent?.label ?? 'No active batch',
                tone: mostUrgent?.tone ?? AppStatusTone.neutral,
              ),
              if (product.sellingPriceMinor != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$currencyCode ${formatSellingPriceMinor(product.sellingPriceMinor!)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.item, required this.highlighted});

  final ExpiryDashboardItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final status = expiryStatusForDays(item.daysToExpiry);
    return ColoredBox(
      color: highlighted
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppStatusChip(label: status.label, tone: status.tone),
                ),
                Text('Qty ${item.quantityLabel}', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _BatchFact(label: 'Expiry', value: item.expiryDate?.toString() ?? 'Not recorded'),
            if (item.lotNumber != null) _BatchFact(label: 'Lot / batch', value: item.lotNumber!),
          ],
        ),
      ),
    );
  }
}

class _BatchFact extends StatelessWidget {
  const _BatchFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text('$label: $value', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
