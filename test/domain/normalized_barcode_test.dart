import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';

void main() {
  test('trims surrounding whitespace without changing digits', () {
    final barcode = NormalizedBarcode.parse('  0123456789012  ');

    expect(barcode.value, '0123456789012');
    expect(barcode.format, BarcodeFormat.ean13);
  });

  test('supports EAN-8, UPC-A, EAN-13, and GTIN-14 representations', () {
    expect(NormalizedBarcode.parse('12345670').format, BarcodeFormat.ean8);
    expect(NormalizedBarcode.parse('123456789012').format, BarcodeFormat.upcA);
    expect(NormalizedBarcode.parse('1234567890123').format, BarcodeFormat.ean13);
    expect(NormalizedBarcode.parse('01234567890123').format, BarcodeFormat.gtin14);
  });

  for (final invalid in ['', '   ', '123-45678', '1234567', '123456789012345']) {
    test('rejects invalid barcode "$invalid"', () {
      expect(() => NormalizedBarcode.parse(invalid), throwsA(isA<BarcodeValidationException>()));
    });
  }

  test('rejects a scanner format that conflicts with the digit length', () {
    expect(
      () => NormalizedBarcode.parse('1234567890123', formatHint: BarcodeFormat.upcA),
      throwsA(isA<BarcodeValidationException>()),
    );
  });
}
