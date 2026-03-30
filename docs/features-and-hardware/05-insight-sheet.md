# Insight Sheet

The Insight Sheet is the primary post-scan result screen, surfacing AI taxonomy, confidence data, ecological context, and media for every scan. It is presented as a sheet modal from `CameraRootView` when `CameraViewModel.activeSheet == .insight`.

---

## Architecture

| File | Role |
|---|---|
| `InsightSheetViewModel` | `@Observable @MainActor final class` — UI state, SwiftData ops, share/export |
| `InsightSheetView` | Root sheet view; owns `@State private var viewModel = InsightSheetViewModel()` |
| `InsightContentView` | Routes to `BiologicalView` or `NonBiologicalView` based on `speciesData.isBiological` |
| `BiologicalView` | Full biological result: taxonomy, ecology badges, confidence, Wikipedia, lookalike diagnostic. Cards enter with a hardware-gated staggered animation via `CardEntranceModifier` (indices 0–8). |
| `NonBiologicalView` | Simplified result for non-biological subjects (objects, structures); renders a name/description card followed by a `ScanInformationCard` |
| `InsightHeader` | Scrollable header with species name, description, `ConfidenceBadge`, and conditionally the `ModelTierBadge` pill if the confidence score is a "Possible match" |
| `ImagesCarousel` | Horizontally scrolling image strip combining live captures + historic paths + reference images |
| `ConfidenceBadge` | Tappable capsule showing the AI's confidence band (Strong / Possible / Weak) with a shimmering glare animation; opens `ConfidenceExplanationSheet` on tap |
| `ConfidenceSpectrum` | Visual confidence spectrum with `SpectrumNode` labels; band thresholds derived from `MerianConfig` |
| `ConfidenceExplanationSheet` | Sub-sheet explaining the confidence scale, AI limitations, and tips for improving scan accuracy |
| `TaxonomyCard` | Collapsible card showing the full Linnaean tree |
| `SimilarSpeciesGallery` | Horizontally scrolling carousel of lookalike or similar species sourced from `speciesData.similarSpecies` (`SimilarSpecies` wrapper decoded from `LocalScanRecord.lookalikesData` for V27+ records, or from `LocalScanRecord.similarSpecies: [String]?` for pre-V27 records); each `SimilarSpeciesCard` renders `referenceImageUrl` directly when available, otherwise falls back to `SimilarSpeciesImageFetcher` |
| `OverviewCard` | Structural card rendering dynamic biological KeyValueRow metrics (e.g., size, life stage, interactions, invasive species status) followed by an 8-line truncated Wikipedia extract and a built-in Safari "Learn more" button. |
| `ScanInformationCard` | Spatiotemporal context card: location, elevation, zoom, weather, date/time, and a MapKit snapshot |
| `GBIFHeatmapMapView` | SwiftUI `View` that composites two images to render a full-world GBIF occurrence heatmap natively. (1) A static `WorldMapBase` custom Mapbox topography background image, entirely eliminating MapKit CPU overhead. (2) The GBIF density zoom-0 tile (`/0/0/0@2x.png`) — a single 512 px PNG covering the entire world in Web Mercator — is fetched and drawn on top. Both images perfectly align their projection/extent. Features a custom `UIViewRepresentable` bridge (`PinchPanOverlay`) which unlocks elastic 2-finger pinch and pan exploration. This gesture controller safely locks down the encompassing parent `ScrollView` and engages `.interactiveDismissDisabled` on the bottom sheet to prevent SwiftUI swipe cancellation conflicts during map manipulation. |
| `HabitatAndDistributionCard` | Habitat and distribution card: encyclopedic habitat text. Has three states: (1) **Loaded** — habitat text; (2) **Loading** — shimmer skeleton shown while `inferenceEngine.isEnrichmentLoading` is `true`; (3) **Retry** — data missing, tap to re-trigger `fetchAndApplyEnrichment`. |
| `ToxicityBanner` | Hazard warning banner shown when `insightData.hazardType != "none"`. Displays hazard-specific copy: venomous (bite/sting), allergenic (allergic reaction), irritant (skin/eye), or poisonous (ingestion/contact). |
| `ConservationBanner` | IUCN Red List status banner |
| `CelebrationBanner` | "New Discovery" confetti overlay |

