from __future__ import annotations

from pathlib import Path
import tempfile
import threading
import unittest

from tools.ansar_catalog.excel_repository import ExcelRepository
from tools.ansar_catalog.sync_supabase import (
    SupabaseSyncError,
    prepare_catalog,
    synchronize,
    verify_remote,
)


def product_row(barcode: str, row_id: str, **overrides):
    row = {
        "id": row_id,
        "canonical_name": f"Product {barcode}",
        "source_display_name": f"Product {barcode}",
        "brand": "Ansar Brand",
        "product_family": "Family",
        "variant_name": "Variant",
        "product_type": "packaged",
        "global_barcode": barcode,
        "barcode_type": {8: "GTIN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14"}[len(barcode)],
        "barcode_valid": True,
        "ansar_sku": barcode,
        "identifier_classification": "EAN-13",
        "pack_count": 1,
        "unit_quantity": 500,
        "unit_quantity_unit": "g",
        "total_quantity": 500,
        "total_quantity_unit": "g",
        "packaging_display": "500g",
        "category": "Dry Food",
        "subcategory": "Rice",
        "country_of_origin": None,
        "manufacturer": None,
        "primary_image_url": "https://media.ansargallery.com/product.jpg",
        "source_product_url": f"https://www.ansargallery.com/en/product-{row_id}",
        "source": "Ansar Gallery Qatar",
        "first_seen_at": "2026-09-01T00:00:00Z",
        "last_seen_at": "2026-09-01T00:00:00Z",
        "data_confidence": 0.95,
        "notes": None,
    }
    row.update(overrides)
    return row


class FakeClient:
    def __init__(self):
        self.products = {}
        self.calls = 0
        self.fail_on_call = None
        self.lock = threading.Lock()
        self.protected = {
            "products": 4,
            "product_barcodes": 4,
            "batches": 3,
            "inventory_movements": 3,
            "published_product_listings": 0,
            "deals": 0,
        }

    def ingest(self, observation):
        with self.lock:
            self.calls += 1
            if self.calls == self.fail_on_call:
                raise SupabaseSyncError("injected failure")
            barcode = observation["global_barcode"]
            existing = self.products.get(barcode)
            if existing is None:
                product_id = f"catalog-{len(self.products) + 1}"
                self.products[barcode] = {
                    "id": product_id,
                    "canonical_name": observation["canonical_name"],
                    "brand": observation.get("brand"),
                }
                status = "inserted"
            else:
                product_id = existing["id"]
                if existing.get("brand") is None and observation.get("brand"):
                    existing["brand"] = observation["brand"]
                    status = "enriched"
                else:
                    status = "unchanged"
            return {"catalog_product_id": product_id, "barcode": barcode, "status": status}

    def verify(self, barcodes):
        distinct = set(barcodes)
        matched = {barcode for barcode in distinct if barcode in self.products}
        return {
            "requested": len(distinct),
            "matched": len(matched),
            "distinct_catalog_products": len({self.products[x]["id"] for x in matched}),
            "missing": sorted(distinct - matched),
            "catalog_products": len({item["id"] for item in self.products.values()}),
            "catalog_product_barcodes": len(self.products),
            "catalog_product_observations": len(self.products),
            "protected_counts": dict(self.protected),
        }


def workbook(path: Path, rows):
    repository = ExcelRepository(path)
    repository.append(
        list(rows),
        {
            "run_id": "run-1",
            "started_at": "2026-09-01T00:00:00Z",
            "completed_at": "2026-09-01T00:01:00Z",
            "candidate_products_examined": len(rows),
            "new_products_added": len(rows),
        },
    )


