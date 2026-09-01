# Current Codebase Map

Last reviewed: 2026-08-24.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed
for developer convenience and should be regenerated with `xcodegen generate`
after target, package, entitlement, build setting, or source-list changes.

| Target                    | Type                    | Source                                                                                                            | Deployment   |
| ------------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------ |
| `Merian`                  | iOS application         | `apps/ios/Merian/`, `apps/ios/Shared/Branding/`                                                                   | iOS 17.2     |
| `MerianExploreWidget`     | WidgetKit app extension | `apps/ios/widgets/Explore/`, `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift`, shared branding | iOS 17.2     |
| `MerianMessagesExtension` | Messages app extension  | `apps/ios/messages/MerianMessagesExtension/`, `apps/ios/messages/ScanSharing/Shared/`, shared branding            | iOS 17.2     |
| `MerianWatch`             | watchOS companion app   | `apps/watch/MerianWatch/`, shared branding                                                                        | watchOS 10.0 |
| `merianTests`             | Unit tests              | `apps/ios/MerianTests/`                                                                                           | iOS 17.2     |
| `merianUITests`           | UI tests                | `apps/ios/MerianUITests/`                                                                                         | iOS 17.2     |
| `@merian/web`             | Next.js public web app  | `apps/web/`                                                                                                       | Node/Next.js |

Tracked build config:

- `Config.xcconfig` stores app-facing runtime values such as Supabase URL,
  Supabase publishable key, RevenueCat, PostHog, and Google Sign-In client IDs.
  These are bundled client config values, not backend-only secrets.
- `Signing.xcconfig` includes optional ignored `Signing.local.xcconfig`.
- `Signing.local.example.xcconfig` is the template for a local Apple Developer
  Team ID.
- `apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy` is the main app's
  privacy declaration. XcodeGen places it exactly once at the root of
  `Merian.app`; `scripts/validate-ios-privacy-manifest.sh` owns the exact
  collected-data and required-reason policy.

Web runtime config:

- `apps/web/.env.example` documents the public web environment.
- `NEXT_PUBLIC_SITE_URL` should be `https://naturebook.earth` in production.
- `NEXT_PUBLIC_SUPPORT_EMAIL` should be `support@naturebook.earth` in
  production.
- Supabase server keys are server-only. Prefer `SUPABASE_SERVER_API_KEY`, then
  the hosted `SUPABASE_SECRET_KEYS` JSON dictionary; `SUPABASE_SERVICE_ROLE_KEY`
  is migration-only. The singular Edge-local `SUPABASE_SECRET_KEY` is
  deliberately unsupported by web. Never expose any server key through a
  `NEXT_PUBLIC_` variable or client component. Their only web owner is
  `apps/web/lib/supabaseAdmin.ts`, guarded by `server-only`; `explore.ts` uses
  that client only through fixed-anonymous, service-only web RPCs.
  `supabasePublic.ts` contains the anonymous Species Dictionary projection
  client. Credential sources are classified independently so a malformed lower
  migration source cannot veto a valid selected source or enter the candidate
  set.
- **Release status:** DwC-A is hidden in Release iOS builds and disabled by the
  canonical private PostgreSQL singleton for the initial launch. The server
  rejects old/direct intake, scheduled continuation is stopped, capabilities are
  revoked, and archive cleanup stays active. Public-web detail independently
  owns canonical anonymous visibility and
  `get_public_web_explore_post_page(...)` returns card plus detail atomically.
  Base promotion remains held for exact-SHA fresh-catalog, complete CI, catalog,
  and credential-smoke evidence; active export load/delivery evidence belongs to
  the later feature-enable gate. See
  `docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`.

## Public Brand and Compatibility

Naturebook is the public product and Merian is the permanent technical identity.
The iOS/extension source of truth is
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

