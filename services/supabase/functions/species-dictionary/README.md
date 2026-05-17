# Species Dictionary

Returns public species-level dictionary data for the standalone species
dictionary page. The endpoint is intentionally shared-safe for a future web
frontend and must not expose user-specific scan data.

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

Successful `200 OK` responses include public cache headers:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

`400`, `404`, and `500` responses do not include those cache headers. Missing
rows and transient failures must be able to recover as soon as the backing
dictionary data is created or repaired.

`content_quality` is additive and can be `complete`, `sparse`, or
`needs_enrichment`. It is derived from four public content signals: reference
imagery, a usable Wikipedia overview, habitat/distribution data, and meaningful
taxonomy. `complete` means all four are present, `sparse` means two or three are
present, and `needs_enrichment` means fewer than two are present.

`license` and `attribution` are preserved on normalized `reference_images` when
stored in `species_reference_images`. Future web species pages must run
`publicWebReferenceImageAttributionIssues(...)` from
`_shared/publicSpeciesProjection.ts` before rendering public reference media and
must not publish images with missing rights metadata unless they provide an
equivalent source-specific attribution path.

If no `species_dictionary` row exists for the scientific name, the function
returns:

```json
{ "error": "Species not found" }
```

with status `404`.

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
`services/supabase/functions/_shared/publicSpeciesProjection.ts`. Explore detail similar
species use matching SQL helpers so common-name fallback, reference-image
fallback, and private-field exclusions stay aligned across public species
surfaces.

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

Alternative common names and group tags are trimmed and deduped before
returning. Hydrated lookalikes include `species_id` for canonical dictionary
routing. Lookalike relation metadata is additive and optional; older clients can
ignore it. Public readers omit rows whose `review_status` is `rejected`.

Provenance and refresh metadata are stored separately in
`public.species_content_provenance`. The public response does not include those
fields in V1. The scheduled `refresh-species-content` worker consumes
`public.get_species_content_refresh_queue(...)` hourly and refreshes only
GBIF/Wikipedia-backed fields in V1: alternate common names, taxonomy, Wikipedia
URL/overview, GBIF taxon key, and reference images. Model-heavy or review-heavy
keys remain skipped until curation/model refresh tooling exists.
Merian source scan/post/user provenance is stored privately in
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

The function does not call `withEdgeHandler` or `requireAuth` because the
endpoint is intentionally public. It uses the service role key internally only
to read the safe projected fields listed above.

## Local Verification

```sh
deno check services/supabase/functions/_shared/http.ts services/supabase/functions/_shared/publicSpeciesProjection.ts services/supabase/functions/_shared/speciesContentProvenance.ts services/supabase/functions/_shared/identify/db.ts services/supabase/functions/refresh-species-content/index.ts services/supabase/functions/refresh-species-content/db.ts services/supabase/functions/species-dictionary/index.ts services/supabase/functions/species-dictionary/db.ts services/supabase/functions/species-dictionary/db.test.ts
deno test services/supabase/functions/_shared/http_test.ts services/supabase/functions/_shared/publicSpeciesProjection_test.ts services/supabase/functions/_shared/speciesContentProvenance_test.ts services/supabase/functions/_shared/identify/db_test.ts services/supabase/functions/refresh-species-content/db.test.ts services/supabase/functions/species-dictionary/db.test.ts
```
