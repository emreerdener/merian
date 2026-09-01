# Species Observation Charts

Species Observation Charts are reusable iNaturalist-style charts shown on
species surfaces. They compare the user's private local Merian logs with a
cached global public iNaturalist baseline.

V1 appears in two places:

- Insight Sheet: after Habitat & Distribution in `BiologicalView`.
- Species Dictionary: after Habitat & Distribution in
  `SpeciesDictionaryPageContentView`.

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
- `apps/ios/Merian/Features/SpeciesReference/Models/SpeciesObservationLocalStats.swift`
- `apps/ios/Merian/Features/SpeciesReference/Models/SpeciesObservationChartPresentation.swift`
- `apps/ios/Merian/Features/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`
- `apps/ios/Merian/Features/SpeciesReference/Services/SpeciesObservationStatsDatabaseActor.swift`
- `apps/ios/Merian/Features/SpeciesReference/Services/SpeciesObservationStatsDependencies.swift`
- `apps/ios/Merian/Features/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift`
- `apps/ios/Merian/Features/SpeciesReference/Views/SpeciesObservationChartsCard.swift`
- `apps/ios/Merian/Features/SpeciesReference/Components/Charts/SpeciesObservationChartContent.swift`
- `apps/ios/Merian/Features/SpeciesReference/Components/Charts/SpeciesObservationSeasonalityHeatmapView.swift`
- `apps/ios/Merian/Features/Insights/Content/Views/BiologicalView.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Detail/Views/SpeciesDictionaryPageContentView.swift`

`SpeciesObservationStatsViewModel` is `@Observable @MainActor`. It receives a
small `SpeciesObservationStatsDependencies` value rather than resolving a live
client. `Services/` alone creates the `@ModelActor`
`SpeciesObservationStatsDatabaseActor` from `modelContext.container` and adapts
`MerianNetworkClient.getSpeciesObservationStats(...)`. The actor fetches narrow
local projections, then delegates normalization and bucket aggregation to the
platform-neutral `SpeciesObservationStatsReducer`.

Each load owns a generation token. A late local or public result cannot mutate
state after a newer species request starts, and an empty identity invalidates an
older in-flight request. A changed species identity clears the prior species'
published local and public values before awaiting replacement data; a
same-species refresh retains its current presentation. A task already cancelled
before a valid load begins does not claim generation ownership or disturb the
current presentation. Local and public failures remain independent: an
unavailable local projection may still show the public baseline, and a public
failure keeps usable local charts.

`SpeciesObservationChartsCard` owns selected-tab and task identity. The
render-only `SpeciesObservationChartContent` and seasonality heatmap component
render Swift Charts for:

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
- If a dictionary `speciesId` is available, match `confirmedSpeciesId` or
  `speciesId`.
- Also match by effective scientific name, where `userIdentificationOverride`
  wins over `scientificName`.
- Scientific names are trimmed, whitespace-collapsed, and compared
  case-insensitively.

Fetch rules:

- Species-id candidates and scientific-name candidates are fetched with separate
  `#Predicate` descriptors so SQLite narrows the row set before Swift reduction.
- Candidate rows are merged by `LocalScanRecord.id`, then sorted by
  `(timestamp, id)` for deterministic reducer input.
- `propertiesToFetch` is limited to the reducer projection: `id`, `speciesId`,
  `scientificName`, `userIdentificationOverride`, `confirmedSpeciesId`,
  `captureDate`, `timestamp`, `lifeStage`, and `isBiological`.
- Production chart loads use `SpeciesObservationStatsDatabaseActor`; pure
  reducer tests pass explicit record arrays and perform no imperative fetch.

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
- `services/supabase/functions/species-observation-stats/security.ts`
- `services/supabase/functions/species-observation-stats/db.test.ts`
- `services/supabase/migrations/20260517190000_add_species_observation_stats.sql`
- `services/supabase/migrations/20260724170709_harden_species_observation_stats.sql`

The iOS client uses an authenticated GET so normal app traffic receives both
user and IP budgets. The database-owned IP preflight occurs before optional
token verification, preventing invalid-token traffic from amplifying Auth calls.
The endpoint remains usable without a user session:

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

