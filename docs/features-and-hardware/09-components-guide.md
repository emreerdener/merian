# Shared Components and Primitives

Naturebook abstracts repetitive SwiftUI view structures into a dedicated
components layer (`Core/UI/` and `Features/*/Components/`) to enforce DRY (Don't
Repeat Yourself) principles and establish a unified aesthetic baseline.

## 1. Zero-State Handling: `EmptyStateView`

**Location**: `Core/UI/Components/EmptyStateView.swift`

Historically, empty states in the Scans Library, Non-Biological Vault, and
Collections were monolithic `VStack` geometries scattered across multiple view
files. These were consolidated into a single, strongly-typed `EmptyStateView`
component. Explore and Species Dictionary now consume the same primitive, so
Core owns its geometry while each feature supplies its own copy and visibility
policy.

- **Dynamic Context**: It accepts dynamic messaging primitives (`title: String`,
  `message: String`, `systemImage: String`).
- **Layout Consistency**: Guarantees identical typography scaling and vertical
  padding ratios regardless of where the empty state is invoked.

## 2. Navigational Orchestration: `MainTabBar`

**Location**: `Core/UI/Components/MainTabBar.swift`

The central navigational routing anchor for the application, designed as a
custom floating "Liquid Glass" capsule rather than relying on standard iOS
`TabView` mechanics.

- **Glassmorphism**: Uses `.ultraThinMaterial` backgrounds bounded by a specular
  `.strokeBorder`.
- **Z-Index Layering**: Hovers persistently at the bottom of the
  `CaptureWorkspaceView` camera feed, allowing the viewfinder to bleed
  infinitely to the edges of the device screen.
- **Explore parity**: `FloatingNavigationMenu` owns the MainTabBar icon, label,
  item-slot, and capsule spacing constants. Treat the Explore bottom navigation
  as the visual reference before changing those metrics.
- **Notification Badging**: Subscribes to `@AppStorage("hasUnseenScan")` to
  overlay an 8pt red continuous notification dot on the Scans icon, tracking
  silent inference completions without manual `@State` plumbing.

## 3. Archival Aesthetics: `ArchivedVisualsView`

**Location**: `Core/UI/Components/ArchivedVisualsView.swift`

Provides a standardized visual protocol for scans that have been archived or
flagged. It encapsulates dark scrim overlays, watermark iconography, and
desaturation modifiers, ensuring that any scan presented in a "historic" or
"vaulted" context renders accurately within a grid matrix.

`ArchivedVisualsView` is no longer used as the generic fallback for every scan
tile with no immediately loadable bitmap. `ScanThumbnail` now distinguishes
between archived/missing visual assets and non-visual analyses that are waiting
on a biological reference image. Those non-visual paths render a dedicated
placeholder (`Reference pending`, `Reference unavailable`) keyed off the capture
modality instead of implying that a photo once existed and was archived.
`ScanThumbnail` and its projection/loading helpers live under `Core/UI` because
Scans, Explore Field Trips, and Profile consume them. The renderer delegates to
`ScanThumbnailLoader`, whose live dependency adapter is the only owner that
resolves image and spectrogram loaders. The service and final main-actor commit
both fence cancellation, and the view's typed task identity covers every input
that can change the requested source or rendering policy.

## 4. Scroll Physics: `FadingScrollView`

**Location**: `Core/UI/Components/FadingScrollView.swift`

A custom geometry wrapper used heavily within the `ProfileView` Contribution
Heatmap (52-week grid).

- **Geometric Vignetting**: Uses `.clear` boundary gradients overlapping the
  vertical or horizontal edges of a `ScrollView`.
- **Tracking Physics**: Translates scroll offset physics into dynamic opacity
  bounds, preventing hard clipping of visual data structures (like the 11pt heat
  nodes) when they reach the geometric constraints of the device screen.

## 5. Destructive Safeties: `ScanDeletionDialogModifier`

**Location**: `Features/Scans/Shared/Modifiers/ScanDeletionDialogModifier.swift`

A Scans-scoped `.viewModifier` that presents the shared destructive confirmation
for delete interactions.

- Replaces isolated inline `.alert` or `.confirmationDialog` blocks to ensure
  identical warning dialogue verbiage across all views.
- Owns only alert copy and completion handoff. The injected
  `ScanDeletionService` performs the single-record fetch, feedback, and
  repository erasure sequence; the modifier does not fetch SwiftData or resolve
  the app container.
- Treats an already-absent record as a completed presentation, while a missing
  scan selection performs no work and leaves completion untouched.

## 6. Confidence Badge: `ConfidenceBadge`

**Location**:
`Features/Insights/IdentificationReview/Confidence/Views/ConfidenceBadge.swift`

A tappable liquid-glass capsule shown in `InsightHeader` that communicates the
AI's confidence band — or the user's identification review decision — for a
scan.

- **Review state priority**: Before evaluating confidence bands, the badge
  checks `userIdentificationOverride` and `userConfirmedIdentification` passed
  from `InsightHeader`. Either state shows "Confirmed" (green,
  `checkmark.circle.fill`) and renders regardless of `confidenceScore`
  (including zero for historical scans). Tapping opens the explanation sheet
  where users can undo their review decision.
- **Band logic**: When no review state is active, derives label, color, and icon
  dynamically from `confidenceScore` against
  `MerianConfig.confidenceBands(for: isPro)`. High constraints for Free tier (≥
  96%), relaxed bounds for Pro (≥ 85%). Three bands exist: Strong (green),
  Possible (orange), Weak (gray).
- **Liquid glass aesthetic**: Layered `ZStack` — `ultraThickMaterial` base,
  volumetric color tint, glossy inner rim gradient, ambient border, and an
  animated holographic glare painted inside a fixed `Canvas`.
- **Shimmer animation**: For completed states only, an idle `.task` loop
  advances the Canvas gradient phase with a 3.5-second `easeOut` sweep every
  4–10 seconds (random interval). Canvas drawing cannot contribute translated
  child geometry to the Button's accessibility frame.
