from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import time
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .barcode import classify_identifier
from .config import DATA_DIR, WORKBOOK_PATH
from .excel_repository import ExcelRepository


SYNC_STATE_PATH = DATA_DIR / "ansar_supabase_sync_state.json"
SYNC_STATE_VERSION = 1
SOURCE = "Ansar Gallery Qatar"
RPC_FIELDS = (
    "source_display_name",
    "product_family",
    "variant_name",
    "product_type",
    "pack_count",
    "unit_quantity",
    "unit_quantity_unit",
    "total_quantity",
    "total_quantity_unit",
    "packaging_display",
    "category",
    "subcategory",
    "country_of_origin",
    "manufacturer",
)


class SupabaseSyncError(RuntimeError):
    pass


class CatalogSyncClient(Protocol):
    def ingest(self, observation: dict[str, Any]) -> dict[str, Any]: ...

    def verify(self, barcodes: list[str]) -> dict[str, Any]: ...


@dataclass(frozen=True)
class PreparedCatalog:
    observations: list[dict[str, Any]]
    rejected: list[dict[str, str]]
    eligible_ids: set[str]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _optional_text(value: Any, maximum: int | None = None) -> str | None:
    if value is None:
        return None
    normalized = " ".join(str(value).split())
    if not normalized:
        return None
    return normalized[:maximum] if maximum is not None else normalized


def _valid_http_url(value: Any) -> str | None:
    normalized = _optional_text(value)
    return normalized if normalized and normalized.startswith(("http://", "https://")) else None


def _database_format(barcode: str) -> str:
    return {8: "ean8", 12: "upc_a", 13: "ean13", 14: "gtin14"}[len(barcode)]


def _prepare_observation(row: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    row_id = _optional_text(row.get("id")) or "<missing-id>"
    if row.get("source") != SOURCE:
        return None, "source_not_ansar_gallery_qatar"
    if row.get("barcode_valid") is not True:
        return None, "workbook_barcode_not_valid"

    raw_barcode = row.get("global_barcode")
    barcode = str(raw_barcode).strip() if raw_barcode is not None else ""
    identifier = classify_identifier(barcode)
    if not identifier.barcode_valid or identifier.global_barcode != barcode:
        return None, identifier.rejection_reason or "global_barcode_invalid"

    canonical_name = _optional_text(row.get("canonical_name"), 240)
    if not canonical_name:
        return None, "canonical_name_missing"
    source_url = _optional_text(row.get("source_product_url"))
    if not source_url or not source_url.startswith(
        ("https://www.ansargallery.com/", "https://ansargallery.com/")
    ):
        return None, "ansar_source_url_invalid"
    first_seen = _optional_text(row.get("first_seen_at"))
    last_seen = _optional_text(row.get("last_seen_at"))
    if not first_seen or not last_seen:
        return None, "observation_timestamp_missing"

    observation: dict[str, Any] = {
        "row_id": row_id,
        "source": SOURCE,
        "global_barcode": barcode,
        "barcode_format": _database_format(barcode),
        "canonical_name": canonical_name,
        "brand": _optional_text(row.get("brand"), 240),
        "primary_image_url": _valid_http_url(row.get("primary_image_url")),
        "ansar_sku": _optional_text(row.get("ansar_sku")),
        "source_product_url": source_url,
        "data_confidence": row.get("data_confidence"),
        "first_seen_at": first_seen,
        "last_seen_at": last_seen,
    }
    for field in RPC_FIELDS:
        value = row.get(field)
        if field in {"pack_count", "unit_quantity", "total_quantity"}:
            observation[field] = value
        else:
            observation[field] = _optional_text(value)
    return observation, None


def prepare_catalog(rows: list[dict[str, Any]]) -> PreparedCatalog:
    observations: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    eligible_ids: set[str] = set()
    for row in rows:
        observation, reason = _prepare_observation(row)
        row_id = _optional_text(row.get("id")) or "<missing-id>"
        if observation is None:
            rejected.append({"row_id": row_id, "reason": reason or "invalid_row"})
            continue
        observations.append(observation)
        eligible_ids.add(row_id)
    return PreparedCatalog(observations, rejected, eligible_ids)


def load_sync_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "version": SYNC_STATE_VERSION,
            "last_successfully_synchronized_crawler_run_id": None,
            "synchronized_at": None,
            "synchronized_product_ids": [],
            "rows_examined": 0,
            "rows_inserted": 0,
            "rows_enriched": 0,
            "rows_unchanged": 0,
            "rows_rejected": 0,
            "rejection_reasons": {},
            "errors": [],
        }
    with path.open("r", encoding="utf-8") as handle:
        state = json.load(handle)
    if state.get("version") != SYNC_STATE_VERSION:
        raise SupabaseSyncError(f"Unsupported sync state version: {state.get('version')!r}")
    return state


