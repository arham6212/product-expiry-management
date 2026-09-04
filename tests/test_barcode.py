import unittest

from tools.ansar_catalog.barcode import classify_identifier, validate_gtin


class BarcodeTests(unittest.TestCase):
    def test_ean_13(self):
        self.assertTrue(validate_gtin("8690101368943"))
        result = classify_identifier("8690101368943")
        self.assertEqual(result.barcode_type, "EAN-13")
        self.assertEqual(result.global_barcode, "8690101368943")

    def test_upc_a_with_leading_zero(self):
        self.assertTrue(validate_gtin("017273501615"))
        self.assertEqual(classify_identifier("017273501615").barcode_type, "UPC-A")

    def test_invalid_checksum_rejected(self):
        result = classify_identifier("8690101368944")
        self.assertFalse(result.barcode_valid)
        self.assertIsNone(result.global_barcode)
        self.assertIn("checksum", result.rejection_reason)

    def test_internal_and_composite_rejected(self):
        internal = classify_identifier("2901234567893")
        self.assertFalse(internal.barcode_valid)
        self.assertEqual(internal.classification, "weighted/internal product code")
        composite = classify_identifier("AG-12345")
        self.assertEqual(composite.classification, "composite identifier")

    def test_checksum_valid_weighted_produce_code_rejected(self):
        result = classify_identifier("9119260000000")
        self.assertFalse(result.barcode_valid)
        self.assertIsNone(result.global_barcode)
        self.assertEqual(result.classification, "weighted/internal product code")


if __name__ == "__main__":
    unittest.main()
