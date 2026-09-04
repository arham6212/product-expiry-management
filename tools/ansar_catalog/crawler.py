from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import uuid
from urllib.error import HTTPError

from .barcode import classify_identifier
from .config import LOCK_PATH, LOG_DIR, SOURCE, STATE_PATH, TARGET_PRODUCTS, WORKBOOK_PATH
from .coverage import coverage_job_matches, infer_explicit_brand_prefix
from .excel_repository import ExcelRepository
from .fetcher import Fetcher
from .normalizer import identity_text, infer_family_variant, json_number, normalize_space, parse_packaging
from .parser import ListingCandidate, parse_listing, parse_product
from .state_repository import StateRepository


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@contextmanager
def exclusive_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise RuntimeError(f"another crawler run is active: {path}") from exc
    try:
        os.write(fd, f"pid={os.getpid()} started={utc_now()}\n".encode())
        os.close(fd)
        yield
    finally:
        path.unlink(missing_ok=True)


def _candidate_score(candidate: ListingCandidate) -> tuple[int, str]:
    name = candidate.name.casefold()
    score = 0
    if candidate.sku_hint and classify_identifier(candidate.sku_hint).barcode_valid:
        score += 100
    for keyword in ("noodle", "drink", "water", "juice", "milk", "yog", "biscuit", "chip", "chocolate", "oil", "rice", "flour", "pasta", "sauce", "ketchup", "coffee", "tea", "cereal", "frozen", "bread", "spice", "sugar", "salt"):
        if keyword in name:
            score += 8
    if re.search(r"\d\s*(?:kg|g|ml|l|x|pieces|pcs)\b", name):
        score += 12
    if any(word in name for word in ("holder", "container", "plate", "fork", "spoon", "pet bed")):
        score -= 30
    return -score, candidate.name.casefold()