- **Analyzing mode** (`analyzingPhrase != nil`): All three glass fill layers
  collapse to `opacity(0)`, border switches to `Color.primary.opacity(0.2)`,
  icon changes to `sparkle`, and text uses the AI gradient. The optional private
  analyzing callback receives a tap without opening the explanation sheet. The
  glare Canvas is absent and its shimmer task exits. Each phrase is
  auto-suffixed with `...` if not already ending with one.
- **`RevealText` subview**: Phrase labels retain SwiftUI identity across text
  changes and use an opacity-only content transition. There is no translated
  mask view. The parent `HStack` retains its spring animation so capsule width
  interpolates smoothly as phrase length changes.
- **Accessibility boundary**: The native Button receives an explicit label but
  is not re-composed with `.accessibilityElement(children: .ignore)`, which
  would prevent an outer identifier from remaining discoverable as a Button.
  Callers keep the composed badge at intrinsic size; no decorative child may use
  `GeometryReader` or horizontal offsets.
- **Sheet integration**: Tap opens `ConfidenceExplanationSheet`. The sheet uses
  stored candidates for the alternatives-exhausted Review again path and
  policy-visible candidates for the normal review card. Review-state cards are
  evaluated in priority order: `AllCandidatesReviewedView`
  (`alternativesExhausted == true`) → `OverriddenView` → `ConfirmedView`. When
  no review state is active, the normal confidence explanation is shown
  unobstructed. The `candidateCount: Int` prop that previously threaded
  `BiologicalView → InsightHeader → ConfidenceBadge → ConfidenceExplanationSheet`
  has been removed.

## 7. Confidence Spectrum: `ConfidenceSpectrum`

**Location**:
`Features/Insights/IdentificationReview/Confidence/Views/ConfidenceSpectrum.swift`

A vertical timeline of `SpectrumNode` items inside `ConfidenceExplanationSheet`,
explaining what each band means.

- **Threshold parity**: Band percentage strings are computed dynamically based
  on the current user's entitlement tier via
  `MerianConfig.confidenceBands(for: isPro)`. This ensures that the displayed
  ranges in the UI always match the live badge thresholds exactly.
- **Current bands**: Strong (≥ 96% Flash / ≥ 85% Pro), Possible (75–95% Flash /
  65–84% Pro), Weak (below 75% Flash / below 65% Pro).

## 8. Overview: `OverviewCard`

**Location**: `Features/Insights/Content/Components/Cards/OverviewCard.swift`

An informational liquid-glass component displaying AI-enriched encyclopedic
extracts (`wikipediaOverview`), alongside a suite of dynamic biological
`KeyValueRow` metrics, and a native Safari overlay button.

- **Structural Rendering**: Dynamically parses and lists available biological
  telemetry such as `estimatedSizeCm`, `lifeStage`, `reproductiveCondition`,
  `sex`, and `ecologicalInteractions` while safely omitting empty values. Note:
  The `individualCount` metric is captured via backend Edge Functions for DWCA
  telemetry but intentionally omitted from this front-end display to conserve UI
  space.
- **Invasive status context**: Renders `isInvasive` as a compact
  `INVASIVE STATUS` summary rather than a native-status claim. When available,
  it adds a secondary assessed-region/confidence line and a muted
  `WHY NATUREBOOK THINKS THIS` rationale from the original AI invasive-status
  assessment. Historical scans with only the boolean keep the simple `Invasive`
  / `Not invasive` value.
- **Heuristic Filtering**: Enforces a strict ≥60 character length threshold on
  `wikipediaOverview`. When valid, the extract is capped at an 8-line truncation
  limit to avoid walls of text, terminating gracefully into a "Read more on
  Wikipedia" pill that relies on injected parent `$isSafariPresented` bindings.
- **Shared card chrome**: `OverviewCard` and `ExploreOverviewCard` keep separate
  data sourcing and visibility gates, but both render through focused helpers
  under `Features/Insights/Shared/Cards/Chrome/`: `InsightCardHeader.swift`,
  `WikipediaSummarySection.swift`, and `WikipediaReadMoreButton.swift`. Future
  Explore/Insights cards should reuse these presentational helpers instead of
  copying header typography or Wikipedia button styling.

## 9. Staggered Entrance: `CardEntranceModifier`

**Location**: `Core/UI/Modifiers/CardEntranceModifier.swift`

A `ViewModifier` that animates cards into view with a fade + 20pt upward slide
on first appearance. Applied via the `.cardEntrance(index:)` view extension.

- **Two-gate system**: Motion is suppressed when either
  `HardwareOrchestrator.shared.isAnimationEnabled` is `false` (expedition mode
  or thermal state ≥ `.serious`) **or** the system `accessibilityReduceMotion`
  environment value is `true`. When either gate is closed, the card renders at
  full opacity instantly with no transform.
- **Stagger via `index`**: Each card receives a sequential integer index. Delay
  is computed as `Double(index) × 0.07s`, producing a natural cascading entrance
  without firing simultaneous layout passes.
- **One-shot guard**: The `hasAppeared: Bool` state flag prevents re-animation
  on SwiftUI view identity changes or sheet re-presentations.
- **Spring curve**: `.spring(response: 0.5, dampingFraction: 0.78)` — responsive
  enough to feel alive without overshooting on dense content stacks.
- **Current usage**: `BiologicalView` applies indices 0–10 across
  `InsightHeader` (0), `ToxicityBanner` (1), conditional `CandidatesCard` (2),
  `FieldNotesCard` (3), `OverviewCard` (4), `HabitatAndDistributionCard` (5),
  `SpeciesObservationChartsCard` (6), `TaxonomyCard` (7),
  `SimilarSpeciesGallery` or its skeleton (8), `ScanInformationCard` (9), and
  `UserTagsCard` (10), giving a ~770ms full-stack cascade at nominal hardware.
  Conditional cards intentionally leave small stagger gaps when hidden; the
  remaining card indices stay stable.

## 10. Circular Control Chrome: `CircularMaterialControlModifier`

**Location**: `Core/UI/Modifiers/IconButtonModifiers.swift`

