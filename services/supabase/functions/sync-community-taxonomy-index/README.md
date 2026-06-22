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

- `Authorization: Bearer <service-role credential>`

The worker accepts an exact `SUPABASE_SERVICE_ROLE_KEY` environment match or a
project service-role token that can prove access to service-role-only taxonomy
import state.

Body fields are optional:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false
}
```

Limits:

- `target`: only `birds` in v1
- `offset`: non-negative integer
- `limit`: `1...200`
- `page_count`: `1...5`

## Behavior

Each page calls:

`GET https://api.gbif.org/v1/species/search?highertaxon_key=212&rank=SPECIES&status=ACCEPTED`

The worker normalizes GBIF rows into Merian's community taxon payload, calls
`upsert_gbif_community_taxa(...)`, then annotates the created import run as
`scope = "gbif_bounded_birds"` with page metadata. The existing RPC refreshes
taxonomy coverage targets after each successful page.

Use `dry_run: true` to verify the GBIF page and response shape without writing
taxonomy rows.

## Response

```json
{
  "success": true,
  "target": "birds",
  "root_gbif_taxon_key": 212,
  "dry_run": false,
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

Call the endpoint again with `offset = next_offset` to continue the import.

## Manual Runbook

Run this worker manually after the current migrations and Edge Functions are
deployed.

1. Dry-run the first page:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","offset":0,"limit":50,"page_count":1,"dry_run":true}'
```

2. Import the first page:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","offset":0,"limit":50,"page_count":1}'
```

3. Check status:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/community-taxonomy-status" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"import_run_limit":10,"job_limit":10}'
```

4. Continue with the next batch using the previous response's `next_offset`:

```bash
curl -sS \
  -X POST "$SUPABASE_URL/functions/v1/sync-community-taxonomy-index" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"target":"birds","offset":50,"limit":50,"page_count":1}'
```

Keep early rollout batches to one page at a time. Increase `page_count` only
after status checks show expected `gbif_bounded_birds` import runs and coverage
counts.
