# Current Codebase Map

Last reviewed: 2026-07-02.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed for
developer convenience and should be regenerated with `xcodegen generate` after
target, package, entitlement, build setting, or source-list changes.

| Target | Type | Source | Deployment |
|---|---|---|---|
| `Merian` | iOS application | `apps/ios/Merian/` | iOS 17.2 |
| `MerianExploreWidget` | WidgetKit app extension | `apps/ios/widgets/Explore/`, `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift` | iOS 17.2 |
| `MerianMessagesExtension` | Messages app extension | `apps/ios/messages/MerianMessagesExtension/`, `apps/ios/messages/ScanSharing/Shared/` | iOS 17.2 |
| `MerianWatch` | watchOS companion app | `apps/watch/MerianWatch/` | watchOS 10.0 |
| `merianTests` | Unit tests | `apps/ios/MerianTests/` | iOS 17.2 |
| `merianUITests` | UI tests | `apps/ios/MerianUITests/` | iOS 17.2 |
| `@merian/web` | Next.js public web app | `apps/web/` | Node/Next.js |

Tracked build config:

- `Config.xcconfig` stores app-facing runtime values such as Supabase URL,
  Supabase publishable key, RevenueCat, PostHog, TelemetryDeck, and Google
  Sign-In client IDs. These are bundled client config values, not backend-only
  secrets.
- `Signing.xcconfig` includes optional ignored `Signing.local.xcconfig`.
- `Signing.local.example.xcconfig` is the template for a local Apple Developer
  Team ID.

Web runtime config:

- `apps/web/.env.example` documents the public web environment.
- `NEXT_PUBLIC_SITE_URL` should be `https://merian.earth` in production.
- `SUPABASE_SERVICE_ROLE_KEY` is server-only. Never expose it through a
  `NEXT_PUBLIC_` variable or client component.

## App Entry And Dependency Injection