| Area                         | File                                                                                                                                                             | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| SwiftUI app entry            | `apps/ios/Merian/App/MerianApp.swift`                                                                                                                            | Builds the `ModelContainer` from `CurrentSchema` using store-aware migration selection, delegates duplicate-checksum fallback, corruption quarantine, and legacy migration rescue to `Core/Data/StoreRecovery/`, selects onboarding, retryable launch-matched consent restoration, or Capture workspace through `AppRootPresentationPolicy`, configures `ScanRepository`, migrates species display preferences, prepares the first-party analytics facade outside tests without configuring PostHog, applies global theme to `UIWindow`, handles canonical `naturebook://` and legacy `merian://` Explore/species/scan/library deep links plus Naturebook/Merian Universal Links, and classifies file URLs for the Photos document-import inbox before Supabase auth handling. |
| App delegate bridge          | `apps/ios/Merian/App/MerianApp.swift`                                                                                                                            | Owns background `URLSession` completion handoff and push token callbacks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Objective-C exception bridge | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`, `apps/ios/Merian/Configuration/Merian-Bridging-Header.h`                                                      | Converts launch-time SwiftData/Core Data Objective-C exceptions into Swift errors so store recovery can run.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Dependency container         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                                                                      | Owns the production dependency graph, including one typed invalidation bus, one route coordinator, one milestone presenter/coordinator/host registry, and its clock; injects observable hardware, AI, sync, network, analytics, security, settings, profile, goal-context, route, and feedback state through SwiftUI `@Environment`. Preview graphs remain isolated from production route/auth/milestone binding.                                                                                                                                                                                                                                                                                                                                                              |
| Local visual-analysis DI     | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/LocalVisualAnalysis.swift`                                                                 | Owns the live Apple Vision classifier, deterministic five-cue palette/tone/contrast/surface trait extractor, no-op Xcode 26.6 Foundation visual-cue provider, and runtime eligibility checker injected into `InferenceEngine`. The bounded image and all local classifications/cues remain ephemeral.                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Typed invalidation bus       | `apps/ios/Merian/Core/Utilities/AppEventPublisher.swift`                                                                                                         | Synchronous `@MainActor`, process-local, loss-tolerant invalidations and lifecycle commands. The subject is private; producer and streaming capabilities are separated, and payloads never replace durable authority.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Root route state machine     | `apps/ios/Merian/Core/Utilities/AppRouteCoordinator.swift`                                                                                                       | Bounded priority/FIFO navigation envelopes with stable IDs, semantic coalescing, expiry, account/session fences, explicit outcomes, one in-flight request, and exact presentation-dismissal identity. Durable work remains in its owning store.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Typed visual feedback        | `apps/ios/Merian/Core/UI/Feedback/ToastPayload.swift`, `AchievementToastPresenter.swift`, `apps/ios/Merian/Core/UI/Modifiers/MerianSystemFeedbackModifier.swift` | Lightweight severity/action-typed ordinary toasts plus the bounded, deduplicated, session-fenced milestone queue. A foreground-host registry serializes nested rendering; identity-keyed structured tasks, injected milestone time, and one-time effect claims prevent stale teardown and remount replay. Passive feedback remains pass-through.                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Framework publisher bridge   | `apps/ios/Merian/Core/Utilities/Publisher+MainActor.swift`                                                                                                       | Ordered asynchronous hop from framework Combine publishers with unknown originating executors to a compiler-declared `@MainActor` receive closure. The synchronous app bus does not use this bridge.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Detached work helper         | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                                                                      | Small wrapper for intentional detached image, database, file-system, and bootstrap work.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianActiveSchemaV50
```

`MerianActiveSchemaV50` is declared in
`apps/ios/Merian/Models/SchemaVersions.swift`. The released V50 graph is frozen
in `Models/Schema/SchemaV50Snapshots.swift`; the active V50 owner references the
current models plus its schema-scoped goal-hint companion. V47 through V50
remain available in `SchemaVersions.swift` for fixtures and source-specific
startup recovery.

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

Active V50 resolves the SwiftData tombstone naming collision in source. The
`ScanCollection.isPendingDeletion` property maps to the released `isDeleted`
column with `@Attribute(originalName:)`; the outgoing `is_deleted` wire field
and acknowledgement-only purge contract remain unchanged. The frozen
`MerianSchemaV50` graph is an immutable released-store fixture;
`MerianActiveSchemaV50` has the same persisted V50 model, so no rename migration
stage exists. The canonical schema and recovery contract is in the
[SwiftData schema contract](./backend-and-data/04-database-schema.md#scancollection-user-albums).

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
  V43 stores also use a source-isolated startup recovery plan before the V43→V49
  repair path.
- V44 added optional dog/cat pet-identification display metadata on completed
  local scans.
- V45 added optional invasive-status context to completed local scans. V46 was a
  shipped no-op checksum twin of V45; runtime migration keeps the
  duplicate-prone V44/V45/V46 recent cluster out of the full historical plan,
  jumps older stores V42→V49 or V43→V49, and uses source-isolated recent plans
  for stores already stamped V42, V43, V44, V45, or V46. V44, V45, and V46
  stores jump through separate direct V44→V49, V45→V49, and V46→V49 plans.
- V47 added offline video inference replay fields so sampled frames can be
  queued separately from the user-visible playback video timeline. Its frozen
  schema keeps local-scan, captured-media, and collection models self-contained
  inside V47, and keeps `OfflineQueuedScan` scalar-only.
- V48 added durable queue retry metadata on `OfflineQueuedScan`, plus
  `OfflineJobRecord` and bounded `OfflineQueueEvent` rows for scan ingestion,
  cloud deletion, collection sync, diagnostics, and future offline work. The
  V47→V49 migration is custom, not lightweight: every existing queued scan must
  leave migration with retry fields initialized and a `scan-ingestion:{id}` job
  row so startup can recover persistently on stores with queued media. V47
  job/event rows and replacement queued-scan rows are seeded from migration
  snapshots so stale SwiftData model-identity traps cannot survive into V49.
- V49 is a startup store-repair schema. It keeps the V48 queue scheduler model,
  adds `OfflineQueuedScan.queueSchemaRepairGeneration`, and provides separate
  V48→V49 plans for the known-good V48 checksum and the accidental
  optional-queue V48 TestFlight checksum. Startup diagnostics record redacted
  store metadata and attempted plan names so failing devices can share evidence
  without exposing paths, account data, scan text, or media URLs. The existing
  integer is also the durable runtime generation/latch for converting pre-WAV
  queued audio before upload or replay (`-1` claimed, `2` committed, `1`
  ordinary/reset). This semantic reuse does not alter the V49/V50 model shape or
  add a migration stage. `MigrationPlanTests` carries the disk-store fixture
  matrix for image, video, audio, description-only, and mixed queued media, and
  `.github/workflows/ios-startup-safety.yml` runs that suite beside store
  recovery tests.
- V50 adds `OfflineQueuedScanGoalHint`, a scan-keyed companion containing the
  optional standard-outing and checklist-item preference for a queued scan. Its
  frozen graph is pinned in `SchemaV50Snapshots.swift`; the lightweight V49→V50
  stage leaves `OfflineQueuedScan` unchanged. Stores already stamped V49 use a
  dedicated `[V49, active V50]` source-isolated plan, while stores stamped V50
  open as current without a migration plan. Older recent source-specific plans
  reach V49 and then active V50. The supported recent-source enum remains
  consecutive through V49; app dispatch is exhaustive and has no full-history
  fallback for an unhandled recent source. Disk fixtures run the production
  metadata decision before opening stores, and the source guardrail locks
  checksum retry order to current store followed by V49 through V42.

Compiled iOS assurance lives in `.github/workflows/ios-build-and-test.yml`. Its
fail-closed detector (`scripts/ci-detect-ios-build-source-changes.sh`) sends
every iOS/watch/project build input, merge-queue commit, and manual request to
pinned Xcode 26.6 jobs that execute the complete unit-test target, then the four
deterministic progressive-analyzing, live-to-queue, queued-retry, and
queued-completion UI smokes, and independently create an unsigned current-SHA
Release archive without allocating a release build. Distribution is owned solely
by Xcode Organizer after the exact SHA passes the full iOS workflow. Operators
archive a clean `main` checkout with the Merian scheme, choose **TestFlight &
App Store**, and leave automatic signing plus **Manage version and build
number** enabled. Xcode and App Store Connect own the unique uploaded build
number; GitHub has no Apple signing or upload credentials.
`scripts/check-ios-release-prep.sh`,
`scripts/ios-release-source-fingerprint.sh`, and
`scripts/embed-ios-build-provenance.sh` require a clean exact revision and bind
its fingerprint/state into the app. The tracked `CURRENT_PROJECT_VERSION`
remains a synchronized archive baseline rather than a per-beta counter. CI
verifies this boundary and produces only an unsigned validation archive. The
processed App Store Connect build is then promoted without rebuilding between
TestFlight and App Review stages. The authority decision is documented in
`docs/system-architecture/09-ios-release-publisher.md`; setup, archive,
verification, upload, promotion, and emergency procedures live only in
`docs/development-guides/14-ios-release-versioning.md`. Fingerprinting rejects
tracked `assume-unchanged` and `skip-worktree` index state so sparse or locally
hidden files cannot masquerade as a complete clean release checkout. The embed
phase also rejects traversal, a final plist symlink, or a multiple-hard-link
plist before writing provenance outside the canonical product build directory.
`scripts/check-ios-project-resources.sh` additionally proves the preflight and
embed phases are defined once, invoke only the canonical scripts, belong only to
the main `Merian` target, and occupy the required first and final
product-mutating positions. Its portable detached, duplicate, wrong-command, and
phase-order fixtures live in `scripts/test-check-ios-project-resources.sh`.
`scripts/check-ios-project-source-membership.sh` compares every `project.yml`
source against the generated build phases and rejects source code orphaned
outside all declared targets; its adversarial fixture is
`scripts/test-ios-project-source-membership.sh`.
`scripts/test-ios-build-and-test-workflow.sh` locks the complete unit-target and
exact queued-scan UI selectors, invocation of that membership check, exact-SHA
and lockfile behavior, immutable action pins, focused-result validation,
archive/dSYM checks, and unconditional final decision. Repository rules should
require only `iOS Build and Test / Production readiness`. On failure,
`scripts/extract-ios-test-failure-diagnostics.sh` reads the structured result
summary first, then the failed test tree, and uses the raw build log only as a
fallback. Its fixture test prevents expected negative-path application logs from
replacing the actual failed test and assertion in the job summary.

Backend candidate assurance lives in **Supabase Candidate Validation**
(`.github/workflows/supabase-candidate-validation.yml`). A fail-closed scope job
runs on every pull request and reports the stable **Candidate readiness** check;
manual candidate refs, merge-queue commits, and `.github/workflows/deploy.yml`
force complete validation. The scope covers the full contract-input roots and
unresolved or unclassified comparisons fail closed. The workflow can then verify
a clean exact SHA with pinned tools, full migration replay, discovered pgTAP
catalogs, Edge/database-concurrency tests, lint, and advisors against a
disposable database. It has no Production environment, production secrets, or
mutation step. The production workflow's separate `deploy` job depends on this
gate and is the only job that receives Production access, pushes migrations,
deploys Functions, or runs production smokes.

Historical schema snapshots V1 through V39 live under
`apps/ios/Merian/Models/Schema/`. V40 through V49 live in `SchemaVersions.swift`
alongside the migration plan; the released V50 graph is frozen in
`SchemaV50Snapshots.swift`, while the active V50 owner and migration plans
remain in `SchemaVersions.swift`.

## Feature Modules

| Feature            | Current files                                                                  | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture            | `apps/ios/Merian/Features/Capture/`                                            | Product-area-first capture surface. `Shell/` owns the three-page Scan/Record/Describe pager, fixed overlay chrome, the sole root `CameraSheetRouter` host, route consumption, exact dismissal handoff, root view model, pending Photos-import handoff, draft mutation/file cleanup, and the non-blocking active-goal indicator/deep link. Feature-local description/question/video/crop/survey presentations report the same UIKit slot as occupied without becoming global routes. `Core/Models/CaptureGoalContext.swift` defines the source-agnostic goal, provider, typed destination, and app-injected account cache; the Field trips feature is the first provider. `Staging/` owns the ephemeral mixed-media aggregate, canonical chronology and capacity/media values, plus description/crop presentation timing. `Submission/` owns staged-to-request projection, live/replay timelines, hand-written Identify descriptors, shared live/offline admission and analysis orchestration, normalized staged payloads, and the typed foreground/queue-only route. `Refinement/` is reserved for reanalysis helpers; `Shared/` holds cross-mode capture primitives.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Scan               | `apps/ios/Merian/Features/Capture/Scan/`                                       | Visual-modality preview, focus/zoom/photo/video actions, platform-neutral media request/result values, narrow camera/context/Photo Library/media/entitlement/feedback adapters, bounded still preparation, sampled-frame/playback/WAV video preparation, and generation-fenced recording/progress task ownership. Views/components contain no networking or global service resolution, and every production Scan file stays below the 600-line guard. `CameraManager` owns session/device configuration. Shared crop encoding lives in `Core/Media`; the crop view and presentation-only flash control live in `Core/UI`; Capture source/crop metadata remains in `Capture/Shared`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Record             | `apps/ios/Merian/Features/Capture/Record/`                                     | Audio Listen Mode presentation split across platform-neutral `Models`, the only concrete manager/haptic adapter in `Services`, UI-only idle/scrub state in `ViewModels`, a thin `Views` composition, and focused `Components`. Shell resolves the live manager snapshot and retains microphone permission and record/pause/resume/stop/review controls; Submission retains staging and `/identify-multimodal` orchestration. `Core/Hardware` owns the 15-second Int16 WAV engine, playback, FFT, rolling ambient-noise policy, and token-aware audio-session leases. `Core/Media` owns shared spectrogram raster/layout policy, `Core/UI` owns the shared SwiftUI spectrogram, and `Capture/Shared` owns the audio/video countdown badge. Record views issue no endpoint calls and every production Record file stays below the 600-line guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Describe           | `apps/ios/Merian/Features/Capture/Describe/`                                   | Typed and dictated observation presentation. `Models/` owns prompt/subject values, taxonomy resolution, exact text composition, and stable tag ranking; `Services/` owns live preference, haptic, keyboard, subject-delay, and speech-manager adapters; `ViewModels/` owns prompt/funnel state plus generation-fenced subject inference and dictation sessions without constructing concrete hardware adapters; `Views/` retains the page, workspace lifecycle observer, focus, and sheet timing; and `Components/` owns the UIKit scroll host, navigation, tags, and editor. Views/components resolve no singleton or platform action, Models remain platform-neutral, and every production Describe file remains below the 600-line guard. Cross-feature `SpeechManager` and its lifecycle tests live in `Core/Hardware`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Insights           | `apps/ios/Merian/Features/Insights/`                                           | Product-area-first result feature. `Shell/` owns presentation sessions, completed-scan routes, navigation, and generation-fenced result activation; `Content/` owns biological/non-biological results and queued/foreground analysis UI; `IdentificationReview/` owns candidate and confidence workflows; `Media/` owns Insight page assembly, continuity, focus, availability, inline video, boost policy, and scan-to-export request mapping; `FieldNotes/`, `Sharing/`, and `Toolbars/` own their named subareas; and `Shared/` contains only Insight-specific cross-subarea presentation. Core Media/UI own export processing and reusable carousel playback/gallery primitives. Species Reference and Field Chat are independent cross-feature owners.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Species Reference  | `apps/ios/Merian/Features/SpeciesReference/`                                   | Cross-feature species-level charts, habitat, GBIF heatmaps, taxonomy, lookalikes, and fallback reference imagery used by Insights, Explore, Species Dictionary, and identification review. Platform-neutral Models own aggregation/presentation policy; Services alone resolve SwiftData, endpoints, external sessions, image loading, haptics, and enrichment; generation-fenced ViewModels publish async state; Views and domain Components retain task identity, gestures, scrolling, placeholders, and UI-only timing. Every production file remains below 600 lines.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Field Chat         | `apps/ios/Merian/Features/FieldChat/`                                          | Cross-feature private Pro conversation experience used by Insights, Explore posts, and Species Dictionary pages. Platform-neutral `Models/` own source and presentation values; `Services/` alone resolve live endpoint, haptic, telemetry, clipboard, clock, and request-ID dependencies; `ViewModels/` own subject-generation-fenced conversation, prompt, feedback, availability, and review state; and `Views/` plus grouped `Components/` retain rendering and UI-only timing. Host features own eligibility, entitlement, navigation, and sheet occupancy. Core Network retains Codable DTOs, strict validation, and transport. Stable `InsightChat...` names remain source-compatible. Every production Field Chat file stays below the 600-line guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Scans              | `apps/ios/Merian/Features/Scans/`                                              | Product-area-first private scan library. `Shell/Models` owns tabs, typed routes, session fencing, and UI-only incident presentation; `Shell/Services` owns queue/record SwiftData reads, account-scoped overview preferences, thumbnail prefetch/backfill/cloud repair, and service-specific repository/loader/actor/event adapters; `Shell/ViewModels` owns queue polling policy, incident loading/coalescing/cancellation/account fencing, store synchronization, selected-record mutations, and the narrow auth/endpoint/event/time/badge dependency value for that state; `Shell/Views` retains only navigation, pager, focus, alert, animation, and lifecycle presentation timing; and `Shell/Components` owns toolbar, tab composition, and presentation modifiers. Shell views/components make no endpoint, Supabase, shared-loader, actor, or app-container lookup. The private queued route retains `QueuedScanContext` while hashing by ID, and the destination treats a persisted same-ID completion as authoritative on every bind. `Library/` owns individual scans, `ScansManager` observable state/actions and event sink, the contained generation-fenced `ScansLibrarySearchCoordinator`, feature-local search/filter models and actors, the advanced filter component, injected export/publication/event/haptic adapters, queued completion-race hydration, and mixed photo/video batch-save feedback. Library views/components resolve no endpoint or singleton. `Collections/Models` owns membership, cover, catalog, and smart presentation values; `Collections/Services` owns save-first validation/mutations, smart suggestion policy, local smart preferences, and narrow event/share-state/sync/feedback adapters; `Collections/ViewModels` derives catalog, detail, selection, and smart-detail state from the Shell-owned record query; `Collections/Views`, `Components/Cards`, and `Components/Catalog` retain navigation, search, timer, lifecycle, and Collections-local presentation; and `Components/Alerts` owns collection-action presentation consumed by Collections, Scans Shell, and Insight. Collections views/components perform no SwiftData fetch or singleton lookup. `Map/Models` owns exact owner-coordinate snapshots, region/annotation geometry, and presentation values; `Map/Services` owns detached SwiftData projection, the revisioned store/index, lossless refresh and sensitive-reset fencing, MapKit/Web-Mercator clustering, viewport work, startup/current-location sequencing, and preview rendering; `Map/ViewModels`, `Map/Views`, and `Map/Components` own presentation state and UI with no endpoint calls or direct persistence reads. Scans Shell remains the typed Insight route owner. `NonBiological/Models` owns correction/copy values plus refresh and erasure snapshots; `NonBiological/Services` owns retention purge, actor-isolated database/file deletion, library invalidation, deletion sync, route, and feedback adapters; `NonBiological/ViewModels` derives the isolated record set from the Shell query and owns mutation lifecycle; and its thin View/Components retain only navigation and presentation timing. Non-biological views/components perform no persistence reads, actor construction, or singleton lookup. `BackgroundDatabaseActor` is the commit-time deletion authority: it re-fetches every candidate and skips a row reclassified as biological before accepting its record, local-path, or cloud-deletion mutation. `Shared/Models` owns detached queued-row values, `Shared/Services` owns injected grid feedback and single-delete orchestration, `Shared/Components/Grid` owns the Scans-only composite grid, and `Shared/Modifiers` owns deletion alert presentation. Shared views/components perform no fetch, endpoint, loader, repository, or app-container lookup. Cross-feature `ScanThumbnail` and `EmptyStateView` presentation lives in `Core/UI`; immutable thumbnail-backfill inputs live with the actor in `Core/Data/Images`. Every production Shell, Library, Collections, Map, NonBiological, and Shared file remains below the 600-line review guard. |
| Explore            | `apps/ios/Merian/Features/Explore/`                                            | Product-area-first public discovery feature. `Shell/` owns the root sheet/router, conversion from typed capture-goal and progress-toast destinations into focused standard Field trip checklist-item routes or Seasonal Challenge detail routes, device-local completed-goal scan lookup and embedded Insight routing, stack-based author-profile routing, the profile-to-scan nesting cap, and scoped video playback coordinator; `Feed/` owns observations feed, post detail, comments, hashtags, feed interaction state, the shared feed/detail media host, feed center Play/Pause versus outer navigation gesture policy, surface-aware video mute transitions, standalone-audio spectrogram playback with a display-synchronized live-clock playhead, and device-local per-post audio boost preferences/DSP; `Map/` owns the map surface; `Identify/` owns Community ID requests/activity; `FieldTrips/` owns its typed cross-surface routes, public Field trip Outings and Events, Goals/Tips detail, completed-scan thumbnails, Seasonal Challenges, guided template detail, focused target expansion/highlighting, its capture-goal provider mapping, progress, publication/challenge-entry detail, badges, and profile modules; `Notifications/` owns Explore activity notifications; `AuthorProfile/` owns public author routes, profile/library presentation, injected loading/pagination/follow/report state, and feature-grouped components, with live networking confined to its `Services/` adapter; `Shared/` holds only cross-area Explore UI helpers; and `Widgets/` writes the image-only Explore widget cache. Core UI owns the published-scan grid geometry shared by Author Profile, Profile, and Species Dictionary.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Messages sharing   | `apps/ios/messages/ScanSharing/`, `apps/ios/messages/MerianMessagesExtension/` | Shipped iMessage sharing surface. `MerianMessagesExtension/` owns the extension UI, `ScanSharing/Shared/` owns the App Group cache model read by both targets, and `ScanSharing/AppSupport/` owns the containing-app cache writer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Profile            | `apps/ios/Merian/Features/Profile/`                                            | Product-area-first account feature. `Shell/` owns the profile/settings pager, close chrome, and composition of the environment-owned geoprivacy and hardware adapters required by Settings; `UserProfile/` owns the public profile card, published scans, Field trip profile modules, achievements, persona, terrarium, heatmap, and Profile stats actor. Within `UserProfile/`, Models hold feature values/policy, Services resolve live endpoints plus imperative SwiftData, image, event, route, preference, and haptic boundaries, and ViewModels own generation-fenced asynchronous state. Views/Components retain presentation state and rendering; the publication grids keep a read-only local-scan query only for reference-image fallback on already server-visible posts. `Settings/` owns preferences, privacy/processing withdrawal, optional analytics, geoprivacy, export, resources, and danger-zone account actions. Its Models contain presentation values, Services contain narrow account/export/preference/platform action adapters, and ViewModels own serialized, single-flight, or generation-fenced lifecycle state. Leaf Views/Components retain route, binding, focus, animation, reactive environment reads, and rendering state without endpoint, direct SDK-write, repository, or action-singleton lookup. Account-deletion protocol/recovery and durable Apple fallback recording remain in `SupabaseManager`; Settings injects the local purge adapter. `Settings/Plan/` and `Settings/Feedback/` repeat the full Models/Services/ViewModels/Views/Components boundary for RevenueCat and survey submission; `Settings/Notifications/` uses Models/Services/ViewModels/Views for push preferences; and `Settings/Changelog/` owns local Models/Views release notes. Cross-surface complimentary-scan display state belongs to `Core/UI/Models`, while `Shared/` holds cross-area profile state such as `ProfileViewModel`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Species Dictionary | `apps/ios/Merian/Features/SpeciesDictionary/`                                  | Product-area-first species reference feature. `Detail/` owns the public species page, UUID-first readable share action, reference gallery, and authenticated Community sightings preview/paginated grid. `Catalog/Models` owns normalized browse selections/page requests, overview presentation policy, country flags, and the typed category route; `Catalog/Services` alone resolves the live dictionary endpoint, cached image loader, geocoder, and MapKit snapshotter; generation-fenced `Catalog/ViewModels` own catalog, overview, and region-map state; its three thin root Views plus grouped Components retain search, refresh, navigation, and rendering without direct networking. Selection changes fence initial and pagination work before search debounce, including reverted and failed replacement identities. Core Network retains Codable wire DTOs and transport, while Explore Shell owns Identify/Index selection and the shared navigation stack. Mirrored Catalog tests enforce those boundaries and a 600-line production-file ceiling. Index is the sole dictionary browser; taxonomy remains catalog/detail metadata and has no separate route. External UUID and UUID-plus-slug links enter through the shared deep-link parser and `CaptureWorkspaceViewModel`, then select Explore Identify/Index before opening this detail in its stack.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Onboarding         | `apps/ios/Merian/Features/Onboarding/`                                         | Product-area-first permission and consent flow. `Shell/Services` alone resolves live settings, consent, telemetry, queue recovery, and animation policy; its state owner sequences Welcome → Camera → Location → Ready and fences duplicate or late step completions. `Steps/` owns copy, layout, UI-only state, shared chrome, and the Ready Models/ViewModel/Components projection without native permission calls. `Permissions/` owns the AVFoundation adapter and one-shot `@MainActor` Core Location delegate, which re-enters the actor before reading authorization state from a nonisolated callback. `MerianApp` injects its selected app-scoped managers and keeps completed users outside the shell while required account evidence is unresolved; only a resolved absence routes them directly to Ready. Mirrored feature tests enforce the ownership boundary, callback-isolation order, and 600-line ceiling, while Core Security owns consent ledger, restoration, authority, lifecycle, and reapproval tests.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

Within Species Dictionary Detail, platform-neutral `Models/` own request, state,
share, presentation, telemetry, and hero-edge policy; `Services/` alone resolve
the dictionary and Community endpoints, telemetry, haptics, entitlement,
fallback Explore state, and Field Chat state; and generation-fenced
`ViewModels/` own page and Community loading. The standalone shell and shared
content View retain navigation, presentation, scroll, and lifecycle timing.
Grouped `Components/{Community,Content,Gallery,Loading,Shared}` render without
direct networking. Mirrored Detail tests enforce stale-completion fencing,
endpoint adaptation, ownership boundaries, and a 600-line production-file
ceiling; Core Network retains wire DTOs and transport.

`SpeciesDictionary/Shared/Models` owns the route and entry-point values,
taxonomy bridge, and reference-image labels/attribution used across Catalog,
Detail, Explore, and Field Trips. Core Network separately owns canonical
UUID/name normalization, exact schema/response-identity validation, transport,
and the bounded memory cache. The backend generated
`species_dictionary.is_public_biological` value is authoritative before catalog
keysets and overview/country aggregation. Mirrored Shared architecture tests
keep that folder platform-neutral and free of networking.

Within Insights Sharing, `Models` owns platform-neutral Share copy and action
projection; `Services` alone resolves publication, Community, detail,
share-state, cache, event, and feedback effects; `ViewModels` owns the focused
root-state extensions, contained reconciliation clocks, and observable Community
request draft; and `Views` plus `Components` retain rendering and UI-only
timing. Sharing views/components contain no networking, the former
Explore-sharing aggregate and nested Community view path are absent, and every
production Sharing Swift file stays below the 600-line review guard.

Within Insights Content, `Models` owns fact data, custom-tag validation,
queued-retry copy, and queued phrase/rotation policy; `Services` alone resolves
preferred-name persistence, ordered and account-bound Supabase tag
synchronization, queue scheduling/mutation, durable queue snapshots, app events,
and haptic feedback; and `ViewModels` owns fact-deck, tag-transaction, queued
retry, name-preference, and Content action state. `Views` retains lifecycle
tasks, bindings, selection, animation, and Debug fixture timing; grouped
`Components` renders cards, Field-trip progress, header, queue recovery,
scanning, and tags without direct networking.
`Core/UI/Components/NamePickerSheet.swift` is the cross-feature display-only
name chooser. Mirrored tests under `MerianTests/Features/Insights/Content` lock
these boundaries, rollback and effect ordering, ordered tag synchronization,
queue request identity, legacy-owner removal, and the 600-line production-file
ceiling.

Within Species Reference, platform-neutral `Models` own observation and heatmap
presentation policy; `Services` alone resolve the local SwiftData projection,
public observation endpoint, GBIF/Wikipedia sessions, bounded image loading,
haptics, and habitat enrichment; and generation-fenced `ViewModels` publish
observation, heatmap, and fallback-image state. `Views` owns the chart
composition and task identity, while domain-grouped `Components` retain
rendering, map gestures, gallery scrolling, retry timing, and other UI-only
state. Empty or replacement identities invalidate older work, pre-cancelled
valid loads do not claim a generation, and the chart owner clears cross-species
values without blanking a same-species refresh. Mirrored tests under
`MerianTests/Features/SpeciesReference` enforce these boundaries, checked
feature sendability, removal of the former `Cards`/`Utilities` owners, and the
600-line production-file ceiling.

Within Insights Media, `Carousel/Models` owns platform-neutral selection, focus,
image-origin, and availability policy. Its `CarouselSelectionCandidate` contract
prevents the policy layer from depending on SwiftUI-backed page values.
`Builders` owns page assembly and transient availability; `Services` adds
Insight telemetry and feedback naming to the Core playback dependency; and
`Playback` owns only inline-video state plus the stable pause coordinator. Root
carousel views, `Pages`, and `Components` retain Insight-only selection, focus,
animation, and mounted inline state without networking or direct singleton
resolution. Media export maps scan state to Core requests in a session-fenced
view-model extension. Mirrored tests under `MerianTests/Features/Insights/Media`
lock those boundaries and the 600-line production-file ceiling. The image
renderer shared by Insights, Explore, Field Trips, and Species Dictionary is
`Core/UI/Components/AsyncLocalImageView.swift`; its live `LocalImageLoader`
resolution belongs to `Core/UI/Services/AsyncLocalImageDependencies.swift`. The
domain-neutral native pager, page identity and gallery values, zoom host,
pagination dots, top scroll-edge treatment, fullscreen gallery, audio page, and
reusable video chrome live in `Core/UI/Components/MediaCarousel`; feature-owned
page values project their own stable controller-reuse keys into that boundary.
Equal ID/reuse keys preserve a mounted controller; a sequence or key change
invalidates the native data-source cache before the selected page is
reinstalled. `Core/Media/MediaExportService.swift` owns bounded export and share
preparation for both Insight and Scans.

Within Capture, Scan's contained task owner generation-fences still shutters,
video admission/start, recording, and progress work. Shell invalidates pending
visual generations across scene, mode, presentation, teardown, and reset
transitions while preserving graceful stop-and-stage behavior for an active
video. `CameraPreviewView` consumes the environment-injected `CameraManager` as
its single session and zoom owner; it does not resolve the singleton.

Within the Scans row, `ScanQueueState.isManualRetryEligible` is the canonical
grid/Insight value-level retry baseline; mutation owners still re-fetch and
revalidate the durable row. Cross-feature `ScanThumbnail` delegates media work
to `Core/UI/Services/ScanThumbnailLoader.swift`. That service
cancellation-fences shared cache work, while the view's typed task identity
includes every source/policy input that can require a replacement load. Scans
Shared's live grid-feedback and deletion-presentation adapters remain main-actor
owned.

The long-term ownership and extension contract for the Capture/Explore goal seam
is recorded in
[`docs/rfcs/active-capture-goal-context.md`](rfcs/active-capture-goal-context.md).

Within Capture Shell, `Models/` owns deterministic media and presentation
policy, `Services/` is the only Shell owner that constructs live clients,
sessions, remote-media/prewarm work, share/account lookup, keyboard platform,
and feedback adapters, and `ViewModels/` owns the root state plus routing,
imports, staging, refinement, and lifecycle orchestration. The keyboard service
owns the raw UIKit notification publishers and actions; the mounted modifier
only binds them to SwiftUI presentation state. An encapsulated operation-state
owner keeps task handles, one-shot routes, import coalescing, timeout fences,
and crop ordering in private storage. `Views/`, grouped `Components/`, and
`Modifiers/` retain UI-only pager, focus, expansion, presentation, and dismissal
timing without direct endpoint calls. Mirrored tests under
`apps/ios/MerianTests/Features/Capture/Shell/` lock these boundaries,
raw-notification confinement, deterministic Models, and the folder's 600-line
production-file ceiling. The composing-center SwiftUI environment contract lives
in `Capture/Shared/Utilities` because Shell supplies it and Record consumes it.
The immutable `SendableCGImage` wrapper lives in `Core/Media` because Capture
and Insights both use it across concurrency boundaries.

Within Capture Staging, `Models/` owns only the ephemeral `StagedCapture`,
capacity policy, modality wrappers, UIKit-backed image bundle, and the one
chronological `StagedCaptureNode` sequence. `Views/` owns crop/description
presentation timing without endpoint or persistence calls. Shell owns mutation,
required-crop and automatic-submit fences, and disposable-file deletion.
Submission owns `CaptureSubmissionMediaTimeline`, the aligned
`CaptureSubmissionMediaProjection`, and hand-written `Identify*` request/replay
descriptors; Core AI, network, database, and offline queue code consume those
stable values. `ActiveScanToolbar` filters the canonical staged order for
renderable video covers without a second sort. Mirrored Staging, Shell,
Submission, and Core Utilities suites own state, presentation, wire/replay, and
connectivity-policy assertions respectively.

Within Insight Shell, `Models/` owns deterministic presentation identities,
binding keys, and display projections; `Services/` owns the sole live network,
authentication, repository, routing, feature-access, badge, and feedback
resolution boundary; `ViewModels/` owns scan-bound state plus focused lifecycle,
record, capability, media, content, and presentation projections; and `Views/`,
`Components/`, and `Modifiers/` retain composition, navigation, presentation,
focus, scrolling, animation, and dismissal timing. `InsightContentPresentation`
and `InsightShellPresentation` are the two typed modal slots.
`InsightSheetViewModel+MediaPresentation.swift` and
`+PresentationIdentity.swift` own the former display aggregate's media and
identity seams; `InsightSheetView+Content.swift` owns root content/toast
routing, not Field-trip domain policy. Shell views and view models issue no
endpoint calls. Mirrored Shell, Content, FieldNotes, Media, and Sharing suites
enforce these boundaries, removal of both aggregate files, and the 600-line
ceiling for production files. The optional dependency parameter defaults to
`.live`, and queued completion polling is subject-, generation-, and
cancellation-fenced.

Within Insight Field Notes, `Models/` owns platform-neutral prompt, edit,
visibility-request, and feedback values; `Services/` alone adapts the Core
repository, shared speech manager, Explore visibility action, and haptic
feedback; `ViewModels/` owns editor state plus scan/generation-fenced mutations
on the Shell root; `Views/` owns composition, focus, dismissal, and autosave
task timing; and `Components/Card/` plus `Components/Editor/` own render-only
leaves. `FieldNotesRepository` remains in `Core/Utilities` as the shared
SwiftData and legacy-bridge reconciliation boundary. Mirrored Field Notes tests
own edit, visibility, identity, and architecture coverage plus stable-baseline,
overlap, ownership, and automatic-termination dictation fences; repository tests
live under `Core/Utilities`, while Share-cache refresh tests live under
`Insights/Sharing`. The former component and root-level test aggregates are
retired, and every production Field Notes Swift file stays below 600 lines.

Within Capture Record, feature files own only immutable presentation, narrow
manager/haptic projection, UI-only artwork and scrubbing state, and mounted
rendering. Core Hardware owns `AudioCaptureManager`, its initializer-injected
engine/session dependencies, the shared startup/resume/DSP/countdown generation
fence, `SpectrogramActor`, and `AudioSessionCoordinator`. The coordinator
publishes one-shot lease ownership only after activation succeeds; mode,
background, reset, pause, and replacement invalidate pending manager work before
it can start an engine or publish into a newer Capture state. Mirrored Core
Hardware tests lock duplicate-resume coalescing, late-completion rejection,
transition invalidation, successful lease replacement, failed-activation
configuration restoration, rollback-failure invalidation, and first-activation
cleanup.

Within Capture Submission, `Models/` owns deterministic admission, media,
goal-preference, and latency policy plus normalized payload and sendable
environment-context values. `Services/` owns live admission/context composition,
telemetry formatting, the actor-backed 150 ms context race, and the sole
`/update-scan-context` adapter. That adapter commits late context to the durable
queue before remote delivery and performs at most one remote retry after 500 ms;
endpoint, transport, and task cancellation are terminal. Submission cancels
captured context work whenever no foreground attempt will consume it. Only a
timeout-losing accepted attempt keeps a late-enrichment task, which retains the
injected service and bounded telemetry inputs rather than the workspace view
model or full display-image collection. Responsibility-specific `ViewModels/`
extensions orchestrate visual, nonvisual, Describe, admission, and presentation
state without issuing endpoint calls. Submission has no view layer; Shell and
modality views retain UI-only timing. Mirrored tests under
`apps/ios/MerianTests/Features/Capture/Submission/` lock policy, context-race,
cancellation, retry, dependency, and architecture behavior, including the
600-line production-file ceiling.

Scan media workers propagate structured cancellation into detached work and
lease newly created WAV/compressed-playback files until staging accepts them.
This keeps timeout-losing and otherwise unconsumed artifacts inside the Scan
service owner instead of leaving cleanup to views or process lifetime.

## Public Web App

The public web frontend lives in `apps/web/` and is intentionally separate from
the native iOS source tree.

| Area                       | Current files                                                                                                                                                                               | Responsibility                                                                                                                                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App shell                  | `apps/web/app/layout.tsx`, `apps/web/app/theme.ts`, `apps/web/app/globals.css`                                                                                                              | Mantine provider, global metadata defaults, theme, pre-hydration color-scheme bridge, and responsive page chrome.                                                                                                                            |
| Marketing/home placeholder | `apps/web/app/page.tsx`, `apps/web/lib/exploreMedia.ts`                                                                                                                                     | Lightweight landing surface with a public Explore grid that keeps visual heroes and uses species reference thumbnails for audio posts.                                                                                                       |
| Explore share page         | `apps/web/app/explore/post/[postId]/page.tsx`, `apps/web/components/ExploreMediaCarousel.tsx`, `apps/web/components/ExploreBoostedAudio.tsx`                                                | Server-rendered public post page with square ordered media, looping muted video, spectrogram-backed audio, optional local Boost Audio, metadata, and support reporting.                                                                      |
| Species share page         | `apps/web/app/species/[speciesId]/page.tsx`, `apps/web/app/species/[speciesId]/[slug]/page.tsx`, `apps/web/lib/species.ts`                                                                  | Server-rendered UUID-first readable Species Dictionary page with UUID-only/stale-slug redirects, strict versioned Edge mapping, rights-filtered reference imagery/metadata, native CTA, and textual lookalike navigation.                    |
| Web audio boost stream     | `apps/web/app/api/explore/audio/route.ts`, `apps/web/lib/audioProxy.ts`                                                                                                                     | Range-capable same-origin WAV stream restricted to public Naturebook media on the durable `media.merian.app` technical host; used only when a visitor activates browser-local Boost Audio.                                                   |
| Public beta waitlist       | `apps/web/app/api/waitlist/route.ts`, `apps/web/components/WaitlistForm.tsx`, `apps/web/lib/boundedJson.ts`, `apps/web/lib/waitlistSecurity.ts`                                             | 4 KiB streamed JSON boundary, conservative email normalization, explicit Turnstile widget/Siteverify flow, trusted-proxy daily IP HMAC, distributed pre-provider rate claim, stable request IDs, and service-only atomic database insertion. |
| Policy/support pages       | `apps/web/app/privacy/`, `apps/web/app/privacy-choices/`, `apps/web/app/terms/`, `apps/web/app/guidelines/`, `apps/web/app/support/`, `apps/web/app/legal/`                                 | App Store-friendly public policy, data-choice, community, support, and legal hub pages.                                                                                                                                                      |
| Legal/public components    | `apps/web/components/PublicPageShell.tsx`, `apps/web/components/LegalPage.tsx`, `apps/web/components/ThemePreferenceBridge.tsx`, `apps/web/lib/site.ts`, `apps/web/lib/theme-preference.ts` | Shared public page chrome, legal document layout, iOS-to-Mantine theme preference sync, support email/site URL config.                                                                                                                       |
| Supabase access            | `apps/web/lib/supabaseAdmin.ts`, `apps/web/lib/supabasePublic.ts`, `apps/web/lib/explore.ts`, `apps/web/lib/species.ts`                                                                     | Explicit `server-only` server-key client used only through scoped Explore/waitlist RPCs, separated from the anonymous Species Dictionary projection client, plus strict wire mapping.                                                        |
| Web response security      | `apps/web/proxy.ts`, `apps/web/app/layout.tsx`, `apps/web/lib/securityHeaders.ts`                                                                                                           | Per-request nonce CSP, nonce-bound bootstrap script, production HSTS, and explicit browser defense headers.                                                                                                                                  |
| Universal Links            | `apps/web/app/apple-app-site-association/route.ts`, `apps/web/lib/appleAppSiteAssociation.ts`, `apps/web/lib/canonicalHost.ts`, `apps/web/proxy.ts`                                         | Exact Explore/species AASA paths, direct legacy-host AASA exception, and canonical alias redirects constructed by assigning untrusted pathname/search onto fixed `CANONICAL_ORIGIN`.                                                         |
| Formatting helpers         | `apps/web/lib/formatting.ts`                                                                                                                                                                | Shared Naturebook web copy and URL formatting.                                                                                                                                                                                               |
| Local setup and CI         | `apps/web/README.md`, `apps/web/.env.example`, `apps/web/package.json`, `apps/web/lib/dependencySecurity.test.ts`, `.github/workflows/web-quality.yml`                                      | Web setup, waitlist secret/ingress contract, transitive security overrides, frozen dependency audit, tests, typecheck, and production build.                                                                                                 |

## Core Modules

| Core area      | Current files                              | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| AI             | `apps/ios/Merian/Core/AI/`                 | `InferenceEngine`, edge DTOs, parse/save actor, on-device viewfinder intelligence, and `LocalVisualAnalysis` protocols/policies for bounded Vision classification, deterministic pixel-derived traits, progressive phrases, and future Foundation visual cues.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Analytics      | `apps/ios/Merian/Core/Analytics/`          | Optional, consent-gated PostHog facade and SDK lifecycle, advisory usage quota, and gamification notification manager. The current production-consent candidate remains release-blocked.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Media          | `apps/ios/Merian/Core/Media/`              | Shared bounded local-media processing, including `InferenceAudioPreparer`, adaptive audio boost, spectrogram raster/layout policy, normalized seeking, immutable `SendableCGImage` transport, exact-token `MediaPlaybackObservation`, main-actor audio delegate/session restoration, initializer-injected playback effects, and actor-owned media save/share preparation. `MediaExportService` accepts Sendable local/approved-remote requests, processes batches sequentially, and is shared by Insight and Scans.                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Data/Database  | `apps/ios/Merian/Core/Data/Database/`      | `BackgroundDatabaseActor`, `FileIOActor`, `ScanRepository`, and `HistoricalDatabaseActor`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Data/Images    | `apps/ios/Merian/Core/Data/Images/`        | File-backed still-image preparation, the durable `ExternalImageImportStore` Photos inbox and EXIF extractor, archive rescue, media-aware add-only photo/video PhotoKit writes, gallery thumbnail access, RAM caching, request coalescing, cancellation-aware bounded local/remote ImageIO decoding, and immutable reference-thumbnail backfill inputs plus actor-owned public-reference recovery.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Offline sync   | `apps/ios/Merian/Core/Data/OfflineSync/`   | Durable queue state machine, generation-fenced upload/inference URLSession ownership, exact server-issued staging-key handoff, consumed-key re-upload recovery, a persisted `failed_retryable` dispatch latch and fresh-context retry accounting, compare-before-clear retry/probe registries, background replay and reconciliation, audio queue helpers, and tokenized sync phase state. Scan-analysis retries use a five-second minimum, jittered exponential growth, a 30-second ordinary local maximum, and ten automatic attempts; server-directed minimums remain authoritative, while maintenance keeps its 15-minute maximum.                                                                                                                                                                                                                                                                                                            |
| Store recovery | `apps/ios/Merian/Core/Data/StoreRecovery/` | SwiftData store metadata parsing, source-aware migration hints, duplicate-checksum detection, corruption-gated quarantine, legacy migration rescue archives, safe-mode decision support, and sanitized recovery manifests.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Hardware       | `apps/ios/Merian/Core/Hardware/`           | Camera, environment context, cross-feature speech, generation-fenced bioacoustic recording/review playback, one-shot token-aware audio-session coordination, spectrogram DSP and ambient-noise classification, haptics, thermal/battery orchestration, and push token management. Audio capture receives maximum-duration feedback through AppDI instead of resolving the haptic singleton.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Network        | `apps/ios/Merian/Core/Network/`            | Supabase auth/client facade and generation-bound transition coordinator, protocol-3 stable purchase-principal prepare/claim/cancel journal orchestration, legacy sign-out purchase handoff, Sign in with Apple authorization-code/Vault registration and subject-bound credential-state revalidation, strict account-deletion receipts, TLS-pinned network client, subject-bound Insight/Explore Field Chat DTO validation, private Field trip completion-scan DTO mapping, Explore DTOs, species dictionary/observation-stats DTOs, and Keychain manager.                                                                                                                                                                                                                                                                                                                                                                                       |
| Security       | `apps/ios/Merian/Core/Security/`           | Circuit breaker; device identity; `PurchasePrincipalResolver`; serialized, binding-generation-fenced RevenueCat identity/readiness; current-launch versioned complimentary entitlement; bounded/no-retry caller-scoped scan-admission preview with typed queue-only connectivity fallback; append-only versioned adult/Terms/Gemini/PostHog consent ledger and sync; fail-closed restoration with account/generation-fenced automatic and explicit retry; causal provider append with stale-grant rejection and deny-wins revocation rebasing; all-version provider-head authorization; atomic verified ledger-file storage; Keychain withdrawal journal; and social guard. The canonical purchase-identity target is [`purchase-principal-auth-separation.md`](./rfcs/purchase-principal-auth-separation.md); the canonical consent hold is [`production-consent-readiness-2026-08-03.md`](./legal/production-consent-readiness-2026-08-03.md). |
| UI             | `apps/ios/Merian/Core/UI/`                 | Shared controls, tab bar, media mode toggle, render-only cards/feedback/model-tier presentation, audio spectrogram, cross-feature scan thumbnails and empty states, goal progress, and a domain-neutral media carousel package containing pager, gallery, audio playback, and reusable video chrome. Live image loading and other effects remain behind injected services/dependencies; feature owners retain navigation, source policy, entitlement lookup, telemetry, and presentation lifetime.                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Utilities      | `apps/ios/Merian/Core/Utilities/`          | App lifecycle, the typed loss-tolerant `AppEventPublisher`, bounded delivery-critical `AppRouteCoordinator`, framework-to-main-actor publisher bridge, config constants, field notes repository, image downsampling, errors, sharing, date/size and trim-to-non-empty helpers, and UserDefaults keys.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

`Core/Media/MediaExportService.swift` is the shared Insight/Scans export
boundary. Its private actor processes Sendable requests sequentially, keeps
remote previews file-backed, and uses an ephemeral, cookie-free session that
accepts only exact-host HTTPS `media.merian.app`, refuses cross-host redirects,
and revalidates final response URLs. Single-share images are bounded to 2,048
px; Scans batch-share images use 1,024 px under the existing 20-selection cap.

## SwiftData Actors

| Actor                                  | File                                                                                            | Lifecycle                                                                                                                                                                                                                                                 |
| -------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BackgroundDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift`                              | Ad-hoc for live writes/enrichment/collections; long-lived through `OfflineQueueManager.resolvedQueueDbActor(container:)` for timestamp-fenced upload/inference queue transitions, redundant scan/job retry-authority reconciliation, and orphan recovery. |
| `HistoricalDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/ScanRepository.swift`                                       | Ad-hoc per historical sync, streaming one cloud page at a time.                                                                                                                                                                                           |
| `ProfileDatabaseActor`                 | `apps/ios/Merian/Features/Profile/UserProfile/Services/ProfileDatabaseActor.swift`              | Ad-hoc behind `ProfileTabDependencies` for Profile render calculations; container-identity-cached via `OfflineQueueManager.resolvedProfileDbActor(container:)` with a fresh projection for every post-inference award evaluation.                         |
| `SpeciesObservationStatsDatabaseActor` | `apps/ios/Merian/Features/SpeciesReference/Services/SpeciesObservationStatsDatabaseActor.swift` | Ad-hoc behind `SpeciesObservationStatsDependencies` for each species chart load; filtered/projection SwiftData fetches local observation overlays, then delegates bucketing to `Features/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`.   |
| `SearchDatabaseActor`                  | `apps/ios/Merian/Features/Scans/Library/Services/ScanLibrarySearchActors.swift`                 | Ad-hoc for incremental search payload extraction from stable scan IDs; full rebuilds use value snapshots and do not perform a second SwiftData fetch.                                                                                                     |
| `FileIOActor`                          | `apps/ios/Merian/Core/Data/Database/FileIOActor.swift`                                          | Singleton actor for image/audio file writes, deletes, and path validation.                                                                                                                                                                                |

