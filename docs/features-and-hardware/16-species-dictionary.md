# Species Dictionary Page

The Species Dictionary Page is the standalone in-app public page for a discovered species. It presents canonical species-level dictionary data and reference imagery without loading a user scan, Explore post, field notes, comments, or any personalized content.

This creates three separate species surfaces in the iOS app:

| Surface | Scope | Primary data source |
|---|---|---|
| Insight scan | A user's specific scan result | `InferenceEngine.shared.speciesData`, local scan media, and per-scan AI reasoning |
| Explore post | A public shared scan | Explore post/detail endpoints plus the backing public scan projection |
| Species dictionary page | General species reference | `species_dictionary`, `species_lookalikes`, and public reference imagery only |

## Product Scope

V1 entry is intentionally narrow: a user taps a similar-species card in either the Insight sheet or an Explore post detail page, and Merian opens a large-detent species dictionary sheet for that species.

Included in V1:

- canonical scientific and common names
- alternate common names
- reference image gallery from normalized public reference imagery
- Wikipedia overview
- habitat description and GBIF heatmap when `gbif_taxon_key` is available
- taxonomy
- IUCN Red List status
- hazard status
- group tags
- read-only similar species

Excluded in V1:

- Explore posts as dictionary-page content
- local scans
- user-uploaded gallery media
- field notes
- comments
- locations
- preferred-name editing
- user-specific review state

## iOS Architecture

Primary files:

- `supabase/functions/_shared/publicSpeciesProjection.ts`
- `merian/Core/Network/SpeciesDictionaryAPIModels.swift`
- `merian/Core/Network/MerianNetworkClient.swift`
- `merian/Features/SpeciesDictionary/ViewModels/SpeciesDictionaryPageViewModel.swift`
- `merian/Features/SpeciesDictionary/Views/SpeciesDictionaryPageView.swift`
- `merian/Features/SpeciesDictionary/Components/SpeciesDictionaryReferenceGallery.swift`
- `merian/Features/SpeciesDictionary/Components/SpeciesDictionaryCards.swift`
- `merian/Features/Insights/Components/Cards/SimilarSpeciesGallery.swift`
- `merian/Features/Insights/Views/Content/BiologicalView.swift`
- `merian/Features/Explore/Views/ExplorePostDetailView.swift`

`SpeciesDictionaryPageView` owns its own `NavigationStack` and is presented as a `.large` detent sheet. It does not mount `InferenceEngine`, does not read SwiftData scan records, and does not reuse `InsightSheetViewModel`.

`SpeciesDictionaryPageViewModel` is an `@Observable @MainActor` model with four user-visible states:

- `loading`
- `loaded(SpeciesDictionaryEntry)`
- `notFound`
- `error(String)`

The model trims the incoming scientific name before fetching and prefers a `speciesId` lookup when the route provides one. A `404` from the backend maps to `notFound`; other failures map to `error`.

## Entry Point

`SimilarSpeciesGallery` and `SimilarSpeciesCard` accept an optional `onSpeciesSelected` callback. Existing read-only usages can omit the callback. The Insight sheet biological result passes a callback from `BiologicalView`:

```swift
SimilarSpeciesGallery(
    similarData: similarData,
    currentScientificName: inferenceEngine.speciesData?.scientificName,
    currentCommonName: inferenceEngine.speciesData?.commonName,
    onSpeciesSelected: { entry in
        speciesDictionaryRoute = SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId
        )
    }
)
```

The route is held as `SpeciesDictionaryRoute?` and presented via `.sheet(item:)`. `speciesId` is preferred for lookup when present; `scientificName` remains the display and backward-compatible lookup fallback.

Explore post detail uses the same route from its public `/get-explore-post-detail` similar-species payload. The Explore entry point is detail-only; feed cards, map previews, author profile previews, scan library, search, and external deep links do not open the species dictionary in V1.

## Backend Contract

The iOS client calls:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

That method POSTs to the public `species-dictionary` Edge Function:

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

The endpoint is public by design and has `verify_jwt = false`. It may receive normal app auth headers from `MerianNetworkClient`, but the function does not require or read identity. The response must remain species-level public dictionary data only.

`schema_version = 1` is the shared public species contract used by the dictionary page and Explore detail similar-species projection. iOS treats the key as optional for backward compatibility with older mocks or deployed functions, and future web clients should use it before depending on new fields.

## Caching

Successful `/species-dictionary` responses are public and slow-changing, so the Edge Function sends:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

Only `200 OK` dictionary responses are cacheable. `400`, `404`, and `500` responses do not opt into public caching, so missing rows and transient errors can recover immediately after data is added or fixed.

