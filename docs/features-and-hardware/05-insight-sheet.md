# Insight Sheet

The Insight Sheet is the primary post-scan result screen, surfacing AI taxonomy, confidence data, ecological context, and media for every scan. It is presented as a sheet modal from `CaptureWorkspaceView` when `CaptureWorkspaceViewModel.activeSheet == .insight`.

---

## Architecture

| File | Role |
|---|---|
| `Shell/ViewModels/InsightSheetViewModel.swift` + product-area extensions | `@Observable @MainActor final class` — the root file owns stored state, init/reset, and `UIState`. Extensions live beside their owners: shell display/lifecycle/record lookup in `Shell/ViewModels/`, field notes in `FieldNotes/ViewModels/`, Explore sharing in `Sharing/ViewModels/`, media export in `Media/Utilities/`, and name preferences in `Content/NamePreferences/ViewModels/`, while preserving the scan-ID/snapshot safety boundary. |
| `InsightSheetView` | Root sheet view. Accepts an optional `queuedScan: QueuedScanContext? = nil` value-type parameter (not an `OfflineQueuedScan @Model` reference — see §Queued Scan Value-Type Pattern). Uses a **custom `init`** to seed `_viewModel` via `State(initialValue: InsightSheetViewModel(queuedContext: queuedScan))` — this ensures the view model's `queuedContext` is set at construction time, before SwiftUI evaluates any body. (Relying on `onAppear` alone was insufficient: `.sheet(isPresented:)` pre-evaluates the body with `scanToManage = nil`, setting `@State` once at that point; later re-evaluations with a non-nil `queuedScan` do not re-run `State(initialValue:)`.) An `onChange(of: queuedScan)` modifier nils `viewModel.queuedContext` when the queued scan is cleared from outside the sheet (e.g., `LibraryView` sets `scanToManage = nil` after the scan completes), ensuring the `.analyzing` → results transition path is not blocked by a stale `queuedContext`. When non-nil, shows a dedicated trash `ToolbarItem` in place of the standard ellipsis menu, and branches the delete alert to call `offlineQueueManager.deleteQueuedScan(scanId:)` then `dismiss()` instead of `eradicateCurrentScan`. On `onAppear` also sets `suppressInferenceBanners = true` and clears `hasUnseenScan`; on `onDisappear` clears `suppressInferenceBanners`. Detects queued-scan completion through the initial `.task(id: queuedScan?.id)` and `ScanLibraryEvents.libraryDidUpdatePublisher()`; `attemptQueuedCompletionHandoff` retries up to 8 × 350 ms for the new `LocalScanRecord` before handing off to `inferenceEngine.load(from:)` (see §Queued Scan Completion Transition). |
| `Shell/Views/InsightSheetView+Toolbar.swift` | Keeps toolbar assembly out of the root sheet body. It wires queued-scan trash handling, collection actions, report/reanalyze/review/confirm actions, and bottom-toolbar visibility using view-model capability flags and record snapshots. |
| `Shell/Modifiers/EmbeddedInsightNavigationModifiers.swift` | Hosts the feature-local back-swipe, navigation swipe enabler, and species-dictionary destination modifier used by embedded Insight navigation stacks. |
| `Shell/Models/InsightPresentation.swift` | Defines `InsightPresentationStyle` and `ScanInsightRoute`, the value-only presentation/navigation surface used across Insight, Explore, and Species Dictionary links. |
| `Toolbars/Models/InsightToolbarRecordSnapshot.swift` | Captures the toolbar's value snapshot of a `LocalScanRecord` before modal/share/delete boundaries so UI work does not retain a deleted SwiftData model. |
| `InsightContentView` | Four-way content router. Switches on `viewModel.contentMode` (`.analyzing` / `.queued` / `.nonBiological` / `.biological`) — routing logic lives entirely in the viewModel rather than being duplicated in the view. Shows `AnalyzingContentView` when `contentMode == .analyzing`, `QueuedContentView` when `contentMode == .queued`. Routes to `BiologicalView` or `NonBiologicalView` for the other two cases. The switch is animated with `.easeInOut(duration: 0.35)` keyed on `viewModel.contentMode`. **First-open `@State` timing guard**: `InsightContentView` holds `queuedScan` as a plain `var` stored property (not `@State`), passed directly from `InsightSheetView`. Because `@State` is initialized once at first SwiftUI evaluation — which happens during `.sheet(isPresented:)` pre-evaluation with `scanToManage = nil` — the view model's `queuedContext` may still be nil on the first render even though a queued scan is being opened. The plain `var` always reflects the current struct value. In the `.analyzing` case, if `queuedScan` is non-nil, the router renders `QueuedContentView(viewModel: viewModel, queuedContext: queuedScan)` immediately instead of `AnalyzingContentView`, closing the race and preventing the analyzing skeleton from flashing on first open of a queued scan. The `.queued` case also falls back to `queuedScan` if `viewModel.queuedContext` is not yet set: `if let ctx = viewModel.queuedContext ?? queuedScan`. | **Routing guarantee:** `CaptureWorkspaceViewModel.submitActiveScan()` calls `InferenceEngine.prepareForNewScan()` synchronously before opening the sheet — this sets `isProcessing = true` and `speciesData = nil` atomically, ensuring the router never briefly shows a previous scan's result view during the async telemetry-resolution gap. **`defer` state-reset guard:** The `defer` block inside `analyze()`'s `inferenceTask` captures `ownedScanId = scanId` before the task body. The reset (`isProcessing = false`, `activeScanId = nil`) only fires when `self.activeScanId == ownedScanId`, preventing a cancelled task's `defer` from overwriting a new scan's state that was set by a subsequent `prepareForNewScan()` + `analyze()` call racing before the cancellation propagated. **Background-completion path:** If the user backgrounds the app immediately after capture, the background URLSession pipeline can complete and commit the scan to the database while the live `InferenceEngine.analyze()` task is suspended. When the app returns to the foreground in this state, `processInferenceDownloadResult` detects the race (`engine.isProcessing == true && engine.activeScanId == scanId`) and hydrates `engine.speciesData` directly from the already-decoded `SpeciesData`, then cancels the live task and sets `isProcessing = false`. `InsightContentView` observes the change and exits "Analyzing..." mode immediately, preventing the live task from resuming and showing "Network timeout" for a scan already committed. |
| `AnalyzingContentView` | Shown inside `InsightSheetView` exclusively while `viewModel.contentMode == .analyzing` — i.e. a live camera capture is actively under edge resolution. Has no awareness of `OfflineQueueManager` or `QueuedScanContext`. `ConfidenceBadge` displays `inferenceEngine.scanningPhaseText` (rotating phase phrases). Renders three layers: (1) `ConfidenceBadge` in analyzing mode; (2) `DidYouKnowCard` — a rotating biology fact card giving users something interesting to read while processing. Backed by a `FactManager` singleton using `AppStorage` to maintain a shuffled deck of 70+ facts to prevent repeats. Automatically advances every 8.5 seconds relying on a strict SwiftUI `.task(id:)` reactive binding; (3) `ScanInformationCard` populated from live engine context (`activeLocationName`, `activeTemperatureF`, `activeWeatherCondition`, `activeElevation`, `activeLatitude`, `activeLongitude`). Transitions out via `.easeInOut(duration: 0.35)` keyed on `viewModel.contentMode`. |
| `QueuedContentView` | Shown inside `InsightSheetView` when `viewModel.contentMode == .queued` — i.e. the user is viewing an `OfflineQueuedScan` resting in the background-upload batch queue. Intentionally isolated from `AnalyzingContentView` so the UI clearly distinguishes a scan purposefully waiting in queue from one actively under edge resolution. Receives a `QueuedScanContext` value type (never a live `@Model` reference) plus `InsightSheetViewModel` for editable field notes. The `ConfidenceBadge` phrase (`badgePhrase`) and the large serif title (`displayTitle`) are always **semantically distinct** across all three states — the badge is a system-status phrase, the title is a noun phrase: when offline `badgePhrase = "No connection"` / `displayTitle = "Queued for upload"`; when `isSyncing`, `badgePhrase = "Uploading..."` / `displayTitle = "Syncing"`; otherwise `badgePhrase = "In queue"` / `displayTitle = "Queued for upload"`. This guarantees the badge and title never show identical copy simultaneously. Title transitions animate via `.contentTransition(.numericText())`. A helper text paragraph explains the background-upload sync pipeline to the user. The same `FieldNotesCard` used by completed biological insights appears while queued scans wait, and edits write through `FieldNotesRepository` to `OfflineQueuedScan.fieldNotes` so notes survive upload handoff. `ScanInformationCard` is populated from `QueuedScanContext` value fields (`timestamp`, `locationName`, `weatherTemperatureF`, `weatherCondition`, `gpsElevation`, `gpsLatitude`, `gpsLongitude`). Note: `isSyncing` is a manager-level flag, not per-scan — if another scan is uploading concurrently, the badge reflects that global state. |
| `BiologicalView` | Full biological result: taxonomy, ecology badges, confidence, Wikipedia, habitat/distribution, observation patterns, and lookalike diagnostic. Cards enter with a hardware-gated staggered animation via `CardEntranceModifier`. |
| `NonBiologicalView` | Simplified result for non-biological subjects (objects, structures); renders a name/description card followed by a `ScanInformationCard`. The header title resolves to the friendly display label `Non-biological` even when the stored fallback common name is `Unknown Subject` or `Not Applicable`. Local inference error placeholders such as `Network timeout` reuse this simple layout but hide the non-biological pill and retention notice because they are retry/offline states, not model classifications. |
| `InsightHeader` | Scrollable header with species name, description, `ConfidenceBadge`, and conditionally the `ModelTierBadge` pill if the confidence score is a "Possible match". For dog/cat scans with a displayable `SpeciesData.petIdentification`, the large headline uses the pet label while the subtitle remains the scientific name only; otherwise the header uses the normal common-name/scientific-name behavior. Automatically deduplicates its subtitle (scientific name) if it exactly matches the primary title string. Passes `userIdentificationOverride`, `userConfirmedIdentification`, `aiScientificName`, and the optional Ask the Community callback down to `ConfidenceBadge` (and transitively to `ConfidenceExplanationSheet`). Non-biological results display the stable title `Non-biological` instead of exposing unresolved taxonomy placeholders. Accepts an optional `visionTransitionText: String?` parameter: when non-nil, the paragraph slot renders the captured Apple Vision analysis text first, then cross-fades to Gemini `aiReasoning` after 700 ms via an `.easeInOut(0.45)` opacity transition. The species title is hidden initially and springs into view (`opacity 0→1`, `y+10→0`) on `.onAppear` with a 150 ms delay; a `triggerLightImpact(intensity: 0.5)` fires at title entrance and a `triggerSelectionPulse()` fires at the paragraph cross-fade moment. **Alternative names line**: when `alternativeCommonNames` is non-nil and non-empty, a footnote-sized "Also known as: X · Y · Z" line is rendered below the headline as a tappable `Button`; tapping calls `onAlternativeNamesTap` which sets `InsightSheetViewModel.isNamePickerPresented = true` to present `NamePickerSheet`. The common name title itself is also tappable when `alternativeCommonNames` are available — it calls the same `onAlternativeNamesTap` callback, so tapping the headline directly opens the same `NamePickerSheet` as tapping the "Also known as" footnote. |
| `NamePickerSheet` | Bottom sheet (`.medium` detent) presented when the user taps the "Also known as" line in `InsightHeader`. Renders a `NavigationStack` list of all known common names for the species (primary `commonName` + `alternativeCommonNames`, deduplicated) with a checkmark on the currently active name. Pet labels are intentionally excluded: selecting a name calls `InsightSheetViewModel.setPreferredCommonName(_:for:modelContext:)`, which writes through `SpeciesPreferredNameRepository` and fires a `toastMessage`. A "Use default name" row calls `clearPreferredCommonName(for:modelContext:)` to remove the override. |
| `ImagesCarousel` | Horizontally scrolling mixed-media strip combining live captures, persisted user media pages, and reference images. The user-media portion is sourced from `ActiveScanMedia`, which can contain images, videos, standalone audio clips, and descriptions in one stable ordered timeline. Image pages use `ZoomPageViewController`, video pages use inline AVPlayer playback, and audio/description pages use their matching mixed-media page type. Extracted video audio is inference context attached to the video item and does not render as a separate audio page. Tapping an image or video page opens `InsightFullscreenImageCarousel`, a read-only full-screen visual gallery/playback surface; audio, descriptions, and reference-loading placeholders stay out of the modal. When `totalImages == 0`, renders a `globe.americas.fill` placeholder on a black background. Pagination dots are shown whenever `totalImages > 1`, and page identity is stabilized across the queued/live/result handoff by keying off the persistent scan ID. |
| `ConfidenceBadge` | Tappable liquid-glass capsule showing the AI's confidence band (Strong / Possible / Weak) with a shimmering glare animation; opens `ConfidenceExplanationSheet` on tap. When `userIdentificationOverride` is non-nil, shows "Your ID" (indigo, `person.fill.checkmark`). When `userConfirmedIdentification` is `true`, shows "Confirmed" (green, `checkmark.seal.fill`). **Analyzing mode** (`analyzingPhrase != nil`): background glass layers collapse to transparent, icon switches to `sparkles.2`, text uses `Color.primary` on a minimal capsule border — tap is suppressed. Each phrase change triggers a left-to-right gradient mask sweep via the internal `RevealText` view and the capsule width springs to fit the new string length. Phrases are auto-suffixed with `...` if not already ending with one. |
| `ConfidenceSpectrum` | Visual confidence spectrum with `SpectrumNode` labels; band thresholds derived from `MerianConfig` |
| `ConfidenceExplanationSheet` | Sub-sheet explaining the confidence scale, AI limitations, and tips for improving scan accuracy. When an alternatives-exhausted, override, or confirmed state is active, renders bespoke explanation cards at the top of the modal payload that allow the user to undo, reset, review again, or ask the community for help. **Review-state cards (mutually exclusive):** `AllCandidatesReviewedView` (`alternativesExhausted == true`; user rejected all swipe-deck alternatives), `OverriddenView` (user selected an alternative species), and `ConfirmedView` (user confirmed the AI match). Contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`, `AIMistakesBanner`, and `ProTips`. The `ProTips` component evaluates `RevenueCatManager.shared.isProActive` to conditionally render a premium upgrade trigger that opens `PaywallView` for free-tier users. |
| `ModelInfoSection` | Informational card inside `ConfidenceExplanationSheet` showing which Merian AI tier processed the scan. Standard tier (`inferenceTier == nil` or `"flash"`) renders a blue `cpu` icon with a gray "Standard" capsule badge. Pro tier (`inferenceTier == "pro"`) renders an indigo `sparkles` icon with an indigo "Pro" capsule badge and a "Powered by Gemini 2.5 Pro" footnote. Positioned between `ConfidenceSpectrum` and `AIMistakesBanner`. |
| `CandidatesCard` | Identification candidates card with a multi-state approve/deny and Community handoff UX. Shown only with policy-visible candidates from `CandidateReviewVisibilityPolicy`, not raw `speciesData.candidates`. Hidden after confirmation, override, or alternatives exhaustion; when `alternativesExhausted == true`, `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` replaces the card with a condensed summary, Review again, and Ask the community affordances. |
| `TaxonomyCard` | Collapsible card showing the full Linnaean tree. Also reused by the Explore detail page when public taxonomy data is available. |
| `SimilarSpeciesGallery` | Horizontally scrolling carousel of lookalikes sourced from `speciesData.similarSpecies` in Insight and from public `similar_species` on Explore detail. Each `SimilarSpeciesCard` renders `referenceImageUrl` via `AsyncLocalImageView` when available, or asynchronously falls back to `SimilarSpeciesImageFetcher` (Wikipedia → GBIF waterfall). Image load failures never remove a card — on failure the card falls back to a leaf-icon placeholder so species names remain visible. Cards are excluded when their `scientificName` is blank, when they duplicate the active species scientific name, or when the same scientific name appears twice. If a lookalike shares the active species' common name, the gallery suppresses the duplicate common-name label and lets the scientific name carry the distinction. Insight, Explore detail, and Species Dictionary pass `routeForSpecies` builders so cards push `SpeciesDictionaryPageContentView` in the current sheet/navigation stack, preferring `speciesId` when present and falling back to scientific name. The card no longer renders relation rationale copy; it stays focused on image, common name, and scientific name. |
| `OverviewCard` | Structural card rendering dynamic biological metrics (e.g., size, life stage, sex with supporting cue/confidence, interactions, and conservation). Invasive status is grouped into a compact local summary: the primary `Invasive` / `Not invasive` value, an optional assessed-region and confidence detail line, and an optional `WHY MERIAN THINKS THIS` rationale note from the original AI assessment. The card then shows an 8-line truncated Wikipedia extract and a built-in Safari "Learn more" button when available. |
| `InsightChatSheet` | Bottom-sheet Field chat for completed biological, non-human insights with a stable scan id. The Insight bottom toolbar shows the chat entry for eligible scans; non-Pro users hit the existing paywall, while Pro/trial users first preflight the scan with `/check-scan-status` and only open the sheet when the current account owns the scan. Scans that fail this preflight are marked unavailable for that presentation, hidden from the toolbar, and surface a clear toast instead of launching into a chat 403. The toolbar entry keeps the native button label/chrome stable and uses a fixed, accessibility-hidden rainbow glow layer behind the button. The sheet renders the scan's single saved chat, AI-generated quick prompt chips with a local deterministic fallback, message history, and an anchored composer. `InsightChatViewModel` owns conversation loading, sending, offline read-only state, deterministic unavailable hiding, rate-limit/error copy, durable failed-send retry/edit state, duplicate-send `client_message_id` values, prompt loading/category tracking, answer feedback, and chat-to-notes summary draft loading; chat state stays out of `InsightSheetViewModel` except for presentation/action hooks. Safety refusals render as `Safe field guidance`, assistant replies expose only icon copy and inline feedback controls, and the sheet options menu owns thread-level feature feedback plus reviewed append-only chat summaries. Sending is online-only and talks to `/insight-chat`; prompt generation uses `/insight-chat` `action: "suggest_prompts"` after initial load and after successful assistant responses. The sheet never sends raw image bytes, cloud image URLs, internal scan IDs, exact GPS, or public Explore data. The Edge Function builds chat and prompt context from stored private scan/species text, including review/provenance state, observed traits, ecological annotations, invasive-status region/rationale/confidence, species group tags, and image/capture-quality metadata. |
| `ScanInformationCard` | Privacy-aware spatiotemporal context card. Reads `ProfileViewModel.defaultGeoprivacy`: `private` hides location/elevation/weather/map, `obscured` shows sanitized location plus rounded map region, and `open` may show exact owner-facing location context. |
| `GBIFHeatmapMapView` | SwiftUI `View` that composites two images to render a full-world GBIF occurrence heatmap natively. (1) A static `world-map-base` custom Mapbox topography background image, entirely eliminating MapKit CPU overhead. (2) The GBIF density zoom-0 tile (`/0/0/0@2x.png`) — a single 512 px PNG covering the entire world in Web Mercator — is fetched and drawn on top. Both images perfectly align their projection/extent. Features a custom `UIViewRepresentable` bridge (`PinchPanOverlay`) which unlocks elastic 2-finger pinch and pan exploration. This gesture controller safely locks down the encompassing parent `ScrollView` and engages `.interactiveDismissDisabled` on the bottom sheet to prevent SwiftUI swipe cancellation conflicts during map manipulation. The same map primitive is also reused by Explore's public habitat/distribution card on the post detail page. |
| `HabitatAndDistributionCard` | Habitat and distribution card: encyclopedic habitat text. Has three states: (1) **Loaded** — habitat text; (2) **Loading** — shimmer skeleton shown while `inferenceEngine.isEnrichmentLoading` is `true`; (3) **Retry** — data missing, tap to re-trigger `fetchAndApplyEnrichment`. Reads `habitatDescription` and `scientificName` directly from `inferenceEngine.speciesData` (not passed as parameters) so the card directly tracks `@Observable` changes on `speciesData` and re-renders the moment enrichment writes to it, independent of any parent view re-render timing. |
| `SpeciesObservationChartsCard` | Reusable Swift Charts card rendered after Habitat & Distribution for known biological species. `SpeciesObservationStatsViewModel` coordinates loading, `SpeciesObservationStatsDatabaseActor` fetches local SwiftData projections off the main actor, and `SpeciesObservationStatsReducer` computes on-device aggregates before combining them with cached global public iNaturalist stats from `/species-observation-stats`. Tabs are Seasonality, History, and Life Stage; per-scan sex is shown in `OverviewCard` instead. |
| `ToxicityBanner` | Glassmorphic hazard warning banner shown when `insightData.hazardType != "none"`. Implements a premium liquid-glass design using `.regularMaterial` and dynamic tinting (`.red` for severe threats like venomous/poisonous, `.yellow` for allergens/irritants), explicitly constrained using `maxWidth: .infinity` full-bleed bounds. Displays hazard-specific copy. |
| `ConservationBanner` | IUCN Red List status banner |
| `MilestoneToastBanner` / `MilestoneToastPresenter` | Shared bottom in-app milestone notification. Insight enqueues `New to Merian` only when the edge response marks the scan as a global species-dictionary contribution. Achievement unlocks reuse the same queue and banner styling from Profile/Settings. |

---

## Data Source

`InsightSheetView` reads everything from `InferenceEngine.shared.speciesData` (a `SpeciesData` struct). It does NOT own a copy of the data — it observes the engine directly via `@Environment(InferenceEngine.self)`.

`InsightSheetViewModel` holds a reference to the `InferenceEngine` and exposes computed properties:

`SpeciesData.isNewDiscovery` remains the local "new to this user" signal for
stats, persona, firefly progress, and achievement calculations. It no longer
drives a user-facing Insight celebration. `SpeciesData.isNewToMerianDictionary`
is the separate global dictionary contribution signal returned by the identify
Edge payload. On first sheet appearance,
`InsightSheetViewModel.evaluateVoiceOverAndCelebration` enqueues
`MilestoneToastPresenter.shared.enqueueNewToMerianMilestone()` once per
presentation when that flag is true for a valid biological subject. Error
placeholders created by local fallback handling have no scan ID, preserve their
sentence-case title such as `Network timeout`, and never show non-biological
collection or retention messaging.

```swift
var resolvedHeaderTitle: String {
    // Non-biological results → "Non-biological".
    // Displayable dog/cat petIdentification labels win the headline.
    // Otherwise user's preferred common name (SpeciesPreferredNameRepository)
    // → canonical DB commonName. Falls back to `scientificName` if `commonName`
    // is empty, avoiding capitalization rules that corrupt scientific taxonomy
    // casing, and suppressing subtitle duplication.
    if species.isBiological == false { return "Non-biological" }
    if let pet = species.petIdentification, pet.isDisplayable { return pet.label }
    if let preferred = preferredCommonName, !preferred.isEmpty { return preferred }
    // ... fallback to species.commonName / scientificName
}
var displayAlternativeCommonNames: [String]? {
    // Filters allNamesForPicker (which includes the canonical primary name alongside
    // alternativeCommonNames) to exclude the currently resolved headline (case-insensitive).
    // This means the default primary name reappears in the footnote when the user has
    // selected an alternative as their preferred headline — the picker always shows
    // all other available names relative to whatever is currently displayed as the title.
    // Nil when no alternatives exist after filtering.
}
var allNamesForPicker: [String] {
    // Full deduped list: [primaryCommonName] + alternativeCommonNames. Fed into NamePickerSheet.
}
var hazardType: String { inferenceEngine?.speciesData?.insightData.hazardType ?? "none" }
var isHazardous: Bool { hazardType != "none" }
var refUrls: [String] {
    // Returns [] when speciesData.isHumanSubject — blocks Wikipedia/GBIF reference
    // images for human subjects. totalImages derives from refUrls, so the carousel
    // page count drops automatically with no additional call sites to update.
    // Historical unresolved biological placeholders also suppress reference-loading
    // pages until they have a resolved biological identification.
}
var activeMedia: ActiveScanMedia {
    if queuedContext != nil { return cachedActiveMedia ?? ActiveScanMedia() }
    return inferenceEngine?.activeMedia ?? ActiveScanMedia()
}
var totalImages: Int {
    // Delegates to the unified media model, which already accounts for live media,
    // persisted user media, and reference-image loading state.
    return activeMedia.totalItems
}

