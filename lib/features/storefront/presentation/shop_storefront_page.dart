import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/storefront_models.dart';
import '../application/public_storefront_controller.dart';
import 'product_listing_details_page.dart';
import 'storefront_format.dart';

class ShopStorefrontPage extends ConsumerWidget {
  const ShopStorefrontPage({required this.shopId, super.key});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storefront = ref.watch(publicStorefrontProvider(shopId));
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (storefront) {
          AsyncData(:final value) => value.profile.displayName,
          _ => 'Storefront',
        }),
      ),
      body: SafeArea(
        child: switch (storefront) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError() => _StorefrontError(
            onRetry: () => ref.read(publicStorefrontProvider(shopId).notifier).retry(),
          ),
          AsyncData(:final value) => _StorefrontBody(
            state: value,
            onSearch: ref.read(publicStorefrontProvider(shopId).notifier).search,
          ),
        },
      ),
    );
  }
}

class _StorefrontBody extends StatelessWidget {
  const _StorefrontBody({required this.state, required this.onSearch});

  final PublicStorefrontState state;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final listings = state.visibleListings;
    return CustomScrollView(
      key: const Key('storefrontScrollView'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.profile.displayName, style: Theme.of(context).textTheme.headlineMedium),
                if (state.profile.area != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 4),
                      Text(state.profile.area!),
                    ],
                  ),
                ],
                if (state.profile.description != null) ...[
                  const SizedBox(height: 10),
                  Text(state.profile.description!),
                ],
                const SizedBox(height: 20),
                TextField(
                  key: const Key('publicProductSearchField'),
                  onChanged: onSearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search this shop',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Deals', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (state.deals.isEmpty)
                  const _InlineEmpty(
                    key: Key('noDealsState'),
                    icon: Icons.local_offer_outlined,
                    message: 'No deals are active right now.',
                  )
                else
                  SizedBox(
                    height: 156,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.deals.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final deal = state.deals[index];
                        final listing = state.listings
                            .where((candidate) => candidate.id == deal.listingId)
                            .firstOrNull;
                        if (listing == null) return const SizedBox.shrink();
                        return _DealCard(listing: listing, deal: deal);
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Products', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        if (state.listings.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _InlineEmpty(
              key: Key('emptyStorefrontState'),
              icon: Icons.inventory_2_outlined,
              message: 'This shop has not published any products yet.',
            ),
          )
        else if (listings.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _InlineEmpty(
              key: Key('productSearchEmptyState'),
              icon: Icons.search_off,
              message: 'No products match your search.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.separated(
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final listing = listings[index];
                return _ProductCard(listing: listing, deal: state.activeDealFor(listing.id));
              },
            ),
          ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.listing, required this.deal});

  final PublishedProductListing listing;
  final Deal? deal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: _ProductImage(url: listing.imageUrl),
        title: Text(listing.displayName),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: deal == null
              ? Text(formatMinorPrice(listing.priceMinor, listing.currencyCode))
              : Row(
                  children: [
                    Text(
                      formatMinorPrice(listing.priceMinor, listing.currencyCode),
                      style: const TextStyle(decoration: TextDecoration.lineThrough),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMinorPrice(deal!.offerPriceMinor, listing.currencyCode),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ProductListingDetailsPage(listing: listing, deal: deal),
          ),
        ),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.listing, required this.deal});

  final PublishedProductListing listing;
  final Deal deal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ProductListingDetailsPage(listing: listing, deal: deal),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.local_offer_outlined),
                const Spacer(),
                Text(
                  deal.title ?? listing.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(listing.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(
                  formatMinorPrice(deal.offerPriceMinor, listing.currencyCode),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final Uri? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const SizedBox.square(dimension: 52, child: Icon(Icons.shopping_basket_outlined));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url.toString(),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const SizedBox.square(dimension: 52, child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 38), const SizedBox(height: 8), Text(message)],
        ),
      ),
    );
  }
}

class _StorefrontError extends StatelessWidget {
  const _StorefrontError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This storefront could not be loaded.'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
