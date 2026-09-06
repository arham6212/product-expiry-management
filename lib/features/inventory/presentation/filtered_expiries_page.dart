import 'package:flutter/material.dart';

import '../../../design_system/components/app_components.dart';
import '../../../design_system/theme/app_tokens.dart';
import '../application/expiry_dashboard.dart';

class FilteredExpiriesPage extends StatelessWidget {
  const FilteredExpiriesPage({
    required this.title,
    required this.items,
    required this.accentColor,
    super.key,
  });

  final String title;
  final List<ExpiryDashboardItem> items;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          return _FilteredExpiryItemCard(item: item, accentColor: accentColor);
        },
      ),
    );
  }
}

class _FilteredExpiryItemCard extends StatelessWidget {
  const _FilteredExpiryItemCard({required this.item, required this.accentColor});

  final ExpiryDashboardItem item;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expiryText = item.expiryDate == null
        ? 'Expiry date not recorded'
        : 'Expires ${item.expiryDate}';
    return Semantics(
      label: '${item.productName}, $expiryText, quantity ${item.quantityLabel}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName, style: Theme.of(context).textTheme.titleSmall),
            if (item.productBrand != null) ...[
              const SizedBox(height: 2),
              Text(
                item.productBrand!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: AppStatusChip(
                label: expiryText,
                tone: item.daysToExpiry == null
                    ? AppStatusTone.neutral
                    : item.daysToExpiry! < 0
                    ? AppStatusTone.critical
                    : item.daysToExpiry == 0
                    ? AppStatusTone.warning
                    : item.daysToExpiry! <= 7
                    ? AppStatusTone.caution
                    : AppStatusTone.positive,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _ItemFact(icon: Icons.inventory_2_outlined, text: 'Quantity ${item.quantityLabel}'),
                if (item.lotNumber != null)
                  _ItemFact(icon: Icons.tag_outlined, text: 'Lot ${item.lotNumber}'),
                _ItemFact(
                  icon: Icons.move_to_inbox_outlined,
                  text: 'Received ${_formatUtcDate(item.receivedAt)} UTC',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemFact extends StatelessWidget {
  const _ItemFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ),
      ],
    );
  }
}

String _formatUtcDate(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
}
