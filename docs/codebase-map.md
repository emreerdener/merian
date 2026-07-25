# Current Codebase Map

Last reviewed: 2026-07-22.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed
for developer convenience and should be regenerated with `xcodegen generate`
after target, package, entitlement, build setting, or source-list changes.

| Target                    | Type                    | Source                                                                                           | Deployment   |
| ------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------ | ------------ |
| `Merian`                  | iOS application         | `apps/ios/Merian/`, `apps/ios/Shared/Branding/`                                                  | iOS 17.2     |
| `MerianExploreWidget`     | WidgetKit app extension | `apps/ios/widgets/Explore/`, `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift`, shared branding | iOS 17.2     |
| `MerianMessagesExtension` | Messages app extension  | `apps/ios/messages/MerianMessagesExtension/`, `apps/ios/messages/ScanSharing/Shared/`, shared branding | iOS 17.2     |
| `MerianWatch`             | watchOS companion app   | `apps/watch/MerianWatch/`, shared branding                                                       | watchOS 10.0 |
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
- `NEXT_PUBLIC_SITE_URL` should be `https://naturebook.earth` in production.
- `NEXT_PUBLIC_SUPPORT_EMAIL` should be `support@naturebook.earth` in
  production.
- `SUPABASE_SERVICE_ROLE_KEY` is server-only. Never expose it through a
  `NEXT_PUBLIC_` variable or client component.

## Public Brand and Compatibility

Naturebook is the public product and Merian is the permanent technical
identity. The iOS/extension source of truth is
`apps/ios/Shared/Branding/PublicBrand.swift`; the web source is
`apps/web/lib/site.ts` plus the production environment. Host redirects and the
legacy AASA exception live in `apps/web/proxy.ts` and
`apps/web/lib/canonicalHost.ts`.

New links emit `https://naturebook.earth` or `naturebook://`. The app continues
accepting `https://merian.earth` and `merian://`. Bundle IDs, targets, modules,
App Groups, SwiftData, backend names, `source = 'merian'`, RevenueCat product
IDs, analytics, and `media.merian.app` remain unchanged. See
`docs/system-architecture/08-public-brand-compatibility.md` for the complete
contract and `docs/development-guides/15-naturebook-rebrand-rollout.md` for the
release checklist.

## App Entry And Dependency Injection

| Area                         | File                                                                                                        | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SwiftUI app entry            | `apps/ios/Merian/App/MerianApp.swift`                                                                       | Builds the `ModelContainer` from `CurrentSchema` using store-aware migration selection, delegates duplicate-checksum fallback, corruption quarantine, and legacy migration rescue to `Core/Data/StoreRecovery/`, configures `ScanRepository`, migrates species display preferences, initializes app analytics outside tests, applies global theme to `UIWindow`, handles canonical `naturebook://` and legacy `merian://` Explore/species/scan/library deep links plus Naturebook/Merian Universal Links, and classifies file URLs for the Photos document-import inbox before Supabase auth handling. |
| App delegate bridge          | `apps/ios/Merian/App/MerianApp.swift`                                                                       | Owns background `URLSession` completion handoff and push token callbacks.                                                                                                                                                                                                                                                                                                                                                                     |
| Objective-C exception bridge | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`, `apps/ios/Merian/Configuration/Merian-Bridging-Header.h` | Converts launch-time SwiftData/Core Data Objective-C exceptions into Swift errors so store recovery can run.                                                                                                                                                                                                                                                                                                                                  |
| Dependency container         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                 | Injects hardware, AI, sync, network, analytics, security, settings, and profile dependencies through SwiftUI `@Environment`.                                                                                                                                                                                                                                                                                                                  |
| Detached work helper         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                 | Small wrapper for intentional detached image, database, file-system, and bootstrap work.                                                                                                                                                                                                                                                                                                                                                      |

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianSchemaV50
```

`MerianSchemaV50` is declared in `apps/ios/Merian/Models/SchemaVersions.swift`.
It reuses the released V49 queue/global active models and adds one schema-scoped
goal-hint companion. V47 through V49 remain available in
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
- `OfflineQueuedScanGoalHint`

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
  plan that jumps directly to V49, avoiding the older V42→V43 bridge that still
  failed on real TestFlight stores.
- V43 introduced AI-derived sex observation metadata on completed local scans.
  V43 stores also use a source-isolated startup recovery plan before the
  V43→V49 repair path.
