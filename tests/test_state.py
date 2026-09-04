import json
from pathlib import Path
import tempfile
import unittest

from tools.ansar_catalog.state_repository import StateRepository, default_state


class StateTests(unittest.TestCase):
    def test_resume_preserves_page_and_inspected_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state.json"
            repo = StateRepository(path)
            state = default_state()
            state["categories"][0]["next_page"] = 7
            state["product_urls_inspected"] = ["https://example/product"]
            repo.save(state)
            loaded = repo.load()
            self.assertEqual(loaded["categories"][0]["next_page"], 7)
            self.assertEqual(loaded["product_urls_inspected"], ["https://example/product"])
            self.assertEqual(loaded["version"], 2)
            self.assertEqual(loaded["coverage_cursor"], 0)
            self.assertEqual(loaded["coverage_jobs"], [])
            self.assertIsNotNone(json.loads(path.read_text())["updated_at"])


if __name__ == "__main__":
    unittest.main()