// Processing state — mirrors InferenceEngine.isProcessing.
// Routing this through the viewModel means toolbar flags and contentMode
// all share one source of truth without each view needing its own engine read.
// When a queuedContext is set, always returns true — not for content routing (that
// is handled by .queued), but to keep the toolbar in its non-interactive state
// (suppresses the ellipsis menu and the bottom bar tools while a scan is queued).
var isProcessing: Bool {
    if queuedContext != nil { return true }
    return inferenceEngine?.isProcessing ?? false
}

// Toolbar capability flags — all short-circuit to false when queuedContext != nil
// (the queued-scan path exposes only a trash button; no review actions apply).
var isReviewLocked: Bool   { guard queuedContext == nil else { return false }; /* userConfirmedIdentification || userIdentificationOverride != nil */ }
var canReanalyze: Bool     { guard queuedContext == nil else { return false }; /* not review-locked, local path, no additional images */ }
var canReviewAlternatives: Bool { guard queuedContext == nil else { return false }; /* reviewAlternativeCandidates is non-empty */ }
var canConfirm: Bool       { guard queuedContext == nil else { return false }; /* reviewAlternativeCandidates is non-empty */ }
var canShareToExplore: Bool { /* false unless the active record has a resolved biological identification */ }
var canRequestCommunityIdentification: Bool { canShareToExplore && activeImageCount > 0 }