A small presentation-only modifier for compact circular material controls. It
owns only the shared frame, `Circle` material background, optional border, and
optional enforced `ColorScheme`; callers still own icon choice, color, haptics,
disabled state, accessibility labels, and action semantics.

- **Current usage**: `CaptureControlBar` audio/describe utility buttons,
  `CaptureFlashButton`, `PhotoLibraryButton`, `ToastBanner` dismiss affordances,
  `FieldNotesCard` dismiss, and the candidate-verification dismiss chips.
- **Abstraction boundary**: Do not use this modifier for controls with
  additional animated backgrounds, semantic fills, or domain-specific geometry.
  `DictationButton`, `CaptureButton`, avatars, feed action pills, and map menus
  remain isolated because their visual contracts are not identical.

## 11. Habitat Map: `HabitatAndDistributionCard`

**Location**:
`Features/Insights/SpeciesReference/Components/Habitat/HabitatAndDistributionCard.swift`

An edge-to-edge structural presentation component for the `gbifTaxonKey` density
map and LLM `habitatDescription`.

- **Edge-to-Edge Maps**: Rebuts the `.card()` background modifier found
  elsewhere, leveraging `-16pt` negative horizontal padding on its root `VStack`
  to cancel default `BiologicalView` safe area margins, allowing the map frame
  to stretch across the full width of the interface.
- **Shared map/text chrome**: `HabitatAndDistributionCard` and
  `ExploreHabitatDistributionCard` both use `.gbifHeatmapCardChrome()` from
  `GBIFHeatmapCardChrome.swift` for the 260 pt rounded map frame, shadow, and
  border treatment, and `InsightScientificNameStyler.highlightedText(...)` from
  `InsightScientificNameStyler.swift` for monospaced scientific-name
  highlighting. The cards still own their own loading/visibility behavior.
- **Loading continuity**: While habitat copy is still hydrating, the card keeps
  the same map chrome mounted and renders a compact pulsing text placeholder
  below the header. The retry loop stays local to `HabitatAndDistributionCard`;
  the live enrichment action is injected through
  `HabitatDistributionDependencies`, and the shared chrome does not own any
  enrichment behavior.
- **Null Fallbacks**: Wraps the map in a `ZStack` so that if
  `isEnrichmentLoading` completes but the GBIF occurrence dataset yields no
  result (nil `gbifTaxonKey`), `GBIFHeatmapMapView` still renders its
  world-level base map snapshot and drops a distinct "No distribution data
  available" pill directly atop it.
- **Tile ownership**: `GBIFHeatmapTileService` owns the bounded `URLSession`
  request and response decoding. `GBIFHeatmapViewModel` owns generation-fenced
  load state. `GBIFHeatmapMapView` retains only map composition, overlay copy,
  and two-finger zoom/pan state.

## 12. Observation Charts: `SpeciesObservationChartsCard`

**Location**:
`Features/Insights/SpeciesReference/Views/SpeciesObservationChartsCard.swift`

A reusable Swift Charts card for species-level observation patterns.

- **Shared surface**: Rendered inside Insight biological results and Species
  Dictionary pages. Both surfaces pass a species ID when available and the
  canonical scientific name.
- **Data ownership**: `SpeciesObservationStatsViewModel` owns generation-fenced
  loading and public-baseline coordination through injected dependencies.
  `Services/SpeciesObservationStatsDatabaseActor` fetches local SwiftData
  projections off the main actor, `Services/SpeciesObservationStatsDependencies`
  adapts the public client, and `Models/SpeciesObservationStatsReducer` owns
  normalization and bucket aggregation. Local scan data stays on-device; the
  network request contains only species identity.
- **Tabs**: Seasonality, History, and Life Stage. Sex is treated as per-scan
  Overview metadata rather than a species-level chart dimension.
- **Normalized compare scale**: Local and public series normalize independently
  so small personal logs remain visible beside large iNaturalist counts. Raw
  peak counts remain available in the footer and accessibility text.
- **Graceful states**: Empty, local-only, public-only, partial provider, and
  stale-cache states all keep the card mounted with explanatory copy.

## 13. Identification Candidates: `CandidatesCard`

**Location**:
`Features/Insights/IdentificationReview/Candidates/Components/CandidatesCard.swift`

A diagnostic card surfacing alternative species the AI genuinely considered,
with a full approve/deny UX for the user's identification review. The card
receives only policy-visible candidates; raw persisted candidate presence is not
enough to mount the card. Manages a local `ReviewState` enum: `.pending`,
`.confirmed`, `.overridden(to:)`.

- **Display gate**: `BiologicalView` obtains candidates from
  `CandidateReviewVisibilityPolicy.visibleCandidates(for:)`. The policy requires
  a biological, non-human, resolved subject with stored candidates; no user
  confirmation, override, flag, or exhausted alternatives; and
  `primaryConfidence < diagnosticTrigger` (`0.99` for both Flash and Pro). It
  then shows candidates when the primary confidence is below the tier's Strong
  threshold, or when a Strong primary has a top candidate with
  `confidenceScore >= 0.80` within `0.15` of the primary confidence.
- **Threshold sourcing**: Candidate persistence still follows
  `MerianConfig.confidenceBands(forInferenceTier: inferenceTier).diagnosticTrigger`,
  matching `FLASH_DIAGNOSTIC_TRIGGER` and `PRO_DIAGNOSTIC_TRIGGER` in
  `services/supabase/functions/_shared/identify/thresholds.ts`. Candidate
  display uses the on-device `CandidateReviewVisibilityPolicy` constants above,
  so a Strong scan can store hidden candidates until an alternative is
  competitive enough to show.
- **`.pending` state — PendingView**: Displays a high-end "Flayed Stack" teaser
  featuring a native `ZStack` of `FlayedCandidateThumbnail` views that
  asynchronously load species reference imagery. The view presents two
  full-width capsule action buttons beneath the stack: "Review alternatives"
  (triggers the dedicated `CandidateSwipeModal` via `.sheet`) and "Confirm
  species" (calls `InferenceEngine.confirmAIIdentification` natively). The
  legacy inline list expansion and localized "Not sure" toggles have been
  completely deprecated in favor of this dedicated swipe routing.
