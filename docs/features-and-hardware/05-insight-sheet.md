# Insight Sheet

The Insight Sheet is the primary post-scan result screen, surfacing AI taxonomy, confidence data, ecological context, and media for every scan. It is presented as a sheet modal from `CameraRootView` when `CameraViewModel.activeSheet == .insight`.

---

## Architecture

| File | Role |
|---|---|
| `InsightSheetViewModel` | `@Observable @MainActor final class` — UI state, SwiftData ops, share/export |
| `InsightSheetView` | Root sheet view; owns `@State private var viewModel = InsightSheetViewModel()` |
| `InsightContentView` | Three-way content router. When `inferenceEngine.isProcessing && speciesData == nil` shows `AnalyzingContentView` (analyzing mode). Otherwise routes to `BiologicalView` or `NonBiologicalView` based on `speciesData.isBiological`. The switch is animated with `.easeInOut(duration: 0.35)` keyed on `isProcessing`. |
| `AnalyzingContentView` | Shown inside `InsightSheetView` while `inferenceEngine.isProcessing == true` and `speciesData == nil`. Renders three layers: (1) `ConfidenceBadge` in analyzing mode — the rotating `scanningPhaseText` phrase appears on a transparent capsule with a left-to-right `RevealText` sweep, `sparkles.2` icon, and `Color.primary` styling; each phrase is appended with `...` automatically; (2) `VisionStreamingParagraph` — streams `inferenceEngine.visionAnalysisText` character-by-character as the multi-pass Apple Vision pipeline completes each pass, using `.contentTransition(.opacity)` for a fluid reveal; (3) `ScanInformationCard` for eager telemetry — map, time, weather, and altitude are visible immediately while Gemini is still in-flight. Transitions out via `.easeInOut(duration: 0.35)` keyed on `isProcessing`. |
| `BiologicalView` | Full biological result: taxonomy, ecology badges, confidence, Wikipedia, lookalike diagnostic. Cards enter with a hardware-gated staggered animation via `CardEntranceModifier` (indices 0–9). |
| `NonBiologicalView` | Simplified result for non-biological subjects (objects, structures); renders a name/description card followed by a `ScanInformationCard` |
| `InsightHeader` | Scrollable header with species name, description, `ConfidenceBadge`, and conditionally the `ModelTierBadge` pill if the confidence score is a "Possible match". Automatically deduplicates its subtitle (scientific name) if it exactly matches the primary title string. Passes `userIdentificationOverride` and `userConfirmedIdentification` from `speciesData` down to `ConfidenceBadge`. Accepts an optional `visionTransitionText: String?` parameter: when non-nil, the paragraph slot renders the captured Apple Vision analysis text first, then cross-fades to Gemini `aiReasoning` after 700 ms via an `.easeInOut(0.45)` opacity transition. The species title is hidden initially and springs into view (`opacity 0→1`, `y+10→0`) on `.onAppear` with a 150 ms delay; a `triggerLightImpact(intensity: 0.5)` fires at title entrance and a `triggerSelectionPulse()` fires at the paragraph cross-fade moment. |
| `ImagesCarousel` | Horizontally scrolling image strip combining live captures + historic paths + reference images. When `totalImages == 0` (e.g. debug/analyze-only state), renders a `globe.americas.fill` placeholder on a black background. Pagination dots are hidden while `inferenceEngine.isProcessing == true` and slide up from the bottom edge via a combined `.opacity + .move` transition when processing finishes. |
| `ConfidenceBadge` | Tappable liquid-glass capsule showing the AI's confidence band (Strong / Possible / Weak) with a shimmering glare animation; opens `ConfidenceExplanationSheet` on tap. When `isFlagged` is `true`, shows "Under Review" (orange, `flag.fill`). When `userIdentificationOverride` is non-nil, shows "Your ID" (indigo, `person.fill.checkmark`). When `userConfirmedIdentification` is `true`, shows "Confirmed" (green, `checkmark.seal.fill`). **Analyzing mode** (`analyzingPhrase != nil`): background glass layers collapse to transparent, icon switches to `sparkles.2`, text uses `Color.primary` on a minimal capsule border — tap is suppressed. Each phrase change triggers a left-to-right gradient mask sweep via the internal `RevealText` view and the capsule width springs to fit the new string length. Phrases are auto-suffixed with `...` if not already ending with one. |
| `ConfidenceSpectrum` | Visual confidence spectrum with `SpectrumNode` labels; band thresholds derived from `MerianConfig` |
| `ConfidenceExplanationSheet` | Sub-sheet explaining the confidence scale, AI limitations, and tips for improving scan accuracy. When an override, confirmed, or flagged state is active, renders bespoke explanation cards (`OverriddenView`, `ConfirmedView`, `UnderReviewView`) at the top of the modal payload that allow the user to undo or change their review. Contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`, `AIMistakesBanner`, and `ProTips`. The `ProTips` component evaluates `RevenueCatManager.shared.isProActive` to conditionally render a premium upgrade trigger that opens `PaywallView` for free-tier users. |
| `ModelInfoSection` | Informational card inside `ConfidenceExplanationSheet` showing which Merian AI tier processed the scan. Standard tier (`inferenceTier == nil` or `"flash"`) renders a blue `cpu` icon with a gray "Standard" capsule badge. Pro tier (`inferenceTier == "pro"`) renders an indigo `sparkles` icon with an indigo "Pro" capsule badge and a "Powered by Gemini 2.5 Pro" footnote. Positioned between `ConfidenceSpectrum` and `AIMistakesBanner`. |
| `CandidatesCard` | Identification candidates card with a multi-state approve/deny and moderation UX. Shown when `speciesData.candidates` has ≥ 2 entries **or** when a review state (override/confirmed/flagged) is already set. Gated in `BiologicalView` via `candidates.count >= 2 || hasReviewState`. |
| `TaxonomyCard` | Collapsible card showing the full Linnaean tree |
| `SimilarSpeciesGallery` | Horizontally scrolling carousel of lookalikes sourced from `speciesData.similarSpecies`. Each `SimilarSpeciesCard` renders `referenceImageUrl` via `AsyncLocalImageView` when available, or asynchronously falls back to `SimilarSpeciesImageFetcher` (Wikipedia → GBIF waterfall). Image load failures never remove a card — on failure the card falls back to a leaf-icon placeholder so species names remain visible. Cards are only excluded from `validEntries` when their `scientificName` is blank. |
| `OverviewCard` | Structural card rendering dynamic biological KeyValueRow metrics (e.g., size, life stage, interactions, invasive species status) followed by an 8-line truncated Wikipedia extract and a built-in Safari "Learn more" button. |
| `ScanInformationCard` | Spatiotemporal context card: location, elevation, zoom, weather, date/time, and a MapKit snapshot |
| `GBIFHeatmapMapView` | SwiftUI `View` that composites two images to render a full-world GBIF occurrence heatmap natively. (1) A static `WorldMapBase` custom Mapbox topography background image, entirely eliminating MapKit CPU overhead. (2) The GBIF density zoom-0 tile (`/0/0/0@2x.png`) — a single 512 px PNG covering the entire world in Web Mercator — is fetched and drawn on top. Both images perfectly align their projection/extent. Features a custom `UIViewRepresentable` bridge (`PinchPanOverlay`) which unlocks elastic 2-finger pinch and pan exploration. This gesture controller safely locks down the encompassing parent `ScrollView` and engages `.interactiveDismissDisabled` on the bottom sheet to prevent SwiftUI swipe cancellation conflicts during map manipulation. |
| `HabitatAndDistributionCard` | Habitat and distribution card: encyclopedic habitat text. Has three states: (1) **Loaded** — habitat text; (2) **Loading** — shimmer skeleton shown while `inferenceEngine.isEnrichmentLoading` is `true`; (3) **Retry** — data missing, tap to re-trigger `fetchAndApplyEnrichment`. |
| `ToxicityBanner` | Glassmorphic hazard warning banner shown when `insightData.hazardType != "none"`. Implements a premium liquid-glass design using `.regularMaterial` and dynamic tinting (`.red` for severe threats like venomous/poisonous, `.yellow` for allergens/irritants), explicitly constrained using `maxWidth: .infinity` full-bleed bounds. Displays hazard-specific copy. |
| `ConservationBanner` | IUCN Red List status banner |
| `CelebrationBanner` | "New Discovery" confetti overlay |

---

## Data Source

`InsightSheetView` reads everything from `InferenceEngine.shared.speciesData` (a `SpeciesData` struct). It does NOT own a copy of the data — it observes the engine directly via `@Environment(InferenceEngine.self)`.

`InsightSheetViewModel` holds a reference to the `InferenceEngine` and exposes computed properties:

```swift
var headerTitle: String { 
    // Falls back to `scientificName` if `commonName` is empty, avoiding capitalization 
    // rules that corrupt scientific taxonomy casing, and suppressing subtitle duplication.
}
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

