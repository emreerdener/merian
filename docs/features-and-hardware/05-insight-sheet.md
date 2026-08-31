# Insight Sheet

The Insight Sheet is the primary post-scan result screen, surfacing AI taxonomy,
confidence data, ecological context, and media for every scan. Capture presents
it modally when `CaptureWorkspaceViewModel.activeSheet == .insight`; Scans and
Explore can host the same feature as a pushed destination in their existing
navigation stack.

## Field Chat Entitlement Boundary

Field Chat is a Pro capability. A customer with an active store subscription,
receipt-backed free trial, or explicitly approved finite RevenueCat beta
promotion receives Field Chat after that entitlement is projected to
`public.users.subscription_tier = 'pro'`. RevenueCat's developer project being
on the Pro plan does not grant any customer access, and a client-only Pro value
is not sufficient because `/insight-chat`, `/explore-post-chat`, and
`/species-dictionary-chat` enforce the server projection. Separately, an exactly
verified `pro_complimentary` functional tier also satisfies the server chat gate
while an available credit or active hold remains; it does not create a
RevenueCat entitlement or paid badge.

The shared iOS conversation implementation is owned by
`apps/ios/Merian/Features/FieldChat/`. Insight Shell owns scan eligibility,
owner-row readiness, dismissal handoffs, and its typed presentation slot;
`FieldChatEndpoint` and `InsightChatViewModel` own source adaptation and
subject-fenced conversation state. Core Network retains the Codable wire
contracts, strict validation, and transport.

Availability preparation is same-subject single-flight; subject replacement or
clearing invalidates older readiness. Prompt refresh is latest-trigger-wins, and
a canceled in-flight send returns the exact current pending bubble to retryable
state under its original UUID. These shared rules apply equally to Insight,
Explore-post, and Species Dictionary hosts.

