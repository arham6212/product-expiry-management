import '../entities/domain_models.dart';

final class BarcodeValidationException implements Exception {
  const BarcodeValidationException(this.message);

  final String message;

  @override
  String toString() => 'BarcodeValidationException: $message';
}

/// A retail barcode whose digit identity is preserved exactly.
///
/// Supported manual representations are EAN-8, UPC-A, EAN-13, and GTIN-14.
/// Whitespace around the value is removed, but leading zeroes are never
/// stripped and UPC/EAN forms are never expanded into a different code.
final class NormalizedBarcode {
  factory NormalizedBarcode.parse(String input, {BarcodeFormat? formatHint}) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const BarcodeValidationException('Enter or scan a barcode.');
    }
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const BarcodeValidationException('Barcode must contain digits only.');
    }

    final inferredFormat = switch (value.length) {
      8 => BarcodeFormat.ean8,
      12 => BarcodeFormat.upcA,
      13 => BarcodeFormat.ean13,
      14 => BarcodeFormat.gtin14,
      _ => throw const BarcodeValidationException(
        'Supported barcode lengths are 8, 12, 13, or 14 digits.',
      ),
    };

    if (_isRetailerOnly(value) || !_hasValidGtinChecksum(value)) {
      throw const BarcodeValidationException('Barcode is not a valid global EAN, UPC, or GTIN.');
    }

    if (formatHint != null &&
        formatHint != BarcodeFormat.unknown &&
        !_isCompatible(formatHint, value.length)) {
      throw const BarcodeValidationException(
        'The scanned barcode length does not match its reported format.',
      );
    }

    final format = formatHint == null || formatHint == BarcodeFormat.unknown
        ? inferredFormat
        : formatHint;
    return NormalizedBarcode._(value, format);
  }

  const NormalizedBarcode._(this.value, this.format);

  final String value;
  final BarcodeFormat format;

  static bool _isCompatible(BarcodeFormat format, int length) {
    return switch (format) {
      BarcodeFormat.ean8 || BarcodeFormat.upcE => length == 8,
      BarcodeFormat.upcA => length == 12,
      BarcodeFormat.ean13 => length == 13,
      BarcodeFormat.gtin14 => length == 14,
      _ => false,
    };
  }

  static bool _isRetailerOnly(String value) {
    if (value.split('').toSet().length == 1 || value.startsWith('499990')) {
      return true;
    }
    if (value.length == 13 && RegExp(r'^\d{6}0{7}$').hasMatch(value)) {
      return true;
    }
    if ((value.length == 13 || value.length == 14) &&
        int.parse(value.substring(0, 2)) >= 20 &&
        int.parse(value.substring(0, 2)) <= 29) {
      return true;
    }
    return false;
  }

  static bool _hasValidGtinChecksum(String value) {
    var sum = 0;
    var positionFromRight = 1;
    for (var index = value.length - 2; index >= 0; index--) {
      final digit = int.parse(value[index]);
      sum += digit * (positionFromRight.isOdd ? 3 : 1);
      positionFromRight += 1;
    }
    final expected = (10 - sum % 10) % 10;
    return expected == int.parse(value[value.length - 1]);
  }

  @override
  bool operator ==(Object other) {
    return other is NormalizedBarcode && other.value == value && other.format == format;
  }

  @override
  int get hashCode => Object.hash(value, format);

  @override
  String toString() => value;
}
