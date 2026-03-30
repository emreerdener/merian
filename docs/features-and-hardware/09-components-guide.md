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
- **Z-Index Layering**: Hovers persistently at the bottom of the `CameraRootView` camera feed, allowing the viewfinder to bleed infinitely to the edges of the device screen.
- **Notification Badging**: Subscribes to `@AppStorage("hasUnseenScan")` to overlay an 8pt red continuous notification dot on the Scans icon, tracking silent inference completions without manual `@State` plumbing.

## 3. Archival Aesthetics: `ArchivedVisualsView`
**Location**: `Core/UI/Components/ArchivedVisualsView.swift`

Provides a standardized visual protocol for scans that have been archived or flagged. It encapsulates dark scrim overlays, watermark iconography, and desaturation modifiers, ensuring that any scan presented in a "historic" or "vaulted" context renders accurately within a grid matrix.

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

A tappable liquid-glass capsule shown in `InsightHeader` that communicates the AI's confidence band for a scan.
- **Band logic**: Derives label, color, and icon dynamically from `confidenceScore` against `MerianConfig.confidenceBands(for: isPro)`. High constraints for Free tier (≥ 93%), relaxed bounds for Pro (≥ 85%). Three bands exist: Strong (green), Possible (orange), Weak (gray).
- **Liquid glass aesthetic**: Layered `ZStack` — `ultraThickMaterial` base, volumetric color tint, glossy inner rim gradient, ambient border, animated holographic glare sweep.
- **Shimmer animation**: An idle `.task` loop triggers a 3.5-second `easeOut` glare sweep every 4–10 seconds (random interval), creating a living feel without continuous CPU usage.
- **Sheet integration**: Tap opens `ConfidenceExplanationSheet`.

## 7. Confidence Spectrum: `ConfidenceSpectrum`
**Location**: `Features/Insights/Components/Confidence/ConfidenceSpectrum.swift`

A vertical timeline of `SpectrumNode` items inside `ConfidenceExplanationSheet`, explaining what each band means.
- **Threshold parity**: Band percentage strings are computed dynamically based on the current user's entitlement tier via `MerianConfig.confidenceBands(for: isPro)`. This ensures that the displayed ranges in the UI always match the live badge thresholds exactly.
- **Current bands**: Strong (≥ 93% Flash / ≥ 85% Pro), Possible (75-92% Flash / 65-84% Pro), Weak (below 75% Flash / below 65% Pro).

## 8. Overview: `OverviewCard`
**Location**: `Features/Insights/Components/Cards/OverviewCard.swift`

An informational liquid-glass component displaying AI-enriched encyclopedic extracts (`wikipediaOverview`), alongside a suite of dynamic biological `KeyValueRow` metrics, and a native Safari overlay button.
- **Structural Rendering**: Dynamically parses and lists available biological telemetry such as `estimatedSizeCm`, `lifeStage`, `reproductiveCondition`, and `ecologicalInteractions` while safely omitting empty values. Note: The `individualCount` metric is captured via backend Edge Functions for DWCA telemetry but intentionally omitted from this front-end display to conserve UI space.
- **Heuristic Filtering**: Enforces a strict ≥60 character length threshold on `wikipediaOverview`. When valid, the extract is capped at an 8-line truncation limit to avoid walls of text, terminating gracefully into a "Learn more on Wikipedia" pill that relies on injected parent `$isSafariPresented` bindings.

## 9. Staggered Entrance: `CardEntranceModifier`
**Location**: `Core/UI/Modifiers/CardEntranceModifier.swift`

A `ViewModifier` that animates cards into view with a fade + 20pt upward slide on first appearance. Applied via the `.cardEntrance(index:)` view extension.

- **Two-gate system**: Motion is suppressed when either `HardwareOrchestrator.shared.isAnimationEnabled` is `false` (expedition mode or thermal state ≥ `.serious`) **or** the system `accessibilityReduceMotion` environment value is `true`. When either gate is closed, the card renders at full opacity instantly with no transform.
- **Stagger via `index`**: Each card receives a sequential integer index. Delay is computed as `Double(index) × 0.07s`, producing a natural cascading entrance without firing simultaneous layout passes.
- **One-shot guard**: The `hasAppeared: Bool` state flag prevents re-animation on SwiftUI view identity changes or sheet re-presentations.
- **Spring curve**: `.spring(response: 0.5, dampingFraction: 0.78)` — responsive enough to feel alive without overshooting on dense content stacks.
- **Current usage**: `BiologicalView` applies indices 0–7 across `InsightHeader`, `ToxicityBanner`, `ConservationBanner`, `OverviewCard`, `HabitatAndDistributionCard`, `TaxonomyCard`, `ScanInformationCard`, and `UserTagsCard`, giving a ~560ms full-stack cascade at nominal hardware.

## 10. Habitat Map: `HabitatAndDistributionCard`
**Location**: `Features/Insights/Components/Cards/HabitatAndDistributionCard.swift`

An edge-to-edge structural presentation component for the `gbifTaxonKey` density map and LLM `habitatDescription`.
- **Edge-to-Edge Maps**: Rebuts the `.card()` background modifier found elsewhere, leveraging `-16pt` negative horizontal padding on its root `VStack` to cancel default `BiologicalView` safe area margins, allowing the map frame to stretch across the full width of the interface.
- **Top Corner Radii**: The 280-pt-tall shimmering loading placeholder and the live `GBIFHeatmapMapView` apply a custom `TopRoundedRectangle` shape, bringing a subtle UI rounding exclusively to their top-left/top-right edges without adding a cutout effect below.
- **Null Fallbacks**: Wraps the map in a `ZStack` so that if `isEnrichmentLoading` completes but the GBIF occurrence dataset yields no result (nil `gbifTaxonKey`), `GBIFHeatmapMapView` still renders its world-level base map snapshot and drops a distinct "No distribution data available" pill directly atop it.
