import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../../inventory/application/expiry_dashboard.dart';
import '../../product_resolution/presentation/shop_product_image.dart';
import '../../inventory/application/expiry_dashboard_controller.dart';
import '../../inventory/presentation/filtered_expiries_page.dart';
import '../../inventory/presentation/product_details_page.dart';
import '../../inventory/presentation/scan_receive_workflow.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_members_controller.dart';
import '../../shops/application/shop_session_controller.dart';
import '../../shops/presentation/shop_members_screen.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeShop = ref.watch(activeShopProvider);
    if (activeShop == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dashboard = ref.watch(expiryDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _HomeAppBar(activeShop: activeShop),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  104,
                ),
                sliver: SliverList.list(
                  children: [
                    _WelcomeHeader(activeShop: activeShop),
                    const SizedBox(height: AppSpacing.lg),
                    switch (dashboard) {
                      AsyncData(:final value) => _DashboardContent(
                        state: value,
                        activeShop: activeShop,
                      ),
                      AsyncError() => AppStatePanel(
                        icon: Icons.cloud_off_outlined,
                        title: 'Could not load dashboard',
                        message:
                            'Check the connection and try again. Your inventory was not changed.',
                        actionLabel: 'Retry',
                        onAction: () => _retry(ref),
                      ),
                      _ => const AppStatePanel(
                        icon: Icons.inventory_2_outlined,
                        title: 'Checking your stock',
                        message: 'Loading expiry priorities for this shop.',
                        showProgress: true,
                      ),
                    },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    try {
      await ref.read(expiryDashboardActionsProvider).refresh();
    } catch (_) {}
  }

  Future<void> _retry(WidgetRef ref) => _refresh(ref);
}

class _HomeAppBar extends ConsumerWidget {
  const _HomeAppBar({required this.activeShop});

  final ShopAccess activeShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(shopSessionControllerProvider).value?.shops ?? const <ShopAccess>[];
    final pendingCount = ref
        .watch(shopMembersControllerProvider)
        .maybeWhen(data: (state) => state.pendingRequests.length, orElse: () => 0);
    return SliverAppBar(
      pinned: true,
      titleSpacing: AppSpacing.md,
      title: Semantics(
        button: shops.length > 1,
        label: 'Current shop, ${activeShop.shop.name}',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          onTap: shops.length > 1
              ? () => ref.read(shopSessionControllerProvider.notifier).chooseAnotherShop()
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    activeShop.shop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (shops.length > 1) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  const Icon(Icons.expand_more),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (pendingCount > 0)
          Badge(
            isLabelVisible: pendingCount > 0,
            label: Text('$pendingCount'),
            child: IconButton(
              tooltip: pendingCount > 0
                  ? '$pendingCount pending team requests'
                  : 'No pending requests',
              onPressed: pendingCount > 0
                  ? () => Navigator.of(
                      context,
                    ).push<void>(MaterialPageRoute<void>(builder: (_) => const ShopMembersScreen()))
                  : null,
              icon: const Icon(Icons.notifications_outlined),
            ),
          ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.activeShop});

  final ShopAccess activeShop;

  @override
  Widget build(BuildContext context) {
    return AppPageHeader(
      title: 'Stock priorities',
      trailing: FilledButton.icon(
        key: const Key('scanProductHomeButton'),
        onPressed: () => _resolveAndReceive(context, activeShop),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan'),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.state, required this.activeShop});

  final ExpiryDashboardState state;
  final ShopAccess activeShop;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return Column(
        children: [
          AppStatePanel(
            icon: Icons.inventory_2_outlined,
            title: 'Start tracking expiries',
            message: 'Scan your first product. New stock will appear here by urgency.',
            actionLabel: 'Scan product',
            onAction: () => _resolveAndReceive(context, activeShop),
          ),
        ],
      );
    }

    final urgent = <ExpiryDashboardItem>[
      ...state.expired,
      ...state.expiresToday,
      ...state.next7Days,
    ]..sort((a, b) => (a.daysToExpiry ?? 9999).compareTo(b.daysToExpiry ?? 9999));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PriorityGrid(state: state),
        const SizedBox(height: AppSpacing.lg),
        if (urgent.isNotEmpty) ...[
          AppSectionHeader(
            title: 'Act next',
            subtitle: '${urgent.length} urgent ${urgent.length == 1 ? 'batch' : 'batches'}',
            action: TextButton(
              onPressed: () =>
                  _openExpiryList(context, 'Urgent expiries', urgent, AppColors.expired),
              child: const Text('View all'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < urgent.take(4).length; i++) ...[
                  _ExpiryRow(item: urgent[i]),
                  if (i < urgent.take(4).length - 1) const Divider(height: 1, indent: 72),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (urgent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No urgent expiries. Your stock is up to date.'),
          ),
      ],
    );
  }
}

class _PriorityGrid extends StatelessWidget {
  const _PriorityGrid({required this.state});

  final ExpiryDashboardState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 600
            ? (constraints.maxWidth - AppSpacing.sm * 3) / 4
            : (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _PriorityTile(
              width: width,
              label: 'Expired',
              count: state.expired.length,
              tone: AppStatusTone.critical,
              icon: Icons.error_outline,
              onTap: () => _openExpiryList(context, 'Expired', state.expired, AppColors.expired),
            ),
            _PriorityTile(
              width: width,
              label: 'Expires today',
              count: state.expiresToday.length,
              tone: AppStatusTone.warning,
              icon: Icons.today_outlined,
              onTap: () =>
                  _openExpiryList(context, 'Expiring today', state.expiresToday, AppColors.urgent),
            ),
            _PriorityTile(
              width: width,
              label: 'Next 7 days',
              count: state.next7Days.length,
              tone: AppStatusTone.caution,
              icon: Icons.date_range_outlined,
              onTap: () =>
                  _openExpiryList(context, 'Expiring in 7 days', state.next7Days, AppColors.soon),
            ),
            _PriorityTile(
              width: width,
              label: 'Needs a date',
              count: state.needsDate.length,
              tone: AppStatusTone.neutral,
              icon: Icons.event_busy_outlined,
              onTap: () => _openExpiryList(
                context,
                'Expiry date needed',
                state.needsDate,
                AppColors.unknown,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({
    required this.width,
    required this.label,
    required this.count,
    required this.tone,
    required this.icon,
    required this.onTap,
  });

  final double width;
  final String label;
  final int count;
  final AppStatusTone tone;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = tone.foreground(Theme.of(context).colorScheme);
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: count == 0 ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: foreground),
                    const Spacer(),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: foreground),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(label, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({required this.item});

  final ExpiryDashboardItem item;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _status(item.daysToExpiry);
    return Semantics(
      label: '${item.productName}, $label, quantity ${item.quantityLabel}',
      button: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProductDetailsPage(productId: item.productId, highlightBatchId: item.batchId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ShopProductImage(shopId: item.shopId, productId: item.productId, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${item.productBrand ?? 'Unbranded'} · Qty ${item.quantityLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppStatusChip(label: label, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

(String, AppStatusTone) _status(int? days) {
  if (days == null) return ('Date needed', AppStatusTone.neutral);
  if (days < 0) return ('Expired', AppStatusTone.critical);
  if (days == 0) return ('Today', AppStatusTone.warning);
  if (days <= 7) return ('$days days', AppStatusTone.caution);
  return ('$days days', AppStatusTone.positive);
}

void _openExpiryList(
  BuildContext context,
  String title,
  List<ExpiryDashboardItem> items,
  Color color,
) {
  if (items.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => FilteredExpiriesPage(title: title, items: items, accentColor: color),
    ),
  );
}

Future<void> _resolveAndReceive(BuildContext context, ShopAccess activeShop) async {
  await openScanReceiveWorkflow(
    context,
    shopId: activeShop.shop.id,
    currencyCode: activeShop.shop.currencyCode,
  );
}
