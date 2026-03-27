# Insight Sheet

The Insight Sheet is the primary post-scan result screen, surfacing AI taxonomy, confidence data, ecological context, and media for every scan. It is presented as a sheet modal from `CameraRootView` when `CameraViewModel.activeSheet == .insight`.

---

## Architecture

| File | Role |
|---|---|
| `InsightSheetViewModel` | `@Observable @MainActor final class` — UI state, SwiftData ops, share/export |
| `InsightSheetView` | Root sheet view; owns `@State private var viewModel = InsightSheetViewModel()` |
| `InsightContentView` | Routes to `BiologicalView` or `NonBiologicalView` based on `speciesData.isBiological` |
| `BiologicalView` | Full biological result: taxonomy, ecology badges, confidence, Wikipedia, lookalike diagnostic |
| `NonBiologicalView` | Simplified result for non-biological subjects (objects, structures); renders a name/description card followed by a `ScanInformationCard` |
| `InsightHeader` | Scrollable header with species name, description, badges, and `ConfidenceBadge` |
| `ImagesCarousel` | Horizontally scrolling image strip combining live captures + historic paths + reference images |
| `ConfidenceBadge` | Tappable capsule showing the AI's confidence band (Strong / Possible / Weak) with a shimmering glare animation; opens `ConfidenceExplanationSheet` on tap |
| `ConfidenceSpectrum` | Visual confidence spectrum with `SpectrumNode` labels; band thresholds derived from `MerianConfig` |
| `ConfidenceExplanationSheet` | Sub-sheet explaining the confidence scale, AI limitations, and tips for improving scan accuracy |
| `TaxonomyCard` | Collapsible card showing the full Linnaean tree |
| `AIReasoningCard` | Diagnostic comparison — primary rationale, lookalike name, key differentiators |
| `WikipediaCard` | Wikipedia extract with SafariServices deep link |
| `ScanInformationCard` | Spatiotemporal context card: location, elevation, zoom, weather, date/time, and a MapKit snapshot |
| `PremiumInsightsCard` | Enriched intelligence hook: Encyclopedic habitat parameters, and global distribution vector heatmaps. If the user is Free it acts as a 7-Day pass glassmorphism paywall unlocking via RevenueCat. |
| `ToxicityBanner` | Red warning banner for poisonous subjects |
| `ConservationBanner` | IUCN Red List status banner |
| `CelebrationBanner` | "New Discovery" confetti overlay |

---

## Data Source

`InsightSheetView` reads everything from `InferenceEngine.shared.speciesData` (a `SpeciesData` struct). It does NOT own a copy of the data — it observes the engine directly via `@Environment(InferenceEngine.self)`.

`InsightSheetViewModel` holds a reference to the `InferenceEngine` and exposes computed properties:

```swift
var headerTitle: String { inferenceEngine?.speciesData?.commonName.capitalized ?? "Scanning subject..." }
var isPoisonous: Bool { inferenceEngine?.speciesData?.insightData.isPoisonous ?? false }
var refUrls: [String] { /* parsed from comma-separated referenceImageUrl */ }
var totalImages: Int { liveCount + validHistoricImagePaths.count + refUrls.count }
```

`InsightSheetView` also queries SwiftData directly via `@Query` for `[ScanCollection]` (reverse-sorted by `createdAt`) to populate the collection management toolbar.

---

## Image Carousel

The carousel merges three image sources in order:

1. **Live captures** (`inferenceEngine.activeLiveCaptureDatas`) — raw `Data` from the current shutter session, available during the active inference call
2. **Historic paths** (`inferenceEngine.validHistoricImagePaths`) — local file paths written to disk by `InferenceProcessingActor.parseAndSave` on live scan success, or populated via `InferenceEngine.load(from:)` for scans opened from the library
3. **Reference images** (`speciesData.referenceImageUrl`) — comma-separated Wikimedia or reference URLs arrived from Wikipedia hydration

**Seamless image source handoff**: On a live scan, `validHistoricImagePaths` is populated with the on-disk paths returned by `parseAndSave` *before* `speciesData` is set and *before* `activeLiveCaptureDatas` is cleared. This means the carousel has the user's saved image ready the instant the insight sheet renders — the reference image is never the only page shown on first open. The `NativePageCarousel` is keyed on `scanId` so that when `speciesData` is set (changing the key), the initial page build already includes the on-disk image paths.