The Scans library's advanced filtering worker is intentionally not a SwiftData
actor. `Features/Scans/Library/Models/ScanLibraryFilterIndex.swift` accepts only
`Sendable` projections extracted by `ScansLibrarySearchCoordinator`; it caches
option dimensions and performs normalized matching off-main without owning a
`ModelContext`. Full text-payload and posting-index construction also remains in
the coordinator's cancellation-aware detached worker. `ScansManager` remains the
UI-facing selection, filter-input, action-feedback, and event-subscription
owner; the coordinator owns targeted reindexing. Live export, Explore
publication, share-state, app-event, and haptic adapters are isolated to
`Features/Scans/Library/Services/ScansLibraryDependencies.swift`; Library views
perform no endpoint or singleton lookup. Every production Library file remains
below 600 lines.

The Scans root follows the same boundary. `ScansShellDataStore` owns fresh
SwiftData projections, `ScansThumbnailPipeline` owns loader/repair/backfill
integration, and `ScansShellViewModel` owns queue and Explore-media incident
state through its narrow auth/endpoint/event/time/badge dependency value.
Service-specific live adapters stay with their data-store and thumbnail owners.
`ScansSheetView` retains only navigation and presentation timing and performs no
direct endpoint, Supabase, app-container, loader, or actor lookup. Every
production Shell file remains below 600 lines.

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

