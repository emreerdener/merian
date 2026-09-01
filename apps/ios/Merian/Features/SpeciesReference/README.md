# Species Reference

`SpeciesReference` owns reusable species-level reference presentation shared by
Insight, Species Dictionary, Explore detail, and identification review.

The canonical product contracts remain
[Species Observation Charts](../../../../../docs/features-and-hardware/18-species-observation-charts.md),
[Species Dictionary](../../../../../docs/features-and-hardware/16-species-dictionary.md),
and the
[components guide](../../../../../docs/features-and-hardware/09-components-guide.md).
This README defines the iOS ownership and verification boundary.

## Ownership

- `Models/` owns platform-neutral local-stat values, chart and heatmap
  presentation, normalization, aggregation, and GBIF response classification.
- `Services/` is the only owner that resolves `MerianNetworkClient`,
  `URLSession`, `LocalImageLoader`, app haptics, habitat enrichment actions, or
  imperative SwiftData queries. Small closure-based dependency values adapt
  those live effects for initializer injection.
- `ViewModels/` owns generation-fenced observation-stat, GBIF-tile, and fallback
  reference-image state. A late response cannot overwrite a newer species or
  taxon request. Empty identities invalidate active work, and an already-
  cancelled valid request cannot claim generation ownership or clear the
  currently published presentation.
- `Views/` owns the observation-chart composition root, selected tab, task
  identity, accessibility summary, and loading/footer presentation.
- `Components/Charts`, `Components/Habitat`, `Components/Lookalikes`,
  `Components/Maps`, and `Components/Taxonomy` own render-focused leaf UI.
  Gallery scroll state, map gestures, habitat retry timing, placeholders, and
  animation remain view-local so cancellation and interaction timing do not
  change.

Views and Components perform no direct networking or singleton resolution. Keep
the existing chart, habitat, heatmap, taxonomy, gallery, and image-fetcher
initializer call sites source-compatible. Every production Swift file in this
folder must remain at or below 600 lines.

## Observation Statistics

`SpeciesObservationStatsDatabaseActor` fetches narrow local `LocalScanRecord`
projections. `SpeciesObservationStatsReducer` performs the pure matching and
bucket reduction. `SpeciesObservationStatsDependencies` adapts that actor and
the public `/species-observation-stats` client call, while
`SpeciesObservationStatsViewModel` coordinates the two sources and preserves a
usable local result when the public baseline fails. Changing species identity
clears the prior species' local and public values before either replacement
request awaits; a same-species refresh retains its current presentation until
the refreshed values arrive. An empty identity invalidates an in-flight load,
and cancellation after an uncooperative local dependency prevents public loading
and publication.

Local scan dates, life stages, identifiers, and counts never enter the public
request. The request contains only the canonical dictionary species UUID and
scientific name. DTOs and wire validation remain in `Core/Network`; this feature
owns no JSON contract.

## External Reference Images

`SimilarSpeciesImageFetcher` is the observable fallback state owner for
lookalikes and identification candidates that lack a usable `referenceImageUrl`.
`SimilarSpeciesImageService` concurrently resolves Wikipedia and GBIF metadata,
filters every candidate through `ExternalReferenceImagePolicy`, downloads
permitted candidates through `LocalImageLoader`, and restores source ordering
before publication. `SimilarSpeciesImageFetcher` only publishes the resulting
observable state and invalidates an active load when its species identity is
cleared or replaced. An already-cancelled load cannot claim generation ownership
or clear valid presentation. Network timing therefore cannot change the
preferred thumbnail or restore stale content.

This feature service intentionally owns the Wikipedia summary request and GBIF
scientific-name query needed for fallback UI images. The distinct Wikipedia
mobile-sections and GBIF taxon-key contract shared by Inference and scan-
thumbnail recovery lives in
`Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift`; do not
duplicate that session, wire DTO, or HTML-normalization boundary here.

The exact denied media path
`inaturalist-open-data.s3.amazonaws.com/photos/605615444/` is treated as absent.
This covers the original and resized variants for GBIF occurrence `5938154750`
without suppressing the European wildcat card or other imagery for the species.
If the first result is denied or fails, the next successful permitted result is
shown. If every result is denied or fails, the existing leaf placeholder is
shown.

Historical `SimilarSpeciesEntry` blobs are sanitized while decoding, so a
previously cached denied URL becomes `nil` and automatically enters the fallback
path. Do not clear all cached lookalikes to repair one media outlier.

## GBIF Heatmap

`GBIFHeatmapTileService` owns the existing best-effort zoom-zero density-tile
request and bounded timeout. `GBIFHeatmapResponsePolicy` distinguishes no data,
provider outage, invalid response, and decodable image states. The service
transfers decoded immutable artwork through `SendableCGImage`, and
`GBIFHeatmapViewModel` creates the UIKit presentation image on the main actor
and fences response publication by request generation. A request already
cancelled before entry leaves the currently published heatmap state intact.
`GBIFHeatmapMapView` retains only the base-map composition, overlay copy, and
two-finger zoom/pan state.

## Verification

Mirrored tests under `MerianTests/Features/SpeciesReference` cover local
aggregation, chart presentation, local/public failure independence,
latest-request-wins behavior, pre-entry cancellation for all three asynchronous
state owners, cancellation after uncooperative dependencies, GBIF response and
endpoint adaptation, fallback image ordering and races, ownership folders,
Services-only live resolution, platform-neutral Models, absence of feature-
owned unchecked sendability, private map helpers, aggregate removal, and the
600-line ceiling.

```bash
make xcodegen
xcodebuild -project Merian.xcodeproj -scheme Merian \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/SpeciesObservationStatsReducerTests \
  -only-testing:merianTests/SpeciesObservationStatsViewModelTests \
  -only-testing:merianTests/GBIFHeatmapViewModelTests \
  -only-testing:merianTests/SimilarSpeciesImageFetcherTests \
  -only-testing:merianTests/SpeciesReferenceArchitectureTests \
  -only-testing:merianTests/SpeciesDictionaryTests \
  -only-testing:merianTests/LocalImageLoaderTests test
```