// Content routing — derived from queuedContext / isProcessing / speciesData.
// InsightContentView switches on this enum rather than duplicating the guard chain.
// queuedContext maps to .queued (its own dedicated view); engine isProcessing maps to .analyzing.
enum ContentMode: Equatable { case analyzing, queued, nonBiological, biological }
var contentMode: ContentMode {
    if queuedContext != nil { return .queued }
    // ... .analyzing when isProcessing; else .nonBiological / .biological
}
```

Historical unresolved biological placeholders (`Unknown Subject` / `Taxonomy Unavailable`) are treated as compatibility data, not valid identifications. They suppress visible AI confidence, reference-loading carousel pages, and Explore sharing until reanalysis produces a resolved biological result. The local programmatic share guard returns `Reanalyze this scan before sharing to Explore.` for those records.

**Name preference methods** (all routed through `SpeciesPreferredNameRepository`, keyed by scientific name):
- `loadPreferredCommonName(for:modelContext:)` — reads `UserSpeciesPreference` into `preferredCommonName`. If a legacy `SpeciesPreferredNameStore` key is encountered, the repository promotes that value into SwiftData and removes the legacy key only after the save succeeds; called from `InsightSheetView.task(id: scanId)` when a new species loads.
- `setPreferredCommonName(_:for:modelContext:)` — writes `UserSpeciesPreference`, clears any stale legacy key only after `modelContext.save()` succeeds, updates `preferredCommonName` in-memory (triggering `@Observable` recompute of `resolvedHeaderTitle`), and fires a `toastMessage`.
- `clearPreferredCommonName(for:modelContext:)` — deletes the SwiftData row, clears any stale legacy key after save, and nils `preferredCommonName`, reverting the headline to the canonical DB name.

`SpeciesPreferredNameRepository` intentionally remains separate from `AppSettings`: preferred names are per-species keyed data, not global UI state. `MerianApp` runs `migrateLegacyPreferences(modelContext:)` after SwiftData bootstraps, promoting all legacy `speciesPreferredName_*` keys and deleting them only after a successful database save. The repository then syncs SwiftData rows to Supabase `user_species_preferences`; clears are retained as pending local delete timestamps until a remote `deleted_at` tombstone is confirmed. Sync triggers from auth restore, foreground activation, and local edits are single-flight, so only one preferred-name cloud reconciliation is active at a time; mid-flight triggers record a trailing follow-up request so edits saved after the active sync's local fetch still flush before the coalesced task completes. Clean lifecycle/auth syncs skip when a successful sync completed in the last 60 seconds, while local edits force the sync path. `SpeciesPreferredNameStore.syncDiagnostics` records the latest attempt/success/status/message plus pushed/pulled counts for support. Explore feed, map, detail, comments, and share text resolve display names through an `ExploreFeedViewModel` cache hydrated from the SwiftData-backed repository using the current `ModelContext`. The network DTOs in `ExploreAPIModels` stay pure decode models and never read `UserDefaults` directly; the legacy `SpeciesPreferredNameStore` remains only as migration input, cloud-delete tombstone staging, diagnostics, and lazy fallback if a pre-migration key is discovered later.

Pet labels are not species preferences. They are scan-level metadata decoded
from `SpeciesData.petIdentification` / `LocalScanRecord.petIdentificationData`
and may change from scan to scan even when the scientific name is the same.

`InsightSheetView` also queries SwiftData directly via `@Query` for non-deleted `[ScanCollection]` rows (reverse-sorted by `createdAt`) to populate the collection management toolbar. Soft-deleted collections (`isDeleted == true`) are intentionally excluded so a collection that is pending remote deletion never reappears in the add-to-collection menu.

Explore share state in the bottom toolbar uses a two-step hydration path. `InsightSheetViewModel.fetchLocalRecord(for:modelContext:)` first restores `sharedExplorePostId` from the per-scan `UserDefaults` cache so the button can immediately render `View post` on same-device relaunch. `InsightSheetView.task(id: scanId)` then calls `/get-scan-explore-share-state` in the background and reconciles that authoritative server answer back into the same cache. The server response only reports a live Explore post when the post has saved public `explore_post_media`; media-less rows left by failed snapshot writes clear the local post cache instead of opening a phantom post. It also carries the saved post-level `location_sharing` for live posts, or the scan's current geoprivacy as the default for new shares, so the share/edit composer can hydrate Open, Obscured, or Private without mutating the underlying scan. This keeps the toolbar fast on-device while also correcting stale cache after reinstall, cross-device share/unshare, failed media publish, or remote visibility changes.

The Share sheet routes low-confidence biological scans through Identify by
default. A Strong AI result uses the configured inference-tier threshold
(Flash `>= 0.95`, Pro `>= 0.85`); anything below that, or a missing confidence
value from restored state, defaults the primary Share action to **Ask the
Community** when image media is available. User-confirmed identifications,
manual user overrides, existing feed-visible posts, and community-resolved
requests ready for owner publication keep **Share to Explore** as the primary
path. A direct low-confidence Explore publish remains available before an
Identify request exists, but it requires an explicit warning confirmation.

`TopToolbar` also exposes **Ask the Community** beside the identification
actions when `canRequestCommunityIdentification` is true. The CTA opens
`CommunityIdentificationRequestSheet`, where the user can add an optional note
and choose the same Open/Obscured/Private post-level location sharing used by
Explore sharing. Submission calls `/request-community-identification`, creating
or reusing the scan's Explore post and flagging it as a `needs_id` community
request. That post is then marked `community_needs_id` in
`explore_observation_projection` and hidden from the normal Explore
feed/map/author/hashtag projections. Resolved community requests remain public
inside Identify, but they do not enter normal Explore surfaces until the owner
explicitly publishes them afterward.

If the Edge function returns `Scan not found`, `MerianNetworkClient` treats that
as a local/cloud drift case for Insight-originated actions. It recreates a
minimal owned cloud scan row from the local record, resolves the server species
id by scientific name instead of trusting local-only UUIDs, restores saved local
image paths or the active live image buffer to staging, then retries the
Community request with `restored_object_keys`. The same recovery path is shared
with direct Explore sharing. The Ask affordance is gated on actual user image
media, not a padded display count, so image-less historical/text scans cannot
enter a request that the server cannot publish.

The request sheet title is `Ask the community` in sentence case. The shared
`CommunityIdentificationRequestSheet` is used for both new requests and existing
request edits, with the primary action in the toolbar: `Send`/`Sending...` for
new requests and `Save`/`Saving...` for edits. When the scan already has an
active community request, the Insight share sheet shows horizontal **Edit** and
**View** actions, then a separate **Publish to Explore** action with a visible
reminder that the community is still reviewing the ID. After the community
request resolves, owner publish materializes any new GBIF-backed species into
the Dictionary, writes that species to `scans.confirmed_species_id`, preserves
the original AI `scans.species_id`, and makes the post eligible for normal
Explore surfaces.

---

## Queued Scan Value-Type Pattern

`InsightSheetView` supports viewing pending `OfflineQueuedScan` records from the library grid. A critical constraint is that **no live `@Model` reference may be held** after the scan is deleted from the SwiftData context — accessing any unfaulted attribute on a deleted `@Model` crashes with `"backing data was detached from a context without resolving attribute faults"`.

Two value-type structs encapsulate all data the insight chain needs at snapshot time, while the `@Model` object is live:

| Type | Purpose |
|---|---|
| `QueuedScanSnapshot` | Minimal value type for `ScansGrid` tile rendering (`id`, `imagePath`, `timestamp`). Used in `LazyVGrid` `ForEach` so no grid tile holds a zombie `@Model` reference. |
| `QueuedScanContext` | Richer value type for the full insight sheet chain — all telemetry fields plus `capturedMediaItems: [SerializedMediaItem]`. Initialized from a live `OfflineQueuedScan` while the object is accessible, then read through `capturedMediaSnapshot` so no queued-scan UI holds a live SwiftData reference. |

`InsightSheetViewModel.queuedContext: QueuedScanContext?` stores the context. All computed properties (`isProcessing`, `contentMode`, toolbar flags, carousel sources) switch on `queuedContext == nil` rather than accessing any `@Model` attribute after initialization.

**`gridId` namespacing**: `LocalScanRecord.id` and `QueuedScanSnapshot.id` share the same UUID value (`client_scan_id`). Without namespacing, `LazyVGrid`'s `ForEach` produces duplicate `AnyHashable` keys. `QueuedScanSnapshot.gridId` returns `"q_\(id)"` so queued-scan tiles always have a distinct key from their eventual `LocalScanRecord` counterpart.

---

## Queued Scan Completion Transition

When an offline scan completes while `InsightSheetView` is open, the sheet must **transition to results without dismissing**. The key mechanism:

`LibraryView` uses `.sheet(isPresented: $isQueuedSheetPresented)` with a separate `scanToManage: QueuedScanContext?` state. This decouples sheet presentation from the context — clearing `scanToManage` does not close the sheet.

```
OfflineQueueManager.deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:)
    → ScanLibraryEvents.libraryDidUpdatePublisher() emits
    → InsightSheetView.attemptQueuedCompletionHandoff(...)
    → Retry up to 8 × 350 ms for LocalScanRecord with matching ID
    → viewModel.queuedContext = nil        // Clear BEFORE load so .analyzing guard passes
    → inferenceEngine.load(from: record)   // Triggers isProcessing true→false
    → InsightContentView renders results