- V44 added optional dog/cat pet-identification display metadata on completed
  local scans.
- V45 added optional invasive-status context to completed local scans. V46 was a
  shipped no-op checksum twin of V45; runtime migration keeps the
  duplicate-prone V44/V45/V46 recent cluster out of the full historical plan,
  jumps older stores V42→V49 or V43→V49, and uses source-isolated recent plans for stores
  already stamped V42, V43, V44, V45, or V46. V44, V45, and V46 stores jump through
  separate direct V44→V49, V45→V49, and V46→V49 plans.
- V47 added offline video inference replay fields so sampled frames can be
  queued separately from the user-visible playback video timeline. Its frozen
  schema keeps local-scan, captured-media, and collection models self-contained
  inside V47, and keeps `OfflineQueuedScan` scalar-only.
- V48 added durable queue retry metadata on `OfflineQueuedScan`, plus
  `OfflineJobRecord` and bounded `OfflineQueueEvent` rows for scan ingestion,
  cloud deletion, collection sync, diagnostics, and future offline work. The
  V47→V49 migration is custom, not lightweight: every existing queued scan must
  leave migration with retry fields initialized and a `scan-ingestion:{id}` job
  row so startup can recover persistently on stores with queued media.
  V47 job/event rows and replacement queued-scan rows are seeded from migration
  snapshots so stale SwiftData model-identity traps cannot survive into V49.
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
- V50 adds `OfflineQueuedScanGoalHint`, a scan-keyed companion containing the
  optional standard-outing and checklist-item preference for a queued scan. The
  lightweight V49→V50 stage leaves `OfflineQueuedScan` unchanged. All recent
  source-specific plans reach V49 first, then advance through the same V50
  stage.

Historical schema snapshots V1 through V39 live under
`apps/ios/Merian/Models/Schema/`. V40 through V50 live in `SchemaVersions.swift`
alongside the migration plan.

## Feature Modules

