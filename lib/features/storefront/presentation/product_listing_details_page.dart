import 'package:flutter/material.dart';

import '../../../domain/entities/storefront_models.dart';
import 'storefront_format.dart';

class ProductListingDetailsPage extends StatelessWidget {
  const ProductListingDetailsPage({required this.listing, this.deal, super.key});

  final PublishedProductListing listing;
  final Deal? deal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product details')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (listing.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                listing.imageUrl.toString(),
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const SizedBox(height: 160, child: Icon(Icons.broken_image_outlined, size: 56)),
              ),
            )
          else
            const SizedBox(height: 140, child: Icon(Icons.shopping_basket_outlined, size: 64)),
          const SizedBox(height: 24),
          Text(listing.displayName, style: Theme.of(context).textTheme.headlineSmall),
          if (listing.description != null) ...[
            const SizedBox(height: 10),
            Text(listing.description!),
          ],
          const SizedBox(height: 20),
          if (deal == null)
            Text(
              formatMinorPrice(listing.priceMinor, listing.currencyCode),
              style: Theme.of(context).textTheme.headlineSmall,
            )
          else
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal!.title ?? 'Current deal',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (deal!.description != null) ...[
                      const SizedBox(height: 6),
                      Text(deal!.description!),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      formatMinorPrice(listing.priceMinor, listing.currencyCode),
                      style: const TextStyle(decoration: TextDecoration.lineThrough),
                    ),
                    Text(
                      formatMinorPrice(deal!.offerPriceMinor, listing.currencyCode),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('Offer ends ${formatDealDate(deal!.endsAt)}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Prices are published by the shop. Availability is not guaranteed and is not based on private inventory quantities.',
          ),
        ],
      ),
    );
  }
}