```

Clearing `queuedContext` before calling `load(from:)` is critical: `InsightSheetView.onChange(of: inferenceEngine.isProcessing)` has a `guard viewModel.queuedContext == nil else { return }` guard — if `queuedContext` were still set when `isProcessing` goes false, the completion path (celebration, haptics, record-marking) would be skipped.

`LibraryView.onChange(of: queuedScans.map(\.id))` also runs in parallel: when a scan leaves the queued array, it checks whether a `LocalScanRecord` exists for that ID. If yes, it sets `scanToManage = nil` (keeping `isQueuedSheetPresented = true`) so `InsightSheetView` receives `nil` for `queuedScan` and its internal transition runs. If no record exists (scan was deleted or failed), it sets `isQueuedSheetPresented = false` to dismiss the sheet.

---

## Tab Bar Badge Dot (`hasUnseenScan`)

`MainTabBar` reads `AppSettings.hasUnseenScan` to display an 8 pt red dot on the Scans icon. The flag is persisted underneath so background completions survive process suspension, and `AppLifecycleManager` calls `AppSettings.refreshFromDefaults()` on foreground to reconcile background delegate writes.

**Set to `true` (badge appears):**
- `CaptureWorkspaceViewModel.handleInferenceProcessingChange` — when live `isProcessing` goes false **and** `activeSheet != .insight` (user is not already viewing the result).
- `OfflineQueueManager+URLSession.processInferenceDownloadResult` — when an offline scan completes, **unless** `AppSettings.suppressInferenceBanners` is `true` (insight sheet is open and the user is watching the transition to results).

**Set to `false` (badge cleared):**
- `CameraSheetRouter.scans.onAppear` — when the scans sheet opens from the camera tab bar.
- `CameraSheetRouter.insight.onAppear` — when the insight sheet opens from the camera flow.
- `ScansSheetView.onAppear` — on every scans sheet presentation.
- `ScansSheetView.onChange(of: appSettings.hasUnseenScan)` — immediately clears the badge if it fires while the scans sheet is already visible (a scan completing while the user is already in the library).
- `InsightSheetView.onAppear` — clears the badge whenever any insight sheet opens (camera or library path).

---

## Push Notification Delivery

`InsightSheetView` manages the `AppSettings.suppressInferenceBanners` flag:
- **`onAppear`**: sets `suppressInferenceBanners = true`
- **`onDisappear`**: sets `suppressInferenceBanners = false`

`PushNotificationManager.willPresent(_:withCompletionHandler:)` reads the persisted key synchronously when the app is in the foreground because the delegate method is nonisolated and must call its completion handler immediately. If `true` (user is on the insight sheet), the notification is delivered silently (`completionHandler([])`). If `false` (user is elsewhere in the app), the banner is shown (`completionHandler([.banner, .sound, .list])`).

Both notification call sites (`InferenceEngine` live path, `OfflineQueueManager` offline path) schedule notifications unconditionally — without an `applicationState != .active` guard. Foreground suppression is delegated entirely to `PushNotificationManager.willPresent`. When the app is backgrounded, `willPresent` is never called and the OS shows the notification automatically.

---

## Image Carousel

The carousel now renders a unified mixed-media page model rather than stitching together separate image-only arrays.

1. **Live captures** (`viewModel.activeMedia.liveImageData`) — display-quality `Data` for the current session's live frame when analysis is still in flight.
2. **Persisted user media** (`viewModel.activeMedia.items`) — the ordered user timeline rebuilt from `CapturedMediaSnapshot`. This can contain image pages, video playback pages, standalone audio playback pages, and description pages in one stable sequence. Video poster thumbnails stay attached to the video item for grid/list preview purposes and are not duplicated as separate carousel pages; extracted video audio is kept as inference metadata on the video item, not a visible media page. Cloud hydration prefers `scans.captured_media` when present; legacy rows with `video_storage_urls` collapse sampled frame URLs into the video thumbnail instead of rendering those frames as standalone pages.
3. **Reference images** (`speciesData.referenceImageUrl`) — comma-separated verified field observations (e.g. iNaturalist) and Wikimedia images populated natively via GBIF occurrence hydration. **Suppressed for human subjects**: `viewModel.refUrls` returns `[]` when `speciesData.isHumanSubject` is true, preventing third-party photos of people from appearing in the carousel regardless of what the server populates.

**Seamless user-media handoff**: On a live scan, the saved on-disk media is rebuilt into `ActiveScanMedia` before `speciesData` is assigned and before the transient live image is cleared. On queued scans, `InsightSheetViewModel` seeds `cachedActiveMedia` directly from `queuedContext.capturedMediaSnapshot.activeScanMedia`. On completed records, `fetchLocalRecord` hydrates the same structure from `record.capturedMediaSnapshot.activeScanMedia`. That shared read path is what keeps the playback video clip, standalone audio clip, or mixed-media order intact while the sheet transitions from queued/analyzing state to results. Pending video paths may move from temporary capture storage into Documents during queue persistence, so the resolver falls back by filename before declaring video unavailable.

**Video presentation rule**: Scan tiles, widgets, map/profile previews, and share previews remain thumbnail-first by reading `coverImagePath`, `primaryImagePath`, or `thumbnailImagePaths`. Once the Insight sheet is open, `ActiveScanMedia` renders `.video` pages as playback surfaces, and tapping a video opens the fullscreen modal carousel on that video item. The poster image is therefore a preview asset, not a user-visible duplicate of the clip inside Insight. Non-biological video scans use the same media timeline, so their result body changes but the video remains playable media rather than a strip of sampled inference frames.

**SwiftData fault safety**: `CapturedMediaSnapshot` for `LocalScanRecord` and `OfflineQueuedScan` intentionally decodes `capturedMediaJSON` before touching the `capturedMediaEntries` relationship. This keeps insight-sheet body evaluation, `BiologicalView`, and carousel hydration on scalar SwiftData reads whenever the JSON mirror is valid, avoiding child-row faults during layout. `capturedMediaEntries` remains a fallback mirror, not the preferred hot read path.

**On-disk image quality**: Persisted image pages restored into `ActiveScanMedia` are 2048 px WebP (display-quality path). This covers the full native pixel width of all current iOS devices without upscaling (iPhone Pro Max at 3× ≈ 1290 px; iPad Pro at 2× = 2048 px), eliminating the JPEG blocking artifacts that appeared when the carousel rendered the 1024 px inference payload directly. The AI inference path remains at 1024 px — see [Image Pipeline → Dual-Path Downsample](../system-architecture/03-image-pipeline.md) for the full architecture.

All images are loaded through `AsyncLocalImageView`, which handles RAM cache hits, request coalescing, and local-vs-remote routing transparently.

Invalid carousel images are handled via the injected `onImageFailure: (String) -> Void` closure rather than a direct engine call. `InsightContentView` passes `{ path in inferenceEngine.dropInvalidCarouselImage(path) }`, which removes the entry from the active user-media timeline or from the comma-separated `speciesData.referenceImageUrl` without throwing index-out-of-bounds errors. The queued-scan path passes a no-op, keeping `ImagesCarousel` free of any engine dependency.

### NativePageCarousel & Per-Page Zoom Architecture

`ImagesCarousel` renders pages via `NativePageCarousel` — a `UIViewControllerRepresentable` wrapping `UIPageViewController`. `TabView(.page)` was evaluated and rejected for two reasons: it lazily instantiates pages (so `AsyncLocalImageView.task` only fires when the user swipes to a page, causing image loads during the swipe transition), and its gesture recogniser conflicts with the sheet's pan gesture. `UIPageViewController` fixes both: the `Coordinator` pre-creates all controllers upfront, and its internal `UIScrollView` defers to the sheet's pan without manual workarounds.

**`ZoomPageViewController`**: Each carousel page is a `ZoomPageViewController` — a `UIViewController` that embeds its SwiftUI content inside a `ZoomScrollView`. It exposes a `rootView: AnyView` computed property that proxies to the inner `UIHostingController`, preserving `updateUIViewController`'s existing state-push pattern (`controller.rootView = pages[i]`) without any changes to the page-update path.

**`ZoomScrollView`**: A `UIScrollView` subclass configured with `minimumZoomScale: 1.0` and `maximumZoomScale: 4.0`. It overrides `gestureRecognizerShouldBegin(_:)` to return `false` for its `panGestureRecognizer` when `zoomScale ≤ minimumZoomScale + 0.01`. This is the only safe way to suppress the inner pan at 1×: replacing `panGestureRecognizer.delegate` directly throws `NSInvalidArgumentException` at runtime because UIKit requires the scroll view itself to remain its pan gesture's delegate. At 1× the UIPageViewController swipe wins; above 1× the inner scroll view's pan fires, allowing the user to explore the zoomed image freely.

**Snap-back**: Both `scrollViewDidEndZooming` (pinch released) and `scrollViewDidEndDragging` (pan released while zoomed) call `snapBackToIdentity`, which cancels any pending deceleration then runs `UIView.animate(usingSpringWithDamping: 0.72)` to restore `zoomScale → 1.0` and `contentOffset → .zero` simultaneously.

---

## Scan Information Card

`ScanInformationCard` renders the spatiotemporal context captured at the moment
of the scan after applying `ProfileViewModel.defaultGeoprivacy`. It is hidden
entirely when no privacy-visible data remains (for example, a private scan with
only location/weather telemetry), preventing the card from appearing as an empty
placeholder.

Rows displayed when present:

| Row | Source | Condition |
|---|---|---|
| LOCATION | `speciesData.locationName` | Non-empty string |
| ELEVATION | `speciesData.gpsElevation` | Non-nil, non-zero |
| WEATHER | `speciesData.weatherTemperatureF` + `weatherCondition` | Both non-nil |
| DATE | `timestamp` parameter | Non-nil |
| TIME | `timestamp` parameter | Non-nil |
| IMAGES | `imageCount` parameter | `imageCount > 1` only; hidden for single-image scans |
| CAMERA ZOOM | `speciesData.zoomFactor` | Non-nil (1× scans omit this row) |
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

**24h enrichment deduplication** (`enrichedSpeciesTimestamps`): After `fetchAndApplyEnrichment` completes, `InferenceEngine` records the scientific name with a timestamp in `enrichedSpeciesTimestamps` (a `[String: Double]` UserDefaults-persisted dictionary with a 24h TTL) to prevent redundant `enrich-scan` Edge calls for the same species within 24 hours. This write is **conditional on `speciesData?.habitatDescription != nil`** — if enrichment fails transiently and `habitatDescription` is not populated, no timestamp is recorded. This ensures a failed enrichment attempt does not block future enrichment retries for species whose prior call failed transiently.

### Loading Flow (historical scans)

When `InferenceEngine.load(from:)` loads a `LocalScanRecord` that is missing `habitatDescription`, `gbifTaxonKey`, or `lookalikesData`, it automatically fires `fetchAndApplyEnrichment`. Metadata remains species-cache-aware, but lookalikes are still fetched per scan whenever the record lacks rich local lookalike data. This aggressively gap-fills enrichment for older scans (even those that already have flat `similarSpecies` string arrays) to ensure they retrieve rich image and common name JSON payloads from the V27 pipeline.

### States

| State | Trigger | Rendered |
|---|---|---|
| **Loaded** | `habitatDescription != nil` | Habitat text |
| **Loading** | `inferenceEngine.isEnrichmentLoading == true` | Shimmer skeleton (3 text lines) |
| **Retry** | No data, not loading | "Retry" button → calls `inferenceEngine.fetchAndApplyEnrichment`. **Auto-retry**: when the card first enters this state, a `.task` fires `triggerEnrichment()` once after a 2-second delay (gated by `@State private var hasAutoRetried = false`). The manual Retry button remains as a fallback. |

### Observation Pattern Charts

`SpeciesObservationChartsCard` renders immediately after
`HabitatAndDistributionCard` when the biological result has a non-empty
scientific name and is not the `"Taxonomy Unavailable"` placeholder.

Data flow:

- `BiologicalView` passes `viewModel.activeLocalRecord?.confirmedSpeciesId` and
  `inferenceEngine.speciesData?.scientificName`.
- `SpeciesObservationStatsViewModel` creates
  `SpeciesObservationStatsDatabaseActor` for filtered SwiftData projection
  fetches, then delegates local normalization and bucketing to
  `SpeciesObservationStatsReducer`.
- Local Seasonality, History, and Life Stage are computed on-device from
  effective species matches using `captureDate ?? timestamp`.
- `MerianNetworkClient.getSpeciesObservationStats(...)` fetches the cached
  global public iNaturalist baseline. The request contains only dictionary
  species ID and scientific name, never local counts or local dates.
- The chart normalizes local and public series independently so personal logs
  stay visible beside large public datasets. Footer/accessibility text keeps
  raw peak counts available.

States:

| State | Trigger | Rendered |
|---|---|---|
| Local + Public | Local rows and public cache/provider data exist | Normalized comparison chart with raw summary footer |
| Local only | Public request fails or is unavailable | Local chart plus public-unavailable note |
| Public only | No local rows yet | Public chart baseline |
| Partial/Stale | Backend returns `partial` or `stale` | Chart plus refresh/cache note |
| Empty | Selected tab has no local or public values | Compact empty state explaining the tab |

See
[`Species Observation Charts`](./18-species-observation-charts.md) for the full
API contract, iNaturalist annotation mappings, cache rules, and privacy
boundary.

### Similar Species Rendering

`similar_species` data is rendered by `SimilarSpeciesGallery` inside `BiologicalView` sequentially. The gallery is explicitly treated as informational and unconditionally renders as "Similar species". Previous dynamic confidence-based gating has been removed to prioritize objective reference availability.

**Mathematical Baseline Constraints**: To prevent Apple's SwiftUI Layout Engine from allowing extreme intrinsic image aspect ratios (e.g., highly vertical photos) from stretching the row, `SimilarSpeciesCard` enforces fixed card geometry at `200 x 260` points. The image fills the card bounds, while the bottom text overlay uses material chrome and internal padding so a 2-line `.subheadline` common name and 1-line `.caption` scientific name remain stable without resizing the carousel.

Each `SimilarSpeciesCard` receives a `SimilarSpeciesEntry`. When `referenceImageUrl` is non-nil, the card renders it via `AsyncLocalImageView`; if the URL fails, local `@State var remoteImageFailed` flips to `true` and the card shows the leaf-icon placeholder instead. When `referenceImageUrl` is nil, a `SimilarSpeciesImageFetcher` Wikipedia/GBIF waterfall runs in a `.task`. In all failure cases the card stays in the gallery — it is never removed. The only exclusion rule is a blank `scientificName` (truly invalid server data), filtered in `validEntries`.

---

## Identification Candidates

When the AI's confidence falls below the tier-specific `diagnosticTrigger` threshold (`0.99` for both Flash and Pro) the `candidates` array is forwarded to the client and persisted for the scan. This threshold is intentionally above the `strong` band on each tier (`0.95` Flash / `0.85` Pro), so Possible, Weak, and most Strong-match scans can still carry candidates as an escape hatch for overconfident wrong IDs. Only scans at or above `0.99` have candidates stripped.

Stored candidates do **not** automatically create a visible candidate-review UI. Display is controlled on-device by `CandidateReviewVisibilityPolicy`, which is shared by the inline `CandidatesCard`, `ConfidenceExplanationSheet`, toolbar actions, and the Needs review smart collection. The policy shows review alternatives when the primary identification is below the tier's Strong threshold, or when a Strong primary has a genuinely competitive alternative.

### Data Flow

1. **Gemini schema** (`services/supabase/functions/_shared/identify/schema.ts`): `candidates` is a **required** field in `merianResponseSchema` — Gemini always generates exactly 2 alternative species regardless of confidence. Each entry is `{ scientific_name, confidence_score, distinguishing_feature }` where `distinguishing_feature` (required string) is the single most important observable visual trait that separates this candidate from the primary identification, grounded in `extracted_visual_traits`. `common_name` is absent from the Gemini schema — it is enriched server-side via a batch `species_dictionary` lookup before the response is sent, so the field is present when the candidate species is already cached and absent (omitted from JSON) on a cache miss. The system instruction asks for genuinely distinct alternatives, not subspecies variants of the primary identification.
2. **Server-side strip** (`services/supabase/functions/identify-multimodal/index.ts`, shared thresholds in `services/supabase/functions/_shared/identify/thresholds.ts`): After Gemini returns, the active multimodal handler calls `diagnosticTriggerForTier(tier)`. If `confidence_score >= diagnosticTrigger`, the `candidates` array is cleared to `null` before the response is sent to the client and before the `insertScan` DB write. This is the sole gate: Gemini is not asked to self-suppress, the server enforces the rule unconditionally. **Thresholds**: `0.99` for both Flash and Pro (intentionally above `FLASH_STRONG` = 0.95 and `PRO_STRONG` = 0.85 so Strong match scans still carry candidates). `MerianConfig.flashConfidence.diagnosticTrigger` and `MerianConfig.proConfidence.diagnosticTrigger` in the iOS client mirror these values and must be kept in sync.
3. **Supabase persistence** (`candidates` JSONB, migration `20260330000000_add_candidates_to_scans.sql`): Stored as a JSONB column on `public.scans`. `NULL` for scans at or above the diagnostic trigger (`0.99`) and all scans from before this migration. A partial index (`WHERE candidates IS NOT NULL`) keeps index overhead minimal since most near-certain scans do not need stored alternatives.
4. **SwiftData persistence** (`candidatesData: Data?`, `MerianSchemaV28`): The iOS client JSON-encodes `[IdentificationCandidate]` via `JSONEncoder` and stores the blob in `LocalScanRecord.candidatesData`. `InferenceEngine.load(from:)` decodes it back via `JSONDecoder` for historical scans.
5. **Historical sync** (`ScanRepository.syncHistoricalScansDown`): The `candidates` column is included in the `SELECT` query. A `CloudIdentificationCandidate` DTO (`{ scientific_name: String, common_name: String?, confidence_score: Double, distinguishing_feature: String? }`) decodes the cloud JSONB. `ingestScans` re-encodes it to `IdentificationCandidate` (including `distinguishingFeature`) and persists as `candidatesData`. The `updateExistingScans` backfill path checks `existing.candidatesData == nil` before writing, ensuring cloud candidates are retroactively available in pre-existing local records. `distinguishing_feature` is `String?` in the DTO to decode gracefully from pre-migration JSONB rows that have only the two-field shape.

### Display Gate

`CandidateReviewVisibilityPolicy` centralizes review visibility. `BiologicalView`, `ConfidenceExplanationSheet`, and `InsightSheetViewModel.canReviewAlternatives` call this policy instead of checking raw candidate presence independently.

Visible candidate-review UI is allowed when all baseline guards pass:

```swift
isBiological == true
isUnknownSubject == false
isHumanSubject == false
candidates.isEmpty == false
userIdentificationOverride == nil
userConfirmedIdentification == false
alternativesExhausted == false
primaryConfidence < MerianConfig.confidenceBands(forInferenceTier: tier).diagnosticTrigger
```

After the baseline guards pass, one of these confidence checks must also pass:

```swift
primaryConfidence < MerianConfig.confidenceBands(forInferenceTier: tier).strong