Shared identify helpers under `services/supabase/functions/_shared/identify/`
own cross-route contracts for the executable model/final wire descriptor,
generated provider schema, thresholds, cache hydration, database writes, media
resolution, moderation, latency-oriented database RPCs, and subject
classification. `_shared/identify/contract.ts` generates the Vision/Describe
schemas plus the provider-private audio variant, runtime-validates provider and
complete server-enriched responses, and infers their TypeScript types.
`_shared/identify/googleSchema.ts` is the typed seam from that dependency-free
projection into the pinned Google SDK schema.
`_shared/identify/audioSubjectPolicy.ts` owns the shared audio-only
non-human-over-Human precedence and consumes its provider-private discriminator
before either audio route assembles the unchanged public Identify payload.
`services/supabase/scripts/validate_edge_dtos.ts` imports that same executable
descriptor and deterministically generates the marked Identify DTO block in iOS
`InferenceEdgeDTOs.swift`, including nested types, arrays, numeric
representations, coding keys, and explicit decoders. The gate compares the
checked-in block exactly and checks exclusive generated DTO ownership across the
complete `apps/ios` source graph. Its focused tests, third-party-free Deno
config, and frozen lock exercise stale generation, aliased decoder extensions,
missing source roots, and runtime numeric bounds.
`_shared/capturedMediaContract.ts` independently owns the durable
`public.scans.captured_media` outer-key/`_0` union. Its focused
`validate_captured_media_dtos.ts` generator owns
`Core/Data/Database/CapturedMediaWireDTOs.swift`; Identify provider-schema
projection does not consume this JSONB compatibility union. Strict V1 validates
every nonempty new write, while compatible reads accept historical aliases,
description timestamps, device-local references, nested video audio, and empty
manifests before canonical rewrites discard retired/device-only fields. Current
scan-ingestion intent schema v3 likewise persists description contexts as
text-only `freeText`; schema-v2 replay remains readable and is normalized before
any new durable write. `scanIngestionJobs.ts` owns the atomic ingestion-setup
call and strict RPC response validation; `latencyDb.ts` owns dictionary
hydration. `completedResponse.ts` owns owner-scoped stored/reconstructed success
replay and bounded concurrent-request coalescing across all four scan-producing
routes. `subjectClassification.ts` is the processed-material boundary: visual
and describe routes call it before biological gates so manufactured or processed
objects cannot enter `species_dictionary` through one route while another blocks
them.

