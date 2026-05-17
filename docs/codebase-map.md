# Current Codebase Map

Last reviewed: 2026-05-16.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed for
developer convenience and should be regenerated with `xcodegen generate` after
target, package, entitlement, build setting, or source-list changes.

| Target | Type | Source | Deployment |
|---|---|---|---|
| `Merian` | iOS application | `merian/` | iOS 17.2 |
| `MerianExploreWidget` | WidgetKit app extension | `MerianExploreWidget/`, `merian/Features/Explore/Widgets/ExploreWidgetCache.swift` | iOS 17.2 |
| `MerianWatch` | watchOS companion app | `MerianWatch/` | watchOS 10.0 |
| `merianTests` | Unit tests | `merianTests/` | iOS 17.2 |
| `merianUITests` | UI tests | `merianUITests/` | iOS 17.2 |

Tracked build config:

- `Config.xcconfig` stores app-facing runtime values such as Supabase URL,
  Supabase publishable key, RevenueCat, PostHog, TelemetryDeck, and Google
  Sign-In client IDs. These are bundled client config values, not backend-only
  secrets.
- `Signing.xcconfig` includes optional ignored `Signing.local.xcconfig`.
- `Signing.local.example.xcconfig` is the template for a local Apple Developer
  Team ID.

## App Entry And Dependency Injection

