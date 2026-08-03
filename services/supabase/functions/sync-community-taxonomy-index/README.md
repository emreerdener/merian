# sync-community-taxonomy-index

Service-role-only worker for bounded GBIF imports into Merian's Community
Taxonomy Index.

For the running import ledger, next offsets, and follow-up checklist, see
`docs/backend-and-data/07-community-taxonomy-import-checklist.md`.

## Purpose

Community ID suggestions should be broader than Merian's enriched
`species_dictionary`, but Merian should not mirror all of GBIF. This worker
imports one bounded scope at a time into `taxon_nodes` and `taxon_names` through
the existing `upsert_gbif_community_taxa(...)` bridge.

v1 supports only the `birds` target:

- GBIF root taxon key: `212`
- Root rank: `class`
- Root scientific name: `Aves`
- Imported rows: accepted species from GBIF species search

## Request

`POST /functions/v1/sync-community-taxonomy-index`

Headers:

- Legacy key: `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` and
  `apikey: <SUPABASE_SERVICE_ROLE_KEY>`
- Named non-JWT project secret: `apikey: <sb_secret_...>` only

The worker accepts only an exact match from the shared resolver:
`SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
`MERIAN_SUPABASE_SERVER_API_KEY`, a value in the JSON `SUPABASE_SECRET_KEYS`
dictionary, the singular `SUPABASE_SECRET_KEY` local/manual fallback, or the
migration-only `SUPABASE_SERVICE_ROLE_KEY` legacy fallback. It does not infer
authority from taxonomy table reachability or an RLS-filtered result.
Conflicting Authorization/apikey credentials fail closed.

Body fields are optional:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 100,
  "page_count": 1,
  "dry_run": false,
  "refresh_coverage": true,
  "retry": false
}
```

Limits:

- `target`: only `birds` in v1
- `offset`: optional non-negative integer; omitted means continue from the
  target's stored `next_import_offset`
- `limit`: `1...200`
- `page_count`: `1...20`
- `refresh_coverage`: defaults to `true`; recomputes coverage once after the
  run, not after every page
- `retry`: defaults to `false`; when `true` and `offset` is omitted, replays the
  last failed offset or most recent successful page offset

## Behavior

Each page calls:

`GET https://api.gbif.org/v1/species/search?highertaxon_key=212&rank=SPECIES&status=ACCEPTED`

The worker normalizes GBIF rows into Merian's community taxon payload, calls
`upsert_gbif_community_taxa(...)`, then annotates the created import run as
`scope = "gbif_bounded_birds"` with page metadata. Each page suppresses the
expensive coverage refresh. After every successfully fetched page, the worker
checkpoints `taxonomy_coverage_targets.last_imported_offset` and
`next_import_offset`, including pages whose raw GBIF rows all normalize out. The
worker continues past those pages and stops only at `endOfRecords`, a raw empty
page, or the requested page count. After a successful run that imports at least
one row, it refreshes coverage once. If a later page fails, the worker records
its offset as `last_failed_offset`, so an earlier committed page is not replayed
by the next ordinary run and `retry = true` resumes at the first unprocessed
page.

GBIF transport failures plus HTTP `408`, `425`, `429`, and `5xx` responses are
retried at the read-only page-fetch boundary with a three-attempt, bounded-delay
ceiling. The worker does not automatically replay a mutation.

Use `dry_run: true` to verify the GBIF page and response shape without writing
taxonomy rows or the persisted cursor; the returned cursor still advances
through the pages that were simulated.

## Response

```json
{
  "success": true,
  "target": "birds",
  "root_gbif_taxon_key": 212,
  "dry_run": false,
  "retry": false,
  "refresh_coverage": true,
  "start_offset": 0,
  "imported_count": 50,
  "fetched_count": 50,
  "normalized_count": 50,
  "end_of_records": false,
  "next_offset": 50,
  "pages": [
    {
      "offset": 0,
      "limit": 50,
      "requested_query": "bounded:birds:root=212:rank=species:status=accepted:offset=0:limit=50",
      "fetched_count": 50,
      "normalized_count": 50,
      "imported_count": 50,
      "dry_run": false,
      "end_of_records": false,
      "next_offset": 50
    }
  ]
}
```

Call the endpoint again without `offset` to continue from the stored cursor, or
with `offset = next_offset` for explicit manual control.

## Manual Runbook

Run this worker manually after the current migrations and Edge Functions are
deployed.

Preferred local operator path:

```bash
SUPABASE_URL="https://qlarqavoqhkuwzmevrmf.supabase.co" \
SUPABASE_SERVER_API_KEY="$SUPABASE_SERVER_API_KEY" \
deno run --allow-net --allow-env --allow-read --allow-write \
  services/supabase/scripts/import_community_taxonomy.ts \
  --target birds --limit 100 --page-count 3 --update-checklist
```

Use `--dry-run` to verify the next cursor without writing, `--offset <n>` for
manual recovery, and `--retry` to replay the last failed or completed page.

Raw Edge Function fallback:

1. Dry-run the next cursor:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","limit":100,"page_count":1,"dry_run":true}'
```

2. Import from the stored cursor:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","limit":100,"page_count":1}'
```

3. Check status:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/community-taxonomy-status" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"view":"coverage","target":"birds","import_run_limit":10,"job_limit":1}'
```

4. Continue with an explicit offset only when recovering manually:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "apikey: $SUPABASE_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","offset":150,"limit":100,"page_count":1}'
```

Keep rollout batches at `page_count = 1...3` until status checks remain stable.
These preferred commands use a current `sb_secret_...` key. During legacy-key
migration only, send the same JWT in both `apikey` and
`Authorization: Bearer ...`. After several clean runs, scheduled imports may use
`page_count = 20` for the Birds target. Increase beyond manual defaults only
when `gbif_bounded_birds` import runs, coverage counts, and `next_import_offset`
advance as expected.
