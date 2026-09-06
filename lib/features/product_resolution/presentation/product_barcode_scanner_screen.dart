import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../application/product_barcode_scan_controller.dart';
import 'scanner_overlay.dart';

class ProductBarcodeScannerScreen extends ConsumerStatefulWidget {
  const ProductBarcodeScannerScreen({
    required this.onDetect,
    required this.onManualEntry,
    this.onWithoutBarcode,
    super.key,
  });

  final ValueChanged<String> onDetect;
  final VoidCallback onManualEntry;
  final VoidCallback? onWithoutBarcode;

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
    if (barcode == null) return;

    try {
      await _cameraController.stop();
    } on MobileScannerException {
      // Resolution can continue even if the camera is already stopping.
    }
    if (!mounted) return;

    widget.onDetect(barcode);
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
    final isSuccess = scanState.status == ProductBarcodeScanStatus.accepted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan product'),
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
      body: ValueListenableBuilder(
        valueListenable: _cameraController,
        builder: (context, camera, _) => Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _cameraController,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(
                message: _cameraErrorMessage(error.errorCode),
                onRetry: _retryScan,
                onManualEntry: widget.onManualEntry,
                onWithoutBarcode: widget.onWithoutBarcode,
              ),
            ),

            if (camera.error == null) ScannerOverlay(isSuccess: isSuccess),

            if (camera.error == null &&
                scanState.status == ProductBarcodeScanStatus.scanning &&
                !isSuccess)
              const Positioned(
                top: 24,
                left: 32,
                right: 32,
                child: SafeArea(
                  child: Text(
                    'Center one barcode inside the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

            // Subtle fallback button when scanning is active
            if (camera.error == null &&
                scanState.status == ProductBarcodeScanStatus.scanning &&
                !isSuccess)
              Positioned(
                bottom: 32,
                left: 24,
                right: 24,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            try {
                              await _cameraController.stop();
                            } on MobileScannerException {
                              /* Already stopped. */
                            }
                            if (mounted) widget.onManualEntry();
                          },
                          icon: const Icon(Icons.keyboard_outlined),
                          label: const Text('Enter barcode'),
                        ),
                        if (widget.onWithoutBarcode != null)
                          TextButton(
                            key: const Key('scannerWithoutBarcodeButton'),
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: () async {
                              try {
                                await _cameraController.stop();
                              } on MobileScannerException {
                                /* Already stopped. */
                              }
                              if (mounted) widget.onWithoutBarcode!();
                            },
                            child: const Text('No barcode? Add product'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            if (scanState.status == ProductBarcodeScanStatus.invalid && !isSuccess)
              _InvalidBarcodeOverlay(
                message: scanState.message ?? 'This barcode is not supported.',
                onRetry: _retryScan,
                onManualEntry: widget.onManualEntry,
              ),
          ],
        ),
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
  const _CameraError({
    required this.message,
    required this.onRetry,
    required this.onManualEntry,
    this.onWithoutBarcode,
  });
  final VoidCallback? onWithoutBarcode;

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
              TextButton(onPressed: onManualEntry, child: const Text('Enter barcode')),
              if (onWithoutBarcode != null)
                TextButton(
                  onPressed: onWithoutBarcode,
                  child: const Text('No barcode? Add product'),
                ),
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