- **`.confirmed` state**: Emits `EmptyView()` — the card disappears.
  `ConfirmedView` in `ConfidenceExplanationSheet` handles the confirmed state
  display instead.
- **`.overridden(to:)` state**: Emits `EmptyView()` — the card disappears.
  `OverriddenView` in `ConfidenceExplanationSheet` handles the overridden state
  display instead.
- **`.flagged` state**: Always emits `EmptyView()`. Candidate exhaustion is
  tracked separately via `alternativesExhausted`; in that state the condensed
  `AllCandidatesReviewedView` inside `ConfidenceExplanationSheet` replaces the
  card with a "Review again" button that re-opens `CandidateSwipeModal` using
  stored candidates. The user can reconsider the alternatives and select one as
  an override without resetting first.
- **Data origin**: Candidates are scan-specific — they model genuine per-image
  uncertainty rather than species-level similarity. They are stored as a
  `candidates JSONB` column in `public.scans` (not in `species_dictionary`) and
  as `LocalScanRecord.candidatesData: Data?` (`MerianSchemaV28`) on-device. The
  override is stored as `LocalScanRecord.userIdentificationOverride: String?`
  (`MerianSchemaV29`) locally and in `public.scans.user_identification_override`
  in the cloud.

## 14. Similar Species Gallery: `SimilarSpeciesGallery`

**Location**:
`Features/Insights/SpeciesReference/Components/Lookalikes/SimilarSpeciesGallery.swift`

A horizontally scrolling carousel of ecologically similar lookalike species,
rendered in `BiologicalView` at card entrance index 4. Sourced from
`speciesData.similarSpecies` (a `SimilarSpecies` struct with an
`entries: [SimilarSpeciesEntry]` array), which is populated asynchronously by
`fetchAndApplyEnrichment` and persisted to
`LocalScanRecord.lookalikesData: Data?`.

- **Visibility gate**: Shown when `inferenceEngine.speciesData?.similarSpecies`
  is non-nil. While enrichment is in-flight
  (`inferenceEngine.isEnrichmentLoading == true`) and `similarSpecies` is still
  nil, `SimilarSpeciesGallery.Skeleton` renders in its place at the same index.
  The transition is animated via
  `.animation(.easeInOut, value: inferenceEngine.isEnrichmentLoading)`.
- **Entry filtering**: `validEntries` delegates to
  `SimilarSpecies.filteredEntries(...)`, removing blank scientific names, the
  active species, duplicate scientific names, and duplicate active common-name
  labels. Image load failure never removes a card.
- **Tap behavior**: The gallery accepts an optional `routeForSpecies` builder
  and emits `NavigationLink(value:)` cards when a route is available. Insight,
  Explore detail, and Species Dictionary use this path so tapped lookalikes push
  `SpeciesDictionaryPageContentView` in the current sheet/navigation stack,
  preferring `SimilarSpeciesEntry.speciesId` when present and falling back to
  `scientificName`; each route also carries a zero-PII species dictionary
  analytics entry point. The older `onSpeciesSelected` callback remains
  available for non-navigation hosts.
- **Effect ownership**: The gallery keeps horizontal scroll, placeholder, and
  tap routing in SwiftUI. `SimilarSpeciesGalleryDependencies` supplies selection
  feedback and fallback image dependencies. `SimilarSpeciesImageFetcher` owns
  generation-fenced observable state, while `SimilarSpeciesImageService` alone
  resolves Wikipedia/GBIF metadata and delegates bitmap loading to
  `LocalImageLoader`.
- **Relation explanation**: Relation metadata (`reason`, `visualTraits`,
  confidence, source, review status) remains in the model/API for curation and
  future UI, but the shipped card does not display rationale text. The visible
  overlay is intentionally limited to image, common name, and scientific name.
- **Image loading**: Each `SimilarSpeciesCard` uses a two-tier strategy:
  1. **Rich path** (`referenceImageUrl != nil`): `AsyncLocalImageView` loads the
     pre-resolved join-table URL. If the URL fails (network error, simulator,
     expired CDN link), local `@State var remoteImageFailed` flips to `true` and
     the card falls through to the leaf-icon placeholder. The card stays
     visible.
  2. **Fallback path** (`referenceImageUrl == nil`): A `.task` spawns
     `SimilarSpeciesImageFetcher`, whose injected `SimilarSpeciesImageService`
     runs the Wikipedia → GBIF image waterfall. If both fail, the card shows the
     leaf-icon placeholder.
- **Fixed geometry**: Cards are locked to `width: 200, height: 260`. This
  prevents extreme image aspect ratios from breaking the horizontal row layout.
- **Label**: Always "Similar species" — no confidence-gated label switching.
- **Header chrome**: The live gallery and skeleton both use `InsightCardHeader`,
  matching the same title/icon treatment as Overview, Taxonomy, Scan, Tags,
  Field Notes, Did You Know, and Explore detail cards.
- **Skeleton**: `SimilarSpeciesGallery.Skeleton` renders three placeholder cards
  with a pulsing opacity loop (`easeInOut(duration: 1.0).repeatForever`).

## Species Dictionary Reference Gallery

**Location**:
`Features/SpeciesDictionary/Detail/Components/SpeciesDictionaryReferenceGallery.swift`

Displays public species reference images from `/species-dictionary`.

- **Source label**: Each image keeps the existing source pill (`Naturebook`,
  `Wikipedia`, or `GBIF`) over the image. Unknown future source values decode as
  `Reference` so additive backend sources do not break the page.
- **Naturebook contributor badge**: A Naturebook-sourced image shows the
  contributor's current `@username` in a leading material capsule, truncated to
  one line. Tapping it opens `ExploreAuthorProfileSheet`; the trailing
  `Naturebook` source pill remains unchanged.
- **No page attribution footer**: The species page does not render
  attribution/license text below the gallery. The source and contributor
  capsules are the only attribution treatment on the page.
