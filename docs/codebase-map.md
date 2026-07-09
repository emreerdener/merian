# Current Codebase Map

Last reviewed: 2026-07-07.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed
for developer convenience and should be regenerated with `xcodegen generate`
after target, package, entitlement, build setting, or source-list changes.

| Target                    | Type                    | Source                                                                                           | Deployment   |
| ------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------ | ------------ |
| `Merian`                  | iOS application         | `apps/ios/Merian/`                                                                               | iOS 17.2     |
| `MerianExploreWidget`     | WidgetKit app extension | `apps/ios/widgets/Explore/`, `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift` | iOS 17.2     |
| `MerianMessagesExtension` | Messages app extension  | `apps/ios/messages/MerianMessagesExtension/`, `apps/ios/messages/ScanSharing/Shared/`            | iOS 17.2     |
| `MerianWatch`             | watchOS companion app   | `apps/watch/MerianWatch/`                                                                        | watchOS 10.0 |
| `merianTests`             | Unit tests              | `apps/ios/MerianTests/`                                                                          | iOS 17.2     |
| `merianUITests`           | UI tests                | `apps/ios/MerianUITests/`                                                                        | iOS 17.2     |
| `@merian/web`             | Next.js public web app  | `apps/web/`                                                                                      | Node/Next.js |

Tracked build config:

- `Config.xcconfig` stores app-facing runtime values such as Supabase URL,
  Supabase publishable key, RevenueCat, PostHog, and Google
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

| Area                         | File                                                                                                        | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SwiftUI app entry            | `apps/ios/Merian/App/MerianApp.swift`                                                                       | Builds the `ModelContainer` from `CurrentSchema` using store-aware migration selection, delegates duplicate-checksum fallback and corruption-aware quarantine to `Core/Data/StoreRecovery/`, configures `ScanRepository`, migrates species display preferences, initializes app analytics outside tests, applies global theme to `UIWindow`, and handles `merian://explore/post/<id>`, `merian://scan/<id>`, and `merian://scans` deep links. |
| App delegate bridge          | `apps/ios/Merian/App/MerianApp.swift`                                                                       | Owns background `URLSession` completion handoff and push token callbacks.                                                                                                                                                                                                                                                                                                                                                                     |
| Objective-C exception bridge | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`, `apps/ios/Merian/Configuration/Merian-Bridging-Header.h` | Converts launch-time SwiftData/Core Data Objective-C exceptions into Swift errors so store recovery can run.                                                                                                                                                                                                                                                                                                                                  |
| Dependency container         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                 | Injects hardware, AI, sync, network, analytics, security, settings, and profile dependencies through SwiftUI `@Environment`.                                                                                                                                                                                                                                                                                                                  |
| Detached work helper         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                 | Small wrapper for intentional detached image, database, file-system, and bootstrap work.                                                                                                                                                                                                                                                                                                                                                      |

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianSchemaV49
```

`MerianSchemaV49` is declared in `apps/ios/Merian/Models/SchemaVersions.swift`
and points at the global active model classes in
`apps/ios/Merian/Models/ActiveSchema/`. V47 and V48 remain frozen in
`SchemaVersions.swift` for source-specific startup recovery.

Active persistent models:

- `LocalScanRecord`
- `OfflineQueuedScan`
- `OfflineJobRecord`
- `OfflineQueueEvent`
- `CapturedMediaEntry`
- `ScanCollection`
- `PendingCloudDeletionTask`
- `UserSpeciesPreference`

Recent schema milestones:

- V40 introduced `capturedMediaJSON` and `coverImagePath` as scalar mixed-media
  durability mirrors.
- V41 introduced `CapturedMediaEntry` and relationship mirrors for queued and
  completed scans. Current video entries store `StoredVideoMediaReference`
  (`video` plus poster `thumbnail`) in `capturedMediaJSON`; relationship rows
  are compatibility mirrors and should not be treated as the richer source of
  truth.
