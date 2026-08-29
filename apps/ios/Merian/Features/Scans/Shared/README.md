# Scans Shared

`Scans/Shared` owns scan-library presentation and interaction primitives reused
by multiple Scans product areas. App-wide or cross-feature presentation belongs
in `Core` instead.

## Ownership

- `Models/QueuedScanSnapshot.swift` is the detached value boundary for queued
  grid rows. Its automatic recovery policy separates durable queue state from
  live network and large-video policy. Manual retry visibility delegates to the
  canonical `ScanQueueState` policy shared with `QueuedScanContext`.
- `Services/ScansGridInteractions.swift` owns the injected selection-feedback
  effects used by the grid. `Services/ScanDeletionService.swift` owns the
  single-scan fetch, destructive feedback, and repository erasure sequence.
- `Components/Grid/ScansGrid.swift` owns Scans-only completed, queued,
  selection, and add-tile composition. Product areas provide route, retry,
  delete, and context-menu actions through callbacks.
- `Modifiers/ScanDeletionDialogModifier.swift` owns only the shared alert copy
  and presentation completion handoff; it delegates mutation work to
  `ScanDeletionService`.

The live service dependencies may adapt `AppDIContainer` infrastructure, but
Shared views and components do not resolve the app container, fetch SwiftData,
or call loaders, repositories, or endpoints directly.

Grid composition, selection feedback, deletion presentation, and their live UI
dependency adapters are main-actor owned. Repository erasure remains an injected
async service action. Fix isolation at those boundaries; do not make live
haptics or SwiftUI state nonisolated merely to construct a default dependency.

## Core Boundaries

- `Core/UI/Components/ScanThumbnail.swift`,
  `Core/UI/Models/ScanThumbnailPresentation.swift`, and
  `Core/UI/Services/ScanThumbnailLoader.swift` own the scan thumbnail used by
  Scans, Explore Field Trips, and Profile.
- `Core/UI/Components/EmptyStateView.swift` owns the generic empty state used by
  Scans, Explore, and Species Dictionary.
- `Core/Data/Images/ScanThumbnailBackfillCandidate.swift` owns immutable inputs
  for the Core reference-thumbnail recovery actor.

Do not move these cross-feature declarations back into Scans. Conversely,
Scans-specific queue recovery, selection, retry, and deletion policy must not be
promoted into Core UI.

## Verification

Focused policy coverage lives in:

- `MerianTests/Core/UI/ScanThumbnailPresentationTests.swift`
- `MerianTests/Core/UI/ScanThumbnailLoaderTests.swift`
- `MerianTests/Features/Scans/Shared/ScansSharedPolicyTests.swift`
- `MerianTests/Features/Scans/Shared/ScanDeletionServiceTests.swift`

Also run the Scans Shell thumbnail-pipeline and Map fallback suites when
changing thumbnail projection or backfill eligibility.
