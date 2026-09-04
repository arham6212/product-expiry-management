from __future__ import annotations

import argparse
import json
from pathlib import Path

from .config import STATE_PATH, TARGET_PRODUCTS, WORKBOOK_PATH
from .crawler import AnsarCatalogCrawler
from .coverage import infer_explicit_brand_prefix
from .excel_repository import ExcelRepository
from .state_repository import StateRepository


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Persistent Ansar Gallery Qatar grocery catalog crawler")
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run_once", help="collect one batch and exit")
    run.add_argument("--target", type=int, default=TARGET_PRODUCTS)
    run.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    run.add_argument("--state", type=Path, default=STATE_PATH)
    verify = sub.add_parser("verify", help="verify workbook structure and uniqueness")
    verify.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    verify.add_argument("--preview-dir", type=Path)
    seed = sub.add_parser("seed_coverage", help="migrate and seed persistent brand/family coverage jobs")
    seed.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    seed.add_argument("--state", type=Path, default=STATE_PATH)
    repair = sub.add_parser("repair_details", help="apply conservative in-place product detail corrections")
    repair.add_argument("--workbook", type=Path, default=WORKBOOK_PATH)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "run_once":
        result = AnsarCatalogCrawler(args.workbook, args.state).run_once(args.target)
    elif args.command == "verify":
        result = ExcelRepository(args.workbook).verify(args.preview_dir)
    elif args.command == "seed_coverage":
        states = StateRepository(args.state)
        state = states.load()
        rows = ExcelRepository(args.workbook).snapshot()["products"]
        created = states.reconcile_coverage_jobs(state, rows)
        states.save(state)
        result = {
            "products_examined": len(rows),
            "coverage_jobs_created": created,
            "coverage_jobs_total": len(state["coverage_jobs"]),
            "state": str(args.state),
        }
    else:
        excel = ExcelRepository(args.workbook)
        rows = excel.snapshot()["products"]
        patches = []
        for row in rows:
            if row.get("brand"):
                continue
            inferred = infer_explicit_brand_prefix(str(row.get("canonical_name") or ""))
            if inferred:
                patches.append({"id": row["id"], "values": {"brand": inferred}})
        result = {
            "products_examined": len(rows),
            "rows_corrected": excel.patch_products(patches),
            "corrections": [{"id": patch["id"], **patch["values"]} for patch in patches],
            "workbook": str(args.workbook),
        }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