`services/supabase/functions/_shared/scanRecovery.ts` is the shared
compatibility owner-row repair boundary used by `check-scan-status` and
`share-scan-to-explore`. It validates only bounded non-media fields, derives
identity and public privacy projection server-side, checks the owner-scoped
ingestion job, and performs a duplicate-safe write. Both callers reload by scan
and authenticated owner before proceeding. iOS builds the matching payload in
`MerianNetworkClient.swift`; Field Chat preflights it from
`InsightSheetView+Toolbar.swift`, while `ExploreErrorFormatter.swift` translates
technical share failures into customer-facing retry guidance.

`services/supabase/functions/_shared/aiQuota.ts`, `_shared/groupTagQuota.ts`,
`_shared/entitlement.ts`, `_shared/complimentaryScans.ts`, migrations
`20260723160229_enforce_server_ai_quotas.sql` and
`20260802235833_three_complimentary_pro_scans.sql`,
`20260803181936_add_reservation_safe_entitlement_protocol.sql`, plus
`scripts/cutover_complimentary_entitlements.sql`, own the cross-route
paid-provider and complimentary-result boundary. Identification, audio,
cache-miss enrichment, model chat, and Explore/Community share-or-edit audio
moderation reserve a database operation with a stable UUID before dispatch. The
shared moderation helper refuses live provider work when a transitive caller
omits that quota boundary. The migration owns durable entitlement versioning,
policy/model selection, UTC-day and user/IP counters, ten-minute fenced
reservation leases, charged failed-retry state, automatic stale refund, and
API-role privilege revocations. Coverage lives in
`_tests/aiQuotaCoverage.test.ts`, `_tests/aiQuotaMigrationContract.test.ts`, and
`tests/ai_quota_security.sql`. The complimentary extension adds one fixed
three-scan private lifetime ledger, original-analysis linkage, server-derived
Flash fallback, protocol 3, user-first completion/terminal settlement fences,
paid preservation, Ghost merge cap, and admin aggregates. iOS adds a serialized
account/scan funding reservation, durable release marker, conservative legacy
blockers, one bulk owner-scoped funding-state read, entitlement-refresh-fenced
terminal settlement, and persisted deferred paid/complimentary/Flash
reclassification. Coverage lives in
`_tests/complimentaryProScansMigrationContract.test.ts`,
`_tests/complimentaryScansConcurrencyDb.test.ts`, and
`tests/complimentary_pro_scans_security.sql`; the normative contract is
`docs/backend-and-data/18-complimentary-pro-scans.md`.

`services/supabase/functions/sync-collections/` and migrations
`20260803180211_harden_collection_ownership_and_memberships.sql` plus
`20260803215309_fix_collection_owner_upsert_ordinality.sql` and
`20260803215310_grant_collection_sync_invoker_privileges.sql`, then
`20260804002819_fix_collection_membership_conflict_ambiguity.sql`, own custom
collection reconciliation. One invoker RPC atomically accepts new/same-owner
collection IDs without reparenting foreign collisions; a second joins both
membership parents to that owner. The forward repairs use valid PostgreSQL
ordinality syntax, grant only the invoker operations required for sync, and use
the composite primary-key constraint to avoid PL/pgSQL output-variable
ambiguity; collection ownership remains column-update protected. Accepted IDs
alone feed composite-key hydration and the O(N) delta. A trigger, split
authenticated RLS, explicit service-only RPC ACLs, and mutable-column-only
`service_role` UPDATE protect direct database paths. Source coverage is
route-local plus `_tests/collectionOwnershipMigrationContract.test.ts`;
fresh-catalog coverage is `tests/collection_ownership_security.sql`.

Supabase project credential boundaries:

- `services/supabase/functions/_shared/publishableKey.ts` resolves hosted named
  publishable keys and the temporary complete legacy anon fallback for
  user-scoped clients.
- `services/supabase/functions/_shared/serviceRoleAuth.ts` owns strict
  server-key source classification, exact internal request matching, and
  format-aware standard headers. Hosted deploys add the non-reserved
  `MERIAN_SUPABASE_SERVER_API_KEY` synchronization fallback without changing
  inbound transport. Inbound matching isolates independently valid sources while
  unmatched malformed configuration still fails closed.
- `services/supabase/functions/_shared/serviceRoleClient.ts` is the only
  privileged SDK factory and removes only an exact inherited opaque-key Bearer
  fallback while preserving real user JWTs.
- `services/supabase/scripts/resolve_project_api_keys.ts` performs bounded,
  reveal-explicit Management API resolution for positive and real public-key
  negative smoke controls.
- `services/supabase/scripts/verify_edge_secret_digest.ts` compares the
  synchronized secret's stored SHA-256 digest with the exact selected key
  without logging either value. The deploy workflow requires this after
  synchronization and before Function deployment, then uses bounded
  propagation-aware positive smoke retries. The canonical matrix and exit gate
  are in
  `docs/backend-and-data/13-server-credentials-and-database-release-safety.md`.

Privileged database routine execution:

- `services/supabase/migrations/20260723144640_harden_privileged_routine_execution.sql`
  owns the deny-by-default public-definer ACL catalog, fixed empty search paths,
  owner-safe defaults, and caller-check requirement.
- `services/supabase/migrations/20260727010340_fix_service_role_authorization_guard.sql`
  keeps the service-only in-function check compatible with legacy JWT keys and
  PostgREST role impersonation for opaque server keys without changing grants.
- `services/supabase/migrations/20260727013416_future_proof_server_key_boundaries.sql`
  adds the private key-format-aware `pg_net` header policy, migrates installed
  HTTP routines and persisted cron commands, and repairs mixed user/service
  dispatch in the owner media-incident routine.
- `services/supabase/migrations/20260727183356_restore_identity_first_media_incident_guard.sql`
  restores identity-first mixed routine dispatch after a later migration
  accidentally reintroduced the JWT-only branch.
- `services/supabase/migrations/20260727190637_secure_explore_comment_reactions_and_defaults.sql`
  enables the last missing public-table RLS boundary, restricts reaction-table
  grants to the Edge admin client, and revokes unsafe global/schema future table
  and sequence defaults.
- `services/supabase/migrations/20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql`
  catalogs owned user foreign keys, reuses only valid/ready leading indexes,
  creates bounded small indexes, and requires supervised construction for large
  or partitioned relations.
- `services/supabase/functions/_tests/privilegedRoutineMigrationContract.test.ts`,
  `services/supabase/functions/_tests/serverApiKeyBoundaryMigrationContract.test.ts`,
  `services/supabase/functions/_tests/publicSchemaSecurityMigrationContract.test.ts`,
  `services/supabase/tests/privileged_routine_security.sql`, and
  `services/supabase/tests/public_schema_security.sql`, plus
  `services/supabase/scripts/audit_privileged_routine_acl.ts` provide static,
  disposable-catalog, and production read-only enforcement respectively.

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
- `get-explore-species-posts` — authenticated, exact-species Community sightings
  cards with image-quality cursor ordering
- `get-explore-comments`
- `get-explore-comment-replies`
- `get-explore-mention-suggestions`
- `explore-post-chat` — private per-viewer Pro Field Chat grounded only in the
  public privacy-filtered post projection
- `field-trips`
- `report-explore-comment`
- `report-explore-post` — authenticated Explore post-content moderation queue
  used by feed, post-detail, and Community-detail **Report post** actions;
  separate from scan identification review
- `flag-issue` — backward-compatible JWT-authorized identification-dispute
  ingress; owner submissions atomically write `flagged_reviews` and mark the
  scan for review, while the exact old Community post-report signature is routed
  to `explore_post_reports` without changing scan review state
  (`services/supabase/migrations/20260831120000_submit_owned_flag_issue_atomically.sql`
  and
  `services/supabase/migrations/20260901032158_repair_owned_flag_issue_insert_detection.sql`
  plus the matching Deno contract and
  `services/supabase/tests/flag_issue_submission_security.sql` lock the database
  boundary)
- `toggle-explore-comment-reaction`

