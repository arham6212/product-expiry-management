from pathlib import Path
import tempfile
import unittest
import uuid

from tools.ansar_catalog.config import PRODUCT_COLUMNS, RUN_LOG_COLUMNS
from tools.ansar_catalog.excel_repository import ExcelRepository


def product(barcode: str, name: str = "Test Product 330ml") -> dict:
    row = {column: None for column in PRODUCT_COLUMNS}
    row.update({
        "id": str(uuid.uuid4()), "canonical_name": name, "source_display_name": name,
        "global_barcode": barcode, "barcode_type": "EAN-13", "barcode_valid": True,
        "ansar_sku": barcode, "identifier_classification": "EAN-13",
        "source_product_url": f"https://www.ansargallery.com/en/test-qatar-{barcode}",
        "source": "Ansar Gallery Qatar", "first_seen_at": "2026-09-01T00:00:00Z",
        "last_seen_at": "2026-09-01T00:00:00Z", "data_confidence": 0.9,
    })
    return row


def log(run_id: str) -> dict:
    row = {column: None for column in RUN_LOG_COLUMNS}
    row.update({"run_id": run_id, "started_at": "2026-09-01T00:00:00Z", "completed_at": "2026-09-01T00:01:00Z"})
    return row


class ExcelRepositoryTests(unittest.TestCase):
    def test_append_preserves_rows_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "catalog.xlsx"
            repo = ExcelRepository(path)
            first, dropped = repo.append([product("8690101368943")], log("run-1"))
            self.assertEqual((first, dropped), (1, 0))
            second, dropped = repo.append([product("8690101368943")], log("run-2"))
            self.assertEqual((second, dropped), (0, 1))
            third, dropped = repo.append([product("089686180657", "Second Product 75g")], log("run-3"))
            self.assertEqual((third, dropped), (1, 0))
            snapshot = repo.snapshot()
            self.assertEqual(len(snapshot["products"]), 2)
            self.assertEqual(snapshot["products"][0]["global_barcode"], "8690101368943")
            self.assertEqual(snapshot["products"][1]["global_barcode"], "089686180657")
            self.assertEqual(snapshot["products"][0]["first_seen_at"], "2026-09-01T00:00:00Z")
            self.assertEqual(len(snapshot["run_log"]), 3)
            self.assertEqual(snapshot["run_log"][0]["started_at"], "2026-09-01T00:00:00Z")
            verify = repo.verify()
            self.assertEqual(verify["duplicate_global_barcodes"], [])
            self.assertEqual(verify["duplicate_source_urls"], [])


if __name__ == "__main__":
    unittest.main()
