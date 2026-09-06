import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/product_image_contribution.dart';
import '../application/product_image_controller.dart';

class ProductImageCard extends ConsumerWidget {
  const ProductImageCard({
    required this.shopId,
    required this.productId,
    this.imageUrl,
    this.uploadEnabled = true,
    this.compact = false,
    super.key,
  });
  final String shopId;
  final String productId;
  final Uri? imageUrl;
  final bool uploadEnabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ProductImageTarget(shopId: shopId, productId: productId);
    final state = ref.watch(productImageControllerProvider(target));
    final controller = ref.read(productImageControllerProvider(target).notifier);
    final savedUrl = ref.watch(savedShopPhotosProvider.select((photos) => photos[target]));
    final submitted = state.contribution != null;
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: state.selected == null
          ? _RemoteProductImage(imageUrl: savedUrl ?? imageUrl)
          : Image.memory(
              state.selected!.bytes,
              key: const Key('selectedProductImage'),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
    );
    final status = switch (state.stage) {
      ProductImageStage.selecting => 'Opening photos…',
      ProductImageStage.processing => 'Preparing photo…',
      ProductImageStage.uploading => 'Uploading…',
      ProductImageStage.error => state.message,
      ProductImageStage.success => 'Saved to your shop',
      _ => null,
    };
    return _frame(
      context,
      preview,
      Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.stage == ProductImageStage.uploading)
              const LinearProgressIndicator(key: Key('productImageUploadProgress')),
            if (status != null) Text(status),
          ],
        ),
      ),
      Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            key: const Key('chooseProductImageButton'),
            onPressed: state.isBusy || !uploadEnabled
                ? null
                : () => _chooseSource(context, controller),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(
              savedUrl != null || imageUrl != null || state.selected != null
                  ? 'Change photo'
                  : 'Add photo',
            ),
          ),
          if (state.selected != null && !submitted && !state.isBusy) ...[
            if (state.stage == ProductImageStage.error)
              TextButton(
                key: const Key('uploadProductImageButton'),
                onPressed: uploadEnabled ? controller.upload : null,
                child: const Text('Retry upload'),
              ),
            IconButton(
              key: const Key('removeSelectedProductImageButton'),
              tooltip: 'Remove local photo',
              onPressed: controller.removeSelection,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _frame(BuildContext context, Widget preview, Widget status, Widget? actions) => Padding(
    key: const Key('productImageCard'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        preview,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?actions,
              DefaultTextStyle(style: Theme.of(context).textTheme.bodySmall!, child: status),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _chooseSource(BuildContext context, ProductImageController controller) async {
    final source = await showModalBottomSheet<ProductImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              key: const Key('takeProductPhotoOption'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ProductImageSource.camera),
            ),
            ListTile(
              key: const Key('chooseProductPhotoOption'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ProductImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && context.mounted) {
      await controller.selectAndUpload(source);
    }
  }
}

class _RemoteProductImage extends StatelessWidget {
  const _RemoteProductImage({required this.imageUrl});
  final Uri? imageUrl;
  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) return const _ImagePlaceholder();
    return Image.network(
      imageUrl.toString(),
      key: const Key('savedProductImage'),
      width: 72,
      height: 72,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const SizedBox.square(dimension: 72, child: Center(child: CircularProgressIndicator())),
      errorBuilder: (_, _, _) => const _ImagePlaceholder(label: 'Image unavailable'),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.label = 'No product photo'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('productImagePlaceholder'),
    width: 72,
    height: 72,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Semantics(label: label, child: const Icon(Icons.image_outlined, size: 24)),
  );
}