- V42 added first-class `fieldNotes` columns to `LocalScanRecord` and
  `OfflineQueuedScan`, while preserving the legacy UserDefaults bridge through
  `FieldNotesRepository`. V42 stores now use a source-isolated startup recovery
  plan to avoid validating older full-historical custom stages before migration
  reaches the actual source.
- V43 introduced AI-derived sex observation metadata on completed local scans.
  V43 stores also use a source-isolated startup recovery plan before the
  V43→V48→V49 repair path.
- V44 added optional dog/cat pet-identification display metadata on completed
  local scans.
- V45 added optional invasive-status context to completed local scans. V46 was a
  shipped no-op checksum twin of V45; runtime migration keeps the
  duplicate-prone V44/V45/V46 recent cluster out of the full historical plan,
  jumps older stores V43→V48, and uses source-isolated recent plans for stores
  already stamped V42, V43, V44, V45, or V46. V44, V45, and V46 stores jump through
  separate direct V44→V48, V45→V48, and V46→V48 plans.
- V47 added offline video inference replay fields so sampled frames can be
  queued separately from the user-visible playback video timeline. Its frozen
  schema keeps local-scan, captured-media, and collection models self-contained
  inside V47, and keeps `OfflineQueuedScan` scalar-only.
- V48 added durable queue retry metadata on `OfflineQueuedScan`, plus
  `OfflineJobRecord` and bounded `OfflineQueueEvent` rows for scan ingestion,
  cloud deletion, collection sync, diagnostics, and future offline work. The
  V47→V48 migration is custom, not lightweight: every existing queued scan must
  leave migration with retry fields initialized and a `scan-ingestion:{id}` job
  row so startup does not fall back to safe mode on stores with queued media.
  V47 job/event rows and replacement queued-scan rows are seeded from migration
  snapshots so stale SwiftData model-identity traps cannot survive into V48.
- V49 is a startup store-repair schema. It keeps the V48 queue scheduler model,
  adds `OfflineQueuedScan.queueSchemaRepairGeneration`, and provides separate
  V48→V49 plans for the known-good V48 checksum and the accidental
  optional-queue V48 TestFlight checksum. Startup diagnostics record redacted
  store metadata and attempted plan names so failing devices can share evidence
  without exposing paths, account data, scan text, or media URLs.
  `MigrationPlanTests` carries the disk-store fixture matrix for image, video,
  audio, description-only, and mixed queued media, and
  `.github/workflows/ios-startup-safety.yml` runs that suite beside store
  recovery tests.

Historical schema snapshots V1 through V39 live under
`apps/ios/Merian/Models/Schema/`. V40 through V47 live in `SchemaVersions.swift`
alongside the migration plan.

## Feature Modules