---

## Data Source

`InsightSheetView` reads everything from `InferenceEngine.shared.speciesData` (a `SpeciesData` struct). It does NOT own a copy of the data — it observes the engine directly via `@Environment(InferenceEngine.self)`.

`InsightSheetViewModel` holds a reference to the `InferenceEngine` and exposes computed properties:

```swift
var headerTitle: String { inferenceEngine?.speciesData?.commonName.capitalized ?? "Scanning subject..." }
var hazardType: String { inferenceEngine?.speciesData?.insightData.hazardType ?? "none" }
var isHazardous: Bool { hazardType != "none" }
var refUrls: [String] { /* parsed from comma-separated referenceImageUrl */ }
var totalImages: Int { liveCount + validHistoricImagePaths.count + refUrls.count }
```

`InsightSheetView` also queries SwiftData directly via `@Query` for `[ScanCollection]` (reverse-sorted by `createdAt`) to populate the collection management toolbar.

---

## Image Carousel

The carousel merges three image sources in order:

1. **Live captures** (`inferenceEngine.activeLiveCaptureDatas`) — raw `Data` from the current shutter session, available during the active inference call
2. **Historic paths** (`inferenceEngine.validHistoricImagePaths`) — local file paths written to disk by `InferenceProcessingActor.parseAndSave` on live scan success, or populated via `InferenceEngine.load(from:)` for scans opened from the library
3. **Reference images** (`speciesData.referenceImageUrl`) — comma-separated verified field observations (e.g. iNaturalist) and Wikimedia images populated natively via GBIF Occurrence array hydration.

**Seamless image source handoff**: On a live scan, `validHistoricImagePaths` is populated with the on-disk paths returned by `parseAndSave` *before* `speciesData` is set and *before* `activeLiveCaptureDatas` is cleared. This means the carousel has the user's saved image ready the instant the insight sheet renders — the reference image is never the only page shown on first open. The `NativePageCarousel` is keyed on `scanId` so that when `speciesData` is set (changing the key), the initial page build already includes the on-disk image paths.

**On-disk image quality**: The files written to `validHistoricImagePaths` are 2048 px WebP (display-quality path). This covers the full native pixel width of all current iOS devices without upscaling (iPhone Pro Max at 3× ≈ 1290 px; iPad Pro at 2× = 2048 px), eliminating the JPEG blocking artifacts that appeared when the carousel rendered the 1024 px inference payload directly. The AI inference path remains at 1024 px — see [Image Pipeline → Dual-Path Downsample](../system-architecture/03-image-pipeline.md) for the full architecture.

All images are loaded through `AsyncLocalImageView`, which handles RAM cache hits, request coalescing, and local-vs-remote routing transparently.

Invalid carousel URLs are purged from state via `InferenceEngine.dropInvalidCarouselImage(_:)`, which removes the entry from `validHistoricImagePaths` or from the comma-separated `speciesData.referenceImageUrl` without throwing index-out-of-bounds errors.

---

## Scan Information Card

`ScanInformationCard` renders the spatiotemporal context captured at the moment of the scan. It is hidden entirely when `hasValidData` is false (no location, weather, zoom, elevation, or timestamp is available), preventing the card from appearing as an empty placeholder.

Rows displayed when present:

| Row | Source | Condition |
|---|---|---|
| LOCATION | `speciesData.locationName` | Non-empty string |
| ELEVATION | `speciesData.gpsElevation` | Non-nil, non-zero |
| ZOOM | `speciesData.zoomFactor` | Non-nil (1× scans omit this row) |
| WEATHER | `speciesData.weatherTemperatureF` + `weatherCondition` | Both non-nil |
| DATE | `timestamp` parameter | Non-nil |
| TIME | `timestamp` parameter | Non-nil |
| Map | `speciesData.gpsLatitude` + `gpsLongitude` | Valid coordinate pair, not `(0, 0)` |