| Feature            | Current files                                                                                                                          | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Capture            | `apps/ios/Merian/Features/Capture/`                                                                                                    | Product-area-first capture surface. `Shell/` owns the three-page Scan/Record/Describe pager, fixed overlay chrome, sheets, routing, root view model, pending Photos-import handoff, and the non-blocking active-goal indicator/deep link. `Core/Models/CaptureGoalContext.swift` defines the source-agnostic goal, provider, typed destination, and app-injected account cache; the Field trips feature is the first provider. `Staging/` owns mixed-media staging UI and models; `Submission/` owns shared live/offline analysis paths; `Refinement/` is reserved for reanalysis helpers; `Shared/` holds cross-mode capture primitives.                                                                                                                                                                                                      |
| Scan               | `apps/ios/Merian/Features/Capture/Scan/`                                                                                               | Camera preview, focus/zoom gestures, cropper, flash, photo picker, viewfinder hints, Pro video capture with active-recording-only AVFoundation stabilization, sampled-frame/WAV extraction, and upload-bounded playback clip staging.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Record             | `apps/ios/Merian/Features/Capture/Record/` plus `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift` and `SpectrogramActor.swift` | 15-second WAV recording, spectrogram, SNR gauge, review/playback, staging, and `/identify-multimodal` submission.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Describe           | `apps/ios/Merian/Features/Capture/Describe/`                                                                                           | Typed observation input, guided question funnels, subject keyword matching, and `SpeechManager` dictation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Insights           | `apps/ios/Merian/Features/Insights/`                                                                                                   | Product-area-first insight result feature. `Shell/` owns the root sheet, presentation routes, embedded navigation, and root view model; `Content/` owns biological/non-biological/queued/analyzing result bodies; `Media/` owns carousel/gallery/export work plus per-scan audio boost preferences and playback switching; `IdentificationReview/` owns candidates and confidence UX; `FieldNotes/`, `Chat/`, `Sharing/`, `Reporting/`, `Toolbars/`, and `SpeciesReference/` own their named insight subareas; `Toolbars/TopToolbar/` owns collection and audio-listening overflow actions; `Shared/` holds reusable insight chrome.                                                                                              |
| Scans              | `apps/ios/Merian/Features/Scans/`                                                                                                      | Product-area-first private scan library. `Shell/` owns the root sheet, pager, toolbar, and search chrome; `Library/` owns individual scans, `ScansManager`, the search index, and queued-scan snapshots; `Collections/` owns collection grids, detail routes, smart collections, and scan selection flows; `NonBiological/` owns the non-biological isolation surface; `Shared/` holds scan grid, thumbnail, empty-state, and deletion UI reused across Scans product areas.                                                                                                                                                                                 |
| Explore            | `apps/ios/Merian/Features/Explore/`                                                                                                    | Product-area-first public discovery feature. `Shell/` owns the root sheet/router, conversion from typed capture-goal and progress-toast destinations into focused standard Field trip checklist-item routes or Events-gated Seasonal Challenge detail routes, device-local completed-goal scan lookup and embedded Insight routing, stack-based author-profile routing, the profile-to-scan nesting cap, and scoped video playback coordinator; `Feed/` owns observations feed, post detail, comments, hashtags, feed interaction state, the shared feed/detail media host, feed center Play/Pause versus outer navigation gesture policy, surface-aware video mute transitions, standalone-audio spectrogram playback with a display-synchronized live-clock playhead, and device-local per-post audio boost preferences/DSP; `Map/` owns the map surface; `Identify/` owns Community ID requests/activity; `FieldTrips/` owns public Field trip Outings and client-staged Events, Goals/Tips detail, completed-scan thumbnails, Seasonal Challenges, guided template detail, focused target expansion/highlighting, its capture-goal provider mapping, progress, publication/challenge-entry detail, badges, and profile modules; `Notifications/` owns Explore activity notifications; `AuthorProfile/` owns public author profile content/routes; `Shared/` holds only cross-area Explore UI helpers; and `Widgets/` writes the image-only Explore widget cache. |
| Messages sharing   | `apps/ios/messages/ScanSharing/`, `apps/ios/messages/MerianMessagesExtension/`                                                         | Shipped iMessage sharing surface. `MerianMessagesExtension/` owns the extension UI, `ScanSharing/Shared/` owns the App Group cache model read by both targets, and `ScanSharing/AppSupport/` owns the containing-app cache writer.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Profile            | `apps/ios/Merian/Features/Profile/`                                                                                                    | Product-area-first account feature. `Shell/` owns the profile/settings pager and close chrome; `UserProfile/` owns the public profile card, published scans preview, Field trip profile modules, achievements, persona, terrarium, heatmap, and profile stats actor; `Settings/` owns preferences, geoprivacy, export, resources, and danger-zone account actions; `Settings/Plan/` owns RevenueCat plan management, profile plan cards, and paywall UI; `Settings/Notifications/` owns push-notification preferences; `Settings/Changelog/` owns bundled release notes; `Settings/Feedback/` owns the beta survey; `Shared/` holds cross-area profile state such as `ProfileViewModel`. |
| Species Dictionary | `apps/ios/Merian/Features/SpeciesDictionary/`                                                                                          | Product-area-first species reference feature. `Detail/` owns the public species page, UUID-first readable share action, reference gallery, and authenticated Community sightings preview/paginated grid; `Catalog/` owns the Explore Index catalog/overview/regions surfaces; and `Tree/` owns the taxonomy canvas and graph model. External UUID and UUID-plus-slug links enter through the shared deep-link parser and `CaptureWorkspaceViewModel`, then open this detail in Explore's Dictionary stack.                                                                                                                                                                                   |
| Onboarding         | `apps/ios/Merian/Features/Onboarding/`                                                                                                 | Product-area-first permission priming flow. `Shell/` owns the root view and state machine, `Steps/` owns the welcome/camera/location/ready screens plus shared step chrome, and `Permissions/` owns native permission delegates.                                                                                                                                                                                                                                                                                                                                                                                                                             |

The long-term ownership and extension contract for the Capture/Explore goal
seam is recorded in
[`docs/rfcs/active-capture-goal-context.md`](rfcs/active-capture-goal-context.md).

## Public Web App

The public web frontend lives in `apps/web/` and is intentionally separate from
the native iOS source tree.

