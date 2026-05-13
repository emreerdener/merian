# refresh-species-content

Scheduled service-role worker for stale public species dictionary content.

The worker consumes `public.get_species_content_refresh_queue(...)`, groups rows
by species, refreshes supported public fields from GBIF/Wikipedia, updates
`species_dictionary`, synchronizes normalized `species_reference_images`, and
records fresh `species_content_provenance` rows.

## Security

- `verify_jwt = false` in `supabase/config.toml` so `pg_net` can invoke the
  function without gateway JWT validation.
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
  extras behind freshly verified rows.
- `refresh_species_content_hourly`, a `pg_cron` schedule that invokes
  `/functions/v1/refresh-species-content` through `pg_net`.

## Boundaries

The worker does not refresh model-heavy or review-heavy fields in V1:
`common_names`, `habitat_description`, `lookalikes`, `group_tags`,
`iucn_red_list_status`, and `hazard_type` are skipped until curation/model
refresh tooling can update them safely.
