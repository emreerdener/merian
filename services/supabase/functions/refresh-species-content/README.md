# refresh-species-content

Scheduled service-role worker for stale public species dictionary content.

The worker claims first-class `species_enrichment_jobs` for the
`gbif_wikipedia_reference` content group, groups work by species, refreshes
supported public fields from GBIF/Wikipedia, updates `species_dictionary`,
synchronizes normalized `species_reference_images`, and records fresh
`species_content_provenance` rows. If no jobs are queued, it falls back to the
legacy `public.get_species_content_refresh_queue(...)` provenance queue.

## Security

- `verify_jwt = false` in `services/supabase/config.toml` so `pg_net` can invoke
  the function without gateway JWT validation.
- The function still requires
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and compares it with
  `timingSafeCompare`.
- It is not an iOS or public web endpoint.

## Request

The scheduled cron sends:

```json
{ "limit": 25 }
```

Manual runs may also send:

```json
{
  "limit": 10,
  "dry_run": true,
  "as_of": "2026-05-13T00:00:00Z",
  "content_keys": ["wikipedia_url", "reference_images"]
}
```

`limit` defaults to `25` and is capped at `100` per Edge invocation. Species
refreshes run with a concurrency cap of `4` so the hourly worker stays inside
Edge runtime bounds without stampeding GBIF/Wikipedia. `content_keys` may
include any known provenance key, but V1 refreshes only:

- `alternative_common_names`
- `taxonomy`
- `wikipedia_url`
- `wikipedia_overview`
- `gbif_taxon_key`
- `reference_images`

Unsupported queued keys are reported as skipped rather than overwritten.

## Response

```json
{
  "success": true,
  "queued_count": 12,
  "planned_count": 4,
  "refreshed_count": 3,
  "no_data_count": 1,
  "failed_count": 0,
  "skipped_count": 8,
  "skipped": [],
  "results": []
}
```

Per-species failures are logged and reported in `results`; one failed species
does not abort the rest of the batch.

## Database Support

Migration `20260513070000_add_species_content_refresh_worker_schedule.sql` adds:

- `public.replace_species_reference_images(UUID, JSONB)`, executable only by
  `service_role`. It upserts refreshed images, removes stale unlicensed rows,
  preserves existing license/attribution metadata, and demotes curated licensed
  extras behind freshly verified rows. `source = "merian"` rows are preserved
  because they are owned by `/refresh-merian-reference-images`.
- `refresh_species_content_hourly`, a `pg_cron` schedule that invokes
  `/functions/v1/refresh-species-content` through `pg_net`.

Migration `20260622030000_long_term_community_taxonomy_index.sql` adds:

- `species_enrichment_jobs`, the operational queue for newly materialized
  species.
- `public.claim_species_enrichment_jobs(...)` and
  `public.complete_species_enrichment_job(...)`, executable only by
  `service_role`.

Migration `20260707153931_species_dictionary_enrichment_queue_backfill.sql` adds
the `species_dictionary` insert trigger and sparse-row backfill that feed
`gbif_wikipedia_reference` jobs into this worker and model-heavy jobs into
`refresh-species-model-content`.

## Boundaries

The worker does not refresh model-heavy or review-heavy fields: `common_names`,
`habitat_description`, `lookalikes`, `group_tags`, `iucn_red_list_status`, and
`hazard_type` are skipped here. Habitat, lookalikes, and group tags are handled
by `/refresh-species-model-content`; common-name overrides, conservation, and
hazard data remain curation-owned.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/refresh-species-content/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/refresh-species-content/db.test.ts
```

`supabase db lint --local --fail-on error` should also be run when a local
Supabase database is available so the migration helper and cron schedule are
validated against PostgreSQL.
