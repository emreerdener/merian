# Species Dictionary Page

The Species Dictionary Page is the standalone in-app public page for a
discovered species. It presents canonical species-level dictionary data and
reference imagery without loading a user scan, Explore post, field notes, or
comments. The only personalized V1 element is the on-device local-observation
overlay inside `SpeciesObservationChartsCard`; those local counts are never sent
to Supabase.

This creates three separate species surfaces in the iOS app:

| Surface                 | Scope                         | Primary data source                                                               |
| ----------------------- | ----------------------------- | --------------------------------------------------------------------------------- |
| Insight scan            | A user's specific scan result | `InferenceEngine.shared.speciesData`, local scan media, and per-scan AI reasoning |
| Explore post            | A public shared scan          | Explore post/detail endpoints plus the backing public scan projection             |
| Species dictionary page | General species reference     | `species_dictionary`, `species_lookalikes`, public reference imagery, local on-device observation aggregates, and cached global public iNaturalist stats |

## Product Scope

V1 entry is intentionally narrow: a user taps a similar-species card in either
the Insight sheet or an Explore post detail page, and Merian pushes the public
species dictionary page inside that sheet's existing navigation stack. The
standalone dictionary presenter still uses a large-detent sheet when opened
directly.

Included in V1:

- canonical scientific and common names
- alternate common names, rendered as a compact line under the primary common
  name
- reference image gallery from normalized public reference imagery
- Wikipedia overview
- habitat description and GBIF heatmap when `gbif_taxon_key` is available
- observation pattern charts from local on-device logs plus cached global public
  iNaturalist stats
- taxonomy
- IUCN Red List status
- hazard status
- similar species that route to another dictionary page in the same stack

Excluded in V1:

- Explore posts as dictionary-page content
- local scan lists, scan media, or per-scan detail pages
- user-uploaded gallery media
- field notes
- comments
- locations
- preferred-name editing
- user-specific review state

## iOS Architecture

Primary files:

- `services/supabase/functions/_shared/publicSpeciesProjection.ts`
- `apps/ios/Merian/Core/Network/SpeciesDictionaryAPIModels.swift`
- `apps/ios/Merian/Core/Network/SpeciesObservationStatsAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Insights/Components/Cards/SpeciesObservationChartsCard.swift`
- `apps/ios/Merian/Features/Insights/ViewModels/SpeciesObservationStatsViewModel.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/ViewModels/SpeciesDictionaryPageViewModel.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Views/SpeciesDictionaryPageView.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Components/SpeciesDictionaryReferenceGallery.swift`
- `apps/ios/Merian/Features/SpeciesDictionary/Components/SpeciesDictionaryCards.swift`
- `apps/ios/Merian/Features/Insights/Components/Cards/SimilarSpeciesGallery.swift`
- `apps/ios/Merian/Features/Insights/Views/Content/BiologicalView.swift`
- `apps/ios/Merian/Features/Explore/Views/ExplorePostDetailView.swift`

`SpeciesDictionaryPageView` is the standalone sheet shell. It owns a
`NavigationStack`, presents at `.large`, hides the sheet grabber, and renders
the root `SpeciesDictionaryPageContentView` with an `xmark` close button.
Pushed dictionary pages render the same content view with native back
navigation instead of a close button. When dictionary content is pushed from
Insight or Explore, those sheet roots own the navigation stack and register
`SpeciesDictionaryRoute`; the dictionary content does not create a nested sheet.
It does not mount `InferenceEngine`, does not read SwiftData scan records, and
does not reuse `InsightSheetViewModel`.

`SpeciesDictionaryPageViewModel` is an `@Observable @MainActor` model with four
user-visible states:

- `loading`
- `loaded(SpeciesDictionaryEntry)`
- `notFound`
- `error(String)`

The model trims the incoming scientific name before fetching and prefers a
`speciesId` lookup when the route provides one. A `404` from the backend maps to
`notFound`; other failures map to `error`.

`SpeciesObservationChartsCard` is embedded in the loaded dictionary content
after Habitat & Distribution. It owns its own
`SpeciesObservationStatsViewModel`, fetches local scan projections through
`SpeciesObservationStatsDatabaseActor`, aggregates them on-device through
`SpeciesObservationStatsReducer`, and fetches the public baseline from
`/species-observation-stats`. The dictionary page passes `species.id` and
`species.scientificName`, so the stats endpoint can use the dictionary UUID and
resolve/store `inaturalist_taxon_id`.

## Entry Point

