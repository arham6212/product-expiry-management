# Ansar Gallery Qatar catalog crawler

This isolated utility builds one persistent, database-ready product catalog. It
does not touch Flutter, Supabase, prices, carts, inventory, batches, or expiry
data.

## Commands

```bash
# Collect up to 50 new products now
python3 -m tools.ansar_catalog.cli run_once

# Seed/migrate brand and family coverage without crawling
python3 -m tools.ansar_catalog.cli seed_coverage

# Fill only confidently inferable missing brand fields in place
python3 -m tools.ansar_catalog.cli repair_details

# Verify row counts, headers, and uniqueness
python3 -m tools.ansar_catalog.cli verify --preview-dir data/verification_previews

# Synchronize only rows added since the last successful checkpoint
SUPABASE_URL=... SUPABASE_SECRET_KEY=... \
  python3 -m tools.ansar_catalog.sync_supabase sync

# Reconcile every valid Ansar row for recovery or enrichment
SUPABASE_URL=... SUPABASE_SECRET_KEY=... \
  python3 -m tools.ansar_catalog.sync_supabase sync --full-reconcile

# Start durable scheduling (macOS launchd or Linux systemd user timer)
python3 -m tools.ansar_catalog.scheduler install

# Stop and remove scheduling
python3 -m tools.ansar_catalog.scheduler uninstall

# Generate both scheduler templates without activating them
python3 -m tools.ansar_catalog.scheduler generate
```

For GitHub-hosted operation, use `.github/workflows/ansar-catalog.yml`. Do not
also install the local launchd/systemd scheduler, because that would create two
independent writers for the same checkpoint.

The schedule is an elapsed **18,000 seconds / 5 hours** (`StartInterval=18000`
on macOS, `OnUnitActiveSec=5h` on Linux), not the uneven cron expression
`0 */5 * * *`. The scheduler runs at load/within five minutes of boot and then
every five hours. Linux uses `Persistent=true` so a missed run is caught up.

Logs are under `data/logs/`. On Linux inspect the timer with
`systemctl --user status ansar-catalog.timer` and execution logs with
`journalctl --user -u ansar-catalog.service`. On macOS use
`launchctl print gui/$UID/com.openai.ansar-catalog` plus the two scheduler log
files.

## Persistence and safety

- Workbook: `data/ansar_gallery_product_catalog.xlsx`
- Crawl state: `data/ansar_gallery_crawl_state.json`
- Excel is loaded before every run and is the deduplication source of truth.
- Validated global barcode is the primary key. Normalized identity + Ansar SKU
  + source URL is the fallback key.
- The workbook is written to a same-directory temporary file and atomically
  renamed only after export succeeds.
- Crawl progress advances only after the workbook transaction succeeds.
- An exclusive lock prevents overlapping scheduler/manual runs.

## Brand and family completeness

Discovering a product now creates durable coverage jobs. A brand job scans all
grocery category pages for that brand; a stable product-family job scans its
category; and discovering a soft drink creates a broader Soft Drinks job. Jobs
store their own category/page cursors and remain in the state file until every
applicable Ansar page is exhausted.

Each 50-product run prefers 45 coverage products and reserves 5 positions for
fresh category discovery. If either side has fewer candidates, the other side
fills the batch. A single coverage job contributes at most 6 candidates per
run, so a large portfolio such as Nestle cannot crowd out every other brand.
Nestle portfolio name aliases (for example Nestle, Nescafe, Nesquik, Maggi,
Milo, Nido, Cerelac, KitKat, and Lion cereal) are included as crawl hints.
Coca-Cola and Soft Drinks coverage includes distinct flavors, container sizes,
and multipacks. Each sellable GTIN remains a separate product row.

Workbook operations use the pinned Python `openpyxl` dependency so the same
code runs on GitHub-hosted runners without a private Codex runtime. The bundled
workflow tests and verifies the catalog before committing the workbook and
state back to the same repository paths.

## Supabase synchronization

The hosted workflow synchronizes verified Ansar observations only after the
crawl and workbook integrity checks pass. It prefers `SUPABASE_SECRET_KEY` and
supports `SUPABASE_SERVICE_ROLE_KEY` only for legacy projects. These values are
GitHub Actions secrets and must never be stored in the repository or printed.

`data/ansar_supabase_sync_state.json` advances only after every selected row and
the complete remote verification succeed. Database uniqueness plus the
per-barcode transaction lock makes a retry safe even if database writes commit
before a failed job can save its checkpoint. Ingestion can create or enrich
global catalog data and provenance only; it never writes shop Products,
barcodes, prices, batches, inventory movements, listings, or deals.