| Area                       | Current files                                                                                                                                                                               | Responsibility                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| App shell                  | `apps/web/app/layout.tsx`, `apps/web/app/theme.ts`, `apps/web/app/globals.css`                                                                                                              | Mantine provider, global metadata defaults, theme, pre-hydration color-scheme bridge, and responsive page chrome.      |
| Marketing/home placeholder | `apps/web/app/page.tsx`, `apps/web/lib/exploreMedia.ts` | Lightweight landing surface with a public Explore grid that keeps visual heroes and uses species reference thumbnails for audio posts. |
| Explore share page | `apps/web/app/explore/post/[postId]/page.tsx`, `apps/web/components/ExploreMediaCarousel.tsx`, `apps/web/components/ExploreBoostedAudio.tsx` | Server-rendered public post page with square ordered media, looping muted video, spectrogram-backed audio, optional local Boost Audio, metadata, and support reporting. |
| Species share page | `apps/web/app/species/[speciesId]/page.tsx`, `apps/web/app/species/[speciesId]/[slug]/page.tsx`, `apps/web/lib/species.ts` | Server-rendered UUID-first readable Species Dictionary page with UUID-only/stale-slug redirects, strict versioned Edge mapping, rights-filtered reference imagery/metadata, native CTA, and textual lookalike navigation. |
| Web audio boost stream | `apps/web/app/api/explore/audio/route.ts`, `apps/web/lib/audioProxy.ts` | Range-capable same-origin WAV stream restricted to public Naturebook media on the durable `media.merian.app` technical host; used only when a visitor activates browser-local Boost Audio. |
| Public beta waitlist | `apps/web/app/api/waitlist/route.ts`, `apps/web/components/WaitlistForm.tsx`, `apps/web/lib/boundedJson.ts`, `apps/web/lib/waitlistSecurity.ts` | 4 KiB streamed JSON boundary, conservative email normalization, explicit Turnstile widget/Siteverify flow, trusted-proxy daily IP HMAC, distributed pre-provider rate claim, stable request IDs, and service-only atomic database insertion. |
| Policy/support pages       | `apps/web/app/privacy/`, `apps/web/app/privacy-choices/`, `apps/web/app/terms/`, `apps/web/app/guidelines/`, `apps/web/app/support/`, `apps/web/app/legal/`                                 | App Store-friendly public policy, data-choice, community, support, and legal hub pages.                                |
| Legal/public components    | `apps/web/components/PublicPageShell.tsx`, `apps/web/components/LegalPage.tsx`, `apps/web/components/ThemePreferenceBridge.tsx`, `apps/web/lib/site.ts`, `apps/web/lib/theme-preference.ts` | Shared public page chrome, legal document layout, iOS-to-Mantine theme preference sync, support email/site URL config. |
| Supabase access            | `apps/web/lib/supabase.ts`, `apps/web/lib/explore.ts`, `apps/web/lib/species.ts`                                                                                                            | Server-only Supabase creation plus strict public Explore RPC and Species Dictionary Edge projection mapping.           |
| Universal Links           | `apps/web/app/apple-app-site-association/route.ts`, `apps/web/lib/appleAppSiteAssociation.ts`, `apps/web/lib/canonicalHost.ts`, `apps/web/proxy.ts`                                         | Exact Explore/species AASA paths, direct legacy-host AASA exception, and canonical alias redirects.                    |
| Formatting helpers         | `apps/web/lib/formatting.ts`                                                                                                                                                                | Shared Naturebook web copy and URL formatting.                                                                         |
| Local setup and CI         | `apps/web/README.md`, `apps/web/.env.example`, `apps/web/package.json`, `.github/workflows/web-quality.yml`                                                                                | Web setup, waitlist secret/ingress contract, npm scripts, dependency manifest, tests, typecheck, and production build. |

## Core Modules