`SimilarSpeciesGallery` can either emit `NavigationLink(value:)` routes through
`routeForSpecies` or call an optional legacy `onSpeciesSelected` callback. The
Insight sheet biological result passes a route builder from `BiologicalView`:

```swift
SimilarSpeciesGallery(
    similarData: similarData,
    currentScientificName: inferenceEngine.speciesData?.scientificName,
    currentCommonName: inferenceEngine.speciesData?.commonName,
    routeForSpecies: insightSimilarSpeciesRoute
)
```

The sheet root owns the route destination, so the user sees a single navigation
stack: Insight or Explore detail -> Species Dictionary -> another dictionary
page if they tap a similar species again. `speciesId` is preferred for lookup
when present; `scientificName` remains the display and backward-compatible
lookup fallback.

Explore post detail uses the same route from its public
`/get-explore-post-detail` similar-species payload. The Explore entry point is
detail-only; feed cards, map previews, author profile previews, scan library,
search, and external deep links do not open the species dictionary in V1.

## Title And Alternate Names

The header renders the scientific name, then the primary common name, then
`AlternativeCommonNamesLine` when alternate names are available. The line uses
the compact copy `Also known as: Name, Name` and wraps naturally for long lists.
It trims names, splits comma-delimited source values, deduplicates
case-insensitively, treats whitespace/underscore/dash variants as the same
name, and excludes the primary common name. For example, `Desert Rose` and
`Desert-rose` share the same display key, so the alternate line is suppressed
instead of repeating the title with punctuation changed.

Alternate names are intentionally not repeated in a lower card. The old
dictionary-only "Also known as" grid was removed so the information lives in the
same place on both Species Dictionary and Explore detail pages. The toolbar
badge uses only the primary common name.

## Backend Contract

The iOS client calls:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