**On-disk image quality**: The files written to `validHistoricImagePaths` are 2048 px WebP (display-quality path). This covers the full native pixel width of all current iOS devices without upscaling (iPhone Pro Max at 3× ≈ 1290 px; iPad Pro at 2× = 2048 px), eliminating the JPEG blocking artifacts that appeared when the carousel rendered the 1024 px inference payload directly. The AI inference path remains at 1024 px — see [Image Pipeline → Dual-Path Downsample](../system-architecture/14-image-pipeline.md) for the full architecture.

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

## Premium Insights

`PremiumInsightsCard` dynamically bridges real-time Edge validation and local SwiftData memory to render deep encyclopedic intelligence.

- **Pro Users**: The `/identify` response includes a `premium_insights` block for Pro-tier requests, populated from `species_dictionary` (Cache Hit) or from the concurrent `fetchStaticEncyclopedicData` call (Cache Miss). The card renders immediately with no additional network call.
- **Free Users — Paywall State**: If the scan has no `habitatDescription` and `isProActive` is `false`, the card renders as a glassmorphism paywall offering a frictionless $2.99 7-Day Pass via the RevenueCat `weekly` package.
- **Free Users — Ad-Hoc Enrichment**: Once the pass is active (or if the user is already Pro), tapping "Generate Insights" calls `/enrich-scan`. That function checks `species_dictionary` first — because the `/identify` Cache Miss path writes habitat and distribution data on every new species regardless of tier, the DB-first check resolves immediately for most scans with no Gemini call or added latency. The returned data is saved to `LocalScanRecord` and bound back to `InferenceEngine.speciesData.habitatDescription` in-place.

---

## Confidence Badge and Spectrum

`ConfidenceBadge` is a tappable liquid-glass capsule that shows the AI's confidence band for the current scan. The band label, color, and icon are derived from `confidenceScore` against the `MerianConfig` thresholds. An animated holographic shimmer sweeps across the badge rim every 4–10 seconds. Tapping it opens `ConfidenceExplanationSheet`.

Band thresholds (single source of truth in `MerianConfig`):

| Band label | Color | Score range |
|---|---|---|
| Strong match | Green | ≥ 90% (`confidenceStrongThreshold`) |
| Possible match | Orange | 70% – 89% (`confidencePossibleThreshold` – `confidenceStrongThreshold`) |
| Weak match | Gray | Below 70% |

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items using the same `MerianConfig` constants so the displayed percentage ranges are always in sync with the badge logic.

`ConfidenceExplanationSheet` opens as a bottom sheet from the badge tap. It contains `ConfidenceHeader`, `ConfidenceSpectrum`, `AIMistakesBanner`, and `ProTips` (which conditionally shows a location permission prompt when GPS access is not granted).

`blur_score` is populated from live inference only (`SpeciesData.blurScore` maps to `EdgeResponse.blur_score`). It is `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`.

---

## Wikipedia Enrichment

Wikipedia data is loaded in two passes:

1. **Synchronous with inference** (live scans): the Edge function fetches Wikipedia in `EdgeRuntime.waitUntil` and includes `wikipedia_extract` and `wikipedia_url` in the response. These populate immediately when the sheet opens.
2. **Retroactive hydration** (live scans where Wikipedia was missing, and all historical scans): `InferenceEngine.asynchronouslyFetchWikipediaAndHydrate` fires a secondary `GET` to `en.wikipedia.org/api/rest_v1/page/summary/<scientific_name>` with a 4-second timeout. On success it mutates `speciesData.wikipediaExtract`, `speciesData.wikipediaUrl`, and `speciesData.referenceImageUrl` in-place on the `@MainActor`, triggering a UI update without reopening the sheet. The result is also persisted to `LocalScanRecord.wikipediaExtract` via `BackgroundDatabaseActor.updateScanWithWikipedia`.

---

## Celebration Banner (New Discovery)

On sheet `.onAppear`, `InsightSheetViewModel.evaluateVoiceOverAndCelebration` checks:

```swift
if data.isNewDiscovery && data.isBiological
    && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
    showCelebration = true
}
```

`showCelebration = true` triggers the `CelebrationBanner` confetti overlay. VoiceOver users receive an accessibility announcement instead — including a poisonous warning if `isPoisonous` is true.

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