Explore community identification:

- `request-community-identification`
- `get-community-identification-feed`
- `get-community-identification-activity`
- `get-community-identification-detail`
- `update-community-identification-request`
- `search-community-taxa`
- `submit-community-identification`
- `withdraw-community-identification`
- `restore-community-identification`
- `submit-community-feedback`

The root iOS contract is Observations / Field trips / Identify. Identify owns
Requests/Index. Its `Models/` define presentation and route values, `Services/`
adapts live network/identity/event dependencies, `ViewModels/` owns dashboard,
pagination, detail, search, and feedback state, and `Views/` plus grouped
`Components/` render without direct networking. The feature boundary is
documented in `apps/ios/Merian/Features/Explore/Identify/README.md`. Index
reuses `Features/SpeciesDictionary/Catalog/`; that product area owns the typed
category route and normalized browse-selection policy, Services-only
endpoint/image/map adapters, selection- and generation-fenced
catalog/overview/map state, and render-only root views and grouped components.
Explore Shell still owns the shared navigation stack and Identify/Index
selection. The Activity route's service adapter lives in
`services/supabase/functions/get-community-identification-activity/`, while
`20260731050009_add_community_identification_activity.sql` owns its internal
projection, triggers, shared request classifier, service-only RPC, and current
generation backfill.
`20260731063804_index_community_identification_activity_actor_user_fk.sql` owns
the actor-to-user reverse FK index used by deletion and identity maintenance.
`20260801145720_use_usernames_for_community_identification_activity.sql` owns
public-username attribution in the Activity read RPC. Index is the sole Species
Dictionary browser; taxonomy remains reference metadata and has no separate
route or feature directory.

The Explore root is organized under `apps/ios/Merian/Features/Explore/Shell/`:
`Models/` owns root-mode and initial-route policy plus the typed notification
destination, open token, and preparation outcome; `Services/` alone resolves the
live app-event stream and root Scans-library request plus narrow haptic actions;
`ViewModels/` owns latest-wins notification post preparation, token-checked
success/failure commits, and the one-time staged-to-pending dismiss handoff;
`Views/` owns the shared `NavigationPath`, root selection, destination
registration, lifecycle modifiers, sheet occupancy, and playback coordinator;
and `Components/` owns the segmented picker and bell. Shell views contain no
endpoint or singleton lookup, and every production Shell file remains below 600
lines. Field-trip route values consumed across Explore, Profile, Feed, Author
Profile, and Insights live with their product owner under
`Explore/FieldTrips/Models/FieldTripRoutes.swift`.

Observations Map is organized under `apps/ios/Merian/Features/Explore/Map/`:
`Models/` owns focus/request values, presentation, camera, filtering, and region
policy, plus its bounded in-memory cache; `Services/` is the only Map layer with
a live `MerianNetworkClient` closure; `ViewModels/` owns spatial
load/filter/selection state; and `Views/` plus grouped `Components/` own
camera/gesture timing and rendering. Its focused presentation and state tests
mirror that owner under `apps/ios/MerianTests/Features/Explore/Map/`; wire
decoding and payload tests remain under `MerianTests/Core/Network/`.

Observations Feed is organized under `apps/ios/Merian/Features/Explore/Feed/`:
`Models/` owns routes, composer values, and presentation policy; `Services/`
owns live feed/comment/interaction, post-detail, composer-image,
identity/entitlement, and notification-realtime adapters; `ViewModels/` owns
catalog, post-store, comments, hashtag pagination, and post-detail state; and
`Views/` plus grouped
`Components/{Cards,Catalog,Comments,Composer,Detail,DetailCards,Media,Shared}`
render without direct networking. Focus, scroll proxies, typed sheet occupancy,
and delayed presentation work remain view-local. Feed production files stay at
or below the pass's 600-line review guard.

Explore activity is organized under
`apps/ios/Merian/Features/Explore/Notifications/`: `Models/` owns decoded
notification values, stable row presentation, and notification reply routes;
`Services/` alone resolves live catalog/read, comment/reply, viewer-context,
telemetry, and error dependencies; `ViewModels/` owns generation-fenced catalog
and reply-thread loading/pagination state; and `Views/` plus grouped
`Components/` render without direct networking or singleton lookup. The Shell
notification coordinator owns the latest-open token, token-checked preparation
outcome commit, and separated staged and pending dismiss destinations, while
Feed keeps `ExploreNotificationReplyThreadTarget` inside `ExplorePostRoute`.
Failed catalog refresh preserves the last successful cursor, and a server reply
found after bounded notification fallback insertion replaces that fallback in
place.

The cross-area public-media renderer, player bridge, hero image, indicators,
playback extensions/state/policies/coordinator, and narrow loader adapters live
under `apps/ios/Merian/Features/Explore/Shared/Media/`. The domain-neutral Pro
badge lives under `Core/UI/Components/`; reusable spectrogram loading lives
under `Core/Media/`; and secure comment-avatar fallback shared by Feed and
Notifications lives under `Explore/Shared/Models/`. Shell coordinates navigation
but Feed owns its tab, hashtag, detail, and typed route declarations.
Playback-policy/state tests mirror Shared/Media; Feed, Notifications, and Shared
presentation/state tests mirror their production owners; the cross-surface
audio-boost suite remains under `MerianTests/Features/Explore/`.

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

`services/supabase/functions/_shared/fieldChatResponse.ts` owns the additive
success-envelope identity shared by `insight-chat`, `explore-post-chat`, and
`species-dictionary-chat`. Every empty/populated thread and action success
echoes its requested scan, post, or species UUID as `subject_id`; iOS validates
that echo plus populated message/conversation identity before applying candidate
success. The same helper binds each assistant to its canonical send UUID in
private metadata, derives its deterministic UUIDv8 row identity, and boundedly
coalesces in-flight quota/transport replays; both response messages project that
UUID so iOS can require one complete pair and manual retry can preserve the
original request. New sends reserve both rows inside the 30-row cap, and
conflicting text reuse fails explicitly. Route-local prompt builders keep
Insight model output and deterministic Explore labels within the shared
three-prompt, 120-character safety contract.

`services/supabase/functions/_shared/fieldChatReservation.ts` owns the
fail-closed adapter to `20260729163616_reserve_field_chat_sends_atomically.sql`.
That migration serializes per-user cross-table daily accounting before
per-conversation capacity admission, inserts the exact subject-bound user row
atomically, blocks a second unanswered UUID in that conversation, and revokes
direct browser-role chat-table access. Its narrow stale-quota routine can reopen
only a ten-minute-stale exact request whose user row exists and assistant is
absent; the subsequent provider attempt is newly metered.
`20260730180000_bind_field_chat_rows_to_subjects.sql` then makes retained
Insight conversations structurally match their exact scan owners and makes
conversation/scan-or-post/user and copied-feedback identity structural through
validated deferred composite foreign keys. It cleans only impossible historical
private bindings, independently binds conversation-optional feature feedback to
its exact scan owner, and closes the remaining direct Insight-feedback Data API
surface. `20260821030027_add_species_dictionary_field_chat.sql` adds the
Edge-only Dictionary conversation, message, and feedback tables; subject type
`species_dictionary`; operation `species_dictionary_chat_reply`; three-family
daily admission and stale recovery; and anonymous-account merge support. Each
Dictionary send reloads only the bounded public reference projection and treats
its text as untrusted data. Community sightings, observation charts, scans,
notes, people, locations, media, URLs, and attribution identities never enter
that prompt. `20260824210544_preserve_field_chat_daily_usage.sql` adds the
content-free user/day admission aggregate, service-only read RPC, atomic
counter-backed reservation/conversation creation, and conservative Ghost-merge
coalescing. It registers the effective handler, asserts registry coverage, and
short-locks all three conversation/message families to remove historical
message-less threads. It blocks novel sends through the next database-observed
UTC boundary and until explicit activation, permanently reserves conversation
insertion for the atomic RPC, and keeps exact persisted replays available. Any
unverifiable usage or cutover read fails closed. Source fixtures exercise all
three production reservation/delete paths and the full current-day merge race;
they require non-skipped disposable-database execution before release.

iOS now allowlists `species-dictionary-chat` for exact-key ambiguous replay, and
runtime handler-core tests exercise action/ownership/recovery. The database
boundary prevents quota denial from creating an empty conversation. After all
three selected bundles deploy, a one-way service-only activation records the
candidate, migration, and all three content-addressed route digests after the
live marker/digest probes match. Database `ready` force-selects the full fleet
after the migration becomes the deployment baseline. Swift and Deno execute
`docs/contracts/species-dictionary-prompt-label-policy.json`, including U+2013
EN DASH, U+0085 normalization, and U+FEFF rejection. The handler suite executes
the actual wrapper with deterministic accepted/refused authenticators; hosted
real-token authentication remains an evidence gap. The checked-in
`species_dictionary_chat_production_hold` blocks Supabase production until
controls execute without database skips, same-SHA hosted gates, the real
released-binary V49→V50 install-over, and canonical external evidence pass. Its
source verifier requires the named ID; after a reviewed inactive change, the
exact-SHA-checked mutation job also requires a protected clearance structurally
bound to the manifest and criterion artifacts. The verifier downloads and
recomputes those artifacts, validates exact-SHA runs and payloads, and checks
live branch/environment protections.

Data lifecycle, identity, and exports:

- `sync-collections`
- `merge-ghost-profile` — uses a source-issued, provider-bound proof to
  atomically merge guest data before purging the anonymous Auth shell. Its
  pending schema-aware hardening must execute source-controlled ownership
  policies, verify derived scan state, and schedule permanent provider repair.
- `reconcile-ghost-profile-merges` — scheduled service-role worker that leases
  committed merge receipts and retries obsolete anonymous Auth deletion.
- `resolve-purchase-principal` — authenticated, additive stable-purchase
  identity boundary. Ordinary resolution hashes a device-only installation
  capability and uses a monotonic binding intent to resolve one immutable
  server-owned RevenueCat customer. Protocol 3 adds source-authenticated
  sign-out reservation, exact fresh-anonymous claim, and source-only
  cancellation on the same route. Prepared rows block generic binding writes,
  and terminal intent fences reject resolver completions begun before
  preparation. The route never accepts an Auth UUID, principal ID, or provider
  ID from the body and never performs a provider transfer.
- `transfer-signout-purchases` — legacy-mode StoreKit-only compatibility
  handoff. It binds one fresh anonymous UUID, requires RevenueCat receipt sync
  plus server verification, and leaves account promotions on the linked source.
  Retain it throughout the supported old-client and rollback window.
- `safe-delete` — authenticated intake plus immediate processing for the durable
  `pending → storage_pending → auth_pending → completed` account-deletion state
  machine; retained scans become account-detached ownerless scientific
  tombstones that preserve exact coordinates and other scientific facts, all
  canonical R2 prefixes receive a cursor-persisted sweep and delayed empty
  verification pass, a stored Apple credential is revoked and destroyed, and
  only then may Auth be deleted. Legacy Apple identities return a durable manual
  fallback disposition that supporting clients persist; fallback delivery to
  older binaries remains release-gated. The SQL storage claim requires the
  matching cleaned-up `storage_pending` private job and vetoes live profiles or
  owned scans. See the
  [canonical scientific-retention contract](./backend-and-data/17-scientific-observation-retention.md).
- `register-apple-revocation-token` — authenticated one-use Apple code exchange,
  identity-subject binding, Vault refresh-token persistence, token-free
  response-loss idempotency, and compensating revocation after persistence
  failure. See the
  [canonical Apple deletion contract](./backend-and-data/20-sign-in-with-apple-account-deletion.md).
- `reconcile-account-deletions` — scheduled service-role worker that leases and
  resumes incomplete relational, storage, Apple provider, and Auth deletion work
  without accepting caller-selected user IDs. Aggregate
  queue/lease/configuration health is exposed only through
  `get_account_deletion_health()` and consumed by
  `services/supabase/scripts/monitor_account_deletion_health.ts` plus the
  independent `.github/workflows/account-deletion-health-monitor.yml` schedule.
- `repair-scan-image` — owner-authenticated R2 inspection and missing-image
  repair; promotes one surviving staging image and atomically replaces its exact
  URL across active scan, captured-media, normalized-media, and matching
  owner-post Explore metadata.
- `delete-scan` — owner-authenticated fast path that durably fences a scan UUID
  before deleting canonical and derived R2 media, then removes the owner row
  only after storage confirms deletion.
- `auto-purge-nonbio` — service-only daily retention intake that
  generation-locks and revalidates expired non-biological rows, writes permanent
  scan-deletion fences, and delegates all R2 and row erasure to the independent
  reaper.
- `reconcile-scan-deletions` — service-only deadline-draining reaper for
  interrupted scan erasure; leases private jobs, compare-before-releases
  failures, and emits aggregate oldest-pending/backlog/expired-lease health.
- `submit-feedback-survey`
- `request-export-dwca` — deployed tombstone-compatible permanent-account
  boundary; while the launch gate is off its atomic service-only request RPC
  returns `disabled`, and global exports remain internal-only.