When `InferenceEngine.load(from:)` loads a `LocalScanRecord` that is missing `habitatDescription`, `gbifTaxonKey`, or `lookalikesData`, it automatically fires `fetchAndApplyEnrichment`. This aggressively gap-fills enrichment for older scans (even those that already have flat `similarSpecies` string arrays) to ensure they retrieve rich image and common name JSON payloads from the V27 pipeline.

### States

| State | Trigger | Rendered |
|---|---|---|
| **Loaded** | `habitatDescription != nil` | Habitat text |
| **Loading** | `inferenceEngine.isEnrichmentLoading == true` | Shimmer skeleton (3 text lines) |
| **Retry** | No data, not loading | "Retry" button → calls `inferenceEngine.fetchAndApplyEnrichment` |

### Similar Species Rendering

`similar_species` data is rendered by `SimilarSpeciesGallery` inside `BiologicalView` sequentially. The gallery is explicitly treated as informational and unconditionally renders as "SIMILAR SPECIES". (Previous dynamic confidence-based gating has been removed to prioritize objective reference availability).

**Mathematical Baseline Constraints**: To prevent Apple's SwiftUI Layout Engine from allowing extreme intrinsic image aspect ratios (e.g., highly vertical photos) from stretching the `maxHeight` boundaries and destroying the symmetric masonry of the horizontal scrolling row, `SimilarSpeciesCard` enforces absolute mathematical geometry. The overall card bounds are strictly locked to `240` points. The bottom text compartment allocates `60` points (`48` text space + `12` padding) to comfortably fit a 2-line `.subheadline` Common Name and a 1-line `.caption` Scientific Name. The topmost image compartment is definitively clamped to `160` points. 

