# refresh-species-content

Scheduled service-role worker for stale public species dictionary content.

The worker claims first-class `species_enrichment_jobs` for the
`gbif_wikipedia_reference` content group, groups work by species, refreshes
supported public fields from GBIF/Wikipedia, updates `species_dictionary`,
synchronizes normalized `species_reference_images`, atomically replaces
service-owned `species_country_occurrences`, and records fresh
`species_content_provenance` rows. If no jobs are queued, it falls back to the
legacy `public.get_species_content_refresh_queue(...)` provenance queue.

External reference images are filtered by `_shared/externalImagePolicy.ts`
before either the legacy comma-separated cache or the normalized-image RPC
payload is built. The current exact rule removes all URL variants below
`inaturalist-open-data.s3.amazonaws.com/photos/605615444/` while preserving the
relative order of permitted images.

## Reference image rights

The durable worker uses `fetchExternalEnrichmentWithImageRights(...)`. It keeps
image URLs in the legacy cache and sends verified per-image `license` and
`attribution` through the existing `replace_species_reference_images` RPC. No
schema or public response version changes are needed. Interactive identification
continues using the URL-only enrichment path; the additional Commons request
runs only in the durable worker, never during web page rendering.

GBIF rights come only from each media item's `license`, `creator`, and
`rightsHolder`, never the occurrence's license or observer. Wikimedia Commons
rights come from the exact file's Imageinfo `extmetadata`, with returned
original URL identity checked against the selected image. Custom attribution
takes precedence over Artist/Credit; provider HTML becomes bounded plain text.
The lookup uses a fixed Commons API origin, rejects redirects, and retains the
shared 2.5-second deadline and 256 KiB response limit. Transport,
malformed-response, and API failures fail the species job before database writes
so it can retry.

Automatic ingestion accepts explicit CC BY, CC BY-SA (including the 3.0
Australia versions), CC0, and public-domain terms. Jurisdiction-specific
licenses retain their original jurisdiction in the canonical license link.
Restricted, unknown, non-free, deletion-pending, or incompletely credited
provider results supply no new rights fields; their availability in iOS does not
establish web eligibility. The existing RPC preserves previously stored/curated
credits when incoming rights are absent and gives existing non-null credits
precedence. This change fills missing metadata; it is not a rights-revocation or
credit-correction mechanism. Those changes require separately reviewed curation.
The public web attribution gate remains required for both page media and social
previews. Captions link the license and either the exact Commons file page or
GBIF's supplied original media URL.

### Existing-image refresh after an authorized deployment

Existing image URLs can satisfy the enrichment completeness predicate even when
rights are absent. Deploying this code alone does not guarantee that those rows
are queued. After separately authorized deployment and data refresh on the named
project:

1. Review a bounded list of canonical species UUIDs whose external reference
   images lack license or attribution, including legacy URL-only entries.
2. Enqueue each reviewed UUID through the existing service-only
   `enqueue_species_enrichment_jobs` RPC with `target_species_id` set to that
   UUID, `source_trigger: "reference_image_rights_backfill"`,
   `priority_value: 80`, and `content_groups: ["gbif_wikipedia_reference"]`. Do
   not change grants or bulk-reset job state. Running jobs are left alone;
   failed/exhausted jobs need separate operational review under the existing
   retry controls.
3. Let the scheduled worker process the queue, or explicitly authorize a bounded
   `/refresh-species-content` run with its normal `limit` (25 by default). Keep
   the full content group so unrelated pending fields are not marked complete by
   a reference-only run.
4. Verify stored image-specific credits, the public `species-dictionary`
   response, and the web gallery/caption/social preview after its five-minute
   revalidation window. Images still lacking verified credits stay hidden.

This procedure prepares a repair; it does not authorize production writes or
claim that existing data has already been refreshed.

## Security

- `verify_jwt = false` in `services/supabase/config.toml` so `pg_net` can invoke
  the function without gateway JWT validation.
- The function still requires one exact current or legacy server key through
  `_shared/serviceRoleAuth.ts`; opaque keys use `apikey` only.
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
- `country_occurrences`

Unsupported queued keys are reported as skipped rather than overwritten. Country
occurrence refresh uses GBIF's country facet for georeferenced PRESENT records
without geospatial issues. A valid empty facet clears stale rows and is recorded
as a successful refresh; a timeout, non-OK response, or malformed payload fails
the species job so existing coverage is retained and retried. If the fresh GBIF
name match is unavailable, the worker uses an existing positive dictionary taxon
key; if neither identity is available, it fails the durable job for retry rather
than silently completing partial hydration. The scheduled worker treats
provenance writes as durable job state: if a replacement succeeds but its
provenance upsert fails, the species job fails and retries. Interactive
identification paths continue to record provenance on a best-effort basis so a
telemetry-side failure cannot block an identification.

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

Migration `20260719023147_suppress_european_wildcat_roadkill_image.sql` removes
iNaturalist media `605615444` from normalized and legacy caches, filters it from
the public first/all-image SQL helpers, and adds a service-write trigger that
silently discards future normalized rows for that exact media path. This is a
database backstop for refresh or repair code; Edge filtering remains required so
the denied URL is never sent to the write boundary.

Migration `20260731151344_add_species_country_occurrence_index.sql` adds:

- `species_country_occurrences`, a deny-by-default service-role table keyed by
  species UUID and uppercase ISO 3166-1 alpha-2 country code.
- `public.replace_species_country_occurrences(...)`, the validated atomic
  replacement boundary for one GBIF taxon. It takes the same transaction-scoped
  advisory lock as the dictionary identity-change trigger so concurrent taxon
  rematches cannot commit stale country rows.
- `public.get_species_dictionary_country_summaries(...)`, the exact-country
  aggregate used by the Dictionary overview.
- a trigger that purges country rows, invalidates their provenance, and queues
  an immediate durable refresh when a species' GBIF taxon key changes,
  preventing stale evidence from crossing taxon identities or remaining empty.
- the `country_occurrences` provenance key, insert-trigger gap detection, and a
  durable `gbif_wikipedia_reference` backfill for existing biological rows.

The table describes occurrence evidence ("recorded in"), not native range.

## Boundaries

The worker does not refresh model-heavy or review-heavy fields: `common_names`,
`habitat_description`, `lookalikes`, `group_tags`, `iucn_red_list_status`, and
`hazard_type` are skipped here. Habitat, lookalikes, and group tags are handled
by `/refresh-species-model-content`; common-name overrides, conservation, and
hazard data remain curation-owned.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/_shared/externalImagePolicy.ts services/supabase/functions/refresh-species-content/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/_shared/externalImagePolicy_test.ts services/supabase/functions/refresh-species-content/db.test.ts
deno test --allow-read=services/supabase/migrations --config services/supabase/functions/deno.json services/supabase/functions/_tests/speciesContentMigrationContract.test.ts
```

`supabase db lint --local --fail-on error` should also be run when a local
Supabase database is available so the migration helper and cron schedule are
validated against PostgreSQL.
