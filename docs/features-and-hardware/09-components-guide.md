# Shared Components and Primitives

Merian abstracts repetitive SwiftUI view structures into a dedicated components layer (`Core/UI/` and `Features/*/Components/`) to enforce DRY (Don't Repeat Yourself) principles and establish a unified aesthetic baseline.

## 1. Zero-State Handling: `EmptyStateView`
**Location**: `Features/Scans/Components/EmptyStateView.swift`

Historically, empty states in the Scans Library, Non-Biological Vault, and Collections were monolithic `VStack` geometries scattered across multiple view files. These were consolidated into a single, strongly-typed `EmptyStateView` component.
- **Dynamic Context**: It accepts dynamic messaging primitives (`title: String`, `message: String`, `systemImage: String`).
- **Layout Consistency**: Guarantees identical typography scaling and vertical padding ratios regardless of where the empty state is invoked.

## 2. Navigational Orchestration: `MainTabBar`
**Location**: `Core/UI/Components/MainTabBar.swift`

The central navigational routing anchor for the application, designed as a custom floating "Liquid Glass" capsule rather than relying on standard iOS `TabView` mechanics.
- **Glassmorphism**: Uses `.ultraThinMaterial` backgrounds bounded by a specular `.strokeBorder`.
- **Z-Index Layering**: Hovers persistently at the bottom of the `CaptureWorkspaceView` camera feed, allowing the viewfinder to bleed infinitely to the edges of the device screen.
- **Notification Badging**: Subscribes to `@AppStorage("hasUnseenScan")` to overlay an 8pt red continuous notification dot on the Scans icon, tracking silent inference completions without manual `@State` plumbing.

## 3. Archival Aesthetics: `ArchivedVisualsView`
**Location**: `Core/UI/Components/ArchivedVisualsView.swift`

Provides a standardized visual protocol for scans that have been archived or flagged. It encapsulates dark scrim overlays, watermark iconography, and desaturation modifiers, ensuring that any scan presented in a "historic" or "vaulted" context renders accurately within a grid matrix.

`ArchivedVisualsView` is no longer used as the generic fallback for every scan tile with no immediately loadable bitmap. `ScanThumbnail` now distinguishes between archived/missing visual assets and non-visual analyses that are waiting on a biological reference image. Those non-visual paths render a dedicated placeholder (`Reference pending`, `Reference unavailable`) keyed off the capture modality instead of implying that a photo once existed and was archived.

## 4. Scroll Physics: `FadingScrollView`
**Location**: `Core/UI/Components/FadingScrollView.swift`

A custom geometry wrapper used heavily within the `ProfileView` Contribution Heatmap (52-week grid).
- **Geometric Vignetting**: Uses `.clear` boundary gradients overlapping the vertical or horizontal edges of a `ScrollView`.
- **Tracking Physics**: Translates scroll offset physics into dynamic opacity bounds, preventing hard clipping of visual data structures (like the 11pt heat nodes) when they reach the geometric constraints of the device screen.

## 5. Destructive Safeties: `ScanDeletionDialogModifier`
**Location**: `Features/Scans/Modifiers/ScanDeletionDialogModifier.swift`

A global `.viewModifier` that intercepts `.contextMenu` or `Menu` delete interactions.
- Replaces isolated inline `.alert` or `.confirmationDialog` blocks to ensure identical warning dialogue verbiage across all views.
- Safely decouples the deletion `Task` from the view hierarchy, executing SwiftData `modelContext.delete()` constraints upstream of Cloudflare R2 binary deletions.

## 6. Confidence Badge: `ConfidenceBadge`
**Location**: `Features/Insights/Components/Confidence/ConfidenceBadge.swift`

A tappable liquid-glass capsule shown in `InsightHeader` that communicates the AI's confidence band — or the user's identification review decision — for a scan.
- **Review state priority**: Before evaluating confidence bands, the badge checks `isFlagged`, `userIdentificationOverride`, and `userConfirmedIdentification` passed from `InsightHeader`. If `isFlagged == true`, the badge switches to "Under Review" (orange, `flag.fill`). Else, if `userIdentificationOverride != nil`, the badge shows "Your ID" (indigo, `person.fill.checkmark`). If `userConfirmedIdentification == true`, it shows "Confirmed" (green, `checkmark.seal.fill`). All review states render regardless of `confidenceScore` (including zero for historical scans). Tapping any of these states opens the explanation sheet where users can undo their review decision.
- **Band logic**: When no review state is active, derives label, color, and icon dynamically from `confidenceScore` against `MerianConfig.confidenceBands(for: isPro)`. High constraints for Free tier (≥ 96%), relaxed bounds for Pro (≥ 85%). Three bands exist: Strong (green), Possible (orange), Weak (gray).
- **Liquid glass aesthetic**: Layered `ZStack` — `ultraThickMaterial` base, volumetric color tint, glossy inner rim gradient, ambient border, animated holographic glare sweep.
- **Shimmer animation**: An idle `.task` loop triggers a 3.5-second `easeOut` glare sweep every 4–10 seconds (random interval), creating a living feel without continuous CPU usage.
- **Analyzing mode** (`analyzingPhrase != nil`): All three glass fill layers collapse to `opacity(0)`, border switches to `Color.primary.opacity(0.2)`, icon changes to `sparkles.2`, and text uses `Color.primary` — creating a minimal transparent capsule that sits cleanly on the insight sheet background. Tapping is suppressed. Each phrase is auto-suffixed with `...` if not already ending with one.
- **`RevealText` subview**: Phrase labels are rendered by a private `RevealText` struct that preserves SwiftUI view identity across text changes (no `.id()` reset). On `onAppear` and each `onChange(of: text)`, `revealProgress` snaps to `0` (via a `disablesAnimations` transaction) then animates to `1` via `easeOut(duration: 0.6)`. The mask is a `LinearGradient`-filled `Rectangle` offset by `(revealProgress - 1.0) * maskWidth`, sweeping a soft gradient edge left-to-right. The parent `HStack` carries `.animation(.spring(response: 0.45, dampingFraction: 0.85), value: data.label)` so the capsule width interpolates smoothly as phrase length changes.
- **Sheet integration**: Tap opens `ConfidenceExplanationSheet`. The sheet reads `inferenceEngine.speciesData?.candidates` directly to discriminate between `AllCandidatesReviewedView` (`isFlagged && candidates.count >= 2`) and `UnderReviewView` (`isFlagged && candidates.count < 2`). Review-state cards are evaluated in priority order: `AllCandidatesReviewedView` → `UnderReviewView` → `OverriddenView` → `ConfirmedView`. When no review state is active, the normal confidence explanation is shown unobstructed. The `candidateCount: Int` prop that previously threaded `BiologicalView → InsightHeader → ConfidenceBadge → ConfidenceExplanationSheet` has been removed.

## 7. Confidence Spectrum: `ConfidenceSpectrum`
**Location**: `Features/Insights/Components/Confidence/ConfidenceSpectrum.swift`

A vertical timeline of `SpectrumNode` items inside `ConfidenceExplanationSheet`, explaining what each band means.
- **Threshold parity**: Band percentage strings are computed dynamically based on the current user's entitlement tier via `MerianConfig.confidenceBands(for: isPro)`. This ensures that the displayed ranges in the UI always match the live badge thresholds exactly.
- **Current bands**: Strong (≥ 96% Flash / ≥ 85% Pro), Possible (75–95% Flash / 65–84% Pro), Weak (below 75% Flash / below 65% Pro).

## 8. Overview: `OverviewCard`
**Location**: `Features/Insights/Components/Cards/OverviewCard.swift`

An informational liquid-glass component displaying AI-enriched encyclopedic extracts (`wikipediaOverview`), alongside a suite of dynamic biological `KeyValueRow` metrics, and a native Safari overlay button.
- **Structural Rendering**: Dynamically parses and lists available biological telemetry such as `estimatedSizeCm`, `lifeStage`, `reproductiveCondition`, and `ecologicalInteractions` while safely omitting empty values. Note: The `individualCount` metric is captured via backend Edge Functions for DWCA telemetry but intentionally omitted from this front-end display to conserve UI space.
- **Heuristic Filtering**: Enforces a strict ≥60 character length threshold on `wikipediaOverview`. When valid, the extract is capped at an 8-line truncation limit to avoid walls of text, terminating gracefully into a "Read more on Wikipedia" pill that relies on injected parent `$isSafariPresented` bindings.
- **Shared card chrome**: `OverviewCard` and `ExploreOverviewCard` keep separate data sourcing and visibility gates, but both render through `InsightCardHeader`, `WikipediaSummarySection`, and `WikipediaReadMoreButton` from `Features/Insights/Components/Cards/Card.swift`. Future Explore/Insights cards should reuse these presentational helpers instead of copying header typography or Wikipedia button styling.

## 9. Staggered Entrance: `CardEntranceModifier`
**Location**: `Core/UI/Modifiers/CardEntranceModifier.swift`

A `ViewModifier` that animates cards into view with a fade + 20pt upward slide on first appearance. Applied via the `.cardEntrance(index:)` view extension.

- **Two-gate system**: Motion is suppressed when either `HardwareOrchestrator.shared.isAnimationEnabled` is `false` (expedition mode or thermal state ≥ `.serious`) **or** the system `accessibilityReduceMotion` environment value is `true`. When either gate is closed, the card renders at full opacity instantly with no transform.
- **Stagger via `index`**: Each card receives a sequential integer index. Delay is computed as `Double(index) × 0.07s`, producing a natural cascading entrance without firing simultaneous layout passes.
- **One-shot guard**: The `hasAppeared: Bool` state flag prevents re-animation on SwiftUI view identity changes or sheet re-presentations.
- **Spring curve**: `.spring(response: 0.5, dampingFraction: 0.78)` — responsive enough to feel alive without overshooting on dense content stacks.
- **Current usage**: `BiologicalView` applies indices 0–9 across `InsightHeader` (0), `ToxicityBanner` (1), `ConservationBanner` (2), `CandidatesCard` (3), `SimilarSpeciesGallery` or its skeleton (4), `OverviewCard` (5), `HabitatAndDistributionCard` (6), `TaxonomyCard` (7), `ScanInformationCard` (8), and `UserTagsCard` (9), giving a ~700ms full-stack cascade at nominal hardware. `CandidatesCard` occupies index 3 unconditionally — when confidence is above the diagnostic threshold (card not shown), the stagger gap between `ConservationBanner` and `SimilarSpeciesGallery` simply increases by one step (~70ms). Both the live `SimilarSpeciesGallery` and its `Skeleton` placeholder share index 4 so the stagger position is stable regardless of enrichment state.

## 10. Circular Control Chrome: `CircularMaterialControlModifier`
**Location**: `Core/UI/Modifiers/IconButtonModifiers.swift`

A small presentation-only modifier for compact circular material controls. It owns only the shared frame, `Circle` material background, optional border, and optional enforced `ColorScheme`; callers still own icon choice, color, haptics, disabled state, accessibility labels, and action semantics.

- **Current usage**: `CaptureControlBar` audio/describe utility buttons, `FlashButton`, `PhotoLibraryButton`, `ToastBanner` dismiss affordances, `FieldNotesCard` dismiss, and the candidate-verification dismiss chips.
- **Abstraction boundary**: Do not use this modifier for controls with additional animated backgrounds, semantic fills, or domain-specific geometry. `DictationButton`, `CaptureButton`, avatars, feed action pills, and map menus remain isolated because their visual contracts are not identical.

## 11. Habitat Map: `HabitatAndDistributionCard`
**Location**: `Features/Insights/Components/Cards/HabitatAndDistributionCard.swift`

An edge-to-edge structural presentation component for the `gbifTaxonKey` density map and LLM `habitatDescription`.
- **Edge-to-Edge Maps**: Rebuts the `.card()` background modifier found elsewhere, leveraging `-16pt` negative horizontal padding on its root `VStack` to cancel default `BiologicalView` safe area margins, allowing the map frame to stretch across the full width of the interface.
- **Shared map/text chrome**: `HabitatAndDistributionCard` and `ExploreHabitatDistributionCard` both use `.gbifHeatmapCardChrome()` for the 260 pt rounded map frame, shadow, and border treatment, and `InsightScientificNameStyler.highlightedText(...)` for monospaced scientific-name highlighting. The cards still own their own loading/visibility behavior.
- **Loading continuity**: While habitat copy is still hydrating, the card keeps the same map chrome mounted and renders a compact pulsing text placeholder below the header. The retry loop stays local to `HabitatAndDistributionCard`; the shared chrome does not own any enrichment behavior.
- **Null Fallbacks**: Wraps the map in a `ZStack` so that if `isEnrichmentLoading` completes but the GBIF occurrence dataset yields no result (nil `gbifTaxonKey`), `GBIFHeatmapMapView` still renders its world-level base map snapshot and drops a distinct "No distribution data available" pill directly atop it.

## 12. Identification Candidates: `CandidatesCard`
**Location**: `Features/Insights/Components/Cards/CandidatesCard.swift`

A diagnostic card surfacing up to 2 alternative species the AI genuinely considered, with a full approve/deny UX for the user's identification review. Manages a local `ReviewState` enum: `.pending`, `.confirmed`, `.overridden(to:)`.

- **Display gate**: Rendered by `BiologicalView` when `candidates.count >= 2 || hasReviewState || hasLowConfidence` **and** `!allCandidatesRejected`. `hasReviewState` is true if `userIdentificationOverride != nil` or `userConfirmedIdentification == true`. `allCandidatesRejected` is `isFlagged == true && candidates.count >= 2` — this flag combination means the user exhausted all swipe alternatives, and the card is replaced by `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` instead.
- **Threshold sourcing**: `CandidatesCard` computes the threshold internally via `MerianConfig.confidenceBands(forInferenceTier: inferenceTier).diagnosticTrigger` (`0.99` for both Flash and Pro) for display copy, matching `FLASH_DIAGNOSTIC_TRIGGER` and `PRO_DIAGNOSTIC_TRIGGER` in `supabase/functions/_shared/identify/thresholds.ts` exactly. This value is intentionally above the strong-band thresholds (`FLASH_STRONG` = 0.95, `PRO_STRONG` = 0.85) so that every Possible, Weak, and Strong match scan carries candidates.
- **`.pending` state — PendingView**: Displays a high-end "Flayed Stack" teaser featuring a native `ZStack` of `FlayedCandidateThumbnail` views that asynchronously load species reference imagery. The view presents two full-width capsule action buttons beneath the stack: "Review alternatives" (triggers the dedicated `CandidateSwipeModal` via `.sheet`) and "Confirm species" (calls `InferenceEngine.confirmAIIdentification` natively). The legacy inline list expansion and localized "Not sure" toggles have been completely deprecated in favor of this dedicated swipe routing.
- **`.confirmed` state**: Emits `EmptyView()` — the card disappears. `ConfirmedView` in `ConfidenceExplanationSheet` handles the confirmed state display instead.
- **`.overridden(to:)` state**: Emits `EmptyView()` — the card disappears. `OverriddenView` in `ConfidenceExplanationSheet` handles the overridden state display instead.
- **`.flagged` state**: Always emits `EmptyView()`. For the "all candidates rejected" sub-path (`candidates.count >= 2`), `BiologicalView` gates the card out via `allCandidatesRejected` before `CandidatesCard` is even instantiated. The condensed `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` replaces it with a "Review again" button that re-opens `CandidateSwipeModal(candidates:aiScientificName:onFlagIssue:nil)` — the user can reconsider the alternatives and select one as an override without resetting the flagged state first.
- **Data origin**: Candidates are scan-specific — they model genuine per-image uncertainty rather than species-level similarity. They are stored as a `candidates JSONB` column in `public.scans` (not in `species_dictionary`) and as `LocalScanRecord.candidatesData: Data?` (`MerianSchemaV28`) on-device. The override is stored as `LocalScanRecord.userIdentificationOverride: String?` (`MerianSchemaV29`) locally and in `public.scans.user_identification_override` in the cloud.

## 13. Similar Species Gallery: `SimilarSpeciesGallery`
**Location**: `Features/Insights/Components/Cards/SimilarSpeciesGallery.swift`

A horizontally scrolling carousel of ecologically similar lookalike species, rendered in `BiologicalView` at card entrance index 4. Sourced from `speciesData.similarSpecies` (a `SimilarSpecies` struct with an `entries: [SimilarSpeciesEntry]` array), which is populated asynchronously by `fetchAndApplyEnrichment` and persisted to `LocalScanRecord.lookalikesData: Data?`.

- **Visibility gate**: Shown when `inferenceEngine.speciesData?.similarSpecies` is non-nil. While enrichment is in-flight (`inferenceEngine.isEnrichmentLoading == true`) and `similarSpecies` is still nil, `SimilarSpeciesGallery.Skeleton` renders in its place at the same index. The transition is animated via `.animation(.easeInOut, value: inferenceEngine.isEnrichmentLoading)`.
- **Entry filtering**: `validEntries` delegates to `SimilarSpecies.filteredEntries(...)`, removing blank scientific names, the active species, duplicate scientific names, and duplicate active common-name labels. Image load failure never removes a card.
- **Tap behavior**: The gallery accepts an optional `onSpeciesSelected` callback. The Insight sheet and Explore post detail page pass this callback to open `SpeciesDictionaryPageView` for the tapped lookalike; species dictionary usages omit the callback so their similar-species section stays read-only in V1.
- **Image loading**: Each `SimilarSpeciesCard` uses a two-tier strategy:
  1. **Rich path** (`referenceImageUrl != nil`): `AsyncLocalImageView` loads the pre-resolved join-table URL. If the URL fails (network error, simulator, expired CDN link), local `@State var remoteImageFailed` flips to `true` and the card falls through to the leaf-icon placeholder. The card stays visible.
  2. **Fallback path** (`referenceImageUrl == nil`): A `.task` spawns `SimilarSpeciesImageFetcher`, which runs a Wikipedia → GBIF image waterfall lookup. If both fail, the card shows the leaf-icon placeholder.
- **Fixed geometry**: Cards are locked to `width: 200, height: 260`. This prevents extreme image aspect ratios from breaking the horizontal row layout.
- **Label**: Always "Similar species" — no confidence-gated label switching.
- **Header chrome**: The live gallery and skeleton both use `InsightCardHeader`, matching the same title/icon treatment as Overview, Taxonomy, Scan, Tags, Field Notes, Did You Know, and Explore detail cards.
- **Skeleton**: `SimilarSpeciesGallery.Skeleton` renders three placeholder cards with a pulsing opacity loop (`easeInOut(duration: 1.0).repeatForever`).

## 14. Candidate Swipe Experience: `CandidateSwipeModal`
**Location**: `Features/Insights/Components/Cards/CandidateSwipe/` (Directory)

A high-end, Tinder-style gesture interface allowing users to rapidly review and identify AI alternative candidates. The `CandidateSwipeModal` has been fully decoupled from a monolith into a clean, modular folder hierarchy consisting of 10 isolated files:

- **`CandidateSwipeModal`**: The primary modal `.sheet` entry point. It manages the `stack` array natively and observes it via an `.onChange(of: stack.isEmpty)` interceptor, automatically executing `dismiss()` the moment the final card resolves (eliminating the need for an empty state).
- **`SwipeableCandidateCard`**: The core structural view for the individual species cards. Integrates `SimilarSpeciesImageFetcher` to asynchronously load up to 5 progressively loaded Wikipedia/GBIF visuals under a 3-stop vertical gradient that defaults to the `.images.first` thumb.
- **`CandidateImageExpandedView`**: Natively loads the `imageFetcher.images` array iteratively into a `.page` TabView carousel embedding the custom `ZoomableScrollView`.
- **`OriginalCaptureExpandedView`**: A dedicated single-image sheet container that provides pinch-to-zoom over the user’s original capture payload using `ZoomableScrollView`.
- **`OriginalCapturePiPView`**: A 58×76 pt picture-in-picture thumbnail embedded inside `SwipeableCandidateCard`. Tapping it triggers `OriginalCaptureExpandedView`.
- **`DistinguishingFeatureSheetView`**: Shows the full untruncated text of the `distinguishingFeature` that separates the candidate mathematically from the core ID inside a bottom sheet.
- **`ZoomableScrollView`**: Uses `UIViewRepresentable` and `UIScrollView` native delegate architecture spanning exactly 1× up to 4× zoom scales without UIKit delegate mutation conflicts.
- **`CandidateSwipeIndicator`**: An isolated view handling the complex 20% "deadzone" delay calculations that mask the `-90` degree radial progress stroke.
- **`CandidateActionBar`**: Replaces icon-only toolbars with explicit, text-labeled liquid glass `.ultraThickMaterial` buttons.
- **`GridSwipeableCell`**: The fallback wrapper component utilized when the user toggles the interface out of the Card Deck into the Grid layout.

## 15. Model Info Section: `ModelInfoSection`
**Location**: `Features/Insights/Components/Confidence/ModelInfoSection.swift`

An informational card rendered inside `ConfidenceExplanationSheet`, positioned between `ConfidenceSpectrum` and `AIMistakesBanner`. Communicates which Merian AI tier processed the scan — using Merian AI branding rather than raw model names to preserve the product abstraction layer and future-proof against model changes.

- **Standard tier** (`inferenceTier == nil` or `"flash"`): Renders a blue `cpu` icon inside a circular fill, "Merian AI" headline in `.callout.bold`, a gray "Standard" capsule badge, and a footnote describing the speed-optimised standard model.
- **Pro tier** (`inferenceTier == "pro"`): Renders an indigo `sparkles` icon, "Merian AI" headline, an indigo "Pro" capsule badge, a footnote describing the enhanced reasoning model, and a "Powered by Gemini 2.5 Pro" line in `.caption2` / `.tertiary` style as a trust signal for pro users.
- **Branding rationale**: All user-facing copy uses "Merian AI" rather than "Gemini" to maintain product consistency with `ConfidenceHeader` ("Merian's AI") and to decouple the UI from any specific underlying model version. The "Powered by Gemini" attribution is surfaced only on the Pro tier where model provenance is a meaningful quality signal.
- **Visual style**: Matches the full-section glass card aesthetic of the sheet — `Color(uiColor: .secondarySystemFill).opacity(0.5)` fill, `RoundedRectangle(cornerRadius: 32, style: .continuous)`, `.white.opacity(0.1)` border stroke, and 24 pt inner padding — identical to `ConfidenceSpectrum` and `ProTips`.

## 16. Image Carousel: `ImagesCarousel`
**Location**: `Features/Insights/Components/ImagesCarousel.swift`

The full-width image carousel at the top of the Insight Sheet, combining live captures, on-disk paths, and reference images into a horizontally scrolling full-screen strip with per-page pinch-to-zoom and pan.

`ImagesCarousel` has **no direct `InferenceEngine` dependency**. All data is injected as plain parameters, making the component reusable across both the live camera pipeline and the offline queued-scan path:

| Parameter | Type | Source |
|---|---|---|
| `scanId` | `String?` | `viewModel.persistentScanId` — prefers `queuedScan.id`, then `activeLocalRecord?.id`, then `inferenceEngine.speciesData?.scanId` |
| `refUrls` | `[String]` | `viewModel.refUrls` |
| `activeMedia` | `ActiveScanMedia` | `viewModel.resolvedMedia(for:)` — queued scans seed this from `QueuedScanContext.capturedMediaSnapshot`, while completed scans hydrate it from `record.capturedMediaSnapshot` |
| `totalImages` | `Int` | `viewModel.totalImages` |
| `isProcessing` | `Bool` | `viewModel.isProcessing` |
| `onImageFailure` | `(String) -> Void` | Closure injected by `InsightContentView`; no-op when `queuedScan != nil` (guard prevents engine call) |

- **`NativePageCarousel`**: A private `UIViewControllerRepresentable` wrapping `UIPageViewController`. `Coordinator.controllers: [ZoomPageViewController]` is populated eagerly so `AsyncLocalImageView.task` fires for all pages immediately — images load in the background before the user swipes to them. `UIPageViewController`'s internal `UIScrollView` defers to the sheet's pan gesture without manual workarounds (unlike `TabView(.page)`).
- **`ZoomPageViewController`**: Each page controller. Embeds its SwiftUI content (`AsyncLocalImageView` or `LiveCapturePageView`) inside a `ZoomScrollView`. Exposes `rootView: AnyView` as a computed property proxying into the inner `UIHostingController`, so `updateUIViewController`'s existing `controller.rootView = pages[i]` state-push pattern works without modification.
- **`ZoomScrollView`**: A `UIScrollView` subclass (`minimumZoomScale: 1.0`, `maximumZoomScale: 4.0`) that overrides `gestureRecognizerShouldBegin(_:)` to suppress its `panGestureRecognizer` when `zoomScale ≤ minimumZoomScale + 0.01`. This is the **only safe interception point** — replacing `panGestureRecognizer.delegate` directly throws `NSInvalidArgumentException` at runtime because UIKit requires the scroll view to remain its own pan delegate. At 1× UIPageViewController's swipe wins; above 1× the inner scroll view handles panning.
- **Snap-back**: `scrollViewDidEndZooming` (pinch release) and `scrollViewDidEndDragging` (drag release while zoomed) both call `snapBackToIdentity`: pending deceleration is cancelled first, then `UIView.animate(usingSpringWithDamping: 0.72)` restores `zoomScale → 1.0` and `contentOffset → .zero` simultaneously.
- **Async page growth**: `updateUIViewController` handles the user-media page model resolving asynchronously after `makeCoordinator`. New controllers are appended and `UIPageViewController.dataSource` is nil-reset to force neighbor re-queries.
- **Image failure handling**: `handleImageFailure(identifier:)` calls the injected `onImageFailure` closure and adjusts `selectedIndex`. `InsightContentView` passes `{ path in inferenceEngine.dropInvalidCarouselImage(path) }` for the live path; the queued-scan path passes a no-op. `updateUIViewController` trims the controller pool and navigates away with `.reverse` if the displayed page was removed.
- **`LiveCapturePageView`**: Asynchronously downsamples live capture `Data` in `DetachedWork.value(category: .imagePreparation)` and commits only the final `UIImage` to `@State`. It remains backed by `NSCache<NSNumber, UIImage>` keyed by `data.hashValue`, but ImageIO decode no longer runs from `body` layout evaluation.

## 17. Analyzing Content View: `AnalyzingContentView`
**Location**: `Features/Insights/Views/Content/AnalyzingContentView.swift`

The analyzing state rendered inside `InsightSheetView` when `viewModel.contentMode == .analyzing`. `contentMode` is `.analyzing` while `InferenceEngine.isProcessing == true`, `speciesData == nil`, **or** a `queuedContext` is set. The insight sheet opens immediately on scan submission — no fullscreen overlay is used. When `contentMode` transitions away from `.analyzing`, the view cross-fades out via `.easeInOut(duration: 0.35)` and `BiologicalView` or `NonBiologicalView` fades in. `InsightContentView` switches on `viewModel.contentMode` — not `inferenceEngine.isProcessing` directly — keeping the routing extensible without modifying the view.

`AnalyzingContentView` accepts an optional `queuedContext: QueuedScanContext? = nil` value-type parameter (**not** a live `OfflineQueuedScan @Model` reference). This is essential for crash safety: `LazyVGrid` accesses view properties lazily, and after `context.delete(scan)` fires during sheet dismissal, accessing any unfaulted `@Model` attribute causes a fatal "backing data detached from context" error. The `QueuedScanContext` value type copies all needed data at fetch time — before any deletion — so `AnalyzingContentView` can render safely regardless of the underlying object's lifecycle. Two distinct paths:

- **Live scan path** (`queuedContext == nil`): The `analyzingPhrase` computed property returns `inferenceEngine.scanningPhaseText` (the engine's rotating phase label). `ScanInformationCard` reads telemetry from `InferenceEngine` state directly.
- **Queued-scan path** (`queuedContext != nil`): `analyzingPhrase` derives from `OfflineQueueManager.isOnline` and `OfflineQueueManager.isSyncing` — "Waiting for connection" when offline; "Uploading..." when syncing; "Processing..." otherwise. Manager-level flags are used rather than per-scan `queueState` to avoid any live `@Model` access on a potentially deleted object. `ScanInformationCard` is populated from `QueuedScanContext` value fields (`timestamp`, `locationName`, `weatherTemperatureF`, `weatherCondition`, `gpsElevation`, `gpsLatitude`, `gpsLongitude`) with live engine values as `??` fallbacks, ensuring the telemetry card is always meaningful even before the scan reaches the server.

- **Confidence Badge slot**: Renders `ConfidenceBadge` with `analyzingPhrase: analyzingPhrase`. The badge operates in analyzing mode — transparent capsule, `sparkles.2` icon, `Color.primary` text — and cycles through phrase changes with a left-to-right `RevealText` sweep on each change.
- **`DidYouKnowCard`**: A rotating biology fact card inserted between the badge and the telemetry card. Backed by `FactManager`, which loads a shuffled deck of 70+ facts from `FactLibrary` upon initialization and stores the user's `currentPosition` in `AppStorage` to prevent repeats across app sessions. Re-initialization overhead is mitigated by deferring parsing logic out of the main constructor via an asynchronous `prepareIfNeeded` background invocation inside `.task()`. Auto-advances every 8.5 seconds using a strict iOS 16 `Clock` `.task(id: factManager.currentIndex)` binding—which elegantly cancels and restarts the active countdown upon any horizontal tapped or drag gestures for manual left/right navigation (`advance()` / `retreat()`). The card body uses an invisible `Text` pre-seeded with the longest fact (`FactLibrary.longestFact`) as a height anchor. Footer layout features an 8x8 dot pagination strip matched to a monospaced `#CATEGORY` string.
- **Eager telemetry via `ScanInformationCard`**: The scan's map, timestamp, weather, and altitude are rendered immediately regardless of whether the scan is live or queued.
- **No internal spacer**: `AnalyzingContentView` intentionally omits a trailing `Spacer` — `InsightContentView.contentCards` provides the universal `Spacer(minLength: 40)` outside the routing block, preventing double-spacing.

## 18. Drag-to-Confirm Pill: `SlideToConfirm`
**Location**: `Core/UI/Components/SlideToConfirm.swift`

A pill-shaped drag-to-confirm control that replicates the iPhone unlock gesture, used in `CandidateVerificationView` and `CandidateAlternativesView` to gate identification confirmations behind intentional gesture input.

- **Drag mechanics**: A circle thumb slides from the left edge to the right within a capsule-shaped track. At ≥88% travel, `onConfirm` fires automatically. The track fills progressively behind the thumb as drag progresses. The label fades out as the thumb advances (opacity multiplier `1.0 - progress * 2.5`).
- **Snap-back**: Releasing before the 88% threshold springs the thumb back via `.spring(response: 0.45, dampingFraction: 0.72)` with a `triggerLightImpact()` haptic.
- **Completion state**: On trigger, the thumb snaps to full width with `.spring(response: 0.28, dampingFraction: 0.82)`, chevrons are replaced by a checkmark, and `onConfirm` is called after a 380 ms delay so the user sees the completed state before the view transitions.
- **Haptics**: `triggerSuccessPulse()` on threshold reached; `triggerLightImpact()` on snap-back.
- **Label**: Accepts dynamically injected strings (e.g. `"Confirm \(viewModel.resolvedHeaderTitle)"`). To handle long scientific names without breaking the UI pill geometry on single lines, the `<Text>` label aggressively shrinks typography via `.minimumScaleFactor(0.6)` before resorting to truncation.
- **Disabled**: Once `isCompleted = true`, the component ignores further drag input.