Each `SimilarSpeciesCard` receives a `SimilarSpeciesEntry`. When `referenceImageUrl` is non-nil, the card renders it via `AsyncLocalImageView`; if the URL fails, local `@State var remoteImageFailed` flips to `true` and the card shows the leaf-icon placeholder instead. When `referenceImageUrl` is nil, a `SimilarSpeciesImageFetcher` Wikipedia/GBIF waterfall runs in a `.task`. In all failure cases the card stays in the gallery — it is never removed. The only exclusion rule is a blank `scientificName` (truly invalid server data), filtered in `validEntries`.

---

## Identification Candidates

When the AI's confidence falls below the tier-specific `diagnosticTrigger` threshold (`0.88` for Free/Flash, `0.80` for Pro), Gemini is instructed to emit up to 2 alternative species it genuinely considered alongside the primary identification. These are stored on the scan and displayed as a `CandidatesCard` in `BiologicalView`.

### Data Flow

1. **Gemini schema** (`supabase/functions/identify/schema.ts`): The `merianResponseSchema` includes a `candidates` array field. The system instruction tells the model to only populate it when genuinely uncertain between species — not as a reflexive "alternatives" list. Each entry is `{ scientific_name, confidence_score }`.
2. **Server-side strip** (`supabase/functions/identify/index.ts`): After Gemini returns, `index.ts` computes `diagnosticTrigger = userTier === "pro" ? 0.80 : 0.88`. If `confidence_score >= diagnosticTrigger`, the `candidates` array is cleared to `null` before the response is sent to the client and before the `insertScan` DB write. This is a defense-in-depth measure — even if the model emits candidates at high confidence, the server discards them.
3. **Supabase persistence** (`candidates` JSONB, migration `20260330000000_add_candidates_to_scans.sql`): Stored as a JSONB column on `public.scans`. `NULL` for high-confidence scans and all scans from before this migration. A partial index (`WHERE candidates IS NOT NULL`) keeps index overhead minimal since the vast majority of scans are high-confidence.
4. **SwiftData persistence** (`candidatesData: Data?`, `MerianSchemaV28`): The iOS client JSON-encodes `[IdentificationCandidate]` via `JSONEncoder` and stores the blob in `LocalScanRecord.candidatesData`. `InferenceEngine.load(from:)` decodes it back via `JSONDecoder` for historical scans.
5. **Historical sync** (`ScanRepository.syncHistoricalScansDown`): The `candidates` column is included in the `SELECT` query. A `CloudIdentificationCandidate` DTO (`{ scientific_name: String, confidence_score: Double }`) decodes the cloud JSONB. `ingestScans` re-encodes it to `IdentificationCandidate` and persists as `candidatesData`. The `updateExistingScans` backfill path checks `existing.candidatesData == nil` before writing, ensuring cloud candidates are retroactively available in pre-existing local records.