| Area | File | Notes |
|---|---|---|
| SwiftUI app entry | `apps/ios/Merian/App/MerianApp.swift` | Builds the `ModelContainer` from `CurrentSchema`, performs corruption-aware store quarantine, configures `ScanRepository`, migrates species display preferences, initializes TelemetryDeck outside tests, applies global theme to `UIWindow`, and handles `merian://explore/post/<id>`, `merian://scan/<id>`, and `merian://scans` deep links. |
| App delegate bridge | `apps/ios/Merian/App/MerianApp.swift` | Owns background `URLSession` completion handoff and push token callbacks. |
| Dependency container | `apps/ios/Merian/Core/AppDIContainer.swift` | Injects hardware, AI, sync, network, analytics, security, settings, and profile dependencies through SwiftUI `@Environment`. |
| Detached work helper | `apps/ios/Merian/Core/AppDIContainer.swift` | Small wrapper for intentional detached image, database, file-system, and bootstrap work. |

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianSchemaV44
```

`MerianSchemaV44` is declared in `apps/ios/Merian/Models/SchemaVersions.swift` and points
at the global active model classes in `apps/ios/Merian/Models/ActiveSchema/`.

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
- V43 introduced AI-derived sex observation metadata on completed local scans.
- V44 added optional dog/cat pet-identification display metadata on completed
  local scans.

Historical schema snapshots V1 through V39 live under `apps/ios/Merian/Models/Schema/`.
V40 through V44 live in `SchemaVersions.swift` alongside the migration plan.

## Feature Modules

| Feature | Current files | Responsibility |
|---|---|---|
| Capture | `apps/ios/Merian/Features/Capture/` | Product-area-first capture surface. `Shell/` owns the three-page Scan/Record/Describe pager, fixed overlay chrome, sheets, routing, and root view model; `Staging/` owns mixed-media staging UI and models; `Submission/` owns shared live/offline analysis paths; `Refinement/` is reserved for reanalysis helpers; `Shared/` holds cross-mode capture primitives. |
| Scan | `apps/ios/Merian/Features/Capture/Scan/` | Camera preview, focus/zoom gestures, cropper, flash, photo picker, viewfinder hints, and visual scan components. |
| Record | `apps/ios/Merian/Features/Capture/Record/` plus `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift` and `SpectrogramActor.swift` | 15-second WAV recording, spectrogram, SNR gauge, review/playback, staging, and `/identify-multimodal` submission. |
| Describe | `apps/ios/Merian/Features/Capture/Describe/` | Typed observation input, guided question funnels, subject keyword matching, and `SpeechManager` dictation. |
| Insights | `apps/ios/Merian/Features/Insights/` | Product-area-first insight result feature. `Shell/` owns the root sheet, presentation routes, embedded navigation, and root view model; `Content/` owns biological/non-biological/queued/analyzing result bodies; `Media/` owns carousel/gallery/export work; `IdentificationReview/` owns candidates and confidence UX; `FieldNotes/`, `Chat/`, `Sharing/`, `Reporting/`, `Toolbars/`, and `SpeciesReference/` own their named insight subareas; `Toolbars/TopToolbar/` owns the collection-membership overflow menu; `Shared/` holds reusable insight chrome. |
| Scans | `apps/ios/Merian/Features/Scans/` | Product-area-first private scan library. `Shell/` owns the root sheet, pager, toolbar, and search chrome; `Library/` owns individual scans, `ScansManager`, the search index, and queued-scan snapshots; `Collections/` owns collection grids, detail routes, smart collections, and scan selection flows; `NonBiological/` owns the non-biological isolation surface; `Shared/` holds scan grid, thumbnail, empty-state, and deletion UI reused across Scans product areas. |
| Explore | `apps/ios/Merian/Features/Explore/` | Product-area-first public discovery feature. `Shell/` owns the root sheet/router, `Feed/` owns observations feed, post detail, comments, hashtags, and feed interaction state, `Map/` owns the map surface, `Identify/` owns Community ID requests/activity, `Notifications/` owns Explore activity notifications, `AuthorProfile/` owns public author sheets, `Shared/` holds only cross-area Explore UI helpers, and `Widgets/` writes the Explore widget cache. |
| Messages sharing | `apps/ios/messages/ScanSharing/`, `apps/ios/messages/MerianMessagesExtension/` | Shipped iMessage sharing surface. `MerianMessagesExtension/` owns the extension UI, `ScanSharing/Shared/` owns the App Group cache model read by both targets, and `ScanSharing/AppSupport/` owns the containing-app cache writer. |
| Profile | `apps/ios/Merian/Features/Profile/` | Product-area-first account feature. `Shell/` owns the profile/settings pager and close chrome; `UserProfile/` owns the public profile card, published scans preview, achievements, persona, terrarium, heatmap, and profile stats actor; `Settings/` owns preferences, geoprivacy, export, resources, and danger-zone account actions; `Settings/Plan/` owns RevenueCat plan management, profile plan cards, and paywall UI; `Settings/Notifications/` owns push-notification preferences; `Settings/Changelog/` owns bundled release notes; `Settings/Feedback/` owns the beta survey; `Shared/` holds cross-area profile state such as `ProfileViewModel`. |
| Species Dictionary | `apps/ios/Merian/Features/SpeciesDictionary/` | Product-area-first species reference feature. `Detail/` owns the public species page and reference gallery, `Catalog/` owns the Explore Index catalog/overview/regions surfaces, and `Tree/` owns the taxonomy canvas and graph model. |
| Onboarding | `apps/ios/Merian/Features/Onboarding/` | Product-area-first permission priming flow. `Shell/` owns the root view and state machine, `Steps/` owns the welcome/camera/location/ready screens plus shared step chrome, and `Permissions/` owns native permission delegates. |

## Public Web App

The public web frontend lives in `apps/web/` and is intentionally separate from the
native iOS source tree.

| Area | Current files | Responsibility |
|---|---|---|
| App shell | `apps/web/app/layout.tsx`, `apps/web/app/theme.ts`, `apps/web/app/globals.css` | Mantine provider, global metadata defaults, theme, pre-hydration color-scheme bridge, and responsive page chrome. |
| Marketing/home placeholder | `apps/web/app/page.tsx` | Lightweight Merian landing surface until the broader public website exists. |
| Explore share page | `apps/web/app/explore/post/[postId]/page.tsx` | Server-rendered public Explore post page with canonical, Open Graph, and Twitter metadata. |
| Policy/support pages | `apps/web/app/privacy/`, `apps/web/app/privacy-choices/`, `apps/web/app/terms/`, `apps/web/app/guidelines/`, `apps/web/app/support/`, `apps/web/app/legal/` | App Store-friendly public policy, data-choice, community, support, and legal hub pages. |
| Legal/public components | `apps/web/components/PublicPageShell.tsx`, `apps/web/components/LegalPage.tsx`, `apps/web/components/ThemePreferenceBridge.tsx`, `apps/web/lib/site.ts`, `apps/web/lib/theme-preference.ts` | Shared public page chrome, legal document layout, iOS-to-Mantine theme preference sync, support email/site URL config. |
| Supabase access | `apps/web/lib/supabase.ts`, `apps/web/lib/explore.ts` | Server-side Supabase client creation and `get_explore_post` RPC mapping. |
| Formatting helpers | `apps/web/lib/formatting.ts` | Shared web copy/URL formatting, including `merian://explore/post/{postId}` button URLs. |
| Local setup | `apps/web/README.md`, `apps/web/.env.example`, `apps/web/package.json` | Web setup, env variable contract, npm scripts, and dependency manifest. |