// OR, for Strong primaries:
topCandidateConfidence >= 0.80
abs(primaryConfidence - topCandidateConfidence) <= 0.15
```

These constants live in `CandidateReviewVisibilityPolicy`:

- `minimumCompetitiveCandidateConfidence = 0.80`
- `competitiveCandidateMargin = 0.15`

**`isUnknownSubject`** — suppresses candidates when taxonomy is unavailable; the alternatives would be equally unresolved.

**`isHumanSubject`** (`SpeciesData.isHumanSubject`: `commonName.lowercased() == "human" || scientificName.lowercased() == "homo sapiens"`) — suppresses candidates for human subjects. The AI sometimes generates plausible-sounding primate alternatives when confidence is low; surfacing them for a human photo would be misleading and inappropriate.

**`hasReviewState`** — suppresses candidates once a decisive identification action has been taken (`userIdentificationOverride`, `userConfirmedIdentification`, or `alternativesExhausted`). Legacy `isFlagged` values no longer hide candidate review or surface a review UI. When `alternativesExhausted == true`, `CandidatesCard` is hidden and `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` takes over instead.

The policy returns the stored candidate array only when it is visible. Hidden candidates remain persisted for recovery and future flows, but inline cards, confidence-sheet rows, and toolbar Review alternatives actions behave as if the candidate list is empty.

**`isHumanSubject` and the override path**: `isHumanSubject` checks `scientificName` (the mutable active field), not `aiScientificName`. If a user overrides a human scan to another species, `scientificName` changes to the override name, the guard lifts, and candidates for the override species become visible — consistent with the carousel ref-image unblock that also follows an override.

### `CandidateSwipeModal` — Alternatives Review Sheet

`CandidateSwipeModal` is presented as a `.sheet` from both `CandidatesCard` (via `BiologicalView`) and `ConfidenceExplanationSheet`. It receives an explicit `@Binding var isPresented: Bool` rather than using `@Environment(\.dismiss)` — the dismiss environment value leaks up through nested sheets in SwiftUI and would close the parent `InsightSheetView` instead of only the modal.

**State model**: `CandidateSwipeSession` in `IdentificationReview/Candidates/Models` owns `originalCandidates`, `remainingCandidates`, `confirmedCandidate`, and `isExhausted`, plus the skip/reject/confirm/restart decisions. `CandidateSwipeModal` keeps animation, drag offsets, dismissal timing, paywall routing, and sheet wiring in SwiftUI.

**Card stack**: The top card is draggable (Tinder-style). Dragging ≥ 200 pt right confirms the candidate through the session; left rejects it. The card behind it scales up as the drag percentage increases. A "Skip" capsule button appears when `session.remainingCandidates.count > 1`, moving the top card to the bottom of the queue.

**Grid mode**: When `session.remainingCandidates.count > 1`, a grid toggle button appears in the top-right toolbar. Grid mode shows all remaining candidates as `GridSwipeableCell` rows with per-row confirm/reject buttons.

**Toolbar**: The leading X button sets `isPresented = false`. When multiple candidates remain, the trailing button toggles grid/stack mode. When alternatives are exhausted (`session.isExhausted && !isDismissing`), a plain **Restart** text button appears in the trailing slot and calls `session.restart()` without closing the sheet.

**Exhausted state** (`exhaustedStateContent`): Shown when all candidates have been swiped away. Displays the original scan thumbnail and up to three action controls stacked vertically:
1. `SlideToConfirm(label: "Confirm species", color: .green)` — always shown; calls `onConfirmOriginal()` and dismisses
2. `SlideToConfirm(label: "Reanalyze species", color: .orange)` — only shown when `onRefineScan != nil` (i.e. the scan is a local file and has not already been refined); calls `onRefineScan()` and dismisses
3. `SlideToConfirm(label: "Ask the community", color: .blue)` — only shown when `onAskCommunity != nil`; dismisses the modal after a 300 ms delay and then opens the Ask the Community request sheet on `@MainActor`

**`onRefineScan` wiring**: `BiologicalView` computes `refinementAction: (() -> Void)?` — it sends `.triggerRefinement(record:)` via `AppEventPublisher` and calls `dismiss()`. The guard `(record.additionalImagePaths ?? []).isEmpty` blocks re-refinement of scans that already carry supplementary images. The action threads through: `BiologicalView` → `CandidatesCard(onRefineScan:)` → `CandidateSwipeModal(onRefineScan:)`. `ConfidenceExplanationSheet` independently computes the same action and passes it directly to the modal.

**Confirmed state**: After a stack or grid confirm, `session.confirmedCandidate` is set, showing a green `checkmark.circle.fill` success screen for 1.5 s before the sheet auto-dismisses. `applyIdentificationOverride` is deferred a further 300 ms after dismissal to prevent SwiftUI from destroying the host sheet anchor during the structural `speciesData` mutation.

**`onDisappear` guard**: If `session.isExhausted && !isDismissing`, `inferenceEngine.markAlternativesExhausted()` is called — this sets the `alternativesExhausted` flag that surfaces `AllCandidatesReviewedView` in `ConfidenceExplanationSheet` on next open.

**Nested sheet `Menu` incompatibility**: SwiftUI `Menu` uses `UIContextMenuInteraction` which fails to attach in nested sheet contexts — the tap falls through to the sheet's dismiss gesture. All contextual actions are surfaced as first-class controls within the view body rather than toolbar menus.

### Stage 2 — Approve / Deny UX

Users can confirm or override the AI's primary identification directly from `CandidatesCard`. The card manages a local `ReviewState` enum:

- **`.pending`**: Default state. Shows a "Was the AI correct?" prompt with a `SlideToConfirm` drag-to-confirm pill. The system passes a dynamically injected name derived from `viewModel.resolvedHeaderTitle` (e.g., "Confirm Giant Panda") rather than a hardcoded string. To prevent text overflow on these long dynamic names, the pill natively relies on `minimumScaleFactor(0.6)` typographic squishing before truncating. The user drags the thumb ≥88% of the track width to confirm; releasing early springs the thumb back. On completion, `InferenceEngine.confirmAIIdentification(modelContext:)` is called, setting `userConfirmedIdentification = true` locally and transitioning to `.confirmed`. Refusing all alternatives lets the user ask the community for help instead of sending a dead moderation flag. For candidates with missing `commonName` strings (or common names identical to taxonomy), `SwipeableCandidateCard` securely elevates the `scientificName` to the primary title string un-capitalized. Each card also displays `distinguishingFeature` (the single most important observable visual trait separating this candidate from the primary ID) below the species name in sentence case, truncated to 2 lines. Tapping the feature text opens a `DistinguishingFeatureSheetView` sheet ("What to look for") at `.fraction(0.35)` height showing the full untruncated text. The original capture is also accessible via a PiP thumbnail (bottom-right) that expands to a full-screen `OriginalCaptureExpandedView`; that expanded path downscales `activeMedia.liveImageData` through `ImageDownsampler` at `MerianConfig.displayImageMaxSize` rather than inflating the original capture with `UIImage(data:)`. Tapping the candidate image expands it to a paged `TabView` carousel containing up to 5 progressively loaded reference images inside `CandidateImageExpandedView`.
- **`.confirmed`**: Replaces the prompt with nothing (the card hides its body). `ConfidenceBadge` transitions to "Confirmed" (green, `checkmark.seal.fill`). `ConfidenceExplanationSheet` shows a confirmation message.
- **`.overridden(to:)`**: Active after the user selects a candidate as their preferred identification. Renders an `OverriddenView` showing "Your identification" with the override name, "AI originally suggested X" footer, and an Undo button. `ConfidenceBadge` transitions to "Your ID" (indigo, `person.fill.checkmark`).
Candidate exhaustion is a separate state: when `alternativesExhausted == true`, `AllCandidatesReviewedView` shows "Alternatives reviewed", the stored candidate count, a Reset button (`resetIdentificationReview`), a **"Review again" button** that re-opens `CandidateSwipeModal` with stored candidates, and an **"Ask the community" button** that opens the Community request sheet for human identification help.

**Override flow**: Selecting a candidate calls `InferenceEngine.applyIdentificationOverride(scientificName:modelContext:)`, which:
1. Mutates `speciesData.userIdentificationOverride` and `speciesData.scientificName` to the override name, and clears any legacy local flag bit so old scans cannot carry stale review state forward.
2. Persists `LocalScanRecord.userIdentificationOverride` via `BackgroundDatabaseActor.updateScanWithOverride`.
3. Syncs to `public.scans.user_identification_override` via a direct PostgREST PATCH (`InferenceEngine.syncIdentificationReviewToCloud`), guarded by `.eq("user_id", userId)`.
4. Fires `fetchAndPatchOverrideData(scientificName:scanId:modelContext:)` — queries `species_dictionary` for a cache hit and patches `speciesData` fields (common name, taxonomy, Wikipedia, etc.). On cache miss, calls `fetchAndApplyEnrichment` (which uses the already-mutated `speciesData.scientificName` as the lookup key).
5. After patching `speciesData`, persists the updated species-dict fields (common name, hazard type, taxonomy, Wikipedia, habitat, GBIF key, etc.) to `LocalScanRecord` via `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData`. `scientificName` is intentionally excluded from this write — `record.scientificName` is preserved as the authoritative original-AI identifier, reused as `aiScientificName` on `load(from:)` so that `resetIdentificationReview` can recover the original name without a separate schema field.

**Re-opening an overridden scan**: `InferenceEngine.load(from:)` applies two rules when `record.userIdentificationOverride != nil`:
- Sets `speciesData.scientificName` to `record.userIdentificationOverride` (the override name) rather than `record.scientificName` (the original AI name).
- Suppresses `InsightData.aiReasoning` — the AI's vision reasoning was written for the original species and is misleading under the override name.
`record.scientificName` is always used as `aiScientificName`, enabling the "AI originally suggested X" footer and the Undo/reset path regardless of how many times the sheet is reopened.

**Data model**: Four fields on `LocalScanRecord` (all cloud-synced):
- `userIdentificationOverride: String?` — mirrors `public.scans.user_identification_override`.
- `userConfirmedIdentification: Bool` — mirrors `public.scans.user_confirmed_identification`. Both legacy fields are sent in `ReviewSyncPayload` alongside the explicit enum.
- `userReviewStateRaw: String` — typed mapping storing the `user_review_state` enum value natively.
- `isFlagged: Bool` — legacy V31 persistence field retained for schema compatibility; it no longer drives Insight confidence or candidate-review UI.

**Re-identification**: A user who has already acted on a review can always re-enter the selection flow:
- From `.overridden`: tap Undo → calls `resetIdentificationReview` → reverts to `.pending` with policy-visible candidates available again.
- From `.confirmed`: tap "Change" in `ConfirmedView` → calls `resetIdentificationReview` → reverts to `.pending`.
- `resetIdentificationReview` clears `userIdentificationOverride`, `userConfirmedIdentification`, any legacy flag bit, and `alternativesExhausted` locally, reverts `speciesData.scientificName` to `aiScientificName`, and re-hydrates the AI's original species data from `species_dictionary`. It sets `userReviewStateRaw` to `"unreviewed"` locally. Clearing `alternativesExhausted` is required for the `AllCandidatesReviewedView` → full reset path; otherwise `CandidateReviewVisibilityPolicy` would keep candidate actions suppressed after reset.

**Cross-device sync caveat**: `ScanRepository.updateExistingScans` propagates `userConfirmedIdentification` in the `true` direction only — a reset performed on device A (which syncs `user_confirmed_identification = false` to the cloud) will not propagate to device B during that device's next sync. Device B retains its local confirmed/overridden state. Full bidirectional review-state sync is deferred.

---

## Confidence Badge and Spectrum

`ConfidenceBadge` is a tappable liquid-glass capsule that shows the AI's confidence band for the current scan. The badge first checks durable identification decisions before falling back to the confidence-band logic:

**Identification review states** (take precedence over confidence bands):
| State | Label | Color | Icon | Trigger |
|---|---|---|---|---|
| User override | "Your ID" | Indigo | `person.fill.checkmark` | `userIdentificationOverride != nil` |
| User confirmed | "Confirmed" | Green | `checkmark.seal.fill` | `userConfirmedIdentification == true` |

**Confidence bands** (when no review state is set — managed dynamically via `MerianConfig.confidenceBands(for: isPro)`):

**Gemini 2.5 Flash (Free Tier)**
| Band label | Color | Score range |
|---|---|---|
| Strong match | Green | ≥ 96% |
| Possible match | Orange | 75% – 95% |
| Weak match | Gray | Below 75% |

**Gemini 2.5 Pro (Premium Tier)**
| Band label | Color | Score range |
|---|---|---|
| Strong match | Green | ≥ 85% |
| Possible match | Orange | 65% – 84% |
| Weak match | Gray | Below 65% |

The badge renders for override/confirmed states even when `confidenceScore == 0` (historical scans where confidence is unavailable).

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items using the same `MerianConfig` constants so the displayed percentage ranges are always in sync with the badge logic.

`ConfidenceExplanationSheet` opens as a bottom sheet from the badge tap. It contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`, `AIMistakesBanner`, and `ProTips` (which conditionally shows a location permission prompt when GPS access is not granted). `ModelInfoSection` sits between `ConfidenceSpectrum` and `AIMistakesBanner` and surfaces which Merian AI tier processed the scan — "Merian AI Standard" for free/Flash scans, "Merian AI Pro" for Pro scans, with a "Powered by Gemini 2.5 Pro" footnote on the Pro variant. The sheet reads stored candidates for the alternatives-exhausted Review again path and `CandidateReviewVisibilityPolicy.visibleCandidates(for:)` for normal candidate display. Review-state cards rendered at the top of the sheet (mutually exclusive, evaluated in order):