The iOS client also memoizes recently opened dictionary pages inside `MerianNetworkClient`. The cache is in memory only, capped at 64 keys, and expires entries after 10 minutes. Entries are stored under both canonical `species_id` keys and normalized scientific-name keys when available, so an Insight or Explore tap that carries a dictionary ID can warm a later scientific-name route for the same species. The cache is cleared in DEBUG whenever tests swap the injected `URLSession`.

Invalidation is currently TTL-based: refreshed species rows become visible after the iOS memo TTL and the HTTP freshness window expire. Future scheduled refresh or curation tooling that needs immediate public web visibility should add a CDN/cache purge step alongside the dictionary write.

## Content Quality States

Every current `/species-dictionary` response includes additive `content_quality`:

- `complete`: reference imagery, overview, habitat/distribution, and meaningful taxonomy are present.
- `sparse`: at least two of those public content sections are present.
- `needs_enrichment`: fewer than two public content sections are present.

iOS treats the field as optional for backward compatibility and estimates the same state when older payloads omit it. `complete` pages render normally. `sparse` and `needs_enrichment` pages show a compact status card below the species header so missing sections read as limited dictionary coverage, not broken layout. The page still renders every available section and continues to fall back gracefully when images or text are missing.

TelemetryDeck tracks `SpeciesDictionaryLoaded` with `contentQuality` and `SpeciesDictionaryNotFound` without attaching species names, IDs, user locations, scans, or Explore post identifiers.

## Data Mapping Rules

All backend mapping rules below live in the shared public species projection module. `/species-dictionary` uses the Deno helper directly; Explore detail similar species use matching SQL helpers (`public.public_species_common_name`, `public.public_species_first_reference_image_url`, and `public.public_species_similar_species`) so SQL output stays aligned with the Edge DTO.

Common name fallback order:

1. `species_dictionary.common_names.en`
2. first non-empty value in `common_names`
3. `scientific_name`

Reference image mapping:

- The Edge Function prefers ordered rows from `species_reference_images`.
- Each normalized row becomes `{ "url": "...", "source": "wikipedia" | "gbif" }` with optional `license`, `attribution`, `width`, and `height`.
- If no normalized rows exist, the function falls back to the legacy comma-separated `species_dictionary.reference_image_url`, then splits, trims, and dedupes URLs.
- Wikimedia/Wikipedia hosts are marked `wikipedia`.
- When a Wikipedia URL exists and the first image has no clear host signal, the first image is treated as `wikipedia`; all other unresolved URLs default to `gbif`.

Reference image attribution:

- `license` and `attribution` come from normalized `species_reference_images` rows.
- `SpeciesDictionaryReferenceGallery` shows the current image's attribution/license below the carousel when either value exists.
- The footer follows carousel paging, so multi-image galleries show attribution for the active image only.
- Legacy fallback images may not have attribution metadata. iOS can still render those images with source labeling, but the future public web frontend must use the shared attribution audit before publishing them.

Lookalikes:

- Source table: `species_lookalikes`.
- Hydration uses the explicit PostgREST FK hint `species_dictionary!lookalike_id` because the join table has two foreign keys to `species_dictionary`.
- Returned fields include `species_id`, `scientific_name`, `common_names`, `reference_image_url`, `iucn_red_list_status`, and optional relation metadata (`reason`, `visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`, `sort_order`); thumbnail URLs prefer `species_reference_images` and fall back to the legacy dictionary cache.
- Cards show the relation `reason` when present, otherwise they can fall back to the first shared visual traits.
- The page renders the section read-only in V1.

Provenance:

- The iOS page does not display provenance or freshness metadata in V1.
- Backend writers record source/freshness rows in `species_content_provenance` for dictionary fields and durable lookalikes.
- Future refresh workers should consume `public.get_species_content_refresh_queue(...)` so stale GBIF/Wikipedia/model-enriched fields can be refreshed selectively without overwriting curated content blindly.

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

If a future web frontend consumes this endpoint, it should be able to use the same response safely without an authenticated session.

## Testing

Backend:

```sh
deno check supabase/functions/_shared/http.ts supabase/functions/_shared/publicSpeciesProjection.ts supabase/functions/_shared/speciesContentProvenance.ts supabase/functions/species-dictionary/index.ts supabase/functions/species-dictionary/db.ts supabase/functions/species-dictionary/db.test.ts
deno test supabase/functions/_shared/http_test.ts supabase/functions/_shared/publicSpeciesProjection_test.ts supabase/functions/_shared/speciesContentProvenance_test.ts supabase/functions/species-dictionary/db.test.ts
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
- Confirm the large species page sheet opens and loads the tapped scientific name.
- Open an Explore post detail page with public similar species.
- Confirm the similar-species section appears after habitat/distribution, then tap a card and verify the same species page sheet opens.
- Confirm gallery images render, and missing images fall back gracefully.
- Confirm a missing dictionary row shows the not-found/retry state.
