# Community Taxonomy Import Checklist

Running checklist for Merian's bounded GBIF-backed Community Taxonomy Index
imports. Update this file whenever we run another import batch, change the
worker, or promote coverage information into product surfaces.

Last updated: 2026-06-22

## Current Policy

- Import scope is intentionally bounded. Do not mirror all of GBIF.
- `species_dictionary` remains Merian's enriched subset. GBIF imports populate
  `taxon_nodes` and `taxon_names` only.
- Materialize Dictionary rows only through explicit triggers such as
  owner-published Community ID consensus, scan confirmation, Dictionary
  navigation, or curation.
- Keep early imports manual and one page at a time until rollout status remains
  stable.
- Do not show gamified coverage claims until a target has a meaningful imported
  denominator and the product wording explains that it is based on the indexed
  target scope.

## Production Status

Last verified remote status: 2026-06-22 after Birds batch 2 and Edge Function
auth fix deployment.

| Target         | GBIF Root | Imported Offsets | Imported Rows | Next Offset | Indexed Species | Dictionary Species |   Coverage |
| -------------- | --------- | ---------------- | ------------: | ----------: | --------------: | -----------------: | ---------: |
| Birds (`Aves`) | `212`     | `0`, `50`        |         `100` |       `100` |           `169` |               `69` | `0.408284` |

GBIF reported `14,641` accepted bird species under Aves during the first import
run. This is the expected rough denominator for completing the Birds target over
time, but Merian's stored denominator should come from
`taxonomy_coverage_targets.indexed_species_count`, not from this note.

## Completed Import Batches

| Date       | Target | Offset | Limit | Normalized | Imported | Import Scope         | Result                      |
| ---------- | ------ | -----: | ----: | ---------: | -------: | -------------------- | --------------------------- |
| 2026-06-22 | Birds  |    `0` |  `50` |       `50` |     `50` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-22 | Birds  |   `50` |  `50` |       `50` |     `50` | `gbif_bounded_birds` | Complete, `error_count = 0` |

## Next Import Batches

- [ ] Birds offset `100`, limit `50`.
- [ ] Birds offset `150`, limit `50`.
- [ ] Birds offset `200`, limit `50`.
- [ ] Recheck `community-taxonomy-status` after every 1-3 batches.
- [ ] Stop and investigate if any import row has `status != completed` or
      `error_count > 0`.

## Operational Checklist

Before importing:

- [ ] Confirm the latest migrations are deployed.
- [ ] Confirm `sync-community-taxonomy-index` and `community-taxonomy-status`
      are deployed.
- [ ] Run a dry run for the next offset through `sync-community-taxonomy-index`.
- [ ] Confirm the latest completed import run and coverage target values.

During each import:

- [ ] Import one page for early rollout: `target = birds`, `limit = 50`,
      `page_count = 1`.
- [ ] Record the response's `normalized_count`, `imported_count`,
      `end_of_records`, and `next_offset`.
- [ ] Confirm the corresponding `taxonomy_import_runs` row is annotated with
      `scope = gbif_bounded_birds`.
- [ ] Confirm `taxonomy_coverage_targets.last_computed_at` advances.

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
- [ ] Add a safer operator script for imports so future batches do not require
      ad hoc shell payload construction.
- [ ] Add remote smoke checks to the deployment runbook for status and dry-run
      import.
- [ ] Add more coverage targets only after Birds import behavior is stable.

## Commands

Preferred Edge Function call:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","offset":100,"limit":50,"page_count":1}'
```

Status check:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/community-taxonomy-status" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"import_run_limit":10,"job_limit":10}'
```

Use the service-role database RPC path only if the Edge Function path regresses,
keep batches small, and update this checklist immediately after each run.
