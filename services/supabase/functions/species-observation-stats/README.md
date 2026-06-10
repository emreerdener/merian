# Species Observation Stats

Returns public, global iNaturalist observation aggregates for a species. The
endpoint backs iNaturalist-style observation charts in the Insight Sheet and
Species Dictionary page. It is intentionally public and must never receive or
persist a user's local Merian scan history.

## Request

Preferred client transport is `GET` with query parameters:

```text
/functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

`POST` with a JSON body remains supported for compatibility:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation:

- `scientific_name` is required.
- `scientific_name` must be a non-empty string after trimming and whitespace
  collapse.
- `species_id`, when present, must be a valid UUID. Empty strings are ignored.
- Names over 160 characters are rejected.

Invalid bodies return `400`.

## Response

```json
{
  "schema_version": 1,
  "data": {
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "scientific_name": "Danaus plexippus",
    "source": {
      "provider": "inaturalist",
      "scope": "global",
      "inaturalist_taxon_id": 48662,
      "fetched_at": "2026-05-17T12:00:00.000Z"
    },
    "status": "fresh",
    "total_observations": 450448,
    "last_observation_date": "2026-05-17",
    "fetched_at": "2026-05-17T12:00:00.000Z",
    "provider_errors": [],
    "seasonality": [{ "month": 5, "count": 1200 }],
    "history": [{ "year": 2026, "month": 5, "count": 1200 }],
    "life_stage": [
      {
        "key": "adult",
        "label": "Adult",
        "values": [{ "month": 8, "count": 100 }]
      }
    ],
    "sex": [
      {
        "key": "female",
        "label": "Female",
        "values": [{ "month": 8, "count": 12 }]
      }
    ]
  }
}
```

`schema_version = 1` is the current observation-stats contract. New response
keys must be additive, nullable values may remain `null`, and clients must
ignore unknown keys.

## Status Values

- `fresh`: provider fetch completed and data was found.
- `no_data`: provider fetch completed but returned no observations.
- `partial`: at least one provider bucket failed, but enough data was fetched to
  show a useful result. Cold cache misses may also return core totals,
  seasonality, and history with `partial` while annotation buckets refresh in
  the background.
- `stale`: a usable stale cache payload was returned while refresh work is
  deferred off the response path.
- `unavailable`: provider refresh failed and no usable cache existed.

## Data Sources

Primary species row:

- `public.species_dictionary`

Cache row:

- `public.species_observation_stats_cache`

External provider:

- iNaturalist public API, global scope.

Lookup order:

1. Use `species_dictionary.inaturalist_taxon_id` when stored.
2. Otherwise resolve an exact `scientific_name` match through
   `GET /v1/taxa?q=...&per_page=10`.
3. If no exact taxon ID is found, fall back to iNaturalist `taxon_name`.

## iNaturalist Buckets

The function requests:

- `/v1/observations` for total observations and most recent observation date.
- `/v1/observations/histogram?interval=month_of_year` for seasonality.
- `/v1/observations/histogram?interval=month` for rolling seven-year history.
- Annotation-filtered month-of-year histograms for life stage and sex.

Annotation mappings used by V1:

| Group      | `term_id` | Value            | `term_value_id` |
| ---------- | --------: | ---------------- | --------------: |
| Life Stage |         1 | Adult            |               2 |
| Life Stage |         1 | Teneral          |               3 |
| Life Stage |         1 | Pupa             |               4 |
| Life Stage |         1 | Nymph            |               5 |
| Life Stage |         1 | Larva            |               6 |
| Life Stage |         1 | Egg              |               7 |
| Life Stage |         1 | Juvenile         |               8 |
| Life Stage |         1 | Subimago         |              16 |
| Sex        |         9 | Female           |              10 |
| Sex        |         9 | Male             |              11 |
| Sex        |         9 | Cannot determine |              20 |

Histogram normalization is intentionally tolerant of multiple iNaturalist JSON
shapes: direct bucket maps, `results` maps, and object buckets containing
`count`, `total`, `value`, or `observation_count`.

## Cache Behavior

Successful public stats are cached in `species_observation_stats_cache` keyed by
`species_id + source + scope`.

- Fresh TTL: 7 days.
- Stale fallback window: 30 additional days.
- Cache scope is currently always `global`.
- Source is currently always `inaturalist`.
- A resolved iNaturalist taxon ID is written back to
  `species_dictionary.inaturalist_taxon_id` for future stable lookup.
- Cold cache misses fetch core stats synchronously, then use `runBackground` to
  populate life-stage and sex annotation buckets in
  `species_observation_stats_cache`.
- Usable stale cache rows are returned immediately and refreshed in the
  background. Duplicate in-flight refreshes for the same species are suppressed
  per isolate.

Fresh and `no_data` `200 OK` responses send:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

Refreshing responses (`partial`, `stale`, and `unavailable`) use a shorter
public cache window so a CDN does not pin incomplete data:

```http
Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=300
Vary: Accept-Encoding
```

## Privacy Contract

This endpoint is public species-level data only. Do not add:

- local scan IDs
- user IDs
- Explore post IDs
- field notes
- locations
- local media
- preferred-name overrides
- raw local Merian observation counts

Local Merian observations are aggregated on-device by
`SpeciesObservationStatsViewModel` and are never sent to Supabase.

## Auth

`services/supabase/config.toml` sets:

```toml
[functions.species-observation-stats]
verify_jwt = false
```

The function does not call `withEdgeHandler` or `requireAuth` because the
response is public species-level data. It uses the service role key internally
for dictionary/cache reads and writes.

## Local Verification

```sh
deno fmt --check services/supabase/functions/species-observation-stats
deno lint services/supabase/functions/species-observation-stats
deno test services/supabase/functions/species-observation-stats/db.test.ts
```
