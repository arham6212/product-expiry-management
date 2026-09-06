import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_image_contribution.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_image_controller.dart';

void main() {
  const target = ProductImageTarget(shopId: 'shop-1', productId: 'catalog-1');
  final raw = RawProductImage(bytes: Uint8List.fromList([1, 2, 3]), filename: 'photo.png');
  final processed = ProcessedProductImage(
    bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
    filename: 'photo.jpg',
    mimeType: 'image/jpeg',
  );

  test('cancel returns to idle without an error', () async {
    final picker = _Picker((_) async => null);
    final container = _container(
      picker: picker,
      processor: _Processor(processed),
      repository: _Repository(),
    );
    addTearDown(container.dispose);
    await container
        .read(productImageControllerProvider(target).notifier)
        .select(ProductImageSource.gallery);
    expect(container.read(productImageControllerProvider(target)).stage, ProductImageStage.idle);
    expect(container.read(productImageControllerProvider(target)).message, isNull);
  });

  test('automatic upload preserves success when replacement is cancelled', () async {
    var cancel = false;
    final repository = _Repository();
    final container = _container(
      picker: _Picker((_) async => cancel ? null : raw),
      processor: _Processor(processed),
      repository: repository,
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.selectAndUpload(ProductImageSource.camera);
    expect(repository.calls, 1);
    final success = container.read(productImageControllerProvider(target));
    cancel = true;
    await controller.selectAndUpload(ProductImageSource.gallery);
    expect(container.read(productImageControllerProvider(target)), same(success));
    expect(repository.calls, 1);
  });

  test('automatic upload failure keeps image and explicit retry succeeds', () async {
    final repository = _Repository(failures: 1);
    final container = _container(
      picker: _Picker((_) async => raw),
      processor: _Processor(processed),
      repository: repository,
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.selectAndUpload(ProductImageSource.gallery);
    expect(container.read(productImageControllerProvider(target)).stage, ProductImageStage.error);
    expect(container.read(productImageControllerProvider(target)).selected, same(processed));
    await controller.upload();
    expect(container.read(productImageControllerProvider(target)).stage, ProductImageStage.success);
    expect(repository.calls, 2);
  });

  test('failed replacement does not resubmit an already submitted photo', () async {
    var fail = false;
    final repository = _Repository();
    final container = _container(
      picker: _Picker((_) async {
        if (fail) {
          throw const ProductImageException(
            ProductImageFailureKind.permissionDenied,
            'Permission denied.',
          );
        }
        return raw;
      }),
      processor: _Processor(processed),
      repository: repository,
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.selectAndUpload(ProductImageSource.gallery);
    fail = true;
    await controller.selectAndUpload(ProductImageSource.camera);
    expect(container.read(productImageControllerProvider(target)).selected, same(processed));
    expect(container.read(productImageControllerProvider(target)).contribution, isNotNull);
    await controller.upload();
    expect(repository.calls, 1);
  });

  test('permission denial is explicit and does not call processing', () async {
    final processor = _Processor(processed);
    final container = _container(
      picker: _Picker(
        (_) => throw const ProductImageException(
          ProductImageFailureKind.permissionDenied,
          'Permission denied.',
        ),
      ),
      processor: processor,
      repository: _Repository(),
    );
    addTearDown(container.dispose);
    await container
        .read(productImageControllerProvider(target).notifier)
        .select(ProductImageSource.camera);
    final state = container.read(productImageControllerProvider(target));
    expect(state.stage, ProductImageStage.error);
    expect(state.failureKind, ProductImageFailureKind.permissionDenied);
    expect(processor.calls, 0);
  });

  test('duplicate selection taps are ignored while picker is active', () async {
    final picked = Completer<RawProductImage?>();
    final picker = _Picker((_) => picked.future);
    final container = _container(
      picker: picker,
      processor: _Processor(processed),
      repository: _Repository(),
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    final first = controller.select(ProductImageSource.camera);
    final second = controller.select(ProductImageSource.gallery);
    expect(picker.calls, 1);
    picked.complete(raw);
    await Future.wait([first, second]);
    expect(container.read(productImageControllerProvider(target)).stage, ProductImageStage.ready);
  });

  test('recoverable upload failure retains selection and retry succeeds', () async {
    final repository = _Repository(failures: 1);
    final container = _container(
      picker: _Picker((_) async => raw),
      processor: _Processor(processed),
      repository: repository,
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.select(ProductImageSource.gallery);
    expect(await controller.upload(), isNull);
    var state = container.read(productImageControllerProvider(target));
    expect(state.stage, ProductImageStage.error);
    expect(state.selected, same(processed));
    final result = await controller.upload();
    state = container.read(productImageControllerProvider(target));
    expect(result?.status, 'pending');
    expect(state.stage, ProductImageStage.success);
    expect(repository.calls, 2);
  });

  test('duplicate upload calls are ignored while an upload is active', () async {
    final upload = Completer<ProductImageContribution>();
    final repository = _CompletingRepository(upload);
    final container = _container(
      picker: _Picker((_) async => raw),
      processor: _Processor(processed),
      repository: repository,
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.select(ProductImageSource.gallery);

    final first = controller.upload();
    final second = controller.upload();
    expect(repository.calls, 1);
    expect(await second, isNull);
    upload.complete(
      ProductImageContribution(
        id: 'contribution-1',
        status: 'pending',
        deliveryUrl: Uri.parse('https://res.cloudinary.com/demo/image/upload/photo.jpg'),
      ),
    );
    await first;
    expect(await controller.upload(), isNull);
    expect(repository.calls, 1);
  });

  test('remove clears a locally selected photo', () async {
    final container = _container(
      picker: _Picker((_) async => raw),
      processor: _Processor(processed),
      repository: _Repository(),
    );
    addTearDown(container.dispose);
    final controller = container.read(productImageControllerProvider(target).notifier);
    await controller.select(ProductImageSource.gallery);
    controller.removeSelection();
    expect(container.read(productImageControllerProvider(target)).selected, isNull);
  });
}

ProviderContainer _container({
  required ProductImagePicker picker,
  required ProductImageProcessor processor,
  required ProductImageContributionRepository repository,
}) => ProviderContainer(
  overrides: [
    productImagePickerProvider.overrideWithValue(picker),
    productImageProcessorProvider.overrideWithValue(processor),
    productImageContributionRepositoryProvider.overrideWithValue(repository),
  ],
);

final class _Picker implements ProductImagePicker {
  _Picker(this.callback);
  final Future<RawProductImage?> Function(ProductImageSource) callback;
  int calls = 0;
  @override
  Future<RawProductImage?> pick(ProductImageSource source) {
    calls++;
    return callback(source);
  }
}

final class _Processor implements ProductImageProcessor {
  _Processor(this.result);
  final ProcessedProductImage result;
  int calls = 0;
  @override
  Future<ProcessedProductImage> process(RawProductImage image) async {
    calls++;
    return result;
  }
}

final class _Repository implements ProductImageContributionRepository {
  _Repository({this.failures = 0});
  int failures;
  int calls = 0;
  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const ProductImageException(ProductImageFailureKind.offline, 'Offline.');
    }
    return ProductImageContribution(
      id: 'contribution-1',
      status: 'pending',
      deliveryUrl: Uri.parse('https://res.cloudinary.com/demo/image/upload/photo.jpg'),
    );
  }
}

final class _CompletingRepository implements ProductImageContributionRepository {
  _CompletingRepository(this.result);
  final Completer<ProductImageContribution> result;
  int calls = 0;

  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) {
    calls++;
    return result.future;
  }
}
