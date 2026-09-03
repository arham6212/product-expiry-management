import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/storefront_models.dart';
import '../../auth/presentation/authenticated_shop_gate.dart';
import '../application/public_storefront_controller.dart';
import 'shop_storefront_page.dart';

class ExploreShopsPage extends ConsumerWidget {
  const ExploreShopsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(publicShopsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore shops'),
        actions: [
          TextButton.icon(
            key: const Key('openShopOperationsButton'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AuthenticatedShopGate(enableStorefront: true),
              ),
            ),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Shop operations'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: switch (shops) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError() => _PublicError(
            message: 'Shops could not be loaded. Check your connection and try again.',
            onRetry: () => ref.read(publicShopsProvider.notifier).retry(),
          ),
          AsyncData(:final value) when value.isEmpty => const _EmptyExplore(),
          AsyncData(:final value) => _ShopList(shops: value),
        },
      ),
    );
  }
}

class _ShopList extends StatelessWidget {
  const _ShopList({required this.shops});

  final List<PublicShopProfile> shops;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('publicShopList'),
      padding: const EdgeInsets.all(20),
      itemCount: shops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final shop = shops[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => ShopStorefrontPage(shopId: shop.shopId)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _ShopLogo(profile: shop),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop.displayName, style: Theme.of(context).textTheme.titleLarge),
                        if (shop.area != null) ...[
                          const SizedBox(height: 4),
                          Text(shop.area!, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        if (shop.description != null) ...[
                          const SizedBox(height: 8),
                          Text(shop.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShopLogo extends StatelessWidget {
  const _ShopLogo({required this.profile});

  final PublicShopProfile profile;

  @override
  Widget build(BuildContext context) {
    final url = profile.logoUrl;
    if (url == null) {
      return CircleAvatar(radius: 28, child: Text(profile.displayName.characters.first));
    }
    return CircleAvatar(
      radius: 28,
      backgroundImage: NetworkImage(url.toString()),
      onBackgroundImageError: (_, _) {},
    );
  }
}

class _EmptyExplore extends StatelessWidget {
  const _EmptyExplore();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 56),
            SizedBox(height: 16),
            Text(
              'No public shops yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Enabled storefronts will appear here.'),
          ],
        ),
      ),
    );
  }
}

class _PublicError extends StatelessWidget {
  const _PublicError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