- **Fullscreen attribution**: Opening an image shows its fuller credit in the
  existing bottom overlay. Naturebook uses `@username · Naturebook` and never
  falls back to the stored display name or “Used with permission” text; if
  username data is unavailable, it shows only `Naturebook`. External images can
  include photographer, license, and source.
- **Fallback behavior**: Images without attribution metadata still render in iOS
  with source labeling. Future web renderers must run the shared public
  projection attribution audit before publishing reference media.

## 15. Candidate Swipe Experience: `CandidateSwipeModal`

**Location**: `Features/Insights/IdentificationReview/Candidates/Views/`
(Directory) plus
`Features/Insights/IdentificationReview/Candidates/Models/CandidateSwipeSession.swift`

A high-end, Tinder-style gesture interface allowing users to rapidly review and
identify AI alternative candidates. The `CandidateSwipeModal` is split into
focused component files, while the swipe-decision state lives in the
feature-local `CandidateSwipeSession` model:

- **`CandidateSwipeModal`**: The primary modal `.sheet` entry point. It owns
  animation, drag offsets, grid/stack mode, dismissal timing, and paywall
  routing. It delegates candidate decisions to `CandidateSwipeSession` and
  renders an explicit exhausted state when no alternatives remain.
- **`CandidateSwipeSession`**: Pure feature-local model for
  `remainingCandidates`, `confirmedCandidate`, `isExhausted`, and
  skip/reject/confirm/restart transitions. Unit tests cover the state
  transitions without SwiftUI animation concerns.
- **`SwipeableCandidateCard`**: The core structural view for the individual
  species cards. Integrates `SimilarSpeciesImageFetcher`, backed by
  `SimilarSpeciesImageService`, to asynchronously load up to 5 progressively
  loaded Wikipedia/GBIF visuals under a 3-stop vertical gradient that defaults
  to the `.images.first` thumb. Original capture, candidate gallery, and
  distinguishing feature are cases of one `CandidateCardPresentation` value and
  share one `.sheet(item:)`; the card must not add independent Boolean
  presenters for those destinations.
- **`CandidateImageExpandedView`**: Natively loads the `imageFetcher.images`
  array iteratively into a `.page` TabView carousel embedding the custom
  `ZoomableScrollView`.
- **`OriginalCaptureExpandedView`**: A dedicated single-image sheet container
  that provides pinch-to-zoom over the user’s original capture payload using
  `ZoomableScrollView`.
- **`OriginalCapturePiPView`**: A 58×76 pt picture-in-picture thumbnail embedded
  inside `SwipeableCandidateCard`. Tapping it triggers
  `OriginalCaptureExpandedView`.
- **`DistinguishingFeatureSheetView`**: Shows the full untruncated text of the
  `distinguishingFeature` that separates the candidate mathematically from the
  core ID inside a bottom sheet.
- **`ZoomableScrollView`**: Uses `UIViewRepresentable` and `UIScrollView` native
  delegate architecture spanning exactly 1× up to 4× zoom scales without UIKit
  delegate mutation conflicts.
- **`CandidateSwipeIndicator`**: An isolated view handling the complex 20%
  "deadzone" delay calculations that mask the `-90` degree radial progress
  stroke.
- **`CandidateActionBar`**: Replaces icon-only toolbars with explicit,
  text-labeled liquid glass `.ultraThickMaterial` buttons.
- **`GridSwipeableCell`**: The fallback wrapper component utilized when the user
  toggles the interface out of the Card Deck into the Grid layout.

## 16. Model Info Section: `ModelInfoSection`

**Location**:
`Features/Insights/IdentificationReview/Confidence/Views/ModelInfoSection.swift`

An informational card rendered inside `ConfidenceExplanationSheet`, positioned
between `ConfidenceSpectrum` and `AIMistakesBanner`. Communicates which
Naturebook AI tier processed the scan — using Naturebook AI branding rather than
raw model names to preserve the product abstraction layer and future-proof
against model changes.

- **Standard tier** (`inferenceTier == nil` or `"flash"`): Renders a blue `cpu`
  icon inside a circular fill, "Naturebook AI" headline in `.callout.bold`, a
  gray "Standard" capsule badge, and a footnote describing the speed-optimised
  standard model.
- **Pro tier** (`inferenceTier == "pro"`): Renders an indigo `sparkles` icon,
  "Naturebook AI" headline, an indigo "Pro" capsule badge, a footnote describing
  the enhanced reasoning model, and a "Powered by Gemini 2.5 Pro" line in
  `.caption2` / `.tertiary` style as a trust signal for pro users.
- **Branding rationale**: All user-facing copy uses "Naturebook AI" rather than
  "Gemini" to maintain product consistency with `ConfidenceHeader`
  ("Naturebook's AI") and to decouple the UI from any specific underlying model
  version. The "Powered by Gemini" attribution is surfaced only on the Pro tier
  where model provenance is a meaningful quality signal.
- **Visual style**: Matches the full-section glass card aesthetic of the sheet —
  `Color(uiColor: .secondarySystemFill).opacity(0.5)` fill,
  `RoundedRectangle(cornerRadius: 32, style: .continuous)`,
  `.white.opacity(0.1)` border stroke, and 24 pt inner padding — identical to
  `ConfidenceSpectrum` and `ProTips`.

## 17. Mixed-Media Carousel: `ImagesCarousel`

**Location**: `Features/Insights/Media/Carousel/ImagesCarousel.swift`

The full-width mixed-media carousel at the top of the Insight Sheet combines
live captures, persisted images, videos, standalone audio, descriptions, and
reference images in one horizontally scrolling strip. Visual pages retain
per-page pinch-to-zoom and pan.

Its local-path/remote-fallback renderer is the cross-feature
`Core/UI/Components/AsyncLocalImageView.swift`. The corresponding
`Core/UI/Services/AsyncLocalImageDependencies.swift` adapter is the only shared
UI owner that resolves `LocalImageLoader`; the Carousel supplies source values
and availability callbacks.

