# Community Taxonomy Import Checklist

Running checklist for Merian's bounded GBIF-backed Community Taxonomy Index
imports. Update this file whenever we run another import batch, change the
worker, or promote coverage information into product surfaces.

Last updated: 2026-06-23

## Current Policy

- Import scope is intentionally bounded. Do not mirror all of GBIF.
- `species_dictionary` remains Merian's enriched subset. GBIF imports populate
  `taxon_nodes` and `taxon_names` only.
- Materialize Dictionary rows only through explicit triggers such as
  owner-published Community ID consensus, scan confirmation, Dictionary
  navigation, or curation.
- Prefer the **Import Community Taxonomy** GitHub Actions workflow for
  production imports. It uses the existing production service-role secret and
  constructs the Supabase URL from the project ref, so no local key or URL
  export is required.
- Use the local operator script only when GitHub Actions is unavailable or when
  intentionally updating this checklist from a trusted local environment.
- Keep batches bounded. `limit = 100`, `page_count = 1...3` is the normal
  post-smoke path; use smaller batches when recovering from failures.
- Do not show gamified coverage claims until a target has a meaningful imported
  denominator and the product wording explains that it is based on the indexed
  target scope.

## Production Status

Last verified remote status: 2026-06-23 after Birds batch 3.

| Target         | GBIF Root | Imported Offsets | Imported Rows | Next Offset | Indexed Species | Dictionary Species |   Coverage |
| -------------- | --------- | ---------------- | ------------: | ----------: | --------------: | -----------------: | ---------: |
| Birds (`Aves`) | `212`     | `0`, `50`, `100` |         `150` |       `150` |           `218` |               `69` | `0.316514` |

GBIF reported `14,641` accepted bird species under Aves during the first import
run. This is the expected rough denominator for completing the Birds target over
time, but Merian's stored denominator should come from
`taxonomy_coverage_targets.indexed_species_count`, not from this note.
`taxonomy_coverage_targets.last_imported_offset` is the most recent successful
GBIF page offset. `taxonomy_coverage_targets.next_import_offset` is the machine
cursor used when the import worker is called without an explicit `offset`.

## Completed Import Batches

| Date       | Target | Offset | Limit | Normalized | Imported | Import Scope         | Result                      |
| ---------- | ------ | -----: | ----: | ---------: | -------: | -------------------- | --------------------------- |
| 2026-06-22 | Birds  |    `0` |  `50` |       `50` |     `50` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-22 | Birds  |   `50` |  `50` |       `50` |     `50` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-23 | Birds  |  `100` |  `50` |       `50` |     `50` | `gbif_bounded_birds` | Complete, `error_count = 0` |

## Next Import Batches

- [ ] Birds offset `150`, limit `100`.
- [ ] Birds offset `250`, limit `100`.
- [ ] Birds offset `350`, limit `100`.
- [ ] Recheck `community-taxonomy-status` coverage view after every 1-3 batches.
- [ ] Stop and investigate if any import row has `status != completed` or
      `error_count > 0`.

## Operational Checklist

Before importing:

- [ ] Confirm the latest migrations are deployed.
- [ ] Confirm `sync-community-taxonomy-index` and `community-taxonomy-status`
      are deployed.
- [ ] Run the **Import Community Taxonomy** GitHub Actions workflow with
      `dry_run = true`.
- [ ] Confirm the latest completed import run and coverage target values.

During each import:

- [ ] Run the **Import Community Taxonomy** GitHub Actions workflow with
      `dry_run = false`.
- [ ] Import a bounded batch: `target = birds`, `limit = 100`,
      `page_count = 1...3`.
- [ ] Record the response's `normalized_count`, `imported_count`,
      `end_of_records`, and `next_offset`.
- [ ] Confirm the corresponding `taxonomy_import_runs` row is annotated with
      `scope = gbif_bounded_birds`.
- [ ] Confirm `taxonomy_coverage_targets.last_imported_offset`,
      `next_import_offset`, and `last_computed_at` advance.

After importing:

- [ ] Update the completed-batch table above.
- [ ] Update the production status table above.
- [ ] Update `Next Import Batches` so the next offset is obvious.
- [ ] If the imported denominator changes product-visible coverage math, review
      any related user-facing copy before exposing it.

## Known Follow-Ups

- [x] Fix and remotely verify `sync-community-taxonomy-index` and
      `community-taxonomy-status` Edge Function auth. Both functions now accept
      an exact env-key match or prove service-role access through a
      service-role-only taxonomy import read. Production smoke checks returned
      `HTTP 200` for status and dry-run import on 2026-06-22.
- [x] Optimize `community-taxonomy-status` before using it as the main import
      monitor for larger batches. The broad status call hung during the
      2026-06-23 offset `100` follow-up, while targeted coverage and latest-run
      reads returned quickly. The endpoint now supports `view = coverage` for
      lightweight target-specific status reads.
- [x] Add a safer operator script for imports so future batches do not require
      ad hoc shell payload construction.
- [x] Add remote smoke checks to the deployment runbook for status and dry-run
      import. CI now checks coverage status plus a tiny dry-run import after
      Edge Function deployment.
- [ ] Add more coverage targets only after Birds import behavior is stable.

## Commands

Preferred GitHub Actions path:

1. Open GitHub Actions.
2. Select **Import Community Taxonomy**.
3. Click **Run workflow**.
4. Leave `dry_run = true` for the first check.
5. If the dry run passes, run again with `dry_run = false`.

Preferred operator command:

```bash
SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co" \
SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
deno run --allow-net --allow-env --allow-read --allow-write \
  services/supabase/scripts/import_community_taxonomy.ts \
  --target birds --limit 100 --page-count 3 --update-checklist
```

Dry run without advancing the cursor:

```bash
SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co" \
SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
deno run --allow-net --allow-env --allow-read --allow-write \
  services/supabase/scripts/import_community_taxonomy.ts \
  --target birds --limit 100 --page-count 1 --dry-run
```

Fallback Edge Function call:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","limit":100,"page_count":1}'
```

Status check:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/community-taxonomy-status" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"view":"coverage","target":"birds","import_run_limit":10,"job_limit":1}'
```

Use the service-role database RPC path only if the Edge Function path regresses,
keep batches small, and update this checklist immediately after each run.