- `export-dwca` — currently disabled service-authenticated resumable worker;
  `_shared/dwcaReleaseState.ts` reads the canonical database gate and `db.ts`
  owns canonical phase claims, immutable job-membership/revision validation,
  full-member privacy fences before final side effects, claim-bound 100-row/256
  KiB keyset access, durable cursors/manifests, and row/byte budgets;
  `archive.ts` owns fixed-capacity incremental CSV encoding while `crc32.ts`
  calculates bounded chunk checksums and composes full-entry CRCs algebraically;
  `zip.ts` owns manifest-sized archive streaming without a per-archive-byte
  checksum loop; `storage.ts` owns claim-fenced CSV chunks and R2 multipart
  upload plus short read-only signing; `downloadGrant.ts` owns 256-bit
  application capability generation; `pseudonym.ts` owns versioned export HMACs;
  `worker.ts` performs one preparation, assembly, or delivery phase per claim
  and revalidates after every delivery suspension; and `drain.ts` owns
  sequential deadline/step bounds, oldest-due waves, failure suppression, and
  aggregate queue-health classification. Independent production continuation and
  archive-deletion alerting lives in `scripts/monitor_dwca_export_queue.ts` and
  `.github/workflows/dwca-export-health-monitor.yml`, so absent cron/Vault
  configuration cannot silence both workers and monitoring.
- `download-dwca` — public opaque-capability GET boundary; while the launch gate
  is off it returns `410` before signing storage. When enabled it applies a
  distributed address limit and full-source privacy fence on every click before
  issuing a no-store R2 read redirect valid for at most 30 seconds.
- `reconcile-dwca-archive-cleanup` — scheduled service worker that
  deadline-drains UUID-leased archive-deletion outbox rows, durably backs off
  storage failures, purges retained completed snapshots, and emits aggregate
  oldest-due/backlog/expired-lease health.
- `revenuecat-webhook` — verifies the configured bearer credential and
  RevenueCat raw-body HMAC, parses bounded event identities, fetches
  authoritative CustomerInfo, and commits idempotent per-user state through
  service-only database RPCs. Route-local `handler.ts`, `protocol.ts`,
  `signature.ts`, `subscriber.ts`, and `db.ts` keep those boundaries
  independently testable.
- `reconcile-revenuecat-subscribers` — scheduled service-role repair worker that
  deadline-drains small durable queue leases and applies newer authoritative
  CustomerInfo snapshots when webhook delivery is missed; `db.ts` also owns the
  service-only backlog-health read used by
  `services/supabase/scripts/monitor_revenuecat_reconciliation.ts` and its
  scheduled GitHub monitor.
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
- `reconcile-scan-deletions`
- `reconcile-dwca-archive-cleanup`

Every function above has a `[functions.<name>]` entry in
`services/supabase/config.toml`. `merge-ghost-profile` and `request-export-dwca`
intentionally use `verify_jwt = true`. App-facing routes with a documented
custom identity policy may set `false` and authenticate inside shared handler
code; service-role workers such as `reconcile-ghost-profile-merges` set `false`
for `pg_net` reachability and enforce an exact constant-time match through
standard format-aware transport: current opaque keys use `apikey` only, while a
legacy service-role JWT uses matching `apikey` and Bearer values. Each function
also has a generated local `deno.json` backed by `functions/dependencies.lock`.
The dependency/deploy control plane lives in
`services/supabase/scripts/function_dependency_tools.ts`,
`sync_function_deno_configs.ts`, `validate_function_dependencies.ts`,
`plan_function_deploy.ts`, and `deploy_function_batches.sh`; CI uses that graph
to type-check deploy-time configs and select transitive runtime consumers. The
discovery-based `test_supabase_tooling.sh` runner type-checks every standard
TypeScript script, runs every `*_test.ts`, exercises the isolated DTO validator,
and syntax-checks/tests shell tooling without a hand-maintained test list. The
shared `validate_migration_contracts.sh` runner discovers every
`*Migration*.test.ts` and `migration*.test.ts` source contract for both the
local Make target and production deploy before database replay. The inventory
above is descriptive rather than a second source of truth:
`function_dependency_tools_test.ts` requires exact name-for-name parity between
`config.toml` and discoverable function graphs without hard-coding a fleet size.

## Supabase Media Projections