That method POSTs to the `species-dictionary` Edge Function:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Successful responses are wrapped in a `data` envelope:

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
        "iucn_red_list_status": "least concern"
      }
    ]
  }
}
```

The default detail lookup is public by design and has `verify_jwt = false`. It
may receive normal app auth headers from `MerianNetworkClient`, but the detail
and catalog paths do not require or read identity. Those responses must remain
species-level public dictionary data only.

`schema_version = 1` is the shared public species contract used by the
dictionary page and Explore detail similar-species projection. iOS treats the
key as optional for backward compatibility with older mocks or deployed
functions, and future web clients should use it before depending on new fields.

### Overview and Catalog Modes

The same `/species-dictionary` function also supports the Explore Dictionary
landing view through overview mode:

```json
{
  "mode": "overview",
  "user_region": "US",
  "cache_buster": "550e8400-e29b-41d4-a716-446655440000"
}
```

The response returns image-backed category summaries for `All`, `Your Region`,
`Taxonomy`, and `Recently Added`, a Recently Added featured species card with
overview copy, graphic-led high-level group summaries such as Birds and Plants,
plus region summaries derived from `species_dictionary.native_region`.
`Recently Added` is capped to the newest 40 biological entries for its overview
count and representative image so it does not duplicate the `All` total. iOS
uses that featured card as the visible Recently Added entry point, renders
`Your Region` as a full-width MapKit snapshot card when a matched native-region
catalog exists, and moves `All` into a bottom row link. Explore keeps Dictionary
as the only bottom-navigation entry for species reference surfaces; the root
Dictionary tab exposes a header segmented control that switches between the
Catalog overview/search content and the Tree canvas. The region snapshot uses
the backend-matched native region and falls back to a default United States map
only when MapKit geocoding cannot resolve that region label. If the overview has
no non-empty region summaries with species counts, iOS hides the Region section
and the "Browse all regions" row instead of showing an empty regional path.
Catalog detail pages opened from overview cards or rows, including Birds,
Mammals, All, Your Region, and Recently Added, keep the same paginated species
row list but add toolbar search, matching the Scans library search presentation,
that filters within the active category.
Overview, catalog, and tree results are gated to public biological taxa: a row
must have a scientific name plus either a positive GBIF taxon key or usable
biological taxonomy with a kingdom and at least one downstream rank. Rows that
only resolve to generic encyclopedia concepts are filtered out before they can
appear as dictionary records.
`user_region` may be an ISO region code from an already-authorized physical
location or, when location is unavailable/not granted, from
`Locale.current.region?.identifier`; the function expands codes such as `US`
for native-region matching. iOS includes `cache_buster` so overview requests
bypass old cached response bodies while category thumbnails are randomized.

```json
{
  "schema_version": 1,
  "data": {
    "featured_species": {
      "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      "scientific_name": "Danaus plexippus",
      "common_name": "Monarch Butterfly",
      "overview": "The monarch butterfly is a milkweed butterfly known for long-distance migration.",
      "reference_image_url": "https://..."
    },
    "categories": [
      {
        "id": "your_region",
        "title": "Your Region",
        "subtitle": "Species associated with United States",
        "count": 8,
        "reference_image_url": "https://...",
        "region": "United States"
      }
    ],
    "groups": [
      {
        "id": "birds",
        "title": "Birds",
        "count": 12,
        "reference_image_url": "https://..."
      }
    ],
    "regions": [
      {
        "id": "region:united%20states",
        "title": "United States",
        "count": 8,
        "reference_image_url": "https://..."
      }
    ]
  }
}
```

Catalog mode powers search results and category detail pages:

```json
{
  "mode": "catalog",
  "category": "region",
  "region": "United States",
  "query": "Danaus",
  "limit": 40,
  "cursor": {
    "scientific_name": "Danaus plexippus",
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "created_at": "2026-06-01T12:00:00Z"
  }
}
```

`category` defaults to `all` for backward compatibility. `region` is required
when `category` is `region` and may also be an ISO region code. `group` is
required when `category` is `group`; supported high-level groups are `plants`,
`birds`, `insects`, `fungi`, `mammals`, and `reptiles_amphibians`.
`recently_added` sorts by
`species_dictionary.created_at DESC, id DESC`; other catalog views sort by
`scientific_name ASC, id ASC`. The response keeps the shared schema version and
returns a cursor-paginated list:

```json
{
  "schema_version": 1,
  "data": [
    {
      "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      "scientific_name": "Danaus plexippus",
      "common_name": "Monarch Butterfly",
      "content_quality": "complete",
      "taxonomy": {
        "kingdom": "Animalia",
        "phylum": "Arthropoda",
        "class": "Insecta",
        "order": "Lepidoptera",
        "family": "Nymphalidae",
        "genus": "Danaus"
      },
      "iucn_red_list_status": "least concern",
      "hazard_type": "none",
      "group_tags": ["animal", "insect"],
      "reference_image_url": "https://..."
    }
  ],
  "next_cursor": null
}
```

Catalog rows are intentionally compact. They include enough species-level public
data for list cards, then route into `SpeciesDictionaryPageContentView` for full
reference imagery, overview, habitat, observation charts, and similar-species
content.

### Tree Mode

The Tree of Life canvas is available from the Explore Dictionary header segment
instead of as a separate Explore bottom-navigation tab. It uses the same Edge
Function with `mode: "tree"`:

```json
{
  "mode": "tree"
}
```

The response keeps the shared schema version and returns a graph payload:

```json
{
  "schema_version": 1,
  "data": {
    "nodes": [
      {
        "id": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus",
        "rank": "genus",
        "title": "Danaus",
        "subtitle": "Genus",
        "parent_id": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
        "species_count": 2,
        "child_count": 2,
        "lineage": {
          "kingdom": "Animalia",
          "phylum": "Arthropoda",
          "class": "Insecta",
          "order": "Lepidoptera",
          "family": "Nymphalidae",
          "genus": "Danaus"
        },
        "representative_species": {
          "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
          "scientific_name": "Danaus plexippus",
          "common_name": "Monarch Butterfly",
          "content_quality": "complete",
          "taxonomy": { "kingdom": "Animalia" },
          "iucn_red_list_status": "least concern",
          "hazard_type": "none",
          "group_tags": ["animal", "insect"],
          "reference_image_url": "https://..."
        },
        "species": null
      }
    ],
    "edges": [
      {
        "from": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
        "to": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
      }
    ]
  }
}
```

Tree mode requires the user's auth session because the species set is scoped to
that user's non-deleted biological scans. It reads `confirmed_species_id` first,
then falls back to `species_id`, dedupes those IDs, and fetches matching
`species_dictionary` rows through the same public species projection used by
detail and catalog responses.

The tree response is still species-level public data only. It adds graph-ready
taxonomy nodes, parent/child edges, species counts, representative species, and
preview fields so the iOS canvas can zoom, focus branches, and show
species previews without exposing scan IDs, users, media, locations, comments,
Explore posts, or field notes. Empty scan libraries return an empty graph and
the iOS canvas shows a scanned-taxonomy empty state.

Observation pattern charts use a separate public endpoint:

```swift
MerianNetworkClient.shared.getSpeciesObservationStats(
    speciesId:scientificName:
)
```

That method sends a public GET to `species-observation-stats` with the
dictionary `species_id` and `scientific_name`. It returns global public
iNaturalist aggregates only. Local Merian logs are aggregated on-device and are
not sent to Supabase. See
[`Species Observation Charts`](./18-species-observation-charts.md) for the full
contract, cache behavior, annotation mappings, and privacy rules.

## Caching

Successful detail and catalog `/species-dictionary` responses are public and
slow-changing, so the Edge Function sends:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

Tree mode sends `Cache-Control: private, no-store` and
`Vary: Authorization, Accept-Encoding` because the graph membership depends on
the signed-in user's scan library. `400`, `401`, `404`, and `500` responses do
not opt into public caching, so missing rows, auth failures, and transient
errors can recover immediately after data is added or fixed.

The iOS client also memoizes recently opened dictionary pages inside
`MerianNetworkClient`. The cache is in memory only, capped at 64 keys, and
expires entries after 10 minutes. Entries are stored under both canonical
`species_id` keys and normalized scientific-name keys when available, so an
Insight or Explore tap that carries a dictionary ID can warm a later
scientific-name route for the same species. The cache is cleared in DEBUG
whenever tests swap the injected `URLSession`.

Invalidation is currently TTL-based: rows refreshed by the scheduled
`refresh-species-content` worker become visible after the iOS memo TTL and the
HTTP freshness window expire. Future curation tooling that needs immediate
public web visibility should add a CDN/cache purge step alongside the dictionary
write.

## Content Quality States

Every current `/species-dictionary` response includes additive
`content_quality`:

- `complete`: reference imagery, overview, habitat/distribution, and meaningful
  taxonomy are present.
- `sparse`: at least two of those public content sections are present.
- `needs_enrichment`: fewer than two public content sections are present.

iOS treats the field as optional for backward compatibility and estimates the
same state when older payloads omit it. `complete` pages render normally.
`sparse` and `needs_enrichment` pages show a compact status card below the
species header so missing sections read as limited dictionary coverage, not
broken layout. The page still renders every available section and continues to
fall back gracefully when images or text are missing.

TelemetryDeck tracks `SpeciesDictionaryOpened`, `SpeciesDictionaryLoaded`,
`SpeciesDictionaryNotFound`, `SpeciesDictionaryRetry`, and
`SpeciesDictionaryImageFallback`. Events include only `entryPoint`,
`contentQuality`, and image `source` where relevant. They never attach species
names, species IDs, user locations, scans, Explore post identifiers, field
notes, comments, image URLs, or review state.

Current iOS entry points are:

- `insight_similar_species`
- `explore_detail_similar_species`

Reserved future entry points are `search`, `deep_link`, `web`, and `unknown`.

## Data Mapping Rules

All backend mapping rules below live in the shared public species projection
module. `/species-dictionary` uses the Deno helper directly; Explore detail
similar species use matching SQL helpers (`public.public_species_common_name`,
`public.public_species_first_reference_image_url`, and
`public.public_species_similar_species`) so SQL output stays aligned with the
Edge DTO.

Common name fallback order:

1. `species_dictionary.common_names.en`
2. first non-empty value in `common_names`
3. `scientific_name`

Reference image mapping:

- The Edge Function prefers ordered rows from `species_reference_images`.
- Each normalized row becomes
  `{ "url": "...", "source": "merian" | "wikipedia" | "gbif" }` with optional
  `license`, `attribution`, `width`, and `height`.
- Normalized rows are ordered Merian first, then Wikipedia, then GBIF.
- If no normalized rows exist, the function falls back to the legacy
  comma-separated `species_dictionary.reference_image_url`, then splits, trims,
  and dedupes URLs.
- Merian rows come from currently published Explore media whose scan-level
  `image_quality_score` meets the scheduled worker threshold. V1 uses all
  non-empty image URLs from the qualifying scan and caps promotion at 8 images
  per species.
- Wikimedia/Wikipedia hosts are marked `wikipedia`.
- When a Wikipedia URL exists and the first image has no clear host signal, the
  first image is treated as `wikipedia`; all other unresolved URLs default to
  `gbif`.

Reference image attribution:

- `license` and `attribution` come from normalized `species_reference_images`
  rows.
- Merian-sourced rows use `license = "Used with permission via Merian"` and the
  source author's public Explore label as attribution.
- `SpeciesDictionaryReferenceGallery` shows the current image's
  attribution/license below the carousel when either value exists.
- The footer follows carousel paging, so multi-image galleries show attribution
  for the active image only.
- Legacy fallback images may not have attribution metadata. iOS can still render
  those images with source labeling, but the future public web frontend must use
  the shared attribution audit before publishing them.

Lookalikes:

- Source table: `species_lookalikes`.
- Hydration uses the explicit PostgREST FK hint
  `species_dictionary!lookalike_id` because the join table has two foreign keys
  to `species_dictionary`.
- Returned fields include `species_id`, `scientific_name`, `common_names`,
  `reference_image_url`, `iucn_red_list_status`, and optional relation metadata
  (`reason`, `visual_traits`, `confidence`, `source`, `review_status`,
  `is_bidirectional`, `sort_order`); thumbnail URLs prefer
  `species_reference_images` and fall back to the legacy dictionary cache.
- Cards show only the common/scientific names over the image. Relation
  rationale and visual-trait explanation copy are intentionally hidden in the
  UI even though the payload remains additive for future curation views.
- The page renders the section as same-stack navigation in V1.

Provenance:

- The iOS page does not display provenance or freshness metadata in V1.
- Backend writers record source/freshness rows in `species_content_provenance`
  for dictionary fields and durable lookalikes.
- `refresh-species-content` consumes
  `public.get_species_content_refresh_queue(...)` on an hourly service-role cron
  and refreshes only GBIF/Wikipedia-backed fields in V1: alternate common names,
  taxonomy, Wikipedia URL/overview, GBIF taxon key, and reference images.
- The worker reports unsupported queued keys as skipped. Common names, habitat
  prose, lookalikes, group tags, IUCN status, and hazard type remain reserved
  for future curation/model refresh tooling.
- Reference image refreshes update both the legacy comma-separated cache and
  normalized `species_reference_images` rows through
  `public.replace_species_reference_images(...)`, preserving existing
  license/attribution metadata for matching URLs and preserving Merian rows.
- `refresh-merian-reference-images` runs hourly as a separate service-role cron
  worker. It promotes published Explore media with `image_quality_score >= 80`
  and either `ai_confidence_score >= 0.95` or a resolved
  `confirmed_species_id`, stores private source/confidence provenance in
  `species_reference_image_merian_sources`, and removes public Merian rows when
  the source Explore post/media stops being visible.

Manual acceptance for Merian reference images:

1. Publish an Explore post backed by a scan with `image_quality_score >= 80` and
   either `ai_confidence_score >= 0.95` or a confirmed species.
2. Run or wait for `refresh-merian-reference-images`.
3. Open the species dictionary page and verify Merian images appear first with
   author attribution.
4. Unshare the Explore post and run or wait for the worker again.
5. Reopen the species dictionary page and verify the Merian images are removed
   while external Wikipedia/GBIF imagery remains.

## Privacy Rules

The species dictionary page must never expose:

- scan IDs
- user IDs
- Explore post IDs
- exact or approximate user locations
- field notes
- comments
- local scan media
- per-scan AI reasoning
- user review state
- preferred common-name overrides
- scan-level pet-identification labels

If a future web frontend consumes this endpoint, it should be able to use the
same response safely without an authenticated session.

## Testing

Backend:

```sh
deno check services/supabase/functions/_shared/http.ts services/supabase/functions/_shared/publicSpeciesProjection.ts services/supabase/functions/_shared/speciesContentProvenance.ts services/supabase/functions/refresh-species-content/index.ts services/supabase/functions/refresh-species-content/db.ts services/supabase/functions/species-dictionary/index.ts services/supabase/functions/species-dictionary/db.ts services/supabase/functions/species-dictionary/db.test.ts
deno test services/supabase/functions/_shared/http_test.ts services/supabase/functions/_shared/publicSpeciesProjection_test.ts services/supabase/functions/_shared/speciesContentProvenance_test.ts services/supabase/functions/refresh-species-content/db.test.ts services/supabase/functions/species-dictionary/db.test.ts
```

iOS:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<booted simulator id>' CODE_SIGNING_ALLOWED=NO test -only-testing:merianTests/SpeciesDictionaryTests
```

Manual acceptance:

- Open a biological Insight scan with similar species.
- Tap a similar-species card.
- Confirm the large species page sheet opens and loads the tapped scientific
  name.
- Open an Explore post detail page with public similar species.
- Confirm the similar-species section appears after habitat/distribution, then
  tap a card and verify the same species page sheet opens.
- Confirm gallery images render, and missing images fall back gracefully.
- Confirm a missing dictionary row shows the not-found/retry state.