The Species Dictionary source is a release-held candidate. Its shared sheet and
entitlement wiring do not authorize product promotion until the Ghost merge and
three-family admission contracts, explicit post-deploy cutover activation,
no-write quota denial, automatic idempotent replay, authenticated-wrapper
evidence, exact Swift/Deno label parity, candidate-matched live bundle digests,
ready-state rerun selection, artifact-backed protected clearance, and the
remaining release gates pass the
[canonical Dictionary checklist](16-species-dictionary.md#candidate-release-status).

The beta grant operation remains release-held until the identity, cohort, and
reconciliation conditions in the
[RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md)
are satisfied.

---

## Architecture

| File                                                                     | Role                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Shell/ViewModels/InsightSheetViewModel.swift` + product-area extensions | `@Observable @MainActor final class` — the root file owns stored state, init/reset, and `UIState`. Shell extensions own lifecycle, records, capabilities, content presentation, media presentation, and presentation identity in `Shell/ViewModels/`. Field notes remain in `FieldNotes/ViewModels/`, Explore sharing in `Sharing/ViewModels/`, media export in `Media/Utilities/`, and name preferences plus result actions in `Content/ViewModels/`, preserving the scan-ID/snapshot safety boundary.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `InsightSheetView`                                                       | Root Insight presentation. `InsightPresentationStyle` selects modal-sheet behavior or embedded Scans-library navigation. The optional `queuedScan: QueuedScanContext?` is a value snapshot, never an `OfflineQueuedScan @Model`; the custom initializer seeds `InsightSheetViewModel(queuedContext:)` before body evaluation. Queued presentations use a dedicated trash action, suppress duplicate inference banners, and observe both their initial task and typed `.scanLibraryChanged` invalidations for completion. `attemptQueuedCompletionHandoff` retries up to 8 × 350 ms for the matching `LocalScanRecord`, then replaces queued state with the completed result without dismissing or popping the presentation. See §Queued Scan Completion Transition.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `Shell/Views/InsightSheetView+Toolbar.swift`                             | Keeps toolbar assembly out of the root sheet body. It wires queued-scan trash handling, collection actions, report/reanalyze/review/confirm actions, and bottom-toolbar visibility using view-model capability flags and record snapshots.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `Shell/Modifiers/EmbeddedInsightNavigationModifiers.swift`               | Hosts the feature-local back-swipe, navigation swipe enabler, and species-dictionary destination modifier used by embedded Insight navigation stacks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `Shell/Models/InsightPresentation.swift`                                 | Defines `.sheet` and `.embeddedInScansLibrary` presentation styles plus `ScanInsightRoute`, whose stable scan ID is the value-only route for completed Scans-library Insights. The queued route is private to `ScansSheetView` because it must carry a `QueuedScanContext` snapshot while hashing by scan ID.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `Toolbars/Models/InsightToolbarRecordSnapshot.swift`                     | Captures the toolbar's value snapshot of a `LocalScanRecord` before modal/share/delete boundaries so UI work does not retain a deleted SwiftData model.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `InsightContentView` / `InsightContentRouterView`                        | `InsightContentView` owns the hero/media shell and delegates the four-way mode switch (`.analyzing` / `.queued` / `.nonBiological` / `.biological`) to `InsightContentRouterView`. The first-open timing guard keeps `queuedScan` as a plain input value and falls back to it until `viewModel.queuedContext` is bound, preventing the wrong scanning body from flashing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `Media/Carousel/`                                                        | `ImagesCarousel` and `InsightFullscreenImageCarousel` remain the stable composition entries. Platform-neutral `Models` own gallery, selection, focus, and audio presentation policy; `Builders` derive ordered pages and availability; `Services` alone resolve live audio-session, boost, telemetry, and haptic effects through `InsightCarouselDependencies`; `Playback` owns AVPlayer observation and cancellation lifetimes; `Pages`, `Components`, and `Animation` retain mounted playback state, rendering, gestures, and time-derived analysis motion. Carousel views perform no networking or direct live-service lookup, and every production Carousel Swift file stays below the 600-line review guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `AnalyzingContentView` / `ScanningExperienceView`                        | `AnalyzingContentView` supplies the foreground engine's rotating `scanningPhaseText` and live telemetry. Generic `ScanningExperienceView` owns the shared visible scanning contract for foreground and queued work: status pill, optional actionable supplemental content, rotating `DidYouKnowCard`, Field notes, and `ScanInformationCard`. Queue recovery therefore remains ahead of educational content whenever it is present. The animated status pill is constrained to its intrinsic bounds after overlay composition so its accessibility activation frame remains inside the window.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `QueuedContentView`                                                      | Owns queued polling, the one-second/350-millisecond SwiftUI task timing, phrase animation, and recovery interaction wiring while delegating visible layout to `ScanningExperienceView`. `QueuedScanningPresentation` owns phrase/rotation policy, `QueuedContentViewModel` owns retry single-flight and refresh request identity, and `QueuedContentDependencies` owns scheduling, durable row hydration, retry mutation, event, and feedback effects. The view receives only `QueuedScanContext` value data. Ordinary active queued inference reuses `InferenceEngine.genericScanningPhasePhrases`; an exact online live-to-queue handoff continues its ephemeral contextual deck without restarting on queue/save-state changes. Offline, backoff, finalization, and needs-attention states use honest queue-specific phrases. It does not render a separate heading, helper paragraph, media-kind summary, or file-size label. Retry timing, friendly errors, and `Retry now` appear only when actionable. Field notes and telemetry continue to use the queued snapshot and survive completed-result handoff.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `BiologicalView`                                                         | Full biological result: taxonomy, ecology badges, confidence, Wikipedia, habitat/distribution, observation patterns, and lookalike diagnostic. Cards enter with a hardware-gated staggered animation via `CardEntranceModifier`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `NonBiologicalView`                                                      | Simplified result for non-biological subjects (objects, structures); renders its name, description, and retention notice directly on the sheet, followed by a `ScanInformationCard`. The header title resolves to the friendly display label `Non-biological` even when the stored fallback common name is `Unknown Subject` or `Not Applicable`. Local inference error placeholders such as `Network timeout`, `Analysis delayed`, `Approval needed`, `Upgrade needed`, `Retrying shortly`, and `Try another capture` reuse this simple layout but hide the non-biological pill and retention notice because they are recovery, provider-admission, or terminal policy states, not model classifications. Daily quota exhaustion does not enter this router: Capture replaces the root Insight sheet with `PaywallView` before publishing any error `SpeciesData`. `SpeciesData.presentationRole` explicitly separates inference errors from results; display titles cannot change routing. The separate queue-handoff transport blocker is tracked below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `InsightHeader`                                                          | Scrollable header with species name, description, `ConfidenceBadge`, and `ModelTierBadge`, which shows verified complimentary remaining/exhausted state in Results before falling back to the Possible-match upgrade pill. For dog/cat scans with a displayable `SpeciesData.petIdentification`, the large headline uses the pet label while the subtitle remains the scientific name only; otherwise the header uses the normal common-name/scientific-name behavior. Automatically deduplicates its subtitle (scientific name) if it exactly matches the primary title string. Passes `userIdentificationOverride`, `userConfirmedIdentification`, `aiScientificName`, and the optional Ask the Community callback down to `ConfidenceBadge` (and transitively to `ConfidenceExplanationSheet`). Non-biological results display the stable title `Non-biological` instead of exposing unresolved taxonomy placeholders. Accepts an optional `visionTransitionText: String?` parameter: when non-nil, the paragraph slot renders the captured Apple Vision analysis text first, then cross-fades to Gemini `aiReasoning` after 700 ms via an `.easeInOut(0.45)` opacity transition. The species title is hidden initially and springs into view (`opacity 0→1`, `y+10→0`) on `.onAppear` with a 150 ms delay; a `triggerLightImpact(intensity: 0.5)` fires at title entrance and a `triggerSelectionPulse()` fires at the paragraph cross-fade moment. **Alternative names line**: when `alternativeCommonNames` is non-nil and non-empty, a footnote-sized "Also known as: X · Y · Z" line is rendered below the headline as a tappable `Button`; tapping calls `onAlternativeNamesTap` which sets `InsightSheetViewModel.isNamePickerPresented = true` to present `NamePickerSheet`. The common name title itself is also tappable when `alternativeCommonNames` are available — it calls the same `onAlternativeNamesTap` callback, so tapping the headline directly opens the same `NamePickerSheet` as tapping the "Also known as" footnote. |
| `Core/UI/Components/NamePickerSheet`                                     | Display-only bottom sheet (`.medium` detent) presented when the user taps the "Also known as" line in `InsightHeader`. The shared component renders a `NavigationStack` list of caller-provided common names with a checkmark on the active name; it owns no repository or feedback. Pet labels are intentionally excluded by Insight Content. `Content/ViewModels/InsightSheetViewModel+NamePreferences` uses injected Content dependencies to write through `SpeciesPreferredNameRepository`, refresh state, and publish the existing toast/feedback.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `ImagesCarousel`                                                         | Horizontally scrolling mixed-media strip combining live captures, persisted user media pages, and reference images. `ActiveScanMedia` preserves images, videos, standalone audio clips, and descriptions in one stable timeline. A missing video resolves in place to its one retained poster or middle sampled frame; if a submitted user visual becomes unavailable and no usable user visual remains, `Original photo unavailable` is appended after all nonvisual, reference, and loading pages. Intentionally audio/description-only scans never synthesize a photo error. Images and playable videos open `InsightFullscreenImageCarousel`; audio, descriptions, loading pages, and the terminal unavailable state stay out. Page identity remains stable across queued/live/result handoff and asynchronous fallback replacement.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `ConfidenceBadge`                                                        | Tappable liquid-glass capsule showing the AI's confidence band (Strong / Possible / Weak) with a shimmering glare animation; opens `ConfidenceExplanationSheet` on a completed-result tap. When `userIdentificationOverride` is non-nil or `userConfirmedIdentification` is `true`, shows "Confirmed" (green, `checkmark.circle.fill`). **Analyzing mode** (`analyzingPhrase != nil`): background glass layers collapse to transparent, icon switches to `sparkle`, text uses the AI gradient on a minimal capsule border, and the optional private analyzing callback receives the tap without opening the explanation sheet. Label changes use an opacity-only content transition and the capsule width springs to fit the new string. The completed-state glare is painted inside a fixed Canvas, so neither animation creates translated child geometry that can enlarge the Button's accessibility frame. Phrases are auto-suffixed with `...` if not already ending with one.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `ConfidenceSpectrum`                                                     | Visual confidence spectrum with `SpectrumNode` labels; band thresholds derived from `MerianConfig`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ConfidenceExplanationSheet`                                             | Sub-sheet explaining the confidence scale, AI limitations, and tips for improving scan accuracy. When an alternatives-exhausted, override, or confirmed state is active, renders bespoke explanation cards at the top of the modal payload that allow the user to undo, reset, review again, or ask the community for help. **Review-state cards (mutually exclusive):** `AllCandidatesReviewedView` (`alternativesExhausted == true`; user rejected all swipe-deck alternatives), `OverriddenView` (user selected an alternative species), and `ConfirmedView` (user confirmed the AI match). Contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`, `AIMistakesBanner`, and `ProTips`. The `ProTips` component evaluates `RevenueCatManager.shared.isProActive` to conditionally render a premium upgrade trigger that opens `PaywallView` for free-tier users.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `ModelInfoSection`                                                       | Informational card inside `ConfidenceExplanationSheet` showing which Naturebook AI tier processed the scan. Standard tier (`inferenceTier == nil` or `"flash"`) renders a blue `cpu` icon with a gray "Standard" capsule badge. Pro tier (`inferenceTier == "pro"`) renders an indigo `sparkles` icon with an indigo "Pro" capsule badge and a "Powered by Gemini 2.5 Pro" footnote. Positioned between `ConfidenceSpectrum` and `AIMistakesBanner`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `CandidatesCard`                                                         | Identification candidates card with a multi-state approve/deny and Community handoff UX. Shown only with policy-visible candidates from `CandidateReviewVisibilityPolicy`, not raw `speciesData.candidates`. Hidden after confirmation, override, or alternatives exhaustion; when `alternativesExhausted == true`, `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` replaces the card with a condensed summary, Review again, and Ask the community affordances.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `TaxonomyCard`                                                           | Collapsible card showing the full Linnaean tree. Also reused by the Explore detail page when public taxonomy data is available.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `SimilarSpeciesGallery`                                                  | Horizontally scrolling carousel of lookalikes sourced from `speciesData.similarSpecies` in Insight and from public `similar_species` on Explore detail. Each `SimilarSpeciesCard` renders `referenceImageUrl` via `AsyncLocalImageView` when available, or asynchronously falls back to `SimilarSpeciesImageFetcher` (Wikipedia → GBIF waterfall). Image load failures never remove a card — on failure the card falls back to a leaf-icon placeholder so species names remain visible. Cards are excluded when their `scientificName` is blank, when they duplicate the active species scientific name, or when the same scientific name appears twice. If a lookalike shares the active species' common name, the gallery suppresses the duplicate common-name label and lets the scientific name carry the distinction. Insight, Explore detail, and Species Dictionary pass `routeForSpecies` builders so cards push `SpeciesDictionaryPageContentView` in the current sheet/navigation stack, preferring `speciesId` when present and falling back to scientific name. The card no longer renders relation rationale copy; it stays focused on image, common name, and scientific name.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `OverviewCard`                                                           | Structural card rendering dynamic biological metrics (e.g., size, life stage, sex with supporting cue/confidence, interactions, and conservation). Invasive status is grouped into a compact local summary: the primary `Invasive` / `Not invasive` value, an optional assessed-region and confidence detail line, and an optional `WHY NATUREBOOK THINKS THIS` rationale note from the original AI assessment. The card then shows an 8-line truncated Wikipedia extract and a built-in Safari "Learn more" button when available.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `InsightChatSheet`                                                       | Shared bottom-sheet Field chat. For completed biological, non-human Insights, a valid toolbar tap presents the loading shell immediately; the sheet then preflights ownership through `/check-scan-status` before using `/insight-chat`. Explore post details reuse the same floating `FieldChatToolbarButton`, sheet, and view model with `/explore-post-chat`. Every loaded canonical Species Dictionary page uses a third source with `/species-dictionary-chat`; loading/error states hide its bottom bar, while Share stays at top. Each Explore or Dictionary thread belongs only to the requesting viewer, and Non-Pro users open the existing paywall. The sheet renders saved messages, deterministic/AI prompt chips, in-memory offline reading, durable failed-send retry/edit, safety refusal styling, answer feedback, deletion, and an anchored composer. Owner-only Insight actions such as append-to-notes, feature feedback, identification review, and reanalysis are disabled for Explore and Dictionary threads. Backend context stays source-specific and text-only. Dictionary product telemetry omits species names and IDs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `ScanInformationCard`                                                    | Privacy-aware spatiotemporal context card. Reads `ProfileViewModel.defaultGeoprivacy`: `private` hides location/elevation/weather/map, `obscured` shows sanitized location plus rounded map region, and `open` may show exact owner-facing location context.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `GBIFHeatmapMapView`                                                     | SwiftUI `View` that composites two images to render a full-world GBIF occurrence heatmap natively. (1) A static `world-map-base` custom Mapbox topography background image, entirely eliminating MapKit CPU overhead. (2) The GBIF density zoom-0 tile (`/0/0/0@2x.png`) — a single 512 px PNG covering the entire world in Web Mercator — is fetched and drawn on top. Both images perfectly align their projection/extent. Features a custom `UIViewRepresentable` bridge (`PinchPanOverlay`) which unlocks elastic 2-finger pinch and pan exploration. This gesture controller safely locks down the encompassing parent `ScrollView` and engages `.interactiveDismissDisabled` on the bottom sheet to prevent SwiftUI swipe cancellation conflicts during map manipulation. The same map primitive is also reused by Explore's public habitat/distribution card on the post detail page.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `HabitatAndDistributionCard`                                             | Habitat and distribution card: encyclopedic habitat text. Has three states: (1) **Loaded** — habitat text; (2) **Loading** — shimmer skeleton shown while `inferenceEngine.isEnrichmentLoading` is `true`; (3) **Retry** — data missing, tap to re-trigger `fetchAndApplyEnrichment`. Reads `habitatDescription` and `scientificName` directly from `inferenceEngine.speciesData` (not passed as parameters) so the card directly tracks `@Observable` changes on `speciesData` and re-renders the moment enrichment writes to it, independent of any parent view re-render timing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `SpeciesObservationChartsCard`                                           | Reusable Swift Charts card rendered after Habitat & Distribution for known biological species. `SpeciesObservationStatsViewModel` coordinates loading, `SpeciesObservationStatsDatabaseActor` fetches local SwiftData projections off the main actor, and `SpeciesObservationStatsReducer` computes on-device aggregates before combining them with cached global public iNaturalist stats from `/species-observation-stats`. Tabs are Seasonality, History, and Life Stage; per-scan sex is shown in `OverviewCard` instead.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `ToxicityBanner`                                                         | Glassmorphic hazard warning banner shown when `insightData.hazardType != "none"`. Implements a premium liquid-glass design using `.regularMaterial` and dynamic tinting (`.red` for severe threats like venomous/poisonous, `.yellow` for allergens/irritants), explicitly constrained using `maxWidth: .infinity` full-bleed bounds. Displays hazard-specific copy.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `ConservationBanner`                                                     | IUCN Red List status banner                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `FieldTripProgressCard`                                                  | Persistent server-backed **Field trips** card for a saved biological scan's standard-outing and Event credits. It uses the shared `InsightCardHeader`, an uppercase completion eyebrow, a headline-sized goal, an experience-only subtitle, enlarged goal artwork, a green completion badge, and a prominent `GoalProgressRing`; every contribution remains visible as its own row. A row pushes the owning experience's Goals overview without carrying Capture's checklist focus, and native Back returns to the Insight.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `MilestoneToastBanner` / `MilestoneToastPresenter`                       | Shared bottom in-app milestone notification for Field trip progress, achievement unlocks, and `New to Naturebook`. `ScanMilestoneCoordinator`, not the Insight lifecycle, batches scan milestones after remote progress finishes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

---

### Shell ownership boundaries

The root Shell is organized into `Models`, `Services`, `ViewModels`, `Views`,
`Components`, and `Modifiers`. Deterministic presentation identities and display
values live in Models. `InsightShellDependencies` in Services is the sole Shell
owner that resolves `MerianNetworkClient`, authentication, repositories, app
routing, feature access, badge updates, and haptic feedback. It projects those
live implementations into narrow initializer-injected closures; Shell views and
view-model extensions do not resolve endpoints or shared managers directly.

`InsightContentPresentation`, `InsightShellPresentation`, and the supporting
display/load-key values are platform-neutral Models. The root view model keeps
stored state, initialization, and reset in `InsightSheetViewModel.swift`, then
splits lifecycle, record mutation, capability policy, content presentation,
media presentation, and presentation identity into named extensions. The
optional trailing `InsightShellDependencies` parameter defaults to `.live`, so
existing callers preserve their initializer contract while tests supply
deterministic closures.

`InsightSheetView` and `InsightContentView` remain the stable composition entry
points. Focused extensions own their content and Shell presentation hosts,
bindings, lifecycle attachment, toolbar, chat actions, content/toast routing,
queued handoff, and Explore-composer responsibilities while the views retain
gallery, scrolling, focus, animation, and dismissal timing. Every production
Shell Swift file remains below the 600-line review guard.

`Sharing/` mirrors that boundary below the Shell. Platform-neutral Models own
Share copy and action projection; Services alone adapt the live publication,
Community request, detail, share-state, cache, app-event, and feedback effects;
focused root-view-model extensions own mutations and reconciliation; and the
observable Community request view model owns only its draft/load state. Views
and Components retain sheet, focus, selection, and action-generation timing and
perform no networking. The existing `InsightShareButton`, Community request
sheet, root view-model action, and route signatures remain stable, and every
production Sharing Swift file stays below the 600-line guard.

Mirrored tests live under `MerianTests/Features/Insights/Shell`, `Content`,
`FieldNotes`, `Media`, and `Sharing`. `InsightShellArchitectureTests` enforces
the folder shape, deterministic Models, live-service confinement, no networking
in views/view models, aggregate-file removal, and the file-size ceiling.

## Progressive Analyzing Pill

For foreground visual scans, `AnalyzingContentView` continues to read only
`InferenceEngine.scanningPhaseText`. The engine now progresses that value from
generic visible analysis to a qualifying broad Apple Vision category, then to
five bounded image-specific dominant-color, saturation, lighting,
light-contrast, and surface-detail cues from the current deterministic local
extractor. The category handoff is immediate; later automatic label changes use
the shared 2.3-second clock. A future eligible Foundation Models provider may
replace the deterministic trait deck with richer visible cues. Source priority
is monotonic, so generic or category text never returns after more-specific
trait context arrives. The pill shows every phrase in its active deck before
wrapping to the first phrase for a new round.

Visible trait strings are natural verb-led observations such as **Analyzing gray
and green colors**, **Reviewing softly colored areas**, and **Observing light
and shadow areas**, never labeled `Color: description` fields. Trait kinds and
numeric buckets stay internal and only select the visible wording; midpoint copy
never says **moderate color levels** or **balanced light and dark**.

The pill does not claim a species, confidence, candidate match, records lookup,
range check, or completed cloud result. Deterministic local analysis is limited
to five complete, unique labels of at most 36 rendered characters; the future
Foundation stream remains limited to three. Partial stream snapshots and invalid
identity-bearing text never reach SwiftUI. Gemini remains the only source for
the completed identification and Insight content.

`ConfidenceBadge` keeps the same opacity-only text transition and intrinsic
capsule composition. The deterministic `-seedProgressiveAnalyzingFlow` UI
fixture advances generic → category → trait on explicit badge taps and verifies
that the native Button's accessibility frame remains inside the application
window at every label width.

Unsupported devices silently retain Vision plus deterministic image-trait
wording. The Xcode 26.6 build injects a no-op Foundation visual-cue provider;
stable Xcode 27 is a prerequisite for the availability-gated generative
multimodal implementation. Low Power Mode, serious/critical thermal pressure,
inactive app state, unavailable or not-ready Apple Intelligence, result arrival,
and every scan-ownership handoff all suppress or cancel the richer stage without
changing the visible fallback.

Daily-quota presentation is normally decided before Insight exists. Online
Capture runs the caller-scoped scan-admission preview before the camera shutter,
audio recorder, or staged submission begins; an exhausted allowance opens the
root `PaywallView` while preserving staged input. Insight's exact
`ai_quota_daily_exceeded` handler is retained only for authoritative
post-preview races, and it replaces the sheet without publishing a synthetic
result. The preview has a two-second no-wait/no-retry transport bound. A
classified connectivity failure plus local eligibility selects queue-only, so
the observation is saved without opening an analyzing Insight or creating a
foreground inference generation. Cancellation, malformed data,
authentication/TLS, and server failure block new processing with retry feedback
instead of allowing an unverified request to reach Insight.

## Embedded Field-trip Completion Route

Completed standard-outing goals reuse the existing Insight surface instead of
presenting a second sheet. The authenticated Field trips catalog/detail payload
supplies an optional private `completed_scan_id`; `ExploreView` resolves that ID
to a device-local `LocalScanRecord` and appends `ScanInsightRoute` to its
current `NavigationPath`. The destination mounts first; `LocalScanInsightLoader`
then performs the exact record lookup and engine hydration before constructing
the Insight content.

The destination constructs `InsightSheetView` with
`InsightPresentationStyle.embeddedInScansLibrary`, disables another Explore
presentation, hides the bottom tab bar, and uses the feature-local back arrow
and interactive back gesture. Back returns to the existing outing detail and
sheet state. No Field trips payload supplies or downloads media. If the local
record cannot be found, Explore shows the non-destructive unavailable message
and does not push an empty Insight route.

## Persistent Field Trip Progress Card

`InsightSheetViewModel` loads `field-trips` action `scan_contributions` whenever
the persistent scan ID or authenticated account identity changes. Including
authentication state and account ID in the SwiftUI task key makes a cold-launch
presentation retry automatically when Supabase finishes restoring its cached
session, and clears/reloads correctly on sign-out or account switching. The read
is attempted only for authenticated, saved biological Insights while Field trips
are enabled. Queued scans, non-biological results, missing IDs, unauthenticated
sessions, empty responses, and network failures render no placeholder or error.
Event rows are presented alongside standard outing contributions.

The card is rendered after toxicity and identification-review content and before
Field notes and educational cards. Its visible header is **Field trips**. It
shows all returned contributions without collapsing or selecting a primary
experience. Rows have no separators or disclosure chevrons: each uses an
uppercase **GOAL COMPLETE** eyebrow above the standalone goal name, followed by
the experience title and credited level. Enlarged exact goal artwork and a green
completion badge lead the row; a prominent trailing ring shows the credited
level's current count. The entire row remains the navigation target. Its
VoiceOver label follows the form
`Butterfly or moth goal complete in Park Pollinators, 3 of 4`. The card adds no
haptic, confetti, or milestone notification; the existing transient milestone
queue remains the only immediate celebration surface.

Each row carries a typed `CaptureGoalDestination`. Standard outings open the
template detail focused on the credited checklist item; Event rows open the
challenge detail. An Insight already embedded in Explore reuses that navigation
stack. A root modal Insight dismisses/routes through its optional
`onOpenCaptureGoal` callback so it does not build a second Explore stack.
`fieldTripScanContributionsInvalidated(scanId:)` reloads only the matching open
Insight after scan progress or correction completes. Contributions are never
cached in SwiftData in this release; historical reopening always asks the
private server read model.

## Data Source

`InsightSheetView` reads everything from `InferenceEngine.shared.speciesData` (a
`SpeciesData` struct). It does NOT own a copy of the data — it observes the
engine directly via `@Environment(InferenceEngine.self)`.

`InsightSheetViewModel` holds a reference to the `InferenceEngine` and exposes
computed properties:

### Audio subject presentation

Audio does not add a content-router state or client DTO. A Human-only result has
`isBiological == true`, routes through `BiologicalView`, and presents canonical
`Human` / `Homo sapiens`. Confident non-human presence without a resolved taxon
also remains biological and displays **Unidentified Wildlife**, but
`presentationConfidenceScore` is `nil`, candidates and reference imagery are
suppressed, and reanalysis remains available when source media survives. A true
non-biological audio result routes through `NonBiologicalView` and displays **No
wildlife detected** with the ordinary non-biological retention behavior.

`HumanSubjectIdentityPolicy` recognizes structured common-name, scientific-name,
and override aliases including malformed `Homo sapien`; it never searches AI
reasoning. Historical `Unknown Subject` / `Taxonomy Unavailable` audio keeps its
stored values and receives safe unresolved presentation only. No SwiftData
field, schema version, or migration is introduced.

### First-result presentation boundary

For a live-camera still scan, `InferenceEngine` commits `speciesData` only after
the response has parsed and the local scan/media write succeeds. It does so
before award calculation or Field trips. Field trips remain gated on
`/check-scan-status` confirming server ingestion, and optional enrichment may
fill cards later without blocking the initial result.

`InsightSheetView` records tap-to-first-render with a one-shot 1x1 UIKit draw
probe installed on the result hierarchy. The measurement closes only after an
actual display pass; `speciesData` assignment, `onAppear`, or a SwiftUI task
yield is not an acceptable substitute. This keeps the release target of
response-to-first-render p95 at or below 300 ms tied to user-visible output.

The one-time Explore onboarding recommendation is delayed by a stored,
cancellable main-actor task keyed to the exact scan ID and presentation
generation. Re-evaluating the same result does not restart its three-second
clock. Reset, record replacement, non-biological/error resolution, or task
cancellation clears ownership; the task revalidates share eligibility and the
one-time setting before mounting the sheet. It assigns presentation state
directly so a producer-level animation transaction cannot redraw the Insight
hierarchy.

`SpeciesData.isNewDiscovery` remains the local "new to this user" signal for
stats, persona, firefly progress, and achievement calculations. It no longer
drives a user-facing Insight celebration. `SpeciesData.isNewToMerianDictionary`
is the separate global dictionary contribution signal returned by the identify
Edge payload. `ScanMilestoneCoordinator` evaluates that flag for the final saved
scan after the Field trip progress attempt and appends **New to Naturebook**
after any standard outing progress, Seasonal Challenge progress, and newly
unlocked achievements. The Insight lifecycle retains VoiceOver/result haptic
work but does not enqueue the dictionary milestone, preventing repeated sheet
appearances from duplicating it. Error placeholders created by local fallback
handling have no scan ID, preserve their sentence-case title such as
`Network timeout`, and never show non-biological collection or retention
messaging. That timeout placeholder is reserved for direct work without a
durable queue owner. An exact queue-backed connectivity failure instead binds
the matching `OfflineQueuedScan` snapshot and routes the sheet to `.queued`.
Queue-owned foreground transport has a 15-second safety deadline so a
path-satisfied but silently stalled connection cannot keep the sheet analyzing
for the direct caller's 90-second window. An exhausted queue-backed service
failure uses **Analysis delayed / Scan saved** and now satisfies
`isInferenceErrorPlaceholder`, so the simple renderer cannot apply
non-biological success treatment to an operational failure. The
transport/ownership source boundary is now protected; exact-SHA and
physical-device closure remain release-blocked by the
[live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md).

The exact Identify replay conflicts `ai_request_in_progress`,
`ai_request_already_completed`, `scan_already_complete`, and
`scan_already_finalized` use the distinct **Restoring scan** placeholder. Its
customer copy explains that the scan was safely saved and is being restored; it
is not presented as connectivity loss. The engine retains the exact presentation
scan ID so either a background Identify response or status-recovered
`LocalScanRecord` can replace the placeholder, but a stale completion can never
publish over a newer scan.

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
    // Returns [] when speciesData.shouldSuppressReferenceImages — blocks Wikipedia/GBIF
    // reference images for humans, Felis catus, and Canis lupus familiaris.
    // totalImages derives from refUrls, so the carousel page count drops
    // automatically with no additional call sites to update.
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
var canReviewIdentificationConcernCandidates: Bool { /* stored candidates for explicit Field chat ID concerns */ }
var canConfirm: Bool       { guard queuedContext == nil else { return false }; /* reviewAlternativeCandidates is non-empty */ }
var canShareToExplore: Bool { /* resolved non-Human biological identity in both active result and record */ }
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

Historical unresolved biological placeholders (`Unknown Subject` /
`Taxonomy Unavailable`) are treated as compatibility data, not valid
identifications. They suppress visible AI confidence, reference-loading carousel
pages, and Explore sharing until reanalysis produces a resolved biological
result. The local programmatic share guard returns
`Reanalyze this scan before sharing to Explore.` for those records.

**Name preference methods** (all routed through
`SpeciesPreferredNameRepository`, keyed by scientific name):

- `loadPreferredCommonName(for:modelContext:)` — reads `UserSpeciesPreference`
  into `preferredCommonName`. If a legacy `SpeciesPreferredNameStore` key is
  encountered, the repository promotes that value into SwiftData and removes the
  legacy key only after the save succeeds; called from
  `InsightSheetView.task(id: scanId)` when a new species loads.
- `setPreferredCommonName(_:for:modelContext:)` — writes
  `UserSpeciesPreference`, clears any stale legacy key only after
  `modelContext.save()` succeeds, updates `preferredCommonName` in-memory
  (triggering `@Observable` recompute of `resolvedHeaderTitle`), and fires a
  `toastMessage`.
- `clearPreferredCommonName(for:modelContext:)` — deletes the SwiftData row,
  clears any stale legacy key after save, and nils `preferredCommonName`,
  reverting the headline to the canonical DB name.

`SpeciesPreferredNameRepository` intentionally remains separate from
`AppSettings`: preferred names are per-species keyed data, not global UI state.
`MerianApp` runs `migrateLegacyPreferences(modelContext:)` after SwiftData
bootstraps, promoting all legacy `speciesPreferredName_*` keys and deleting them
only after a successful database save. The repository then syncs SwiftData rows
to Supabase `user_species_preferences`; clears are retained as pending local
delete timestamps until a remote `deleted_at` tombstone is confirmed. Sync
triggers from auth restore, foreground activation, and local edits are
single-flight, so only one preferred-name cloud reconciliation is active at a
time; mid-flight triggers record a trailing follow-up request so edits saved
after the active sync's local fetch still flush before the coalesced task
completes. Clean lifecycle/auth syncs skip when a successful sync completed in
the last 60 seconds, while local edits force the sync path.
`SpeciesPreferredNameStore.syncDiagnostics` records the latest
attempt/success/status/message plus pushed/pulled counts for support. Explore
feed, map, detail, comments, and share text resolve display names through an
`ExploreFeedViewModel` cache hydrated from the SwiftData-backed repository using
the current `ModelContext`. The network DTOs in `ExploreAPIModels` stay pure
decode models and never read `UserDefaults` directly; the legacy
`SpeciesPreferredNameStore` remains only as migration input, cloud-delete
tombstone staging, diagnostics, and lazy fallback if a pre-migration key is
discovered later.

Pet labels are not species preferences. They are scan-level metadata decoded
from `SpeciesData.petIdentification` / `LocalScanRecord.petIdentificationData`
and may change from scan to scan even when the scientific name is the same.

`InsightSheetView` also queries SwiftData directly via `@Query` for non-deleted
`[ScanCollection]` rows (reverse-sorted by `createdAt`) to populate the
collection management toolbar. Its predicate excludes the durable
`isPendingDeletion` application tombstone so a collection pending remote
deletion does not reappear in the add-to-collection menu. Active V50 maps that
property to the released `isDeleted` column with `@Attribute(originalName:)`, so
the filter remains effective after save/refetch and reopening the store. The
complete contract is described in
[Collections](./07-feature-modules-and-ui.md#collections-top-level-photo-albums).
The released V50 schema is the historical source for this rename: its
`isDeleted` field is preserved in the frozen migration snapshot and is never
read by current UI code.

Explore share state in the bottom toolbar uses a two-step hydration path.
`InsightSheetViewModel.fetchLocalRecord(for:modelContext:)` first restores
`sharedExplorePostId` from the per-scan `UserDefaults` cache so the button can
immediately render `View post` on same-device relaunch.
`InsightSheetView.task(id: scanId)` then calls `/get-scan-explore-share-state`
in the background and reconciles that authoritative server answer back into the
same cache. The server response only reports a live Explore post when the post
has saved public `explore_post_media`; any historical or invalid media-less row
clears the local post cache instead of opening a phantom post. It also carries
the saved post-level `location_sharing` for live posts, or the scan's current
geoprivacy as the default for new shares, so the share/edit composer can hydrate
Open, Obscured, or Private without mutating the underlying scan. This keeps the
toolbar fast on-device while also correcting stale cache after reinstall,
cross-device share/unshare, failed media publish, or remote visibility changes.

The reconciliation state belongs to
`Sharing/ViewModels/InsightSharingOperationState.swift`. Each authoritative read
captures one request token and the current same-scan mutation revision.
Replacement reads, sheet reset, record replacement, and successful publication
or Community mutations invalidate an older read before it can update the open
Insight. `Sharing/Services/InsightSharingDependencies.swift` is the only Sharing
declaration that resolves the live endpoint, local share-state cache, app-event
publisher, preferred-name repository, or haptic feedback.

The completed `InferenceEngine.speciesData.scanId` is the action presentation
authority. `presentedSpeciesScanId` returns a value only when any active
local-record ID and toolbar snapshot identify that same scan. Explore requires
all three identities before enabling publication. If asynchronous SwiftData
lookup targets a different scan and misses, the view model clears stale
scan-bound post, Community, notes, media, and action state; a same-scan miss
retains its immutable snapshot during context propagation. Field Chat captures
the exact selected ID, presents its loading shell synchronously, passes the ID
into cloud preflight, fences every await, and dismisses if the engine changes
scans.

Persisted-record actions additionally require `presentedLocalRecordScanId`,
which proves the engine result, active model, active-record ID, and toolbar
snapshot all agree. A monotonic presentation generation invalidates older
asynchronous publication, post-edit, Community, and field-note callbacks. Sheet
reset advances rather than zeroes the Explore request/revision clocks, so an A →
B → A cycle cannot make an older response token numerically current.
Record-bound collection, reanalysis, identification review, and deletion actions
independently carry or recheck their expected scan ID; candidate dismissal
requests additionally capture the engine presentation generation. The Explore
and Community editors, Field Notes editor, New Collection alert, and delayed
Explore onboarding prompt capture both the scan ID and presentation generation.
Nested Share receives that parent generation and compares it directly on every
callback, including before `onChange` cleanup. The toolbar captures one
immutable scan/generation target for collection, export, Field Chat,
identification, share, review, reanalysis, and deletion callbacks instead of
rereading the engine when a menu callback finally runs. Media-carousel
observation taps, audio-boost bindings, local-gallery sheets, Wikipedia/Safari
sheets, common-name selection, candidate modals, Explore composer submissions,
and toast actions retain that same exact target. Parent Field Chat close/toast
callbacks also require the generation that opened the thread. A
queued-to-completed handoff advances the generation even when the UUID is
unchanged, invalidating callbacks rendered by the queue presentation before
result controls become active. The delayed bottom toolbar reveal and Field Notes
synchronization tasks are therefore keyed to that generation rather than
`persistentScanId`; queued and completed presentations intentionally share the
UUID, so an ID-keyed task canceled during promotion would not restart to expose
Field Chat, Share, or completed notes. Presentation dismissals clear only the
matching captured target, never an editor, gallery, Safari page, candidate
review, or chat opened by a newer render. Same-scan Explore and Community
mutations also retain the exact post/request UUID across their await. The
advisory post-detail projection preserves the last confirmed or optimistic Field
Notes visibility when that read is unavailable or echoes a different post UUID.
Community editor hydration likewise requires the decoded detail to echo the
requested request UUID; a mismatch preserves the current draft and follows the
normal invalid-response feedback path.

`InsightContentView` maps its independently-owned destination state into one
typed `InsightContentPresentation`. Safari, report, Community request, Explore
composer, candidate review, Field Notes, and observation description share one
item-based sheet host; the media gallery uses a full-screen binding filtered
from that same mutually exclusive value. Destination callbacks keep their
existing scan and generation fences, but no destination may add a sibling sheet
modifier to the Insight content root.

The outer `InsightSheetView` has a separate single typed slot for paywall,
Field-trip author, Field Chat, Explore onboarding, and Explore. It retains at
most one validated follow-up while UIKit tears down the active sheet and mounts
that value only from the active sheet's real `onDismiss`. Field Chat and Explore
retain their captured scan ID and presentation generation through dismissal;
stale, replaced, or disallowed requests are cleared instead of creating a second
presenter. `SwipeableCandidateCard` follows the same local rule for its original
capture, candidate gallery, and distinguishing-feature sheets.

The delete alert captures its target when opened. `ReportInsightViewModel`
rejects issue submission unless its supplied scan still matches the engine
result, before either the remote report or local flag can mutate. Its completion
also requires the captured engine presentation generation, so an A → B → A cycle
cannot dismiss or confirm the newer report sheet. A callback from an older
render can therefore neither mutate the prior observation accidentally nor apply
its state to the new presentation, including an A → B → A switch where the same
UUID returns under a newer presentation.

Identification hydration and persistence carry the original scan, scientific
name, presentation generation, and latest review-action generation through
dictionary, enrichment, Wikipedia, and GBIF awaits. Local/cloud review writes
and the species-metadata writes they trigger drain through one serial tail. If
an older write has already begun, the newer choice waits behind it and remains
the final durable writer; if it has not begun, its stale generation rejects it.

The Share sheet routes low-confidence biological scans through Identify by
default. A Strong AI result uses the configured inference-tier threshold (Flash
`>= 0.95`, Pro `>= 0.85`); anything below that, or a missing confidence value
from restored state, defaults the primary Share action to **Ask the Community**
when image media is available. User-confirmed identifications, manual user
overrides, existing feed-visible posts, and community-resolved requests ready
for owner publication keep **Share to Explore** as the primary path. A direct
low-confidence Explore publish remains available before an Identify request
exists, but it requires an explicit warning confirmation.

Both actions require a resolved non-Human biological identity in the active
result and persisted toolbar snapshot. Human aliases and unresolved taxonomy
therefore suppress the Share/Community entry points even when audio or other
user media is available. `/share-scan-to-explore`, reused by the Community
route, independently repeats that owner-row eligibility check.

`TopToolbar` also exposes **Ask the Community** beside the identification
actions when `canRequestCommunityIdentification` is true. The CTA opens
`Sharing/Views/Community/CommunityIdentificationRequestSheet`, where the user
can add an optional note and choose the same Open/Obscured/Private post-level
location sharing used by Explore sharing. The sheet delegates existing-request
detail hydration to its generation-fenced Sharing view model, whose injected
Service closure owns the endpoint call. Submission calls
`/request-community-identification`, creating or reusing the scan's Explore post
and flagging it as a `needs_id` community request. That post is then marked
`community_needs_id` in `explore_observation_projection` and hidden from the
normal Explore feed/map/author/hashtag projections. Resolved community requests
remain public inside Identify, but they do not enter normal Explore surfaces
until the owner explicitly publishes them afterward.

Taxonomy resolution and audible-media moderation complete before one final
`request_community_identification_atomically(...)` mutation. The post/media
snapshot and hidden request commit together; a late request or projection
failure restores the prior post instead of leaking a normal Explore item.
Reopening withdrawn state begins a fresh consensus generation while preserving
withdrawn vote history. A write-time `needs_id` recheck also prevents a
concurrent direct share from returning success after a Community request wins.

If an Insight-originated action finds that the authenticated owner's cloud row
is absent, `MerianNetworkClient` first polls `/check-scan-status`. Active or
retryable ingestion remains authoritative, and known moderation/provider-policy
rejection is not repaired. Eligible legacy drift uses the single-request
`recovery_scan` contract to recreate only bounded non-media fields; server
species IDs are resolved by scientific name instead of trusting local-only
UUIDs.

The media step then remains endpoint-specific. Direct Explore sharing combines
`recovery_scan` with staged local image, video, or audio keys in
`/share-scan-to-explore`. Ask the Community repairs the row through
`/check-scan-status`, uploads saved local image paths or the active live image
buffer to staging, and retries `/request-community-identification` with
`restored_object_keys`. Field Chat uses status recovery without publishing media
before it presents `/insight-chat`. No path directly upserts `public.scans` from
iOS, and a transient still-syncing result stays retryable instead of permanently
marking Field Chat unavailable. The Ask affordance is gated on actual user image
media, not a padded display count, so image-less historical/text scans cannot
enter a request that the server cannot publish.

Customer feedback stays at the feature boundary:

- Explore missing row: “This observation is still syncing. Please wait a moment
  and try sharing again.”
- Explore internal boundary: “Explore is temporarily unavailable. Please try
  again in a few minutes.”
- Field Chat: “This observation is still syncing. Please try Field chat again in
  a moment.”

Raw database authorization text is never customer-facing. The complete joined
behavior is maintained in
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

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

`InsightSheetView` supports viewing pending `OfflineQueuedScan` records from the
library grid. A critical constraint is that **no live `@Model` reference may be
held** after the scan is deleted from the SwiftData context — accessing any
unfaulted attribute on a deleted `@Model` crashes with
`"backing data was detached from a context without resolving attribute faults"`.

Two value-type structs encapsulate all data the insight chain needs at snapshot
time, while the `@Model` object is live:

| Type                 | Purpose                                                                                                                                                                                                                                                                       |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `QueuedScanSnapshot` | Grid value containing identity, cover/media snapshot, queue state, retry presentation fields, timestamp, and an internal approximate-byte estimate. Used by `LazyVGrid` so no tile holds a detached `@Model` reference.                                                       |
| `QueuedScanContext`  | Richer Insight-route value containing captured media, queue/retry state, telemetry, focus descriptors, and internal diagnostics. It is initialized from a live `OfflineQueuedScan`, then read through `capturedMediaSnapshot` so queued UI never retains the SwiftData model. |

`InsightSheetViewModel.queuedContext: QueuedScanContext?` stores the context.
All computed properties (`isProcessing`, `contentMode`, toolbar flags, carousel
sources) switch on `queuedContext == nil` rather than accessing any `@Model`
attribute after initialization.

**`gridId` namespacing**: `LocalScanRecord.id` and `QueuedScanSnapshot.id` share
the same UUID value (`client_scan_id`). Without namespacing, `LazyVGrid`'s
`ForEach` produces duplicate `AnyHashable` keys. `QueuedScanSnapshot.gridId`
returns `"q_\(id)"` so queued-scan tiles always have a distinct key from their
eventual `LocalScanRecord` counterpart.

Historical completed scans follow the same value-boundary rule.
`InferenceEngine.load(from:)` may receive a live `LocalScanRecord`, but async
hydration must operate on copied scalar values. Reference-image URLs, candidate
blobs, taxonomy primitives, and IDs are snapshotted before the hydration `Task`
starts; the task must not read the live model after suspension, because the scan
can be deleted or detached while the Insight sheet is dismissing.

### Queued Retry Presentation and Wake

`QueuedContentView` treats `queueNextRetryAt` as a durable eligibility boundary,
not proof that work is actively running. On presentation it asks through
`QueuedContentViewModel` and `QueuedContentDependencies` for the live scheduler
to restore the earliest persisted wake. While visible, the view advances a
one-second reference clock; the injected Service snapshots the queued row
through a fresh `ModelContext`. This makes deadline removal,
`.staged → .inferencing` claims, failures, and reschedules observable without
retaining a live `OfflineQueuedScan`. The view also retains the exact
350-millisecond explicit-retry refresh task. Request identity in the view model
prevents an older completion from clearing a replacement retry.

`QueuedRetryPresentation` resolves all customer-facing retry state. It maps
stable queue/server codes to safe explanations and never displays the stored raw
error message. Direct and inference-prefixed HTTP `402` codes resolve to the
same entitlement explanation and **View plans** action. A future online deadline
explains why analysis paused, shows a live automatic-retry countdown, and
exposes **Retry now** when another attempt can help. Offline work explains that
the connection was interrupted and that retry resumes when it returns, with no
numeric countdown or **Retry now** action. A dedicated local navigation action
such as **View plans** may remain available offline because it does not dispatch
queue work. Once a deadline elapses, the helper and retry action disappear; the
analyzing state already communicates that work is underway. Consent,
entitlement, missing-media, and terminal states use their dedicated explanation
or action rather than a misleading retry.

`ScanQueueState.isManualRetryEligible` is the single state/deadline baseline
used by `QueuedScanSnapshot` and `QueuedScanContext`. This value-level agreement
keeps the grid and Insight route from drifting, but it does not authorize a
mutation: retry services re-fetch the current SwiftData row, and
`QueuedRetryPresentation` may further suppress the action for connectivity or a
reason-specific state.

The queued presentation otherwise follows the same visible scanning contract as
foreground inference: a rotating status pill, `DidYouKnowCard`, Field notes, and
`ScanInformationCard`. When queue recovery is actionable, its retry timing,
error, and control block is inserted directly after the status pill and before
`DidYouKnowCard`. `QueuedContentView` rotates honest phrases from the exact
queued state and reuses the engine's generic scanning phrases while the server
is processing an ordinary queued scan. It intentionally omits a separate
heading, explanatory paragraph, media-kind summary, and approximate-byte label;
the copied media and byte fields remain internal routing and diagnostic data.

This view also owns the presentation half of the required live-to-queue handoff.
The engine accepts an active visual transfer only for the exact scan ID and
attempt generation owned by its typed visual-presentation session. It keeps the
current phrase first, consumes every unseen phrase before revisiting seen copy,
and retains presentation-owned `ActiveScanMedia`. A prepared visual transfer
gets the full generic deck without live media; audio and Describe transfers use
their existing nonvisual copy. Failed ownership checks expose no contextual
phrase or media. Queue upload, server state, persistence, and offline/online
changes do not restart the active visual cursor. **Waiting for connection** is a
temporary overlay and consumes no deck entry. The transition adds no
saved/continuing explanation, emits no error haptic, and preserves normal
same-ID completed-result promotion.

The same ownership rule applies to the carousel presentation. An exact live
visual handoff keeps its overlay mounted through pending, uploading, staged, and
inferencing queue states, while ordinary queued scans animate only during
inferencing and failed, external-import, completed, or attention-required states
remain still. The shell continues passing the canonical scan ID and the engine's
in-memory `ActiveScanMedia`, preserving the selected page, native page
controller, decoded image, and focus state instead of replacing them with the
new queue path. The time-derived scan sweep session lives above the conditional
overlay and resets only for a different canonical scan or a later analysis after
completion; Reduce Motion remains fixed at the sweep midpoint.

`TopToolbar` likewise keeps one trailing item mounted. Before a durable queued
ID exists, a clear 44-point non-control placeholder reserves its layout; no
native button is mounted. On iOS 26, the item's shared toolbar background is
also hidden while the placeholder is active because the toolbar item itself can
otherwise draw empty Liquid Glass even when its child content is clear. Binding
the exact queued row restores automatic toolbar glass, inserts the delete button
with a 0.2-second opacity transition, and exposes `InsightQueuedDeleteButton`;
tapping it retains the existing queued **Cancel upload & delete** confirmation
and deletion semantics. The queued delete button and completed-result actions
menu explicitly use circular border shapes. No second toolbar item or sheet
relayout is introduced.

The engine half remains release-gated, with its source behavior now remediated.
The queue manager can retire durable foreground ownership as soon as the path
becomes unsatisfied, before URLSession's error reaches the engine. The catch
path uses exact local presentation authority only to publish queue takeover;
provider results and generic failures still require full ownership, so a newer
scan or completed result fences them. Queue-backed transport does not replay
inline. The protected transport/retirement race and request-count matrix are
defined in the
[live scan connectivity handoff incident](../incidents/2026-08-live-scan-connectivity-handoff-gap.md).

Each poll and delayed Retry callback applies its fresh `QueuedScanContext` only
when the view model still presents that exact queued scan ID. A completion from
scan A cannot restore A's queue snapshot after scan B has opened. A direct
parent `queuedScan` replacement calls `bindQueuedPresentation` so A's action
generation and scan-bound state are invalidated before B's snapshot and media
are installed. An accepted same-scan refresh replaces both queue state and the
cached media snapshot. Manual Retry tracks `retryingScanId`, so A's delayed
completion cannot release B's indicator. Its 350 ms follow-up refresh is an
identity-keyed SwiftUI task rather than a fire-and-forget callback, so view
teardown cancels it before it can retain or mutate a replaced queued
presentation. Queued Field Notes remain editable: their sheet captures the
queued scan ID and presentation generation, writes through
`FieldNotesRepository`, and rejects any callback after the queue presentation
changes.

---

## Live Result Ownership and Background Handoff

Capture prepares `InferenceEngine` only after durable queue acceptance and
immediately before opening the Insight sheet. A live task owns three identities:
the stable scan ID, a process-local presentation UUID, and the foreground
inference UUID persisted on the scan-ingestion job. Task defer clears
`isProcessing` and the active fields only when its presentation UUID still owns
the slot. Provider dispatch and every result or failure publication additionally
require the durable foreground UUID to remain current.

If background URLSession recovery completes first,
`commitRecoveredBackgroundResult` compares the exact scan, presentation UUID,
released foreground UUID, and absence of a replacement foreground owner. It
atomically invalidates that presentation before committing recovered
`speciesData`, then cooperatively cancels only the displaced live task. A stale
completion for attempt A cannot hydrate, cancel, or publish over replacement B.
Likewise, A's delayed failure handler cannot emit telemetry, update the circuit
breaker, trigger an error haptic, or replace B with a timeout placeholder.

`InsightContentView` observes the recovered state and leaves analyzing mode
immediately. Correctness comes from the ownership transfer, not from assuming
task cancellation is immediate.

The queued-scan trash action is intentionally different: its
`deleteQueuedScan(scanId:)` call represents an explicit user request to cancel
all work for that scan, so it deliberately omits a generation expectation.

---

## Queued Scan Completion Transition

When an offline scan completes while an embedded `InsightSheetView` is open, the
pushed destination must **transition to results without popping**.
`LibraryView.openQueuedScan` first checks for a completed `LocalScanRecord` to
close the render-to-tap race. If no completed record exists, it fetches the
fresh queue row, snapshots `QueuedScanContext`, and emits it through
`onQueuedInsight`. `ScansSheetView` appends a private `QueuedScanInsightRoute`
to its existing `NavigationPath`; the route carries the immutable context but
compares and hashes by queue ID.

```
LibraryView.openQueuedScan(snapshot)
    → completed record exists: push ScanInsightRoute
    → otherwise snapshot QueuedScanContext and emit onQueuedInsight
    → ScansSheetView appends QueuedScanInsightRoute
    → InsightSheetView(
          queuedScan: context,
          presentationStyle: .embeddedInScansLibrary
      )
    → bindQueuedPresentationPreferringCompletedRecord(...)
        → same-ID LocalScanRecord exists: promote immediately
        → otherwise retain queued presentation
    → AppEvent.scanLibraryChanged emits through the container bus
    → InsightSheetView.attemptQueuedCompletionHandoff(...)
    → Retry up to 8 × 350 ms for LocalScanRecord with matching ID
    → viewModel.queuedContext = nil        // Clear BEFORE load so .analyzing guard passes
    → inferenceEngine.load(from: record)   // Triggers isProcessing true→false
    → InsightContentView renders results
```

The same Insight destination remains on the Scans navigation stack while the
queue row is deleted and the completed record is loaded. Native Back therefore
returns to the library, matching completed-scan navigation; no second sheet is
presented over the Scans sheet. A fallback context can be built from the grid
snapshot if the queue row disappears between tap and fetch. Because a
`NavigationPath` retains that queued value snapshot, every destination bind
treats a persisted same-ID completed record as authoritative; a parent refresh
cannot resurrect analyzing UI after completion. Rebinding that stale route after
the exact completion is already visible is idempotent and preserves both the
presentation generation and result controls.

The shared scanning badge contains no translated SwiftUI child geometry. Its
completed-state glare is painted inside one fixed Canvas, label changes use an
opacity-only content transition, and its native Button receives an explicit
label before the caller applies an intrinsic-size constraint and assigns
`ScanningStatusBadge`. It is not re-composed through
`.accessibilityElement(children: .ignore)`, because hosted Run 105 proved that
doing so prevents the outer identifier from remaining discoverable as a Button.
This stronger boundary is deliberate: one simulator layout exposed a 703-point
translated overlay as the Button's accessibility frame in a 402-point window;
another hierarchy phase exposed width 1,406 around the same roughly 234-point
visible capsule. Visually clipping those descendants did not repair their
semantic geometry, as hosted Run 104 proved. Automation had consequently tapped
a fallback edge point instead of the capsule. The exact queued-audio smoke
requires the frame to remain fully inside the app window before it initiates
deterministic completion and reports both rectangles on failure.

The companion live-connectivity smoke starts from an analyzing Insight whose
exact durable queue row already exists. Its Debug-only trigger calls the same
production queue-presentation transition used after a transport handoff. The
test requires an invisible identifier-scoped queued-presentation marker, keeps
the visible pill on the same user-facing AI-analysis copy, rejects the removed
saved/continuing explanation and any **Network timeout** card, dismisses the
sheet, and verifies that the same scan ID remains queued in Scans. The hosted
gate accepts only the exact four-case set containing the progressive analyzing
smoke, this transition, the queued-retry safe-copy smoke, and the queued-audio
completion smoke.

The handoff single-flight is subject-aware rather than one global busy Boolean.
A request for a different queued scan advances its generation and replaces the
older poller; the older task checks that token and exact queued ID before every
promotion attempt. It also checks task cancellation before each attempt, and a
canceled 350 ms sleep exits instead of resuming another poll. Dismissal or
identity-keyed task replacement therefore cannot mutate a newer presentation.
`promoteQueuedScanIfLocalRecordExists` independently requires the same queued ID
before it releases queued routing and loads the completed record. A direct
open-destination promotion completes before `.scanLibraryChanged` is sent for
parent Library refresh. Reversing that order would synchronously rebuild the
parent while its route still carried the stale queued snapshot.

Clearing `queuedContext` before calling `load(from:)` is critical:
`InsightSheetView.onChange(of: inferenceEngine.isProcessing)` has a
`guard viewModel.queuedContext == nil else { return }` guard — if
`queuedContext` were still set when `isProcessing` goes false, the completion
path (celebration, haptics, record-marking) would be skipped.

---

## Tab Bar Badge Dot (`hasUnseenScan`)

`MainTabBar` reads `AppSettings.hasUnseenScan` to display an 8 pt red dot on the
Scans icon. The flag is persisted underneath so background completions survive
process suspension, and `AppLifecycleManager` calls
`AppSettings.refreshFromDefaults()` on foreground to reconcile background
delegate writes.

**Set to `true` (badge appears):**

- `CaptureWorkspaceViewModel.handleInferenceProcessingChange` — when live
  `isProcessing` goes false **and** `activeSheet != .insight` (user is not
  already viewing the result).
- `OfflineQueueManager+URLSession.processInferenceDownloadResult` — when an
  offline scan completes, **unless** `AppSettings.suppressInferenceBanners` is
  `true` (insight sheet is open and the user is watching the transition to
  results).

**Set to `false` (badge cleared):**

- `CameraSheetRouter.scans.onAppear` — when the scans sheet opens from the
  camera tab bar.
- `CameraSheetRouter.insight.onAppear` — when the insight sheet opens from the
  camera flow.
- `ScansSheetView.onAppear` asks `ScansShellViewModel` to clear it on every
  scans sheet presentation.
- `ScansSheetView.onChange(of: appSettings.hasUnseenScan)` asks the view model
  to clear it immediately if it fires while the scans sheet is already visible
  (a scan completing while the user is already in the library).
- `InsightSheetView.onAppear` — clears the badge whenever any insight sheet
  opens (camera or library path).

---

## Push Notification Delivery

`InsightSheetView` manages the `AppSettings.suppressInferenceBanners` flag:

- **`onAppear`**: sets `suppressInferenceBanners = true`
- **`onDisappear`**: sets `suppressInferenceBanners = false`

`PushNotificationManager.willPresent(_:withCompletionHandler:)` reads the
persisted key synchronously when the app is in the foreground because the
delegate method is nonisolated and must call its completion handler immediately.
If `true` (user is on the insight sheet), the notification is delivered silently
(`completionHandler([])`). If `false` (user is elsewhere in the app), the banner
is shown (`completionHandler([.banner, .sound, .list])`).

Both notification call sites (`InferenceEngine` live path, `OfflineQueueManager`
offline path) schedule notifications unconditionally — without an
`applicationState != .active` guard. Foreground suppression is delegated
entirely to `PushNotificationManager.willPresent`. When the app is backgrounded,
`willPresent` is never called and the OS shows the notification automatically.

---

## Mixed-Media Carousel

The carousel now renders a unified mixed-media page model rather than stitching
together separate image-only arrays.

Source ownership mirrors the runtime pipeline: `Media/Carousel/Models` defines
deterministic presentation values, `Builders` assembles and filters pages,
`Services` supplies the narrow live side-effect seam, `Playback` contains
AVPlayer lifetimes, and mounted UI state stays in `Pages`, `Components`, and the
two root carousel views. Domain-neutral paging, zoom, pagination, and hero
scroll-edge presentation shared with Field Trips belongs to
`Core/UI/Components/MediaCarousel`. The split does not change the mixed-media
order, copy, accessibility identifiers, animation clock, mute policy, focus
timing, fallback behavior, or fullscreen routes.

1. **Live captures** (`viewModel.activeMedia.liveImageData`) — display-quality
   `Data` for the current session's live frame when analysis is still in flight.
2. **Persisted user media** (`viewModel.activeMedia.items`) — the ordered user
   timeline rebuilt from `CapturedMediaSnapshot`. This can contain image pages,
   video playback pages, standalone audio playback pages, and description pages
   in one stable sequence. Video poster thumbnails stay attached to the video
   item for grid/list preview purposes and are not duplicated as separate
   carousel pages; extracted video audio is kept as inference metadata on the
   video item, not a visible media page. Cloud hydration uses
   `scans.captured_media` as authoritative only when its nonempty decoded
   projection contains a usable image or video; owner-history hydration also
   dual-reads durable image/audio/video URL columns and
   `user_observation_context` so an empty, device-only, incomplete, or legacy
   manifest cannot erase durable media or submitted description text. New
   canonical manifests preserve every audio and description position. The
   compatibility columns lack cross-modal positions, so only legacy missing
   audio is appended in stored-array order and the stored context follows it.
   They are not deletion authority. Cloud audio replaces a local standalone clip
   only on an exact path or unique `sourceIndex` match; unindexed ambiguous
   media and unmatched descriptions are retained rather than consumed by ordinal
   guess. Legacy rows with `video_storage_urls` collapse sampled frame URLs into
   the video thumbnail instead of rendering those frames as standalone pages.

   An active video may carry one degraded image fallback without changing the
   persisted wire format: the stored poster wins, otherwise the middle retained
   sampled frame is used. When cloud reconciliation receives an explicitly empty
   `video_storage_urls`, a stale video manifest is demoted to that image in its
   timeline position, including for an already-cached remote record. Runtime
   playback failure resolves through the same path with the same page identity,
   removes playback and mute controls, and makes the replacement a normal
   zoomable image. The other sampled frames never become pages.

   If a scan contained a user image or video and availability resolution leaves
   no usable user visual, failed visual pages are removed and
   `Original photo
   unavailable` is appended after all audio, description,
   reference, and reference-loading pages. A scan composed only of audio and
   description pages does not create this photo-specific state. The state is not
   tappable and is excluded from the fullscreen gallery.

Backend finalization now proves this same canonical projection. Forward
migration `20260729012153_fix_video_scan_canonical_finalization.sql` no longer
requires sampled frame URLs as ready standalone images, but still requires the
exact owner's ready playback row and every genuine image/audio row before a
fresh multimodal result can complete. The UI must not compensate for an
incomplete backend scan by manufacturing sampled-frame pages; the one retained
degraded fallback above is availability handling for a completed historical
scan, not canonical backend media completion.

Persisted, completed scans with standalone audio add **Boost audio** to the top
ellipsis menu and directly on the spectrogram. The compact bottom-left control
shares the carousel attribution-tag inset and transitions to **Boosted audio**
when the processed source is ready; a matching bottom-right badge shows elapsed
and total playback time. The preference is device-local and per scan, applies to
every standalone audio page in a mixed-media carousel, and remains independent
from any public Explore-post preference. Restoration is silent; explicit
activation shows progress, and successful playback displays **Boosted audio**
without modifying the original recording. An idle first play remains disabled
while a restored boosted source is being prepared. If a boost or revert finishes
during active playback, the prepared source is staged without interrupting the
active player. The source handoff occurs at the next pause, marker drag, or clip
end and aligns the replacement to the live player position immediately before
the swap. If a marker drag resumes playback, playhead observation restarts for
the replacement player. Completion callbacks from replaced players are ignored
so they cannot reset the active playhead.

Boost processing writes a Core Audio file inside an explicit close scope, then
reopens and decodes every rendered frame before publishing the source to a
player. Decode errors and callback-less playback stops invalidate the cached
boost and fall back to the original recording at the last confirmed playhead
position, so the UI cannot remain falsely stuck in its playing state.

Insight audio spectrograms support focused seeking. A tap jumps playback to the
selected time. During playback, the thin playmarker and its 44-point invisible
drag target sample `AVAudioPlayer.currentTime` on SwiftUI's display-synchronized
animation timeline; the raster-backed, equatable spectrogram remains outside
that frame loop. A drag that starts on the marker pauses playback while moving
and resumes only if the clip was previously playing. Horizontal drags elsewhere
continue paging through mixed media. VoiceOver adjusts the position in
five-second steps. Seek position is session-local and works identically for
original and boosted playback. Playback taps use the shared Merian haptic
vocabulary: medium feedback for play or enabling boost, light feedback for
pause, mute, or disabling boost, and a single begin/commit pair for a scrub
gesture. Timer updates, playhead movement, silent preference restoration, and
carousel hydration do not generate haptics. 3. **Reference images**
(`speciesData.referenceImageUrl`) — comma-separated verified field observations
(e.g. iNaturalist) and Wikimedia images populated natively via GBIF occurrence
hydration. **Suppressed for humans and domestic cats/dogs**: `viewModel.refUrls`
returns `[]` when `speciesData.shouldSuppressReferenceImages` is true. Beyond
the existing human rule, suppression matches only the normalized scientific
names `Felis catus` and `Canis lupus familiaris`; wild felids and canids retain
their reference galleries. The user's captured media remains visible in every
case. Before counts or pages are derived, `InsightSheetViewModel` also removes
references matching the exact scan's image/video paths, persisted or queued
thumbnails, and cover image. Other scans' Naturebook media and unrelated
Wikipedia/GBIF references remain eligible.

**Current-scan reference deduplication**: `ReferenceImageDeduplicationPolicy`
identifies Naturebook media by normalized host and encoded object path, ignoring
scheme, query strings, and fragments. External references use their complete
trimmed URL identity. This is URL/provenance deduplication, not perceptual image
matching: a separately uploaded copy with a different object path remains
visible. `ActiveScanMedia.removingDuplicateReferenceImages(excluding:)` runs
before `refUrls`, `totalImages`, `CarouselPageBuilder`, and
`InsightImageGalleryBuilder` consume the state. Surviving references keep their
source order and attribution; an emptied `.loaded` state becomes `.empty`, so
inline and fullscreen galleries report the same corrected count without an empty
reference page.

**Seamless user-media handoff**: On a live scan, the saved on-disk media is
rebuilt into `ActiveScanMedia` before `speciesData` is assigned and before the
transient live image is cleared. On queued scans, `InsightSheetViewModel` seeds
`cachedActiveMedia` directly from
`queuedContext.capturedMediaSnapshot.activeScanMedia`. On completed records,
`fetchLocalRecord` hydrates the same structure from
`record.capturedMediaSnapshot.activeScanMedia`. That shared read path is what
keeps the playback video clip, standalone audio clip, or mixed-media order
intact while the Insight presentation transitions from queued/analyzing state to
results. Pending video paths may move from temporary capture storage into
Documents during queue persistence, so the resolver falls back by filename
before declaring video unavailable.

**Video presentation rule**: Scan tiles, widgets, map/profile previews, and
share previews remain thumbnail-first by reading `coverImagePath`,
`primaryImagePath`, or `thumbnailImagePaths`. Once the Insight sheet is open,
`ActiveScanMedia` renders `.video` pages as playback surfaces, and tapping a
video opens the fullscreen modal carousel on that video item. The poster image
is therefore a preview asset, not a user-visible duplicate of the clip inside
Insight. Non-biological video scans use the same media timeline, so their result
body changes but the video remains playable media rather than a strip of sampled
inference frames.

**SwiftData fault safety**: `CapturedMediaSnapshot` for `LocalScanRecord` and
`OfflineQueuedScan` intentionally decodes `capturedMediaJSON` before touching
the `capturedMediaEntries` relationship. This keeps insight-sheet body
evaluation, `BiologicalView`, and carousel hydration on scalar SwiftData reads
whenever the JSON mirror is valid, avoiding child-row faults during layout.
`capturedMediaEntries` remains a fallback mirror, not the preferred hot read
path.

**On-disk image quality**: Persisted image pages restored into `ActiveScanMedia`
are 2048 px WebP (display-quality path). This covers the full native pixel width
of all current iOS devices without upscaling (iPhone Pro Max at 3× ≈ 1290 px;
iPad Pro at 2× = 2048 px), eliminating the JPEG blocking artifacts that appeared
when the carousel rendered the 1024 px inference payload directly. The AI
inference path remains at 1024 px — see
[Image Pipeline → Dual-Path Downsample](../system-architecture/03-image-pipeline.md)
for the full architecture.

All images are loaded through the cross-feature
`Core/UI/Components/AsyncLocalImageView`, which handles RAM cache hits, request
coalescing, and local-vs-remote routing transparently. Its live
`LocalImageLoader` resolution is isolated in
`Core/UI/Services/AsyncLocalImageDependencies.swift`; the Insights carousel
supplies sources and transient availability callbacks without owning the loader.

Image availability is transient presentation state owned by `ImagesCarousel`.
Load failures do not mutate `ActiveScanMedia`, the persisted user-media
timeline, or `speciesData.referenceImageUrl`. Instead, image slots are stably
partitioned so unavailable images move behind available images while audio,
video, and description slots retain their positions. If the selected image
fails, selection advances to the first available visual page when one exists. A
later successful retry restores the image to its source order. The transient
failure set is cleared when `scanId` changes so a URL reused by a different
observation is never inherited as unavailable. The same scan boundary resets
selection to the first page and restores muted video playback.

### NativePageCarousel & Per-Page Zoom Architecture

`ImagesCarousel` and the private Field-trip Goals hero render pages via the
shared `NativePageCarousel` — a `UIViewControllerRepresentable` wrapping
`UIPageViewController` in `Core/UI/Components/MediaCarousel`. The pager consumes
the domain-neutral `NativePageCarouselPage`: Insight projects its existing
image-origin, still-source, and focus identity into the reuse key, while Field
Trips uses its stable goal-derived page ID plus the existing reference/user
source-family boundary. Both surfaces also use `MediaCarouselPaginationDots` for
the same single-page hiding, selection animation, material capsule, and
accessibility count treatment. Their top-edge heroes share
`MediaHeroTopScrollEdgeEffectModifier`, which suppresses the iOS 26 scroll-edge
treatment while imagery remains beneath transparent navigation chrome and
restores it after the hero clears the toolbar. `TabView(.page)` was evaluated
and rejected for two reasons: it lazily instantiates pages (so
`AsyncLocalImageView.task` only fires when the user swipes to a page, causing
image loads during the swipe transition), and its gesture recogniser conflicts
with the sheet's pan gesture. `UIPageViewController` fixes both: the
`Coordinator` pre-creates all controllers upfront, and its internal
`UIScrollView` defers to the sheet's pan without manual workarounds.

The Core page defaults its reuse key to its stable ID. When both values remain
equal, the coordinator pushes updated SwiftUI content into the mounted
controller without losing page-local state. If the ordered page sequence or a
feature-supplied reuse key changes, the pager nil-resets its native data source
and reinstalls the selected controller so `UIPageViewController` cannot retain a
stale cached neighbor. Insight's image-origin, source-index, and focus
projection therefore preserves exact live/queue continuity while still
remounting a structurally different page.

**`ZoomPageViewController`**: Each carousel page is a `ZoomPageViewController` —
a `UIViewController` that embeds its SwiftUI content inside a `ZoomScrollView`.
It exposes a `rootView: AnyView` computed property that proxies to the inner
`UIHostingController`, preserving `updateUIViewController`'s existing state-push
pattern (`controller.rootView = pages[i]`) without any changes to the
page-update path.

**`ZoomScrollView`**: A `UIScrollView` subclass configured with
`minimumZoomScale: 1.0` and `maximumZoomScale: 4.0`. It overrides
`gestureRecognizerShouldBegin(_:)` to return `false` for its
`panGestureRecognizer` when `zoomScale ≤ minimumZoomScale + 0.01`. This is the
only safe way to suppress the inner pan at 1×: replacing
`panGestureRecognizer.delegate` directly throws `NSInvalidArgumentException` at
runtime because UIKit requires the scroll view itself to remain its pan
gesture's delegate. At 1× the UIPageViewController swipe wins; above 1× the
inner scroll view's pan fires, allowing the user to explore the zoomed image
freely.

**Snap-back**: Both `scrollViewDidEndZooming` (pinch released) and
`scrollViewDidEndDragging` (pan released while zoomed) call
`snapBackToIdentity`, which cancels any pending deceleration then runs
`UIView.animate(usingSpringWithDamping: 0.72)` to restore `zoomScale → 1.0` and
`contentOffset → .zero` simultaneously.

---

## Scan Information Card

`ScanInformationCard` renders the spatiotemporal context captured at the moment
of the scan after applying `ProfileViewModel.defaultGeoprivacy`. It is hidden
entirely when no privacy-visible data remains (for example, a private scan with
only location/weather telemetry), preventing the card from appearing as an empty
placeholder.

Rows displayed when present:

| Row         | Source                                                 | Condition                                            |
| ----------- | ------------------------------------------------------ | ---------------------------------------------------- |
| LOCATION    | `speciesData.locationName`                             | Non-empty string                                     |
| ELEVATION   | `speciesData.gpsElevation`                             | Non-nil, non-zero                                    |
| WEATHER     | `speciesData.weatherTemperatureF` + `weatherCondition` | Both non-nil                                         |
| DATE        | `timestamp` parameter                                  | Non-nil                                              |
| TIME        | `timestamp` parameter                                  | Non-nil                                              |
| IMAGES      | `imageCount` parameter                                 | `imageCount > 1` only; hidden for single-image scans |
| CAMERA ZOOM | `speciesData.zoomFactor`                               | Non-nil (1× scans omit this row)                     |
| Map         | `speciesData.gpsLatitude` + `gpsLongitude`             | Valid coordinate pair, not `(0, 0)`                  |

The ZOOM row shows the value formatted as `"3.0×"`. It is omitted for 1× scans
because `CaptureTelemetry.zoomFactor` is set to `nil` when zoom is at 1× — a 1×
value carries no useful signal for identification. The row is also absent for
scans captured on single-lens hardware
(`CameraManager.isZoomSupported == false`) and any scan recorded before
`MerianSchemaV13`.

---

## Custom Tags

`Content/Components/Tags/UserTagsCard` is the render and interaction surface for
personal scan labels on biological and non-biological results. It owns the
capsule layout and alert draft only. `UserTagValidation` trims surrounding
spaces, treats duplicates and empty input as no-ops, and rejects more than 50
tags, a visible tag longer than 64 characters, a tag larger than 256 UTF-8
bytes, or any control character. These limits match the authenticated metadata
RPC's durable bounds while retaining the stricter iOS display cap.

`UserTagsViewModel` mutates the presented `LocalScanRecord` and saves its
`ModelContext` before any external effect. A save failure rolls the context and
record back to the prior tag array and starts neither cloud synchronization nor
search-index invalidation. After a successful save,
`UserTagsCloudSyncCoordinator` serializes immutable snapshots in mutation order,
so an older add cannot complete after and overwrite a newer removal. Each
snapshot retains the authenticated user ID observed when it was enqueued;
`UserTagsDependencies` must acquire an exact account-bound work lease before
calling `update_owned_scan_custom_tags`, and skips the request when an Auth
transition makes that identity stale. The RPC still derives ownership from the
JWT and accepts no user ID parameter.

Cloud synchronization is a best-effort mirror of already committed local state.
A remote failure is logged without response data and does not roll back the
SwiftData value or typed local search-index invalidation. See
[Authenticated Scan Metadata RPCs](../backend-and-data/05-api-contracts.md#authenticated-scan-metadata-rpcs)
for the trusted boundary.

---

## Species Insights

`HabitatAndDistributionCard` renders habitat and distribution intelligence for
the identified species. Available to all users.

### Loading Flow (new scans)

After a successful biological scan, `InferenceEngine.analyze()` fires
`fetchAndApplyEnrichment(modelContext:)` in a background `Task` for all users.
While this request is in flight:

- `inferenceEngine.isEnrichmentLoading` is `true`
- `HabitatAndDistributionCard` renders an animated shimmer skeleton (three
  placeholder text lines)
- When data arrives (typically 2–3 seconds post-scan),
  `speciesData.habitatDescription` is patched in-place on `@MainActor`, the
  skeleton is replaced by content with no navigation required, and the data is
  persisted to `LocalScanRecord`

**24h enrichment deduplication** (`enrichedSpeciesTimestamps`): After
`fetchAndApplyEnrichment` completes, `InferenceEngine` records the scientific
name with a timestamp in `enrichedSpeciesTimestamps` (a `[String: Double]`
UserDefaults-persisted dictionary with a 24h TTL) to prevent redundant
`enrich-scan` Edge calls for the same species within 24 hours. This write is
**conditional on `speciesData?.habitatDescription != nil`** — if enrichment
fails transiently and `habitatDescription` is not populated, no timestamp is
recorded. This ensures a failed enrichment attempt does not block future
enrichment retries for species whose prior call failed transiently.

### Loading Flow (historical scans)

When `InferenceEngine.load(from:)` loads an eligible resolved non-Human
`LocalScanRecord` that is missing `habitatDescription`, `gbifTaxonKey`, or
`lookalikesData`, it automatically fires `fetchAndApplyEnrichment`. Human and
unresolved records skip this path and load without stale candidates, lookalikes,
GBIF keys, or external reference imagery. For eligible species, metadata remains
species-cache-aware, but lookalikes are still fetched per scan whenever the
record lacks rich local lookalike data. This gap-fills enrichment for older
resolved scans (even those that already have flat `similarSpecies` string
arrays) to retrieve rich image and common-name JSON payloads from the V27
pipeline.

### States

| State       | Trigger                                       | Rendered                                                                                                                                                                                                                                                                                          |
| ----------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Loaded**  | `habitatDescription != nil`                   | Habitat text                                                                                                                                                                                                                                                                                      |
| **Loading** | `inferenceEngine.isEnrichmentLoading == true` | Shimmer skeleton (3 text lines)                                                                                                                                                                                                                                                                   |
| **Retry**   | No data, not loading                          | "Retry" button → calls `inferenceEngine.fetchAndApplyEnrichment`. **Auto-retry**: when the card first enters this state, a `.task` fires `triggerEnrichment()` once after a 2-second delay (gated by `@State private var hasAutoRetried = false`). The manual Retry button remains as a fallback. |

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
  stay visible beside large public datasets. Footer/accessibility text keeps raw
  peak counts available.

States:

| State          | Trigger                                         | Rendered                                            |
| -------------- | ----------------------------------------------- | --------------------------------------------------- |
| Local + Public | Local rows and public cache/provider data exist | Normalized comparison chart with raw summary footer |
| Local only     | Public request fails or is unavailable          | Local chart plus public-unavailable note            |
| Public only    | No local rows yet                               | Public chart baseline                               |
| Partial/Stale  | Backend returns `partial` or `stale`            | Chart plus refresh/cache note                       |
| Empty          | Selected tab has no local or public values      | Compact empty state explaining the tab              |

See [`Species Observation Charts`](./18-species-observation-charts.md) for the
full API contract, iNaturalist annotation mappings, cache rules, and privacy
boundary.

### Similar Species Rendering

`similar_species` data is rendered by `SimilarSpeciesGallery` inside
`BiologicalView` sequentially. The gallery is explicitly treated as
informational and unconditionally renders as "Similar species". Previous dynamic
confidence-based gating has been removed to prioritize objective reference
availability.

**Mathematical Baseline Constraints**: To prevent Apple's SwiftUI Layout Engine
from allowing extreme intrinsic image aspect ratios (e.g., highly vertical
photos) from stretching the row, `SimilarSpeciesCard` enforces fixed card
geometry at `200 x 260` points. The image fills the card bounds, while the
bottom text overlay uses material chrome and internal padding so a 2-line
`.subheadline` common name and 1-line `.caption` scientific name remain stable
without resizing the carousel.

Each `SimilarSpeciesCard` receives a `SimilarSpeciesEntry`. When
`referenceImageUrl` is non-nil, the card renders it via `AsyncLocalImageView`;
if the URL fails, local `@State var remoteImageFailed` flips to `true` and the
card shows the leaf-icon placeholder instead. When `referenceImageUrl` is nil, a
`SimilarSpeciesImageFetcher` Wikipedia/GBIF waterfall runs in a `.task`. In all
failure cases the card stays in the gallery — it is never removed. The only
exclusion rule is a blank `scientificName` (truly invalid server data), filtered
in `validEntries`.

---

## Identification Candidates

When the AI's confidence falls below the tier-specific `diagnosticTrigger`
threshold (`0.99` for both Flash and Pro) the `candidates` array is forwarded to
the client and persisted for the scan. This threshold is intentionally above the
`strong` band on each tier (`0.95` Flash / `0.85` Pro), so Possible, Weak, and
most Strong-match scans can still carry candidates as an escape hatch for
overconfident wrong IDs. Only scans at or above `0.99` have candidates stripped.

Stored candidates do **not** automatically create a visible candidate-review UI.
Display is controlled on-device by `CandidateReviewVisibilityPolicy`, which is
shared by the inline `CandidatesCard`, `ConfidenceExplanationSheet`, toolbar
actions, and the Needs review smart collection. The policy shows review
alternatives when the primary identification is below the tier's Strong
threshold, or when a Strong primary has a genuinely competitive alternative.

### Data Flow

1. **Executable model contract**
   (`services/supabase/functions/_shared/identify/contract.ts`): `candidates` is
   required in `merianModelContract`, which generates the Gemini schema and
   validates the live provider value. The generic visual/Describe policy asks
   resolved biological subjects for alternative species, while non-biological
   subjects return an empty array. The private audio contract permits acoustic
   candidates only for `identified_non_human`; `unidentified_non_human`,
   `human_only`, and `no_confident_biological_source` require an empty array.
   Each candidate entry is
   `{ scientific_name, confidence_score, distinguishing_feature }` where
   `distinguishing_feature` is the required observable trait separating the
   candidate from the primary identification. `common_name` is absent from the
   provider model contract and is enriched server-side from
   `species_dictionary`; it is present for a cache hit and nullable on a miss.
   The complete enriched response is validated against the final wire contract
   before it can reach Swift or persistence.
2. **Server-side strip**
   (`services/supabase/functions/identify-multimodal/index.ts`, shared
   thresholds in `services/supabase/functions/_shared/identify/thresholds.ts`):
   After Gemini returns, the active multimodal handler first normalizes
   processed-material results to non-biological and clears candidates. For
   remaining biological results, it calls `diagnosticTriggerForTier(tier)`. If
   `confidence_score >= diagnosticTrigger`, the `candidates` array is cleared to
   `null` before the response is sent to the client and before the `insertScan`
   DB write. This is the sole confidence gate: Gemini is not asked to
   self-suppress, the server enforces the rule unconditionally. **Thresholds**:
   `0.99` for both Flash and Pro (intentionally above `FLASH_STRONG` = 0.95 and
   `PRO_STRONG` = 0.85 so Strong match scans still carry candidates).
   `MerianConfig.flashConfidence.diagnosticTrigger` and
   `MerianConfig.proConfidence.diagnosticTrigger` in the iOS client mirror these
   values and must be kept in sync.
3. **Supabase persistence** (`candidates` JSONB, migration
   `20260330000000_add_candidates_to_scans.sql`): Stored as a JSONB column on
   `public.scans`. `NULL` for non-biological scans, processed-material
   demotions, scans at or above the diagnostic trigger (`0.99`), and all scans
   from before this migration. A partial index (`WHERE candidates IS NOT NULL`)
   keeps index overhead minimal since most near-certain scans do not need stored
   alternatives.
4. **SwiftData persistence** (`candidatesData: Data?`, `MerianSchemaV28`): The
   iOS client JSON-encodes `[IdentificationCandidate]` via `JSONEncoder` and
   stores the blob in `LocalScanRecord.candidatesData`.
   `InferenceEngine.load(from:)` snapshots the blob before async hydration and
   decodes it back via `JSONDecoder` for historical scans.
5. **Historical sync** (`ScanRepository.syncHistoricalScansDown`): The
   `candidates` column is included in the `SELECT` query. A
   `CloudIdentificationCandidate` DTO
   (`{ scientific_name: String, common_name: String?, confidence_score: Double, distinguishing_feature: String? }`)
   decodes the cloud JSONB. `ingestScans` re-encodes it to
   `IdentificationCandidate` (including `distinguishingFeature`) and persists as
   `candidatesData`. The `updateExistingScans` backfill path checks
   `existing.candidatesData == nil` before writing, ensuring cloud candidates
   are retroactively available in pre-existing local records.
   `distinguishing_feature` is `String?` in the DTO to decode gracefully from
   pre-migration JSONB rows that have only the two-field shape.

### Display Gate

`CandidateReviewVisibilityPolicy` centralizes review visibility.
`BiologicalView`, `ConfidenceExplanationSheet`, and
`InsightSheetViewModel.canReviewAlternatives` call this policy instead of
checking raw candidate presence independently.

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

**`isUnknownSubject`** — suppresses candidates when taxonomy is unavailable; the
alternatives would be equally unresolved.

**`isHumanSubject`** delegates to `HumanSubjectIdentityPolicy`, which normalizes
whitespace and checks structured `commonName`, `scientificName`, and
`userIdentificationOverride` against Human aliases such as `Human`, `Person`,
`Homo sapiens`, malformed `Homo sapien`, `Human breathing`, and `Human speech`.
It never searches `aiReasoning`. The result suppresses candidates for human
subjects; surfacing plausible-sounding primate alternatives would be misleading
and inappropriate.

**`hasReviewState`** — suppresses candidates once a decisive identification
action has been taken (`userIdentificationOverride`,
`userConfirmedIdentification`, or `alternativesExhausted`). Legacy `isFlagged`
values no longer hide candidate review or surface a review UI. When
`alternativesExhausted == true`, `CandidatesCard` is hidden and
`AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` takes over
instead.

The policy returns the stored candidate array only when it is visible. Hidden
candidates remain persisted for recovery and future flows, but inline cards,
confidence-sheet rows, and toolbar Review alternatives actions behave as if the
candidate list is empty.

**`isHumanSubject` and the override path**: A Human override applied to an
otherwise non-Human result is itself protected. For an originally Human saved
scan, the persisted toolbar/reference snapshot retains the original structured
identity even if a live override temporarily changes display fields, so sharing,
Field Chat, and reference imagery stay suppressed. Candidate review is also
hidden whenever any override is active.

### `CandidateSwipeModal` — Alternatives Review Sheet

`CandidateSwipeModal` is presented as a `.sheet` from both `CandidatesCard` (via
`BiologicalView`) and `ConfidenceExplanationSheet`. It receives an explicit
`@Binding var isPresented: Bool` rather than using `@Environment(\.dismiss)` —
the dismiss environment value leaks up through nested sheets in SwiftUI and
would close the parent `InsightSheetView` instead of only the modal.

**State model**: `CandidateSwipeSession` in
`IdentificationReview/Candidates/Models` owns `originalCandidates`,
`remainingCandidates`, `confirmedCandidate`, and `isExhausted`, plus the
skip/reject/confirm/restart decisions. `CandidateSwipeModal` keeps animation,
drag offsets, the structured success-acknowledgement task, paywall presentation,
and typed dismissal-request wiring in SwiftUI. It does not mutate the engine.

**Card stack**: The top card is draggable (Tinder-style). Dragging ≥ 200 pt
right confirms the candidate through the session; left rejects it. The card
behind it scales up as the drag percentage increases. A "Skip" capsule button
appears when `session.remainingCandidates.count > 1`, moving the top card to the
bottom of the queue.

**Grid mode**: When `session.remainingCandidates.count > 1`, a grid toggle
button appears in the top-right toolbar. Grid mode shows all remaining
candidates as `GridSwipeableCell` rows with per-row confirm/reject buttons.

**Toolbar**: The leading X button sets `isPresented = false`. When multiple
candidates remain, the trailing button toggles grid/stack mode. When
alternatives are exhausted (`session.isExhausted && !isDismissing`), a plain
**Restart** text button appears in the trailing slot and calls
`session.restart()` without closing the sheet.

**Exhausted state** (`exhaustedStateContent`): Shown when all candidates have
been swiped away. Displays the original scan thumbnail and up to three action
controls stacked vertically:

1. `SlideToConfirm(label: "Reanalyze species", color: .orange)` — shown when a
   persisted scan record allows refinement; Pro users stage `.refineScan`,
   dismiss the candidate modal, and let the owner resume from `onDismiss`, while
   free users see the modal-owned paywall
2. `SlideToConfirm(label: "Ask the community", color: .blue)` — only shown when
   the owner allows it; stages `.askCommunity`, dismisses, and opens the
   Community request only from the source sheet's real `onDismiss`
3. `SlideToConfirm(label: confirmButtonTitle)` — always shown; stages
   `.confirmOriginal` and dismisses before the owner mutates the result

**Refinement wiring**: `BiologicalView` resolves the persisted
`LocalScanRecord`, requests
`AppRoute.refinement(scanId:initialDescription:entryPoint:)` through
`AppRouteCoordinator`, and dismisses the Insight presentation. The action
threads through `BiologicalView` → `CandidatesCard` → the typed
`CandidateSwipeDismissalRequest`. `ConfidenceExplanationSheet` independently
fetches the same persisted record and stages an equivalent typed action.
Availability follows the toolbar's persisted-record rule; cloud-backed,
multi-image, and standalone-audio scans are supported because refinement staging
resolves remote media and selects the first usable historical item. Historical
audio is never passed through as a URL-like path. It is downloaded when
necessary, preflighted with AVFoundation, decoded through the bounded Core Audio
converter, and materialized as a new local Int16 PCM WAV before refinement can
enter the capture/queue pipeline. If every audio reference fails, the first
saved description is staged as the safe fallback.

**Confirmed state**: After a stack or grid confirm, `session.confirmedCandidate`
is set, showing a green `checkmark.circle.fill` success screen for 1.5 s before
the sheet auto-dismisses. That acknowledgement is an identity-keyed SwiftUI
`.task`; unmounting the modal cancels it. The owner receives
`.applyOverride(scientificName:)` before dismissal and invokes
`applyIdentificationOverride` only from the exact `onDismiss`, after rechecking
the captured scan and presentation generation.

**`onDisappear` guard**: If `session.isExhausted && !isDismissing` and the
original scan ID plus engine presentation generation still own the sheet,
`inferenceEngine.markAlternativesExhausted(expectedScanId:)` is called. This
sets the `alternativesExhausted` flag that surfaces `AllCandidatesReviewedView`
in `ConfidenceExplanationSheet` on next open. Candidate confirmation, Community
handoff, and reanalysis requests all carry the same two-part ownership identity;
the owning `CandidatesCard`, `InsightContentView`, or nested confidence sheet
revalidates it after actual dismissal. The direct card controls wrap confirm,
review, dismiss, Community, and refine actions in that ownership check too.

**Nested sheet `Menu` incompatibility**: SwiftUI `Menu` uses
`UIContextMenuInteraction` which fails to attach in nested sheet contexts — the
tap falls through to the sheet's dismiss gesture. All contextual actions are
surfaced as first-class controls within the view body rather than toolbar menus.

### Stage 2 — Approve / Deny UX

Users can confirm or override the AI's primary identification directly from
`CandidatesCard`. The card manages a local `ReviewState` enum:

- **`.pending`**: Default state. Shows a "Was the AI correct?" prompt with a
  `SlideToConfirm` drag-to-confirm pill. The system passes a dynamically
  injected name derived from `viewModel.resolvedHeaderTitle` (e.g., "Confirm
  Giant Panda") rather than a hardcoded string. To prevent text overflow on
  these long dynamic names, the pill natively relies on
  `minimumScaleFactor(0.6)` typographic squishing before truncating. The user
  drags the thumb ≥88% of the track width to confirm; releasing early springs
  the thumb back. On completion,
  `InferenceEngine.confirmAIIdentification(expectedScanId:modelContext:)` is
  called, setting `userConfirmedIdentification = true` locally and transitioning
  to `.confirmed`. Refusing all alternatives lets the user ask the community for
  help instead of sending a dead moderation flag. For candidates with missing
  `commonName` strings (or common names identical to taxonomy),
  `SwipeableCandidateCard` securely elevates the `scientificName` to the primary
  title string un-capitalized. Each card also displays `distinguishingFeature`
  (the single most important observable visual trait separating this candidate
  from the primary ID) below the species name in sentence case, truncated to 2
  lines. Tapping the feature text opens a `DistinguishingFeatureSheetView` sheet
  ("What to look for") at `.fraction(0.35)` height showing the full untruncated
  text. The original capture is also accessible via a PiP thumbnail
  (bottom-right) that expands to a full-screen `OriginalCaptureExpandedView`;
  that expanded path downscales `activeMedia.liveImageData` through
  `ImageDownsampler` at `MerianConfig.displayImageMaxSize` rather than inflating
  the original capture with `UIImage(data:)`. Tapping the candidate image
  expands it to a paged `TabView` carousel containing up to 5 progressively
  loaded reference images inside `CandidateImageExpandedView`.
- **`.confirmed`**: Replaces the prompt with nothing (the card hides its body).
  `ConfidenceBadge` transitions to "Confirmed" (green, `checkmark.seal.fill`).
  `ConfidenceExplanationSheet` shows a confirmation message.
- **`.overridden(to:)`**: Active after the user selects a candidate as their
  preferred identification. Renders an `OverriddenView` showing "Your
  identification" with the override name, "AI originally suggested X" footer,
  and an Undo button. `ConfidenceBadge` transitions to "Your ID" (indigo,
  `person.fill.checkmark`). Candidate exhaustion is a separate state: when
  `alternativesExhausted == true`, `AllCandidatesReviewedView` shows
  "Alternatives reviewed", the stored candidate count, a Reset button
  (`resetIdentificationReview`), a **"Review again" button** that re-opens
  `CandidateSwipeModal` with stored candidates, and an **"Ask the community"
  button** that opens the Community request sheet for human identification help.

**Override flow**: Selecting a candidate calls
`InferenceEngine.applyIdentificationOverride(scientificName:expectedScanId:modelContext:)`,
which:

1. Mutates `speciesData.userIdentificationOverride` and
   `speciesData.scientificName` to the override name, and clears any legacy
   local flag bit so old scans cannot carry stale review state forward. The
   expected scan must still match before this mutation.
2. Advances the scan's latest review-action generation, cancels older species
   hydration, and calls
   `fetchAndPatchOverrideData(scientificName:scanId:modelContext:reviewActionGeneration:)`.
   A cache or enrichment result can patch the live presentation only when the
   scan ID, scientific name, and review-action generation all still match.
3. Serializes local review persistence and cloud review synchronization behind
   one per-engine write tail. This guarantees a request that already started
   cannot finish after and overwrite a newer confirm, override, or reset. Local
   persistence uses `BackgroundDatabaseActor.updateScanWithOverride`.
4. Calls the authenticated `update_owned_scan_identification_review(...)` RPC
   (`InferenceEngine.syncIdentificationReviewToCloud`). The database derives
   ownership from `auth.uid()`, validates the complete typed review state, and
   updates override/confirmation/species/state atomically without exposing
   general scan-table mutation.
5. After patching `speciesData`, persists the updated species-dict fields
   (common name, hazard type, taxonomy, Wikipedia, habitat, GBIF key, etc.) to
   `LocalScanRecord` via
   `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData`. `scientificName`
   is intentionally excluded from this write — `record.scientificName` is
   preserved as the authoritative original-AI identifier, reused as
   `aiScientificName` on `load(from:)` so that `resetIdentificationReview` can
   recover the original name without a separate schema field.

**Re-opening an overridden scan**: `InferenceEngine.load(from:)` applies two
rules when `record.userIdentificationOverride != nil`:

- Sets `speciesData.scientificName` to `record.userIdentificationOverride` (the
  override name) rather than `record.scientificName` (the original AI name).
- Suppresses `InsightData.aiReasoning` — the AI's vision reasoning was written
  for the original species and is misleading under the override name.
  `record.scientificName` is always used as `aiScientificName`, enabling the "AI
  originally suggested X" footer and the Undo/reset path regardless of how many
  times the sheet is reopened.

**Data model**: Four fields on `LocalScanRecord` (all cloud-synced):

- `userIdentificationOverride: String?` — mirrors
  `public.scans.user_identification_override`.
- `userConfirmedIdentification: Bool` — mirrors
  `public.scans.user_confirmed_identification`. Both legacy fields are sent in
  `ReviewSyncPayload` alongside the explicit enum.
- `userReviewStateRaw: String` — typed mapping storing the `user_review_state`
  enum value natively.
- `isFlagged: Bool` — legacy V31 persistence field retained for schema
  compatibility; it no longer drives Insight confidence or candidate-review UI.

**Re-identification**: A user who has already acted on a review can always
re-enter the selection flow:

- From `.overridden`: tap Undo → calls `resetIdentificationReview` → reverts to
  `.pending` with policy-visible candidates available again.
- From `.confirmed`: tap "Change" in `ConfirmedView` → calls
  `resetIdentificationReview` → reverts to `.pending`.
- `resetIdentificationReview` clears `userIdentificationOverride`,
  `userConfirmedIdentification`, any legacy flag bit, and
  `alternativesExhausted` locally, reverts `speciesData.scientificName` to
  `aiScientificName`, and re-hydrates the AI's original species data from
  `species_dictionary`. It sets `userReviewStateRaw` to `"unreviewed"` locally.
  Clearing `alternativesExhausted` is required for the
  `AllCandidatesReviewedView` → full reset path; otherwise
  `CandidateReviewVisibilityPolicy` would keep candidate actions suppressed
  after reset.

**Cross-device sync caveat**: `ScanRepository.updateExistingScans` propagates
`userConfirmedIdentification` in the `true` direction only — a reset performed
on device A (which syncs `user_confirmed_identification = false` to the cloud)
will not propagate to device B during that device's next sync. Device B retains
its local confirmed/overridden state. Full bidirectional review-state sync is
deferred.

---

## Confidence Badge and Spectrum

### Complimentary Pro counter

`ModelTierBadge` independently owns the Results countdown; it is not limited to
the Possible-match upgrade case. For a verified unpaid complimentary account, it
shows the server-reported scans remaining and opens `PaywallView`. On the third
usable Pro result it immediately changes to the exhausted upgrade action, while
the current and historical Pro result content remains fully available.

Only Results and Settings enable this detail. Capture and public Profile or
Explore badges do not show it, and paid accounts use paid plan state instead.
The component observes versioned `EntitlementManager` state and never decrements
a local credit counter. See
[Three Complimentary Pro Scans](../backend-and-data/18-complimentary-pro-scans.md).

`ConfidenceBadge` is a tappable liquid-glass capsule that shows the AI's
confidence band for the current scan. The badge first checks durable
identification decisions before falling back to the confidence-band logic:

**Identification review states** (take precedence over confidence bands):

| State          | Label       | Color | Icon                    | Trigger                               |
| -------------- | ----------- | ----- | ----------------------- | ------------------------------------- |
| User override  | "Confirmed" | Green | `checkmark.circle.fill` | `userIdentificationOverride != nil`   |
| User confirmed | "Confirmed" | Green | `checkmark.circle.fill` | `userConfirmedIdentification == true` |

**Confidence bands** (when no review state is set — managed dynamically via
`MerianConfig.confidenceBands(for: isPro)`):

**Gemini 2.5 Flash (Ordinary Naturebook Tier)**

“Ordinary” is the app plan tier. The production provider request still uses the
approved paid Gemini project; it is not a statement that Google processing is on
unpaid-Service terms.

| Band label     | Color  | Score range |
| -------------- | ------ | ----------- |
| Strong match   | Green  | ≥ 96%       |
| Possible match | Orange | 75% – 95%   |
| Weak match     | Gray   | Below 75%   |

**Gemini 2.5 Pro (Premium Tier)**

| Band label     | Color  | Score range |
| -------------- | ------ | ----------- |
| Strong match   | Green  | ≥ 85%       |
| Possible match | Orange | 65% – 84%   |
| Weak match     | Gray   | Below 65%   |

The inclusive lower edge of **Possible match** is also the server-side automatic
evidence gate for Field trip goals: `0.75` for Flash and `0.65` for Pro. An
unreviewed **Weak match** remains pending and does not advance an outing or
Event until the user confirms the identification or a confirmed
correction/community resolution supplies stronger evidence. See the
[canonical Field Trip policy](25-field-trips.md#identification-evidence-policy).

The badge renders for override/confirmed states even when `confidenceScore == 0`
(historical scans where confidence is unavailable).

`ConfidenceSpectrum` renders a vertical list of `SpectrumNode` items using the
same `MerianConfig` constants so the displayed percentage ranges are always in
sync with the badge logic.

`ConfidenceExplanationSheet` opens as a bottom sheet from the badge tap. It
contains `ConfidenceHeader`, `ConfidenceSpectrum`, `ModelInfoSection`,
`AIMistakesBanner`, and `ProTips` (which conditionally shows a location
permission prompt when GPS access is not granted). `ModelInfoSection` sits
between `ConfidenceSpectrum` and `AIMistakesBanner` and surfaces which
Naturebook AI tier processed the scan — "Naturebook AI Standard" for free/Flash
scans, "Naturebook AI Pro" for Pro scans, with a "Powered by Gemini 2.5 Pro"
footnote on the Pro variant. The sheet reads stored candidates for the
alternatives-exhausted Review again path and
`CandidateReviewVisibilityPolicy.visibleCandidates(for:)` for normal candidate
display. Review-state cards rendered at the top of the sheet (mutually
exclusive, evaluated in order):

Actions that leave Confidence explanation are
`ConfidenceExplanationDismissalAction` values. Nested candidate mutations may
complete after the candidate modal's own `onDismiss` while the explanation
remains visible; Community and refinement actions are staged through the outer
sheet and executed by `ConfidenceBadge` only after its `onDismiss` and a fresh
engine scan/generation check. No sibling presentation is mounted during UIKit
teardown.

| Priority | Condition                             | View                        | Action                                                                                                                 |
| -------- | ------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1        | `alternativesExhausted == true`       | `AllCandidatesReviewedView` | Review again → `CandidateSwipeModal`; Ask the community → Community request sheet; Reset → `resetIdentificationReview` |
| 2        | `userIdentificationOverride != nil`   | `OverriddenView`            | Undo → `resetIdentificationReview`                                                                                     |
| 3        | `userConfirmedIdentification == true` | `ConfirmedView`             | Undo → `resetIdentificationReview`                                                                                     |

When none of the above conditions are met, no review card is rendered and the
full confidence explanation is shown unobstructed.

`blur_score` is populated from live inference only (`SpeciesData.blurScore` maps
to `EdgeResponse.blur_score`). It is `nil` for scans loaded from the local
SwiftData library since it is not persisted to `LocalScanRecord`.

---

## Reference Image and Wikipedia Hydration

Extended ecological media data is loaded in three passes:

1. **Cached with the inference response** (live scans): the post-Gemini
   dictionary RPC includes an already-cached primary species row, so existing
   `wikipedia_overview`, `wikipedia_url`, and reference imagery can populate
   immediately. A cache miss is not added to the already-validated live
   response; primary Wikipedia/GBIF resolution may run during the required scan
   persistence finalization, while group-tag and candidate enrichment remain
   optional `EdgeRuntime.waitUntil` work.
2. **Retroactive Wikipedia hydration** (eligible resolved non-Human live scans
   where Wikipedia was missing, and equivalent historical scans):
   `InferenceEngine.fetchWikipediaAndHydrate` fires a `GET` to
   `en.wikipedia.org/api/rest_v1/page/mobile-sections/<scientific_name>` with an
   8-second timeout. The response includes all article sections; the function
   finds the first section whose `title` case-insensitively equals
   `"Description"` and strips its HTML to plain text via
   `InferenceEngine.stripHTML(_:)`. If no "Description" section exists,
   hydration is skipped entirely. On success it commits
   `speciesData.wikipediaOverview` (the stripped description body),
   `speciesData.wikipediaUrl` (constructed from `lead.normalizedtitle`), and
   `speciesData.referenceImageUrl` (`lead.originalimage.source`) in a single
   full-value replacement on `@MainActor`.
3. **Dynamic GBIF Native Hydration**: When the species' `gbif_taxon_key` is
   available (either instantly on a Cache Hit, or returned seconds later by the
   `enrich-scan` API), the iOS client calls
   `InferenceEngine.fetchGBIFImagesAndHydrate(for:)`. This queries the
   `api.gbif.org/v1/occurrence/search` API for 3-4 high-quality iNaturalist
   field photos, dynamically injecting them into the carousel to ensure highly
   accurate visual context.

Hydration may append a URL that also exists in the scan's own media timeline.
Callers must expose hydrated references through
`InsightSheetViewModel.activeMedia` rather than reading
`speciesData.referenceImageUrl` directly; the view-model boundary applies
suppression, current-scan deduplication, and empty-state normalization before
either carousel is built.

---

## Scan milestone notification

After a foreground or background scan reaches a final saved scan ID,
`ScanMilestoneCoordinator` checks the global dictionary contribution flag, not
the local "new to me" flag:

```swift
if data.isNewToMerianDictionary && data.isBiological
    && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
    includesNewToNaturebook = true
}
```

The coordinator waits for the existing remote-persistence/progress attempt,
collects newly unlocked achievements without presenting them immediately, and
atomically enqueues standard Field trips, Seasonal Challenges, achievements,
then **New to Naturebook**. The final scan ID deduplicates foreground and
background completion races. Progress failure or an empty match result does not
suppress the achievement/dictionary milestones; it only delays them until the
attempt has finished.

The old local `CelebrationBanner` pill is removed. The shared
`MilestoneToastBanner` appears at the bottom of the app with the same queue,
haptics, horizontal/vertical swipe dismissal, close button, 3.5-second timeout,
and VoiceOver announcement. Tapping the `New to Naturebook` body dismisses the
banner because the user is already viewing the scan Insight; achievement taps
open achievement detail, and Field trip taps route to the credited outing goal
or challenge.

VoiceOver users continue to receive the Insight accessibility announcement,
including a hazard-specific warning (venomous / allergenic / irritant / toxic)
when `hazardType != "none"`.

---

## Scroll-Aware Toolbar

`InsightSheetView` tracks whether the common name has scrolled past the viewport
boundary to seamlessly morph the species name into the `TopToolbar`'s
`.principal` display. Tracking an element's `maxY` inside a stretchy header
`ScrollView` creates cyclical layout resolution hazards if `PreferenceKey`
architectures are used (which inherently force sequential multi-pass frame
layouts).

**Asynchronous Geometry Telemetry**: To permanently eradicate the _"Bound
preference tried to update multiple times per frame"_ runtime warning,
`InsightHeader` abandons the `PreferenceKey` system entirely. It embeds a
passive `Color.clear.onChange(of: geo.maxY, initial: true)` hook directly within
its `GeometryReader`. This intercepts the positional coordinate strictly
post-layout and transmits it instantly to `viewModel.evaluateScrollOffset` via
an injected callback (`onScrollOffsetChange`), cleanly decoupling the telemetry
from SwiftUI's layout-invalidation phase lock constraint.

**Dynamic Form Controls**: `TopToolbar` acts as the primary global contextual
sheet. It houses a `Menu` button anchored to the trailing edge spanning four
categories natively via SwiftUI `Section` wrappers. The collection picker lives
directly below Add/Update field notes in this menu, reusing the same Favorites,
existing-collection toggles, and New Collection flow previously hosted in the
bottom toolbar:

Its leading controls retain the visible and VoiceOver labels **Close** and
**Back**, while exposing the stable automation identifiers
`InsightSheetCloseButton` and `InsightSheetBackButton`. Tests must use those
identifiers through the current `InsightSheetView` rather than a global label
query because an underlying SwiftUI presentation can remain in the accessibility
tree during a live-to-queue handoff.

1. Base Export (Download photos and videos)
2. Identification Section (Confirm species, Review alternatives, Reanalyze
   species, Ask the community)
3. Destructive Section (Delete scan) The middle tier ("Identification") is
   driven by `InsightSheetViewModel` display properties. `Confirm species` and
   `Review alternatives` both depend on `reviewAlternativeCandidates`, which is
   filtered through `CandidateReviewVisibilityPolicy`; when policy-visible
   candidates are absent, both actions are hidden. Field chat's
   explicit-identification-concern panel is the exception: it can route to
   `identificationConcernCandidates`, which uses stored scan candidates as a
   manual recovery source without changing the normal toolbar policy.
   `Reanalyze species` remains independently available through its local-record
   guard. `Ask the community` is available for biological, shareable scans with
   image media and opens the Community request sheet. Confirmed, overridden,
   exhausted, unknown, non-biological, and human-subject states suppress
   candidate actions. Reanalysis remains independently available when its source
   record survives; unresolved and Human subjects also suppress Community and
   Explore publication.

---

## Collection Management

Users can add or remove the current scan from any `ScanCollection`:

```swift
func toggleScanInCollection(
    _ collection: ScanCollection,
    modelContext: ModelContext,
    expectedScanId: String?
) {
    // toggles record.collections membership
    // saves modelContext
    // calls OfflineQueueManager.shared.enqueueCollectionSync() for immediate cloud push
    // fires a toast message
}
```

"New Collection" is handled by the `newCollectionAlert` view modifier attached
to `InsightSheetView`. It creates a `ScanCollection` in SwiftData with a UUID
immediately, saves locally, and then schedules cloud sync through
`OfflineQueueManager`'s shared collection drain. The alert captures the exact
local record ID and presentation generation when it opens and passes that
immutable record ID into the modifier. The modifier revalidates `canCreate`
before inserting or attaching anything, so even an alert action racing dismissal
cannot mutate an obsolete presentation.

---

## Deletion

`eradicateCurrentScan` delegates to
`ScanRepository.shared.eradicateScan(record:modelContext:)`, which follows the
transactional deletion protocol:

1. Tombstones any in-flight upload via `softDeleteQueuedScan`
2. Inserts `PendingCloudDeletionTask` + deletes `LocalScanRecord` atomically,
   then calls `modelContext.save()` (DB commit first)
3. Purges local image files via `FileIOActor` only after save succeeds
4. Immediately attempts cloud deletion via `syncPendingDeletions()`

The sheet is dismissed via `DismissAction` after the database operations
complete.

---

## Share & Export

`InsightMediaExportManager.shared` handles two export paths:

- **Save to Photos**: passes live capture data, valid historic local or approved
  cloud image/video paths, and the existing approved reference-photo URL to
  `ExportProcessingActor.shared.saveUserMedia`. Images are saved through
  `PhotoLibraryManager.shared.saveImageManual`, while retained playback clips
  use the file-backed `.video` resource path. Cloud URLs require HTTPS and the
  exact `media.merian.app` host. Completion returns separate photo and video
  counts so alerts and batch toasts describe what was actually saved. See
  [Camera Roll and Captured-Media Export](./27-camera-roll-media-export.md) for
  URL approval, temporary-file ownership, and failure semantics.
- **Share Sheet**: constructs a share payload with the species common name,
  scientific name, and the best available image (live > historic > reference),
  then presents `UIActivityViewController` via `ShareSheetUtility.present`.