Legacy owner-row recovery uses both a private rollout timestamp and the
immutable exact `failed_scan_ingestions` ID snapshot captured by
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql`. Snapshot
membership is mandatory: a producer insert blocked behind migration DDL cannot
gain historical recovery authority from its earlier transaction-start timestamp.

| Surface                                       | Current files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scan ingestion jobs and intents               | `services/supabase/migrations/20260705120000_add_scan_ingestion_jobs.sql`, `services/supabase/migrations/20260705130000_extend_scan_ingestion_jobs_media_manifest.sql`, `services/supabase/migrations/20260705140000_add_scan_ingestion_intents.sql`, `services/supabase/migrations/20260705150000_schedule_scan_ingestion_replay.sql`, `services/supabase/migrations/20260707143157_cap_scan_ingestion_replay_attempts.sql`, `services/supabase/migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql`, `services/supabase/migrations/20260728220000_persist_idempotent_scan_responses.sql`, `services/supabase/migrations/20260729012153_fix_video_scan_canonical_finalization.sql`, `services/supabase/functions/_shared/scanIngestionJobs.ts`, `services/supabase/functions/_shared/scanIngestionIntents.ts`, `services/supabase/functions/_shared/scanIngestionCompatibility.ts`, `services/supabase/functions/_shared/scanIngestionRetry.ts`, `services/supabase/functions/_shared/identify/completedResponse.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/replay-scan-ingestion/`, `services/supabase/functions/_tests/scanMediaIngestionContract.test.ts`, `services/supabase/functions/_tests/dwcaDownloadAndScanFinalizationMigrationContract.test.ts` | Durable server-side state ledger, sanitized replay intent, and scheduled replay dispatcher for accepted scan ingestion attempts. One shared helper supplies the deterministic 30-second ordinary `failed_retryable` deadline to all four scan producers without overriding explicit server-directed values. Claim creation and compatibility recovery share a per-scan database generation lock. The multimodal path updates job state through inference, media promotion, scan insert, and failure; completion is written last by one transaction that proves every claimed staging-key disposition and ready canonical media row and stores the validated success envelope. Canonical projection follows structured captured media or the legacy standalone-image/playback/audio timeline, never treating video inference frames as standalone display rows. Claims include upload-session ids and a normalized media-manifest checksum so retries can be tied back to the exact media shape. Compatibility scan-producing endpoints write the same ledger before returning success, with staged image/audio and text-only intents shaped for multimodal replay. A repeated request first replays a stored completion or reconstructs an exact durable owner row as marked `200`, never calling the provider twice; reconstructed replay may retain a retryable canonical ledger. The paired intent row stores telemetry/descriptors/staged keys without raw media bytes, marking inline-media requests as non-resumable. The replay worker claims due resumable staged media/audio/video or text-only jobs and re-invokes the multimodal path with the same `client_scan_id`, capped at 10 server replay claims before structured `replay_exhausted`; status polling keeps `found` / `not_found` compatibility while exposing optional job details for retry and ops visibility. The contract matrix locks these guarantees across image, audio, text-only, video, status, repair, recovery, and Explore-share seams.                     |
| Captured Media Wire V1                        | `services/supabase/functions/_shared/capturedMediaContract.ts`, `services/supabase/scripts/validate_captured_media_dtos.ts`, `services/supabase/scripts/validate_captured_media_dtos_test.ts`, `apps/ios/Merian/Core/Data/Database/CapturedMediaWireDTOs.swift`, `apps/ios/Merian/Core/Data/Database/ScanRepository.swift`, `services/supabase/functions/identify-multimodal/capturedMedia.ts`, `services/supabase/functions/share-scan-to-explore/db.ts`, `services/supabase/functions/reconcile-scan-media-assets/worker.ts`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Executable contract and generated PostgREST boundary for the owner-visible mixed-media timeline. New nonempty writes are strict, bounded, credential-free HTTPS V1 with text-only descriptions; compatible reads tolerate historical aliases, timestamps, nested video audio, `localFile`, and `[]`, while canonical rewrites discard retired/device-only data and store `null` when nothing durable remains. Historical iOS sync decodes rows independently, quarantines malformed rows without poisoning a page, advances pagination by raw remote row count, and classifies a targeted malformed cloud-complete row as an immediate no-redispatch contract mismatch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Scan admission preview                        | `services/supabase/migrations/20260809155517_add_scan_admission_preview.sql`, `apps/ios/Merian/Core/Security/ScanAdmissionManager.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionDependencies.swift`, `apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+SubmissionAdmission.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Caller-scoped read-only paid → complimentary → Flash UX preflight. iOS uses an isolated two-second, no-wait/no-cache/no-retry transport. Only classified connectivity failure plus current local eligibility selects queue-only; malformed/authentication/TLS/server failures stay blocked. No preview reserves quota, and durable replay still requires authoritative `reserve_ai_quota(...)`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Identification latency and deferred context   | `services/supabase/migrations/20260715153946_reduce_identification_latency_round_trips.sql`, `services/supabase/functions/_shared/identify/latencyDb.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/update-scan-context/`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionEnvironmentContextGrace.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionDeferredContextService.swift`, `apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Keeps the durable queue/auth gates while shortening the non-model critical path. One service-role RPC claims ingestion and records its sanitized intent before Gemini; eligible biological results use at most one RPC to hydrate cached primary/candidate dictionary data afterward. All current modalities share the durable server success fence. The eligible live-camera still path additionally gives weather/geocoding 150 ms, avoids simultaneous inline/background uploads, commits late context locally before the one-retry `/update-scan-context` adapter patches it through the staged-context table/trigger, and never invokes a second identification request; gallery, audio-bearing, and video submissions retain their existing client submission behavior while participating in the same server durability boundary. Diagnostic headers and structured metrics cover tap-to-render without exposing scan/user/species/location identifiers. Model selection and all generation settings remain unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Owner-row durability and compatibility repair | `services/supabase/functions/_shared/identify/db.ts`, `services/supabase/functions/_shared/scanPersistence.ts`, `services/supabase/functions/_shared/scanRecovery.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/share-scan-to-explore/`, `services/supabase/migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql`, `services/supabase/migrations/20260729173000_recover_media_abandoned_owned_scans.sql`, `services/supabase/migrations/20260729200000_harden_media_abandoned_scan_recovery_proof.sql`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/Merian/Core/Utilities/ExploreErrorFormatter.swift`, `apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+Toolbar.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Makes every scan-producer HTTP success contingent on moderation, required media promotion, primary species resolution, duplicate-safe scan creation, and owner-scoped read-back. A fresh provider-owning multimodal success additionally requires complete-last canonical-media finalization. Its later same-UUID request may return a marked reconstructed replay from the exact owner row while canonical repair remains retryable, without another provider call. Compatibility producers attempt finalization synchronously; only a post-row failure may leave a retryable ledger while returning the validated owner-row response immediately. A returned write rejection permits quota/media cleanup only after an exact-owner read proves absence; lost or unreadable responses preserve committed quota and promoted objects until same-UUID recovery. Older/interrupted missing rows can be repaired only from bounded non-media local state after an atomic database decision defers to active/retryable ingestion and permits exact structured `replay_exhausted`, or exact `media_reconciliation_abandoned` with composite service proof: a post-result dead letter no earlier than the latest charged normal/replay inference reservation, producer-generation-appropriate evidence, no active reservation or invalid timestamp lineage, and no moderation-rejected or moderation-pipeline-failed capture row. A private rollout cutoff bounds legacy unstructured proof; modern proof binds exact quota identity, validated provider output, and completed safety evaluation. Current/later policy, unproven abandonment, unknown, and arbitrary terminal reasons fail closed. Explore can combine repair with owner-staged media and applies the same proven-absence rule to restoration updates; Ask the Community repairs through status first; Field Chat repairs non-media state before presentation. Technical errors are translated into retryable customer-facing messages without granting direct scan writes to iOS. |
| Scan media assets                             | `services/supabase/migrations/20260705100000_add_scan_media_assets.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711143348_repair_scan_media_assets_audio_constraints.sql`, `services/supabase/migrations/20260711171512_backfill_missing_ready_audio_assets.sql`, `services/supabase/functions/_shared/scanMediaAssets.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/reconcile-scan-media-assets/`, `services/supabase/functions/scan-media-health/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Normalized image/video/audio lifecycle. Standalone audio is promoted into `audio_storage_urls`, `captured_media`, and ready owner-scoped audio assets; extracted video audio remains inference-only. The explicit constraint repair upgrades early production tables that `CREATE TABLE IF NOT EXISTS` could not reshape, and the follow-up refresh migration makes audio part of the canonical RPC and backfills durable recordings that lack normalized rows. Repair and health paths retain their existing staged-media responsibilities.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Owned scan image recovery                     | `services/supabase/migrations/20260726041109_fence_storage_erasure_claims.sql`, `services/supabase/migrations/20260726041338_repair_owned_scan_image_references.sql`, `services/supabase/functions/repair-scan-image/`, `apps/ios/Merian/Core/Data/Images/LocalImageLoader.swift`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Prevents stale storage outbox rows from authorizing live-account prefix erasure, reconnects strongly evidenced Documents files to missing durable URLs, renders recovered files locally, and restores verified-missing cloud references through owner-scoped staging promotion plus one atomic metadata transaction. Production deployment and recovered-object coverage remain independently verifiable states.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Explore post media                            | `services/supabase/migrations/20260703130000_add_explore_post_media.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711055524_add_explore_audio_moderation_attestations.sql`, `services/supabase/functions/_shared/explorePostMedia.ts`, `services/supabase/functions/_shared/exploreComposerMedia.ts`, `services/supabase/functions/_shared/audioModeration.ts`, `services/supabase/functions/_shared/audioSpectrogram.ts`, `services/supabase/functions/share-scan-to-explore/`, `services/supabase/functions/request-community-identification/`, `services/supabase/functions/update-explore-field-notes/`, `services/supabase/functions/backfill-explore-audio-spectrograms/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Post-owned image/video/audio snapshots. Audible media must have a matching content-addressed attestation or pass the dedicated Gemini speech/non-speech classifier under the authoritative quota boundary before share, Community-request, or edit replacement; changed bytes, model, or policy contract force re-moderation. Approved WAV audio gets a deterministic persisted spectrogram poster shared by web and normalized media; a bounded service-role repair worker fills historical blanks while unsupported legacy codecs keep playback and the icon fallback. Legacy local audio can be repaired through owner-scoped staging into `audio_storage_urls`, canonical `captured_media`, and normalized assets before the same gate runs. Failed attempts create no pending/public media state; maps, widgets, profile grids, and compact previews remain thumbnail-first.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Explore media health                          | `services/supabase/migrations/20260726144647_add_explore_media_quarantine_lifecycle.sql`, `services/supabase/migrations/20260726144754_implement_explore_media_quarantine_state_machine.sql`, `services/supabase/migrations/20260726174555_align_explore_author_publication_contract.sql`, `services/supabase/functions/reconcile-explore-media-health/`, `services/supabase/functions/get-explore-media-incidents/`, `services/supabase/functions/ingest-r2-media-events/`, `docs/backend-and-data/12-explore-media-health-and-quarantine.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Direct signed R2-origin checks confirm unexpected primary-object loss only after two spaced `404` responses. Public projections omit confirmed-missing items and reversibly quarantine all-missing posts while preserving author intent and engagement. Profile count/preview/grid visibility is canonical; owner recovery totals and service-wide aggregate scope remain separate. Owner incidents, repair-triggered restoration, audit runs, optional event acceleration, and read-only verifier credentials are one compatibility contract.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Explore owner share-state parity              | `services/supabase/migrations/20260729120000_align_explore_share_state_media_health.sql`, `services/supabase/functions/get-scan-explore-share-state/`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Keeps owner-only publication identity available for media repair while deriving `is_explore_feed_visible` from the same moderation, aggregate quarantine, usable-item, tombstone, species, shadow-ban, and Community-publication boundaries as canonical Explore projections. The client requires exact scan identity and coherent UUID/time/privacy topology before changing its optimistic cache, and accepts a legitimately hidden post without inventing a Community request or visible destination.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

The July 28 incident extensions to these surfaces are
`20260728230000_recover_inline_scan_ingestion_completions.sql`,
`20260728231000_make_staged_scan_media_registration_idempotent.sql`,
`20260728232000_ensure_scan_user_profile.sql`,
`20260728233000_recover_identity_merge_interrupted_scans.sql`, and
`20260729012153_fix_video_scan_canonical_finalization.sql`. Together with
`generate-upload-urls/assetRegistration.ts`,
`share-scan-to-explore/restoredMediaValidation.ts`, and the four scan producers,
they exclude phantom inline sources, serialize signing retry, enforce the
Auth-backed profile prerequisite, fence in-flight identity merge, retain
standalone audio, project video media without standalone inference frames, and
owner-scope Explore restoration.

The normative joined behavior, success boundary, recovery order, deployment
unit, and verification matrix are maintained in
[`16-scan-ingestion-reliability-and-recovery.md`](backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

## Internal admin surface

- `apps/admin/`: isolated Next.js + Mantine SSR admin for
  `admin.naturebook.earth`, with Google OAuth, TOTP AAL2, role-aware navigation,
  strict response headers, CSRF/origin-checked Server Actions, and no
  service-role key. Its dependency-security tests and
  `.github/workflows/admin-quality.yml` enforce a frozen install, reviewed
  Next.js/PostCSS/Sharp floors, blocking dependency audit, tests, type-check,
  and production build for every pull request and affected `main` changes.
  Repository rules must require the resulting status, and the separate Vercel
  project must use it as a required Deployment Check before domain promotion.
- `services/supabase/migrations/20260719161112_add_internal_admin_foundation.sql`:
  internal membership/session/audit/review/feedback/pricing schema, narrow admin
  RPCs, reversible post moderation, and canonical AI usage ledger.
- `apps/admin/app/(admin)/complimentary-entitlements/` and migration
  `20260802235833_three_complimentary_pro_scans.sql`: analyst-only aggregate
  balances, hold age, settlement reasons, Flash fallback, exhaustion, and paid
  conversion with no per-user ledger browser surface.
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
  cross-field trip order and wraparound, completion advancement,
  account-isolated caching, stale-data retention, exact artwork mapping, typed
  destinations, and focused Explore routing, plus private completed-scan ID
  decoding for item-specific catalog/detail thumbnails.
- Core AI, network, security, hardware, analytics, utilities, and data actors.
- Typed event delivery and route priority/FIFO, coalescing, expiry, overflow,
  account/session fencing, occupied-presentation deferral, exact dismissal,
  missing-target rejection, framework main-actor hops, and detached-player
  callback suppression.
- `MerianTests/Support/SharedProcessStateTestTrait.swift` provides
  resource-keyed cross-suite exclusion for temporary
  network-client/request-interceptor overrides and application-route-coordinator
  ownership. Suite-local `.serialized` remains complementary and does not
  replace this gate.
- Scan-media recovery filename safety, rescue-store alignment, constrained
  timestamp grouping, authenticated cloud inspection/repair DTOs, and one-device
  local fallback behavior.
- Camera-roll automatic opt-out, photo/video PhotoKit resource selection,
  source-video retention, image GPS scrubbing, local/approved-cloud media export
  payloads, exact-host rejection, and media-aware result copy.
- Profile achievements, heatmap/stats, Explore, Species Dictionary, species
  observation stats, Messages sharing, Insights, Scans, and onboarding view
  models.

UI tests live under `apps/ios/MerianUITests/` and include launch coverage plus
seeded flows in `MerianApp.swift` through `UITestSeedCoordinator`. The
progressive-analyzing regression opens the normal foreground Insight, advances
generic → Vision category → validated image trait only after explicit badge
taps, and verifies the native badge accessibility frame after each opacity-only
label change. The live-to-queue regression proves an open analyzing sheet binds
its exact image-backed durable row without presenting a synthetic error. It also
locks the same selected carousel page and animation-session token across the
handoff, keeps the pending analysis overlay and badge mounted, and exercises the
queued delete confirmation after its toolbar action fades in.

The queued-audio handoff regression opens a staged tile, asserts embedded Back
navigation, the shared scanning status badge and `Did you know?` card, then
verifies the same audio page remains available before and after the completed
result replaces the queued presentation. The seed writes a valid Documents PCM
WAV, and the smoke requires its decoded playback control on both sides of the
handoff rather than accepting a filename-only page. There is no timer-driven
replacement: after every queued-state assertion passes, the smoke taps the
shared status badge to request the exact app-private Debug fixture handoff. The
fixture saves through the open Insight sheet's exact environment `ModelContext`
and directly calls the existing production queue-promotion method with that same
context; the library event remains only for parent-list refresh. Release retains
no-op coordinators. The exact-SHA hosted iOS gate executes all four
deterministic analyzing, live-to-queue, queued-retry, and queued-completion
regressions after the complete unit target; the remaining UI tests are compiled
but retain their feature-specific runtime gates.

Deno tests live under `services/supabase/functions/_tests/` plus function-local
`*.test.ts` files. Run from `services/supabase/functions` with:

```bash
deno task test
```

Stable purchase-identity coverage spans the resolver's protocol/DB/handler
tests, `_tests/purchasePrincipalMigrationContract.test.ts`, the disposable
`_tests/purchasePrincipalCompatibilityConcurrencyDb.test.ts` and
`_tests/purchasePrincipalSignoutRotationConcurrencyDb.test.ts` schedules, and
`tests/purchase_principal_security.sql`. The protocol-3 concurrency fixture
proves prepared-resolver exclusion, claim/cancel serialization, expiry recovery,
and terminal binding-intent fences; it must execute against a disposable
database for release and a connection-refused self-skip is not a pass. iOS
source/unit and physical-device evidence owns the complementary write-ahead
journal, exact fresh-anonymous claim, unrelated-session rejection,
RevenueCat/entitlement gate, and relaunch behavior.

Fleet-wide ingress coverage lives in `_shared/http_test.ts`,
`_tests/edgeHandler.test.ts`, `_tests/jsonEndpointSecurityCoverage.test.ts`, and
`_tests/jsonEndpointSecurityMigrationContract.test.ts`. The executable
`services/supabase/tests/waitlist_security.sql` fixture verifies the waitlist
RPC's ACL, constraints, duplicate behavior, and transactional rate ceilings. Web
parser, email, proxy, HMAC, and Turnstile behavior is covered by
`apps/web/lib/*.test.ts`.

Field trip Deno/database coverage includes the tier-specific evidence gate,
pending preferred-goal retention, weak-match confirmation, completed-progress
downgrade reconciliation, receipt replay, matching specificity, and private RPC
ACLs, plus the starter-level catalog and deny-by-default Backyard enrollment
trigger/backfill, in `_tests/fieldTripsMigrationContract.test.ts` and
`_tests/fieldTripProgressDb.test.ts`.

Consent causal coverage spans `_tests/legalConsentMigrationContract.test.ts`,
`_tests/legalConsentConcurrencyDb.test.ts`, `tests/legal_consent_security.sql`,
and the iOS `ConsentManager`/ `SupabaseManager` suites. Static contracts lock
RPC shape, privileges, indexes, and account-row-before-stream lock order. The
disposable-database fixture releases overlapping grant and revocation calls for
both Gemini and PostHog and requires a revoked final head with monotonic
revisions in either order. The pgTAP upgrade fixture additionally submits
prior-disclosure revocations with their stale observed parents after
current-version grants, then verifies both RPCs rebase the accepted parent and
every consumer keeps the revoked all-version head authoritative.

Missing-image repair coverage spans
`repair-scan-image/{validation,worker}_test.ts`,
`_tests/{accountDeletionMigrationContract,migrationMediaContract}.test.ts`,
`tests/{account_deletion_security,scan_image_repair_security}.sql`, and the iOS
`LocalImageLoaderTests`/`MerianNetworkClientTests`.

App privacy assurance spans source, generated project, archive, and export.
`scripts/check-ios-project-resources.sh` validates the source manifest and
requires exactly one Merian Resources membership. The current-SHA archive
requires `Merian.app/PrivacyInfo.xcprivacy` and records
`privacy_manifest_valid: true`; `scripts/validate-ios-exported-ipa.sh` repeats
the root-path and exact-content checks for an Organizer export. The declaration
inventory and change contract live in
`docs/development-guides/16-ios-privacy-manifest.md`. Xcode's aggregate report,
App Store answers, and counsel approval remain operator evidence rather than
repository-generated facts.

App transport assurance spans configured origins, URL-construction boundaries,
source plist, archive, and export. `SecureTransportPolicy.swift` admits only
credential-free HTTPS for remote strings while preserving app-owned local files.
`scripts/validate-ios-transport-security.sh` rejects broad and domain-scoped ATS
exceptions plus insecure Supabase origins; the archive and IPA validators repeat
the check against the built `Info.plist`, and exact-SHA archive evidence records
`transport_security: "ats-default"`. The normative contract lives in
`docs/development-guides/17-ios-transport-security.md`.

## Documentation Maintenance Checklist

When changing the codebase, update docs in the same change if any of these move:

- `CurrentSchema`, schema model fields, or migration stages.
- App target deployment versions, entitlements, packages, or XcodeGen targets.
- Privacy manifests, required-reason API use, collected-data categories,
  purposes, identity linking, tracking, SDK composition, or executable bundle
  ownership.
- ATS exceptions, configured remote origins, signed URL handling, or any
  backend-supplied URL boundary.
- Edge Function request/response bodies, auth policy, config entries, or storage
  lifecycle behavior.
- Destructive queue claim authority, live-owner vetoes, account-isolation
  canaries, recovery coverage, or incident exit criteria.
- Capture modes, offline queue state transitions, media staging, or field-notes
  ownership.
- Camera-roll preference semantics, Photos permission level, media resource
  type, source-file ownership, approved export hosts, or temporary-file cleanup.
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
