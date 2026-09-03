import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/domain_models.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/home/presentation/home_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/inventory/presentation/receive_stock_page.dart';
import '../features/product_resolution/presentation/product_resolution_page.dart';
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
      HomePage(shopName: activeShop.shop.name),
      InventoryPage(shopId: activeShop.shop.id),
      const SizedBox(),
      const Center(child: Text('Alerts')),
      _AccountPage(shopName: activeShop.shop.name, enableStorefront: enableStorefront),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _resolveAndReceive(context, activeShop.shop.id),
        backgroundColor: const Color(0xFF167D68),
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            _NavItem(index: 0, icon: Icons.home, label: 'Home'),
            _NavItem(index: 1, icon: Icons.inventory_2_outlined, label: 'Inventory'),
            SizedBox(width: 48),
            _NavItem(index: 3, icon: Icons.notifications_none, label: 'Alerts'),
            _NavItem(index: 4, icon: Icons.menu, label: 'More'),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveAndReceive(BuildContext context, String shopId) async {
    final product = await Navigator.of(
      context,
    ).push<Product>(MaterialPageRoute<Product>(builder: (_) => const ProductResolutionPage()));
    if (!context.mounted || product == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveStockPage(shopId: shopId, initialProduct: product),
      ),
    );
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
    final color = isSelected ? const Color(0xFF167D68) : Colors.black54;

    return InkWell(
      onTap: () => ref.read(shellNavigationProvider.notifier).select(index),
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(24),
        children: [
          Text('More', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: Text(shopName),
            subtitle: const Text('Current shop'),
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
              subtitle: const Text('Publish products, prices, and deals'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const StorefrontManagementPage()),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Team & Access'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push<void>(MaterialPageRoute<void>(builder: (_) => const ShopMembersScreen()));
            },
          ),
          if (shops.length > 1)
            OutlinedButton(
              key: const Key('changeShopButton'),
              onPressed: () {
                ref.read(shopSessionControllerProvider.notifier).chooseAnotherShop();
              },
              child: const Text('Change shop'),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('signOutButton'),
            onPressed: signOut.isSubmitting
                ? null
                : () => ref.read(signOutControllerProvider.notifier).signOut(),
            child: Text(signOut.isSubmitting ? 'Signing out...' : 'Sign out'),
          ),
          if (signOut.error != null) ...[const SizedBox(height: 12), Text(signOut.error!)],
        ],
      ),
    );
  }
}