| Core area      | Current files                              | Responsibility                                                                                                                                                                           |
| -------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI             | `apps/ios/Merian/Core/AI/`                 | `InferenceEngine`, edge DTOs, parse/save actor, and on-device viewfinder intelligence.                                                                                                   |
| Analytics      | `apps/ios/Merian/Core/Analytics/`          | PostHog-backed app analytics facade, usage quota, and gamification notification manager.                                                                                                 |
| Media          | `apps/ios/Merian/Core/Media/`              | Shared bounded local-media processing, including adaptive audio boost plus normalized spectrogram seeking and display-progress policy reused by Explore and private scan Insights without modifying source recordings.            |
| Data/Database  | `apps/ios/Merian/Core/Data/Database/`      | `BackgroundDatabaseActor`, `FileIOActor`, `ScanRepository`, and `HistoricalDatabaseActor`.                                                                                               |
| Data/Images    | `apps/ios/Merian/Core/Data/Images/`        | File-backed still-image preparation, the durable `ExternalImageImportStore` Photos inbox and EXIF extractor, archive rescue, photo-library access, thumbnails, RAM caching, request coalescing, and cancellation-aware bounded local/remote ImageIO decoding.                                                         |
| Offline sync   | `apps/ios/Merian/Core/Data/OfflineSync/`   | Durable queue state machine, generation-fenced upload/inference URLSession ownership, compare-before-clear retry/probe registries, background replay and reconciliation, audio queue helpers, and tokenized sync phase state.                                                                  |
| Store recovery | `apps/ios/Merian/Core/Data/StoreRecovery/` | SwiftData store metadata parsing, source-aware migration hints, duplicate-checksum detection, corruption-gated quarantine, legacy migration rescue archives, safe-mode decision support, and sanitized recovery manifests. |
| Hardware       | `apps/ios/Merian/Core/Hardware/`           | Camera, environment context, audio, spectrogram, haptics, thermal/battery orchestration, and push token management.                                                                      |
| Network        | `apps/ios/Merian/Core/Network/`            | Supabase auth/client facade, TLS-pinned network client, private Field trip completion-scan DTO mapping, Explore DTOs, species dictionary/observation-stats DTOs, and Keychain manager.                                    |
| Security       | `apps/ios/Merian/Core/Security/`           | Circuit breaker, device identity, RevenueCat, and social guard.                                                                                                                          |
| UI             | `apps/ios/Merian/Core/UI/`                 | Shared controls, tab bar, media mode toggle, domain-neutral goal progress ring, slide-to-confirm, reusable modifiers, and theme model.                                                                                      |
| Utilities      | `apps/ios/Merian/Core/Utilities/`          | App lifecycle, app events, config constants, field notes repository, image downsampling, errors, sharing, date/size helpers, and UserDefaults keys.                                      |

## SwiftData Actors