Both values are required. The database verifies that `species_id` names the
canonical normalized `scientific_name`; unknown/mismatched pairs never reach the
provider. Compatibility POST bodies are stream-bounded to 4 KiB before JSON
decoding. iOS also rejects a malformed UUID or a name outside 1...160 characters
before dispatch.

The Edge Function uses `species_dictionary.inaturalist_taxon_id` when known. A
database lease owner may resolve the exact canonical name when needed, but all
observation calls require the resulting `taxon_id`; there is no free-form name
fallback.

On cold cache misses, the response path fetches core totals, seasonality, and
history, returns those as `status: "partial"`, and queues life-stage/sex
annotation buckets through `runBackground`. Usable stale cache rows return
immediately as `status: "stale"` while one fenced database lease owner refreshes
in the background. A `partial` response always contains useful chart data; a
provider failure that leaves every bucket empty becomes `unavailable`.

## Response Contract

The response is wrapped in `schema_version` and `data`:

Current iOS chart rendering consumes `seasonality`, `history`, and `life_stage`.
The backend may still include `sex` for provider parity, but that series is
intentionally not rendered as a chart tab.

```json
{
  "schema_version": 2,
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

The Deno normalizer accepts multiple histogram shapes so provider response
format drift does not break clients unnecessarily.

## Cache And Pacing

Backend cache:

- Table: `species_observation_stats_cache`.
- Key: `species_id + source + scope`.
- Source: `inaturalist`.
- Scope: `global`.
- Fresh TTLs: seven days for `fresh`, 24 hours for `no_data`, one hour for
  `partial`, and five minutes for `unavailable`.
- Positive stale fallback: 30 additional days. Negative `no_data` stale
  fallback: seven days. `unavailable` is never served stale.
- If a refresh fails while positive data remains within 37 days of its original
  `fetched_at`, the database retains that payload, preserves its age, marks it
  `stale`, records the new row-level cache error, and applies a five-minute
  retry backoff. Cold/negative/too-old rows use the normal `unavailable` cache.

The backend sends a custom `User-Agent`, spaces live iNaturalist requests
conservatively, applies five-second fetch timeouts plus 15/45-second total
deadlines, and rejects provider bodies over 1 MiB while streaming. Successful
response caches vary only by `Accept-Encoding`; the public body does not vary by
user, so adding Authorization would fragment cache entries by token. Error
responses remain private/no-store.

Abuse and concurrency controls:

- all requests: 60/user/minute and 120/IP/minute;
- cold population: 12/user/minute, 30/IP/minute, and four globally/minute;
- raw IPs are replaced with daily, purpose-separated server HMACs;
- one 90-second database lease exists per species;
- cache finalization requires the current lease token, preventing late
  generations from overwriting newer data;
- exact taxon misses are cached for 24 hours and provider failures for five
  minutes.

iOS cache:

- `MerianNetworkClient` keeps a short in-memory cache.
- TTL: 5 minutes.
- Limit: 64 entries.
- Keys: normalized species UUID and normalized scientific name.
- Admission requires response `schema_version >= 2` plus returned UUID/name
  identity equal to the canonical request; legacy and mismatched responses fail
  closed.
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
deno fmt --check \
  services/supabase/functions/_shared/clientAddress.ts \
  services/supabase/functions/species-observation-stats \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/clientAddress.ts \
  services/supabase/functions/_shared/clientAddress_test.ts \
  services/supabase/functions/species-observation-stats \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/config.toml \
  services/supabase/functions/_shared/clientAddress_test.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/species-observation-stats/db.test.ts \
  services/supabase/functions/species-observation-stats/security.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
supabase --workdir services test db --local \
  services/supabase/tests/species_observation_stats_security.sql
```

iOS:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/merian-dd-species-observation-stats CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<BOOTED_SIMULATOR_ID>' -derivedDataPath /tmp/merian-dd-species-observation-stats CODE_SIGNING_ALLOWED=NO test \
  -only-testing:merianTests/SpeciesObservationStatsReducerTests \
  -only-testing:merianTests/SpeciesObservationStatsViewModelTests \
  -only-testing:merianTests/SpeciesReferenceArchitectureTests \
  -only-testing:merianTests/SpeciesDictionaryTests
```
