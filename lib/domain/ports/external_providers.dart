import 'dart:typed_data';

import '../entities/domain_models.dart';
import '../value_objects/local_date.dart';

final class BarcodeScan {
  const BarcodeScan({
    required this.value,
    required this.format,
    required this.scannedAt,
    this.structuredExpiry,
    this.structuredLotCode,
  });

  final String value;
  final BarcodeFormat format;
  final DateTime scannedAt;
  final LocalDate? structuredExpiry;
  final String? structuredLotCode;
}

abstract interface class BarcodeScanner {
  Stream<BarcodeScan> get scans;

  Future<void> start();

  Future<void> stop();
}

final class ProductLookupCandidate {
  const ProductLookupCandidate({
    required this.barcode,
    required this.name,
    required this.providerReference,
    this.brand,
    this.imageUrl,
  });

  final String barcode;
  final String name;
  final String? brand;
  final Uri? imageUrl;
  final String providerReference;
}

enum ProductLookupFailureKind { timeout, network, rateLimited, server, malformed, unknown }

sealed class ProductLookupResult {
  const ProductLookupResult();
}

final class ProductLookupFound extends ProductLookupResult {
  const ProductLookupFound(this.candidate);

  final ProductLookupCandidate candidate;
}

final class ProductLookupNotFound extends ProductLookupResult {
  const ProductLookupNotFound();
}

final class ProductLookupUnavailable extends ProductLookupResult {
  const ProductLookupUnavailable(this.kind);

  final ProductLookupFailureKind kind;
}

abstract interface class ProductLookupProvider {
  Future<ProductLookupResult> findByBarcode(String barcode);
}

final class ExpiryImage {
  const ExpiryImage({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String mediaType;
}

final class ExpiryRecognitionCandidate {
  const ExpiryRecognitionCandidate({
    required this.date,
    required this.dateType,
    required this.confidence,
    required this.rawText,
  });

  final LocalDate? date;
  final ExpiryDateType dateType;
  final double confidence;
  final String rawText;
}

abstract interface class ExpiryRecognitionProvider {
  Future<List<ExpiryRecognitionCandidate>> recognize(ExpiryImage image);
}

final class ExpiryNotificationRequest {
  const ExpiryNotificationRequest({
    required this.id,
    required this.shopId,
    required this.batchId,
    required this.deliverAt,
    required this.title,
    required this.body,
  });

  final String id;
  final String shopId;
  final String batchId;
  final DateTime deliverAt;
  final String title;
  final String body;
}

abstract interface class NotificationProvider {
  Future<void> schedule(ExpiryNotificationRequest request);

  Future<void> cancel(String requestId);
}