| Actor                                  | File                                                                                                   | Lifecycle                                                                                                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BackgroundDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift`                                     | Ad-hoc for live writes/enrichment/collections; long-lived through `OfflineQueueManager.resolvedQueueDbActor(container:)` for timestamp-fenced upload/inference queue transitions and orphan reconciliation.          |
| `HistoricalDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/ScanRepository.swift`                                              | Ad-hoc per historical sync, streaming one cloud page at a time.                                                                                                                                                    |
| `ProfileDatabaseActor`                 | `apps/ios/Merian/Features/Profile/UserProfile/Components/UserStats.swift`                              | Ad-hoc for profile screen calculations; long-lived via `OfflineQueueManager.resolvedProfileDbActor(container:)` for post-inference awards.                                                                         |
| `SpeciesObservationStatsDatabaseActor` | `apps/ios/Merian/Features/Insights/SpeciesReference/ViewModels/SpeciesObservationStatsViewModel.swift` | Ad-hoc per species chart load; filtered/projection SwiftData fetches for local observation overlays, then delegates bucketing to `Features/Insights/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`. |
| `SearchDatabaseActor`                  | `apps/ios/Merian/Features/Scans/Library/ViewModels/ScansManager.swift`                                 | Ad-hoc for incremental search payload extraction from persistent IDs.                                                                                                                                              |
| `FileIOActor`                          | `apps/ios/Merian/Core/Data/Database/FileIOActor.swift`                                                 | Singleton actor for image/audio file writes, deletes, and path validation.                                                                                                                                         |

The Scans library's advanced filtering worker is intentionally not a SwiftData
actor. `Features/Scans/Library/Models/ScanLibraryFilterIndex.swift` accepts only
`Sendable` projections extracted by `ScansManager`; it caches option dimensions
and performs normalized matching off-main without owning a `ModelContext`.

## Supabase Edge Function Inventory

Inference and media staging:

- `generate-upload-urls`
- `identify`
- `identify-multimodal`
- `update-scan-context`
- `identify-describe`
- `audio-spec`
- `check-scan-status`
- `enrich-scan`
- `insight-chat`

Shared identify helpers under
`services/supabase/functions/_shared/identify/` own cross-route contracts for
schema, thresholds, cache hydration, database writes, media resolution,
moderation, latency-oriented database RPCs, and subject classification.
`latencyDb.ts` owns the atomic ingestion-setup and dictionary-hydration calls;
`subjectClassification.ts` is the
processed-material boundary: visual and describe routes call it before
biological gates so manufactured or processed objects cannot enter
`species_dictionary` through one route while another blocks them.

`services/supabase/functions/_shared/aiQuota.ts`,
`_shared/groupTagQuota.ts`,
`_shared/entitlement.ts`, and migration
`20260723160229_enforce_server_ai_quotas.sql` own the cross-route paid-provider
boundary. Identification, audio, cache-miss enrichment, model chat, and
Explore/Community share-or-edit audio moderation reserve a database operation
with a stable UUID before dispatch. The shared moderation helper refuses live
provider work when a transitive caller omits that quota boundary. The migration
owns durable entitlement versioning, policy/model selection, UTC-day and
user/IP counters, ten-minute fenced reservation leases, charged failed-retry
state, automatic stale refund, and API-role privilege revocations. Coverage
lives in
`_tests/aiQuotaCoverage.test.ts`, `_tests/aiQuotaMigrationContract.test.ts`, and
`tests/ai_quota_security.sql`.

Server species-count projection:

- `services/supabase/migrations/20260724222838_optimize_species_count_trigger.sql`
  owns the explicit lock/backfill/cutover transaction, private
  `(user_id, species_id)` scan-count ledger, one-time drift repair,
  deterministic per-user serialization, and the insert/delete/update/truncate
  transition-table triggers.
- `services/supabase/functions/_tests/speciesCountTriggerMigrationContract.test.ts`
  locks the `BEGIN → LOCK TABLE → final trigger → COMMIT` ordering plus the
  statement-level, no-full-recount schema contract.
- `services/supabase/tests/species_count_trigger_security.sql` exercises bulk
  inserts, unrelated updates, OLD/NEW owner and species transfers, deletion,
  dictionary `SET NULL`, catalog shape, fixed search paths, and API-role denial.

Public species data:

- `species-dictionary`
- `species-observation-stats` — public global iNaturalist charts behind
  canonical dictionary binding, optional user plus daily-HMAC IP limits,
  negative caching, bounded provider fetches, fenced database cold-fill leases,
  stale-if-error retention, and schema/identity-checked iOS memoization

Explore and social:

- `get-explore-feed`
- `get-explore-map-points` — privacy-safe Explore Map clustering with faceted
  species-category and image/video/audio filtering
- `get-explore-post`
- `get-explore-post-detail`
- `get-explore-author-profile`
- `get-explore-author-posts`
- `get-explore-hashtag-posts`
- `get-explore-species-posts` — authenticated, exact-species Community
  sightings cards with image-quality cursor ordering
- `get-explore-comments`
- `get-explore-comment-replies`
- `get-explore-mention-suggestions`
- `field-trips`
- `report-explore-comment`
- `report-explore-post` — authenticated Explore post-content moderation queue;
  separate from scan identification review
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
- `merge-ghost-profile` — uses a source-issued, provider-bound proof to
  atomically re-parent every supported guest-owned record before purging the
  anonymous Auth shell.
- `reconcile-ghost-profile-merges` — scheduled service-role worker that leases
  committed merge receipts and retries obsolete anonymous Auth deletion.
- `safe-delete` — authenticated intake plus immediate processing for the
  durable `pending → auth_pending → completed` account-erasure state machine;
  cleanup is committed and verified before Auth deletion.
- `reconcile-account-deletions` — scheduled service-role worker that leases and
  resumes incomplete account deletion jobs without accepting caller-selected
  user IDs.
- `delete-scan`
- `flag-issue` — disputed-identification review only; writes `flagged_reviews`
  and marks the scan for review
- `submit-feedback-survey`
- `request-export-dwca`
- `export-dwca` — service-authenticated leased worker; `db.ts` owns canonical
  claim/keyset access, `archive.ts` and `zip.ts` own bounded streaming,
  `storage.ts` owns R2 multipart upload, `pseudonym.ts` owns versioned export
  HMACs, and `worker.ts` owns retry/idempotent delivery orchestration.
- `revenuecat-webhook` — verifies the configured bearer credential and
  RevenueCat raw-body HMAC, parses bounded event identities, fetches
  authoritative CustomerInfo, and commits idempotent per-user state through
  service-only database RPCs. Route-local `handler.ts`, `protocol.ts`,
  `signature.ts`, `subscriber.ts`, and `db.ts` keep those boundaries
  independently testable.
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
- `reconcile-ghost-profile-merges`
- `backfill-explore-audio-spectrograms`
- `replay-scan-ingestion`
- `scan-media-health`

Every function above has a `[functions.<name>]` entry in
`services/supabase/config.toml`. `merge-ghost-profile` and `request-export-dwca`
intentionally use `verify_jwt = true`. App-facing routes with a documented
custom identity policy may set `false` and authenticate inside shared handler
code; service-role workers such as `reconcile-ghost-profile-merges` set `false`
for `pg_net` reachability and enforce a timing-safe bearer match.
Each function also has a generated local `deno.json` backed by
`functions/dependencies.lock`. The dependency/deploy control plane lives in
`services/supabase/scripts/function_dependency_tools.ts`,
`sync_function_deno_configs.ts`, `validate_function_dependencies.ts`,
`plan_function_deploy.ts`, and `deploy_function_batches.sh`; CI uses that graph
to type-check deploy-time configs and select transitive runtime consumers. The
inventory above is descriptive rather than a second source of truth:
`function_dependency_tools_test.ts` requires exact name-for-name parity between
`config.toml` and discoverable function graphs without hard-coding a fleet
size.

## Supabase Media Projections

| Surface                         | Current files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scan ingestion jobs and intents | `services/supabase/migrations/20260705120000_add_scan_ingestion_jobs.sql`, `services/supabase/migrations/20260705130000_extend_scan_ingestion_jobs_media_manifest.sql`, `services/supabase/migrations/20260705140000_add_scan_ingestion_intents.sql`, `services/supabase/migrations/20260705150000_schedule_scan_ingestion_replay.sql`, `services/supabase/migrations/20260707143157_cap_scan_ingestion_replay_attempts.sql`, `services/supabase/functions/_shared/scanIngestionJobs.ts`, `services/supabase/functions/_shared/scanIngestionIntents.ts`, `services/supabase/functions/_shared/scanIngestionCompatibility.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/replay-scan-ingestion/`, `services/supabase/functions/_tests/scanMediaIngestionContract.test.ts` | Durable server-side state ledger, sanitized replay intent, and scheduled replay dispatcher for accepted scan ingestion attempts. The multimodal path claims and updates job state through inference, media promotion, scan insert, completion, and failure; claims include upload-session ids and a normalized media-manifest checksum so retries can be tied back to the exact media shape. Compatibility scan-producing endpoints write the same ledger before returning success, with staged image/audio and text-only intents shaped for multimodal replay. The paired intent row stores telemetry/descriptors/staged keys without raw media bytes, marking inline-media requests as non-resumable. The replay worker claims due resumable staged media/audio/video or text-only jobs and re-invokes the multimodal path with the same `client_scan_id`, capped at 10 server replay claims before `failed_terminal / server_replay_limit_reached`; status polling keeps `found` / `not_found` compatibility while exposing optional job details for retry and ops visibility. The media-ingestion contract test matrix locks these guarantees across image, audio, text-only, video, status, repair, and Explore-share seams. |
| Identification latency and deferred context | `services/supabase/migrations/20260715153946_reduce_identification_latency_round_trips.sql`, `services/supabase/functions/_shared/identify/latencyDb.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/update-scan-context/`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/Merian/Features/Capture/Submission/ViewModels/Analysis.swift` | Keeps the durable queue/auth gates while shortening the non-model critical path. One service-role RPC claims ingestion and records its sanitized intent before Gemini; eligible biological results use at most one RPC to hydrate cached primary/candidate dictionary data afterward. For eligible live-camera still scans, the client gives weather/geocoding 150 ms, avoids simultaneous inline/background uploads, and patches late owner context through the staged-context table/trigger; gallery, audio-bearing, and video submissions remain behaviorally unchanged. Diagnostic headers and structured metrics cover tap-to-render without exposing scan/user/species/location identifiers. Model selection and all generation settings remain unchanged. |
| Scan media assets               | `services/supabase/migrations/20260705100000_add_scan_media_assets.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711143348_repair_scan_media_assets_audio_constraints.sql`, `services/supabase/migrations/20260711171512_backfill_missing_ready_audio_assets.sql`, `services/supabase/functions/_shared/scanMediaAssets.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/reconcile-scan-media-assets/`, `services/supabase/functions/scan-media-health/` | Normalized image/video/audio lifecycle. Standalone audio is promoted into `audio_storage_urls`, `captured_media`, and ready owner-scoped audio assets; extracted video audio remains inference-only. The explicit constraint repair upgrades early production tables that `CREATE TABLE IF NOT EXISTS` could not reshape, and the follow-up refresh migration makes audio part of the canonical RPC and backfills durable recordings that lack normalized rows. Repair and health paths retain their existing staged-media responsibilities. |
| Explore post media              | `services/supabase/migrations/20260703130000_add_explore_post_media.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711055524_add_explore_audio_moderation_attestations.sql`, `services/supabase/functions/_shared/explorePostMedia.ts`, `services/supabase/functions/_shared/exploreComposerMedia.ts`, `services/supabase/functions/_shared/audioModeration.ts`, `services/supabase/functions/_shared/audioSpectrogram.ts`, `services/supabase/functions/share-scan-to-explore/`, `services/supabase/functions/request-community-identification/`, `services/supabase/functions/update-explore-field-notes/`, `services/supabase/functions/backfill-explore-audio-spectrograms/` | Post-owned image/video/audio snapshots. Audible media must have a matching content-addressed attestation or pass the dedicated Gemini speech/non-speech classifier under the authoritative quota boundary before share, Community-request, or edit replacement; changed bytes, model, or policy contract force re-moderation. Approved WAV audio gets a deterministic persisted spectrogram poster shared by web and normalized media; a bounded service-role repair worker fills historical blanks while unsupported legacy codecs keep playback and the icon fallback. Legacy local audio can be repaired through owner-scoped staging into `audio_storage_urls`, canonical `captured_media`, and normalized assets before the same gate runs. Failed attempts create no pending/public media state; maps, widgets, profile grids, and compact previews remain thumbnail-first. |