class SupabaseCatalogSyncTests(unittest.TestCase):
    def test_complete_initial_backfill_and_repeated_import_are_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            workbook_path = Path(temporary) / "catalog.xlsx"
            state_path = Path(temporary) / "state.json"
            workbook(
                workbook_path,
                [
                    product_row("5000112519945", "one"),
                    product_row("017273501615", "leading-zero"),
                ],
            )
            client = FakeClient()

            first = synchronize(client, workbook_path, state_path)
            second = synchronize(client, workbook_path, state_path)

            self.assertEqual(first["rows_examined"], 2)
            self.assertEqual(first["rows_inserted"], 2)
            self.assertEqual(first["valid_rows_imported"], 2)
            self.assertEqual(second["valid_rows_imported"], 0)
            self.assertEqual(len(client.products), 2)
            self.assertIn("017273501615", client.products)

    def test_full_reconcile_is_idempotent_and_preserves_existing_identity_and_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            workbook_path = Path(temporary) / "catalog.xlsx"
            state_path = Path(temporary) / "state.json"
            workbook(workbook_path, [product_row("5000112519945", "one")])
            client = FakeClient()
            client.products["5000112519945"] = {
                "id": "administrator-product",
                "canonical_name": "Administrator corrected name",
                "brand": "Verified brand",
            }

            result = synchronize(
                client, workbook_path, state_path, full_reconcile=True
            )

            self.assertEqual(result["rows_unchanged"], 1)
            self.assertEqual(client.products["5000112519945"]["id"], "administrator-product")
            self.assertEqual(
                client.products["5000112519945"]["canonical_name"],
                "Administrator corrected name",
            )
            self.assertEqual(client.products["5000112519945"]["brand"], "Verified brand")

    def test_empty_field_is_enriched_without_reassigning_barcode(self):
        observation = prepare_catalog([product_row("5000112519945", "one")]).observations[0]
        client = FakeClient()
        client.products["5000112519945"] = {
            "id": "existing-product",
            "canonical_name": "Existing",
            "brand": None,
        }

        result = client.ingest(observation)

        self.assertEqual(result["status"], "enriched")
        self.assertEqual(result["catalog_product_id"], "existing-product")
        self.assertEqual(client.products["5000112519945"]["brand"], "Ansar Brand")

    def test_invalid_internal_and_wrong_source_rows_are_rejected(self):
        prepared = prepare_catalog(
            [
                product_row("2901234567893", "weighted"),
                product_row("5000112519945", "invalid-flag", barcode_valid=False),
                product_row("8690101368943", "wrong-source", source="Snoonu"),
            ]
        )

        self.assertEqual(prepared.observations, [])
        self.assertEqual(len(prepared.rejected), 3)
        self.assertEqual(
            {item["reason"] for item in prepared.rejected},
            {
                "GS1 restricted-distribution prefix 20-29",
                "workbook_barcode_not_valid",
                "source_not_ansar_gallery_qatar",
            },
        )

    def test_different_gtins_remain_separate_products(self):
        prepared = prepare_catalog(
            [
                product_row("5000112519945", "single"),
                product_row("8690101368943", "multipack"),
            ]
        )
        client = FakeClient()
        for observation in prepared.observations:
            client.ingest(observation)

        result = verify_remote(client, prepared)

        self.assertEqual(result["distinct_catalog_products"], 2)

    def test_partial_failure_does_not_advance_checkpoint_and_retry_is_safe(self):
        with tempfile.TemporaryDirectory() as temporary:
            workbook_path = Path(temporary) / "catalog.xlsx"
            state_path = Path(temporary) / "state.json"
            workbook(
                workbook_path,
                [
                    product_row("5000112519945", "one"),
                    product_row("8690101368943", "two"),
                ],
            )
            client = FakeClient()
            client.fail_on_call = 2

            with self.assertRaises(SupabaseSyncError):
                synchronize(client, workbook_path, state_path)
            self.assertFalse(state_path.exists())

            client.fail_on_call = None
            result = synchronize(client, workbook_path, state_path)

            self.assertEqual(result["rows_unchanged"], 1)
            self.assertEqual(result["rows_inserted"], 1)
            self.assertEqual(len(client.products), 2)

    def test_concurrent_import_resolves_one_product(self):
        prepared = prepare_catalog([product_row("5000112519945", "one")])
        client = FakeClient()
        client.ingest(prepared.observations[0])

        result = verify_remote(client, prepared, concurrency_probe=True)

        self.assertTrue(result["concurrency_probe"])
        self.assertEqual(len(client.products), 1)


if __name__ == "__main__":
    unittest.main()
