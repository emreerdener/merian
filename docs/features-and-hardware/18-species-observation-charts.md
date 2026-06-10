# Species Observation Charts

Species Observation Charts are reusable iNaturalist-style charts shown on
species surfaces. They compare the user's private local Merian logs with a
cached global public iNaturalist baseline.

V1 appears in two places:

- Insight Sheet: after Habitat & Distribution in `BiologicalView`.
- Species Dictionary: after Habitat & Distribution in
  `SpeciesDictionaryPageView`.

## Product Scope

Included in V1:

- Seasonality by month.
- Rolling seven-year monthly history.
- Life Stage by month.
- Local Merian aggregation for Seasonality, History, and Life Stage.
- Public global iNaturalist aggregation for those three tabs.
- Normalized compare view so small personal logs remain visible beside large
  public counts.
- Raw peak counts in footer/accessibility copy.
- Partial, stale, local-only, and empty states.

Excluded in V1:

- Sending local observations to Supabase.
- Rendering sex as a species-level chart; scan sex appears in `OverviewCard`
  with its supporting cue/confidence when available.
- GBIF fallback for chart buckets.
- User/location-scoped public stats.
- Persistent on-device storage for fetched public chart payloads.

## iOS Architecture

Primary files:

- `apps/ios/Merian/Core/Network/SpeciesObservationStatsAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Insights/Models/SpeciesObservationStatsReducer.swift`
- `apps/ios/Merian/Features/Insights/ViewModels/SpeciesObservationStatsViewModel.swift`
- `apps/ios/Merian/Features/Insights/Components/Cards/SpeciesObservationChartsCard.swift`
- `apps/ios/Merian/Features/Insights/Views/Content/BiologicalView.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Views/SpeciesDictionaryPageView.swift`

`SpeciesObservationStatsViewModel` is `@Observable @MainActor`, but local
SwiftData fetching is delegated to `@ModelActor`
`SpeciesObservationStatsDatabaseActor`. The actor fetches narrow local
projections, then delegates normalization and bucket aggregation to
`SpeciesObservationStatsReducer`. The view model creates the actor from
`modelContext.container`, awaits the local result, then requests the public
baseline through `MerianNetworkClient.shared.getSpeciesObservationStats(...)`.
If the network request fails, the card still renders the local data.

`SpeciesObservationChartsCard` owns the selected tab and renders Swift Charts
for:

- `Seasonality`
- `History`
- `Life Stage`

The plotted y-values are normalized independently per series. This means a
single local observation in May can still be visible beside tens of thousands of
public observations in August. Raw counts are kept in labels and accessibility
text rather than used for the primary y-axis.

## Local Aggregation

Local data comes from `LocalScanRecord` only. It is never uploaded.

Matching rules:

- Records must be biological.
- If a dictionary `speciesId` is available, match
  `confirmedSpeciesId` or `speciesId`.
- Also match by effective scientific name, where
  `userIdentificationOverride` wins over `scientificName`.
- Scientific names are trimmed, whitespace-collapsed, and compared
  case-insensitively.

Fetch rules:

- Species-id candidates and scientific-name candidates are fetched with
  separate `#Predicate` descriptors so SQLite narrows the row set before Swift
  reduction.
- Candidate rows are merged by `LocalScanRecord.id`, then sorted by
  `(timestamp, id)` for deterministic reducer input.
- `propertiesToFetch` is limited to the reducer projection:
  `id`, `speciesId`, `scientificName`, `userIdentificationOverride`,
  `confirmedSpeciesId`, `captureDate`, `timestamp`, `lifeStage`, and
  `isBiological`.
- The legacy full-fetch reducer remains only as a compatibility helper for
  isolated tests; production chart loads must use
  `SpeciesObservationStatsDatabaseActor`.

Date rules:

- Use `captureDate ?? timestamp`.
- Seasonality counts records by month, across all years.
- History counts records by month from January of the current year minus six
  through the current month.
- Life Stage counts records by month after excluding empty, `unknown`,
  `not_applicable`, `not applicable`, `n/a`, and `none`.

## Public Backend Architecture

Primary files:

