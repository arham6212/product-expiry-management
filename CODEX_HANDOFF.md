# Codex handoff: install the persistent Ansar crawler

Copy this bundle into the repository root without renaming `data/`, `tools/`,
`tests/`, or `.github/workflows/ansar-catalog.yml`.

Then ask Codex to perform this task:

> Install the supplied Ansar crawler bundle at the repository root. Preserve
> `data/ansar_gallery_product_catalog.xlsx` and
> `data/ansar_gallery_crawl_state.json` exactly as the persistent checkpoint;
> do not regenerate or truncate either file. Review the workflow and crawler,
> run `python -m pip install -r requirements.txt`, run
> `python -m unittest discover -s tests -v`, then run
> `python -m tools.ansar_catalog.cli verify`. Fix only genuine portability or
> test failures. Do not run `run_once` locally because that would mutate the
> checkpoint. Commit all supplied files. Push the branch, enable GitHub Actions,
> and manually dispatch `Grow Ansar Catalog` once. Confirm that the workflow
> adds to the same workbook and state, passes integrity verification, and
> commits those same files. Ansar Gallery must remain the primary source.
> Never use a Snoonu identifier as global product identity. Do not collect or
> sync prices, expiry, batches, inventory, Flutter code, Supabase, or migrations.

The workflow runs hourly at minute 17 UTC. GitHub may delay scheduled jobs.
Repository Actions must have **Read and write permissions** under Settings →
Actions → General → Workflow permissions.