## Internal admin surface

- `apps/admin/`: isolated Next.js + Mantine SSR admin for
  `admin.naturebook.earth`, with Google OAuth, TOTP AAL2, role-aware navigation,
  strict response headers, CSRF/origin-checked Server Actions, and no
  service-role key.
- `services/supabase/migrations/20260719161112_add_internal_admin_foundation.sql`:
  internal membership/session/audit/review/feedback/pricing schema, narrow admin
  RPCs, reversible post moderation, and canonical AI usage ledger.
- `services/supabase/functions/report-user/`: authenticated non-self visible
  profile reporting endpoint.
- `services/supabase/functions/_shared/aiUsage.ts`: normalized Gemini modality
  accounting and bounded best-effort writers for independent operations.
- `services/supabase/tests/admin_foundation_security.sql` and
  `admin_review_ai.sql`: live pgTAP authorization/session and grouped
  review/moderation/ledger contracts.
- `docs/backend-and-data/10-internal-admin.md` and
  `11-internal-admin-operations.md`: architecture/data contract and the
  setup/deployment/recovery operator runbook.

## Test Inventory

Swift unit tests live under `apps/ios/MerianTests/` and cover:

- Active schema models and migration invariants.
- Capture workspace staging, camera analysis, Photos document-import durability
  and EXIF handling, active capture-goal presentation/gesture policy,
  audio/describe helpers, and queued handoff flows.