## Core Modules

| Core area | Current files | Responsibility |
|---|---|---|
| AI | `apps/ios/Merian/Core/AI/` | `InferenceEngine`, edge DTOs, parse/save actor, and on-device viewfinder intelligence. |
| Analytics | `apps/ios/Merian/Core/Analytics/` | TelemetryDeck wrapper, PostHog wrapper, usage quota, and gamification notification manager. |
| Data/Database | `apps/ios/Merian/Core/Data/Database/` | `BackgroundDatabaseActor`, `FileIOActor`, `ScanRepository`, and `HistoricalDatabaseActor`. |
| Data/Images | `apps/ios/Merian/Core/Data/Images/` | Archive rescue, photo-library access, thumbnails, local image loading, and RAM image cache. |
| Offline sync | `apps/ios/Merian/Core/Data/OfflineSync/` | Queue state machine, upload URLSession handoff, background inference replay, audio queue helpers, and sync phase state. |
| Hardware | `apps/ios/Merian/Core/Hardware/` | Camera, environment context, audio, spectrogram, haptics, thermal/battery orchestration, and push token management. |
| Network | `apps/ios/Merian/Core/Network/` | Supabase auth/client facade, TLS-pinned network client, Explore DTOs, species dictionary/observation-stats DTOs, and Keychain manager. |
| Security | `apps/ios/Merian/Core/Security/` | Circuit breaker, device identity, RevenueCat, and social guard. |
| UI | `apps/ios/Merian/Core/UI/` | Shared controls, tab bar, media mode toggle, slide-to-confirm, reusable modifiers, and theme model. |
| Utilities | `apps/ios/Merian/Core/Utilities/` | App lifecycle, app events, config constants, field notes repository, image downsampling, errors, sharing, date/size helpers, and UserDefaults keys. |

## SwiftData Actors

| Actor | File | Lifecycle |
|---|---|---|
| `BackgroundDatabaseActor` | `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift` | Ad-hoc for live writes/enrichment/collections; long-lived through `OfflineQueueManager.resolvedInferenceDbActor(container:)` for queue inference state transitions. |
| `HistoricalDatabaseActor` | `apps/ios/Merian/Core/Data/Database/ScanRepository.swift` | Ad-hoc per historical sync, streaming one cloud page at a time. |
| `ProfileDatabaseActor` | `apps/ios/Merian/Features/Profile/UserProfile/Components/UserStats.swift` | Ad-hoc for profile screen calculations; long-lived via `OfflineQueueManager.resolvedProfileDbActor(container:)` for post-inference awards. |
| `SpeciesObservationStatsDatabaseActor` | `apps/ios/Merian/Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift` | Ad-hoc per species chart load; filtered/projection SwiftData fetches for local observation overlays, then delegates bucketing to `Features/Insights/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`. |
| `SearchDatabaseActor` | `apps/ios/Merian/Features/Scans/Library/ViewModels/ScansManager.swift` | Ad-hoc for incremental search payload extraction from persistent IDs. |
| `FileIOActor` | `apps/ios/Merian/Core/Data/Database/FileIOActor.swift` | Singleton actor for image/audio file writes, deletes, and path validation. |

