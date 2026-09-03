import 'package:flutter/material.dart';

import 'receive_stock_page.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({required this.shopId, super.key});

  final String shopId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Inventory',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Record a new stock batch without changing stock already on hand.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.add_box_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Receive stock',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select an existing product, then enter quantity, expiry, and an optional lot.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('openReceiveStockButton'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => ReceiveStockPage(shopId: shopId)),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Receive stock'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