| Feature            | Current files                                                                                                                          | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Capture            | `apps/ios/Merian/Features/Capture/`                                                                                                    | Product-area-first capture surface. `Shell/` owns the three-page Scan/Record/Describe pager, fixed overlay chrome, sheets, routing, and root view model; `Staging/` owns mixed-media staging UI and models; `Submission/` owns shared live/offline analysis paths; `Refinement/` is reserved for reanalysis helpers; `Shared/` holds cross-mode capture primitives.                                                                                                                                                                                                                                                                                          |
| Scan               | `apps/ios/Merian/Features/Capture/Scan/`                                                                                               | Camera preview, focus/zoom gestures, cropper, flash, photo picker, viewfinder hints, Pro video capture with active-recording-only AVFoundation stabilization, sampled-frame/WAV extraction, and upload-bounded playback clip staging.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Record             | `apps/ios/Merian/Features/Capture/Record/` plus `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift` and `SpectrogramActor.swift` | 15-second WAV recording, spectrogram, SNR gauge, review/playback, staging, and `/identify-multimodal` submission.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Describe           | `apps/ios/Merian/Features/Capture/Describe/`                                                                                           | Typed observation input, guided question funnels, subject keyword matching, and `SpeechManager` dictation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Insights           | `apps/ios/Merian/Features/Insights/`                                                                                                   | Product-area-first insight result feature. `Shell/` owns the root sheet, presentation routes, embedded navigation, and root view model; `Content/` owns biological/non-biological/queued/analyzing result bodies; `Media/` owns carousel/gallery/export work; `IdentificationReview/` owns candidates and confidence UX; `FieldNotes/`, `Chat/`, `Sharing/`, `Reporting/`, `Toolbars/`, and `SpeciesReference/` own their named insight subareas; `Toolbars/TopToolbar/` owns the collection-membership overflow menu; `Shared/` holds reusable insight chrome.                                                                                              |
| Scans              | `apps/ios/Merian/Features/Scans/`                                                                                                      | Product-area-first private scan library. `Shell/` owns the root sheet, pager, toolbar, and search chrome; `Library/` owns individual scans, `ScansManager`, the search index, and queued-scan snapshots; `Collections/` owns collection grids, detail routes, smart collections, and scan selection flows; `NonBiological/` owns the non-biological isolation surface; `Shared/` holds scan grid, thumbnail, empty-state, and deletion UI reused across Scans product areas.                                                                                                                                                                                 |
| Explore            | `apps/ios/Merian/Features/Explore/`                                                                                                    | Product-area-first public discovery feature. `Shell/` owns the root sheet/router, stack-based author-profile routing, the profile-to-scan nesting cap, and scoped video playback coordinator; `Feed/` owns observations feed, post detail, comments, hashtags, feed interaction state, and the shared feed/detail video media host; `Map/` owns the map surface; `Identify/` owns Community ID requests/activity; `FieldTrips/` owns Field Trip Available/Community segments, Seasonal Challenges, guided template detail, progress, publication/challenge-entry detail, badges, and profile modules; `Notifications/` owns Explore activity notifications; `AuthorProfile/` owns public author profile content/routes; `Shared/` holds only cross-area Explore UI helpers; and `Widgets/` writes the image-only Explore widget cache. |
| Messages sharing   | `apps/ios/messages/ScanSharing/`, `apps/ios/messages/MerianMessagesExtension/`                                                         | Shipped iMessage sharing surface. `MerianMessagesExtension/` owns the extension UI, `ScanSharing/Shared/` owns the App Group cache model read by both targets, and `ScanSharing/AppSupport/` owns the containing-app cache writer.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Profile            | `apps/ios/Merian/Features/Profile/`                                                                                                    | Product-area-first account feature. `Shell/` owns the profile/settings pager and close chrome; `UserProfile/` owns the public profile card, published scans preview, Field Trip profile modules, achievements, persona, terrarium, heatmap, and profile stats actor; `Settings/` owns preferences, geoprivacy, export, resources, and danger-zone account actions; `Settings/Plan/` owns RevenueCat plan management, profile plan cards, and paywall UI; `Settings/Notifications/` owns push-notification preferences; `Settings/Changelog/` owns bundled release notes; `Settings/Feedback/` owns the beta survey; `Shared/` holds cross-area profile state such as `ProfileViewModel`. |
| Species Dictionary | `apps/ios/Merian/Features/SpeciesDictionary/`                                                                                          | Product-area-first species reference feature. `Detail/` owns the public species page and reference gallery, `Catalog/` owns the Explore Index catalog/overview/regions surfaces, and `Tree/` owns the taxonomy canvas and graph model.                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Onboarding         | `apps/ios/Merian/Features/Onboarding/`                                                                                                 | Product-area-first permission priming flow. `Shell/` owns the root view and state machine, `Steps/` owns the welcome/camera/location/ready screens plus shared step chrome, and `Permissions/` owns native permission delegates.                                                                                                                                                                                                                                                                                                                                                                                                                             |

## Public Web App

