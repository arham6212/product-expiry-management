import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../../../domain/entities/domain_models.dart';
import '../../product_resolution/presentation/shop_product_image.dart';
import '../application/expiry_dashboard.dart';
import '../application/inventory_catalog_controller.dart';
import 'expiry_status.dart';
import 'product_details_page.dart';
import 'receive_stock_page.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({required this.shopId, required this.currencyCode, super.key});

  final String shopId;
  final String currencyCode;

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(inventoryCatalogProvider);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(inventoryCatalogActionsProvider).retry(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 104),
            children: [
              AppPageHeader(
                title: 'Products',
                trailing: FilledButton.icon(
                  key: const Key('openReceiveStockButton'),
                  onPressed: _openReceiveStock,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Receive'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSearchField(
                controller: _searchController,
                hintText: 'Search name, barcode, brand or lot',
                onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.sm),
              switch (catalog) {
                AsyncData(:final value) => _InventoryResults(state: value, query: _query),
                AsyncError() => AppStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Inventory could not be loaded',
                  message: 'Check the connection and try again. No stock was changed.',
                  actionLabel: 'Try again',
                  onAction: () => ref.read(inventoryCatalogActionsProvider).retry(),
                ),
                _ => const AppStatePanel(
                  icon: Icons.inventory_2_outlined,
                  title: 'Loading inventory',
                  message: 'Checking products and active batches for this shop.',
                  showProgress: true,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  void _openReceiveStock() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveStockPage(shopId: widget.shopId, currencyCode: widget.currencyCode),
      ),
    );
  }
}

class _InventoryResults extends StatelessWidget {
  const _InventoryResults({required this.state, required this.query});

  final InventoryCatalogState state;
  final String query;

  @override
  Widget build(BuildContext context) {
    final products = state.products.where((product) {
      if (query.isEmpty) return true;
      final batches = state.dashboard.items.where((item) => item.productId == product.id);
      return product.name.toLowerCase().contains(query) ||
          (product.brand?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.contains(query) ?? false) ||
          batches.any((item) => item.lotNumber?.toLowerCase().contains(query) ?? false);
    }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (state.products.isEmpty) {
      return const AppStatePanel(
        icon: Icons.category_outlined,
        title: 'No products yet',
        message: 'Scan or add a product to start this shop’s catalog.',
      );
    }
    if (products.isEmpty) {
      return const AppStatePanel(
        icon: Icons.search_off_outlined,
        title: 'No matching products',
        message: 'Try a product name, brand, or lot number.',
      );
    }

    return Column(
      children: [
        for (var index = 0; index < products.length; index++) ...[
          _InventoryRow(
            product: products[index],
            batches: state.dashboard.items
                .where((item) => item.productId == products[index].id)
                .toList(),
          ),
          if (index < products.length - 1) const Divider(height: 1, indent: 72),
        ],
      ],
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.product, required this.batches});

  final Product product;
  final List<ExpiryDashboardItem> batches;

  @override
  Widget build(BuildContext context) {
    batches.sort((a, b) => (a.daysToExpiry ?? 999999).compareTo(b.daysToExpiry ?? 999999));
    final status = batches.isEmpty ? null : expiryStatusForDays(batches.first.daysToExpiry);
    final tone = status?.tone ?? AppStatusTone.neutral;
    return Semantics(
      label: '${product.name}, ${status?.label ?? 'no active batch'}',
      child: ListTile(
        leading: ShopProductImage(
          shopId: product.shopId,
          productId: product.id,
          imageUrl: product.imageUrl,
          size: 48,
        ),
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batches.isEmpty
                    ? product.brand ?? 'No active batch'
                    : '${product.brand == null ? '' : '${product.brand} · '}${batches.length} active ${batches.length == 1 ? 'batch' : 'batches'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppStatusChip(label: status?.label ?? 'No active batch', tone: tone),
            ],
          ),
        ),
        isThreeLine: true,
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(productId: product.id)),
        ),
      ),
    );
  }
}
