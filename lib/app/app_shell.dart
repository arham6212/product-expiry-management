import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/components/app_components.dart';
import '../design_system/theme/app_tokens.dart';
import '../domain/entities/domain_models.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/home/presentation/home_page.dart';
import '../features/inventory/application/expiry_dashboard.dart';
import '../features/inventory/application/expiry_dashboard_controller.dart';
import '../features/inventory/application/inventory_catalog_controller.dart';
import '../features/inventory/presentation/expiry_status.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/inventory/presentation/product_details_page.dart';
import '../features/inventory/presentation/scan_receive_workflow.dart';
import '../features/shops/application/shop_access.dart';
import '../features/shops/application/shop_session_controller.dart';
import '../features/shops/presentation/shop_members_screen.dart';
import '../features/storefront/presentation/storefront_management_page.dart';
import 'app_shell_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.enableStorefront, super.key});

  final bool enableStorefront;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeShop = ref.watch(activeShopProvider);
    if (activeShop == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedIndex = ref.watch(shellNavigationProvider);
    final pages = <Widget>[
      const HomePage(),
      InventoryPage(shopId: activeShop.shop.id, currencyCode: activeShop.shop.currencyCode),
      const SizedBox(),
      const _AlertsPage(),
      _AccountPage(shopName: activeShop.shop.name, enableStorefront: enableStorefront),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      floatingActionButton: FloatingActionButton(
        key: const Key('scanProductFab'),
        tooltip: 'Scan product',
        onPressed: () =>
            _resolveAndReceive(context, activeShop.shop.id, activeShop.shop.currencyCode),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            _NavItem(index: 0, icon: Icons.home, label: 'Home'),
            _NavItem(index: 1, icon: Icons.inventory_2_outlined, label: 'Inventory'),
            SizedBox(width: 48),
            _NavItem(index: 3, icon: Icons.notifications_none, label: 'Alerts'),
            _NavItem(index: 4, icon: Icons.person_outline, label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveAndReceive(BuildContext context, String shopId, String currencyCode) async {
    await openScanReceiveWorkflow(context, shopId: shopId, currencyCode: currencyCode);
  }
}

class _NavItem extends ConsumerWidget {
  const _NavItem({required this.index, required this.icon, required this.label});

  final int index;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = ref.watch(shellNavigationProvider) == index;
    final colors = Theme.of(context).colorScheme;
    final color = isSelected ? colors.primary : colors.onSurfaceVariant;

    return InkWell(
      onTap: () => ref.read(shellNavigationProvider.notifier).select(index),
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountPage extends ConsumerWidget {
  const _AccountPage({required this.shopName, required this.enableStorefront});

  final String shopName;
  final bool enableStorefront;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signOut = ref.watch(signOutControllerProvider);
    final session = ref.watch(shopSessionControllerProvider).value;
    final shops = session?.shops ?? const <ShopAccess>[];
    final role = session?.activeShop?.membership.role;
    final canManageStorefront =
        role == ShopMembershipRole.owner || role == ShopMembershipRole.manager;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 104),
        children: [
          const AppPageHeader(title: 'Shop & profile'),
          const SizedBox(height: AppSpacing.lg),
          Column(
            children: [
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: Text(shopName),
                subtitle: Text(
                  [
                    session?.activeShop?.shop.currencyCode,
                    role?.name,
                  ].whereType<String>().join(' · '),
                ),
              ),
              if (enableStorefront)
                ListTile(
                  key: const Key('browsePublicShopsTile'),
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('Browse public shops'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              if (enableStorefront && canManageStorefront)
                ListTile(
                  key: const Key('manageStorefrontTile'),
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Public Storefront'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const StorefrontManagementPage()),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Team & access'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push<void>(MaterialPageRoute<void>(builder: (_) => const ShopMembersScreen())),
              ),
            ],
          ),
          if (shops.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const Key('changeShopButton'),
              onPressed: () {
                ref.read(shopSessionControllerProvider.notifier).chooseAnotherShop();
              },
              child: const Text('Change shop'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            icon: const Icon(Icons.logout),
            key: const Key('signOutButton'),
            onPressed: signOut.isSubmitting
                ? null
                : () => ref.read(signOutControllerProvider.notifier).signOut(),
            label: Text(signOut.isSubmitting ? 'Signing out...' : 'Sign out'),
          ),
          if (signOut.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(signOut.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _AlertsPage extends ConsumerWidget {
  const _AlertsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(inventoryCatalogProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 104),
        children: [
          const AppPageHeader(title: 'Alerts', subtitle: 'Expiry issues that need a decision.'),
          const SizedBox(height: AppSpacing.lg),
          switch (catalog) {
            AsyncData(:final value)
                when value.dashboard.expired.isEmpty &&
                    value.dashboard.expiresToday.isEmpty &&
                    value.dashboard.next7Days.isEmpty =>
              const AppStatePanel(
                icon: Icons.check_circle_outline,
                title: 'Nothing urgent',
                message: 'No batches are expired or approaching expiry in the next 7 days.',
              ),
            AsyncData(:final value) => _AlertList(state: value.dashboard),
            AsyncError() => AppStatePanel(
              icon: Icons.cloud_off_outlined,
              title: 'Alerts could not be loaded',
              message: 'Check the connection and try again.',
              actionLabel: 'Try again',
              onAction: () => ref.read(inventoryCatalogActionsProvider).retry(),
            ),
            _ => const AppStatePanel(
              icon: Icons.notifications_outlined,
              title: 'Checking alerts',
              message: 'Loading urgent expiry items.',
              showProgress: true,
            ),
          },
        ],
      ),
    );
  }
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.state});

  final ExpiryDashboardState state;

  @override
  Widget build(BuildContext context) {
    final items = sortedExpiryAlerts([...state.expired, ...state.expiresToday, ...state.next7Days]);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _AlertRow(item: items[index]),
            if (index < items.length - 1) const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.item});

  final ExpiryDashboardItem item;

  @override
  Widget build(BuildContext context) {
    final status = expiryStatusForDays(item.daysToExpiry);
    final icon = item.daysToExpiry != null && item.daysToExpiry! < 0
        ? Icons.error_outline
        : item.daysToExpiry == 0
        ? Icons.today_outlined
        : Icons.date_range_outlined;
    return Semantics(
      label: '${item.productName}, ${status.label}, quantity ${item.quantityLabel}',
      button: true,
      child: ListTile(
        key: Key('alert-${item.batchId}'),
        leading: Icon(icon, color: status.color),
        title: Text(item.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.expiryDate == null ? 'Expiry not recorded' : 'Expires ${item.expiryDate}'} · Qty ${item.quantityLabel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppStatusChip(label: status.label, tone: status.tone),
            ],
          ),
        ),
        isThreeLine: true,
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProductDetailsPage(productId: item.productId, highlightBatchId: item.batchId),
          ),
        ),
      ),
    );
  }
}
