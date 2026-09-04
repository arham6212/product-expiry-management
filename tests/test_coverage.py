from pathlib import Path
import tempfile
import unittest

from tools.ansar_catalog.coverage import coverage_job_matches, coverage_specs_for_product, infer_explicit_brand_prefix
from tools.ansar_catalog.crawler import AnsarCatalogCrawler
from tools.ansar_catalog.state_repository import StateRepository, default_state


class FakeFetcher:
    def __init__(self, html: str):
        self.html = html
        self.urls: list[str] = []

    def get(self, url: str) -> str:
        self.urls.append(url)
        return self.html


class CoverageTests(unittest.TestCase):
    def test_explicit_prefix_brand_inference_is_conservative(self):
        self.assertEqual(infer_explicit_brand_prefix("Nestle Lion Cereal 400g"), "Nestle")
        self.assertEqual(infer_explicit_brand_prefix("Coca-Cola Zero 330ml"), "Coca-Cola")
        self.assertIsNone(infer_explicit_brand_prefix("Chocolate Cereal 400g"))

    def test_nestle_profile_covers_named_portfolio_families(self):
        specs = coverage_specs_for_product({
            "canonical_name": "Nestle Lion Caramel Cereals 400g",
            "brand": None,
            "category": "Breakfast Food",
        })
        job = next(spec for spec in specs if spec["kind"] == "brand")
        self.assertEqual(job["display_name"], "Nestle")
        self.assertTrue(coverage_job_matches(job, "Nesquik Chocolate Cereal 375g"))
        self.assertTrue(coverage_job_matches(job, "Maggi Curry Noodles 5 x 79g"))
        self.assertFalse(coverage_job_matches(job, "American Garden Ketchup 340g"))

    def test_soft_drink_product_starts_category_family_coverage(self):
        specs = coverage_specs_for_product({
            "canonical_name": "Coca-Cola Zero 6 x 330ml",
            "brand": "Coca-Cola",
            "category": "Beverages",
            "product_family": "Coca-Cola",
            "variant_name": "Zero",
            "global_barcode": "5449000000996",
        })
        kinds = {spec["kind"] for spec in specs}
        self.assertEqual(kinds, {"brand", "product_family", "category_family"})
        soft_drinks = next(spec for spec in specs if spec["kind"] == "category_family")
        self.assertTrue(coverage_job_matches(soft_drinks, "Fanta Orange Can 330ml"))
        self.assertFalse(coverage_job_matches(soft_drinks, "Orange Juice 1L"))

    def test_seed_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = StateRepository(Path(tmp) / "state.json")
            state = default_state()
            rows = [{
                "canonical_name": "Nestle Lion Cereals 400g",
                "brand": None,
                "category": "Breakfast Food",
                "source_product_url": "https://example/nestle",
            }]
            self.assertEqual(repo.seed_coverage_jobs(state, rows), 1)
            self.assertEqual(repo.seed_coverage_jobs(state, rows), 0)
            self.assertEqual(len(state["coverage_jobs"]), 1)

    def test_reconcile_seeds_requested_nestle_and_soft_drink_coverage(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = StateRepository(Path(tmp) / "state.json")
            state = default_state()
            repo.reconcile_coverage_jobs(state, [])
            self.assertEqual(
                {job["key"] for job in state["coverage_jobs"]},
                {"brand:nestle", "category_family:soft-drinks"},
            )

    def test_unbarcoded_generic_variant_does_not_create_family_job(self):
        specs = coverage_specs_for_product({
            "canonical_name": "Green Lemon 500g",
            "brand": None,
            "category": "Fruits & Vegetables",
            "product_family": "Green",
            "variant_name": "Lemon",
            "global_barcode": None,
        })
        self.assertFalse(any(spec["kind"] == "product_family" for spec in specs))

    def test_coverage_page_progress_resumes(self):
        html = """
        <a href="/en/nestle-lion-cereal-qatar-7613031370641" title="Nestle Lion Cereal 400g"></a>
        <a href="/en/other-ketchup-qatar-8690101368943" title="Other Ketchup 340g"></a>
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fetcher = FakeFetcher(html)
            crawler = AnsarCatalogCrawler(root / "catalog.xlsx", root / "state.json", fetcher=fetcher)
            state = default_state()
            state["coverage_jobs"] = []
            StateRepository.ensure_coverage_job(state, {
                "kind": "brand", "display_name": "Nestle", "match_terms": ["nestle"],
                "category_names": ["Breakfast Food"],
            })
            candidates = crawler._gather_coverage_candidates(state, set(), 1, [])
            self.assertEqual([item.name for item in candidates], ["Nestle Lion Cereal 400g"])
            job = state["coverage_jobs"][0]
            self.assertGreaterEqual(job["next_pages"]["Breakfast Food"], 2)
            self.assertTrue(any("?p=2" in url for url in fetcher.urls))


if __name__ == "__main__":
    unittest.main()