class AnsarCatalogCrawler:
    def __init__(self, workbook_path: Path = WORKBOOK_PATH, state_path: Path = STATE_PATH,
                 fetcher: Fetcher | None = None) -> None:
        self.excel = ExcelRepository(workbook_path)
        self.states = StateRepository(state_path)
        self.fetcher = fetcher or Fetcher()
        self.workbook_path = workbook_path
        self.state_path = state_path

    def _existing_keys(self, rows: list[dict]) -> tuple[set[str], set[str], set[str]]:
        barcodes, fallbacks, urls = set(), set(), set()
        for row in rows:
            barcode = str(row.get("global_barcode") or "").strip()
            if barcode:
                barcodes.add(barcode)
            url = str(row.get("source_product_url") or "").strip()
            if url:
                urls.add(url)
            fallbacks.add("|".join([
                identity_text(str(row.get("canonical_name") or "")),
                str(row.get("ansar_sku") or "").strip(), url,
            ]))
        return barcodes, fallbacks, urls

    @staticmethod
    def _category_by_name(state: dict) -> dict[str, dict]:
        return {category["name"]: category for category in state["categories"]}

    def _gather_coverage_candidates(self, state: dict, existing_urls: set[str], target: int,
                                    errors: list[str]) -> list[ListingCandidate]:
        jobs = state.get("coverage_jobs", [])
        if not jobs or target <= 0:
            return []
        categories = self._category_by_name(state)
        inspected = set(state["product_urls_inspected"])
        pool: dict[str, list[ListingCandidate]] = {}
        seen_urls: set[str] = set()
        listing_cache: dict[str, list[ListingCandidate]] = {}
        pages_attempted = 0
        page_budget = max(8, min(24, target + 6))
        idle_passes = 0
        while pages_attempted < page_budget and idle_passes < len(jobs) * 2:
            index = state["coverage_cursor"] % len(jobs)
            state["coverage_cursor"] = (index + 1) % len(jobs)
            job = jobs[index]
            names = job.get("category_names", [])
            exhausted = set(job.get("exhausted_categories", []))
            active = [name for name in names if name not in exhausted and name in categories]
            if not active:
                idle_passes += 1
                continue
            idle_passes = 0
            category_index = int(job.get("category_cursor") or 0) % len(active)
            category_name = active[category_index]
            job["category_cursor"] = (category_index + 1) % len(active)
            page = int(job.setdefault("next_pages", {}).get(category_name) or 1)
            category = categories[category_name]
            url = category["url"] + (f"?p={page}" if page > 1 else "")
            try:
                if url not in listing_cache:
                    listing_cache[url] = parse_listing(self.fetcher.get(url), category_name)
                candidates = listing_cache[url]
                if not candidates:
                    job.setdefault("exhausted_categories", []).append(category_name)
                else:
                    job["next_pages"][category_name] = page + 1
                    job["last_error"] = None
                    for item in candidates:
                        if not coverage_job_matches(job, item.name):
                            continue
                        if item.url in inspected or item.url in existing_urls or item.url in seen_urls:
                            continue
                        pool.setdefault(job["key"], []).append(ListingCandidate(
                            item.name, item.url, item.image_url, item.category,
                            item.sku_hint, job["key"],
                        ))
                        seen_urls.add(item.url)
            except HTTPError as exc:
                if exc.code == 404:
                    job.setdefault("exhausted_categories", []).append(category_name)
                else:
                    errors.append(f"coverage listing {url}: HTTPError: {exc}")
                    job["last_error"] = f"HTTPError: {exc}"
            except Exception as exc:
                errors.append(f"coverage listing {url}: {type(exc).__name__}: {exc}")
                job["last_error"] = f"{type(exc).__name__}: {exc}"
            pages_attempted += 1

        for items in pool.values():
            items.sort(key=_candidate_score)
        ordered: list[ListingCandidate] = []
        # Fair round-robin plus a per-job cap keeps a large portfolio from
        # consuming the whole batch. The job stays queued until all pages end.
        per_job_cap = min(6, target)
        for rank in range(per_job_cap):
            for job in jobs:
                items = pool.get(job["key"], [])
                if rank < len(items):
                    ordered.append(items[rank])
                    if len(ordered) >= target:
                        return ordered
        return ordered

    def _gather_discovery_candidates(self, state: dict, existing_urls: set[str], target: int,
                                     errors: list[str]) -> list[ListingCandidate]:
        categories = state["categories"]
        inspected = set(state["product_urls_inspected"])
        pool: list[ListingCandidate] = []
        seen_urls: set[str] = set()
        pages_attempted = 0
        minimum_diverse_pages = min(10, len(categories))
        while (len(pool) < target * 4 or pages_attempted < minimum_diverse_pages) and pages_attempted < len(categories) * 2:
            index = state["category_cursor"] % len(categories)
            state["category_cursor"] = (index + 1) % len(categories)
            category = categories[index]
            if category.get("exhausted"):
                pages_attempted += 1
                continue
            page = int(category.get("next_page") or 1)
            url = category["url"] + (f"?p={page}" if page > 1 else "")
            try:
                html = self.fetcher.get(url)
                candidates = parse_listing(html, category["name"])
                if not candidates:
                    category["exhausted"] = True
                else:
                    category["next_page"] = page + 1
                    for item in candidates:
                        if item.url not in inspected and item.url not in existing_urls and item.url not in seen_urls:
                            pool.append(item)
                            seen_urls.add(item.url)
            except Exception as exc:
                errors.append(f"listing {url}: {type(exc).__name__}: {exc}")
            pages_attempted += 1
        grouped: dict[str, list[ListingCandidate]] = {}
        for item in pool:
            grouped.setdefault(item.category, []).append(item)
        for items in grouped.values():
            items.sort(key=_candidate_score)
        ordered: list[ListingCandidate] = []
        # Two per category provides diversity; later passes relax the cap only
        # when needed to reach the requested batch size.
        for rank in range(max((len(items) for items in grouped.values()), default=0)):
            for category in categories:
                items = grouped.get(category["name"], [])
                if rank < len(items):
                    ordered.append(items[rank])
        return ordered

    def _gather_candidates(self, state: dict, existing_urls: set[str], target: int,
                           errors: list[str]) -> list[ListingCandidate]:
        coverage_target = min(target, max(1, round(target * 0.9)))
        coverage = self._gather_coverage_candidates(state, existing_urls, coverage_target, errors)
        coverage_urls = {candidate.url for candidate in coverage}
        discovery = self._gather_discovery_candidates(
            state, existing_urls | coverage_urls, target, errors,
        )
        # Prefer 90% queued brand/family coverage and reserve 10% for fresh
        # discovery. Unused coverage capacity is filled by discovery.
        selected_coverage = coverage[:coverage_target]
        candidates = [*selected_coverage, *discovery]
        lower_priority = {"Cleaning & Laundry", "Disposable & Storage", "Produce"}
        return [
            *[item for item in candidates if item.category not in lower_priority],
            *[item for item in candidates if item.category in lower_priority],
        ]

    def _to_row(self, candidate: ListingCandidate, detail: dict, seen_at: str) -> dict:
        name = normalize_space(str(detail.get("name") or candidate.name))
        brand = normalize_space(str(detail.get("brand") or "")) or infer_explicit_brand_prefix(name)
        sku = normalize_space(str(detail.get("sku") or candidate.sku_hint or "")) or None
        identifier = classify_identifier(sku)
        packaging = parse_packaging(name)
        family, variant = infer_family_variant(name, packaging.packaging_display)
        category = normalize_space(str(detail.get("category") or candidate.category)) or None
        subcategory = normalize_space(str(detail.get("subcategory") or "")) or None
        product_type = packaging.product_type
        if identifier.classification == "weighted/internal product code" or category in {"Produce", "Fresh Chicken & Meat", "Fish & Sea Food"}:
            product_type = "weighted"
        confidence = 0.55
        if identifier.barcode_valid:
            confidence += 0.25
        if brand:
            confidence += 0.08
        if packaging.packaging_display:
            confidence += 0.07
        notes = identifier.rejection_reason or None
        stable = identifier.global_barcode or candidate.url
        return {
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{SOURCE}:{stable}")),
            "canonical_name": name,
            "source_display_name": candidate.name,
            "brand": brand,
            "product_family": family,
            "variant_name": variant,
            "product_type": product_type,
            "global_barcode": identifier.global_barcode,
            "barcode_type": identifier.barcode_type,
            "barcode_valid": identifier.barcode_valid,
            "ansar_sku": sku,
            "identifier_classification": identifier.classification,
            "pack_count": packaging.pack_count,
            "unit_quantity": json_number(packaging.unit_quantity),
            "unit_quantity_unit": packaging.unit_quantity_unit,
            "total_quantity": json_number(packaging.total_quantity),
            "total_quantity_unit": packaging.total_quantity_unit,
            "packaging_display": packaging.packaging_display,
            "category": category,
            "subcategory": subcategory,
            "country_of_origin": detail.get("country_of_origin"),
            "manufacturer": detail.get("manufacturer"),
            "primary_image_url": detail.get("image") or candidate.image_url,
            "source_product_url": candidate.url,
            "source": SOURCE,
            "first_seen_at": seen_at,
            "last_seen_at": seen_at,
            "data_confidence": round(confidence, 2),
            "notes": notes,
        }

    def run_once(self, target: int = TARGET_PRODUCTS) -> dict:
        with exclusive_lock(LOCK_PATH if self.workbook_path == WORKBOOK_PATH else self.workbook_path.with_suffix(".lock")):
            started_at = utc_now()
            run_id = str(uuid.uuid4())
            errors: list[str] = []
            snapshot = self.excel.snapshot()
            state = deepcopy(self.states.load())
            self.states.reconcile_coverage_jobs(state, snapshot["products"])
            barcodes, fallbacks, urls = self._existing_keys(snapshot["products"])
            candidates = self._gather_candidates(state, urls, target, errors)
            added: list[dict] = []
            duplicates = 0
            examined = 0
            inspected_this_run: list[str] = []
            for candidate in candidates:
                if len(added) >= target:
                    break
                examined += 1
                inspected_this_run.append(candidate.url)
                try:
                    detail = parse_product(self.fetcher.get(candidate.url))
                    row = self._to_row(candidate, detail, started_at)
                    self.states.seed_coverage_jobs(state, [row])
                    barcode = str(row.get("global_barcode") or "").strip()
                    fallback = "|".join([
                        identity_text(str(row.get("canonical_name") or "")),
                        str(row.get("ansar_sku") or "").strip(), candidate.url,
                    ])
                    if (barcode and barcode in barcodes) or fallback in fallbacks:
                        duplicates += 1
                        continue
                    added.append(row)
                    if barcode:
                        barcodes.add(barcode)
                    fallbacks.add(fallback)
                except Exception as exc:
                    errors.append(f"product {candidate.url}: {type(exc).__name__}: {exc}")
                    failure = state["failed_urls"].setdefault(candidate.url, {"attempts": 0})
                    failure["attempts"] += 1
                    failure["last_error"] = f"{type(exc).__name__}: {exc}"
                    failure["last_attempt_at"] = utc_now()
            valid_count = sum(1 for row in added if row["barcode_valid"])
            completed_at = utc_now()
            notes = None
            if len(added) < target:
                notes = f"Requested {target}; only {len(added)} eligible new products were available in examined candidates."
            run_log = {
                "run_id": run_id, "started_at": started_at, "completed_at": completed_at,
                "candidate_products_examined": examined, "new_products_added": len(added),
                "duplicates_skipped": duplicates, "valid_global_barcodes": valid_count,
                "invalid_or_internal_identifiers": len(added) - valid_count,
                "errors": " | ".join(errors) if errors else None, "notes": notes,
            }
            actual_added, bridge_duplicates = self.excel.append(added, run_log)
            duplicates += bridge_duplicates
            # Commit crawl progress after the workbook succeeds. If the process
            # crashes before this save, Excel deduplication makes the retry safe.
            inspected = list(dict.fromkeys([*state["product_urls_inspected"], *inspected_this_run]))
            state["product_urls_inspected"] = inspected
            state["last_completed_run_id"] = run_id
            self.states.save(state)
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            summary = {
                "run_id": run_id, "started_at": started_at, "completed_at": completed_at,
                "products_added": actual_added, "duplicates_skipped": duplicates,
                "valid_global_barcodes": valid_count,
                "invalid_or_internal_identifiers": len(added) - valid_count,
                "candidate_products_examined": examined,
                "product_names": [row["canonical_name"] for row in added[:actual_added]],
                "errors": errors, "workbook": str(self.workbook_path), "state": str(self.state_path),
            }
            log_path = LOG_DIR / f"run-{started_at.replace(':', '').replace('-', '')}-{run_id[:8]}.json"
            with log_path.open("w", encoding="utf-8") as handle:
                json.dump(summary, handle, indent=2, ensure_ascii=False)
            return summary