| Priority | Condition | View | Action |
|---|---|---|---|
| 1 | `alternativesExhausted == true` | `AllCandidatesReviewedView` | Review again → `CandidateSwipeModal`; Ask the community → Community request sheet; Reset → `resetIdentificationReview` |
| 2 | `userIdentificationOverride != nil` | `OverriddenView` | Undo → `resetIdentificationReview` |
| 3 | `userConfirmedIdentification == true` | `ConfirmedView` | Undo → `resetIdentificationReview` |

When none of the above conditions are met, no review card is rendered and the full confidence explanation is shown unobstructed.

`blur_score` is populated from live inference only (`SpeciesData.blurScore` maps to `EdgeResponse.blur_score`). It is `nil` for scans loaded from the local SwiftData library since it is not persisted to `LocalScanRecord`.

---

## Reference Image and Wikipedia Hydration

Extended ecological media data is loaded in three passes:

1. **Synchronous with inference** (live scans): the Edge function fetches Wikipedia in `EdgeRuntime.waitUntil` and includes `wikipedia_overview` and `wikipedia_url` in the response. These populate immediately when the sheet opens.
2. **Retroactive Wikipedia hydration** (live scans where Wikipedia was missing, and all historical scans): `InferenceEngine.fetchWikipediaAndHydrate` fires a `GET` to `en.wikipedia.org/api/rest_v1/page/mobile-sections/<scientific_name>` with an 8-second timeout. The response includes all article sections; the function finds the first section whose `title` case-insensitively equals `"Description"` and strips its HTML to plain text via `InferenceEngine.stripHTML(_:)`. If no "Description" section exists, hydration is skipped entirely. On success it commits `speciesData.wikipediaOverview` (the stripped description body), `speciesData.wikipediaUrl` (constructed from `lead.normalizedtitle`), and `speciesData.referenceImageUrl` (`lead.originalimage.source`) in a single full-value replacement on `@MainActor`.
3. **Dynamic GBIF Native Hydration**: When the species' `gbif_taxon_key` is available (either instantly on a Cache Hit, or returned seconds later by the `enrich-scan` API), the iOS client calls `InferenceEngine.fetchGBIFImagesAndHydrate(for:)`. This queries the `api.gbif.org/v1/occurrence/search` API for 3-4 high-quality iNaturalist field photos, dynamically injecting them into the carousel to ensure highly accurate visual context.