The public web frontend lives in `apps/web/` and is intentionally separate from
the native iOS source tree.

| Area                       | Current files                                                                                                                                                                               | Responsibility                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| App shell                  | `apps/web/app/layout.tsx`, `apps/web/app/theme.ts`, `apps/web/app/globals.css`                                                                                                              | Mantine provider, global metadata defaults, theme, pre-hydration color-scheme bridge, and responsive page chrome.      |
| Marketing/home placeholder | `apps/web/app/page.tsx`                                                                                                                                                                     | Lightweight Merian landing surface until the broader public website exists.                                            |
| Explore share page         | `apps/web/app/explore/post/[postId]/page.tsx`                                                                                                                                               | Server-rendered public Explore post page with canonical, Open Graph, and Twitter metadata.                             |
| Policy/support pages       | `apps/web/app/privacy/`, `apps/web/app/privacy-choices/`, `apps/web/app/terms/`, `apps/web/app/guidelines/`, `apps/web/app/support/`, `apps/web/app/legal/`                                 | App Store-friendly public policy, data-choice, community, support, and legal hub pages.                                |
| Legal/public components    | `apps/web/components/PublicPageShell.tsx`, `apps/web/components/LegalPage.tsx`, `apps/web/components/ThemePreferenceBridge.tsx`, `apps/web/lib/site.ts`, `apps/web/lib/theme-preference.ts` | Shared public page chrome, legal document layout, iOS-to-Mantine theme preference sync, support email/site URL config. |
| Supabase access            | `apps/web/lib/supabase.ts`, `apps/web/lib/explore.ts`                                                                                                                                       | Server-side Supabase client creation and `get_explore_post` RPC mapping.                                               |
| Formatting helpers         | `apps/web/lib/formatting.ts`                                                                                                                                                                | Shared web copy/URL formatting, including `merian://explore/post/{postId}` button URLs.                                |
| Local setup                | `apps/web/README.md`, `apps/web/.env.example`, `apps/web/package.json`                                                                                                                      | Web setup, env variable contract, npm scripts, and dependency manifest.                                                |

## Core Modules

| Core area      | Current files                              | Responsibility                                                                                                                                                                           |
| -------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI             | `apps/ios/Merian/Core/AI/`                 | `InferenceEngine`, edge DTOs, parse/save actor, and on-device viewfinder intelligence.                                                                                                   |
| Analytics      | `apps/ios/Merian/Core/Analytics/`          | PostHog-backed app analytics facade, usage quota, and gamification notification manager.                                                                                                 |
| Data/Database  | `apps/ios/Merian/Core/Data/Database/`      | `BackgroundDatabaseActor`, `FileIOActor`, `ScanRepository`, and `HistoricalDatabaseActor`.                                                                                               |
| Data/Images    | `apps/ios/Merian/Core/Data/Images/`        | File-backed still-image preparation, archive rescue, photo-library access, thumbnails, local image loading, and RAM image cache.                                                         |
| Offline sync   | `apps/ios/Merian/Core/Data/OfflineSync/`   | Queue state machine, upload URLSession handoff, background inference replay, audio queue helpers, and sync phase state.                                                                  |
| Store recovery | `apps/ios/Merian/Core/Data/StoreRecovery/` | SwiftData store metadata parsing, source-aware migration hints, duplicate-checksum detection, corruption-gated quarantine, safe-mode decision support, and sanitized recovery manifests. |
| Hardware       | `apps/ios/Merian/Core/Hardware/`           | Camera, environment context, audio, spectrogram, haptics, thermal/battery orchestration, and push token management.                                                                      |
| Network        | `apps/ios/Merian/Core/Network/`            | Supabase auth/client facade, TLS-pinned network client, Explore and Field Trip DTOs, species dictionary/observation-stats DTOs, and Keychain manager.                                    |
| Security       | `apps/ios/Merian/Core/Security/`           | Circuit breaker, device identity, RevenueCat, and social guard.                                                                                                                          |
| UI             | `apps/ios/Merian/Core/UI/`                 | Shared controls, tab bar, media mode toggle, slide-to-confirm, reusable modifiers, and theme model.                                                                                      |
| Utilities      | `apps/ios/Merian/Core/Utilities/`          | App lifecycle, app events, config constants, field notes repository, image downsampling, errors, sharing, date/size helpers, and UserDefaults keys.                                      |

