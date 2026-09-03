import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../application/product_barcode_scan_controller.dart';

class ProductBarcodeScannerScreen extends ConsumerStatefulWidget {
  const ProductBarcodeScannerScreen({super.key});

  @override
  ConsumerState<ProductBarcodeScannerScreen> createState() => _ProductBarcodeScannerScreenState();
}

class _ProductBarcodeScannerScreenState extends ConsumerState<ProductBarcodeScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!mounted) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    final barcode = ref.read(productBarcodeScanControllerProvider.notifier).detect(rawValue);
    await _cameraController.stop();
    if (!mounted || barcode == null) return;
    Navigator.of(context).pop(barcode);
  }

  Future<void> _retryScan() async {
    ref.read(productBarcodeScanControllerProvider.notifier).retry();
    try {
      await _cameraController.start();
    } on MobileScannerException {
      // MobileScanner rebuilds its error state with the actionable message below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(productBarcodeScanControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan product barcode'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _cameraController,
            builder: (context, cameraState, child) {
              final canUseTorch = cameraState.torchState != TorchState.unavailable;
              return IconButton(
                icon: Icon(
                  cameraState.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                ),
                tooltip: 'Toggle flashlight',
                onPressed: canUseTorch ? _cameraController.toggleTorch : null,
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              message: _cameraErrorMessage(error.errorCode),
              onRetry: _retryScan,
              onManualEntry: () => Navigator.of(context).pop(),
            ),
          ),
          if (scanState.status == ProductBarcodeScanStatus.invalid)
            _InvalidBarcodeOverlay(
              message: scanState.message ?? 'This barcode is not supported.',
              onRetry: _retryScan,
              onManualEntry: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}

String _cameraErrorMessage(MobileScannerErrorCode errorCode) {
  return switch (errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'Camera permission was denied. Enable camera access in device settings, then try again.',
    MobileScannerErrorCode.unsupported =>
      'No supported camera is available on this device. Enter the barcode manually instead.',
    _ => 'The camera could not be started. Check camera availability and try again.',
  };
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onRetry, required this.onManualEntry});

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try camera again'),
              ),
              TextButton(onPressed: onManualEntry, child: const Text('Enter barcode manually')),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvalidBarcodeOverlay extends StatelessWidget {
  const _InvalidBarcodeOverlay({
    required this.message,
    required this.onRetry,
    required this.onManualEntry,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
                const SizedBox(height: 16),
                Text('Invalid product barcode', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Scan again')),
                TextButton(onPressed: onManualEntry, child: const Text('Enter barcode manually')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