- `services/supabase/functions/species-observation-stats/index.ts`
- `services/supabase/functions/species-observation-stats/db.ts`
- `services/supabase/functions/species-observation-stats/db.test.ts`
- `services/supabase/migrations/20260517190000_add_species_observation_stats.sql`

The iOS client uses an unauthenticated public GET:

```text
/functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

The Edge Function still accepts POST JSON for compatibility:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

`scientific_name` is required. `species_id` is optional but preferred when it is
a dictionary UUID.

The Edge Function reads `species_dictionary`, uses
`species_dictionary.inaturalist_taxon_id` when known, resolves exact scientific
names through iNaturalist when needed, then caches the resulting public payload
in `species_observation_stats_cache`.

On cold cache misses, the response path fetches core totals, seasonality, and
history, returns those as `status: "partial"`, and queues life-stage/sex
annotation buckets through `runBackground`. Usable stale cache rows return
immediately as `status: "stale"` while a full refresh runs in the background.

## Response Contract

The response is wrapped in `schema_version` and `data`:

Current iOS chart rendering consumes `seasonality`, `history`, and
`life_stage`. The backend may still include `sex` for provider parity, but that
series is intentionally not rendered as a chart tab.

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

Status values:

- `fresh`: public provider fetch succeeded and data exists.
- `no_data`: provider fetch succeeded but no observation buckets were found.
- `partial`: some provider buckets failed, or cold-load annotation buckets are
  still refreshing, but useful data is available.
- `stale`: a stale cache payload was returned while refresh work is deferred.
- `unavailable`: refresh failed and no usable cache payload existed.

## iNaturalist Mapping

The public provider scope is global. The backend uses public endpoints only:

- `GET /v1/taxa`
- `GET /v1/observations`
- `GET /v1/observations/histogram`

Annotation IDs:

| Group | `term_id` | Value | `term_value_id` |
| --- | ---: | --- | ---: |
| Life Stage | 1 | Adult | 2 |
| Life Stage | 1 | Teneral | 3 |
| Life Stage | 1 | Pupa | 4 |
| Life Stage | 1 | Nymph | 5 |
| Life Stage | 1 | Larva | 6 |
| Life Stage | 1 | Egg | 7 |
| Life Stage | 1 | Juvenile | 8 |
| Life Stage | 1 | Subimago | 16 |
| Sex | 9 | Female | 10 |
| Sex | 9 | Male | 11 |
| Sex | 9 | Cannot determine | 20 |

The Deno normalizer accepts multiple histogram shapes so provider response
format drift does not break clients unnecessarily.

## Cache And Pacing

Backend cache:

- Table: `species_observation_stats_cache`.
- Key: `species_id + source + scope`.
- Source: `inaturalist`.
- Scope: `global`.
- Fresh TTL: 7 days.
- Stale fallback window: 30 additional days.

The backend sends a custom `User-Agent`, spaces live iNaturalist requests
conservatively, and uses stale cache fallback for provider outages.

iOS cache:

- `MerianNetworkClient` keeps a short in-memory cache.
- TTL: 5 minutes.
- Limit: 64 entries.
- Keys: normalized species UUID and normalized scientific name.
- Cache clears in DEBUG when tests inject a mock `URLSession`.

## Privacy Contract

Local observation data stays on-device:

- Local scan dates are not sent to Supabase.
- Local life-stage counts are not sent to Supabase.
- Local species-match results are not sent to Supabase.
- Per-scan sex metadata follows the normal scan persistence path and is not sent
  through the observation-stats request.

The public endpoint may return only global species-level data from iNaturalist
and cache metadata. It must not include user IDs, scan IDs, Explore post IDs,
field notes, comments, locations, local media, or preferred-name overrides.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/species-observation-stats
deno lint services/supabase/functions/species-observation-stats
deno test services/supabase/functions/species-observation-stats/db.test.ts
```

iOS:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/merian-dd-species-observation-stats CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' -derivedDataPath /tmp/merian-dd-species-observation-stats CODE_SIGNING_ALLOWED=NO test -only-testing:merianTests/SpeciesObservationStatsViewModelTests -only-testing:merianTests/SpeciesDictionaryTests
```
