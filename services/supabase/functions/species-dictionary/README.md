# Species Dictionary

Returns public species-level dictionary data for the standalone iOS and public
web species pages. The endpoint is intentionally shared-safe and must not expose
user-specific scan data.

## Request

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation:

- Either `species_id` or `scientific_name` is required.
- `species_id`, when present, must be a valid UUID and is preferred for lookup.
- `scientific_name`, when present, must be a non-empty string after trimming.
- Internal whitespace is collapsed.
- Names over 160 characters are rejected.

Invalid bodies return `400`.

Tree requests use one of two explicit scopes:

```json
{ "mode": "tree", "scope": "all_species" }
```

```json
{ "mode": "tree", "scope": "my_scans" }
```

Omitting `scope` keeps the legacy authenticated scanned-species tree behavior.

## Response

```json
{
  "schema_version": 1,
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
    "content_quality": "complete",
    "alternative_common_names": [],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    },
    "hazard_type": "none",
    "iucn_red_list_status": "least concern",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly...",
    "habitat_description": "Often found in open meadows and milkweed patches.",
    "gbif_taxon_key": 5139790,
    "group_tags": ["animal", "insect"],
    "reference_images": [
      {
        "url": "https://upload.wikimedia.org/...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Example Photographer",
        "width": 1200,
        "height": 800
      },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://...",
        "iucn_red_list_status": "least concern",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      }
    ]
  }
}
```

`schema_version = 1` is the current public species contract. New keys may be
added inside this version, nullable fields may remain `null`, and clients must
ignore unknown keys. Breaking changes require a new versioned contract rather
than silently changing this shape.

Successful detail and catalog `200 OK` responses include public cache headers:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

Overview mode returns the featured species card plus category, high-level group,
and region summaries. It uses `Cache-Control: no-store` so randomized category
thumbnails and featured species choices can refresh on each request. Overview,
catalog, and the `all_species` tree scope only publish rows that look like
biological taxa: a row must have a scientific name plus either a positive GBIF
taxon key or usable taxonomy with a kingdom and at least one downstream rank.
This prevents generic encyclopedia concepts from appearing as Species Dictionary
records. The `my_scans` tree scope applies the same public species projection
after selecting the current user's scanned species.

`400`, `404`, and `500` responses do not include those cache headers. Missing
rows and transient failures must be able to recover as soon as the backing
dictionary data is created or repaired.

`content_quality` is additive and can be `complete`, `sparse`, or
`needs_enrichment`. It is derived from four public content signals: reference
imagery, a usable Wikipedia overview, habitat/distribution data, and meaningful
taxonomy. `complete` means all four are present, `sparse` means two or three are
present, and `needs_enrichment` means fewer than two are present.

`license` and `attribution` are preserved on normalized `reference_images` when
stored in `species_reference_images`. The web species mapper runs
`publicWebReferenceImageAttributionIssues(...)` from
`_shared/publicSpeciesProjection.ts` before rendering public reference media or
using it in metadata and omits images with missing rights metadata.

If no `species_dictionary` row exists for the scientific name, the function
returns:

```json
{ "error": "Species not found" }
```

with status `404`.

## Public Web Consumer

`apps/web/lib/species.ts` is the server-only consumer for
`/species/[speciesId]/[slug]` and its UUID-only compatibility route. It
validates the route UUID before invoking this function with `species_id`,
requires `schema_version = 1`, verifies the returned identity, and maps only the
documented public fields. The slug is derived from returned names and is never
part of this function's request or identity contract. It must not replace the
Edge call with direct service-role table reads.

Invalid UUIDs and this function's marked handler-owned `404` response become
non-indexable Next.js not-found pages. An unmarked platform `404`, configuration
failure, network failure, other non-success response, malformed payload,
unsupported schema version, or identity mismatch remains a server error so
transient failures are not cached as missing species. Successful UUID-only or
stale-slug requests permanently redirect to the current canonical UUID-plus-slug
path. Successful web pages revalidate every five minutes.

The web mapper audits every candidate reference image with
`publicWebReferenceImageAttributionIssues(...)` before page or metadata use and
omits rows missing `license` or `attribution`. It renders lookalikes as text
links only because `similar_species.reference_image_url` does not currently
carry those rights fields.

## Data Sources

Primary row:

- `public.species_dictionary`

Reference images:

- `public.species_reference_images`
- fallback to legacy `species_dictionary.reference_image_url`

Lookalike rows:

- `public.species_lookalikes`
- hydrated through `species_dictionary!lookalike_id`

The FK hint is required because `species_lookalikes` has both `species_id` and
`lookalike_id` foreign keys pointing at `species_dictionary`.

## Mapping Rules

The Deno mapping lives in
`services/supabase/functions/_shared/publicSpeciesProjection.ts`. Explore detail
similar species use matching SQL helpers so common-name fallback,
reference-image fallback, and private-field exclusions stay aligned across
public species surfaces.

Common name fallback:

1. `common_names.en`
2. first non-empty value from `common_names`
3. `scientific_name`