---

## Milestone Notification (New to Merian)

On sheet `.onAppear`, `InsightSheetViewModel.evaluateVoiceOverAndCelebration`
checks the global dictionary contribution flag, not the local "new to me" flag:

```swift
if data.isNewToMerianDictionary && data.isBiological
    && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
    MilestoneToastPresenter.shared.enqueueNewToMerianMilestone()
}
```

The old local `CelebrationBanner` pill is removed. The shared
`MilestoneToastBanner` appears at the bottom of the app with the same queue,
haptics, swipe-down dismiss, close button, timeout, and VoiceOver announcement as
achievement unlocks. Tapping the `New to Merian` body dismisses the banner in
v1 because the user is already viewing the scan Insight; achievement milestone
taps still open their achievement detail sheet directly.

VoiceOver users continue to receive the Insight accessibility announcement,
including a hazard-specific warning (venomous / allergenic / irritant / toxic)
when `hazardType != "none"`.

---

## Scroll-Aware Toolbar

`InsightSheetView` tracks whether the common name has scrolled past the viewport boundary to seamlessly morph the species name into the `TopToolbar`'s `.principal` display. Tracking an element's `maxY` inside a stretchy header `ScrollView` creates cyclical layout resolution hazards if `PreferenceKey` architectures are used (which inherently force sequential multi-pass frame layouts).