The domain-neutral pager, page identity value, zoom host, pagination dots, and
hero scroll-edge treatment shared with Field Trips live under
`Core/UI/Components/MediaCarousel`. Insight retains mixed-media assembly and
projects its feature-owned page identity into that Core UI boundary.

`ImagesCarousel` has **no direct `InferenceEngine` dependency**. All data is
injected as plain parameters, making the component reusable across both the live
camera pipeline and the offline queued-scan path:

| Parameter               | Type              | Source                                                                                                                                                                                                                             |
| ----------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scanId`                | `String?`         | Active queued snapshot ID, otherwise `viewModel.persistentScanId`; the carousel canonicalizes this identity for state retention                                                                                                    |
| `activeMedia`           | `ActiveScanMedia` | `viewModel.resolvedMedia(for:)` — exact active visual handoffs retain engine media; ordinary queued scans use `QueuedScanContext.activeScanMedia`; `displayMedia(_:)` applies reference suppression and current-scan deduplication |
| `referenceWikipediaUrl` | `String?`         | The current completed result's Wikipedia URL, used only to classify reference attribution                                                                                                                                          |
| `isProcessing`          | `Bool`            | `viewModel.isCarouselAnalysisActive(for:)` — exact non-attention visual handoffs stay active through pending/uploading/staged/inferencing; ordinary queued scans are active only while inferencing                                 |

- **`NativePageCarousel`**: A shared `UIViewControllerRepresentable` used by
  both Insight and the private Field-trip Goals hero, located in
  `Core/UI/Components/MediaCarousel`. It wraps `UIPageViewController`;
  `Coordinator.controllers: [ZoomPageViewController]` is populated eagerly so
  `AsyncLocalImageView.task` fires for all pages immediately, before the user
  swipes to them. `UIPageViewController`'s internal `UIScrollView` defers to the
  sheet's pan gesture without manual workarounds (unlike `TabView(.page)`).
- **`MediaCarouselPaginationDots`**: The shared bottom material capsule used by
  Insight and Field trips. It hides for a single page, clamps transient index
  changes safely, animates selection, and announces the current page count.
- **`MediaHeroTopScrollEdgeEffectModifier`**: Shared iOS 26 toolbar-underlay
  treatment for Insight and the Field-trip Goals hero. Each scroll view removes
  its top content margin and underlaps a transparent navigation bar while media
  is present; the modifier hides the native top scroll-edge effect over the
  image and restores it after the hero clears the toolbar.
- **`ZoomPageViewController`**: Each page controller. Embeds its SwiftUI content
  (image, video, audio, description, loading, or terminal state) inside a
  `ZoomScrollView`. Exposes `rootView: AnyView` as a computed property proxying
  into the inner `UIHostingController`, so equal ID/reuse-key pages receive
  presentation updates without discarding the mounted controller.
- **`ZoomScrollView`**: A `UIScrollView` subclass (`minimumZoomScale: 1.0`,
  `maximumZoomScale: 4.0`) that overrides `gestureRecognizerShouldBegin(_:)` to
  suppress its `panGestureRecognizer` when
  `zoomScale ≤ minimumZoomScale + 0.01`. This is the **only safe interception
  point** — replacing `panGestureRecognizer.delegate` directly throws
  `NSInvalidArgumentException` at runtime because UIKit requires the scroll view
  to remain its own pan delegate. At 1× UIPageViewController's swipe wins; above
  1× the inner scroll view handles panning.
- **Snap-back**: `scrollViewDidEndZooming` (pinch release) and
  `scrollViewDidEndDragging` (drag release while zoomed) both call
  `snapBackToIdentity`: pending deceleration is cancelled first, then
  `UIView.animate(usingSpringWithDamping: 0.72)` restores `zoomScale → 1.0` and
  `contentOffset → .zero` simultaneously.
- **Async page and reuse updates**: `updateUIViewController` handles the
  user-media page model resolving asynchronously after `makeCoordinator`. Equal
  ID/reuse-key pages preserve their controllers; insertions, removals, reorders,
  or reuse-key changes reconstruct only the affected controller list and
  nil-reset `UIPageViewController.dataSource` before reinstalling the selected
  page. This forces neighbor re-queries and prevents a source-family replacement
  from leaving a stale cached page visible.
- **Image failure handling**: `AsyncLocalImageView` reports success or failure
  to `ImagesCarousel`. The carousel keeps that status in a scan-scoped transient
  set and stably moves unavailable image pages behind available image pages
  without deleting user media or reference URLs. Audio, video, and description
  slots remain fixed; selection follows the same page identity across a reorder
  or advances to the first available visual when the selected image fails. A
  successful reconnect retry restores source order, and a `scanId` change clears
  the transient set, returns selection to the first page, and restores muted
  video playback.
- **Current-scan ownership boundary**: `ReferenceImageDeduplicationPolicy`
  removes loaded reference URLs matching the active scan's visual media before
  page construction. Naturebook media matches by normalized host/object path
  while external URLs retain strict identity. This preserves other scans'
  references, ordering, and attribution; an all-duplicate set becomes `.empty`
  and cannot create a stale page indicator.
- **Live-to-queue media continuity**: For an exact active visual handoff,
  `InsightSheetViewModel.resolvedMedia(for:)` keeps returning the engine's
  in-memory `ActiveScanMedia` rather than immediately replacing it with the
  persisted queue path. The canonical scan ID and page identities stay equal, so
  `NativePageCarousel` retains the selected index, decoded image, page
  controller, and focus interaction state. Ordinary queued navigation continues
  to use `QueuedScanContext` media.
- **Analysis clock ownership**: `AnalyzingMediaAnimationSession` is `@State` on
  `ImagesCarousel`, above the conditional `AnalyzingMediaOverlay`. Its
  `startedAt` value drives time-derived sweep and pulse progress through
  `TimelineView`. Exact owner changes do not reset it; a new canonical scan or a
  false-to-true analysis after completion does. Reduce Motion fixes the sweep at
  its midpoint. A Debug-only continuity value combines the session token and
  selected page ID for the seeded UI regression.
- **Video pause publisher allocation**:
  `InsightCarouselVideoPlaybackCoordinator` constructs its private subject and
  erased fullscreen-pause publisher once, and the production carousel keeps the
  coordinator in stable `@State`. Builder-only video pages without a coordinator
  share one cached inactive `Empty` publisher. Do not compute
  `eraseToAnyPublisher()` or allocate an `Empty` fallback from a recomposing
  view property.
- **`LiveCapturePageView`**: Asynchronously downsamples live capture `Data` in
  `DetachedWork.value(category: .imagePreparation)` and commits only the final
  `UIImage` to `@State`. It remains backed by `NSCache<NSNumber, UIImage>` keyed
  by `data.hashValue`, but ImageIO decode no longer runs from `body` layout
  evaluation.

## 18. Shared Scanning Experience: `ScanningExperienceView`

**Locations**:

- `Features/Insights/Content/Components/Scanning/ScanningExperienceView.swift`
- `Features/Insights/Content/Views/AnalyzingContentView.swift`
- `Features/Insights/Content/Views/QueuedContentView.swift`

`InsightContentRouterView` owns the mode split. `.analyzing` renders
`AnalyzingContentView` for foreground work unless a queued presentation value is
still being bound; `.queued` and the queued first-open guard render
`QueuedContentView`. Neither path retains a live `OfflineQueuedScan @Model`.

Both paths delegate their visible layout to generic
`ScanningExperienceView<SupplementalContent>`, which renders this stable order:

1. `ConfidenceBadge` with accessibility identifier `ScanningStatusBadge`.
2. Optional queue-only actionable status/recovery content.
3. `DidYouKnowCard`.
4. `FieldNotesCard`, when enabled for the presented scan.
5. `ScanInformationCard`.

The foreground wrapper supplies `InferenceEngine.scanningPhaseText`, live
location/weather telemetry, and the `.analyzing` Field-notes prompt. The queued
wrapper supplies exact snapshot telemetry and rotates honest phrases keyed by
scan ID, queue state, connectivity, server job status, attention state, and
retry state. Active `.inferencing` work reuses
`InferenceEngine.genericScanningPhasePhrases` for ordinary queued scans. An
exact active-visual live-to-queue handoff continues its contextual foreground
deck and keeps presentation-owned carousel media only after matching scan ID and
attempt generation. Prepared visual, audio, Describe, and stale-owner transfers
cannot inherit that media or contextual deck. Queue-state and connectivity
changes cannot reset the visual cursor; **Waiting for connection** temporarily
overlays it without consuming a phrase. Phrase rotation uses
`MerianConfig.scanningPhaseRotationIntervalNs`.

For a foreground visual scan, that single text binding progresses from a
morphology-only generic phrase to an immediate qualifying Vision category and,
on the current toolchain, five complete validated dominant-color, saturation,
lighting, light-contrast, and surface-detail cues derived from the bounded image
at the next phrase tick. An eligible future Foundation provider may replace that
deterministic deck with richer visible traits. Specificity never moves backward.
Visible traits use natural verb-led copy such as **Analyzing gray and green
colors**, **Reviewing softly colored areas**, or **Observing light and shadow
areas**, not `Color: description` labels or internal **moderate**/**balanced**
buckets. The badge keeps an opacity-only label transition and intrinsic native
Button bounds across these width changes. Every foreground visual label in the
active deck appears before that deck loops to its first phrase. Do not
reintroduce translated label geometry or a second foreground scanning component.
Audio-only and Describe analysis, plus active queued inference, retain their
existing cloud-analysis phrase sources.

Queued lifecycle polling and the exact one-second/350-millisecond task timing
remain in `QueuedContentView`. `QueuedContentViewModel` owns retry single-flight
and refresh request identity; `QueuedContentDependencies` owns scheduling,
durable re-fetch, retry mutation, event, and feedback effects.
`QueuedRetryPresentation` alone maps stable codes to safe reason text,
countdowns, and actions; raw stored errors never render. Future online deadlines
may show **Retry now**, offline deadlines show no countdown or retry action, and
elapsed deadlines show no redundant helper at all. A non-network action such as
**View plans** may remain available offline. Consent, entitlement,
missing-media, retry-limit, and terminal states receive category-appropriate
copy/action. The block stays above the educational fact card and adds no
heading, sync explanation, media-kind summary, or approximate file size.

`QueuedScanContext` is copied while the SwiftData row is live, so queue deletion
and completed-result handoff cannot detach data still needed by the view. The
shared component intentionally omits a trailing `Spacer`;
`InsightContentRouterView` provides the universal bottom spacing.

## 19. Drag-to-Confirm Pill: `SlideToConfirm`

**Location**: `Core/UI/Components/SlideToConfirm.swift`

A pill-shaped drag-to-confirm control that replicates the iPhone unlock gesture,
used in `CandidateVerificationView` and `CandidateAlternativesView` to gate
identification confirmations behind intentional gesture input.

- **Drag mechanics**: A circle thumb slides from the left edge to the right
  within a capsule-shaped track. At ≥88% travel, `onConfirm` fires
  automatically. The track fills progressively behind the thumb as drag
  progresses. The label fades out as the thumb advances (opacity multiplier
  `1.0 - progress * 2.5`).
- **Snap-back**: Releasing before the 88% threshold springs the thumb back via
  `.spring(response: 0.45, dampingFraction: 0.72)` with a `triggerLightImpact()`
  haptic.
- **Completion state**: On trigger, the thumb snaps to full width with
  `.spring(response: 0.28, dampingFraction: 0.82)`, chevrons are replaced by a
  checkmark, and `onConfirm` is called by an identity-keyed `.task` after 380 ms
  so the user sees the completed state before the view transitions. Unmounting
  the control cancels the callback instead of retaining its view state past
  teardown.
- **Haptics**: `triggerSuccessPulse()` on threshold reached;
  `triggerLightImpact()` on snap-back.
- **Label**: Accepts dynamically injected strings (e.g.
  `"Confirm \(viewModel.resolvedHeaderTitle)"`). To handle long scientific names
  without breaking the UI pill geometry on single lines, the `<Text>` label
  aggressively shrinks typography via `.minimumScaleFactor(0.6)` before
  resorting to truncation.
- **Disabled**: Once `isCompleted = true`, the component ignores further drag
  input.

## 20. Field Chat: `FieldChatToolbarButton` and `InsightChatSheet`

**Location**:
`Features/Insights/Toolbars/BottomToolbar/InsightBottomToolbar.swift` and
`Features/FieldChat/Views/InsightChatSheet.swift`, with Dictionary presentation
in `Features/SpeciesDictionary/Detail/Views/SpeciesDictionaryPageView.swift`

The floating Field chat button and sheet are shared by eligible Insight scans
and every visible Explore post detail, including the viewer's own posts. The
source candidate also places it at the bottom right of every loaded canonical
in-app Species Dictionary detail while keeping Share in the top bar; loading,
error, and invalid-subject states hide the Dictionary bottom bar. Explore and
Dictionary each create a private conversation owned by the requesting viewer.
Other viewers cannot see it. On Explore detail, the button is shown while
browsing post content and is removed when the comment composer becomes sticky or
receives focus. It returns after scrolling back above the sticky-comment
threshold. While the floating control is hidden, `ExplorePostDetailMenuButton`
exposes the same Field chat action. Media type does not participate in Field
chat eligibility; image, video, audio, and mixed-media posts use the same
presentation rules. When an Explore thread has no messages, the only explanatory
copy below the question is `This Field chat is private and visible only to you.`
Technical model-context limitations are enforced by the source-specific backend
route and belong in engineering/API documentation rather than additional
empty-state disclaimers.

Copying an assistant response writes it to the pasteboard and shows the
transient `Copied` badge inside `InsightChatAnswerControls`. It does not emit a
second `Copied answer` payload to the parent toast host, so no duplicate
confirmation appears behind the sheet on Insight, Explore, or Species
Dictionary.

Dictionary component reuse is release-held until the
[canonical candidate blockers](16-species-dictionary.md#candidate-release-status)
are fixed and proven; this guide does not override that status.

## 21. Shared Feedback Surfaces: `ToastBanner` and `MilestoneToastBanner`

**Location**: `Core/UI/Feedback/`

`ToastBanner` owns only compact visual chrome and an optional close affordance.
Ordinary feedback uses a typed, lightweight `ToastPayload`; executable actions
remain view-owned. Callers mount it through an alignment-scoped overlay, so no
transparent full-screen hit region covers the underlying UI. Passive payloads
render no controls and disable hit testing. A payload claims interaction only
when both its typed action descriptor and a matching view-owned handler exist;
an incompletely wired action remains pass-through. Interactive payloads
intercept only the intrinsic card. Auto-dismiss tasks are cancellable and
compare message identity before clearing state; a timer from an old message
cannot remove its replacement. Manual close and action callbacks perform the
same UUID check, and replacement cards receive a new SwiftUI identity so their
transition and timer restart together. Entry and exit animation transactions are
scoped to the overlay, not the surrounding feature root. Feature producers
assign payload/action state directly and must not wrap those assignments in
`withAnimation`; the shared modifier is the sole owner of toast insertion and
removal motion.

`MilestoneToastBanner` is the active surface for the bounded FIFO
`MilestoneToastPresenter` owned by `AppDIContainer`. The stacked
`MilestoneToastHostRegistry` retains at most eight host UUIDs, gives the most
recently mounted eligible host sole presentation ownership, and restores the
prior host on unmount. Only the front item starts the 3.5-second timer, haptic,
and VoiceOver announcement or receives hit testing. Up to two queued items
render as decorative backplates; their payload subtrees stay unmounted, avoiding
duplicate material/text layers and queued-card redraws. Field trip items show
goal artwork, a goal-complete title, and outing name; banner taps request typed
`AppRoute` destinations through the host's environment-injected coordinator
rather than presenting a sibling sheet or reaching into the production DI
singleton. The ordinary system toast unmounts only when it shares the milestone
stack's alignment, preventing a single Z-plane collision without hiding
independent top/bottom feedback. The active card's drag offset, scale, and
dismissal opacity apply only to its foreground surface. Decorative backplates
are laid out from the card's stable bounds outside that transform, so they
remain anchored while a swipe reveals the queue beneath instead of leaving with
the dismissed card and jumping back. Account and app-session generations clear
the visual queue and reject stale async enqueues. Presentation effects are
claimed once per item, and a remounted host receives only the remaining lifetime
rather than replaying haptics, announcements, or a fresh timer. Automatic
dequeue mutates presenter state directly. The outer feedback overlay animates
only empty/non-empty visibility; `MilestoneToastStack` alone animates
active-item UUID replacement, and the toast surface alone animates its clamped
decorative-layer count. Do not key an outer animation to every queued UUID or
wrap presenter mutations in `withAnimation`.

Progress for Scans batch export and non-biological bulk deletion uses a compact
pass-through badge, not `ToastBanner` as domain state. The affected mutation
controls are disabled for the operation snapshot while scrolling and unrelated
navigation remain available. See the canonical
[Event and Presentation Routing contract](../system-architecture/10-event-and-presentation-routing.md).

## 22. Personal Scan Labels: `UserTagsCard`

**Location**: `Features/Insights/Content/Components/Tags/UserTagsCard.swift`

`UserTagsCard` renders the horizontal capsule collection and add-tag alert for a
saved biological or non-biological scan. It owns draft, layout, animation, and
accessibility wiring only. `UserTagValidation` owns the 50-label, 64-character,
256-byte, and control-character policy; `UserTagsViewModel` owns the local
mutation and rollback; and `UserTagsDependencies` owns persistence, ordered
account-fenced Supabase synchronization, and typed search invalidation. No
networking or shared-manager resolution belongs in the component.

The local SwiftData save is the effect boundary. Failed saves restore the prior
tag list and emit no cloud or search effect. Successful saves enqueue immutable
cloud snapshots behind prior mutations so stale completion cannot overwrite the
latest tag array. Remote synchronization remains best-effort and cannot roll
back the committed local/search state.