Reference images:

- Prefer ordered rows from `species_reference_images`.
- Include optional `license`, `attribution`, `width`, and `height` when present.
- Normalized rows are ordered `merian`, then `wikipedia`, then `gbif`.
- Merian rows come from high-quality published Explore media promoted by
  `/refresh-merian-reference-images`.
- If no normalized rows exist, split comma-separated
  `species_dictionary.reference_image_url`.
- Trim and dedupe URLs.
- Map each URL to `{ url, source }` plus any available provenance metadata.
- Wikimedia/Wikipedia hosts map to `wikipedia`.
- Merian media hosts map to `merian`.
- If `wikipedia_url` exists, the first unresolved image is treated as
  `wikipedia`.
- Remaining unresolved images map to `gbif`.
- Before source mapping or first-image selection, normalized rows and legacy
  values pass through `_shared/externalImagePolicy.ts`. The current exact rule
  suppresses every URL below
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` and promotes the
  next permitted ordered image. The species row and lookalike navigation remain
  present; an empty permitted set produces the existing no-image state.

Alternative common names and group tags are trimmed and deduped before
returning. Hydrated lookalikes include `species_id` for canonical dictionary
routing. Lookalike relation metadata is additive and optional; older clients can
ignore it. Public readers omit rows whose `review_status` is `rejected`.

Provenance and refresh metadata are stored separately in
`public.species_content_provenance`. The public response does not include those
fields in V1. The scheduled `refresh-species-content` worker claims
`gbif_wikipedia_reference` jobs from `species_enrichment_jobs` first, falls back
to `public.get_species_content_refresh_queue(...)` for older provenance-driven
refreshes, and refreshes GBIF/Wikipedia-backed fields: alternate common names,
taxonomy, Wikipedia URL/overview, GBIF taxon key, and reference images.
`refresh-species-model-content` claims `habitat`, `lookalikes`, and `group_tags`
jobs from the same queue. New dictionary rows and existing sparse rows enter
that queue through
`20260707153931_species_dictionary_enrichment_queue_backfill.sql`. Common-name
overrides, conservation, and hazard data remain curation-owned. Merian source
scan/post/user provenance is stored privately in
`public.species_reference_image_merian_sources`; the public dictionary response
exposes only URL, source, license, attribution, and optional image dimensions.
Merian images qualify only when the source scan is publicly visible, has a high
image-quality score, and either carries high AI species confidence or a resolved
confirmed species.

## Privacy Contract

The response is public species dictionary data only. Do not add:

- scan IDs
- user IDs
- Explore post IDs
- field notes
- comments
- local user media
- locations
- per-scan AI reasoning
- preferred-name overrides

## Auth

`services/supabase/config.toml` sets:

```toml
[functions.species-dictionary]
verify_jwt = false
```

The function does not call `withEdgeHandler` because most dictionary views are
public. Catalog, overview, and the `all_species` tree scope are public. The
`my_scans` tree scope calls `requireAuth` and uses the current user only to
select that user's scanned species before applying the same safe public
projection fields listed above.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/_shared/http.ts services/supabase/functions/_shared/externalImagePolicy.ts services/supabase/functions/_shared/publicSpeciesProjection.ts services/supabase/functions/_shared/speciesContentProvenance.ts services/supabase/functions/_shared/identify/db.ts services/supabase/functions/refresh-species-content/index.ts services/supabase/functions/refresh-species-content/db.ts services/supabase/functions/refresh-species-model-content/index.ts services/supabase/functions/refresh-species-model-content/db.ts services/supabase/functions/species-dictionary/index.ts services/supabase/functions/species-dictionary/db.ts services/supabase/functions/species-dictionary/db.test.ts
deno test --allow-net --config services/supabase/functions/deno.json services/supabase/functions/_shared/http_test.ts services/supabase/functions/_shared/externalImagePolicy_test.ts services/supabase/functions/_shared/external_test.ts services/supabase/functions/_shared/publicSpeciesProjection_test.ts services/supabase/functions/_shared/speciesContentProvenance_test.ts services/supabase/functions/_shared/identify/db_test.ts services/supabase/functions/refresh-species-content/db.test.ts services/supabase/functions/refresh-species-model-content/db.test.ts services/supabase/functions/species-dictionary/db.test.ts
deno test --allow-read=services/supabase/migrations --config services/supabase/functions/deno.json services/supabase/functions/_tests/speciesContentMigrationContract.test.ts
```

## Related Endpoint

Species dictionary pages also render observation pattern charts from
`/species-observation-stats`. That endpoint is separate from this dictionary
projection because it reads/caches public iNaturalist aggregates and owns
canonical UUID/name binding, user/IP/global budgets, negative caching, provider
deadlines, fenced cold-population leases, and stale-if-error retention. The iOS
consumer validates schema version 2 and the returned UUID/name pair before
memoizing stats. Local Merian observation logs are still aggregated on-device
and are never sent to Supabase. See
`services/supabase/functions/species-observation-stats/README.md` for the stats
contract.