def save_sync_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


class SupabaseRestClient:
    def __init__(self, url: str, key: str, retries: int = 3, timeout: int = 30) -> None:
        self.url = url.rstrip("/")
        self.key = key
        self.retries = retries
        self.timeout = timeout

    @classmethod
    def from_environment(cls) -> "SupabaseRestClient":
        url = os.environ.get("SUPABASE_URL", "").strip()
        secret = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
        legacy = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        key = secret or legacy
        if not url:
            raise SupabaseSyncError("SUPABASE_URL is required.")
        if not key:
            raise SupabaseSyncError(
                "SUPABASE_SECRET_KEY is required; SUPABASE_SERVICE_ROLE_KEY is supported for legacy projects."
            )
        return cls(url, key)

    def _rpc(self, name: str, payload: dict[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers = {
            "apikey": self.key,
            "content-type": "application/json",
            "accept": "application/json",
            "user-agent": "ansar-catalog-sync/1.0",
        }
        if not self.key.startswith("sb_secret_"):
            headers["authorization"] = f"Bearer {self.key}"
        request = Request(
            f"{self.url}/rest/v1/rpc/{name}", data=body, headers=headers, method="POST"
        )
        last_error: Exception | None = None
        for attempt in range(self.retries):
            try:
                with urlopen(request, timeout=self.timeout) as response:
                    result = json.loads(response.read().decode("utf-8"))
                    if isinstance(result, list) and len(result) == 1 and isinstance(result[0], dict):
                        return result[0]
                    if not isinstance(result, dict):
                        raise SupabaseSyncError(f"RPC {name} returned an unexpected response.")
                    return result
            except HTTPError as error:
                last_error = error
                if error.code not in {408, 429, 500, 502, 503, 504}:
                    raise SupabaseSyncError(f"RPC {name} failed with HTTP {error.code}.") from error
            except (URLError, TimeoutError) as error:
                last_error = error
            if attempt + 1 < self.retries:
                time.sleep(2**attempt)
        raise SupabaseSyncError(f"RPC {name} failed after {self.retries} attempts.") from last_error

    def ingest(self, observation: dict[str, Any]) -> dict[str, Any]:
        payload = dict(observation)
        payload.pop("row_id", None)
        return self._rpc("ingest_ansar_catalog_observation", {"observation": payload})

    def verify(self, barcodes: list[str]) -> dict[str, Any]:
        return self._rpc("verify_ansar_catalog_sync", {"target_barcodes": barcodes})


def _rejection_counts(rejected: list[dict[str, str]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in rejected:
        reason = item["reason"]
        counts[reason] = counts.get(reason, 0) + 1
    return dict(sorted(counts.items()))


def verify_remote(
    client: CatalogSyncClient,
    prepared: PreparedCatalog,
    *,
    concurrency_probe: bool = False,
) -> dict[str, Any]:
    barcodes = [item["global_barcode"] for item in prepared.observations]
    before = client.verify(barcodes)
    if concurrency_probe and prepared.observations:
        probe = prepared.observations[0]
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(client.ingest, (probe, probe)))
        product_ids = {result.get("catalog_product_id") for result in results}
        if None in product_ids or len(product_ids) != 1:
            raise SupabaseSyncError("Concurrent ingestion did not resolve one CatalogProduct.")
    after = client.verify(barcodes)
    missing = after.get("missing")
    if missing != []:
        raise SupabaseSyncError(f"Remote verification found {len(missing or [])} missing barcodes.")
    requested = len(set(barcodes))
    if after.get("requested") != requested or after.get("matched") != requested:
        raise SupabaseSyncError("Remote barcode counts do not match the workbook.")
    if after.get("distinct_catalog_products") != requested:
        raise SupabaseSyncError("Different valid GTIN rows did not remain separate CatalogProducts.")
    if before.get("protected_counts") != after.get("protected_counts"):
        raise SupabaseSyncError("Verification changed protected shop or inventory tables.")
    return {
        "verified_barcodes": requested,
        "missing": [],
        "distinct_catalog_products": after.get("distinct_catalog_products"),
        "catalog_products": after.get("catalog_products"),
        "catalog_product_barcodes": after.get("catalog_product_barcodes"),
        "catalog_product_observations": after.get("catalog_product_observations"),
        "protected_counts": after.get("protected_counts"),
        "concurrency_probe": concurrency_probe,
    }


def synchronize(
    client: CatalogSyncClient,
    workbook_path: Path = WORKBOOK_PATH,
    state_path: Path = SYNC_STATE_PATH,
    *,
    full_reconcile: bool = False,
) -> dict[str, Any]:
    snapshot = ExcelRepository(workbook_path).snapshot()
    prepared = prepare_catalog(snapshot["products"])
    previous_state = load_sync_state(state_path)
    previously_synchronized = set(previous_state.get("synchronized_product_ids", []))
    selected = prepared.observations if full_reconcile else [
        item for item in prepared.observations if item["row_id"] not in previously_synchronized
    ]

    protected_before = client.verify([]).get("protected_counts")
    counts = {"inserted": 0, "enriched": 0, "unchanged": 0}
    synchronized_ids = set(previously_synchronized)
    for observation in selected:
        result = client.ingest(observation)
        status = result.get("status")
        if status not in counts:
            raise SupabaseSyncError(f"Unexpected ingestion status: {status!r}")
        if result.get("barcode") != observation["global_barcode"]:
            raise SupabaseSyncError("Ingestion response barcode did not match the request.")
        counts[status] += 1
        synchronized_ids.add(observation["row_id"])

    verification = verify_remote(client, prepared)
    if verification["protected_counts"] != protected_before:
        raise SupabaseSyncError("Catalog synchronization modified protected shop or inventory tables.")

    run_log = snapshot["run_log"]
    last_run_id = run_log[-1].get("run_id") if run_log else None
    state = {
        "version": SYNC_STATE_VERSION,
        "last_successfully_synchronized_crawler_run_id": last_run_id,
        "synchronized_at": utc_now(),
        "synchronized_product_ids": sorted(synchronized_ids | prepared.eligible_ids),
        "rows_examined": len(snapshot["products"]) if full_reconcile or not previous_state.get("synchronized_at") else len(selected),
        "valid_rows_imported": len(selected),
        "rows_inserted": counts["inserted"],
        "rows_enriched": counts["enriched"],
        "rows_unchanged": counts["unchanged"],
        "rows_rejected": len(prepared.rejected),
        "rejection_reasons": _rejection_counts(prepared.rejected),
        "errors": [],
    }
    save_sync_state(state_path, state)
    summary = dict(state)
    # The ID list is required for the durable incremental checkpoint, but is
    # intentionally omitted from logs: it grows with the catalog and adds no
    # useful operational signal.
    summary.pop("synchronized_product_ids", None)
    return {**summary, "state": str(state_path), "verification": verification}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Synchronize the Ansar catalog into Supabase")
    subparsers = parser.add_subparsers(dest="command", required=True)
    sync = subparsers.add_parser("sync")
    sync.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    sync.add_argument("--state", type=Path, default=SYNC_STATE_PATH)
    sync.add_argument("--all", "--full-reconcile", action="store_true", dest="full_reconcile")
    verify = subparsers.add_parser("verify")
    verify.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    verify.add_argument("--concurrency-probe", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    client = SupabaseRestClient.from_environment()
    if args.command == "sync":
        result = synchronize(
            client,
            args.workbook,
            args.state,
            full_reconcile=args.full_reconcile,
        )
    else:
        snapshot = ExcelRepository(args.workbook).snapshot()
        result = verify_remote(
            client,
            prepare_catalog(snapshot["products"]),
            concurrency_probe=args.concurrency_probe,
        )
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
