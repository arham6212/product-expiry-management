import unittest

from tools.ansar_catalog.normalizer import infer_family_variant, parse_packaging


class PackagingTests(unittest.TestCase):
    def test_maggi_multipack(self):
        pack = parse_packaging("Maggi Instant Noodles Curry 10 x 79g")
        self.assertEqual(pack.pack_count, 10)
        self.assertEqual(float(pack.unit_quantity), 79)
        self.assertEqual(float(pack.total_quantity), 790)
        self.assertEqual(pack.packaging_display, "10 x 79g")
        self.assertEqual(pack.product_type, "multipack")

    def test_cola_multipack(self):
        pack = parse_packaging("Coca-Cola Original 6 x 330ml")
        self.assertEqual(pack.pack_count, 6)
        self.assertEqual(float(pack.total_quantity), 1980)
        family, variant = infer_family_variant("Coca-Cola Original 6 x 330ml", pack.packaging_display)
        self.assertEqual(family, "Coca-Cola")
        self.assertEqual(variant, "Original")

    def test_single_pack(self):
        pack = parse_packaging("Rauch Peach Juice 355ml")
        self.assertEqual(pack.pack_count, 1)
        self.assertEqual(pack.unit_quantity_unit, "ml")
        self.assertEqual(pack.packaging_display, "355ml")


if __name__ == "__main__":
    unittest.main()