- Field trip capture-context decoding and provider mapping into generic goals,
  cross-field trip order and wraparound, completion advancement, account-isolated
  caching, stale-data retention, exact artwork mapping, typed destinations, and
  focused Explore routing, plus private completed-scan ID decoding for
  item-specific catalog/detail thumbnails.
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

Fleet-wide ingress coverage lives in `_shared/http_test.ts`,
`_tests/edgeHandler.test.ts`,
`_tests/jsonEndpointSecurityCoverage.test.ts`, and
`_tests/jsonEndpointSecurityMigrationContract.test.ts`. The executable
`services/supabase/tests/waitlist_security.sql` fixture verifies the waitlist
RPC's ACL, constraints, duplicate behavior, and transactional rate ceilings.
Web parser, email, proxy, HMAC, and Turnstile behavior is covered by
`apps/web/lib/*.test.ts`.

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
- Public web routes, metadata, env variables, canonical `naturebook.earth`
  generation, or legacy `merian.earth` Universal Link compatibility.
- Native extension targets, App Group boundaries, or shipped/de-shipped
  extension source ownership.
- Asset catalog groups, reusable artwork names, app icons, brand marks, persona
  art, or widget fallback imagery.
- Cross-feature domain contracts, typed navigation boundaries, cache-version
  rules, or accepted architecture decisions under `docs/rfcs/`.
- Release-note behavior in `CHANGELOG.md` or the bundled in-app changelog JSON.
