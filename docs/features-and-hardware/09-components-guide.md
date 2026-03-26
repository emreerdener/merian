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
- **Band logic**: Derives label, color, and icon from `confidenceScore` against `MerianConfig.confidenceStrongThreshold` (0.90) and `MerianConfig.confidencePossibleThreshold` (0.70). Three bands: Strong (green ≥ 90%), Possible (orange 70–89%), Weak (gray < 70%).
- **Liquid glass aesthetic**: Layered `ZStack` — `ultraThickMaterial` base, volumetric color tint, glossy inner rim gradient, ambient border, animated holographic glare sweep.
- **Shimmer animation**: An idle `.task` loop triggers a 3.5-second `easeOut` glare sweep every 4–10 seconds (random interval), creating a living feel without continuous CPU usage.
- **Sheet integration**: Tap opens `ConfidenceExplanationSheet`.

## 7. Confidence Spectrum: `ConfidenceSpectrum`
**Location**: `Features/Insights/Components/Confidence/ConfidenceSpectrum.swift`

A vertical timeline of `SpectrumNode` items inside `ConfidenceExplanationSheet`, explaining what each band means.
- **Threshold parity**: Band percentage strings are computed from `MerianConfig.confidenceStrongThreshold` and `MerianConfig.confidencePossibleThreshold` at type scope (`private static let`), so the displayed ranges always match the live badge thresholds without manual string updates.
- **Current bands**: Strong (90–100%), Possible (70–89%), Weak (below 70%).