## Supabase Edge Function Inventory

Inference and media staging:

- `generate-upload-urls`
- `identify`
- `identify-multimodal`
- `identify-describe`
- `audio-spec`
- `check-scan-status`
- `enrich-scan`
- `insight-chat`

Public species data:

- `species-dictionary`
- `species-observation-stats`

Explore and social:

- `get-explore-feed`
- `get-explore-map-points`
- `get-explore-post`
- `get-explore-post-detail`
- `get-explore-author-profile`
- `get-explore-author-posts`
- `get-explore-hashtag-posts`
- `get-explore-comments`
- `get-explore-comment-replies`
- `get-explore-mention-suggestions`
- `report-explore-comment`
- `toggle-explore-comment-reaction`

Explore community identification:

- `request-community-identification`
- `get-community-identification-feed`
- `get-community-identification-detail`
- `update-community-identification-request`
- `search-community-taxa`
- `submit-community-identification`
- `withdraw-community-identification`
- `restore-community-identification`
- `submit-community-feedback`

Explore publishing, activity, and delivery:

- `get-explore-notifications`
- `get-explore-unread-notification-count`
- `mark-explore-notifications-read`
- `share-scan-to-explore`
- `unshare-explore-post`
- `update-explore-field-notes`
- `update-public-username`
- `update-public-display-name`
- `update-public-avatar`
- `check-public-username`
- `get-scan-explore-share-state`
- `set-explore-post-like`
- `set-user-follow`
- `create-explore-comment`
- `delete-explore-comment`
- `register-push-device`
- `send-push-notification`
- `block-user`

Data lifecycle, identity, and exports:

- `sync-collections`
- `merge-ghost-profile` — re-parents ghost scans, collections, Explore posts,
  Ask the Community request ownership, and follows before purging the anonymous
  shell.
- `safe-delete`
- `delete-scan`
- `flag-issue`
- `submit-feedback-survey`
- `request-export-dwca`
- `export-dwca`
- `revenuecat-webhook`
- `get-filtered-discovery-feed`

Scheduled/background workers:

- `refresh-species-content`
- `refresh-species-model-content`
- `refresh-taxonomy-nodes`
- `community-taxonomy-status`
- `sync-community-taxonomy-index`
- `process-community-consensus-jobs`
- `refresh-merian-reference-images`
- `expire-subscription-passes`
- `auto-purge-nonbio`

Every function above has a `[functions.<name>]` entry in `services/supabase/config.toml`.
`merge-ghost-profile` and `request-export-dwca` intentionally use
`verify_jwt = true`; app-facing functions generally set `verify_jwt = false`
and perform identity checks inside shared handler code.

## Test Inventory

Swift unit tests live under `apps/ios/MerianTests/` and cover:

- Active schema models and migration invariants.
- Capture workspace staging, camera analysis, audio/describe helpers, and
  queued handoff flows.
- Core AI, network, security, hardware, analytics, utilities, and data actors.
- Profile achievements, heatmap/stats, Explore, Species Dictionary, species
  observation stats, Messages sharing, Insights, Scans, and onboarding view
  models.

UI tests live under `apps/ios/MerianUITests/` and include launch coverage plus seeded
flows in `MerianApp.swift` through `UITestSeedCoordinator`.

Deno tests live under `services/supabase/functions/_tests/` plus function-local
`*.test.ts` files. Run from `services/supabase/functions` with:

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
- Public web routes, metadata, env variables, Universal Link behavior, or
  `merian.earth` share URL shape.
- Native extension targets, App Group boundaries, or shipped/de-shipped
  extension source ownership.
- Asset catalog groups, reusable artwork names, app icons, brand marks, persona
  art, or widget fallback imagery.
- Release-note behavior in `CHANGELOG.md` or the bundled in-app changelog JSON.