| Area | File | Notes |
|---|---|---|
| SwiftUI app entry | `merian/App/MerianApp.swift` | Builds the `ModelContainer` from `CurrentSchema`, performs corruption-aware store quarantine, configures `ScanRepository`, migrates species display preferences, initializes TelemetryDeck outside tests, applies global theme to `UIWindow`, and handles `merian://explore/post/<id>` deep links. |
| App delegate bridge | `merian/App/MerianApp.swift` | Owns background `URLSession` completion handoff and push token callbacks. |
| Dependency container | `merian/Core/AppDIContainer.swift` | Injects hardware, AI, sync, network, analytics, security, settings, and profile dependencies through SwiftUI `@Environment`. |
| Detached work helper | `merian/Core/AppDIContainer.swift` | Small wrapper for intentional detached image, database, file-system, and bootstrap work. |

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianSchemaV42
```

`MerianSchemaV42` is declared in `merian/Models/SchemaVersions.swift` and points
at the global active model classes in `merian/Models/ActiveSchema/`.

Active persistent models:

- `LocalScanRecord`
- `OfflineQueuedScan`
- `CapturedMediaEntry`
- `ScanCollection`
- `PendingCloudDeletionTask`
- `UserSpeciesPreference`

Recent schema milestones:

- V40 introduced `capturedMediaJSON` and `coverImagePath` as scalar mixed-media
  durability mirrors.
- V41 introduced `CapturedMediaEntry` and relationship mirrors for queued and
  completed scans.
- V42 added first-class `fieldNotes` columns to `LocalScanRecord` and
  `OfflineQueuedScan`, while preserving the legacy UserDefaults bridge through
  `FieldNotesRepository`.

Historical schema snapshots V1 through V39 live under `merian/Models/Schema/`.
V40 through V42 live in `SchemaVersions.swift` alongside the migration plan.

## Feature Modules

| Feature | Current files | Responsibility |
|---|---|---|
| Capture Workspace | `merian/Features/CaptureWorkspace/` | Three-page capture shell for `.visual`, `.audio`, and `.describe`, fixed overlay controls, staging, refinement scans, and live/offline submission orchestration. |
| Visual capture | `merian/Features/CaptureWorkspace/Modalities/Visual/` | Camera preview, focus/zoom gestures, cropper, flash, photo picker, viewfinder hints, and visual capture components. |
| Audio capture | `merian/Features/CaptureWorkspace/Modalities/Audio/` plus `merian/Core/Hardware/AudioCaptureManager.swift` and `SpectrogramActor.swift` | 15-second WAV recording, spectrogram, SNR gauge, review/playback, staging, and `/identify-multimodal` submission. |
| Describe capture | `merian/Features/CaptureWorkspace/Modalities/Describe/` | Typed observation input, guided question funnels, subject keyword matching, and `SpeechManager` dictation. |
| Insights | `merian/Features/Insights/` | Insight sheet state, biological/non-biological/queued content, candidates/review UX, field notes, sharing, collection actions, media export, and reference hydration. |
| Scans | `merian/Features/Scans/` | `ScansSheetView`, `ScansManager`, library/collections tabs, search index, selection, queued-scan snapshots, non-biological isolation, and collection management. |
| Explore | `merian/Features/Explore/` | Public feed/map, post detail, comments, notifications, author profiles, follow/like/comment/reaction actions, and widget snapshot writing. |
| Profile | `merian/Features/Profile/` | Profile tab, settings, RevenueCat plan screens, geoprivacy, notifications, achievements, heatmap, export, danger-zone actions. |
| Species Dictionary | `merian/Features/SpeciesDictionary/` | Public species dictionary page, reference gallery, similar-species entry points, and preferred common-name display. |
| Onboarding | `merian/Features/Onboarding/` | Permission priming flow and `hasCompletedOnboarding` gate. |

## Core Modules

| Core area | Current files | Responsibility |
|---|---|---|
| AI | `merian/Core/AI/` | `InferenceEngine`, edge DTOs, parse/save actor, and on-device viewfinder intelligence. |
| Analytics | `merian/Core/Analytics/` | TelemetryDeck wrapper, PostHog wrapper, usage quota, and gamification notification manager. |
| Data/Database | `merian/Core/Data/Database/` | `BackgroundDatabaseActor`, `FileIOActor`, `ScanRepository`, and `HistoricalDatabaseActor`. |
| Data/Images | `merian/Core/Data/Images/` | Archive rescue, photo-library access, thumbnails, local image loading, and RAM image cache. |
| Offline sync | `merian/Core/Data/OfflineSync/` | Queue state machine, upload URLSession handoff, background inference replay, audio queue helpers, and sync phase state. |
| Hardware | `merian/Core/Hardware/` | Camera, environment context, audio, spectrogram, haptics, thermal/battery orchestration, and push token management. |
| Network | `merian/Core/Network/` | Supabase auth/client facade, TLS-pinned network client, Explore DTOs, species dictionary DTOs, and Keychain manager. |
| Security | `merian/Core/Security/` | Circuit breaker, device identity, RevenueCat, and social guard. |
| UI | `merian/Core/UI/` | Shared controls, tab bar, media mode toggle, slide-to-confirm, reusable modifiers, and theme model. |
| Utilities | `merian/Core/Utilities/` | App lifecycle, app events, config constants, field notes repository, image downsampling, errors, sharing, date/size helpers, and UserDefaults keys. |

## SwiftData Actors

| Actor | File | Lifecycle |
|---|---|---|
| `BackgroundDatabaseActor` | `merian/Core/Data/Database/BackgroundDatabaseActor.swift` | Ad-hoc for live writes/enrichment/collections; long-lived through `OfflineQueueManager.resolvedInferenceDbActor(container:)` for queue inference state transitions. |
| `HistoricalDatabaseActor` | `merian/Core/Data/Database/ScanRepository.swift` | Ad-hoc per historical sync, streaming one cloud page at a time. |
| `ProfileDatabaseActor` | `merian/Features/Profile/Components/Profile/UserStats.swift` | Ad-hoc for profile screen calculations; long-lived via `OfflineQueueManager.resolvedProfileDbActor(container:)` for post-inference awards. |
| `SearchDatabaseActor` | `merian/Features/Scans/ViewModels/ScansManager.swift` | Ad-hoc for incremental search payload extraction from persistent IDs. |
| `ArchiveDatabaseActor` | `merian/Core/Data/Images/ArchiveManager.swift` | Archive bookkeeping and rescue state. |
| `FileIOActor` | `merian/Core/Data/Database/FileIOActor.swift` | Singleton actor for image/audio file writes, deletes, and path validation. |

## Supabase Edge Function Inventory

Inference and media staging:

- `generate-upload-urls`
- `identify`
- `identify-multimodal`
- `identify-describe`
- `audio-spec`
- `check-scan-status`
- `enrich-scan`

Explore and social:

- `get-explore-feed`
- `get-explore-map-points`
- `get-explore-post`
- `get-explore-post-detail`
- `get-explore-author-profile`
- `get-explore-author-posts`
- `get-explore-comments`
- `get-explore-notifications`
- `get-explore-unread-notification-count`
- `mark-explore-notifications-read`
- `share-scan-to-explore`
- `unshare-explore-post`
- `update-explore-field-notes`
- `get-scan-explore-share-state`
- `set-explore-post-like`
- `set-user-follow`
- `create-explore-comment`
- `delete-explore-comment`
- `toggle-explore-comment-reaction`
- `report-explore-comment`
- `register-push-device`
- `send-push-notification`
- `block-user`

Data lifecycle, identity, and exports:

- `sync-collections`
- `merge-ghost-profile`
- `safe-delete`
- `delete-scan`
- `flag-issue`
- `request-export-dwca`
- `export-dwca`
- `revenuecat-webhook`
- `get-filtered-discovery-feed`

Scheduled/background workers:

- `refresh-species-content`
- `refresh-merian-reference-images`
- `auto-purge-nonbio`
- `auto-purge-domesticated`

Every function above has a `[functions.<name>]` entry in `supabase/config.toml`.
`merge-ghost-profile` and `request-export-dwca` intentionally use
`verify_jwt = true`; app-facing functions generally set `verify_jwt = false`
and perform identity checks inside shared handler code.

## Test Inventory

Swift unit tests live under `merianTests/` and cover:

- Active schema models and migration invariants.
- Capture workspace staging, camera analysis, audio/describe helpers, and
  queued handoff flows.
- Core AI, network, security, hardware, analytics, utilities, and data actors.
- Profile achievements, heatmap/stats, Explore, Species Dictionary, Insights,
  Scans, and onboarding view models.

UI tests live under `merianUITests/` and include launch coverage plus seeded
flows in `MerianApp.swift` through `UITestSeedCoordinator`.

Deno tests live under `supabase/functions/_tests/` plus function-local
`*.test.ts` files. Run from `supabase/functions` with:

```bash
deno task test
```

## Documentation Maintenance Checklist

When changing the codebase, update docs in the same change if any of these move:

- `CurrentSchema`, schema model fields, or migration stages.
- App target deployment versions, entitlements, packages, or XcodeGen targets.
- Edge Function request/response bodies, auth policy, config entries, or storage
  lifecycle behavior.
- Capture modes, offline queue state transitions, media staging, or field-notes
  ownership.
- Feature module names, file paths, or view-model/actor ownership.
- Public Explore surfaces, notification behavior, widget cache shape, or privacy
  contracts.
