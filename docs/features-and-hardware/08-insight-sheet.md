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
| `NonBiologicalView` | Simplified result for non-biological subjects (objects, structures) |
| `InsightHeader` | Scrollable header with image carousel, species name, description, badges |
| `ImagesCarousel` | Horizontally scrolling image strip combining live captures + historic paths + reference images |
| `ConfidenceSpectrum` | Visual confidence spectrum with `SpectrumNode` labels |
| `ConfidenceExplanationSheet` | Sub-sheet explaining the confidence scale |
| `TaxonomyCard` | Collapsible card showing the full Linnaean tree |
| `AIReasoningCard` | Diagnostic comparison — primary rationale, lookalike name, key differentiators |
| `WikipediaCard` | Wikipedia extract with SafariServices deep link |
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

All images are loaded through `AsyncLocalImageView`, which handles RAM cache hits, request coalescing, and local-vs-remote routing transparently.

Invalid carousel URLs are purged from state via `InferenceEngine.dropInvalidCarouselImage(_:)`, which removes the entry from `validHistoricImagePaths` or from the comma-separated `speciesData.referenceImageUrl` without throwing index-out-of-bounds errors.

---

## Confidence Spectrum

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items, each describing a confidence band. The bands as defined in the component are:

| Node label | Score range |
|---|---|
| High confidence | 95% – 100% |
| Confident | 85% – 94% |
| Educated guess | 70% – 84% |
| Low confidence | Below 70% |

Tapping the spectrum (accessed via `ConfidenceExplanationSheet`) opens the sub-sheet which explains the AI's limitations and how environmental context affects accuracy.

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
