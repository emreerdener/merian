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
- reference image gallery from dictionary `reference_image_url`
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

The model trims the incoming scientific name before fetching. A `404` from the backend maps to `notFound`; other failures map to `error`.

## Entry Point

`SimilarSpeciesGallery` and `SimilarSpeciesCard` accept an optional `onSpeciesSelected` callback. Existing read-only usages can omit the callback. The Insight sheet biological result passes a callback from `BiologicalView`:

```swift
SimilarSpeciesGallery(
    similarData: similarData,
    currentScientificName: inferenceEngine.speciesData?.scientificName,
    currentCommonName: inferenceEngine.speciesData?.commonName,
    onSpeciesSelected: { entry in
        speciesDictionaryRoute = SpeciesDictionaryRoute(scientificName: entry.scientificName)
    }
)
```

The route is held as `SpeciesDictionaryRoute?` and presented via `.sheet(item:)`.

Explore post detail uses the same route from its public `/get-explore-post-detail` similar-species payload. The Explore entry point is detail-only; feed cards, map previews, author profile previews, scan library, search, and external deep links do not open the species dictionary in V1.

## Backend Contract

The iOS client calls:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
```

That method POSTs to the public `species-dictionary` Edge Function:

```json
{
  "scientific_name": "Danaus plexippus"
}
```

Successful responses are wrapped in a `data` envelope:

```json
{
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
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
      { "url": "https://upload.wikimedia.org/...", "source": "wikipedia" },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
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

## Data Mapping Rules

Common name fallback order:

1. `species_dictionary.common_names.en`
2. first non-empty value in `common_names`
3. `scientific_name`

Reference image mapping:

- `species_dictionary.reference_image_url` is a comma-separated string.
- The Edge Function splits, trims, and dedupes URLs.
- Each URL becomes `{ "url": "...", "source": "wikipedia" | "gbif" }`.
- Wikimedia/Wikipedia hosts are marked `wikipedia`.
- When a Wikipedia URL exists and the first image has no clear host signal, the first image is treated as `wikipedia`; all other unresolved URLs default to `gbif`.

Lookalikes:

- Source table: `species_lookalikes`.
- Hydration uses the explicit PostgREST FK hint `species_dictionary!lookalike_id` because the join table has two foreign keys to `species_dictionary`.
- Returned fields are limited to `scientific_name`, `common_names`, `reference_image_url`, and `iucn_red_list_status`.
- The page renders the section read-only in V1.

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
deno check supabase/functions/species-dictionary/index.ts supabase/functions/species-dictionary/db.ts supabase/functions/species-dictionary/db.test.ts
deno test supabase/functions/species-dictionary/db.test.ts
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