### Display Gate

`BiologicalView` renders `CandidatesCard` when the scan has ≥ 2 candidates **or** when a review state is already recorded (so the card persists after the user has acted):
```swift
let hasReviewState = inferenceEngine.speciesData?.userIdentificationOverride != nil
                  || inferenceEngine.speciesData?.userConfirmedIdentification == true
                  || inferenceEngine.speciesData?.isFlagged == true
if let primaryAIName = inferenceEngine.speciesData?.aiScientificName,
   let candidates = inferenceEngine.speciesData?.candidates,
   candidates.count >= 2 || hasReviewState {
    CandidatesCard(candidates: candidates,
                   aiScientificName: primaryAIName,
                   inferenceTier: speciesData.inferenceTier)
        .cardEntrance(index: 3)
}
```

The `candidates.count >= 2` guard prevents the card from showing for genuinely ambiguous single-alternative cases (rare, but possible). `CandidatesCard` internally computes the threshold via `MerianConfig.confidenceBands(forInferenceTier: inferenceTier).diagnosticTrigger` for display-only purposes (e.g., subtitle copy).

### Stage 2 — Approve / Deny UX

Users can confirm or override the AI's primary identification directly from `CandidatesCard`. The card manages a local `ReviewState` enum:

- **`.pending`**: Default state. Shows a "Was the AI correct?" prompt with a "Yes, that's right" button and a "Not sure / Show alternatives" toggle. Tapping "Yes" calls `InferenceEngine.confirmAIIdentification(modelContext:)`, setting `userConfirmedIdentification = true` locally and transitioning to `.confirmed`. Refusing all alternatives allows the user to flag the scan. For candidates with missing `commonName` strings (or common names identical to taxonomy), `SwipeableCandidateCard` securely elevates the `scientificName` to the primary title string un-capitalized.
- **`.confirmed`**: Replaces the prompt with nothing (the card hides its body). `ConfidenceBadge` transitions to "Confirmed" (green, `checkmark.seal.fill`). `ConfidenceExplanationSheet` shows a confirmation message.
- **`.overridden(to:)`**: Active after the user selects a candidate as their preferred identification. Renders an `OverriddenView` showing "Your identification" with the override name, "AI originally suggested X" footer, and an Undo button. `ConfidenceBadge` transitions to "Your ID" (indigo, `person.fill.checkmark`).
- **`.flagged`**: Active when the user flags the AI payload for moderation via `ReportInsightViewModel`. To guarantee 100% offline stability, `InferenceEngine.flagAIIdentification` natively mutates the in-memory `speciesData.isFlagged` property first, instantly hiding the `CandidatesCard` (via `EmptyView()`) and updating the `ConfidenceBadge` to "Under Review". `LocalScanRecord.isFlagged` is persisted immediately, allowing `OfflineQueueManager` to safely pipeline the flag to `public.scans` when the network recovers, fully bypassing potential foreign key constraint violations from synchronous edge functions.

**Override flow**: Selecting a candidate calls `InferenceEngine.applyIdentificationOverride(scientificName:modelContext:)`, which:
1. Mutates `speciesData.userIdentificationOverride` and `speciesData.scientificName` to the override name.
2. Persists `LocalScanRecord.userIdentificationOverride` via `BackgroundDatabaseActor.updateScanWithOverride`.
3. Syncs to `public.scans.user_identification_override` via a direct PostgREST PATCH (`InferenceEngine.syncIdentificationReviewToCloud`), guarded by `.eq("user_id", userId)`.
4. Fires `fetchAndPatchOverrideData(scientificName:scanId:modelContext:)` — queries `species_dictionary` for a cache hit and patches `speciesData` fields (common name, taxonomy, Wikipedia, etc.). On cache miss, calls `fetchAndApplyEnrichment` (which uses the already-mutated `speciesData.scientificName` as the lookup key).