## SwiftData Actors

| Actor                                  | File                                                                                                   | Lifecycle                                                                                                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BackgroundDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift`                                     | Ad-hoc for live writes/enrichment/collections; long-lived through `OfflineQueueManager.resolvedInferenceDbActor(container:)` for queue inference state transitions.                                                |
| `HistoricalDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/ScanRepository.swift`                                              | Ad-hoc per historical sync, streaming one cloud page at a time.                                                                                                                                                    |
| `ProfileDatabaseActor`                 | `apps/ios/Merian/Features/Profile/UserProfile/Components/UserStats.swift`                              | Ad-hoc for profile screen calculations; long-lived via `OfflineQueueManager.resolvedProfileDbActor(container:)` for post-inference awards.                                                                         |
| `SpeciesObservationStatsDatabaseActor` | `apps/ios/Merian/Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift` | Ad-hoc per species chart load; filtered/projection SwiftData fetches for local observation overlays, then delegates bucketing to `Features/Insights/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`. |
| `SearchDatabaseActor`                  | `apps/ios/Merian/Features/Scans/Library/ViewModels/ScansManager.swift`                                 | Ad-hoc for incremental search payload extraction from persistent IDs.                                                                                                                                              |
| `FileIOActor`                          | `apps/ios/Merian/Core/Data/Database/FileIOActor.swift`                                                 | Singleton actor for image/audio file writes, deletes, and path validation.                                                                                                                                         |

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

Shared identify helpers under
`services/supabase/functions/_shared/identify/` own cross-route contracts for
schema, thresholds, cache hydration, database writes, media resolution,
moderation, and subject classification. `subjectClassification.ts` is the
processed-material boundary: visual and describe routes call it before
biological gates so manufactured or processed objects cannot enter
`species_dictionary` through one route while another blocks them.

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
- `field-trips`
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
- `reconcile-scan-media-assets`
- `replay-scan-ingestion`
- `scan-media-health`

Every function above has a `[functions.<name>]` entry in
`services/supabase/config.toml`. `merge-ghost-profile` and `request-export-dwca`
intentionally use `verify_jwt = true`; app-facing functions generally set
`verify_jwt = false` and perform identity checks inside shared handler code.

## Supabase Media Projections

| Surface                         | Current files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scan ingestion jobs and intents | `services/supabase/migrations/20260705120000_add_scan_ingestion_jobs.sql`, `services/supabase/migrations/20260705130000_extend_scan_ingestion_jobs_media_manifest.sql`, `services/supabase/migrations/20260705140000_add_scan_ingestion_intents.sql`, `services/supabase/migrations/20260705150000_schedule_scan_ingestion_replay.sql`, `services/supabase/migrations/20260707143157_cap_scan_ingestion_replay_attempts.sql`, `services/supabase/functions/_shared/scanIngestionJobs.ts`, `services/supabase/functions/_shared/scanIngestionIntents.ts`, `services/supabase/functions/_shared/scanIngestionCompatibility.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/replay-scan-ingestion/`, `services/supabase/functions/_tests/scanMediaIngestionContract.test.ts` | Durable server-side state ledger, sanitized replay intent, and scheduled replay dispatcher for accepted scan ingestion attempts. The multimodal path claims and updates job state through inference, media promotion, scan insert, completion, and failure; claims include upload-session ids and a normalized media-manifest checksum so retries can be tied back to the exact media shape. Compatibility scan-producing endpoints write the same ledger before returning success, with staged image/audio and text-only intents shaped for multimodal replay. The paired intent row stores telemetry/descriptors/staged keys without raw media bytes, marking inline-media requests as non-resumable. The replay worker claims due resumable staged media/audio/video or text-only jobs and re-invokes the multimodal path with the same `client_scan_id`, capped at 10 server replay claims before `failed_terminal / server_replay_limit_reached`; status polling keeps `found` / `not_found` compatibility while exposing optional job details for retry and ops visibility. The media-ingestion contract test matrix locks these guarantees across image, audio, text-only, video, status, repair, and Explore-share seams. |
| Scan media assets               | `services/supabase/migrations/20260705100000_add_scan_media_assets.sql`, `services/supabase/migrations/20260705110000_schedule_scan_media_asset_reconciliation.sql`, `services/supabase/migrations/20260706100000_allow_staged_scan_media_without_scan_id.sql`, `services/supabase/migrations/20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql`, `services/supabase/migrations/20260707020956_allow_staged_scan_media_without_url.sql`, `services/supabase/migrations/20260707041259_fix_video_has_audio_metadata.sql`, `services/supabase/functions/_shared/scanMediaAssets.ts`, `services/supabase/functions/generate-upload-urls/`, `services/supabase/functions/reconcile-scan-media-assets/`, `services/supabase/functions/scan-media-health/`, `services/supabase/scripts/monitor_scan_media_health.ts`, `.github/workflows/scan-media-health-monitor.yml`                                                                                                          | Normalized scan media lifecycle table. Upload signing creates staged scan-media rows when clients send `clientScanId`/`mediaRole`; repair migrations allow those staged rows before a final scan id or public media URL exists; identify finalization marks those rows promoted/deleted/failed; the scheduled reconciliation worker repairs stale existing-scan video uploads, respects active/future-retry ingestion jobs before abandoning media, marks repaired jobs complete, and marks TTL-abandoned jobs terminal; the read-only health endpoint reports stuck ingestion jobs and media-manifest drift for deploy smoke checks and operations; the scheduled monitor stores JSON/Markdown health summaries, fails only on critical drift by default, and emits incident actions with owner/runbook/sample hints for each issue code. `captured_media` remains the canonical scan manifest for generated ready rows; readers prefer ready display/playback assets, fall back to the manifest and legacy image/video arrays for older rows, qualify legacy-array refresh aliases to avoid PL/pgSQL `image_url`/`video_url` ambiguity, derive video `has_audio` only from captured-media audio evidence, and avoid treating sampled video frames as standalone user media.                                                                                   |
| Explore post media              | `services/supabase/migrations/20260703130000_add_explore_post_media.sql`, `services/supabase/migrations/20260707041259_fix_video_has_audio_metadata.sql`, `services/supabase/functions/_shared/explorePostMedia.ts`, `services/supabase/functions/_shared/exploreComposerMedia.ts`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Post-owned public media snapshot used by Explore feed/detail, Community ID, map/profile/widget previews, and public web read paths. Feed/detail may play muted videos; widgets, maps, profile grids, and compact previews stay thumbnail-first, with widgets intentionally showing clean still thumbnails. Video `has_audio` is copied from ready normalized media rows or the captured-media video audio reference; legacy URL-array video sources default false because they do not prove that an audio companion was persisted.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

## Test Inventory

Swift unit tests live under `apps/ios/MerianTests/` and cover:

- Active schema models and migration invariants.
- Capture workspace staging, camera analysis, audio/describe helpers, and queued
  handoff flows.
- Core AI, network, security, hardware, analytics, utilities, and data actors.
- Profile achievements, heatmap/stats, Explore, Species Dictionary, species
  observation stats, Messages sharing, Insights, Scans, and onboarding view
  models.

UI tests live under `apps/ios/MerianUITests/` and include launch coverage plus
seeded flows in `MerianApp.swift` through `UITestSeedCoordinator`.

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
