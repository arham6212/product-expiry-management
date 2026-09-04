from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re

from .config import BASE_URL, CATEGORY_SEEDS

STATE_VERSION = 2


def _job_key(kind: str, display_name: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", display_name.casefold()).strip("-")
    return f"{kind}:{normalized}"


def default_state() -> dict:
    return {
        "version": STATE_VERSION,
        "updated_at": None,
        "category_cursor": 0,
        "categories": [
            {"name": name, "url": f"{BASE_URL}{path}", "next_page": 1, "exhausted": False}
            for name, path in CATEGORY_SEEDS
        ],
        "product_urls_inspected": [],
        "failed_urls": {},
        "last_completed_run_id": None,
        "coverage_cursor": 0,
        "coverage_jobs": [],
    }


class StateRepository:
    def __init__(self, path: Path) -> None:
        self.path = path

    def load(self) -> dict:
        if not self.path.exists():
            return default_state()
        with self.path.open("r", encoding="utf-8") as handle:
            state = json.load(handle)
        baseline = default_state()
        known = {item["url"] for item in state.get("categories", [])}
        state.setdefault("categories", []).extend(x for x in baseline["categories"] if x["url"] not in known)
        state.setdefault("product_urls_inspected", [])
        state.setdefault("failed_urls", {})
        state.setdefault("category_cursor", 0)
        state.setdefault("coverage_cursor", 0)
        state.setdefault("coverage_jobs", [])
        state["version"] = STATE_VERSION
        return state

    @staticmethod
    def ensure_coverage_job(state: dict, spec: dict, source_product_url: str | None = None) -> bool:
        kind = str(spec["kind"])
        display_name = str(spec["display_name"])
        key = _job_key(kind, display_name)
        existing = next((job for job in state.setdefault("coverage_jobs", []) if job.get("key") == key), None)
        if existing:
            existing_terms = list(existing.setdefault("match_terms", []))
            for term in spec.get("match_terms", []):
                if term not in existing_terms:
                    existing_terms.append(term)
            existing["match_terms"] = existing_terms
            return False
        allowed = set(spec.get("category_names") or [name for name, _ in CATEGORY_SEEDS])
        category_names = [name for name, _ in CATEGORY_SEEDS if name in allowed]
        state["coverage_jobs"].append({
            "key": key,
            "kind": kind,
            "display_name": display_name,
            "match_terms": list(dict.fromkeys(spec.get("match_terms") or [display_name])),
            "category_names": category_names,
            "category_cursor": 0,
            "next_pages": {name: 1 for name in category_names},
            "exhausted_categories": [],
            "source_product_url": source_product_url,
            "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "last_error": None,
        })
        return True

    def seed_coverage_jobs(self, state: dict, rows: list[dict]) -> int:
        from .coverage import coverage_specs_for_product

        created = 0
        for row in rows:
            source_url = str(row.get("source_product_url") or "") or None
            for spec in coverage_specs_for_product(row):
                created += int(self.ensure_coverage_job(state, spec, source_url))
        return created

    def reconcile_coverage_jobs(self, state: dict, rows: list[dict]) -> int:
        """Seed from the full catalog and drop obsolete inferred-family jobs."""
        from .coverage import REQUESTED_COVERAGE_SPECS, coverage_specs_for_product

        valid_family_keys = {
            _job_key(spec["kind"], spec["display_name"])
            for row in rows
            for spec in coverage_specs_for_product(row)
            if spec["kind"] == "product_family"
        }
        state["coverage_jobs"] = [
            job for job in state.setdefault("coverage_jobs", [])
            if job.get("kind") != "product_family" or job.get("key") in valid_family_keys
        ]
        created = self.seed_coverage_jobs(state, rows)
        for spec in REQUESTED_COVERAGE_SPECS:
            created += int(self.ensure_coverage_job(state, spec))
        return created

    def save(self, state: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = deepcopy(state)
        payload["updated_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        tmp = self.path.with_suffix(self.path.suffix + f".tmp-{os.getpid()}")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.path)