**Asynchronous Geometry Telemetry**: To permanently eradicate the *"Bound preference tried to update multiple times per frame"* runtime warning, `InsightHeader` abandons the `PreferenceKey` system entirely. It embeds a passive `Color.clear.onChange(of: geo.maxY, initial: true)` hook directly within its `GeometryReader`. This intercepts the positional coordinate strictly post-layout and transmits it instantly to `viewModel.evaluateScrollOffset` via an injected callback (`onScrollOffsetChange`), cleanly decoupling the telemetry from SwiftUI's layout-invalidation phase lock constraint.

**Dynamic Form Controls**: `TopToolbar` acts as the primary global contextual sheet. It houses a `Menu` button anchored to the trailing edge spanning four categories natively via SwiftUI `Section` wrappers. The collection picker lives directly below Add/Update field notes in this menu, reusing the same Favorites, existing-collection toggles, and New Collection flow previously hosted in the bottom toolbar:
1. Base Export (Save photos)
2. Identification Section (Confirm species, Review alternatives, Reanalyze species, Ask the community)
3. Destructive Section (Delete scan)
The middle tier ("Identification") is driven by `InsightSheetViewModel` display properties. `Confirm species` and `Review alternatives` both depend on `reviewAlternativeCandidates`, which is filtered through `CandidateReviewVisibilityPolicy`; when policy-visible candidates are absent, both actions are hidden. `Reanalyze species` remains independently available through its local-record guard. `Ask the community` is available for biological, shareable scans with image media and opens the Community request sheet. Confirmed, overridden, exhausted, unknown, non-biological, and human-subject states suppress candidate actions without affecting reanalysis or Community request affordances where those still make sense.

---

## Collection Management

Users can add or remove the current scan from any `ScanCollection`:

```swift
func toggleScanInCollection(_ collection: ScanCollection, modelContext: ModelContext) {
    // toggles record.collections membership
    // saves modelContext
    // calls OfflineQueueManager.shared.enqueueCollectionSync() for immediate cloud push
    // fires a toast message
}
```

"New Collection" is handled by the `newCollectionAlert` view modifier attached to `InsightSheetView`. It creates a `ScanCollection` in SwiftData with a UUID immediately, saves locally, and then schedules cloud sync through `OfflineQueueManager`'s shared collection drain.

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

- **Save to Photos**: passes live capture data, valid historic file paths, and any R2-hosted reference URLs (filtered to the exact `media.merian.app` host only) to `ExportProcessingActor.shared.saveUserPhotos`. Each image is saved to Camera Roll via `PhotoLibraryManager.shared.saveImageManual`. On completion, `showSaveSuccessAlert` is set to `true`.
- **Share Sheet**: constructs a share payload with the species common name, scientific name, and the best available image (live > historic > reference), then presents `UIActivityViewController` via `ShareSheetUtility.present`.