**Data model**: Three fields on `LocalScanRecord` (all cloud-synced):
- `userIdentificationOverride: String?` — mirrors `public.scans.user_identification_override`.
- `userConfirmedIdentification: Bool` — mirrors `public.scans.user_confirmed_identification`. Both fields are sent in the same `ReviewSyncPayload` Encodable struct in `syncIdentificationReviewToCloud`.
- `isFlagged: Bool` — persisted to flag upstream manual moderation routines.

**Re-identification**: A user who has already acted on a review can always re-enter the selection flow:
- From `.overridden`: tap Undo → calls `resetIdentificationReview` → reverts to `.pending` with full candidate list visible.
- From `.confirmed`: tap "Change" in `ConfirmedView` → calls `resetIdentificationReview` → reverts to `.pending`.
- `resetIdentificationReview` clears both fields locally and in the cloud, reverts `speciesData.scientificName` to `aiScientificName`, and re-hydrates the AI's original species data from `species_dictionary`.

**Cross-device sync caveat**: `ScanRepository.updateExistingScans` propagates `userConfirmedIdentification` in the `true` direction only — a reset performed on device A (which syncs `user_confirmed_identification = false` to the cloud) will not propagate to device B during that device's next sync. Device B retains its local confirmed/overridden state. Full bidirectional review-state sync is deferred.

---

## Confidence Badge and Spectrum

`ConfidenceBadge` is a tappable liquid-glass capsule that shows the AI's confidence band for the current scan. The badge first checks identification review state before falling back to the confidence-band logic:

**Identification review states** (take precedence over confidence bands):
| State | Label | Color | Icon | Trigger |
|---|---|---|---|---|
| User flagged | "Under Review" | Orange | `flag.fill` | `isFlagged == true` |
| User override | "Your ID" | Indigo | `person.fill.checkmark` | `userIdentificationOverride != nil` |
| User confirmed | "Confirmed" | Green | `checkmark.seal.fill` | `userConfirmedIdentification == true` |

**Confidence bands** (when no review state is set — managed dynamically via `MerianConfig.confidenceBands(for: isPro)`):

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

The badge renders for override/confirmed states even when `confidenceScore == 0` (historical scans where confidence is unavailable).

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items using the same `MerianConfig` constants so the displayed percentage ranges are always in sync with the badge logic.

`ConfidenceExplanationSheet` opens as a bottom sheet from the badge tap. It contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`, `AIMistakesBanner`, and `ProTips` (which conditionally shows a location permission prompt when GPS access is not granted). `ModelInfoSection` sits between `ConfidenceSpectrum` and `AIMistakesBanner` and surfaces which Merian AI tier processed the scan — "Merian AI Standard" for free/Flash scans, "Merian AI Pro" for Pro scans, with a "Powered by Gemini 2.5 Pro" footnote on the Pro variant. When `userIdentificationOverride` is non-nil, the sheet replaces its normal content with an override-specific explanation showing the override species name, the original AI name (`aiScientificName` if provided), and undo instructions. When `userConfirmedIdentification == true` with no override, the sheet renders the normal confidence content — no confirmed-specific view is shown since the confidence explanation remains relevant and the `ConfirmedView` card already communicates the confirmed state inline.

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

`InsightSheetView` tracks whether the common name has scrolled past the viewport boundary to seamlessly morph the species name into the `TopToolbar`'s `.principal` display. Tracking an element's `maxY` inside a stretchy header `ScrollView` creates cyclical layout resolution hazards if `PreferenceKey` architectures are used (which inherently force sequential multi-pass frame layouts).

**Asynchronous Geometry Telemetry**: To permanently eradicate the *"Bound preference tried to update multiple times per frame"* runtime warning, `InsightHeader` abandons the `PreferenceKey` system entirely. It embeds a passive `Color.clear.onChange(of: geo.maxY, initial: true)` hook directly within its `GeometryReader`. This intercepts the positional coordinate strictly post-layout and transmits it instantly to `viewModel.evaluateScrollOffset` via an injected callback (`onScrollOffsetChange`), cleanly decoupling the telemetry from SwiftUI's layout-invalidation phase lock constraint.

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
