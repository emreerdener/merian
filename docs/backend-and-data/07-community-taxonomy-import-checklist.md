# Community Taxonomy Import Checklist

Running checklist for Merian's bounded GBIF-backed Community Taxonomy Index
imports. Update this file whenever we run another import batch, change the
worker, or promote coverage information into product surfaces.

Last updated: 2026-07-20

## Current Policy

- Import scope is intentionally bounded. Do not mirror all of GBIF.
- `species_dictionary` remains Merian's enriched subset. GBIF imports populate
  `taxon_nodes` and `taxon_names` only.
- Materialize Dictionary rows only through explicit triggers such as
  owner-published Community ID consensus, scan confirmation, Dictionary
  navigation, or curation.
- Prefer the **Import Community Taxonomy** GitHub Actions workflow for
  production imports. It resolves a current secret key (or the exact legacy
  service-role fallback) at runtime from Supabase using the existing
  `SUPABASE_ACCESS_TOKEN` secret and constructs the Supabase URL from the project
  ref, so no local key or URL export is required.
- Use the local operator script only when GitHub Actions is unavailable or when
  intentionally updating this checklist from a trusted local environment.
- Keep batches bounded. `limit = 100`, `page_count = 1...20` is the supported
  range; use smaller batches when recovering from failures.
- The **Import Community Taxonomy** workflow runs weekly on Mondays at
  `09:20 UTC` with `page_count = 20`, `dry_run = false`, and
  `update_checklist = true`.
- Do not show gamified coverage claims until a target has a meaningful imported
  denominator and the product wording explains that it is based on the indexed
  target scope.

## Production Status

Last verified remote status: 2026-07-20 after Birds offset 6750.
Coverage values below still reflect the last captured status snapshot; refresh
`community-taxonomy-status` coverage view before exposing any progress claim.

| Target         | GBIF Root | Imported Offsets | Imported Rows | Next Offset | Indexed Species | Dictionary Species |   Coverage |
| -------------- | --------- | ---------------- | ------------: | ----------: | --------------: | -----------------: | ---------: |
| Birds (`Aves`) | `212`     | `0`, `50`, `100`, `150`, `350`, `450`, `550`, `650`, `750`, `850`, `950`, `1050`, `1150`, `1250`, `1350`, `1450`, `1550`, `1650`, `1750`, `1850`, `1950`, `2050`, `2150`, `2250`, `2350`, `2450`, `2550`, `2650`, `2750`, `2850`, `2950`, `3050`, `3150`, `3250`, `3350`, `3450`, `3550`, `3650`, `3750`, `3850`, `3950`, `4050`, `4150`, `4250`, `4350`, `4450`, `4550`, `4650`, `4750`, `4850`, `4950`, `5050`, `5150`, `5250`, `5350`, `5450`, `5550`, `5650`, `5750`, `5850`, `5950`, `6050`, `6150`, `6250`, `6350`, `6450`, `6550`, `6650`, `6750`, `6850`, `6950`, `7050`, `7150`, `7250`, `7350`, `7450`, `7550`, `7650`, `7750`, `7850`, `7950`, `8050`, `8150`, `8250`, `8350`, `8450`, `8550`, `8650` |         `8650` |       `8750` |           `8772` |               `69` | `0.007866` |

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
| 2026-06-23 | Birds  |  `150` | `100` |      `100` |    `100` | `gbif_bounded_birds` | Complete via GitHub Actions import run #2 |

| 2026-06-23 | Birds  |  `350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-23 | Birds  |  `450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-23 | Birds  |  `550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

| 2026-06-29 | Birds  |  `650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `1950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-06-29 | Birds  |  `2550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

| 2026-07-06 | Birds  |  `2650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `2750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `2850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `2950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `3950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-06 | Birds  |  `4550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

| 2026-07-10 | Birds  |  `4650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

| 2026-07-13 | Birds  |  `4750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `4850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `4950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `5950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-13 | Birds  |  `6650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

| 2026-07-20 | Birds  |  `6750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `6850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `6950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7750` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7850` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `7950` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8050` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8150` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8250` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8350` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8450` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8550` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |
| 2026-07-20 | Birds  |  `8650` | `100` |       `100` |     `100` | `gbif_bounded_birds` | Complete, `error_count = 0` |

## Next Import Batches

- [ ] Birds offset `8750`, limit `100`.
- [ ] Birds offset `8850`, limit `100`.
- [ ] Birds offset `8950`, limit `100`.
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
      `community-taxonomy-status` Edge Function auth. Both functions now require
      an exact platform-managed legacy or named secret-key match; a table/RLS
      read is never authorization evidence. Production deploys first prove real
      anon/publishable keys receive `HTTP 401`, then use the real service-role
      key as the positive status and dry-run control.
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
- [x] Add import workflow summaries and an isolated checklist writer so real
      imports can pass a one-day artifact from a `contents: read` import job to
      the sole scoped `contents: write` job without local credential handling.
- [x] Schedule weekly bounded Birds imports now that manual `page_count = 3`
      runs have succeeded.
- [x] Speed up Birds import throughput to weekly `page_count = 20` while
      keeping the bounded target, summaries, and checklist commits.
- [ ] Add more coverage targets only after Birds import behavior is stable.

## Commands

Preferred GitHub Actions path:

1. Open GitHub Actions.
2. Select **Import Community Taxonomy**.
3. Click **Run workflow**.
4. Leave `dry_run = true` after deploys, auth changes, migration changes, or
   failures.
5. For routine imports after a clean prior run, set `dry_run = false`.
6. Leave `update_checklist = true` so the read-only import job publishes the
   completed-batch ledger artifact and the isolated writer job commits it.
7. Prefer the scheduled Monday run for routine progress; use manual dispatch for
   recovery, dry runs, or intentionally pulling a batch forward.

Preferred operator command:

```bash
SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co" \
SUPABASE_SERVER_API_KEY="$SUPABASE_SERVER_API_KEY" \
deno run --allow-net --allow-env --allow-read --allow-write \
  services/supabase/scripts/import_community_taxonomy.ts \
  --target birds --limit 100 --page-count 3 --update-checklist
```

Dry run without advancing the cursor:

```bash
SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co" \
SUPABASE_SERVER_API_KEY="$SUPABASE_SERVER_API_KEY" \
deno run --allow-net --allow-env --allow-read --allow-write \
  services/supabase/scripts/import_community_taxonomy.ts \
  --target birds --limit 100 --page-count 1 --dry-run
```

Fallback Edge Function call:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","limit":100,"page_count":1}'
```

Status check:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/community-taxonomy-status" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"view":"coverage","target":"birds","import_run_limit":10,"job_limit":1}'
```

These preferred commands use a current `sb_secret_...` key. During legacy-key
migration only, send the same JWT in both `apikey` and
`Authorization: Bearer ...`.

Use the service-role database RPC path only if the Edge Function path regresses,
keep batches small, and update this checklist immediately after each run.