The ZOOM row shows the value formatted as `"3.0×"`. It is omitted for 1× scans because `CaptureTelemetry.zoomFactor` is set to `nil` when zoom is at 1× — a 1× value carries no useful signal for identification. The row is also absent for scans captured on single-lens hardware (`CameraManager.isZoomSupported == false`) and any scan recorded before `MerianSchemaV13`.

---

## Species Insights

`HabitatAndDistributionCard` renders habitat and distribution intelligence for the identified species. Available to all users.

### Loading Flow (new scans)

After a successful biological scan, `InferenceEngine.analyze()` fires `fetchAndApplyEnrichment(modelContext:)` in a background `Task` for all users. While this request is in flight:

- `inferenceEngine.isEnrichmentLoading` is `true`
- `HabitatAndDistributionCard` renders an animated shimmer skeleton (three placeholder text lines)
- When data arrives (typically 2–3 seconds post-scan), `speciesData.habitatDescription` is patched in-place on `@MainActor`, the skeleton is replaced by content with no navigation required, and the data is persisted to `LocalScanRecord`

### Loading Flow (historical scans)

When `InferenceEngine.load(from:)` loads a `LocalScanRecord` that is missing `habitatDescription`, `gbifTaxonKey`, or both `lookalikesData` and `similarSpecies` (i.e., no lookalike data in either form), it automatically fires `fetchAndApplyEnrichment`. This gap-fills enrichment for scans captured before the enrichment pipeline shipped.

### States

| State | Trigger | Rendered |
|---|---|---|
| **Loaded** | `habitatDescription != nil` | Habitat text |
| **Loading** | `inferenceEngine.isEnrichmentLoading == true` | Shimmer skeleton (3 text lines) |
| **Retry** | No data, not loading | "Retry" button → calls `inferenceEngine.fetchAndApplyEnrichment` |

### Similar Species Display Gate

`similar_species` data is rendered by `SimilarSpeciesGallery` inside `BiologicalView` at `cardEntrance(index: 3)`. The gallery receives an `isLowConfidence` flag driven by the scan's `confidenceScore` against the user's tiered `.diagnosticTrigger` threshold (0.88 for Free/Flash; 0.80 for Premium/Pro). When `isLowConfidence = true`, the gallery shows a "POTENTIAL LOOKALIKES" warning label; otherwise it is presented as informational "SIMILAR SPECIES". `enrich-scan` always returns `similar_species` when data is available — no confidence gate is applied on the backend or in `fetchAndApplyEnrichment`.

Each `SimilarSpeciesCard` receives a `SimilarSpeciesEntry` with `scientificName`, `commonName`, `referenceImageUrl`, and `iucnRedListStatus`. When `referenceImageUrl` is non-nil (join table resolved a field photo), the card renders it directly via `AsyncLocalImageView`. When nil (historical records without a join table entry), the card falls back to `SimilarSpeciesImageFetcher` for an on-demand Wikipedia/GBIF lookup.

---

## Confidence Badge and Spectrum

`ConfidenceBadge` is a tappable liquid-glass capsule that shows the AI's confidence band for the current scan. The band label, color, and icon are derived from `confidenceScore` against the `MerianConfig` thresholds. An animated holographic shimmer sweeps across the badge rim every 4–10 seconds. Tapping it opens `ConfidenceExplanationSheet`.

Band thresholds (managed dynamically via `MerianConfig.confidenceBands(for: isPro)`):

**Gemini 2.5 Flash (Free Tier)**
| Band label | Color | Score range |
|---|---|---|
| Strong match | Green | ≥ 93% |
| Possible match | Orange | 75% – 92% |
| Weak match | Gray | Below 75% |

**Gemini 2.5 Pro (Premium Tier)**
| Band label | Color | Score range |
|---|---|---|
| Strong match | Green | ≥ 85% |
| Possible match | Orange | 65% – 84% |
| Weak match | Gray | Below 65% |

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items using the same `MerianConfig` constants so the displayed percentage ranges are always in sync with the badge logic.

`ConfidenceExplanationSheet` opens as a bottom sheet from the badge tap. It contains `ConfidenceHeader`, `ConfidenceSpectrum`, `AIMistakesBanner`, and `ProTips` (which conditionally shows a location permission prompt when GPS access is not granted).

