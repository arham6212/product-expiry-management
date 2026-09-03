import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/storefront_models.dart';
import '../application/storefront_management_controller.dart';
import '../application/storefront_repository.dart';
import 'storefront_format.dart';

class StorefrontManagementPage extends ConsumerWidget {
  const StorefrontManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storefrontManagementProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Public Storefront')),
      body: SafeArea(
        child: switch (state) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => _ManagementError(
            message: error is Exception
                ? error.toString().replaceFirst(RegExp(r'^.*Exception: '), '')
                : 'Storefront could not be loaded.',
            onRetry: () => ref.read(storefrontManagementProvider.notifier).retry(),
          ),
          AsyncData(:final value) => _ManagementBody(state: value),
        },
      ),
    );
  }
}

class _ManagementBody extends ConsumerWidget {
  const _ManagementBody({required this.state});

  final StorefrontManagementState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(storefrontManagementProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  key: const Key('storefrontEnabledSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public storefront'),
                  subtitle: Text(
                    state.profile.isEnabled
                        ? 'Customers can discover this shop.'
                        : 'Only owners and managers can see this draft.',
                  ),
                  value: state.profile.isEnabled,
                  onChanged: state.isSaving
                      ? null
                      : (enabled) => controller.saveProfile(
                          _profileDraft(state.profile, isEnabled: enabled),
                        ),
                ),
                const Divider(),
                Text(state.profile.displayName, style: Theme.of(context).textTheme.titleLarge),
                if (state.profile.area != null) Text(state.profile.area!),
                if (state.profile.description != null) ...[
                  const SizedBox(height: 8),
                  Text(state.profile.description!),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('editStorefrontProfileButton'),
                  onPressed: state.isSaving
                      ? null
                      : () async {
                          final draft = await showDialog<PublicShopProfileDraft>(
                            context: context,
                            builder: (_) => _ProfileDialog(profile: state.profile),
                          );
                          if (draft != null) await controller.saveProfile(draft);
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit public details'),
                ),
              ],
            ),
          ),
        ),
        if (state.actionError != null) ...[
          const SizedBox(height: 12),
          Text(
            state.actionError!,
            key: const Key('storefrontActionError'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        Text('Published products', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Publishing never exposes batches, expiry dates, quantities, or costs.'),
        const SizedBox(height: 12),
        if (state.products.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Add inventory Products before publishing a storefront listing.'),
            ),
          )
        else
          for (final product in state.products) ...[
            _ProductManagementCard(product: product, state: state),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ProductManagementCard extends ConsumerWidget {
  const _ProductManagementCard({required this.product, required this.state});

  final Product product;
  final StorefrontManagementState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = state.listingForProduct(product.id);
    final deals = listing == null ? const <Deal>[] : state.dealsForListing(listing.id);
    final controller = ref.read(storefrontManagementProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(product.name),
              subtitle: Text(
                listing == null
                    ? 'Not configured'
                    : '${formatMinorPrice(listing.priceMinor, listing.currencyCode)} · ${listing.isPublished ? 'Published' : 'Unpublished'}',
              ),
              value: listing?.isPublished ?? false,
              onChanged: state.isSaving
                  ? null
                  : (published) async {
                      if (listing == null) {
                        if (!published) return;
                        await _editListing(
                          context,
                          controller,
                          product,
                          state.currencyCode,
                          null,
                          publishOnCreate: true,
                        );
                        return;
                      }
                      await controller.saveListing(
                        PublishedListingDraft(
                          productId: product.id,
                          displayName: listing.displayName,
                          description: listing.description,
                          imageUrl: listing.imageUrl,
                          priceMinor: listing.priceMinor,
                          currencyCode: listing.currencyCode,
                          isPublished: published,
                        ),
                      );
                    },
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.isSaving
                      ? null
                      : () => _editListing(
                          context,
                          controller,
                          product,
                          state.currencyCode,
                          listing,
                          publishOnCreate: false,
                        ),
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(listing == null ? 'Set price' : 'Edit listing'),
                ),
                if (listing?.isPublished == true) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: Key('createDeal-${product.id}'),
                    onPressed: state.isSaving
                        ? null
                        : () => _editDeal(context, controller, listing!, null),
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('New deal'),
                  ),
                ],
              ],
            ),
            if (deals.isNotEmpty) ...[
              const Divider(height: 24),
              for (final deal in deals)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(deal.title ?? 'Deal'),
                  subtitle: Text(
                    '${formatMinorPrice(deal.offerPriceMinor, listing!.currencyCode)} · '
                    '${formatDealDate(deal.startsAt)}–${formatDealDate(deal.endsAt)}',
                  ),
                  leading: Icon(deal.isEnabled ? Icons.local_offer : Icons.local_offer_outlined),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await _editDeal(context, controller, listing, deal);
                      } else {
                        await controller.setDealEnabled(deal, !deal.isEnabled);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(deal.isEnabled ? 'Deactivate' : 'Activate'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _editListing(
  BuildContext context,
  StorefrontManagementController controller,
  Product product,
  String currencyCode,
  PublishedProductListing? listing, {
  required bool publishOnCreate,
}) async {
  final draft = await showDialog<PublishedListingDraft>(
    context: context,
    builder: (_) => _ListingDialog(
      product: product,
      currencyCode: currencyCode,
      listing: listing,
      publishOnCreate: publishOnCreate,
    ),
  );
  if (draft != null) await controller.saveListing(draft);
}

Future<void> _editDeal(
  BuildContext context,
  StorefrontManagementController controller,
  PublishedProductListing listing,
  Deal? deal,
) async {
  final draft = await showDialog<DealDraft>(
    context: context,
    builder: (_) => _DealDialog(listing: listing, deal: deal),
  );
  if (draft != null) await controller.saveDeal(draft, dealId: deal?.id);
}

PublicShopProfileDraft _profileDraft(PublicShopProfile profile, {required bool isEnabled}) {
  return PublicShopProfileDraft(
    displayName: profile.displayName,
    description: profile.description,
    logoUrl: profile.logoUrl,
    area: profile.area,
    isEnabled: isEnabled,
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile});

  final PublicShopProfile profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _description = TextEditingController(text: widget.profile.description);
  late final _area = TextEditingController(text: widget.profile.area);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Public shop details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _area,
              decoration: const InputDecoration(labelText: 'Area'),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              PublicShopProfileDraft(
                displayName: _name.text,
                description: _description.text,
                area: _area.text,
                logoUrl: widget.profile.logoUrl,
                isEnabled: widget.profile.isEnabled,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ListingDialog extends StatefulWidget {
  const _ListingDialog({
    required this.product,
    required this.currencyCode,
    required this.listing,
    required this.publishOnCreate,
  });

  final Product product;
  final String currencyCode;
  final PublishedProductListing? listing;
  final bool publishOnCreate;

  @override
  State<_ListingDialog> createState() => _ListingDialogState();
}

class _ListingDialogState extends State<_ListingDialog> {
  late final _name = TextEditingController(
    text: widget.listing?.displayName ?? widget.product.name,
  );
  late final _description = TextEditingController(text: widget.listing?.description);
  late final _price = TextEditingController(
    text: widget.listing == null ? '' : (widget.listing!.priceMinor / 100).toStringAsFixed(2),
  );
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Public product listing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Public name'),
            ),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              key: const Key('listingPriceField'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Price (${widget.currencyCode})'),
            ),
            if (error != null)
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final price = parseMajorPriceToMinor(_price.text);
            if (_name.text.trim().isEmpty || price == null || price <= 0) {
              setState(() => error = 'Enter a name and a valid price above zero.');
              return;
            }
            Navigator.pop(
              context,
              PublishedListingDraft(
                productId: widget.product.id,
                displayName: _name.text,
                description: _description.text,
                imageUrl: widget.listing?.imageUrl ?? widget.product.imageUrl,
                priceMinor: price,
                currencyCode: widget.currencyCode,
                isPublished: widget.listing?.isPublished ?? widget.publishOnCreate,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DealDialog extends StatefulWidget {
  const _DealDialog({required this.listing, this.deal});

  final PublishedProductListing listing;
  final Deal? deal;

  @override
  State<_DealDialog> createState() => _DealDialogState();
}

class _DealDialogState extends State<_DealDialog> {
  late final _title = TextEditingController(text: widget.deal?.title);
  late final _description = TextEditingController(text: widget.deal?.description);
  late final _price = TextEditingController(
    text: widget.deal == null ? '' : (widget.deal!.offerPriceMinor / 100).toStringAsFixed(2),
  );
  late DateTime startsAt = widget.deal?.startsAt ?? DateTime.now().toUtc();
  late DateTime endsAt = widget.deal?.endsAt ?? DateTime.now().toUtc().add(const Duration(days: 7));
  String? error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.deal == null ? 'Create deal' : 'Edit deal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.listing.displayName),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              key: const Key('dealOfferPriceField'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Offer price (${widget.listing.currencyCode})',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts'),
              subtitle: Text(formatDealDate(startsAt)),
              onTap: () => _pickDate(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends'),
              subtitle: Text(formatDealDate(endsAt)),
              onTap: () => _pickDate(isStart: false),
            ),
            if (error != null)
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final offer = parseMajorPriceToMinor(_price.text);
            if (offer == null ||
                offer <= 0 ||
                offer >= widget.listing.priceMinor ||
                !endsAt.isAfter(startsAt)) {
              setState(() => error = 'Enter an offer below normal price and a valid date range.');
              return;
            }
            Navigator.pop(
              context,
              DealDraft(
                listingId: widget.listing.id,
                offerPriceMinor: offer,
                startsAt: startsAt,
                endsAt: endsAt,
                isEnabled: widget.deal?.isEnabled ?? true,
                title: _title.text,
                description: _description.text,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = (isStart ? startsAt : endsAt).toLocal();
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      final next = DateTime(
        selected.year,
        selected.month,
        selected.day,
        isStart ? 0 : 23,
        isStart ? 0 : 59,
      ).toUtc();
      if (isStart) {
        startsAt = next;
      } else {
        endsAt = next;
      }
    });
  }
}

class _ManagementError extends StatelessWidget {
  const _ManagementError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