`blur_score` is populated from live inference only (`SpeciesData.blurScore` maps to `EdgeResponse.blur_score`). It is `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`.

---

## Reference Image and Wikipedia Hydration

Extended ecological media data is loaded in three passes:

1. **Synchronous with inference** (live scans): the Edge function fetches Wikipedia in `EdgeRuntime.waitUntil` and includes `wikipedia_overview` and `wikipedia_url` in the response. These populate immediately when the sheet opens.
2. **Retroactive Wikipedia hydration** (live scans where Wikipedia was missing, and all historical scans): `InferenceEngine.asynchronouslyFetchWikipediaAndHydrate` fires a secondary `GET` to `en.wikipedia.org/api/rest_v1/page/summary/<scientific_name>` with a 4-second timeout. On success it mutates `speciesData.wikipediaOverview`, `speciesData.wikipediaUrl`, and `speciesData.referenceImageUrl` in-place on the `@MainActor`.
3. **Dynamic GBIF Native Hydration**: When the species' `gbif_taxon_key` is available (either instantly on a Cache Hit, or returned seconds later by the `enrich-scan` API), the iOS client calls `InferenceEngine.fetchGBIFImagesAndHydrate(for:)`. This queries the `api.gbif.org/v1/occurrence/search` API for 3-4 high-quality iNaturalist field photos, dynamically injecting them into the carousel to ensure highly accurate visual context.

---

## Celebration Banner (New Discovery)

On sheet `.onAppear`, `InsightSheetViewModel.evaluateVoiceOverAndCelebration` checks:

```swift
if data.isNewDiscovery && data.isBiological
    && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
    showCelebration = true
}
```

`showCelebration = true` triggers the `CelebrationBanner` confetti overlay. VoiceOver users receive an accessibility announcement instead — including a hazard-specific warning (venomous / allergenic / irritant / toxic) when `hazardType != "none"`.

---

## Scroll-Aware Toolbar

`InsightSheetView` tracks whether the common name has scrolled past the viewport using a `CommonNameScrollOffsetKey` preference key. `InsightSheetViewModel.evaluateScrollOffset(minY:)` compares the scroll position against a threshold of `-(screen width + 80)`. When the name scrolls past, `isCommonNameScrolledPast` flips to `true`, which causes `TopToolbar` to display the species name inline in the navigation bar title area.

---

## Collection Management

Users can add or remove the current scan from any `ScanCollection`:

```swift
func toggleScanInCollection(_ collection: ScanCollection, modelContext: ModelContext) {
    // toggles record.collections membership
    // saves modelContext
    // calls OfflineQueueManager.shared.syncCollections() for immediate cloud push
    // fires a toast message
}
```

"New Collection" is handled by the `newCollectionAlert` view modifier attached to `InsightSheetView`. It creates a `ScanCollection` in SwiftData with a UUID immediately, then syncs via `pushCollectionsToEdge()`.

---

## Deletion

`eradicateCurrentScan` delegates to `ScanRepository.shared.eradicateScan(record:modelContext:)`, which follows the transactional deletion protocol:

1. Tombstones any in-flight upload via `softDeleteQueuedScan`
2. Inserts `PendingCloudDeletionTask` + deletes `LocalScanRecord` atomically, then calls `modelContext.save()` (DB commit first)
3. Purges local image files via `FileIOActor` only after save succeeds
4. Immediately attempts cloud deletion via `syncPendingDeletions()`

The sheet is dismissed via `DismissAction` after the database operations complete.

---

## Share & Export

`InsightMediaExportManager.shared` handles two export paths:

- **Save to Photos**: passes live capture data, valid historic file paths, and any R2-hosted reference URLs (filtered to `merian.app` domain only) to `ExportProcessingActor.shared.saveUserPhotos`. Each image is saved to Camera Roll via `PhotoLibraryManager.shared.saveImageManual`. On completion, `showSaveSuccessAlert` is set to `true`.
- **Share Sheet**: constructs a share payload with the species common name, scientific name, and the best available image (live > historic > reference), then presents `UIActivityViewController` via `ShareSheetUtility.present`.
