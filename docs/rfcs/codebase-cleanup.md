# Codebase Cleanup Plan

> **Status: completed historical implementation record.** The cleanup round is
> closed. Do not append new normative refactoring policy here; use the current
> [Code Ownership and Refactoring guide](../development-guides/19-code-ownership-and-refactoring.md).
> Preserve the sequence and verification notes below as historical evidence.

This RFC defines the cleanup path for Merian after the public web share-page
work lands. The goal is easier navigation and safer future changes, not a broad
architecture rewrite.

## Principles

- Land product work before moving files. Refactors should not be mixed into
  feature commits unless the move is required for the feature.
- Keep behavior-preserving file splits separate from behavior changes.
- Prefer small, reviewable slices with one domain owner per slice.
- Move code toward the narrowest honest owner: feature code under
  `apps/ios/Merian/Features/<Feature>/`, shared app code under
  `apps/ios/Merian/Core/`, persistent models under `apps/ios/Merian/Models/`,
  public web code under `apps/web/`, and backend code under
  `services/supabase/`.
- Prefer product-area-first feature folders over broad type buckets. For large
  features, start with the user-facing surface (`Feed/`, `Map/`, `Identify/`,
  `Catalog/`, `Detail/`) and place that area's `Views`, `Components`,
  `ViewModels`, `Models`, and helpers inside it. Use `Shared/` only for code
  that is genuinely reused by more than one product area.
- Keep tests and docs aligned in the same change when public contracts, file
  ownership, or route shapes move.

## Phase 0: Commit Current Product Work

Before cleanup begins, land the current public web/legal work as its own commit.
That keeps the Next.js app scaffold, canonical `naturebook.earth` links,
legacy-domain compatibility, and policy pages reviewable without unrelated file
movement.

Expected verification:

```bash
cd apps/web && npm run typecheck && npm run build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

## Phase 1: Repo Hygiene And Boundaries

1. Keep generated artifacts ignored:
   - Xcode build output and derived data
   - Next.js `.next/`, cache, coverage, and hosting metadata
   - `node_modules/` and TypeScript incremental state
2. Document root ownership:
   - `apps/ios/Merian/`: native iOS source
   - `apps/web/`: public Next.js frontend
   - `services/supabase/`: migrations, Edge Functions, and backend tests
   - `docs/`: source-of-truth architecture and contract docs
3. Keep `docs/codebase-map.md` and this RFC updated when moving folders or
   changing ownership rules.

## Phase 2: Behavior-Preserving File Splits

Start with files whose size makes local reasoning expensive. Split by existing
responsibility, keep symbols internal/private where possible, and run the build
after each slice.

For Explore and Species Dictionary, keep the vertical product folders intact:

```text
apps/ios/Merian/Features/Explore/
  Shell/
  Feed/
  Map/
  Identify/
  Notifications/
  AuthorProfile/
  Shared/
  Widgets/

apps/ios/Merian/Features/SpeciesDictionary/
  Detail/
  Catalog/
  Shared/

apps/ios/Merian/Features/Scans/
  Shell/
  Library/
  Collections/
  NonBiological/
  Shared/

apps/ios/Merian/Features/Profile/
  Shell/
  UserProfile/
  Settings/
    Plan/
    Notifications/
    Changelog/
    Feedback/
  Shared/
```

When working on the Explore feed, start in `Explore/Feed/`; that folder owns the
observations feed, post cards, post detail, comments, hashtag presentation, feed
formatting, and feed view-model extensions. Map and Community ID logic should
not be placed there.

When working on the Scans private library, start in `Scans/Library/`; that
folder owns individual scan browsing, UI-facing Library state, contained
generation-fenced search/index work, injected export/publication adapters, and
fresh `QueuedScanContext` hydration. `Scans/Shell/` owns tab and navigation
composition, queue snapshot projection and polling, Explore-media incident
state, and thumbnail pipeline coordination. Completed and queued Insight
destinations are pushed by Shell in the existing Scans navigation stack; Library
emits route values and does not present its own sheet. Collection grids, smart
collections, collection detail/editing, mutation orchestration, and catalog
presentation belong in `Scans/Collections/`; the Scans Shell remains the owner
of the shared completed-library query and passes its record set into that
feature and `Scans/NonBiological/`. The latter derives its filtered projection
and owns correction, retention, and bulk-deletion presentation without mounting
another query. Cross-surface Scans-only UI belongs in `Scans/Shared/`, while
controls reused outside Scans, such as `ScanThumbnail`, `EmptyStateView`, and
`CategoryFilterBar`, belong in `Core/UI/`.

When working on the Profile tab, start in `Profile/UserProfile/`; that folder
owns identity, published scans, achievements, persona, terrarium, heatmap, and
the profile stats actor. Settings rows and account actions belong in
`Profile/Settings/`; plan/paywall surfaces live in `Profile/Settings/Plan/`,
push toggles in `Profile/Settings/Notifications/`, bundled release notes in
`Profile/Settings/Changelog/`, beta survey flows in
`Profile/Settings/Feedback/`, and cross-area profile state lives in
`Profile/Shared/`.

Suggested first targets:

| File                                                                                                                                               | Cleanup Direction                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/ios/Merian/Core/AI/InferenceEngine.swift`                                                                                                    | Integration audit and scoped safety fixes merged; user-confirmed GitHub Actions pass accepted as the baseline. Live visual/nonvisual execution, request/result adaptation, live media timeline/provider/carousel projection, live-attempt and durable-queue ownership, accepted-result completion effects, synchronous failure/queue-handoff coordination, cross-owner session and recovered-presentation transitions, identification-review action/effect/workflow/presentation mapping, species hydration/reference merging/scoped enrichment, hydration-presentation callback and write routing, synchronous historical-load startup, registered historical hydration orchestration, ephemeral presentation-lifecycle identity, stored observable presentation values, legacy lookalike-cache reset, bounded writes, reference transport, and local-analysis ownership are split.                                                                                                                                                                 |
| `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`                                                                                           | Complete for this hygiene round. Eighteen endpoint owners cover the extracted feature, inference, publication, lifecycle, collection-sync, enrichment, feedback/export, storage, and account-deletion operations. Stateless inference policy lives in `Inference/`; signed transfers and publication-media restoration live in `Media/`; owned-row recovery lives in `Recovery/`; route/error/replay policy, the request-scoped executor, the sole pinned session/TLS owner, and the per-attempt authenticated dispatcher live in `Transport/`. The client stays below the 600-line façade ceiling, injects those focused owners, and retains endpoint configuration, shared response/cache bridges, and capability-only account-deletion recovery transport.                                                                                                                                                                                                                                                                                        |
| `apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift`                                                                                            | Retired. `Core/Preferences/UserDefaultsKeys.swift` owns the exact unchanged defaults strings; focused Preferences owners retain typed settings, compatibility stores, verified accepted-account-deletion cache inventory, and post-persistence runtime reset. `Core/Data/SpeciesPreferences` owns durable preferred-name state and synchronization. `Core/Security/KeychainKeys.swift` owns exact secure-key strings, and `Core/Security/AccountDeletion/{Models,Stores}` owns deletion recovery phases, manual-provider notice state, secure proof storage, and pre-Auth barrier restoration. Mirrored suites freeze every installed key string, declaration and test ownership, local-only effects, compatibility behavior, and the 600-line ceiling.                                                                                                                                                                                                                                                                                              |
| `apps/ios/Merian/Core/Utilities/{ImageDownsampler,ImageFocusRegionDetector,SizeEstimator}.swift`                                                   | Retired. Shared stateless ImageIO downsampling lives in `Core/Data/Images`; Capture-only focus detection lives in `Features/Capture/Shared/Services`; and optional Capture telemetry size estimation lives in `Features/Capture/Submission/Services`. Mirrored suites and architecture guards freeze the new owners, retired paths, framework/effect boundaries, and 600-line ceilings.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `apps/ios/Merian/Core/Utilities/{ShimmerModifier,ShareSheetUtility}.swift`                                                                         | Retired. The retained cross-feature glow skeleton lives in `Core/UI/Components/Loading`; the sole main-actor UIKit activity-controller bridge is `Core/UI/Services/ShareSheetPresenter`; and the unused shimmer modifier/extension are removed. Core UI architecture coverage freezes sole ownership, retired paths, effect placement, and the existing visual and presentation contracts.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `apps/ios/Merian/Core/Utilities/ExploreErrorFormatter.swift`                                                                                       | Retired. The unchanged customer-safe mapping now lives in `Features/Explore/Shared/Models/ExploreErrorFormatter.swift`; its focused behavioral and ownership suites live in `MerianTests/Features/Explore/Shared`. The policy remains effect-free, callers retain task/retry/logging/presentation state, and the former Utilities source and mixed `MerianConfigTests` ownership are guarded against returning.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `apps/ios/Merian/Core/Utilities/FieldTripsAvailability.swift`                                                                                      | Retired. App-wide client-build flags and DEBUG-only overrides live in `Configuration/FeatureFlags.swift`; the Field Trips-only standard-outing sharing policy lives in `Features/Explore/FieldTrips/Models/FieldTripSharingAvailability.swift`. Focused tests mirror both owners and freeze the installed override keys, architecture coverage freezes the split, and the DwC-A launch contract follows the configuration source.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `apps/ios/Merian/Core/Utilities/MerianConfig.swift`                                                                                                | Retired. Its unrelated constants now have focused AI, Database, Images, OfflineSync, and Media policy owners. Exact values and helper semantics are preserved, the mixed test suite is split beside those owners, and a repository-wide architecture guard prevents the aggregate or duplicate declarations from returning.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `apps/ios/Merian/Core/Utilities/{AppLifecycleManager,Array+Safe,BackgroundTaskWrapper,FieldNotesRepository,MerianError,Publisher+MainActor}.swift` | Retired. Lifecycle, concurrency, persistence, Offline Sync execution/connectivity, error taxonomy, hardware publisher delivery, Core UI safe access, and Species Reference name presentation now have focused owners and mirrored suites. The unused generic array deduplication API is removed. `Core/Utilities` retains exactly the Foundation-only date and string helpers under a whole-folder architecture guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Queue.swift`                                                                            | Retired. Capture admission and live handoff, funding, Field Trip progress, and uploaded-scan inference replay now have focused Services owners; retry mutations remain in `OfflineQueueDurability.swift`. All production files in this slice are below 600 lines, and mirrored suites plus hosted-result validation follow the new ownership.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+URLSession.swift`                                                                       | Retired. Passes 5A through 5G moved terminal tracking, Auth quiescence, exact owner adoption, terminal routing, and delegate conformance into `Services/BackgroundTransfer`; generation-fenced upload completion into `Services/MediaUpload`; queued-row lookup/mapping and mirrored durable authority into `Persistence`; actor-independent inference decisions into `Policies`; and inference generation lifecycle, request dispatch, accepted task-result/transport-failure completion, delayed status probing, exact-generation task retirement, server-result recovery, durable-authority orphan reconciliation, and retry/server-poll lifetime plus response-to-persistence finalization into eight focused `Services/BackgroundInference` files. Both inference retry paths restore the durable wake immediately after persistence, before post-save ownership revalidation and optional process-local replacement. All nine Background Inference production owners, including policy, are below 600 lines.                                   |
| `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift`                                                                                 | Complete for the actor aggregate. Collection sync lives across an immutable OfflineSync snapshot, an injected account-lease service, a persistence-only actor extension, and a Core Network endpoint owner. Queue selection, upload lifecycle, background-account work, inference lifecycle, inference retry, live/offline scan finalization, shared scan-record support, species metadata, and non-biological retention have separate persistence-only extensions with mirrored behavior and repository-wide architecture tests. An actor-isolated support extension reconciles the durable scan/job retry mirror for only upload and focused inference persistence. A source audit removed the speculative queued-audio repair path; the final unsupported-audio claim fence now lives with inference lifecycle. The declaration-only aggregate is 9 lines. Cross-domain background finalization, stateless record/media mapping, and shared foreground/background response preparation have focused owners with no schema, payload, or UI change. |

Rules for this phase:

- Do not rename public API at the same time as splitting files.
- Preserve call sites unless the old shape forces circular ownership.
- Prefer extensions in sibling files first; move types across folders only after
  the split compiles cleanly.
- Commit each large file split independently.

Implemented Core slices:

- The first `Core/AI/InferenceEngine` slice moved the bounded best-effort write
  FIFO, presentation generations, Auth-transition quiescence fence, per-scan
  review/confirmation/flag action clocks, and ordered identification tail into
  the private `@MainActor InferenceWriteCoordinator`. Active and pending work
  remain capped at eight each, overflow remains best-effort, presentation reset
  invalidates queued generations, and cancellation-ignoring writes remain
  awaitable before Auth identity mutation.
- The second slice moved replaceable live, historical, and identification-review
  hydration task lifetime; cancellation-ignoring Auth quiescence; bounded
  Wikipedia-success and historical-attempt histories; the persisted 24-hour
  enrichment cache; and the temporary rate-limit deadline into
  `InferenceHydrationCoordinator`. GBIF hydration remains a structured child of
  whichever slot resolved its taxon key, preventing duplicate requests and
  detached ownership. Raw task handles no longer escape the owner, and
  `prepareForNewScan()` now clears the temporary enrichment backoff as its
  documented presentation-reset contract requires.
- Wikipedia mobile-sections and GBIF taxon-key request construction, the
  dedicated public `URLSession`, private wire DTOs, HTML normalization, and
  off-main decoding moved once to
  `Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift`.
  `InferenceEngine` retains active-presentation validation and observable state
  mutation; `ScanThumbnailBackfillActor` retains cache, retry, URL-admission,
  persistence, and prefetch policy. The separate Species Reference feature image
  service keeps its distinct Wikipedia summary and GBIF name-query contract.
- The third slice moved all ephemeral local model and cadence state into
  `InferenceLocalAnalysisCoordinator`: classification, deterministic-trait,
  Foundation-cue, and phrase-rotation task slots; bounded derivative and
  provisional classification; request-body gate; phrase cursor; and inactivity
  pause/resume. At that stage, `InferenceEngine` retained exact presentation
  authority and observable phrase publication through narrow callbacks. AppDI
  now supplies the live light-impact start feedback while direct/default engine
  instances use an inert default. The former `LocalVisualAnalysis.swift`
  aggregate was replaced by focused classifier, bounded-image,
  deterministic-trait, Foundation contract/validation/eligibility,
  phrase-policy, and lifecycle files, each below 600 lines. A follow-up
  integration review made repeated inactive/background callbacks idempotent so
  the normal scene transition preserves only one pending exact-session cadence
  resume and cannot restart completed local model work. The generic simulator
  build, focused and complete `merianTests` suites, XcodeGen/source-membership
  checks, parsing, strict lint, and documentation gates passed after that
  correction.
- The fourth slice moved shared visual/nonvisual request preparation and live
  provider dispatch into the initializer-injected `InferenceLiveRequestService`.
  It owns base64 filtering, MIME detection, observation-context serialization,
  aligned descriptor forwarding, staged-video upload, and the single Identify
  call. At that stage, `InferenceEngine` supplied exact-attempt validation after
  encoding, video upload, and provider return and retained its provider-ready
  timer, request-body queue effects, presentation, response parsing,
  persistence, and recovery policy; the ninth slice below moved exact attempt
  and queue-effect ownership into its coordinator and injected service. AppDI
  owns the production live value; tests inject three narrow closures without a
  broad protocol or new singleton. No payload field, request ordering, timeout,
  endpoint, callback, navigation, persistence schema, or observable UI contract
  changed. A follow-up review restored MIME and observation-context helpers to
  file-private visibility and added an explicit stale-after-image-encoding fence
  test.
- The fifth slice added the injected `InferenceLiveResultService` for shared
  visual/nonvisual parse/save input normalization and typed result outcomes. At
  that stage, `InferenceProcessingActor` retained decoding, entitlement,
  storage, media cleanup, and durable-completion rules; the later Core Data
  finalization slice moved shared decoding, mapping, and immutable entitlement-
  settlement projection into `InferenceResponsePreparationService`. The result
  service forwards the exact model context, canonical media, original
  observation-context JSON, and persistence fence; the engine supplies attempt
  validation before/after the actor call. Both persisted and confidence-zero
  no-record completion keep the original engine publication/queue path. Rejected
  or stale results cannot enter it. Discovery feedback, replacement metadata,
  notifications, milestones, hydration, failure policy, and their existing
  ordering remain in the engine. Mirrored service and integration suites use
  injected dependencies and continuation gates, with architecture checks
  preventing direct parse/save mapping from returning to the engine. No DTO,
  payload, schema, endpoint, or presentation contract changed.
- Fifth-slice verification status (2026-09-02): XcodeGen is byte-stable;
  project/source membership, event-routing guards and adversarial tests, Swift
  parsing, strict affected-source lint, isolated result-service typechecking
  against cached app/dependency modules, Markdown formatting, and diff checks
  passed. A successful generic Simulator build, `build-for-testing`, and
  focused/full test execution remain outstanding: local build attempts stopped
  during SwiftPM resolution because of cache-write and nested-sandbox
  restrictions, before any new tests ran. Static checks and isolated
  typechecking are not full-target compilation or runtime evidence. The
  [request/result verification matrix](../development-guides/08-testing-strategy.md#live-inference-requestresult-verification)
  records the required follow-up selectors.
- The sixth slice extracted stateless `InferenceLiveFailurePolicy` and
  `InferenceFailurePresentation` under `Inference/Recovery` and replaced the two
  catch implementations with one private synchronous engine handler.
  Interruption precedence, retired-owner/connectivity handoff before the stale
  guard, exact retirement before terminal effects, known HTTP policy matching,
  all copy, and visual/nonvisual decoding and telemetry differences remain
  unchanged. At that stage, queue mutation, paywall requests, circuit
  accounting, logging, haptics, and observable publication stayed engine-owned;
  the eleventh slice below subsequently extracted all but the observable
  presentation commits. The engine shrank by 337 lines in this slice; both new
  production files remain below 600 lines. Pure policy/presentation suites and
  queue-less engine integration cases cover those decisions, known conflicts,
  decoding, and non-cooperative stale or cancelled failures. Result/recovery
  fixtures now share contained test support and a continuation gate instead of
  duplicating setup. Circuit-breaker XCTest unit cases now use a fresh manager
  instead of resetting the singleton used by Swift Testing integration suites.
  The architecture suite locks the effect-free policies and synchronous
  ownership-to-commit boundary. Parsing, strict affected-source lint,
  byte-stable XcodeGen, project/source membership, event-routing and
  workflow-contract checks, and isolated policy/presentation source and test
  typechecking against cached dependencies passed. A follow-up review
  (2026-09-02) found no additional code fixes necessary. All new result/recovery
  service and integration tests, shared fixtures, policy and presentation tests,
  architecture tests, and the isolated circuit XCTest passed focused frontend
  typechecking against the exact current engine/result/recovery declarations and
  cached unchanged dependencies. That verifies test bodies, not full engine
  compilation or runtime behavior. Simulator discovery is available again, but
  the generic Simulator build and `build-for-testing` still stop at denied
  SwiftPM manifest-cache writes, before candidate tests can execute. Direct
  engine/current-app compilation also stops at the environment's Apple macro
  sandbox restrictions. Focused and full runtime acceptance remain outstanding
  at that slice's handoff; the integration audit below follows it.
- The seventh slice extracted progressive species-enrichment transport
  adaptation and local hydration persistence from `InferenceEngine`.
  `InferenceSpeciesEnrichmentService` owns typed scope/request values, an
  injected fetch seam, and deterministic metadata/lookalike mapping; its `+Live`
  adapter is Core AI's sole `fetchEnrichment` caller.
  `InferenceHydrationPersistenceService` owns immutable reference, metadata, and
  lookalike snapshots; its `+Live` adapter owns `BackgroundDatabaseActor`
  construction and off-main rich-lookalike encoding. `AppDIContainer` composes
  both live values, while direct engine construction retains source-compatible
  live defaults. The engine still owns hydration admission, independent loading,
  task-group scheduling, current-presentation application, bounded retry, and
  write/review generations. Metadata now reaches the actor as domain
  `TaxonomyData`, so the Edge wire DTO no longer crosses into persistence. No
  request/response payload, SwiftData schema, endpoint, feature flag,
  navigation, visible copy, or UI behavior changed.
- Seventh-slice verification status (2026-09-12): XcodeGen is byte-stable;
  project/resource and source-membership checks, event-routing guards and
  adversarial tests, affected Swift parsing, strict affected-source SwiftLint,
  bounded production/test frontend typechecking against cached unchanged
  dependencies, changed-Markdown formatting, the recursive Supabase formatter
  check, and `git diff --check` pass. The canonical generic Simulator
  `build-for-testing` could not start because the required local build wrapper
  was denied process inspection and therefore refused to determine whether
  another `xcodebuild` was active. No current-candidate Simulator test execution
  ran; the bounded typechecks are supplemental evidence, not a full-target build
  or runtime substitute.
- A same-day follow-up review fixed the persistence fence for enrichment on an
  identification override. Metadata and lookalike writes now validate the
  record's effective override-or-original species, matching the reference-write
  boundary. The regression rejects a stale original-species payload while the
  override is active and admits the override payload, including taxonomy,
  alternate names, and the rich lookalike blob.
- The eighth slice extracted historical SwiftData snapshotting, initial
  `SpeciesData` construction, hydration planning, override/original identity,
  reference admission, and rich/legacy lookalike plus candidate decoding into
  `InferenceHistoricalRecordProjection`. Its `@MainActor` initializer consumes
  the live `LocalScanRecord` before suspension and returns only immutable
  `Sendable` values; an awaited detached operation converts deferred legacy and
  candidate content. At this slice, `InferenceEngine.load(from:)` retained
  live-presentation replacement, observable publication, the replaceable
  historical task, network hydration, retry, and write admission. The fourteenth
  slice subsequently moved shared network hydration and enrichment retry into
  the species coordinator; the fifteenth moved registered historical ordering
  into its own coordinator; the sixteenth moved identification-review workflow
  sequencing into its own coordinator; the seventeenth and nineteenth separated
  presentation identity and observable values; the twentieth extracted session
  transition order; and the twenty-first moved synchronous species publication,
  hydration callbacks, exact identity, and bounded write admission into the
  species-presentation bridge. No schema, payload, endpoint, route, feature
  flag, copy, or visible behavior changed.
- A same-day follow-up restored the pre-extraction memory ordering: historical
  identity is assigned and prior live-media buffers are released before the
  projection faults persisted fields or rebuilds historical media. Architecture
  coverage locks that order and proves the deferred task captures no managed
  record; focused coverage also decodes the value snapshot after its source
  record is deleted. Coordinator replacement fences all later effects, while a
  synchronous decoder already running may finish before observing cancellation.
- Eighth-slice verification status (2026-09-12): an independent read-only
  concurrency/parity review found no behavior regression and identified the
  cancellation wording and managed-record-lifetime hardening closed above. The
  primary follow-up audit found and restored the live-media release order.
  Documentation now names the concrete projection owner across the repository,
  records that release order and cooperative-cancellation boundary, routes
  identification-review transport to its injected Network service, and lists the
  complete persisted candidate value shape. XcodeGen is byte-stable;
  project/resource and source-membership checks, event-routing guards and
  adversarial tests, affected Swift parsing, focused production/test iOS
  frontend typechecking, strict affected-source SwiftLint, changed-Markdown
  formatting, the recursive Supabase formatter check, and `git diff --check`
  pass. The required local Simulator build wrapper refused to start because this
  host cannot inspect whether another `xcodebuild` is active, so no
  current-candidate build or runtime test execution is claimed.
- The ninth slice extracted foreground task and exact attempt identity into
  `InferenceLiveAttemptCoordinator`, including the active scan, process-local
  attempt UUID, optional durable generation, and recoverable-presentation scan.
  The coordinator owns exact local/durable validation, full-invalidation
  clear-before-callback ordering, durable-generation fencing before
  exact-current retirement callbacks, duplicate admission, recovered-background
  admission, and post-suspension queue-finalization fencing.
  `InferenceLiveQueueService` supplies a small initializer-injected durable
  boundary; only its `+Live` adapter resolves `OfflineQueueManager` for claim,
  current-owner lookup, deferred-upload release, retirement, exact-generation
  deletion, and terminal rejection. AppDI composes that live value, while
  `InferenceEngine` retains its source-compatible accessors, observable
  presentation, callback timing, and effect sequencing. The engine no longer
  directly resolves the queue.
- Focused service tests record every forwarded value and false result. Focused
  coordinator tests cover queue-less and queue-backed identity, local clearing
  before synchronous durable callbacks, exact-current durable-generation
  fencing, re-entrant replacement preservation, failed-current retirement,
  recovered-background gating, and successful and failed finalization that
  resumes after a same-scan replacement. Architecture coverage freezes the
  private state owner, singleton-free core/live-adapter split, AppDI wiring,
  exact deletion/rejection policy, and 600-line ceiling. No payload, endpoint,
  SwiftData schema, task description, feature flag, navigation, copy, or visible
  behavior changes in this slice.
- Ninth-slice verification status (2026-09-12): affected Swift parsing, strict
  affected-source SwiftLint, strict-concurrency typechecking of the standalone
  production core and live adapter, and focused frontend typechecking of both
  new test suites pass. XcodeGen is byte-stable; project/resource and
  source-membership checks, event-routing validation and adversarial tests, the
  complete iOS CI-tooling regression suite, changed-Markdown formatting, and
  `git diff --check` also pass. The final audit fences the local durable-
  generation slot before exact-current retirement callbacks, preserves
  re-entrant same-scan replacements, and retains the queue coordinator in
  delayed and request-body callbacks so durable upload release does not depend
  on engine lifetime. It also corrected documentation that had overstated the
  adapter's scope: it is Core AI's sole direct queue owner for the live-attempt
  lifecycle. A later integrity review moved accepted-result entitlement effects
  from response preparation to an exact-post-deletion Offline Sync settlement
  owner backed by an injected, retained funding-reconciliation coordinator. It
  also preserved the queue-less nonvisual server-assigned scan-ID contract and
  corrected the post-deletion authorization check to rely on the deletion's
  exact durable proof rather than requiring the now-retired durable generation.
  The canonical local build wrapper refuses to start because this host cannot
  query `xcodebuild` process state (`sysmond` is unavailable); no candidate
  Simulator build or runtime test execution is claimed, and focused typechecking
  is not presented as a substitute.
- The tenth slice extracted the duplicated visual/nonvisual accepted-result
  workflow into `InferenceLiveCompletionCoordinator`. The singleton-free core
  normalizes persisted and confidence-zero no-record outcomes, applies
  new-discovery state, sequences replacement metadata, circuit success, and
  completion telemetry, emits the foreground biological event after observable
  commit, and requires a typed follow-up permit for notifications and milestone
  scheduling. Queue-backed permits require exact-generation deletion while the
  complete local/durable tuple remains current and leave no outstanding durable
  generation. Queue-less nonvisual completion uses a synchronous nil-identity
  permit path so the extraction does not add a suspension. The `+Live` adapter
  alone bridges the concrete managers, repository, settings, analytics, event
  bus, push manager, and milestone coordinator; AppDI captures those
  collaborators once and injects the dependency value. The engine retains public
  signatures and observable media publication. Later slices moved media
  construction into `InferenceLiveMediaProjector`, benchmark placement and
  modality-specific effect order into `InferenceLivePipelineCoordinator`, and
  hydration sequencing into its focused coordinators.
- Focused completion tests cover accepted-outcome normalization, exact shared-
  effect order, rejected-persistence inertness, event and notification gating,
  successful/failed durable finalization, partial durable-identity rejection,
  and replacement or durable retirement during a suspended finalizer.
  Architecture coverage freezes the core/live split, sealed permit construction,
  AppDI wiring, retired engine singleton effects, both modality orders, and the
  600-line production ceiling. No payload, endpoint, SwiftData schema,
  persistence, feature flag, navigation, copy, or intended visible behavior
  contract changed.
- The second-pass audit closed a post-suspension authorization gap. A successful
  queue deletion now authorizes follow-ups only if its complete scan, local
  attempt, and durable generation still match when the deletion returns. A
  same-attempt durable retirement therefore cannot receive stale notification,
  milestone, or hydration work. Partial scan/generation pairs fail closed, the
  permit initializer is file-scoped, and the synchronous queue-less path accepts
  only a nil scan/durable pair. These changes strengthen stale-work rejection
  without altering queue persistence, endpoint, payload, or presentation-
  success ordering.
- Tenth-slice verification status (2026-09-12): XcodeGen is byte-stable;
  generated-project/resource and source-membership guards, event-routing
  validation and adversarial tests, the complete iOS CI-tooling regression
  suite, affected Swift parsing, strict affected-source SwiftLint, standalone
  production-core and focused-test frontend typechecking, changed-Markdown
  formatting, and whitespace validation pass. The required generic Simulator
  `build-for-testing` was attempted through `make ios-local-build`, but the
  safety wrapper refused before invoking Xcode because this sandbox cannot
  inspect whether another `xcodebuild` is active. No fresh build or Simulator
  runtime result is claimed for this slice.
- The eleventh slice extracted duplicated visual/nonvisual failure recovery and
  durable queue-handoff sequencing into `InferenceLiveFailureCoordinator`. Its
  singleton-free main-actor core takes an initial exact local/durable ownership
  snapshot, preserves task/logical/transport cancellation precedence, rechecks
  durable state for retired-owner handoff, handles connectivity handoff before
  the stale guard, and sequences release, retirement, recoverable-ID retention,
  terminal rejection, telemetry, circuit, logging, paywall, feedback, and typed
  failure creation without a task or suspension. It rechecks local ownership
  after synchronous release, retirement, and rejection callbacks so a callback-
  installed replacement cannot receive stale handoff, feedback, or failure
  presentation. The engine now applies only three synchronous observable
  actions: retain a recoverable scan ID, transition the current presentation to
  the queue, or publish the failure value. The `+Live` adapter alone bridges the
  concrete effect managers, and AppDI captures and injects those collaborators;
  direct engine construction preserves its existing paywall closure through a
  lazy fallback adapter.
- Focused coordinator tests lock exact terminal order, queue-less fallback,
  stale suppression, cancellation, retired-owner/transport/connectivity handoff,
  quota, observation rejection, and re-entrant queue callback replacement
  against injected queue/effect seams. A dedicated architecture suite freezes
  the core/live split, AppDI wiring, three narrow engine actions,
  post-retirement ownership guard, retired engine helpers/effects, no-suspension
  boundary, and 600-line production ceiling. No endpoint, JSON payload,
  SwiftData schema, persistence, feature flag, navigation, copy, accessibility,
  layout, or intended visible behavior contract changed.
- Eleventh-slice verification status (2026-09-13): XcodeGen is byte-stable;
  generated-project/resource and source-membership guards, event-routing
  validation and adversarial tests, the complete iOS CI-tooling regression
  suite, affected Swift parsing, strict affected-source SwiftLint, standalone
  production-core and focused-test frontend typechecking against cached iOS
  dependencies, changed-Markdown formatting, and whitespace validation pass. The
  required generic Simulator `build-for-testing` was attempted through
  `make ios-local-build`, but the safety wrapper refused before invoking Xcode
  because this sandbox cannot inspect whether another `xcodebuild` is active.
  Cached-dependency typechecking is not a full current-target compile, and no
  fresh build or Simulator runtime result is claimed for this slice. A same-day
  follow-up review found that an injected synchronous queue callback could
  install a replacement after the initial ownership snapshot. Post-release,
  post-retirement, and post-rejection local-owner guards now suppress stale
  handoff, feedback, and failure presentation, with deterministic re-entrancy
  coverage and an architecture order guard. The executable checks above passed
  again after this correction; the local-build wrapper retained the same
  pre-Xcode process-inspection refusal.
- The twelfth slice extracted identification-review action and effect sequencing
  into `Inference/IdentificationReview`. The singleton-free
  `InferenceIdentificationReviewCoordinator` delegates replacement, final-
  writer, and Auth fencing to the shared write coordinator; preflights the
  bounded throwing snapshot read; classifies Species Dictionary lookup results;
  serializes local persistence before the account-fenced review RPC; and emits
  an Explore refresh before milestone processing only after transport succeeds.
  Its `+Live` adapter alone constructs `BackgroundDatabaseActor`, maps a scan to
  its shared post, logs failures, and binds AppDI-captured event and milestone
  collaborators. The snapshot service moved beside that owner.
- `IdentificationReviewPresentation` now returns pure full-value actions for the
  override placeholder, confirmation, reset, and Species Dictionary hydration,
  including the matching typed persistence patch. `InferenceEngine` retains the
  three public method signatures, current scan/presentation guards, observable
  `SpeciesData` and reference-media commits, and the replaceable review
  hydration slot. The review section no longer constructs a database actor,
  invokes its Network service directly, resolves AppDI/shared-post state, or
  owns cross-feature post-success effects. `UserReviewState` gained compiler-
  checked `Sendable` conformance so the persistence dependency remains typed
  instead of round-tripping through an unchecked or fallible raw string.
- Deterministic coordinator tests lock local-before-cloud and refresh-before-
  milestone order, transport-failure suppression, replacement and Auth-fence
  rejection, typed snapshot/lookup failures, and the silent species-ID fallback.
  Pure presentation tests lock the complete field wipe/restoration, dictionary
  normalization, secure reference admission, and paired durable patch. The
  architecture suite freezes the core/live split, AppDI composition, engine
  effect boundary, source ordering, and the 600-line ceiling. No endpoint, JSON
  payload, SwiftData schema, persistence semantics, feature flag, navigation,
  copy, accessibility, layout, or intended visible behavior contract changed.
- Twelfth-slice verification status (2026-09-13): XcodeGen is byte-stable;
  generated-project/resource and source-membership guards, event-routing
  validation and adversarial tests, the complete iOS CI-tooling regression
  suite, affected Swift parsing, strict production and focused-test SwiftLint,
  focused review owner/test and architecture frontend typechecking against
  cached iOS dependencies, changed-Markdown formatting, and whitespace
  validation pass. The required generic Simulator `build-for-testing` was
  attempted through `make ios-local-build`, but the safety wrapper refused
  before invoking Xcode because this environment cannot verify whether another
  `xcodebuild` is active. Cached-dependency typechecking is not a complete
  current-target compile; no fresh full-target build or Simulator runtime result
  is claimed for this slice.
- A same-day review removed the remaining opportunity for local and cloud review
  state to diverge: the Network mutation now owns one typed `UserReviewState`,
  exposes only coherent override, confirmation, and reset factories, and encodes
  that same value to the unchanged RPC raw string. Coordinator persistence now
  derives from the mutation instead of receiving a second state argument.
  Focused payload coverage locks all three factory shapes and exact null/raw
  encoding. The architecture guard now detects the singleton token with a word
  boundary so an ordinary member such as `sharedPostID` does not create a false
  positive, while still rejecting an actual `.shared` access. All non-Xcode
  checks listed above passed again after these corrections, including strict-
  concurrency frontend typechecking of the current coordinator core and its
  focused test source plus native execution of all three payload encodings. The
  local-build wrapper retained the same pre-Xcode process-inspection refusal.
- The thirteenth slice extracted the live visual/nonvisual execution bodies into
  `Inference/Pipeline/InferenceLivePipelineCoordinator`. Its singleton-free
  main-actor core owns exact admission and activation, circuit gating, request
  and result service sequencing, completion preparation, benchmark placement,
  durable finalization, modality-specific follow-up order, synchronous failure
  dispatch, and exact-owner cleanup. The engine retains the stable method
  signatures, preflight and presentation staging, source-compatible task
  accessor, observable/media commits, local-analysis callback, and hydration
  scheduling callback. The pipeline's `+Live` adapter alone binds circuit,
  quota-refund, and logging effects, while AppDI captures the concrete managers.
- The parity review kept queue-less nonvisual follow-up authorization
  synchronous after commit; only the queue-backed branch awaits durable
  finalization. It also preserved the visual notification-before-timing and
  hydration-before-milestone order, the nonvisual timing-before-authorization
  and milestone-before-notification/hydration order, the two-second upload
  release fail-safe, empty-encoding refund/retirement, and exact stale-owner
  cleanup. Focused pipeline and architecture suites cover admission, visual
  empty encoding, queue-less visual/nonvisual success order, durable nonvisual
  finalization, durable visual deletion-before-follow-up order, circuit failure,
  suspended replacement, live-effect confinement, engine delegation, and the
  600-line Pipeline ceiling. No endpoint, payload, SwiftData schema,
  persistence, feature flag, navigation, copy, accessibility, layout, or
  intended visible behavior contract changed.
- The Pass 13 verification caught and corrected one stale CI ownership check:
  `scripts/test-ios-build-and-test-workflow.sh` now requires both durable-
  recovery bindings at the pipeline provider-dispatch owner and rejects those
  bindings in the engine façade. Queue and completion live defaults now resolve
  inside the main-actor engine initializer, removing the two default-argument
  isolation warnings without changing call-site labels or production
  composition. The complete production Swift source set compiled without
  diagnostics against the cached iOS Simulator SDK; focused pipeline and
  architecture test sources typechecked; changed Swift parsing, strict
  SwiftLint, byte-stable XcodeGen, project/resource membership, event routing,
  iOS CI tooling, Supabase tooling and executable documentation contracts,
  Markdown formatting, and whitespace validation passed. The required local
  build wrapper was attempted again but refused before invoking Xcode because
  this environment cannot verify whether another `xcodebuild` is active, so no
  fresh linked target or Simulator-runtime result is claimed.
- The documentation follow-up aligned the app/Core ownership guides, system
  overview, agent directory guide, codebase and test inventories, offline
  handoff and ingestion contracts, concurrency/error gotchas, Insight race
  narrative, incident record, logging inventory, data/API contracts, focused
  test matrix, and executable documentation guard with the pipeline, failure,
  and identification-review coordinator boundaries. No product, wire,
  persistence, or release contract changed.
- The fourteenth slice extracted live species hydration from `InferenceEngine`.
  The singleton-free `InferenceSpeciesHydrationCoordinator` now owns the
  complete live Wikipedia/enrichment/GBIF sequence, exact
  scan/species/presentation/review identities, sanitized five-URL merging, and
  immutable persistence-work emission. Its private-state
  `InferenceSpeciesEnrichmentCoordinator` owns the concurrent metadata/lookalike
  children, independent loading completion, current-presentation patching,
  silent 403 handling, shared 429 backoff, and the one taxonomy-gated lookalike
  retry. At that slice, historical and identification-review flows retained
  their established engine-level projection/action order while reusing the
  coordinator's exact Wikipedia, GBIF, enrichment, and missing-reference
  operations. The fifteenth slice below moves historical follow-up order into a
  dedicated owner; the engine retains stable entry points, observable
  publication, and bounded persistence admission through narrow callbacks.
- `InferenceLookalikeCacheResetService` separately isolates the installed
  legacy-cache compatibility decision. Its effect-free injected core accepts an
  optional `ModelContainer`; only the `+Live` adapter reads and writes the
  existing UserDefaults reset version, coalesces process-wide work, starts the
  existing utility-priority detached task, and constructs
  `BackgroundDatabaseActor`. `AppDIContainer` composes the reference,
  enrichment, persistence, hydration-logging, and reset values explicitly.
  Focused deterministic suites lock live ordering and enriched taxon-key
  handoff, independent scope failure, loading/reference transitions, stale
  Wikipedia suppression without consuming retry state, immutable persistence-
  work emission, 429 suppression, and reset/nil-container admission.
- Fourteenth-slice verification status (2026-09-13): all 1,255 current app
  sources type-check together against the cached locked iOS Simulator
  dependencies, and the 14 changed/new test and shared-support sources
  type-check against a freshly emitted testing-enabled module. Changed Swift
  parsing, strict no-cache SwiftLint, byte-stable XcodeGen, generated-project,
  resource/source membership, event-routing and adversarial routing checks, and
  the complete iOS CI-tooling regression suite pass. The required local build
  wrapper was attempted but refused before invoking Xcode because this sandbox
  cannot verify whether another `xcodebuild` is active; no fresh linked target
  or Simulator-runtime result is claimed. Documentation formatting, executable
  documentation contracts, and whitespace validation were rerun before handoff.
  No endpoint, JSON payload, SwiftData schema, persistence format, feature flag,
  navigation, copy, accessibility, layout, or release contract changed.
- A second-pass cancellation audit found that a cancellation-ignoring public-
  reference parser or enrichment dependency could return after
  `cancelHistoricHydration()` and still mutate the unchanged presentation. The
  species and enrichment coordinators now recheck cancellation before logging,
  publication, retry, or persistence-work emission after every external
  suspension. Deterministic tests cover Wikipedia, GBIF, metadata, and
  lookalikes returning after cancellation. The complete 1,255-source app module
  and all 14 changed/new test/support sources type-check with warnings as
  errors; strict SwiftLint, parsing, XcodeGen, membership, routing, CI tooling,
  Markdown, and whitespace gates pass. The repository build wrapper remains
  host-blocked before Xcode by process-inspection denial, so no new Simulator
  runtime claim is made.
- The fifteenth slice extracted registered historical follow-up orchestration
  from `InferenceEngine.load(from:)` into the singleton-free
  `InferenceHistoricalHydrationCoordinator`. The engine retains synchronous
  lifecycle reset, persisted-record projection, initial observable/media
  publication, review-generation capture, override refresh callbacks, and
  bounded persistence admission. The new owner registers one `.historic`
  operation, publishes initial reference state, awaits deferred projection
  decoding and displayed-override refresh, runs Wikipedia beside enrichment, and
  awaits GBIF after enrichment supplies the final taxon key. Species-level
  metadata caching remains independent from per-scan lookalike admission, and
  cancellation checks fence every awaited stage. It captures no managed record,
  singleton, network client, database actor, or raw persistence owner.
- Five focused historical-coordinator tests lock the complete order, enriched
  taxon-key handoff, cached-metadata/lookalike independence, replacement after a
  cancellation-ignoring decoder, cancellation after a non-cooperative override
  callback, and terminal empty reference state when eligible providers return no
  usable image. Architecture and executable documentation guards keep the
  asynchronous sequence out of the engine. The extraction removes 114 lines from
  `InferenceEngine.swift`; the final 231-line production owner and 595-line
  focused suite remain below the 600-line review ceiling. No endpoint, JSON
  payload, SwiftData schema, persistence format, feature flag, navigation, copy,
  accessibility, layout, or release contract changed.
- Fifteenth-slice verification status (2026-09-13): focused coordinator/test
  sources and the architecture suite type-check with warnings as errors against
  the cached Pass 14 iOS module. A current engine-integration overlay also
  type-checks after removing only the Observation attributes whose macro plugin
  the sandbox cannot launch. Changed Swift parsing, strict no-cache SwiftLint,
  byte-stable XcodeGen, generated-project and source-membership checks,
  event-routing and adversarial routing checks, the complete iOS CI-tooling
  regression suite, all 265 standard Supabase tooling tests plus the isolated
  DTO contracts, executable documentation contracts, Markdown formatting, skill
  link integrity, and whitespace validation pass. The required local build
  wrapper was attempted in normal and isolated modes but refused before invoking
  Xcode because this sandbox cannot inspect active `xcodebuild` processes; no
  fresh linked-target or Simulator-runtime result is claimed.
- The final Pass 15 review closed three presentation-lifetime gaps. Historical
  hydration now validates the complete scan/species/presentation/review identity
  at entry and after each suspension, and resolves its own still-current loader
  to empty when providers yield no usable image. Live hydration validates that
  identity before its first loader publication or provider request, while its
  deferred cleanup can no longer clear a replacement same-scan presentation's
  loading state. Deterministic tests cover pre-start replacement, cancellation-
  ignoring replacement tails, and terminal empty-provider responses. Byte-stable
  XcodeGen, project/source and event-routing guards, Swift parsing, strict lint,
  warnings-as-errors strict-concurrency typechecking, iOS tooling and exact-
  result validators, the complete Supabase tooling suite, all 26 executable
  documentation contracts, Markdown/Deno formatting, and whitespace validation
  pass. The supported local build wrapper retains the same pre-Xcode process-
  inspection refusal, so no Simulator execution is claimed.
- The sixteenth slice extracted the complete identification-review workflow from
  `InferenceEngine` into the singleton-free
  `InferenceReviewWorkflowCoordinator`. The existing action/effect coordinator
  still owns review/confirmation/legacy-flag generations, ordered local and
  cloud writes, typed snapshot and dictionary failure, and post-sync effects.
  The new workflow owner sequences override, confirmation, reset, and historical
  displayed-override hydration; preserves local admission before dictionary and
  cloud work; registers interactive work in the replaceable review slot; and
  invokes the species-hydration owner for enrichment and reference follow-up.
  The engine's three public signatures and observable/media commits remain
  unchanged behind one presentation-application closure and one hydration
  callback bundle.
- The workflow now revalidates the exact scan, species, presentation generation,
  review generation, cancellation state, and Auth fence after every external
  suspension. A cancellation-ignoring replaced dictionary or species-ID lookup
  can no longer publish, persist, or return a stale result. Focused
  continuation-gate tests lock local-before-cloud and patch-before-review order,
  overlapping override replacement, missing-row enrichment followed by the
  species-ID fallback, and stale historical dictionary/fallback rejection. The
  extraction reduces `InferenceEngine.swift` from 2,077 to 1,796 lines; the
  399-line workflow and 469-line focused suite remain below the 600-line review
  ceiling. No endpoint, payload, SwiftData schema, persistence format, feature
  flag, navigation, copy, accessibility, layout, or release contract changed.
- The final sixteenth-slice review removed duplicate `currentSpeciesData` and
  `currentPresentationGeneration` closures from the workflow callback value.
  Both are now sourced only from its nested species-hydration callbacks, so a
  caller cannot make workflow admission and stale-result checks consult
  different presentation owners. `InferenceArchitectureTests` freezes that
  single-source contract. The audit also corrected residual documentation that
  assigned enrichment scheduling, current-presentation application, reference
  URL policy, or hydration persistence directly to the engine.
- Sixteenth-slice verification includes byte-stable repeated XcodeGen,
  generated-project resource and source-membership guards, event-routing source
  and adversarial guards, project-resource adversarial fixtures, Swift parsing,
  strict SwiftLint, focused Swift 6 strict-concurrency typechecking for the
  workflow and its tests, architecture-suite typechecking, all 26 executable
  documentation contracts, recursive Supabase Deno formatting, Markdown
  formatting, and whitespace validation. The supported local build wrapper
  remains unable to inspect active Xcode processes in this sandbox and exits
  before invoking Xcode, so no Simulator build or test execution is claimed for
  this slice.
- The seventeenth slice extracted process-local presentation lifecycle from
  `InferenceEngine` into the non-observable `@MainActor`
  `InferencePresentationCoordinator`. The focused owner contains exact prepared
  and active presentation identity, visual queue-handoff phrase/media context,
  and the pending first-render timestamp. It performs only synchronous value
  decisions: observable queue IDs, copy, media, species, processing state,
  logging, networking, persistence, and task lifetime remain with their existing
  owners. Public engine entry points, callback order, visual/nonvisual
  semantics, visible Auth behavior, and first-render measurement boundaries
  remain unchanged. One internal hygiene correction closes a latent post-drain
  leak: Auth quiescence now clears any presentation owner and queued visual
  phrase/media context installed re-entrantly during the drain, while preserving
  the pending first-render metric just as Auth admission does.
- Nine deterministic coordinator tests lock prepared versus active handoff,
  exact attempt/current-owner checks, nonvisual isolation, stale cleanup, exact
  finish, reset, Auth admission/quiescence, and one-shot first-render
  consumption. `InferenceArchitectureTests` freezes the extracted fields and
  rejects observable models, effects, tasks, singletons, and domain presentation
  values in the coordinator. This slice reduces `InferenceEngine.swift` from
  1,790 to 1,702 lines; the 231-line production owner and 252-line focused suite
  remain below the 600-line review ceiling. No endpoint, payload, SwiftData
  schema, persistence, feature-flag, navigation, copy, accessibility, layout, or
  release contract changed.
- The eighteenth slice extracted live visual/nonvisual media normalization from
  `InferenceEngine` into `InferenceLiveMediaProjector`. The value-only owner
  derives the fallback timeline, preserves explicit owner order, creates the
  aligned provider projection, selects display-policy image bytes, carries focus
  regions, maps live and persisted media into `ActiveScanMedia`, resolves moved
  Documents/temporary paths, admits only policy-approved remote video, and
  applies explicit-index video poster suppression and fallback. Filesystem
  roots, existence, and secure-URL validation are narrow injected values; the
  owner has no task, observable mutation, logging, persistence, or network call.
  Engine method signatures, admission order, modality choice, phrase selection,
  active-media publication order, persisted-media completion timing, and wire
  inputs remain unchanged. The second-pass review corrected a legacy adjacency
  heuristic: only an image whose index explicitly matches the following video's
  poster is suppressed, so a real staged still immediately before that video
  remains visible in both live and persisted carousel mapping.
- Seven deterministic projector tests lock default versus explicit timelines,
  visual display/focus mapping, owner-order projection, remote-video and poster
  behavior, adjacent-still retention, persisted remapping, compatible local
  paths, empty legacy inputs, and the intentionally independent nonvisual
  audio-modality decision. `InferenceArchitectureTests` requires delegation and
  prevents direct filesystem/mapping helpers from returning to the engine. The
  strict focused compile also caught and removed a helper/local-name ambiguity
  that could make the Swift compiler fail without a diagnostic. This slice
  reduces `InferenceEngine.swift` from 1,702 to 1,593 lines; the 262-line
  production owner and 283-line suite remain below the 600-line review ceiling.
  No endpoint, payload, SwiftData schema, persistence, feature-flag, navigation,
  copy, accessibility, layout, or release contract changed.
- The nineteenth slice extracted stored observable values and their synchronous
  transitions from `InferenceEngine` into the `@MainActor @Observable`
  `InferencePresentationState`. Processing, metadata/enrichment and lookalike
  loaders, scanning copy, active media, species data, the queued-presentation
  ID, and display telemetry now have one effect-free owner. The engine preserves
  every existing property name through computed read-throughs, so SwiftUI
  observation, test/preview mutation, publication order, routes, and call sites
  remain stable. Lifecycle identity, task ownership, networking, persistence,
  logging, filesystem access, and singleton resolution remain outside the state
  owner. The slice also closes a pre-existing telemetry leak: new-scan,
  nonvisual, and cancellation transitions now clear the previous visual subject
  distance.
- Seven deterministic state tests lock complete preparation reset, successful
  result and queue-handoff publication, cancellation, historical replacement,
  displaced historical-loader cleanup, visual-to-nonvisual distance isolation,
  and Observation invalidation through scalar and value-type media writeback on
  the engine facade. `InferenceArchitectureTests` freezes ownership and
  result-publication order. This slice reduces `InferenceEngine.swift` from
  1,593 to 1,580 lines. The production owner has 198 lines and the focused suite
  has 213; both remain below the 600-line review ceiling. Compiler-backed
  candidate typechecking passed with Observation and Swift Testing macro
  expansion. No endpoint, payload, SwiftData schema, persistence format, feature
  flag, navigation, copy, accessibility, layout, or release contract changed.
- The twentieth slice extracted cross-owner session transition order from
  `InferenceEngine` into the effect-acquisition-free `@MainActor`
  `InferenceSessionLifecycleCoordinator`. It sequences new-scan preparation,
  visual/nonvisual replacement, successful publication, pipeline finish, visual
  queue handoff, dismissal, explicit cancellation, historical-load admission,
  application activity, and the two Auth-transition phases across the existing
  attempt, hydration, write, local-analysis, presentation-identity, and
  presentation-value owners. It creates no task, stores no duplicate mutable
  registry, and resolves no network, persistence, logging, filesystem, or
  singleton dependency. Durable queue effects stay behind the attempt owner's
  injected service. The engine keeps every stable entry point and accessor,
  request/task creation, immutable projection, and callback composition.
- Seven deterministic lifecycle tests lock complete reset, modality-specific
  replacement, coherent queue handoff, cancellation, historical replacement, and
  an Auth drain that waits for cancellation-ignoring attempt, hydration, and
  write work. The architecture sibling freezes the critical operation order,
  engine delegation, semantic attempt-task operations, effect exclusions, and
  the 600-line ceiling. This slice reduces `InferenceEngine.swift` from 1,580 to
  1,468 lines; the new production owner is 250 lines, the behavior suite is 481
  lines, and the architecture suite is 233 lines.
- Twentieth-slice candidate verification includes byte-stable XcodeGen,
  generated-project/resource and source-membership guards, event-routing source
  and adversarial checks, Swift parsing, strict SwiftLint, and compiler-backed
  focused typechecking with Observation and Swift Testing macro expansion. The
  supported local Simulator build wrapper was attempted but refused before
  invoking Xcode because this sandbox cannot verify whether another `xcodebuild`
  is active; no new Simulator build or runtime result is claimed. No endpoint,
  payload, SwiftData schema, persistence format, feature flag, navigation, copy,
  accessibility, layout, or release contract changed.
- A second-pass concurrency and ownership audit on 2026-09-13 independently
  retraced task replacement, stale pipeline completion, Auth admission and
  quiescence, cancellation, historical replacement, and the hydration/write
  fences. It found no corrective source change. Fresh verification again passed
  byte-stable XcodeGen, project/resource and source-membership guards, event-
  routing source and adversarial checks, Swift parsing, strict SwiftLint with
  zero violations, warnings-as-errors focused test typechecking, the lifecycle
  architecture oracle, iOS CI-tooling tests, Markdown formatting, documentation
  contracts, recursive Supabase formatting, and `git diff --check`. The
  supported Simulator wrapper again stopped before compilation because this host
  could not inspect active `xcodebuild` processes; no build or runtime test
  result is inferred from the supplemental compiler checks.
- The twenty-first slice extracted the hydration-presentation callback bridge
  and write admission from `InferenceEngine` into the live-dependency-free
  `@MainActor` `InferenceSpeciesPresentationCoordinator`. It is the sole
  production constructor of `InferenceSpeciesHydrationCoordinator.Callbacks`,
  applies admitted species/reference/loading values through
  `InferencePresentationState`, starts review generations, validates exact
  case-insensitive scan/species plus presentation/review generations, routes
  immutable persistence work to the bounded background or serialized review
  owner, and admits eligible live hydration. The engine keeps stable public
  entry points, synchronous historical projection, and source-compatible
  observable read-throughs. The new bridge owns no mutable state, task, live
  dependency, network transport, or persistence implementation.
- Six deterministic behavior cases lock observable publication, shared review
  callbacks, complete identity fencing, both write paths, stale/Auth-fenced
  rejection, and biological-only live admission. A focused architecture suite
  freezes the sole callback factory, engine delegation, required fences and
  routes, effect/state/task exclusions, private dependency storage, and the 600-
  line ceiling. This slice reduces `InferenceEngine.swift` from 1,468 to 1,302
  lines; the production bridge is 174 lines, the behavior suite 382, and the
  architecture suite 158. No endpoint, payload, SwiftData schema, persistence
  format, feature flag, navigation, copy, accessibility, layout, or release
  contract changed.
- Twenty-first-slice candidate verification includes byte-stable XcodeGen,
  generated-project/resource and source-membership guards, event-routing source
  and adversarial checks, Swift parsing, strict no-cache SwiftLint, and
  production plus focused-test compiler validation with Observation and Swift
  Testing macro expansion. The complete iOS CI-tooling regression, all 265
  standard Supabase tooling tests plus the isolated DTO and wire-contract
  suites, all 26 executable documentation contracts, recursive Deno and
  changed-Markdown formatting, and whitespace validation pass. The supported
  local Simulator `build-for-testing` wrapper was attempted but refused before
  invoking Xcode because this sandbox cannot verify whether another `xcodebuild`
  is active; no new linked build or Simulator-runtime result is claimed.
- A final Pass 21 ownership and concurrency audit found no behavioral defect in
  callback construction, live admission, exact identity checks, cancellation,
  Auth fencing, or background-versus-review persistence routing. It corrected
  stale source headers that still assigned hydration callbacks or lifecycle
  coordination to `InferenceEngine`, and clarified the app and Core AI READMEs
  plus the canonical AI, manager, and Insight guides: the species-presentation
  bridge validates scan/species and presentation/review identity, while
  `InferenceWriteCoordinator` retains bounded operation lifetime and enforces
  presentation-generation, Auth, and action-generation fences. All 69 documented
  focused-test selectors resolve to current suites, and the Pass 21 source/test
  line-count claims remain exact. Repeated byte-stable XcodeGen,
  project/resource and source-membership validation, Swift parsing, strict
  SwiftLint, event-routing checks, the complete iOS CI-tooling suite, all 26
  executable documentation contracts, Markdown and recursive Supabase
  formatting, and whitespace validation pass. The required Simulator wrapper was
  retried and again stopped before Xcode because process inspection is
  unavailable; no linked build or runtime-test result is added by this comment-
  and-documentation-only correction.
- The twenty-second slice extracted the remaining live-pipeline presentation
  callback bridge from `InferenceEngine` into the effect-acquisition-free
  `@MainActor` `InferenceLivePresentationCoordinator`. It is now the sole
  production constructor of `InferenceLivePipelineCoordinator.Callbacks` and
  `VisualCallbacks`. The bridge performs the exact local/durable success check
  before invoking persisted-media projection, publishes through
  `InferenceSessionLifecycleCoordinator`, emits the biological completion event
  only after that publication, routes exact finish and all three typed failure
  actions, forwards the captured hydration container/policy, and translates
  visual cancellation/request-body callbacks to
  `InferenceLocalAnalysisCoordinator`. It creates no task or suspension, owns no
  mutable or observable state, resolves no live dependency, and captures no
  engine. Public visual/nonvisual analysis, successful-result commit, recovered-
  result, queue-handoff, navigation, and presentation signatures remain stable.
- Six deterministic bridge cases lock accepted and stale publication, stale
  persisted-media projection suppression, publication-before-event order,
  callback-session finish identity, recoverable/failure/queue action mapping,
  visual queue phrase transfer, exact request-body session forwarding, phrase-
  deck preservation during cancellation, and captured hydration-policy and
  `ModelContainer` forwarding. The async suite has the standard one-minute
  limit. The pipeline architecture suite proves the bridge is the only
  production constructor of either callback bundle, freezes attempt-before-
  projection order plus hydration and local-analysis tuple forwarding, and
  prevents callback construction or typed failure mapping from returning to the
  engine. The completion, failure, lifecycle, and aggregate architecture suites
  point at the new owner. This slice reduces `InferenceEngine.swift` from 1,302
  to 1,220 lines; the production bridge is 172 lines, its behavior suite is 333
  lines, its reusable test support is 301 lines, and the expanded pipeline
  architecture suite is 203 lines. No endpoint, payload, SwiftData schema,
  persistence format, feature flag, navigation, copy, accessibility, layout, or
  release contract changed.
- Pass 22 follow-up review confirmed the callback now evaluates the persisted-
  media mapper lazily behind the exact-attempt guard. Its stale-completion test
  proves the mapper, publication, and foreground event remain inert after
  replacement; the architecture suite freezes the attempt-before-projection
  source order; and the behavior suite has the standard one-minute async limit.
  Byte-stable XcodeGen, project/resource and source-membership validation,
  event-routing source and adversarial checks, Swift parsing, strict SwiftLint,
  focused test typechecking, the complete iOS CI-tooling suite, all 26
  executable documentation contracts, Markdown and recursive Supabase
  formatting, and whitespace validation pass. The supported Simulator
  `build-for-testing` wrapper stopped before invoking Xcode because this
  environment cannot inspect active `xcodebuild` processes, so this local
  follow-up claims no linked build or runtime-test result.
- The twenty-third slice moved all recovered-presentation admission and commit
  ordering from `InferenceEngine` into the existing effect-acquisition-free
  `InferenceSessionLifecycleCoordinator`. Exact background recovery transfers
  the complete released attempt tuple before cancelling local analysis and
  publishing. Queued-result recovery fences the retained presentation ID,
  case-insensitive result ID, and current active scan before cleanup and
  publication. Queued-record recovery fences the retained, record, and active
  IDs, then clears recovery ownership before invoking a synchronous loader. The
  engine retains all three source-compatible methods; it passes immutable IDs
  and values or a nonescaping callback, so the lifecycle owner does not acquire
  `LocalScanRecord`, persistence, task, network, logger, filesystem, or
  singleton ownership.
- Five deterministic recovery cases lock exact background transfer, stale same-
  scan replacement rejection, every queued-result and queued-record identity
  fence, matching-result publication, and clear-before-record-load order. The
  existing lifecycle fixture moved into a 141-line shared test-support file,
  reducing the original behavior suite from 481 to 350 lines. This slice reduces
  `InferenceEngine.swift` from 1,220 to 1,191 lines; the expanded lifecycle
  owner is 312 lines, the recovery suite is 263, and the architecture suite
  is 349. The architecture oracle freezes all three transition orders, stable
  engine delegation without facade-owned recovery guards, effect and managed-
  record exclusions, and the 600-line focused-owner ceiling. No endpoint,
  payload, SwiftData schema, persistence format, feature flag, navigation, copy,
  accessibility, layout, or release contract changed.
- Twenty-third-slice candidate verification includes byte-stable repeated
  XcodeGen, project/resource and source-membership validation, event-routing
  source and adversarial checks, affected Swift parsing, and strict no-cache
  SwiftLint with zero violations. Warnings-as-errors iOS frontend typechecking
  passes for the complete current Inference source set plus engine and for the
  focused lifecycle behavior, recovery, support, and architecture sources with
  macro expansion. The complete iOS CI-tooling suite, all 26 executable
  documentation contracts, Markdown and recursive Supabase formatting, and
  whitespace validation pass. The supported Simulator `build-for-testing`
  wrapper was attempted and stopped before invoking Xcode because this host
  cannot inspect active `xcodebuild` processes; no linked build or runtime-test
  result is claimed.
- The twenty-fourth slice moved visual and nonvisual live-submission startup
  from `InferenceEngine` into the singleton-free `@MainActor`
  `InferenceLiveSubmissionCoordinator`. The new owner preserves Auth and empty-
  payload disposition, admission-before-replacement, media/telemetry staging,
  attempt and presentation activation, local visual analysis, first-render
  timing, immutable request/callback construction, and execution-task
  registration. It immediately installs the task in
  `InferenceLiveAttemptCoordinator`, which remains the sole task-handle and
  attempt-identity owner. It stores no mutable state and resolves no network,
  persistence, logger, filesystem, or singleton dependency. Both engine entry
  signatures remain unchanged and are now thin typed delegates.
- Six deterministic startup cases lock visual presentation and task staging,
  audio and Describe copy, Auth-fenced release-before-retirement, visual empty-
  payload release-before-retirement, and the retained nonvisual retirement-only
  behavior. Source-order guards freeze both modality sequences, engine
  delegation, callback ownership, effect exclusions, and the 600-line focused-
  owner ceiling. The slice reduces `InferenceEngine.swift` from 1,191 to 1,004
  lines; the new production owner is 337 lines and its behavior suite is 354.
  Its local-analysis predicate and launch helpers remain private; existing
  engine debug adapters cross only DEBUG-gated forwarding methods. No endpoint,
  payload, SwiftData schema, persistence format, feature flag, navigation, copy,
  accessibility, layout, or release contract changed. Verification also replaced
  the shared presentation fixture's obsolete optional Species Reference
  transport stub with a type-correct inert 404, and corrected architecture
  oracles to require lifecycle-owned presentation reset and attempt invalidation
  rather than direct engine calls. The executable documentation contract now
  enforces submission-coordinator execution ownership.
- Twenty-fourth-slice candidate verification includes byte-stable repeated
  XcodeGen, project/resource and source-membership validation, event-routing
  source and adversarial checks, affected Swift parsing, and strict no-cache
  SwiftLint with zero violations. The complete iOS CI-tooling and Supabase
  tooling suites, all 26 executable documentation contracts, Markdown and
  recursive Supabase formatting, and whitespace validation pass. The supported
  Simulator `build-for-testing` wrapper stopped before invoking Xcode because
  this environment cannot inspect active `xcodebuild` processes, so this local
  verification claims no linked build or runtime-test result.
- A follow-up Pass 24 concurrency and documentation audit found no production
  defect. Direct comparison with the former `analyze` and `analyzeNonVisual`
  implementations confirmed admission-before-replacement, cancellation order,
  exact-attempt publication fences, and task registration parity. Secondary
  image-pipeline, Capture, Offline Sync, lifecycle, SwiftData, and AI guides now
  identify `InferenceLiveSubmissionCoordinator` as the live startup/task-launch
  owner and `InferenceLiveAttemptCoordinator` as the task-handle owner instead
  of attributing those responsibilities to the engine facade.
- The twenty-fifth slice extracted synchronous persisted-record startup from
  `InferenceEngine.load(from:)` into the singleton-free `@MainActor`
  `InferenceHistoricalLoadCoordinator`. The new owner sequences historical
  lifecycle admission, active-scan identity, live-media release, immutable
  record projection, legacy lookalike-cache reset scheduling, initial
  presentation publication, presentation/review generation capture, callback
  construction, and registered hydration scheduling. It creates no task,
  resolves no live dependency, and retains no managed `LocalScanRecord` after
  `load(from:)` returns. The engine preserves its source-compatible signature as
  a thin delegate. Four deterministic behavior cases lock publication before
  deferred hydration, Auth-fenced rejection without presentation mutation,
  replacement of a cancellation-ignoring prior decode, and required reset
  scheduling with the record's model container. Architecture oracles freeze the
  collaborator inventory, exact startup order, effect exclusions, facade
  delegation, and 600-line focused-owner ceiling. This slice reduces
  `InferenceEngine.swift` from 1,004 to 964 lines; the production coordinator is
  109 lines and its behavior suite is 350 lines. No endpoint, payload, SwiftData
  schema, persistence format, feature flag, navigation, copy, accessibility,
  layout, or release contract changed.
- Pass 25 follow-up review found no production parity or concurrency defect. It
  made the cancellation-ignoring operation gate private to the focused behavior
  suite and corrected the recorded engine and suite line counts. The companion
  documentation audit updated the system overview, memory/concurrency, image
  pipeline, Insight, SwiftData, API, Edge-modularization, agent, and Core AI
  guides to distinguish the synchronous load owner from the engine facade and
  registered hydration owner. The SwiftData example now snapshots the model
  container before constructing the projection. Complete current-source semantic
  compiler checks for production plus the new behavior suite, standalone
  architecture-test typechecking, affected Swift parsing, strict SwiftLint,
  repeated byte-stable XcodeGen, project/resource and source-membership checks,
  event-routing source and adversarial checks, the complete iOS CI-tooling
  suite, all 26 executable documentation contracts, Markdown and recursive
  Supabase formatting, and whitespace validation pass. The supported Simulator
  `build-for-testing` wrapper again stopped before invoking Xcode because this
  environment cannot inspect active `xcodebuild` processes, so no linked build
  or runtime-test result is claimed locally.
- The twenty-sixth slice extracted the engine initializer's internal owner-graph
  construction into the one-shot `@MainActor` `InferenceEngineAssembly`. The
  assembly is now the sole production constructor of the eighteen focused
  inference owners and preserves their exact construction order, injected
  collaborator edges, optional live fallbacks, and retention graph. It stores no
  mutable runtime state, starts no task, and performs no network, persistence,
  logging, filesystem, AppDI, or direct singleton work. `InferenceEngine` keeps
  its initializer signature and defaults unchanged, receives the completed graph
  as a local value, and continues to retain its twelve runtime collaborators as
  private properties; the assembly itself is not retained. This reduces
  `InferenceEngine.swift` from 964 to 881 lines; the production assembly is 204
  lines and its architecture suite is 258 lines, both below the 600-line review
  ceiling. The architecture suite freezes sole constructor ownership, exact
  ordering and dependency edges, exhaustive initializer input forwarding and
  consumption, stable initializer inputs, private facade retention, effect
  exclusions, and the focused-file ceiling. No endpoint, payload, SwiftData
  schema, persistence format, feature flag, navigation, copy, accessibility,
  layout, lifecycle, or release contract changed. Compiler-backed review caught
  and corrected a dropped `Visual` segment in the assembly dependency label
  before handoff; the architecture oracle now rejects that stale spelling and
  also restricts assembly consumers to the assembly file and engine facade.
  Final candidate verification passed exact facade/assembly/ focused-owner
  iOS-SDK typechecking with warnings as errors (using typecheck-only stand-ins
  for live adapters already covered by their focused suites), standalone
  architecture-suite typechecking, affected Swift parsing, strict SwiftLint, the
  constructor/consumer oracle, byte-stable XcodeGen, project and
  source-membership validation, event-routing and adversarial routing guards,
  the complete iOS CI-tooling suite, all 26 executable documentation contracts,
  recursive Supabase and changed-Markdown formatting, and whitespace validation.
  The supported Simulator `build-for-testing` wrapper stopped before invoking
  Xcode because this environment could not inspect active `xcodebuild`
  processes, so no fresh linked build or runtime-test result is claimed locally.
- The Pass 26 documentation reconciliation registered `InferenceEngineAssembly`
  in the Core root contract, system overview, and contributor directory map. It
  also corrected stale ownership claims in Capture Submission, camera,
  image-pipeline, feature-module, concurrency, and manager guidance: the engine
  is the stable observable facade; `InferencePresentationState` owns stored
  presentation values; `InferenceLiveSubmissionCoordinator` starts visual
  analysis; `InferenceLivePipelineCoordinator` owns encoded-empty refund
  handling; `InferenceHistoricalLoadCoordinator` owns historical projection; and
  `InferenceSpeciesPresentationCoordinator` routes admitted persistence work.
  The executable documentation contract now requires the assembly across every
  canonical ownership surface and rejects the superseded orchestrator, refund,
  historical-load, and background-write descriptions. This documentation-only
  follow-up changes no runtime, wire, persistence, navigation, or release
  behavior.
- The twenty-seventh slice partitions the stable inference facade without
  widening its twelve private focused-owner references. Pure source-compatible
  nested modality values and static adapters now live in
  `Inference/Facade/InferenceEngineCompatibility.swift`; the existing simulator
  and test API lives in two fully `#if DEBUG` diagnostic files and coordinates
  scenarios through one ephemeral support value returned by the facade's sole
  DEBUG factory. First-render timing now consumes the exact one-shot scan metric
  in `InferenceLiveSubmissionCoordinator` and routes logging through the
  pipeline benchmark adapter. Alternatives exhaustion now validates the exact
  case-insensitive scan and advances its review generation in
  `InferenceSpeciesPresentationCoordinator`. The established cloud-analysis
  phrase deck is owned by `ScanningPhrasePolicy` behind the unchanged engine
  adapter. This reduces `InferenceEngine.swift` from 881 to 585 lines, below the
  review ceiling; every new production file is also below 600 lines. Focused
  behavior tests cover mismatched/one-shot render metrics and exact/mismatched
  alternatives exhaustion, while a new architecture suite freezes the facade,
  compatibility, diagnostic, visibility, and delegation boundaries. The
  follow-up integration review also closes a legacy replacement gap: once a new
  visual submission is admitted, the lifecycle owner now discards its
  predecessor's ephemeral owner, queued visual context, and render timestamp
  before installing the replacement. This prevents a same-scan retry without a
  new clock from logging the prior tap interval. A second inference-wide review
  makes current-task retirement re-entrancy-safe: the attempt owner detaches and
  retains the exact displaced handle before synchronous durable callbacks, Auth
  drains cancellation-ignoring displaced work, and recovered-result commits
  cancel the displaced task before observable publication so caller cleanup
  cannot cancel an observer-installed replacement. Exact admitted queue-less
  responses also transfer their pending first-render clock from the temporary
  client identity to the server-assigned scan ID; stale callbacks cannot move or
  consume it. Focused overlap and architecture tests freeze each ordering. No
  payload, persistence, schema, navigation, copy, layout, accessibility, or
  release contract changes.
- Focused Core AI and Species Reference suites cover hydration replacement and
  stale-completion isolation, TTL/backoff policy, queue capacity and overflow,
  cancellation and Auth quiescence, ordered newest-action writes, public
  request/parse behavior, missing-description thumbnail compatibility, and
  architecture ownership. The local-analysis suite continues to cover category,
  phrase, cancellation, lifecycle, queue-handoff, and non-cooperative-provider
  behavior through the stable engine adapters. The live-request suite covers
  payload parity, descriptor alignment, upload order, callback forwarding, and
  stale-attempt rejection around its suspension points; the architecture suite
  locks the extracted owners and retired aggregate. The result suites cover
  persistence input parity, actor outcome classification, and stale-result
  isolation through both live engine paths. No JSON payload, SwiftData schema,
  navigation, or backend contract changed. `InferenceEngine.swift` now remains
  below the 600-line ceiling as a source-compatible observable facade; focused
  owner construction and execution responsibilities must not return to it.
- The Inference-wide source integration audit (2026-09-02) traced visual, audio,
  and Describe requests through result, recovery, hydration, writes, Auth, and
  exact queue completion. It repaired an existing reanalysis data-loss path:
  `InferenceScanReplacement` requires a typed persisted result and a distinct
  store-visible replacement, saves tags/collections/notes before deletion, and
  preserves the original on no-record outcomes or lookup/save failure. Scoped
  save rollback leaves unrelated user edits intact. The repository's existing
  deletion/outbox commit still owns destruction; its post-commit cleanup now has
  an optional completion handle so tests can await their own work.
- The post-audit integrity review closes three accepted-result races without
  changing a wire or persistence contract. Auth admission now advances a
  dedicated live follow-up authorization epoch before cancelling inference, so a
  suspended queue deletion that ignores cancellation cannot mint a permit.
  Shared response preparation is pure and compares the provider `scan_id` with
  every supplied or durable client ID before either persistence path can act;
  the queue-less nonvisual compatibility path continues to accept its server-
  assigned ID. The service projects generated entitlement wire values into the
  checked-Sendable `EntitlementStateSnapshot` domain value instead of extending
  generator-owned DTOs. The completion boundary rechecks the settlement against
  the prepared result ID. Foreground and background paths carry the resulting
  `InferenceResponseSettlement` through successful local persistence and apply
  it only after any required exact main-context queue deletion. Offline Sync
  owns the account-lease-protected entitlement, usage, and funding-reservation
  effects. Its injected `InferenceFundingReconciliationOwner` retains all
  accepted leases, coalesces trailing passes, and owns the task that Auth
  cancels and awaits before session replacement. Deterministic response and
  suspended-deletion tests plus source architecture guards freeze the new
  identity, ordering, task-ownership, and generator-boundary invariants.
- The audit added atomic, cancellation-aware resource leases shared by Swift
  Testing and the Capture XCTest base. Queue scopes restore the previous model
  context; individual cases still own other state restoration and task
  completion. Generic Insight/repository fixtures no longer call production
  startup configuration. Enqueue fixtures await `onQueued` with automatic sync
  disabled, pure projection tests delete only their isolated local record, and
  lifecycle admission tests inject inert consent/maintenance callbacks. The live
  lifecycle sequence and durable scheduler call remain unchanged.
- The follow-up review restored executable scheduler dispatch-policy coverage
  lost when the uncontrolled lifecycle replay fixture was removed.
  `OfflineJobScheduler.DrainOperations` injects only the six existing manager
  effects; production still uses the same shared scheduler and call order.
  `OfflineJobSchedulerTests` suspends each async effect, proves inference replay
  is reached in sequence, and checks future-wake admission and offline
  cancellation on a fixture-owned scheduler. It does not claim a real durable
  staged claim or provider replay. The lifecycle background-phase fixture also
  restores its standard-preference timestamp.
- New replacement and integration suites cover durable metadata safety,
  no-record/missing-ID original retention, Auth waiting for cancellation-
  ignoring live results, and suspended queue-backed results losing to
  cancellation or generation replacement across all three modalities. Shared
  gate tests cover atomic overlap, cancelled waiters, throwing scopes, and stale
  release. Byte-stable XcodeGen, project/source membership, event-routing and
  build-workflow guards, changed-source parsing, strict affected-production
  lint, Markdown formatting, and diff checks passed. Focused frontend
  typechecking also passed for 17 test/support files against current
  inference/lifecycle/scheduler declarations and cached unchanged dependencies.
  The scheduler's complete current body also passed isolated typechecking. These
  are bounded compiler checks, not full-target compilation or runtime
  acceptance. The fresh generic Simulator build and `build-for-testing` still
  fail before compilation on denied SwiftPM manifest-diagnostics cache writes.
  Full-engine current-source compilation also encounters the environment's Apple
  macro sandbox restriction. Simulator discovery works. The expanded
  [focused matrix](../development-guides/08-testing-strategy.md#live-inference-requestresult-verification)
  and complete `merianTests` target were still awaiting a successful
  current-source build at that local handoff; stale cached products are not
  candidate evidence. The later merged-CI confirmation below supersedes this
  local verification hold. No deployment or external publication was performed.
- A clean-checkout closeout attempt for committed candidate `28831c812` on
  2026-09-02 repeated byte-stable XcodeGen, project/source membership,
  event-routing and build-workflow guards, parsing of all 39 changed Swift
  files, and strict lint of the ten changed production files successfully.
  Generic Simulator build and `build-for-testing` used separate fresh derived-
  data directories, locked packages, and the CI package-cache flags. Both exited
  74 during SwiftPM manifest resolution on the same denied diagnostics-cache
  writes. Simulator selection returned an available device, but `xcodebuild`
  also reported a CoreSimulatorService connection failure. No candidate test
  products were created, so this local attempt did not execute the focused
  matrix, complete unit target, or manual checks.
- The user subsequently confirmed that the Inference work was merged and all
  GitHub Actions checks passed. That merged-CI confirmation is the accepted
  baseline for proceeding to Core Network; this workspace's local build
  restrictions are not a project-level blocker. The CI run was not independently
  inspected here, and no manual device verification is claimed. New unmerged
  Network changes still need their own candidate CI validation.
- The Core Preferences slices moved `AppSettings`, the Explore-share and
  field-note bridges, and the legacy species-name store into focused
  `Core/Preferences` owners. SwiftData preferred-name CRUD, normalization and
  conflict policy, exact PostgREST values, the narrow injected live client, and
  contained single-flight cloud reconciliation now live under
  `Core/Data/SpeciesPreferences`. The split preserves public call sites, table
  and JSON contracts, lifecycle triggers, tombstone semantics, and persisted
  keys. It also closes invalid `gridColumns` persistence, duplicate normalized
  scientific-name handling, failed-fetch success reporting, failed-save marker
  loss, equal-time tombstone inconsistency, clock-skew freshness suppression,
  unstable equal-time page ordering, post-upsert account-lease invalidation, and
  mid-flight trailing-sync coverage. The final audit additionally repairs a
  crash window that could leave an active SwiftData row and pending tombstone
  for one key, makes tombstone timestamps and acknowledgements monotonic, and
  refetches and re-bounds local state after an upsert suspension so an earlier
  remote page cannot overwrite a mid-flight edit. The focused
  `SpeciesPreferenceLocalRecovery` owner keeps those rules out of the
  coordinator and preserves the 600-line ceiling. Accepted account deletion now
  purges every `CurrentSchema` model and the classified account-derived defaults
  while preserving device settings and recovery fences, then resets observable
  settings, legacy gamification, the generation-fenced app badge, and RAM image
  state through one injected runtime owner. Direct owner tests lock the
  gamification reset and a suspended unread-count result across deletion; keyed
  process-state traits prevent peer suites from racing either singleton. This
  synchronous boundary does not claim whole-store replacement or unreferenced
  app-container file traversal, which requires a separate storage-owner
  inventory. The subsequent ownership slice moved the unchanged defaults-key
  registry into Core Preferences and moved account-deletion recovery state plus
  Keychain key names into Core Security. Mirrored suites and architecture guards
  enforce injected dependency ownership and the 600-line production ceiling.
  Byte-stable XcodeGen, project/source membership, event-routing, tooling,
  documentation, parsing, strict lint, and focused production/test typechecking
  passed. A fresh iOS 26.4 Simulator `build-for-testing` compiled every app and
  test target, and the 107-case focused matrix passed across 12 suites. Repeated
  complete-`merianTests` launches then stopped before test execution when
  CoreSimulatorService disconnected; no new complete-target pass is claimed.

Implemented Core Network slices:

- The 2026-09-04 Network-wide closure audit confirms the final 17 endpoint and
  six Transport owners, the single pinned-session/Auth boundary, and the
  extracted-owner 600-line production ceiling. It removes the unused
  self-recursive private `performPublicGETRequest`, leaving the client façade at
  545 lines, and adds that declaration to the retired-source guard. The audit
  also fixes a pre-existing cancellation leak in owned-scan persistence polling:
  cancellation now throws through Explore publication, Ask the Community, and
  Field Chat preflight instead of becoming deferred recovery, including when it
  arrives immediately after a successful status response. A deterministic
  transport test cancels before the first 250 ms retry window expires and proves
  recovery cannot issue a second status request. Reusable legacy and scoped
  URLProtocol fixtures also move unchanged from the aggregate client suite into
  `Core/Network/NetworkTransportTestSupport.swift`; the architecture guard locks
  that shared test owner. Request and response bytes, endpoint signatures, retry
  eligibility/delays, Auth and idempotency rules, DTO/schema, persistence,
  backend, and deployment contracts do not change. Closure verification
  typechecked all 980 current production sources and the affected
  aggregate/support/publication test sources, then executed all 50 current
  Network architecture cases across eight suites. Byte-stable XcodeGen after
  regeneration, project/source membership, routing and CI-tooling, DTO,
  transport-security, strict lint, recursive parsing, Supabase tooling,
  documentation, formatting, and whitespace gates passed. Fresh device-specific
  and generic Simulator builds stopped before compilation on
  CoreSimulatorService disconnection and nested SwiftPM sandbox denial, so the
  preceding 2,809-case XCResult remains the latest full-target runtime evidence.
- The 2026-09-04 final transport-ownership pass moves the configured production
  session, certificate-pin policy, TLS delegate, and DEBUG session seam into
  `Transport/PinnedNetworkTransport.swift`, while
  `Transport/AuthenticatedTransportDispatcher.swift` owns per-attempt Auth
  leasing and headers, transition/session validation, constrained-network
  signaling, dispatch, and its file-local upload delegate. The main client
  constructs one pinned transport, injects that same instance into the
  dispatcher, and shrinks from 949 to the pass's 600-line ceiling. The
  cross-slice audit now freezes six focused Transport owners and prevents
  session/TLS, upload-delegate, or Auth-attempt ownership from drifting back
  into the façade. A follow-up replaced the unsynchronized lazy production
  session with lock-backed first-use initialization and narrowed hostname
  admission to `supabase.co` plus true subdomains. Seven pinned-transport tests
  and one dispatcher test cover production configuration, rotation-tolerant pin
  validity, exact host admission, concurrent single-session initialization,
  full-chain matching and missing/empty/unmatched or platform-untrusted chain
  rejection, injected dispatch, value-only account resolution, and exact request
  construction. Native typechecking and deterministic execution passed all eight
  focused cases and all 50 affected architecture cases; byte-stable XcodeGen,
  project/source membership, event-routing, CI-tooling, transport-security,
  strict SwiftLint, Swift parsing, documentation-contract, Markdown, and
  whitespace gates also passed. Fresh Xcode attempts stopped before compilation
  because this host denied SwiftPM manifest-cache writes and
  CoreSimulatorService was unavailable, so the prior 2,809-case XCResult remains
  the latest Simulator/full-target runtime baseline. Request bytes, routes,
  retry/Auth semantics, DTO/schema, persistence, hosted service, and deployment
  behavior are unchanged. The TLS hardening deliberately changes unreadable or
  platform-untrusted Supabase server-trust challenges from default
  fallback/pin-only acceptance to fail-closed cancellation; unmatched chains
  were already cancelled.
- The 2026-09-04 authenticated-request-executor pass moves one logical request's
  recursive attempt state, cancellation checkpoints, request/header
  construction, bounded transient/route/5xx replay, response mapping, and
  injected Auth/entitlement/consent effects into
  `Transport/AuthenticatedRequestExecutor.swift`. The main client retains the
  only pinned URLSession, DEBUG overrides, per-attempt Auth headers and account
  lease, constrained-network header, upload delegate, and post-dispatch
  transition/session validation. `MerianNetworkClient.swift` shrinks from 1,216
  to 949 lines and its non-growth cap drops from 1,250 to 975. Nine
  deterministic executor tests cover body/account preservation, ordinary and
  transition-owned refresh, missing-guest replacement, payment and consent
  effects, the 1/2/4-second route schedule, per-attempt body release across
  transient replay, and cancellation. The cross-slice audit freezes four
  Transport owners while requiring the other three to remain stateless and
  preventing the executor from constructing a second session, client singleton,
  or detached task. A follow-up review corrected the successful-attempt
  transport fake and the architecture guard's `/functions/v1/` source token; a
  native harness then ran all nine executor and five architecture cases with 14
  passes. The fresh Xcode attempt remained blocked before compilation by the
  host SwiftPM sandbox and unavailable CoreSimulatorService, so the earlier
  2,809-case XCResult remains the latest full-target runtime baseline. No
  request bytes, routes, retry counts, Auth effects, DTO/schema, persistence,
  hosted service, or deployment behavior change.
- The 2026-09-03 transport-policy pass adds three focused production owners
  under `Core/Network/Transport/`: `EdgeFunctionRoutePolicy` owns validated Edge
  URL construction, unavailable-route evidence, and the unchanged 1/2/4-second
  retry schedule; `EdgeFunctionErrorPolicy` owns stable-code and
  refreshable-Auth response classification; and
  `AuthenticatedRequestRetryPolicy` owns the exact safe-read/idempotency-aware
  allowlists, retry-account binding, and pure Auth recovery decisions, including
  an `UnauthorizedRefreshTarget` value that the stateful client applies. The
  1,216-line `MerianNetworkClient.swift` still owns all mutable session/Auth
  state, performs refresh/regeneration and retries, maps cancellation, and owns
  upload delegates. The architecture audit now has five cases, requires exactly
  these three policy files, extends the 600-line ceiling to `Transport/`, and
  lowers the remaining-client ceiling to 1,250 lines. Eleven mirrored policy
  tests rehome five existing route/replay/Auth/account cases and add six
  deterministic URL, schedule, stable-code, and Auth-evidence cases. A fresh
  generic Simulator `build-for-testing`, focused selector matrix with 202 passed
  XCResult cases, and complete 2,809-case `merianTests` target pass with zero
  failures, skips, or expected failures. Final review then replaced the policy's
  async injected-refresh executor with the pure `UnauthorizedRefreshTarget` and
  kept both refresh effects in the main client. The strengthened source guard
  rejects actor/async/global-effect policy dependencies and locks the client's
  ordinary and transition-owned application branches. A post-fix arm64 generic
  Simulator `build-for-testing` compiled the complete app and test bundles, and
  a native probe executed both target choices; CoreSimulatorService was
  unavailable for a post-fix runtime rerun, so the preceding XCResults remain
  the green baseline rather than post-fix execution evidence. No request bytes,
  routes, attempt counts, Auth effects, API/DTO/schema, persistence, hosted
  service, or deployment behavior changes. The following slice separated the
  stateful authenticated request executor while preserving the single
  pinned-session/Auth boundary.
- The 2026-09-03 Core Network integration audit reconciles all 17 endpoint
  extensions with the shared client, Inference, Media, Recovery, focused tests,
  and generated project. At that checkpoint, a four-case
  `CoreNetworkIntegrationArchitectureTests` suite freezes the exact endpoint
  inventory, prevents duplicate aggregate endpoint declarations, applies the
  600-line review ceiling across all extracted owners, and places a temporary
  1,500-line non-growth cap on the remaining 1,432-line shared transport. It
  also freezes the disjoint safe-read and idempotency-aware replay sets,
  requires exactly one endpoint owner for every classified route, and records
  the exact reviewed owners of URLSession/private transport, Auth,
  consent/profile request context, recovery Species Dictionary lookup, and
  detached inference preparation. Follow-up verification removed the stale
  `get-filtered-discovery-feed` safe-read classification because iOS has no
  endpoint owner or caller for that backend route; its Edge Function and backend
  contract remain unchanged, and the strengthened guard now rejects any future
  unowned classification. The guard and complete `merianTests` target passed on
  the booted iOS 26.4 Simulator after a fresh full app/test-target compile. The
  resulting XCResult records 2,802 passed test cases across 354 suite nodes,
  with zero failures, skips, or expected failures; 214 dynamically parameterized
  tests account for 2,198 argument runs. No payload, endpoint, retry, Auth,
  schema, persistence, feature, hosted service, or deployment behavior changed.
  The later transport-policy slice above completes the stateless part of that
  recommendation.
- The 2026-09-03 inference-network pass moves the pinned-session prewarm and
  five existing Identify entry points into the 392-line
  `Endpoints/MerianNetworkClient+Inference.swift`. Immutable request values and
  stateless JSON, inline-media, staged-owner, and recoverable-conflict concerns
  live in four `Core/Network/Inference/` files of 25–216 lines. The main client
  shrinks from 2,025 to 1,432 lines and retains private endpoint URL, session,
  Auth lease, classified refresh, retry, URLSession cancellation, and
  upload-progress implementation behind five narrow value/prepared-request
  bridges. Public method signatures/defaults, consent ordering, entitlement
  protocol, request keys, telemetry and timeline JSON, 3.6 MB inline body and
  WAV limits, stable idempotency, object-owner fencing, `409` policy, body-sent
  callback, and the queue-backed 15-second/no-transient-transport-replay versus
  direct 90-second/one-replay behavior are unchanged. Handler-owned Auth
  refresh, route propagation, and idempotent 5xx handling remain shared. The
  second-pass review replaced three raw detached blocks with the
  cancellation-propagating `.inferenceRequestPreparation` bridge, added
  cancellation checks around serialization and inline-audio reads, and made both
  byte accumulators overflow-safe without changing accepted payload limits. No
  backend, DTO, schema, persistence, feature-flag, UI, hosted mutation, or
  deployment change is included.
- Twenty-seven inference regressions move from the aggregate network suite into
  `InferenceEndpointTransportTests`, `InferencePayloadBuilderTests`,
  `InferenceMediaPolicyTests`, and `InferenceRequestPolicyTests`, shrinking the
  aggregate from 2,907 to 1,308 lines. The architecture suite guards focused
  ownership, private transport, the detached-work boundary, the 600-line
  ceiling, and exact rehome. A new cancellation case verifies pre-dispatch owner
  cancellation, while prewarm now locks its header/body-free `OPTIONS` shape.
  The critical-result validator retains its three existing foreground/retry case
  names under `Inference Endpoint Transport`; adversarial fixtures reject their
  retired aggregate owner without changing the protected-case count. See the
  [ownership guide](../../apps/ios/Merian/Core/Network/README.md#inference-endpoints-payloads-and-policies)
  and
  [focused matrix](../../apps/ios/Merian/Core/Network/README.md#inference-verification).
- Current-candidate verification passes byte-stable XcodeGen, project/resource
  validation, recursive source membership, the iOS CI-tooling suite, Swift
  parsing, repository-wide strict SwiftLint, the Edge DTO contract, Supabase
  skill link validation, and the 25-test documentation contract. A generic
  Simulator build and the complete unit-test `build-for-testing` action both
  succeed with signing disabled. Runtime execution passes 57 focused inference
  tests in seven suites, 95 adjacent Auth/queue/publication/recovery tests in
  six suites, the final 53-test Core Network matrix, and the complete
  `merianTests` target. The complete-result XCResult records 2,802 passed test
  cases across 354 reported suite nodes, with zero failures, skips, or expected
  failures; 214 dynamically parameterized tests account for 2,198 argument runs.
  The review caught a publication fixture that asserted an exact latitude after
  constructing a nil latitude; the fixture now accepts an explicit coordinate
  while preserving nil as its default, and both focused and full reruns pass.
  Repository-wide strict lint later exposed one unrelated redundant optional
  `= nil` in `SimilarSpeciesGallery`; removing it preserves the synthesized nil
  default, and a post-fix build plus 42 relevant Core Network and Species
  Reference tests pass. CoreSimulator recovered after the temporary service
  outage, so no runtime hold remains. Documentation closeout distinguishes
  endpoint-owned request-preparation cancellation from main-client URLSession
  cancellation and includes `DetachedWorkTests` in the canonical inference
  matrix. No manual device, live backend, deployment, or external-publication
  action is claimed.
- The 2026-09-03 scan-publication and owned-recovery pass moves the two direct
  scan-ID publication methods into the 153-line
  `Endpoints/MerianNetworkClient+ScanPublication.swift`; record-based Explore
  and Ask-the-Community overloads, Field Chat preflight, status polling, payload
  construction, and missing-row orchestration into the 586-line
  `Recovery/MerianNetworkClient+OwnedScanRecovery.swift`; the unchanged 71-line
  recovery payload and 44-line admission policy into focused Recovery owners;
  and local-media planning/upload plus count/byte/error policy into 454- and
  99-line Media owners. The main client shrinks from 3,312 to 2,025 lines and
  exposes only a value-returning owner-ID bridge into its existing private Auth
  boundary. No new session, transport, singleton, protocol, task owner, retry,
  JSON field, endpoint, persistence, UI, or backend behavior is introduced.
- Twelve aggregate regressions retain their selectors under
  `ScanPublicationEndpointTests`, `ScanPublicationEndpointTransportTests`,
  `OwnedScanRecoveryPolicyTests`, and `ScanPublicationMediaRestorePolicyTests`,
  using isolated endpoint fixtures or deterministic policy inputs.
  `ScanPublicationRecoveryArchitectureTests` protects the direct endpoint,
  recovery, media, Auth-bridge, rehome, and 600-line boundaries. The
  critical-result validator and its adversarial fake result tree now require all
  nine protected cases under their new suite/type owners. Existing shared Auth,
  DTO, and feature-state tests keep their owners. See the
  [ownership guide](../../apps/ios/Merian/Core/Network/README.md#scan-publication-and-owned-recovery)
  and
  [focused matrix](../../apps/ios/Merian/Core/Network/README.md#scan-publication-and-owned-recovery-verification).
- Verification passes byte-stable XcodeGen, project/source membership,
  event-routing and iOS CI-tooling gates, current-source parsing, strict
  affected production/test lint, and compiler typechecking of all 969 current
  iOS production sources. A testable module emitted from those same sources, and
  all five new suites typecheck against it. That review also replaced one nested
  Swift Testing `#require` in the transport suite with sequential URL and
  response validation. The first generic Simulator build exposed a missing
  private `EdgeErrorPayload` declaration during compilation; the declaration was
  restored to the main transport owner before the successful full-source
  typecheck. At that handoff, a subsequent ordinary build could not pass SwiftPM
  resolution because the sandbox denied manifest-diagnostics cache writes, and
  CoreSimulatorService was unavailable. The later combined-candidate build and
  runtime matrix recorded above supersedes that local hold; manual
  publication/recovery checks are still not claimed. Documentation follow-up
  reconciles Insight cloud-readiness tests, Hashtags transport touchpoints, the
  Recovery/Media test map, and Auth-boundary wording with the final owners.
  Documentation contract, Deno/Markdown formatting, and whitespace checks also
  pass. No hosted call, deployment, or external publication was performed.
- The 2026-09-03 account-deletion/recovery pass moves six existing methods into
  `Endpoints/MerianNetworkClient+AccountDeletion.swift`, unchanged receipt and
  v2 payload DTOs into `AccountDeletionAPIModels.swift`, and pure admission into
  `AccountDeletionRecoveryValidation.swift` and
  `Decoding/AccountDeletionResponseDecoder.swift`. The main client shrinks from
  3,659 to 3,312 lines; each new production owner is below 600 lines. Two
  fixed-route, nonescaping bridges expose only response bytes/status and retain
  private Auth/session ownership. Legacy nil-body and validation order, exact v2
  proof-key omission, required provider disposition, status/expiry rules,
  20-second public recovery timeout, post-read 64 KiB bound, one two-second
  retry, and cancellation policy remain unchanged. Transition admission,
  Keychain markers/proofs, local sign-out/purge, and retirement stay with
  `SupabaseManager`, Core Security, and `AppDIContainer`. There is no backend,
  schema, persistence, feature-flag, UI, or release-control change.
- Eight aggregate tests move to account-deletion endpoint/recovery and DTO
  suites, with isolated per-client fixtures. Seven focused suites now cover
  payloads, required/optional fields, fixed-clock syntax/expiry, receipt
  phase/status/version rules, Auth refresh and stale-owner refusal, public
  recovery retry/bounds/cancellation, and source ownership. The aggregate drops
  from 3,181 to 2,907 lines, including empty-line cleanup; shared Auth tests and
  protected CI selectors remain in place. V2 success uses exact payload and pure
  decoder tests plus existing injected manager workflow tests, not a new Auth
  bypass. Real-session integration remains a separate requirement. See the
  [account-deletion ownership guide](../../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-ownership)
  and
  [focused matrix](../../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-verification).
- Account-deletion verification passes iOS frontend typechecking for 28 current
  production sources and 14 test/support files against cached dependencies, 53
  native pure/architecture tests in seven suites, and 35 focused deletion
  protocol/adapter/handler/source-contract tests. The iOS CI-tooling and Edge
  DTO gates, Swift parsing, strict affected-file lint, project/source
  membership, Markdown and Edge-fleet formatting, documentation links/selectors,
  and whitespace checks pass. XcodeGen is byte-stable; removing only the 13 new
  source-file references reproduces the baseline project. Exact comparisons
  preserve the remaining main-client code, private public-recovery transport,
  seven DTO declarations, six method signatures, and eight rehomes, allowing
  only fixture adaptation, the added nil-body oracle, and test whitespace
  cleanup. `project.yml` and the retained deletion workflow/Function
  implementations are unchanged. Typecheck/native copies match current source
  apart from test imports and end-of-file whitespace.
- The post-outage review confirmed the extraction and eight rehomes survived;
  verification and documentation had not finished. Independent read-only
  production and test reviews found no parity or security regression. The
  follow-up added the missing nil-body oracle, corrected throwing test closures
  found by compilation, and compared URL error codes rather than
  URLSession-added error metadata. Documentation review corrected the legacy
  absent-body contract wording and distinguished shared DTOs from the three
  private endpoint payloads. Fresh generic Simulator and full-unit
  `build-for-testing` attempts stop before compilation with exit 74 at the
  restricted SwiftPM manifest diagnostic cache; CoreSimulatorService also
  remains unavailable. Focused/full iOS runtime and manual deletion integration
  are not claimed. Local checks use synthetic fixtures only; no live account
  action, deployment, or external publication is part of this pass.
- The documentation follow-up found a pre-existing cross-contract failure that
  the isolated suites do not expose. The v2 `safe-delete` prepare handler omits
  `manual_provider_revocation_required`; native `AccountDeletionReceipt`
  requires it and therefore maps the persisted server preparation response to
  `invalidResponse` before `SupabaseManager` can write
  `capability_prepared_pending` or dispatch commit. Independent read-only review
  confirmed the handler and required-field decode both predate the extraction;
  native fixtures add the missing field while backend tests inspect the handler
  separately. Documentation now marks v2 round-trip integration and promotion
  incomplete, corrects the actual marker-before-Keychain-envelope ordering,
  distinguishes intended workflow from checked-in behavior, and centralizes the
  authorized disposable-account checklist in the
  [Network matrix](../../apps/ios/Merian/Core/Network/README.md#account-deletion-integration-checklist).
  This record does not choose or implement the necessary API-contract fix.
- The 2026-09-03 account-deletion contract follow-up resolves that source-level
  mismatch without changing the Edge response. Native
  `AccountDeletionPreparationReceipt` owns the exact non-destructive four-field
  shape, while `AccountDeletionReceipt` remains strict about
  `manual_provider_revocation_required` for accepted deletion and public
  recovery. `AccountDeletionResponseDecoder.decodePreparation` admits only
  successful HTTP-200 prepared/protocol-v2/future-expiry responses. The Deno
  handler test and native DTO/decoder suites consume one identity-free JSON
  fixture, and a native negative test proves that preparation cannot masquerade
  as an accepted receipt. A small injected `SupabaseManager` seam preserves and
  tests prepare → exact transition-context verification → prepared marker →
  intake marker → commit → accepted-result context verification. Negative cases
  prove stale preparation context or either marker failure cannot dispatch
  commit and preserve the persistence-error classification; stale commit context
  retains `signOutSessionChanged`. Focused native and backend suites, generic
  Simulator build, strict affected-file lint, Swift parsing, project/source
  membership, XcodeGen stability, and whitespace checks pass. The final complete
  `merianTests` `test-without-building` run executed 2,788 tests: 2,778 passed,
  while ten parameterized transport-replay cases across unrelated endpoint
  suites were killed by the test runner. The failing set rotated from the
  preceding full run, and all ten exact selectors—including the account-deletion
  recovery case—passed together when rerun in isolation. The focused
  account-deletion matrix is green, but this record does not claim a green
  complete target. No handler payload, schema, persistence format, deployment,
  live deletion, or external publication changes; authorized real-session and
  older-client release evidence remain outstanding.
- The 2026-09-03 media storage/upload pass extracts six existing client method
  variants into five focused files: `MerianNetworkClient+MediaStorage.swift` (65
  lines), `MediaStorageAPIModels.swift` (43), and `Media/`'s
  `MerianNetworkClient+MediaUploads.swift` (59), `PresignedMediaUpload.swift`
  (44), and `StagedVideoUploadPlan.swift` (91). The main client shrinks from
  3,908 to 3,659 lines. A nonescaping account-bound encoded-body bridge
  preserves configuration → frozen UUID → encoding → private transport, while
  two value-only PUT bridges retain the same private session and file-backed
  upload. DTOs, all six method signatures, exact signed headers, HTTP-200-only
  success, validation order, video count/byte caps, 30-second endpoint
  deadlines, error propagation, refresh/replay/cancellation policy, and
  sequential foreground video behavior remain unchanged. Queue manifest and
  background-task authority, inference attempt fencing, the then-local
  `LocalImageLoader` scan-image repair workflow, Profile avatar promotion, and
  main-client publication/restore orchestration do not move in that storage
  slice; the later scan-publication slice above moves the publication owners,
  and the later Core Data Image Loading slice below moves scan-image repair out
  of `LocalImageLoader`, without changing these primitives. No API, schema,
  persistence, backend, feature-flag, UI, hosted mutation, or deployment change
  is included.
- Six aggregate regressions move intact to `MediaStorageEndpointTests`,
  `ScanImageCloudEndpointTests`, and `StagedVideoUploadTests`, shrinking the
  aggregate from 3,448 to 3,181 lines. Per-client fixtures and unique disposable
  file names replace shared overrides and fixed names. Nine focused suites cover
  wire mapping, current-account refusal, encoding order, raw/optional values,
  decoding errors, refresh/request identity, ambiguous-replay refusal, signed
  header/status policy, raw Data/file errors, missing or changed files, local
  fallback, whole-input planning, count/byte caps, and signing/PUT failures.
  Source guards protect private transport, retained workflows, DTO ownership,
  file-backed transfers, and rehomes. The critical-result gate now requires
  `StagedVideoUploadTests/testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning`
  under `Staged Video Uploads`; its adversarial fixtures reject the retired
  aggregate owner. Read-only review found and corrected one new test oracle: an
  explicit expected owner does not bypass the transport's current-session
  resolution. Success cases retain a current mock identity, and the nil-current
  case now requires `signOutSessionChanged` with zero dispatch. No further
  material production parity or encapsulation finding remained.
- Verification passed current-source iOS frontend typechecking for 24 production
  copies, all 14 endpoint owners, and focused Network suites against cached
  unchanged dependencies; 88 native pure model/decoder/cache/policy/
  planning/architecture tests in 14 suites; parsing of all 20 affected Swift
  files; strict lint of the 19 affected non-aggregate files with zero
  violations; project/source membership; and the complete
  `make test-ios-ci-tooling` gate. The Edge DTO contract gate, 65 signing/
  lifecycle-registration/image-repair unit tests, and both handlers' frozen
  entrypoint checks also pass without hosted calls. Exact comparisons preserve
  the main-client and aggregate remainders and all six rehomes, allowing only
  fixture/unique-name/UTF-8 convenience and whitespace changes. XcodeGen is
  byte-stable; removing only references to the 16 new source files and two new
  `Media` groups reproduces the pre-slice project hash. `project.yml` is
  unchanged. The 24 production copies, four native test/fixture copies, and
  selected staging dependency declarations/methods match current source.
  Markdown and Edge-fleet formatting, local links/anchors, focused selectors,
  command-block syntax, and whitespace checks pass.
- The
  [media storage matrix](../../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-verification),
  shared matrices, native inventories, testing strategy, API contracts, and
  Function READMEs now describe the new owners. They distinguish the queue's
  complete signing-response checks from foreground video's unchanged count
  check, and raw PUT rejection from caller-owned re-signing. The image-pipeline
  guide also corrects existing documentation drift: ambiguous metadata
  persistence preserves a promoted object instead of unconditionally deleting
  it. These are ownership and accuracy corrections, not backend policy changes.
- Fresh generic Simulator and full-unit `build-for-testing` attempts stop before
  compilation with exit 74 because SwiftPM cannot write its manifest diagnostic
  cache; CoreSimulatorService is also unavailable. No fresh candidate iOS test
  products were produced, so focused/full iOS runtime and manual integration
  remain unrun. Native/source checks and cached-dependency typechecking are
  supplemental, not iOS transport, background transfer, or real-session
  account-switch acceptance. These local restrictions do not undo the accepted
  merged baseline; this new candidate still needs its own CI/runtime evidence.
- The media-storage second pass found no production regression. It corrected the
  signing test's name and documentation to describe explicit/resolved
  payload-owner mapping, not live Auth lease enforcement; the existing
  `AuthTransitionFoundationTests` exact-session lease,
  `AuthTransitionPolicyTests` transition-admission, and
  `AuthenticatedRequestRetryPolicyTests` retry-account suites remain the pure
  state/policy owners. The focused matrix now includes all three. A private
  per-session held-request transport adds task-owned cancellation coverage for
  both Data and file PUTs, preserving raw `URLError.cancelled` and requiring the
  underlying request to stop. Independent start/completion/stop bounds and
  session invalidation on completion timeout prevent a cancellation regression
  from hanging the suite. These are test and documentation fixes; production
  source remains unchanged in the second pass.
- Second-pass verification repeated current-source iOS frontend typechecking,
  all 88 native pure/source tests, the complete iOS CI-tooling gate, the Edge
  DTO gate, and 65 backend unit tests. A supplemental native Foundation probe
  exercises both held-request cancellation paths and an unfinished completion
  signal's watchdog using the same private test helper; its two test functions
  bring the native run to 90 tests in 15 suites. That probe uses Foundation
  directly, not the app client or live Auth. Strict lint, Swift parsing,
  project/source membership, byte-stable XcodeGen, exact rehome/source-copy
  comparisons, Markdown/Edge-fleet formatting, documentation references, and
  `git diff --check` also pass. At that second-pass handoff, fresh generic
  Simulator and full-unit `build-for-testing` attempts stopped before
  compilation with exit 74 at the restricted SwiftPM manifest cache, and
  CoreSimulatorService was unavailable. The later combined-candidate build and
  runtime matrix recorded above supersedes that local hold; manual integration
  remains unrun.
- Documentation follow-up makes the remaining
  [media storage integration checklist](../../apps/ios/Merian/Core/Network/README.md#media-storage-integration-checklist)
  explicit: real Data/file bytes and stored length, foreground video failure
  recovery, task cancellation versus live-session fencing, background
  continuation, avatar/image-repair consumers, and publication restore. The
  testing strategy distinguishes Data-body assertions from file-upload mocks and
  source guards; neither file mocks nor the native Foundation probe prove
  received storage bytes. The codebase map identifies the file-private
  cancellation test helpers, and the offline-sync guide links foreground
  planning to Network without moving queue authority. This follow-up changes
  documentation only and adds no fresh runtime or deployment evidence.
- The 2026-09-03 enrichment/export/product-feedback pass extracts five thin
  methods into three stateless owners:
  `MerianNetworkClient+ScanEnrichment.swift` (59 lines),
  `MerianNetworkClient+Exports.swift` (22), and
  `MerianNetworkClient+ProductFeedback.swift` (22). The main client shrinks from
  3,984 to 3,908 lines. A narrow prepared-JSON bridge preserves enrichment's
  configuration → serialization → UUID-key validation → private transport →
  plain-decoder sequence without re-encoding bytes or widening session/Auth
  access. Context's configuration-before-no-op behavior, optional/raw fields,
  hand-written enrichment DTOs, 15-/30-second deadlines, canonical enrichment
  idempotency, body-ignored export/feedback success, and existing refresh,
  replay, and cancellation policies remain unchanged. Capture/AI/Settings/
  Identify retain their scheduling, persistence, presentation, and request-model
  owners. Export remains launch-gated; there is no API, schema, feature-flag,
  hosted mutation, or deployment change.
- Four aggregate regressions move to `ScanEnrichmentEndpointTests` and
  `ExportEndpointTests`, shrinking the aggregate from 3,559 to 3,448 lines. The
  survey endpoint regression moves from Settings to
  `ProductFeedbackEndpointTests`; all five method selectors and assertions are
  retained with isolated per-client transport. Settings' `FeedbackSurveyTests`
  now keeps only its three prompt/cooldown tests and removes shared network
  overrides. New request/transport coverage checks raw scopes and optional
  context, serialization-before-UUID/cancellation, explicit-key enrichment
  projection and decoding errors, constructor normalization/metadata, ignored
  2xx bodies/statuses, bounded keyed replay, unkeyed mutation replay refusal,
  refresh, cancellation, and prepared-body identity.
  `EnrichmentExportFeedbackBoundaryTests` guards the three source owners,
  unchanged DTO locations, private transport, and rehomes. No protected
  critical-result selector changes owner. The
  [focused matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification),
  shared endpoint matrices, caller READMEs, Core manager/codebase inventories,
  testing strategy, and API references now name the owners. The API reference
  also documents the existing Community feedback route; no wire semantics
  change.
- Independent pre-/post-edit contract review found no material parity or
  transport-encapsulation defect. Verification passed current-source iOS
  frontend typechecking for 19 production source copies, all 13 endpoint owners,
  and focused Network/feedback suites against cached dependencies; 63 native
  pure model/decoder/cache/architecture tests in ten suites; Swift parsing of
  the 12 directly affected files; strict lint of four production files and seven
  new/updated test files with zero violations; project/source membership and its
  adversarial fixtures; event routing; and the complete
  `make test-ios-ci-tooling` gate. Exact comparisons preserve the main-client
  remainder, aggregate remainder, and rehomed regressions. Nineteen production
  and eleven native source/fixture copies match current source. XcodeGen is
  byte-stable; removing only 36 generated references for nine new Swift files
  reproduces the pre-slice project hash, and `project.yml` is unchanged.
  Markdown formatting, local links/anchors, focused selectors, command syntax,
  and whitespace checks pass.
- Fresh generic Simulator and full-unit `build-for-testing` attempts stop before
  compilation with exit 74 because SwiftPM cannot write its diagnostic cache;
  CoreSimulatorService is also unavailable. No fresh candidate iOS test products
  were produced. Focused/full iOS runtime and manual integration remain unrun.
  The native/source/typechecking results are supplemental and must not be
  reported as iOS transport or real-session account-fencing acceptance; the new
  candidate still needs its own CI/runtime evidence.
- The second-pass review found no production-code or test correction needed. It
  corrected pre-existing enrichment documentation drift in the canonical API
  section and linked Function README: required scope and UUID attribution,
  separate scoped responses and client requests, the bounded lookalike retry,
  cache/singleflight conditions, and legacy null/omission/placeholder behavior.
  These are documentation corrections to the existing handler, not wire or
  backend changes. The source-parity, native-test, cached-dependency
  typechecking, strict-lint, generated-project, and local CI-tooling reruns
  pass. Both fresh Xcode attempts still stop before compilation at the same
  local SwiftPM permission boundary; no iOS runtime or manual acceptance is
  claimed.
- The follow-up documentation audit aligns the AI architecture, API references,
  native ownership guides, testing strategy, and backend caller READMEs. It
  corrects `EnrichScanResponse` to a hand-written contract below the generated
  Identify block, describes independently scoped enrichment and awaited update
  attempts without promising atomic persistence, and distinguishes survey prompt
  suppression from the manual form's 24-hour submitted-state display.
  Independent contract review, Markdown and Edge-fleet formatting, added local
  links/anchors, focused suite references, shell-block syntax, scoped API
  examples, source-copy parity, and whitespace checks pass. This follow-up is
  documentation-only; it does not rerun or replace the candidate iOS runtime
  evidence still required above.

- The 2026-09-03 scan lifecycle slice moves detailed/bulk status, the legacy
  status-string wrapper, and deletion into the 80-line
  `Core/Network/Endpoints/MerianNetworkClient+ScanLifecycle.swift` owner.
  `ScanLifecycleAPIModels.swift` contains the four unchanged wire DTOs in 82
  lines; `Decoding/ScanLifecycleResponseDecoder.swift` contains strict
  explicit-key single/bulk/deletion validation in 63 lines, with private
  envelope types. The main client shrinks from 4,189 to 3,984 lines. Its narrow
  raw-response JSON bridge preserves recovery-owner forwarding into the existing
  private transport. Configuration/input/encoding order, optional video counts,
  raw request IDs, single-versus-bulk identity matching, legacy status decoding,
  classified refresh, status replay, deletion confirmation/replay refusal, and
  cancellation remain unchanged. Recovery payload construction/classification,
  publication/media orchestration, account deletion, uploads, and durable queue
  authority stay out of this extraction.
- Six legacy regressions move to `ScanStatusEndpointTests` and
  `ScanDeletionEndpointTests`, reducing the aggregate from 3,783 to 3,559 lines.
  All selectors/assertions remain; deletion adds an exact camel-case body
  assertion, and the moved recovery fixture omits location coordinates. Three
  protected integrity selectors now require their new suite owners in CI;
  adversarial fixtures reject results placed under the old aggregate. New
  request coverage has 18 independent variants plus bulk ordering/alias/input
  cases and encoding failure. Separate transport, wire, strict decoder, and
  architecture suites cover retry/cancellation, legacy compatibility,
  confirmation, account-owner pass-through, and private ownership. DEBUG mock
  transport bypasses live Auth lease acquisition; source assertions and mock
  retries are not real-session account-fencing evidence. The
  [scan lifecycle matrix](../../apps/ios/Merian/Core/Network/README.md#scan-lifecycle-verification)
  joins the seven suites with shared Auth, queue, deletion, and Field Chat
  callers. Shared endpoint matrices, API/reliability references, local READMEs,
  testing strategy, and the codebase map now name the new owners. Documentation
  also corrects the earlier claim that bulk status never mutates server state:
  it cannot reconstruct scan rows but may reconcile existing job/quota/staging
  state under the unchanged backend contract.
- Scan lifecycle verification passed current-source iOS frontend typechecking
  for the client, all ten endpoint extensions, decoders/validator/cache/status
  DTOs, and focused Network suites against cached dependencies. A native macOS
  harness passed 57 pure model/decoder/cache/architecture tests in nine suites;
  it did not execute iOS endpoint transport tests. Exact comparisons confirmed
  the unchanged client remainder, all four relocated DTOs, six test rehomes, and
  retained aggregate tests. Repeated XcodeGen is byte-stable; removing only the
  48 generated lines for the 12 new Swift files reproduces the pre-slice project
  hash, and `project.yml` is unchanged. Project/source membership, adversarial
  membership, event-routing, the complete `make test-ios-ci-tooling` gate,
  parsing of all 52 changed/new Swift files, strict 16-file production lint,
  comparison of 16 current production and 11 native test/fixture copies,
  formatting of all 22 changed Markdown files, local links/anchors, focused
  selectors, command syntax, and tracked/new-file whitespace checks passed.
  Fresh generic Simulator and full-unit `build-for-testing` attempts both exited
  74 before compilation on denied SwiftPM diagnostic-cache writes;
  CoreSimulatorService is unavailable. Focused/full iOS runtime and manual
  integration remain unrun. This slice changes no wire, schema, persistence,
  feature, or release contract and performs no hosted calls or deployment; new
  candidate CI/runtime evidence is still required.
- The 2026-09-03 scan lifecycle second-pass review found no material defect and
  made no corrective code edits. Independent caller tracing confirmed unchanged
  Core Data funding/queue/deletion ownership and Field Chat preflight behavior.
  Exact comparisons again preserved all four DTOs, six rehomed regressions, and
  the remaining client/aggregate code. The rerun passed 57 native tests in nine
  suites, current-source iOS frontend typechecking against cached dependencies,
  parsing of 52 changed/new Swift files, strict lint of 16 production and nine
  scan lifecycle test files with zero violations, byte-stable XcodeGen,
  project/source membership and adversarial guards, event-routing, the complete
  CI-tooling gate, Markdown formatting, links/anchors, focused selectors, and
  whitespace checks. Fresh generic and full-unit builds again exited 74 before
  compilation because SwiftPM could not write its diagnostic cache;
  CoreSimulatorService remained unavailable. Focused/full iOS runtime and manual
  verification remain unrun, not waived by the source review. The documentation
  follow-up links the exact CI selector guards, adds the scan lifecycle matrix
  to the codebase map, and clarifies Network-versus-Core Data ownership in the
  offline-sync guide. No API, persistence, deployment, or release control
  changed.
- The initial Species Dictionary extraction moved all six
  detail/catalog/overview/stats public method variants into the then-163-line
  `Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift` owner.
  `Decoding/SpeciesDictionaryResponseValidator.swift` owns typed response
  validation in 73 lines, and `Caching/SpeciesDictionaryResponseCache.swift`
  contains the two private, locked, per-client caches in 133 lines. At that
  checkpoint, the main client shrank from 4,528 to 4,128 lines, retaining
  private transport behind narrow configuration-validation and typed-GET
  bridges. The second-pass entries below record the final encapsulation
  boundary, file sizes, and verification status. Signatures, wire DTOs,
  input/configuration ordering, schema and identity checks, auth/retry behavior,
  30-second POST and 20-second GET deadlines, and overview cache-buster lifetime
  remain unchanged. Cache injection enables deterministic clock tests without
  changing the ten-/five-minute TTLs, 64-alias limits, ID-first lookup, returned
  identity aliases, cancellation behavior, or DEBUG reset semantics. Feature
  callers/state, backend, persistence, and `project.yml` are untouched.
- Eighteen existing wire/endpoint methods move from the two oversized feature
  suites into six mirrored Core suites. Sixteen bodies are byte-identical; two
  lose only the three route assertions now covered by feature-owned
  `SpeciesDictionaryCatalogRouteTests`. New request cases cover all six public
  variants plus eleven parameter combinations. Transport tests cover strict
  malformed-success decoding, denial versus auth refresh, bounded replay, exact
  single-read body/query identity, cancellation, and overview nonce lifetime.
  Eleven deterministic cache tests and seven validator tests cover TTL
  boundaries, alias capacity and expiry, isolation/reset, stale identity
  recovery, schema versions, and normalized names. Source-architecture tests
  protect the contained owners, validation/cache ordering, and private
  transport. The Core Network, Dictionary/catalog/detail, Species Reference,
  Identify, API, ownership, and testing guides now identify the ninth endpoint
  owner and its focused suites; the deployment runbook changes only local source
  paths, not release controls.
- At the initial checkpoint, independent read-only implementation, test-oracle,
  and documentation review found no actionable drift. Native macOS execution
  passed 37 methods in six cache, validator, wire-decoding, and
  source-architecture suites using current source. Compiler verification caught
  a test-only throwing-closure inference error in the new Unicode boundary
  fixture; the test now evaluates each throwing request before asserting its
  result. Final current-source iOS frontend typechecking passed for the client,
  all nine endpoint extensions, decoder, validator, cache, and all
  endpoint/decoder/cache suites against cached unchanged dependencies. Exact
  test-rehome and source-copy comparisons passed. Repeated XcodeGen was
  byte-stable; project/source membership, adversarial membership, event-routing,
  the complete `make test-ios-ci-tooling` gate, parsing of all 33 changed/new
  Swift files, and strict production SwiftLint with zero violations across 13
  files passed. Markdown formatting, local-link/anchor and focused-suite
  validation, shell command-block syntax, and tracked/new-file whitespace checks
  passed. Native execution is bounded evidence for these pure helpers;
  cached-dependency typechecking is not full-target compilation. Neither is an
  iOS transport/runtime pass.
- Fresh generic Simulator build and complete-unit `build-for-testing` attempts
  on 2026-09-02 both exited 74 during package resolution, before compilation, on
  denied SwiftPM diagnostics-cache writes; CoreSimulatorService was also
  unavailable. No candidate test products were created. The
  [Species Dictionary matrix](../../apps/ios/Merian/Core/Network/README.md#species-dictionary-verification),
  shared-bridge matrices, complete `merianTests` runtime, and manual Dictionary,
  chart, VoiceOver, and Dynamic Type checks remain unrun locally. The new
  candidate needs its own CI/runtime validation; the earlier merged Inference CI
  confirmation is not evidence for these edits. No live service calls,
  deployment, or external publication were performed.
- The 2026-09-02 Species Dictionary second-pass review found a cache
  encapsulation gap: the immutable client cache reference was module-internal,
  exposing its mutators to callers that could bypass validation. This supersedes
  the first-pass no-actionable-drift conclusion for that boundary. The reference
  is private again. Two fixed-result client request bridges own lookup,
  authenticated load, fixed schema/identity validation, and insertion; they
  accept neither cache objects nor caller-provided response DTOs, loaders, or
  insertion callbacks. The typed GET helper is also private. The six public
  methods, configuration-before-normalization ordering, payloads, deadlines,
  warm-cache cancellation, TTL/alias policies, and DEBUG reset behavior remain
  unchanged. The endpoint owner is now 130 lines and the main client 4,189
  lines. No new production type, protocol, API field, or backend operation was
  introduced.
- New schema-rejection and returned-identity tests require another dispatch
  after a rejected response, catching premature memo insertion under both
  requested and returned aliases. Architecture tests require the private cache
  reference and GET helper and enforce the fixed-result bridge signatures and
  lookup/load/validate/insert ordering. Independent read-only follow-up review
  found no remaining production parity or test-oracle defect. Native execution
  passed 38 methods in six pure-helper/source-architecture suites, and
  current-source iOS frontend typechecking passed for the client, nine endpoint
  owners, decoder, validator, cache, and all endpoint/decoder/cache suites
  against cached unchanged dependencies. This does not claim iOS runtime
  execution of the new admission tests or full-target compilation.
- The second-pass compiler also rejects a deliberate cross-file attempt to
  access the client's cache because the property is private. Exact comparisons
  confirm the unchanged client remainder outside the reviewed cache boundary,
  all six public signatures, unchanged cache/validator policies, and all 18 test
  rehomes. Repeated XcodeGen is byte-stable; project/source membership,
  adversarial membership, event-routing, the complete `make test-ios-ci-tooling`
  gate, all 33 changed/new Swift parses, all 13 production and six native
  test/fixture source-copy comparisons, strict 13-file production lint, Markdown
  formatting, local links/anchors, focused-suite selectors, and tracked/new-file
  whitespace checks passed. Fresh generic Simulator build and complete-unit
  `build-for-testing` attempts both exited 74 before compilation on denied
  SwiftPM diagnostics-cache writes, with CoreSimulatorService still unavailable.
  Focused/full iOS runtime and manual requirements remain unrun; no candidate
  runtime, deployment, or external publication is claimed.
- Field Chat now lives in
  `Core/Network/Endpoints/MerianNetworkClient+FieldChat.swift`: all 17 Insight,
  Explore-post, and Species Dictionary methods form a 401-line owner.
  `Decoding/FieldChatResponseDecoder.swift` contains the unchanged stateless
  strict validators in 304 lines. The main client shrinks from 5,214 to 4,528
  lines and gains one narrow `Encodable`-body POST bridge that returns bytes.
  Public signatures, DTOs, JSON omission/raw-text rules, per-family deadlines,
  supplied/generated idempotency keys, private
  transport/auth/replay/cancellation, and cloud/media recovery remain unchanged.
  The other seven endpoint owners, feature callers/state, backend, persistence,
  and `project.yml` are untouched.
- `FieldChatNetworkEndpointTests` adds 60 request variants for the 17
  operations; `FieldChatNetworkTransportTests` locks all-method
  malformed/oversized success, denials, classified-401 refresh, cancellation,
  the five-keyed/twelve-unkeyed ambiguous-replay split, exact request/key reuse,
  generated-key lifetime, and encoding errors before dispatch. Five legacy
  regressions retain their names and assertions in
  `FieldChatConversationEndpointTests`, `FieldChatActionEndpointTests`, and
  `SpeciesDictionaryChatEndpointTests`, reducing the aggregate from 4,804 to
  3,783 lines. Per-test clients and scoped sessions replace shared-client
  mutation. `FieldChatResponseDecoderTests` directly tests all five validators,
  and `MerianNetworkArchitectureTests` guards their contained owners and private
  transport. Standalone wire decoding and cloud-preflight integration keep their
  existing owners and protected CI selectors.
- Independent read-only production, test-oracle, and ownership-documentation
  review found no actionable drift. Exact comparisons confirm all 17 signatures,
  validator bodies/constants after owner/name/comment-only normalization, the
  unchanged client remainder, and the five test rehomes. Current-source iOS
  frontend typechecking passed for the client, eight endpoint extensions,
  decoder, and all endpoint/decoder suites against cached unchanged
  dependencies; all ten production copies match current source. Native macOS
  execution passed 23 decoder and ten source-architecture test methods using the
  actual decoder, DTO, date, and error implementations. Repeated XcodeGen was
  byte-stable and adds only new source/group references. Source parsing,
  project/source membership and adversarial membership checks, event-routing,
  the complete `make test-ios-ci-tooling` gate, and strict SwiftLint of all ten
  production files passed. All eight changed Markdown files were formatted;
  Markdown validation, 20 added local links/anchors, 217 unique focused-suite
  selectors, shell command-block syntax, and tracked/new-file whitespace checks
  passed. Ownership guides and focused matrices now include the eighth endpoint
  owner and mirrored decoder tests.
- Fresh generic Simulator build and complete-unit `build-for-testing` attempts
  on 2026-09-02 both exited 74 during package resolution, before compilation, on
  denied SwiftPM diagnostics-cache writes; CoreSimulatorService was also
  unavailable. No candidate test products were created. The
  [Field Chat matrix](../../apps/ios/Merian/Core/Network/README.md#field-chat-verification),
  the other shared-bridge focused matrices, complete `merianTests` runtime, and
  manual three-source/VoiceOver/Dynamic Type checks remain unrun locally. Native
  decoder execution and cached-dependency typechecking are not an iOS transport
  or host-runtime pass. These local restrictions do not prevent the next scoped
  hygiene slice, but new candidate changes still need CI/runtime validation.
  Existing backend release holds are unchanged; no live service calls,
  deployment, or external publication were performed.
- The 2026-09-02 Field Chat second-pass review found a shared retry-test blind
  spot: Field Chat and post-management handlers validated a request body, then
  read it again for their replay fingerprint. A one-shot `httpBodyStream` could
  therefore leave two empty bodies comparing equal. The shared POST assertion
  now returns an immutable `NetworkEndpointRequestSnapshot` of the exact bytes
  it validated, the idempotency key, and the timeout; all five affected replay
  handlers reuse that snapshot. Five new `NetworkEndpointTestSupportTests`
  methods cover data/stream bodies, exact bytes versus semantic JSON
  equivalence, key/timeout identity, and scalar/null/omission distinctions. This
  finding supersedes the earlier no-test-oracle-finding summaries for these two
  slices. No production changes were needed; independent read-only review
  confirmed the repair, and exact extraction/rehome comparisons remained clean.
  The shared focused matrices include the helper suite, and testing-guide
  inventory references now include the eighth endpoint owner, Field Chat.
- Second-pass native execution passed all 38 test methods in three suites (23
  decoder, ten architecture, five test-support). A temporary native-only
  mutation that reread the body made both stream-backed byte-identity tests
  fail, confirming that the new suite detects the original defect. Updated
  current-source iOS frontend typechecking passed for the client, all eight
  extensions, decoder, and endpoint/decoder tests against cached unchanged
  dependencies. All compilation copies were compared with current source.
  Parsing of all 17 changed/new Swift files, strict ten-file production lint,
  byte-stable XcodeGen, project/source membership, adversarial membership,
  event-routing, and the complete iOS CI-tooling gate passed. Markdown
  formatting, local-link/focused-suite validation, shell command-block syntax,
  and tracked/new-file whitespace checks also passed. Fresh generic Simulator
  build and complete-unit `build-for-testing` attempts both exited 74 before
  compilation on denied SwiftPM diagnostics-cache writes, with
  CoreSimulatorService unavailable. No candidate test products, iOS runtime
  pass, or manual device verification are claimed; the focused/full-target
  runtime and manual requirements above still need candidate validation.
- Documentation closeout puts shared endpoint-fixture and verification
  requirements in the Core Network guide, replacing incomplete copied group
  lists in the Field Trips, Identify, and testing guides. The Field Trips and
  Identify selector matrices now include `NetworkEndpointTestSupportTests`.
  Field Chat, Insights, Species Dictionary, Explore, and the codebase map point
  to the extracted request/decoder and test owners. The three chat route
  references are complete, and host guidance requires the shared chat matrix
  separately from Dictionary reads or Insight cloud readiness. This follow-up
  changes documentation only; it does not rerun or upgrade the prior native,
  compiler, iOS-runtime, or release evidence above. Markdown formatting,
  local-link and suite-selector validation, shell command-block syntax, and diff
  checks passed; the non-Markdown candidate hashes remained unchanged.
- Explore post management now lives in
  `Core/Network/Endpoints/MerianNetworkClient+ExplorePostManagement.swift`: six
  composer-media/share-state/incident reads and unshare/notes/content edits form
  a 120-line owner. The main client shrinks from 5,334 to 5,214 lines. The typed
  POST bridge gains nil-defaulted idempotency-key forwarding and
  decoding-failure replacement scoped only to decoding after transport.
  Signatures, defaults, 30-second deadlines, DTOs, payloads, semantic
  share-state checks, legacy incident-array compatibility, callers, backend,
  persistence, and `project.yml` remain unchanged. Publication, uploads, and
  cloud/media recovery stayed together at that checkpoint; the later
  scan-publication slice above records their dedicated owners.
- `ExplorePostManagementEndpointTests` owns 36 request cases and composer/edit
  projections; `ExploreShareStateEndpointTests` and
  `ExploreMediaIncidentEndpointTests` own strict reconciliation and
  compatibility coverage. Six direct endpoint tests retain their names in the
  new suites, reducing the aggregate from 5,046 to 4,804 lines. Four protected
  selectors and their adversarial fixtures now identify the new suite/type
  owners; required case names and count are unchanged. Mixed
  incident/notification DTO decoding and Insight stale-cache clearing remain
  aggregate-owned. `ExplorePostManagementEndpointTransportTests` covers raw
  versus mapped decoding failures, body-ignoring unshare success, handler
  denials, classified 401 refresh, exact body/key preservation through bounded
  replay, distinct content-edit keys, legacy edit/unshare replay refusal, and
  both cancellation paths.
- Independent read-only implementation/contract review found no actionable
  parity, test-oracle, isolation, retry, cancellation, or protected-selector
  defect. Exact baseline comparisons confirm only the six methods and typed
  bridge changed in the main client, its share-state validation is identical,
  and only the six test declarations left the aggregate. Final frontend
  typechecking passed for the full current client, seven endpoint extensions,
  and all endpoint suites against cached unchanged dependencies; all eight
  production copies match current source. Native macOS execution passed eight
  architecture and two exact-source JSON-comparison methods. Repeated XcodeGen
  was byte-stable with source/group additions only. Source parsing,
  generated-project/source membership, event-routing, the complete
  `make test-ios-ci-tooling` gate, strict affected-production SwiftLint,
  Markdown formatting, local-link/selector checks, and tracked/new-file
  whitespace checks passed. Documentation review corrected a remaining
  share-state ownership row in the codebase map.
- The 2026-09-02 post-management second-pass review found no actionable code
  defect and required no corrective code edits. Independent read-only tracing
  confirmed decoding-only error replacement, nil-default compatibility for the
  other six endpoint owners, retry-stable content-edit keys, legacy edit replay
  refusal, and unchanged cancellation boundaries. Exact source/test comparisons,
  cached-dependency frontend typechecking, all ten native architecture/JSON test
  methods, byte-stable XcodeGen, and the source, project, CI-tooling, lint,
  documentation, and whitespace guards passed again. Follow-up documentation
  clarifies that the endpoint returns validated state while Insight Sharing owns
  cache reconciliation and presentation fencing.
- Both initial and second-pass attempts at a fresh generic Simulator build and
  complete-unit `build-for-testing` exited 74 during package resolution, before
  compilation, on denied SwiftPM diagnostics-cache writes; CoreSimulatorService
  was also unavailable. No candidate test products were created. The
  [post-management matrix](../../apps/ios/Merian/Core/Network/README.md#explore-post-management-verification),
  other shared-bridge focused matrices, complete `merianTests` runtime, and
  manual checks still require current-candidate validation outside that
  restriction; source/typechecking evidence is not an iOS runtime pass.
- Notifications and public-profile operations now live in
  `Core/Network/Endpoints/MerianNetworkClient+Notifications.swift` and
  `MerianNetworkClient+PublicProfile.swift`: four methods each, in 53- and
  33-line owners. The main client shrinks from 5,421 to 5,334 lines. Whole-file
  comparison confirms only those eight declarations were removed. Both JSON POST
  overloads, private transport/state, signatures, payloads, DTOs, timeouts,
  callers, backend, persistence, and `project.yml` remain unchanged. Catalog,
  badge/push, shared Profile state, and avatar upload retain their existing
  owners.
- `NotificationEndpointTests` owns 19 payload cases and
  `PublicProfileEndpointTests` owns 16. Typed tests preserve notification
  ordering/metadata/counts, required-but-uninterpreted mark-read `success`,
  server identity projections, display-name clearing, and optional availability
  errors. The shared `NotificationAndPublicProfileEndpointTransportTests`
  distinguishes seven typed results from body-ignoring push success and locks
  the three-read/five-mutation replay split, handler denials, classified-401
  refresh, failed replays, and both cancellation paths. Four endpoint
  regressions retain their names in the new owners; exact aggregate comparison
  confirms only those four removals. The protected shared-Auth
  `testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry` remains
  byte-identical in `MerianNetworkClientTests`, with CI selectors unchanged.
- Independent read-only implementation/contract review found no actionable
  parity issue. Focused iOS frontend typechecking passed for the current full
  client, all six endpoint extensions, and every endpoint suite against cached
  unchanged dependencies; all seven typechecked production copies exactly match
  current source. Native macOS execution passed seven architecture tests and two
  exact-source JSON-comparison methods. Neither check executes hosted iOS
  requests. XcodeGen is byte-stable, with only source/group membership
  additions; project/resource, source-membership/adversarial,
  event-routing/adversarial, and build-workflow guards passed. Source parsing
  and strict affected-production SwiftLint also passed. Ownership guides,
  canonical feature/API references, and shared verification requirements now
  cover all six endpoint groups. Independent documentation review verified those
  boundaries and clarified fixture-local versus shared-client overrides. Added
  local links/anchors, focused suite selectors, command-block syntax, Markdown
  formatting, and tracked/new-file whitespace checks passed.
- The fresh generic Simulator build and complete-unit `build-for-testing` for
  this pair failed during package resolution, before compilation, on denied
  SwiftPM manifest diagnostics-cache writes; CoreSimulatorService also reported
  a connection failure. No candidate test products were created. The
  [notification/public-profile matrix](../../apps/ios/Merian/Core/Network/README.md#notification-and-public-profile-verification),
  complete `merianTests` runtime, and manual checks remain unrun locally and
  need current-candidate validation outside this restriction. Prior merged-CI
  evidence does not attest to this unmerged slice.
- The notification/public-profile second-pass review repeated exact
  source/test-removal comparisons, cached-dependency iOS frontend typechecking,
  all nine native architecture/JSON methods, byte-stable XcodeGen, and the
  listed source, project, workflow, and documentation guards. The typechecked
  source/mock copies and native JSON methods matched current source. Independent
  adversarial review found no extraction, test-oracle, isolation, retry, or
  cancellation defect; no corrective code changes were needed. Both fresh Xcode
  build attempts exited 74 during package resolution before compilation,
  repeating the environment restriction above. No candidate iOS runtime or
  manual pass is claimed.
- Documentation synchronization also covers Settings-to-Core-Notifications push
  registration, the canonical Explore architecture inventory, and Profile
  editors' shared-state ownership. The Profile and backend guides no longer
  claim empty display names are rejected; the API contract explicitly records
  the existing custom-name clearing and username-alias response. These are
  documentation corrections, not app or backend behavior changes.
- Explore interactions now live in
  `Core/Network/Endpoints/MerianNetworkClient+ExploreInteractions.swift`: 12
  comment/reply/mention, like/follow, comment mutation, report, and block
  methods move into a 171-line owner. The main client shrinks from 5,574 to
  5,421 lines. One narrow body-discarding POST overload preserves five `Void`
  operations' HTTP-only success, including empty/non-JSON/false-success bodies;
  seven typed operations retain their decoder and projections. Three reads
  retain bounded ambiguous replay and nine mutations retain replay refusal.
  Signatures, defaults, payloads, cursor pairing, trimming, DTOs, callers,
  feature state, backend, persistence, and `project.yml` remain unchanged.
- `ExploreInteractionEndpointTests` adds 41 independent request cases and
  typed-state/metadata/legacy-response coverage, rehoming six aggregate
  regressions with their names preserved.
  `ExploreInteractionEndpointTransportTests` covers typed versus body-ignoring
  success, handler denials, classified-401 refresh, failed replays, mutation
  replay refusal, and both cancellation paths. The architecture suite protects
  all four owners and both POST overloads. The
  [Core Network interaction matrix](../../apps/ios/Merian/Core/Network/README.md#explore-interaction-verification)
  includes the affected Feed, Author Profile, Notifications, Identify, and Core
  social-guard suites.
- Independent read-only review found no implementation, test-oracle, or legacy
  regression loss. Whole-file comparison confirmed only the 12 removals and new
  body-discarding overload. Focused iOS frontend typechecking passed for the
  full client, all four extensions, and every endpoint suite against cached
  unchanged dependencies. Native macOS execution passed five architecture tests
  and the two exact-source JSON-comparison methods; those seven methods do not
  execute iOS requests. Ownership/test references now include the new owner and
  no longer place follow/report or comment regressions in the aggregate client
  suite. The API documentation also correctly describes the existing reaction
  operation as a toggle, not an idempotent state setter.
- XcodeGen is byte-stable, with generated-project changes limited to source and
  group membership. Project/resource validation, source-membership guards and
  their adversarial tests, event-routing validation and adversarial tests,
  build-workflow regression checks, Swift parsing, strict affected-source
  SwiftLint, documentation links/selectors, Markdown formatting, and
  `git diff --check` passed. Exact aggregate-test comparison confirms that only
  the six rehomed methods were removed.
- The interaction slice's second-pass review repeated exact source/test
  comparisons, focused iOS frontend typechecking against cached unchanged
  dependencies, all seven native architecture/JSON methods, byte-stable
  XcodeGen, and the listed source, project, and documentation guards. The
  typechecked source copies matched the current implementation. Independent
  contract review also found no actionable regression; no corrective code
  changes were needed. Fresh build attempts repeated the pre-compilation failure
  below, not an iOS runtime pass.
- This interaction slice's fresh generic Simulator build and complete-unit
  `build-for-testing` both exited 74 before compilation on denied SwiftPM
  manifest diagnostics-cache writes; CoreSimulatorService also reported a
  connection failure. No candidate test products were created. Focused iOS
  runtime, the complete `merianTests` runtime, and manual regression remain
  unrun locally and require current-candidate validation outside this
  restriction.
- Explore browsing now lives in
  `Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`: eight
  stateless Feed/Map/post/detail/author/hashtag/species methods move into a
  184-line owner through the unchanged JSON POST bridge. The main client shrinks
  from 5,758 to 5,574 lines. Signatures/defaults, raw values, ordering, ISO
  cutoff, coordinate forwarding, paired/ranking/quality cursors, typed
  projections, timeouts, and the existing read replay allowance remain
  unchanged. Comments, mutations, notifications, composer media,
  publication/recovery, and Dictionary validation/caches stay in their current
  owners. No backend, feature caller, UI, DTO, persistence, or manifest contract
  changes are part of this slice.
- `ExploreBrowsingEndpointTests` owns 40 independent request cases and typed
  response regressions, rehoming nine aggregate Feed/Map/author/species request
  tests into isolated clients. `ExploreBrowsingEndpointTransportTests` covers
  every route's malformed success, handler denial, auth-refresh, bounded
  network/503 replay, terminal failed replay, and cancellation boundary. The
  architecture suite protects the exact inventory and private transport.
  Ownership guides, affected feature contracts, test references, and the new
  [Core Network browsing matrix](../../apps/ios/Merian/Core/Network/README.md#endpoint-verification)
  describe the split. Shared test/bridge changes follow the current all-group
  verification requirement in the Core Network guide.
- Independent read-only review on 2026-09-02 found no extraction mismatch or
  unsafe mock. Focused iOS frontend typechecking passed for the full current
  client, all three endpoint extensions, and all endpoint suites against cached
  unchanged dependencies. That check caught and corrected an async throwing
  assertion in the new Following test. Native macOS execution passed the actual
  four architecture tests and two exact-source JSON-comparison methods; those
  six methods do not execute iOS requests. XcodeGen was byte-stable and added
  only source references for the new files, with `project.yml` unchanged.
- Final browsing-slice checks passed project/resource and source-membership
  guards, source-membership adversarial tests, event-routing/adversarial and
  build-workflow guards, affected Swift parsing, strict production lint with
  zero violations, Markdown formatting, added links/anchors, focused-selector
  resolution, command syntax, and `git diff --check`. Full-source comparison
  confirmed that only the eight methods were removed from the pre-slice client;
  the nine rehomed tests are present exactly once and other aggregate tests are
  unchanged apart from the earlier Community rehome. Independent documentation
  review found no ownership or verification drift.
- The second-pass review repeated the source/test comparison, iOS frontend
  typechecking, six native architecture/JSON methods, and all listed source,
  project, and documentation guards. Independent contract review also found no
  actionable issue; no corrective code changes were needed. The fresh Xcode
  build attempts repeated the pre-compilation failure below, not an iOS runtime
  pass. Profile and Insight Sharing ownership references now distinguish their
  existing state/adapters from the extracted browsing transport.
- This browsing slice's fresh generic Simulator build and complete-unit-target
  `build-for-testing` both exited 74 before compilation on denied SwiftPM
  manifest diagnostics-cache writes; Xcode also reported CoreSimulatorService
  connection failure. No candidate test products were created, so the focused
  browsing matrix, complete `merianTests` runtime, and manual checks remain
  unrun locally. This does not reopen the accepted merged Inference baseline or
  count as runtime acceptance of the new Network changes.
- Community Identification browsing/contribution operations now live in
  `Core/Network/Endpoints/MerianNetworkClient+CommunityIdentification.swift`:
  eight existing methods move into a 151-line owner through the existing JSON
  POST bridge. Signatures/defaults, raw text, null/omission, cursor pairing,
  coordinate forwarding, DTO projections, 30-second timeouts, and the ambiguous-
  replay allowlist remain unchanged. Scan-publication overloads and media
  recovery did not move in that Community slice; the later scan-publication
  slice above records their dedicated owners. No backend, UI, schema, or feature
  adapter changes are part of this slice.
- `CommunityIdentificationEndpointTests` adds 32 independent payload cases and
  typed-response, malformed-success, denial, auth-refresh, replay-allowlist, and
  cancellation coverage. The three former Community feed/activity/ request-edit
  regressions move out of the aggregate network suite and use per-case clients.
  Shared `NetworkEndpointTestSupport` keeps their fixture and
  scalar-type-preserving JSON assertions aligned with Field Trips.
  `MerianNetworkArchitectureTests` protects the eight-method inventory, thin
  extension boundary, 600-line guard, and retained scan-publication owner.
  Ownership docs and the Identify focused matrix mirror this split.
- The initial independent review found no extraction mismatch. Its
  classification correction distinguishes the existing allowlisted taxonomy
  search from a pure read: thin search results can enrich the backend cache.
  Test names and documentation now describe the existing replay allowlist
  without changing it. The full current client, both endpoint extensions, and
  focused endpoint tests passed iOS frontend typechecking against cached
  unchanged dependencies. Direct macOS execution passed the actual three
  architecture tests plus the two exact-source JSON-comparison methods,
  including four scalar/null cases. These five test methods do not execute the
  iOS client.
- Follow-up review on 2026-09-02 strengthened the Community suite's test
  oracles: distinct submit/withdraw/restore fixtures assert lifecycle
  timestamps; repeated network/503 failures and post-refresh 401/503 denials
  enforce the existing single-replay budget; handler denials use a mock refresh
  tripwire; and nonzero, out-of-range coordinate sentinels detect dropped or
  swapped values without observed location data. Production endpoint and private
  transport behavior remain unchanged. Independent follow-up review closed all
  four findings. The updated tests passed source parsing and focused iOS
  frontend typechecking against cached unchanged dependencies; the five native
  architecture/JSON-comparison methods and project/routing/workflow, strict
  production lint, Markdown, and diff checks passed again. These regressions
  still require candidate iOS runtime execution; focused typechecking is not a
  runtime pass.
- The Community slice's fresh generic Simulator build and complete-unit-target
  `build-for-testing` attempt both exited 74 before compilation on denied
  SwiftPM manifest diagnostics-cache writes; Xcode also reported a
  CoreSimulatorService connection failure. The focused Identify and Field Trips
  runtime matrices, complete `merianTests` execution, and manual checks remain
  unrun locally. Source parsing, strict affected-production lint, generated
  project/source membership, event-routing/adversarial, and build-workflow
  guards passed. These local restrictions do not reopen the accepted merged
  Inference baseline or constitute runtime acceptance of the new Network slice.
- Field Trips wire operations now live in
  `Core/Network/Endpoints/MerianNetworkClient+FieldTrips.swift`: 29 existing
  client methods and two private helpers move together, with the endpoint file
  below 600 lines. A narrow internal JSON POST bridge delegates to the existing
  private session, Auth, retry, and cancellation implementation. Request
  signatures/defaults, actions, payloads, DTOs, timeouts, and cross-feature
  callers remain compatible. Shared filter trimming uses the existing Core
  string helper; no UI policy or backend contract moved into the endpoint owner.
- `MerianTests/Core/Network/Endpoints` adds 48 request-mapping cases, focused
  response/error/refresh/replay/cancellation tests, and source ownership guards.
  The Core Network guide, codebase map, manager guide, testing strategy, and
  canonical Field Trips matrix describe the split and suite ownership.
- Follow-up review corrected the request tests' Foundation dictionary equality,
  which treated JSON Booleans as equal to numeric 0/1. Canonical JSON comparison
  now preserves scalar types and null/omission without depending on key order,
  with explicit regression cases. Ambiguous-POST coverage also requires the
  original network-loss error code, not merely any thrown error. Production
  endpoint behavior remains unchanged. At that Field Trips review, its
  JSON-comparison methods and architecture suite passed direct macOS execution:
  four test methods, including the four parameterized scalar/null cases. This
  narrow source and Foundation check does not execute the iOS client or replace
  its test matrix.
- The initial Field Trips verification passed byte-stable XcodeGen,
  project/source membership, event-routing and build-workflow guards,
  changed-source parsing, strict affected-production lint, Markdown formatting,
  and diff checks. The complete current client body, extracted endpoint, shared
  trim helper, and new tests passed focused frontend typechecking against cached
  unchanged dependencies; this is bounded compiler evidence, not a full-target
  build or test run. The fresh generic Simulator build and follow-up
  `build-for-testing` attempt exited 74 before compilation because SwiftPM could
  not write its manifest diagnostics cache. No new candidate test product was
  produced, so the updated Field Trips matrix, complete `merianTests` target,
  and manual checks remain unrun locally. The independent read-only review found
  no remaining request, response, fixture, or transport-policy mismatch. This
  slice requires its own CI result; the accepted merged Inference baseline
  remains closed.

Implemented Explore slices:

- `Explore/FieldTrips` now uses feature-owned Models, Services, ViewModels,
  Views, and grouped Components, with live networking isolated to Services and
  production files kept below the pass's 600-line review guard.
- `Explore/Identify` now applies the same product-area boundary to its
  dashboard, complete feeds, request detail, taxonomy search, and feedback flow.
  Its presentation and asynchronous-state tests live under
  `MerianTests/Features/Explore/Identify`; wire decoding remains under Core
  network tests.
- `Explore/AuthorProfile` now separates typed routes and presentation policy,
  live dependency adapters, `@MainActor @Observable` profile/report state,
  views, and grouped components. Generation-fenced library refreshes supersede
  in-flight pagination. Its views call no endpoint, deterministic feature tests
  mirror the production owner, and the published-scan grid layout shared with
  Profile and Species Dictionary lives in Core UI.
- `Explore/Map` now separates focus/request and projection models, the live map
  dependency adapter, generation-fenced loading/filtering state, camera/gesture
  views, and grouped rendering components. Map views perform no endpoint lookup,
  and focused tests mirror presentation, spatial cache, and view-model policy.
- `Explore/Feed` now separates route/composer/presentation models, live endpoint
  and realtime adapters, catalog/comment/hashtag/post-detail state owners, route
  hosts, and grouped catalog/comment/composer/detail/card/media components. Feed
  views and components contain no direct networking; Feed and hashtag refresh
  and pagination discard stale results through request identity or generation
  state. Focused tests mirror the feature, and production files stay at or below
  the pass's 600-line review guard.
- `Explore/Notifications` now separates decoded values, row and reply-route
  presentation, live catalog/read/comment/reply adapters, generation-fenced
  catalog and reply-thread state, thin sheet hosts, and focused row/thread
  components. Views and components contain no endpoint or singleton access;
  refresh supersedes pagination, route replacement discards stale reply work,
  failed refresh keeps the last successful catalog cursor usable, and later
  authoritative reply pages replace bounded notification fallback content.
  Focused tests mirror the feature. Shared comment-avatar fallback moved to
  `Explore/Shared/Models` because both Feed and Notifications consume it.
- `Explore/Shell` now separates root-mode and initial-route policy, narrow live
  app-event/root-route/haptic-action dependencies, latest-wins notification
  preparation with token-checked success/failure commits, staged-to-pending
  navigation state, the root navigation host, sheet/lifecycle/event modifiers,
  and root picker and bell components. `ExploreView` retains view-local
  `NavigationPath`, tab, sheet, Insight-handoff, and playback state. Shell views
  contain no endpoint or singleton lookup, focused tests mirror navigation and
  notification-handoff policy, and every production Shell file stays below the
  pass's 600-line guard. Cross-surface Field-trip route values moved unchanged
  to `Explore/FieldTrips/Models`.

Implemented Species Dictionary slices:

- `SpeciesDictionary/Catalog` now separates normalized browse selection/request,
  typed route, flag, and overview presentation Models; narrow live endpoint,
  cached-image, geocoder, and MapKit snapshot Services; generation-fenced
  catalog, overview, and region-map ViewModels; three stable root Views; and
  grouped Catalog, Overview, Regions, and Shared Components. Views and
  Components perform no direct networking or concrete singleton lookup.
  Selection changes fence work before the search debounce, refresh supersedes
  pagination, reverted identities discard stale results, retained rows cannot
  page beneath a failed replacement, failed current-selection refreshes retain
  usable content, and duplicate initial SwiftUI tasks share one first-page load.
  Catalog wire/payload, presentation, asynchronous-state, and architecture tests
  now mirror that owner, while Core Network retains Codable DTOs and transport.
  Every production Catalog Swift file stays below the pass's 600-line guard.
- `SpeciesDictionary/Detail` now separates request/presentation policy, injected
  live dependencies, generation-fenced page and Community state, thin roots, and
  grouped Community/Content/Gallery/Loading/Shared components. Cross-surface
  route, taxonomy, and reference-image presentation values live in
  `SpeciesDictionary/Shared/Models`, while Core Network retains wire DTOs,
  normalized identity, strict schema/response validation, transport, and
  caching. The retired Tree implementation, route, flag, DTOs, and endpoint mode
  are removed. Mirrored Catalog, Detail, and Shared tests enforce ownership,
  asynchronous fencing, compatibility, and the 600-line guard.

Implemented Insights slices:

- `Insights/Media/Carousel` now retains only Insight-specific focus, selection,
  image-origin, availability, page assembly, analysis motion, live-capture and
  description pages, inline-video coordination, and playback-effect adaptation.
  `ImagesCarousel` remains the stable composition entry, no carousel view
  performs networking or direct live resolution, and mutable mounted playback
  state stays private to its owning surface. Cross-feature `AsyncLocalImageView`
  and its narrow live-loader adapter live in `Core/UI`. The pager, normalized
  gallery values, zoom host, pagination dots, hero scroll-edge treatment,
  fullscreen gallery, audio page, and reusable video chrome live in
  `Core/UI/Components/MediaCarousel`; audio-session restoration, the main-actor
  delegate, shared playback effects, exact-token observation, and bounded media
  export live in `Core/Media`. Insight retains its own ordering,
  controller-reuse-key projection, boost policy, telemetry namespace, and
  scan-to-export request mapping. Core and mirrored Media tests lock playback
  overlap, gallery reuse, export behavior/lifetime, Services-only live
  resolution, private state, and the 600-line ceiling.
- `Insights/Sharing` now separates platform-neutral Share presentation values,
  Services-only publication, Community, detail, cache, event, repository, and
  feedback adapters; focused root-view-model extensions; a contained share-state
  request/revision owner; an observable Community request draft; thin Views; and
  stable Share Components. The 773-line Explore-sharing aggregate and old nested
  Community sheet path were removed. Existing component, route, root action,
  copy, accessibility, and endpoint contracts remain stable; views and
  components perform no networking; and every production Sharing Swift file is
  below 600 lines. Deterministic tests lock dependency routing, presentation
  copy, same-scan mutation versus reconciliation, replacement-request fencing,
  Services-only live resolution, and the new ownership map.
- `Insights/Content` now separates platform-neutral fact, custom-tag,
  queued-retry, and phrase policy Models; preferred-name, Supabase tag, queue,
  event, and feedback Services; contained fact, tag-transaction, queued retry,
  name-preference, and Content-action ViewModels; focused Views; and grouped
  Components. The former `Cards/` and `NamePreferences/` paths and mixed
  `UserTagsMutationController` owner were removed. Queue animation and exact
  one-second/350-millisecond task timing remain view-local; retry completion is
  request-fenced, tag persistence rolls back before suppressing external
  effects, committed tag snapshots are ordered and account-fenced, and render
  layers perform no networking. Mirrored Content tests lock bounded/control-free
  validation, dependency routing, rollback/effect ordering, cloud-snapshot
  ordering and account attribution, queued copy and phrase policy, Services-only
  live resolution, shared name-picker ownership, and the 600-line
  production-file ceiling.

Implemented cross-feature slices:

- `Features/FieldChat` now owns the private Pro conversation experience shared
  by Insights, Explore posts, and Species Dictionary pages. The historical
  `Insights/Chat` aggregate files were replaced by platform-neutral Models,
  Services-only live adapters, subject-generation-fenced observable state,
  focused Views, and grouped Components. Existing `InsightChat...` public and
  host-facing names remain source-compatible. Wire DTOs and strict response
  validation remain in Core Network, while feature and wire tests now mirror
  their respective owners. Architecture coverage enforces the cross-feature
  location, Services-only singleton resolution, platform-neutral Models, and a
  600-line production-file ceiling. Follow-up audit work centralized readiness
  task ownership, made prompt trigger ordering deterministic, restored canceled
  sends to same-UUID retry state, and re-privatized file-local helpers.

Implemented Scans slices:

- `Scans/Library` now separates sort/filter and Sendable search models, ad-hoc
  search actors, narrow export/publication/event/haptic dependencies, observable
  Library state, and a contained generation-fenced search coordinator. Library
  views perform no endpoint or singleton lookup, focused action tests replace
  every live closure and lock publication side-effect ordering, full posting
  snapshots build off-main with cooperative cancellation, existing search/filter
  tests retain deterministic debug completion, and every production Library file
  stays below the pass's 600-line guard.
- `Scans/Shell` now separates typed navigation/session and incident-presentation
  models, queue/record and thumbnail-pipeline Services, observable queue and
  incident state, the root view, and focused toolbar/tab/presentation
  components. Views and components resolve no endpoint, Supabase, app-container,
  shared loader, or background actor. Incident refresh rejects canceled and
  stale-account responses while preserving one account-replacement trailing
  request; focused tests mirror navigation, data-store, thumbnail, and overlap
  policy. Every production Shell file stays below the pass's 600-line guard.
- `Scans/Collections` now separates membership/catalog/smart presentation
  models, save-first mutation and smart-suggestion services, observable catalog,
  detail, selection, and smart-detail state, a feature-owned collection-action
  alert, and Collections-local card/catalog components. The Shell-owned
  completed-library query replaces four duplicate Collections queries;
  Collections views/components perform no fetch or singleton lookup. Focused
  tests lock validation, protected-system-folder handling, rollback and
  side-effect ordering, catalog filtering/empty-state independence, smart share
  mapping, and catalog/detail/selection membership-sensitive refresh identity.
  Every production Collections file stays below the pass's 600-line guard.
- `Scans/NonBiological` now separates stable presentation/correction and
  immutable erasure models, narrow purge/database/file/routing/feedback
  Services, observable filtered and mutation state, a thin destination, and
  status Components. The Collections card and root app route converge on the
  Shell-owned typed destination, which consumes the Shell record query instead
  of mounting another fetch. Focused tests lock copy and routing parity,
  eligibility refresh, mixed-media snapshot mapping, completion ordering,
  failure restoration, and overlapping deletion rejection. Actor coverage locks
  the commit-time eligibility fence so a stale snapshot cannot erase a scan
  reclassified as biological, while the UI fixture locks native Back behavior
  and Collections-tab preservation. Every production NonBiological file stays
  below the pass's 600-line guard.
- `Scans/Shared` now separates detached queued-row policy, injected grid
  interaction feedback, single-delete orchestration, Scans-only grid
  composition, and deletion alert presentation. Shared views/components perform
  no persistence read, endpoint call, loader/repository use, or app-container
  lookup. Cross-feature `ScanThumbnail` projection/rendering and
  `EmptyStateView` moved to `Core/UI`, while immutable backfill inputs moved
  beside the Core image actor. The thumbnail loader has a feature-neutral
  service owner, cancellation-fences results from shared cache work, and keys
  tile tasks by pixel size and audio/reference policy. Queued grid and Insight
  values share one manual-retry eligibility rule on `ScanQueueState`. Focused
  tests mirror thumbnail presentation/loading, queued recovery and callback
  ordering, and deletion outcomes. Every production Shared file stays below the
  pass's 600-line guard.

Implemented Profile slice:

- `Profile/UserProfile` now separates typed Profile, identity, achievement, and
  publication models; narrow live Services; generation-fenced observable state;
  grouped Views; and presentation-only Components. Views and components issue no
  endpoint calls and resolve no app-container, network-client, haptic, or
  image-loader singleton. `ProfileDatabaseActor` owns SwiftData projections; the
  live dependency adapters own actor creation and local route lookup.
  Published-scan refresh supersedes in-flight pagination, Profile refresh
  rejects stale account generations, canceled current loads return to a
  retryable state, and achievement foreground loading clears when a background
  refresh supersedes it. Avatar selection/upload work is request- and
  account-fenced and consults the live view presentation slot before committing
  a prepared preview or error. The long-lived post-inference Profile actor is
  container-identity-scoped and refreshes its projection before every award
  evaluation. Focused tests mirror all state owners, persona boundaries,
  recovery presentation, achievement policy, actor-cache replacement, and
  projection behavior. Every production UserProfile file stays below the pass's
  600-line guard.
- `Profile/Settings` now separates root and subarea presentation models, narrow
  account/export/preference/notification/RevenueCat Services, observable
  lifecycle state, thin Views, and grouped Components. Views and components
  perform no endpoint, Supabase SDK, notification-center, app-container,
  repository, or platform-action lookup. Account deletion delegates live
  protocol and recovery effects to `SupabaseManager`; deterministic
  classification and phase sequencing live in `Core/Network/Auth/`, with local
  purge behind a small adapter. Feedback, notification, export,
  sign-out/deletion, and plan state have deterministic suites; an architecture
  test locks the live-service boundary and 600-line ceiling. The initial pass
  moved complimentary-scan display state out of an aggregate; the later Core UI
  integration audit confirmed that it is Plan-only and co-located it under
  `Profile/Settings/Plan/Models`. The Profile Shell composes the
  environment-owned geoprivacy and hardware adapters. Geoprivacy writes are
  account-fenced, serialized, and latest-selection-coalesced; expedition mode
  persists before constraint reevaluation; notification refreshes discard stale
  generations; and sign-out, deletion, export, survey, purchase, restore, and
  redemption actions reject conflicting overlap.
- `Capture/Shell` now separates deterministic media and presentation models,
  closure-based live Services, responsibility-specific view-model extensions,
  grouped goal/media/shared Components, root Views, and routing/lifecycle/
  presentation Modifiers. Services alone construct the live network client,
  remote-media URL session, connection prewarm, share/account lookups, keyboard
  platform actions, and feedback adapters. Models remain deterministic. An
  encapsulated operation-state owner contains route handoffs, timeout
  protection, import coalescing, crop ordering, and mutable task handles in
  private storage. The external-import owner performs its retry decision and
  task-handle release atomically on the MainActor, closing the completion-time
  lost-wakeup window. UI-only pager, focus, expansion, scroll, and exact
  dismissal timing remain in Views and Modifiers. Mirrored tests retain the
  canonical workspace selector, add deterministic policy and operation-state
  coverage, and enforce the live-service and Models boundaries plus a 600-line
  production-file ceiling. Cross-modality composing layout moved to
  `Capture/Shared/Utilities`, and the image wrapper shared with Insights moved
  to `Core/Media`; Shell Models now remain free of SwiftUI and UIKit imports.
- `Capture/Scan` now separates platform-neutral still/video requests, prepared
  results, and sampling policy; narrow camera/context/Photo Library/media/
  entitlement/feedback Services; bounded still, frame, playback, and WAV
  preparation; photo/video/semantic-feedback view-model actions; and a
  generation-fenced still/pre-recording/recording/progress task owner. Scan
  views/components perform no networking or global service resolution, and every
  production file stays below the 600-line guard. The unused shutter control was
  removed. Cross-feature crop encoding moved to `Core/Media`, while the crop
  view moved to `Core/UI`; the presentation-only flash control later moved
  beside its complete row under Capture Shell. Capture-specific source/crop
  metadata remains in `Capture/Shared`, and Profile owns its own bounded
  avatar-crop presentation value. Callers inject haptic/camera effects so shared
  primitives remain passive. Detached media work now propagates parent
  cancellation, and newly created WAV/compressed-playback files remain leased
  until staging accepts them so timeout-losing or otherwise unconsumed results
  cannot leak artifacts. A staged video finalizes its recording generation and
  cancel UI before the optional PhotoKit save completes, while the capture task
  still retains the original recording through that save. Mirrored tests lock
  sampling, playback presentation, task replacement, lifecycle overlap
  rejection, temporary-file transfer and cleanup, detached cancellation,
  dependency routing, ownership, platform-neutral Models, and the line ceiling.
- `Capture/Submission` now separates deterministic admission/media/goal/latency
  Models, normalized staged payload and sendable context values, narrow live
  admission/context/deferred-update/telemetry Services, and visual, nonvisual,
  Describe, admission, and presentation view-model extensions. Submission has no
  view layer and its ViewModels issue no endpoint calls. The actor-backed grace
  owner races context acquisition alone against 150 ms; late context is
  committed to the durable queue before the remote update, whose service makes
  at most one retry after 500 ms without triggering inference. Endpoint,
  transport, and task cancellation are terminal. Queue rejection, queue-only
  routing, connectivity loss, supersession, and unavailable foreground ownership
  cancel context work with no consumer; a timeout-losing late merge retains only
  the service and bounded telemetry inputs rather than the workspace view model
  or complete display-image collection. Queue-first persistence and the exact
  scan/foreground-generation identity remain intact. Mirrored tests lock
  deterministic policy, context-race and cancellation, retry behavior, existing
  submission parity, ownership boundaries, removal of the three former aggregate
  files, and the 600-line production-file ceiling.
- `Capture/Staging` now separates the ephemeral aggregate, capacity policy,
  chronological modality nodes, small media wrappers, and UIKit-backed image
  bundle. Submission owns the live/replay timeline, aligned media projection,
  and exact hand-written `Identify*` request descriptors; their Swift names,
  Codable fields, JSON keys, legacy fallback ordering, and sparse replay indexes
  are unchanged. A later Core UI ownership slice added a deterministic toolbar
  projection plus Staging-owned Services and Components; `ActiveScanToolbar`
  consumes the canonical staged order without a duplicate sort and resolves no
  live effects. Mixed tests were rehomed to Staging, Shell, Submission, and Core
  Utilities owners, with deterministic projection/descriptor tests and a new
  Staging architecture/600-line guard.
- `Capture/Describe` now separates deterministic prompt, subject, tag-ranking,
  and text-composition Models; narrow preference, feedback, keyboard, subject
  delay, and speech-manager Services; observable prompt and lifecycle
  ViewModels; workspace-scoped Views; and layout-focused Components. The former
  aggregate input view, Managers folder, Manager label, and tag-tracker
  singleton were removed. Cross-feature `SpeechManager` moved to `Core/Hardware`
  without changing its AppDI, permission, audio-session, or teardown contract.
  Delayed subject inference is text- and prompt-flow-generation-fenced;
  dictation startup, stop/restart, and partial-result delivery share a separate
  session generation so stale non-cooperative completion cannot mutate
  replacement state. Replacement dictation also cancels without invoking shared
  teardown while startup is configuring, waits for that startup before entering
  the shared speech manager, and stops a cancellation-ignoring stale success
  before replacement. Verified-start status clears a request when the shared
  manager is busy or never reaches recording. UI-only focus, UIKit scrolling,
  sheet presentation, and tag auto-advance timing remain in Views/Components.
  Mirrored tests lock prompt behavior, exact text composition, stable tag
  ordering, inference and dictation overlaps, Core speech lifecycle, ownership
  boundaries, platform-neutral Models, concrete-hardware-free ViewModels, and
  the 600-line ceiling.
- `Capture/Record` now separates immutable audio presentation and layout policy,
  the only concrete audio-manager/haptic adapter, UI-only idle and scrub state,
  a thin full-screen view, and focused components. Shell resolves the live
  manager snapshot and retains permission and record/pause/resume/stop/review
  controls; Submission retains queue-before-inference orchestration. The shared
  audio-session coordinator has its own `Core/Hardware` owner, and
  `AudioCaptureManager` receives maximum-duration feedback from AppDI instead of
  resolving haptics. The focused recording controller owns the engine, input
  tap, WAV, DSP, and recording lease behind exact recording/operation identity;
  the manager owns countdown and presentation state. Together their retained
  work and fences reject late activation, DSP, and countdown commits across
  lifecycle changes; duplicate resume requests coalesce. The coordinator commits
  one-shot lease ownership only after successful activation. Failed replacement
  restores the prior configuration; failed rollback or first activation
  deactivates partial state instead of publishing unknown ownership. Reusable
  palette/raster/layout policy moved to `Core/Media`, the SwiftUI spectrogram
  moved to `Core/UI`, and the audio/video countdown badge moved to
  `Capture/Shared`. Mirrored feature, hardware, and media suites lock
  presentation, scrubbing, feedback injection, DSP/noise-floor and raster
  behavior, transition/lease concurrency, ownership boundaries, platform-neutral
  Models, and the 600-line production-file ceiling without changing the
  15-second WAV, confirmation, staging, submission, copy, accessibility, or
  audio-session contracts.
- The Capture-wide integration audit verified Shell → Scan/Record/Describe →
  Staging → Submission ownership, chronological media projection, live/replay
  request-key parity, queue-before-inference ordering, and the absence of DTO or
  SwiftData schema drift. It closed two cross-boundary gaps: still shutters and
  video admission/start work are now generation-fenced across scene, mode,
  presentation, teardown, and reset transitions; and the camera preview now uses
  its injected `CameraManager` instead of resolving the singleton. Active video
  keeps its established graceful stop-and-stage semantics. Deterministic overlap
  and architecture guards lock these contracts.
- `Insights/Shell` now separates deterministic presentation values, narrow live
  dependencies, scan-bound state projections, root composition, Shell-only
  components, and embedded-navigation modifiers. The former display and test
  aggregates were removed; the view model, sheet, and content sources are split
  by responsibility while preserving their initializer, route, copy, layout,
  media, lifecycle, accessibility, queued-handoff, and Field-trip contracts.
  Shell Services are the only live network/auth/repository/routing/feedback
  owner, views and view models issue no endpoint calls, mirrored tests lock the
  same behavior, and every production Shell Swift file remains below 600 lines.
  The final audit preserved all 108 former test cases across suites named for
  their responsibilities, rekeyed the critical-result and documentation-contract
  guards to those owners, and made queued-completion polling exit immediately on
  task cancellation. `InsightSheetView+Content.swift` now names its mixed
  root-content responsibility accurately; the largest production Shell file is
  524 lines.
- The Insights-wide integration audit reconciled Shell, Content, Media,
  Toolbars, Shared, Field Notes, Identification Review, and Sharing after their
  individual slices. Cross-feature card, toolbar, feedback, gallery, audio, and
  video presentation now has neutral Core UI ownership; reusable playback and
  export processing lives in Core Media; species-level charts, habitat, maps,
  taxonomy, lookalikes, and fallback imagery live in
  `Features/SpeciesReference`; and private conversation UI lives in
  `Features/FieldChat`. Insight export commits remain operation-, scan-, and
  presentation-generation-fenced. The shared export actor restores the existing
  1,024 px batch-image bound under Scans' 20-item cap, keeps remote previews
  file-backed, and rejects cross-host redirects through its exact-host,
  ephemeral session. `InsightsIntegrationArchitectureTests` locks the final
  inventory, service boundaries, extracted owners, export fencing, and
  feature-wide 600-line ceiling; the complete `merianTests` target covers the
  cross-feature consumers.
- Onboarding now separates Shell composition, live effects, ordered state,
  native permission adapters, deterministic Ready consent policy, editable
  consent projection, and shared rendering components. Step views no longer
  invoke AVFoundation or Core Location, the app root injects its exact manager
  instances, and expected-step fencing rejects duplicate or late permission
  completions. The former 1,810-line test aggregate was rehomed without dropping
  any of its 42 tests: feature behavior remains under
  `MerianTests/Features/Onboarding`, while consent restoration, ledger,
  lifecycle, reapproval, and authority suites live with `Core/Security`.
  Architecture tests enforce the ownership boundaries and 600-line production
  ceiling. The second-pass integration audit moved the Core Location
  authorization read behind the delegate's main-actor hop, added a source guard
  for that ordering, and repointed the Ghost merge client contract from the
  retired aggregate to the Core consent-authority suite.

### Completed Scans Collections Persistence Repair

The Collections organization pass now includes the reviewed V50 source-only
SwiftData repair. V50's two checksum-distinct relationship-bearing graphs are
frozen in `Models/Schema/SchemaV50Snapshots.swift` and
`Models/Schema/SchemaV50ReleasedActiveSnapshots.swift`, including the original
`ScanCollection.isDeleted` source property, the processed release's mapped
`isPendingDeletion` source property, and both goal-hint companions. Checksum
selection routes each graph through its exact source bridge, so the application
tombstone survives save/refetch while the SQLite column and Supabase/JSON field
`is_deleted` remain unchanged.

V51 subsequently made preferred species names account-scoped without changing
the collection shape. V50 stores use their checksum-matched source-isolated
V50→V51 plan; the V49 plan applies V49→V50→V51. The full historical plan is
linear through V42→V49→V50→V51, while V43...V48 keep source-isolated repair
plans. Disk fixtures prove metadata-based graph selection and multi-row
preference deletion from both frozen V50 sources before V51 materializes its new
unique identity. The source guardrail also pins every V35...V48 preference alias
to the immutable V34 shape so the new active fields cannot alter retired
checksums. The fixtures continue to prove tombstone true/false values,
relationship and goal-hint retention, and second-context reads. Collection
mutation and database-actor suites cover exact payload projection, inbound
reconciliation fencing, rollback, and acknowledgement-only purge. Recovery
dispatch treats V51 as current, and checksum fallback tries V50 before the
exhaustive V49...V42 source-isolated ladder.

Do not synthesize deletion from transient view state, hard-delete before cloud
acknowledgement, or edit a frozen schema. Any future persisted-model change must
repeat the schema-update procedure and add its own source-isolated recovery
lane.

### Completed Core Integration Audit

The Core-wide audit closed two cross-boundary gaps left after the individual
organization slices. Preferred species names are now account-scoped end to end:
V51 replaces the device-global SwiftData identity, discards unowned V50/defaults
residue, partitions pending tombstones, freshness, and diagnostics, requires the
latest outcome to be successful before freshness can suppress work, preserves
forced edit reconciliation across later coalesced lifecycle requests, and adds
bounded scientific-name keyset sync across local, remote, and pending-delete
state. The matching forward database migration narrows
`user_species_preferences` to authenticated owner CRUD and removes anonymous and
`TRUNCATE` capability. Source and migrated-catalog tests cover the policy,
grants, cross-account denial, and 200-character constraint.

The audit also moved the final identification-review PostgREST and RPC calls out
of `InferenceEngine` into an immutable AppDI-owned Network service. Account-work
leases now fence every live request across Auth transitions. The subsequent
Inference twelfth slice moved review generations, ordered local persistence,
transport invocation, and post-success effects into the singleton-free
identification-review coordinator and its live adapter. The sixteenth slice then
moved the complete review workflow and hydration timing into the focused
workflow coordinator; at that point the engine retained stable public methods,
observable commits, a presentation-application closure, and one hydration
callback bundle as the workflow's sole current-state source. Architecture tests
lock all three boundaries, that single-source callback contract, and the Core
Network singleton, query, and RPC inventory. No Identify payload, navigation
contract, collection wire field, or non-preference SwiftData shape changed.

The twenty-first Inference slice subsequently moved observable commits,
hydration callback construction, presentation/review identity checks, live
hydration admission, review-generation starts, and background-versus-review
write routing into `InferenceSpeciesPresentationCoordinator`. The engine now
retains only the stable review facade and delegates through that
live-dependency-free bridge; the workflow still receives one single-source
callback bundle.

A final adversarial pass found and fixed two preference-convergence races. The
focused `SpeciesPreferenceLocalRecovery` owner resolves interrupted
SwiftData/tombstone mutations before batching, while timestamp-conditional
acknowledgement and a post-upsert local refetch preserve edits made during a
network suspension. These corrections do not change the PostgREST payload, RLS
policy, schema, route, or UI contract.

### SupabaseManager Auth-transition Foundation

The first `SupabaseManager` hygiene slice moves its value-only Auth transition
and account-work lease models, existing error copy, Guest-presentation policy,
two state coordinators, and main-actor sign-out single-flight into the mirrored
`Core/Network/Auth/{Models,Policies,Coordinators}` owners. The 6,039-line live
manager falls to 5,814 lines while retaining every Supabase SDK call, observable
property, transition state instance, OAuth callback, durable Keychain journal,
purchase-identity effect, consent effect, account-deletion workflow, public
signature, and actor boundary.

Seven deterministic tests retain their assertions and behavior while moving from
the aggregate manager suite to
`Core/Network/Auth/AuthTransitionFoundationTests`.

The second slice moves ten deterministic decisions into the main-actor
`Policies/AuthTransitionPolicy.swift`: deletion-recovery admission,
transition-owned request and listener fencing, Apple callback acceptance, OAuth
rollback and metadata guards, authentication-callback target validation,
cold-start session adoption, external-identity handoff deferral, and failed
sign-out purchase-identity restoration. `AuthSessionAdoption` joins the
transition models. Every function body is byte-identical to its former manager
implementation; `SupabaseManager` now applies the policy while retaining the
live Auth listener, provider SDKs, transition state, and effects. The manager
falls again from 5,814 to 5,691 lines.

Nine tests initially move assertion-identically from the aggregate suite to
`Core/Network/Auth/AuthTransitionPolicyTests`. A follow-up adversarial audit
removes the behavior-neutral `isAnonymous` input that the external-identity
handoff policy discarded and adds explicit nil-session and ownerless-request
boundary coverage. It also locks the coordinator's nil expected-session path so
an unexpected still-signed-in SDK event cannot advance sign-out generation. The
follow-up leaves the manager at 5,690 lines and expands focused ownership to
eight foundation tests and ten policy tests. The Core Network architecture guard
freezes all four production paths, declarations and value conformances, the
exact policy-function inventory, the single main-actor task owner, and the
absence of provider SDK imports, live singleton resolution, and detached tasks.
It also prevents the aggregate from redeclaring the extracted types/functions
and extends the 600-line review ceiling to the new folder. Both slices and the
follow-up preserve Auth behavior, wire payloads, persistence schemas, feature
flags, backend contracts, and release controls.

Candidate verification passed byte-stable XcodeGen regeneration, generated
project/resource and source-membership validation, generic iOS Simulator build,
Swift parsing, strict SwiftLint with zero violations, Markdown formatting, and
whitespace validation. The focused Auth-transition, aggregate-manager, and Core
Network architecture matrix passed 78 tests; the complete `merianTests` target
passed 2,873 tests with zero failures on an iPhone 17 Pro iOS 26.5 Simulator.
After the policy extraction, the generic simulator build and complete
build-for-testing passed again. The final-tree focused foundation, policy,
manager, consent-restoration, and architecture matrix passed 85 tests with zero
failures. The complete `merianTests` target passed 2,873 tests with zero
failures on an iPhone 17 Pro iOS 26.4.1 Simulator.

The follow-up audit passed byte-stable XcodeGen, generated-project and source
membership, event-routing and transport-security guards, strict SwiftLint,
recursive parsing, strict-concurrency executable policy/coordinator probes,
Markdown formatting, and whitespace validation. Fresh Xcode build and test
reruns could not start because CoreSimulatorService became unavailable and the
host denied SwiftPM's nested manifest sandbox. The 2,873-case result above
therefore remains the latest complete runtime baseline; it is not presented as
post-follow-up execution evidence.

The third slice moves four deterministic account-deletion decisions and nine
closure-injected phase sequencers into
`Policies/AccountDeletionTransitionPolicy.swift` and
`Coordinators/AccountDeletionWorkflow.swift`. `SupabaseManager` falls from 5,690
to 5,468 lines while retaining live Auth/SDK state, endpoint calls, Keychain and
marker effects, sign-out, purge composition, lifecycle recovery, and every
public signature. Twenty-one aggregate regressions move into
`AccountDeletionTransitionPolicyTests`, `AccountDeletionIntakeWorkflowTests`,
and `AccountDeletionCleanupWorkflowTests`; the obsolete test-only combined
rejection-retirement regression is replaced by a proof-only boundary matching
the live recovery composition, and one new case locks exact unknown-recovery
classification. The subsequent integration audit adds stale legacy-failure,
stale prepared-v2 failure, and deferred-session revalidation regressions,
bringing the three deterministic deletion suites to 26 tests. The six-file Auth
inventory remains below the 600-line owner ceiling and imports no provider SDK
or live singleton. Its architecture guard freezes the new helper inventory,
rejects both current and former aggregate helper declarations, and keeps the
workflow free of task ownership. The source split changes no wire payload,
server route, persistence schema, feature flag, UI, cleanup order, or release
control.

Pass-three verification includes byte-stable XcodeGen, generated-project and
source-membership validation, event-routing and transport-security guards, Swift
parsing, strict affected-source SwiftLint, generic iOS Simulator
build-for-testing, Markdown formatting, and whitespace validation. On an iPhone
17 Pro iOS 26.4 Simulator, the focused account-deletion/Auth matrix passed 341
parameter-expanded cases across 190 unique test identifiers, and the complete
`merianTests` target passed 4,860 cases across 2,876 unique identifiers; both
had zero failures or skips. No hosted request, live account deletion,
deployment, or external publication was performed.

The follow-up review removed the obsolete test-only combined rejection helper,
kept proof retirement separate from exact cached-session restoration, and
hardened the architecture inventory so access-modified static helpers cannot
evade it. The reviewed candidate again passes the generic Simulator
`build-for-testing` compile plus the non-runtime gates above.
CoreSimulatorService was unavailable for a fresh execution pass, so the 341- and
4,860-case results remain the latest runtime baseline and are not attributed to
the renamed proof-only regression.

The 2026-09-05 Auth-wide integration audit closes the remaining session-context
gaps across deletion and purchase continuity. Every preparation, commit,
legacy-intake, recovery, and acknowledgement result that can mutate a durable
deletion marker now requires the transition's exact expected UUID,
anonymous/account kind, and Auth generation on success and failure. Prepared-v2
failures are fenced before outer recovery classification. Ordinary
authenticated-request refresh can renew only its original exact session;
transition-owned telemetry uses the same fence before and after linking; and
failed linked-account sign-out re-adopts the verified source session before
restoring purchase readiness. Deferred noncommit recovery revalidates the cached
source before marker removal, makes verified marker removal the last failable
stage, publishes synchronously, and delegates optional telemetry/entitlement
retry to foreground lifecycle handling. The workflow no longer supplies
permissive default closures for acknowledgement, retirement, sign-out, or purge
stages. Direct anonymous provider linking now reads back the SDK result and
admits, adopts, and revalidates only a permanent destination with the original
UUID before retiring durable provider-bound ghost-merge recovery. Source guards
lock this order and each named deletion-result boundary rather than counting
incidental text occurrences. No payload, route, persistence format, provider
mutation, schema, feature flag, UI, or release control changes.

This audit extends the Auth transition policy inventory from ten to eleven
decisions and its focused policy suite from ten to eleven tests. The six-file
production ownership boundary and 600-line ceiling are unchanged. The added live
session fences bring `SupabaseManager.swift` to 5,486 lines.

The final candidate passed a complete generic iOS Simulator `build-for-testing`,
including both simulator architectures and the full app and test bundles. It
also passed byte-stable XcodeGen, project/resource and source-membership
validation, the complete iOS CI-tooling suite, event-routing and
transport-security adversarial checks, strict affected-source SwiftLint, Swift
parsing, the executed direct-link policy and source-order probes, Markdown
formatting, Supabase skill-link validation, and whitespace checks.

The final fail-closed review aligns the native public-recovery decoder with the
already-normative Edge and SQL status contract. Legacy recovery and
acknowledgement now admit only `pending|completed`; v2 recovery alone may also
admit a nonacknowledged, provider-neutral `not_committed` receipt; all public
recovery responses require explicit acknowledgement state. The extracted cleanup
workflow independently rejects unsuccessful, `prepared`, and `not_committed`
receipts before marker persistence, sign-out, or local erasure. Focused decoder
and workflow regressions lock both boundaries. This changes no server payload,
route, database schema, persistence format, or release control.

After the final corrections, the focused iPhone 17 Pro iOS 26.4 Simulator matrix
passed 50 XCTest cases and 29 Swift Testing cases with zero failures or skips.
That matrix covers the account-deletion decoder, intake, cleanup, transition
policy, endpoint boundary, Core Network integration architecture, Auth
transition policy, and the Explore media regression that the clean build
surfaced. The focused Edge recovery matrix also passed 12 Deno tests. The full
`merianTests` target was not executed again in this final review; its preceding
complete-target result remains the broader runtime baseline.

### SupabaseManager Purchase-safe Sign-out and Journal Ownership

The fourth `SupabaseManager` hygiene slice moves the three deterministic
ordinary/purchase-safe sign-out sequencers into
`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift` and the
two installed purchase-continuity journal families into
`Core/Security/PurchaseIdentity/{Models,Stores}`. The workflow retains exact
preparation-before-sign-out, anonymous replacement, provider/server/session
verification, cancellation, and proof-removal-last order through injected
closures. It owns no live dependency, log sink, or task; the manager supplies
its existing diagnostic as an injected failure reporter.

`PurchaseIdentityHandoffStore` is now the sole owner of legacy/stable journal
decoding, fail-closed validation, exact Keychain selection,
`WhenUnlockedThisDeviceOnly` accessibility, byte-for-byte write verification,
and verified removal. Its live closure dependencies receive the already-resolved
`KeychainManager` instance from `SupabaseManager`; the store resolves no
singleton and imports no provider or network SDK. Explicit coding keys freeze
the existing camel-case JSON fields. The manager retains thin error-mapping
adapters so existing `SupabaseAuthTransitionError` behavior and all call sites
remain stable while server, Auth, RevenueCat, StoreKit, entitlement, lifecycle,
and retry effects stay in the live orchestrator. `SupabaseManager.swift` falls
from 5,486 to 5,288 lines.

Eight existing workflow regressions move from `SupabaseManagerTests` into
`PurchaseIdentitySignOutWorkflowTests`, joined by cancellation before and
immediately after the legacy server destination bind plus proof-retention
regressions. Thirteen secure-store tests cover absence, exact field names, both
compatibility formats, state-specific expiry, malformed-evidence rejection
before writes and after reads, failed and unverifiable writes, accessibility,
exact-key removal, and storage-error propagation. The architecture suite expands
the Auth inventory from six to seven files, freezes all three relocated workflow
helpers, prevents their return to the aggregate, and locks the separate Core
Security model/store owner under the 600-line ceiling. This slice changes no API
payload, server operation, Keychain key, local JSON bytes, SwiftData schema,
feature flag, navigation, provider action, or release control.

Pass-four verification succeeded with byte-stable XcodeGen, generated-project
resource and source-membership checks, event-routing and transport-security
guards plus their adversarial tooling, the complete iOS CI-tooling suite,
Supabase skill-link validation, recursive Supabase candidate formatting, Swift
parsing, and strict affected-source SwiftLint with zero violations. A generic
iOS Simulator `build-for-testing` compiled the app and all test bundles for both
architectures. On an iPhone 17 Pro iOS 26.4.1 Simulator, the focused workflow,
store, aggregate-manager, and integration-architecture matrix passed 56 tests
with zero failures or skips; the final validation-before-write and preflight-
cancellation review passed another 32 focused workflow/store/architecture tests.
The complete `merianTests` target passed 4,904 parameter-expanded runs across
2,920 unique tests with zero failures or skips. No hosted request, live purchase
or identity transition, deployment, or external publication was performed.

### SupabaseManager Ghost-profile Merge Durability and Finalization

The fifth `SupabaseManager` hygiene slice moves the installed ghost-profile
handoff and version-1 queue models into
`Core/Security/GhostProfileMerge/Models`, their codec and secure persistence
policy into `Core/Security/GhostProfileMerge/Stores`, stable queue replacement
and terminal-code classification into
`Core/Network/Auth/Policies/GhostProfileMergePolicy.swift`, and deterministic
completion order into
`Core/Network/Auth/Coordinators/GhostProfileMergeWorkflow.swift`.
`SupabaseManager.swift` falls from 5,288 to 5,223 lines while retaining the
single-flight task and every live Supabase, Auth/session, RevenueCat, consent,
retry, lifecycle, and logging effect.

`GhostProfileMergeStore` is now the sole codec and Keychain-policy owner for
`Merian_PendingGhostProfileMerge`. It preserves the existing camel-case fields,
version-1 queue, legacy single-record compatibility, established key, and
`WhenUnlockedThisDeviceOnly` accessibility. It adds fail-closed validation
before writes and after reads, exact-byte verification, and verified removal. A
valid legacy proof remains usable if its best-effort envelope rewrite cannot be
verified. The store accepts both established RFC 3339 formatter shapes but does
not compare expiry to the device clock; only the server's terminal
`handoff_expired` or `handoff_invalid` response authorizes retirement without a
successful merge.

`GhostProfileMergeWorkflow` preserves server completion → purchase sync → local
evidence rebind/sync → proof removal and adds cancellation checks before the
first server effect and after every asynchronous phase. The manager keeps thin
adapters for the existing `SupabaseAuthTransitionError`, terminal
`FunctionsError` decoding, analytics suppression, exact-session checks, and
task-generation ownership. Eleven store tests, two pure policy tests, one
endpoint-error adapter test, and six workflow tests now own the extracted
behavior. The cross-slice architecture guard expands the Auth inventory from
seven to nine files, freezes both new function inventories and test rehomes, and
makes the two-file Ghost Profile Merge Security package the sole owner of the
queue key, models, validation, and persistence rules under the 600-line ceiling.
This slice changes no API payload, server operation, Keychain key, persisted
JSON field, SwiftData schema, feature flag, navigation, provider action, or
release control.

Pass-five verification succeeded with byte-stable XcodeGen, generated-project
resource and source-membership checks, event-routing and transport-security
guards plus their adversarial tooling, the complete iOS CI-tooling suite,
Supabase skill-link validation, recursive Supabase candidate formatting, Swift
parsing, and strict affected-source SwiftLint with zero violations. A generic
iOS Simulator `build-for-testing` with code signing disabled compiled the app
and all test bundles for both simulator architectures. Local execution of the
focused Ghost Profile Merge matrix and complete `merianTests` target could not
start because CoreSimulatorService became unavailable; those runtime suites are
not counted as passed and remain required in the canonical CI run. No hosted
request, live purchase or identity transition, deployment, or external
publication was performed.

A post-pass contract audit found three stale source-ownership assertions in the
Edge client-contract suite. The Ghost merge contract now reads the extracted
store, policy, workflow, and owner-named Swift tests; the account-deletion
contract reads `AccountDeletionWorkflow`; and the purchase-principal contract
pins durable proof rereads and fail-closed readiness instead of the removed
cached-Boolean implementation. After those corrections, the complete Edge suite
passed 1,937 tests with zero failures and one intentionally ignored disposable-
database case.

Documentation closure synchronized the Core Network/Auth and Core Security
ownership guides, both affected Function READMEs, the API, Keychain, manager,
revenue-identity, account-deletion, and Onboarding contracts, the codebase map,
testing strategy, and deployment proof matrix. These references now name the
exact extracted Swift owners and make every Deno-to-Swift source-path dependency
an atomic rehome obligation; none describes cached presentation state as durable
purchase-handoff authority.

### `SupabaseManager`-wide integration audit

The 2026-09-05 joined audit followed the five extracted Auth/Security slices
through the remaining live `SupabaseManager` orchestration rather than treating
their individual green suites as sufficient integration evidence. It covered
Auth-listener delivery, anonymous bootstrap, account deletion, ordinary and
purchase-safe sign-out, stable and compatibility purchase continuity, Google and
shared OAuth replacement, ghost merge, restored-session public-author refresh,
entitlement, and deferred history synchronization.

The audit fixed four related stale-work boundaries. Account-deletion intake now
checks cancellation before persistence, after the durable legacy marker,
immediately before and after non-destructive v2 preparation, and after the v2
marker pair, retaining recovery evidence without starting destructive work.
Google rejects cancellation before provider presentation and after its return;
the shared direct provider-link path checks immediately before the SDK mutation.
OAuth replacement also rejects preflight cancellation, rechecks after
synchronous analytics suppression, and reconciles the source without installing
a replacement. Listener, bootstrap, and purchase-continuity completions
revalidate the exact manager-published user, nonexpired SDK session, captured
Auth generation, and transition context after suspension and immediately before
downstream publication or proof removal; a completion without a transition owner
becomes stale as soon as a transition opens. Finally, restored-session
public-author refresh now uses a target account and UUID with
compare-before-clear cleanup, so a cancelled predecessor cannot clear a
replacement task, and it records completion only after success.

Deterministic workflow tests cover cancellation at every new deletion and
sign-out boundary, the aggregate manager suite covers shared OAuth preflight and
post-suppression cancellation, and the cross-slice architecture guard freezes
listener, bootstrap, proof-retirement, provider-return, and public-author task
ownership. The three Deno client-source contracts enforce the corresponding
pre-destructive deletion, OAuth, and purchase-proof ordering. This audit changes
no JSON, endpoint, database, Keychain key or journal shape, SwiftData schema,
navigation, feature flag, provider contract, or release control.

Final verification regenerated a byte-stable Xcode project, passed project,
source-membership, event-routing, transport-security, Markdown, Swift parsing,
strict affected-source SwiftLint, Supabase skill-link, and complete iOS
CI/adversarial tooling checks, and compiled the app plus all test bundles for
both generic Simulator architectures. The canonical focused Auth/Core Network
matrix passed 164 tests, the complete `merianTests` target passed 4,929 tests,
and the complete Edge suite passed 1,937 tests with zero failures and its one
intentional disposable-database skip. No hosted request, live account/purchase
transition, deployment, or external publication was performed.

### `ConsentManager` Models and Pure Policies

The first Core Security consent hygiene slice moves the exact policy versions,
provider identifiers, evidence copy, errors, and source-compatible
`ConsentManager.*` value types into `Core/Security/Consent/Models`. It moves
all-version provider-head selection and authority, account activation and
ghost-evidence rebinding, bounded retry timing, and the value-only
account/generation/cancellation fence into `Consent/Policies`.

Existing nested model names, Codable fields and legacy defaults, manager static
entry points, retry schedules, actor isolation, and every live effect remain
stable. `ConsentManager` remains the observable state and orchestration facade;
it still owns consent mutation, Supabase synchronization, Realtime lifecycle,
restoration tasks, persistence sequencing, derived gates, and PostHog
application. The extraction reduces the aggregate from 3,099 to 2,557 lines
without changing an API payload, database contract, Keychain key, persisted JSON
field, policy string/version, navigation route, inference gate, feature flag, or
release control.

`ConsentArchitectureTests` freezes the six-file Models/Policies inventory,
declaration relocation, dependency exclusions, `ConsentManager`-only production
consumption of the necessarily module-internal policy types, and the 600-line
review ceiling. `ConsentLedgerOwnershipPolicyTests` adds direct
synchronized-versus-pending ledger and withdrawal-journal rebinding coverage,
including the per-account reapproval fence. XcodeGen included every new owner,
generated-project resource and source-membership checks passed, the complete app
and all test bundles compiled for the generic iOS Simulator destination, Swift
parsing and strict SwiftLint passed with zero violations, and whitespace
validation passed. The first focused execution exposed a declaration-guard
substring collision between `AdultEligibilityReceipt` and the valid wire DTO
`AdultEligibilityReceiptInsert`; matching real Swift declaration boundaries
fixed the guard without changing production code. The final focused Consent
matrix passed 33 tests, and the complete `merianTests` target passed 4,933 tests
with zero failures on an iPhone 17 Pro iOS 26.4.1 Simulator. A second-pass
contract audit found no material production defect and added the sole-facade
policy-consumption guard to prevent future coupling through the widened
cross-file access level. No hosted request, database mutation, deployment, or
external publication was performed.

### `ConsentManager` Remote Transport and Wire Mapping

The second Core Security consent hygiene slice moves the two immutable receipt
inserts, both authenticated causal append adapters, four ID-scoped read-backs,
six concurrent authoritative reads, wire DTOs, row mapping, strict append-result
validation, and ambiguous-write recovery into `Core/Security/Consent/Services`.
The initializer-injected `ConsentRemoteService` core contains no Supabase or
singleton dependency; `ConsentRemoteService+Live.swift` is the only direct
PostgREST/RPC owner. `ConsentManager` remains the sole production facade and
retains mutation sequencing, session/account/generation fences, Realtime,
persistence, restoration, derived gates, and PostHog lifecycle authority.

The extraction preserves exact table and RPC names, select columns, filters,
ordering, limits, six-read concurrency, insert/read-back order, accepted versus
superseded causal outcomes, fractional ISO-8601 handling, immutable-payload
retry matching, and the server-rebased revocation-parent exception. It reduces
the manager from 2,557 to 1,896 lines without changing an API payload, database
contract, persisted ledger or journal, Keychain key, policy copy/version,
provider, navigation route, inference gate, feature flag, or release control.

`ConsentRemoteServiceTests` directly cover both receipt and causal-event
adapters, exact request keys and result decoding, recovery after ambiguous
writes, mismatch rejection, independent current-disclosure/provider-head
mapping, malformed accepted results, and synchronization fencing.
`ConsentArchitectureTests` now freeze the nine extracted production files,
600-line ceiling, deterministic-owner dependency exclusions, live Supabase
confinement, manager-only service consumption, `ConsentRemoteWire` confinement
to the remote models, service core, and live adapter, and the separately
retained analytics Realtime table subscription.

Verification passed with byte-stable XcodeGen output, generated-project and
source-membership validation, a generic iOS Simulator build-for-testing, Swift
parsing, and strict SwiftLint with zero violations. The focused Consent matrix
passed 44 tests, and the complete `merianTests` target passed 4,944 tests with
zero failures on an iPhone 17 Pro iOS 26.4.1 Simulator. The complete Edge
Function suite passed 1,937 tests with zero failures and one intentional ignore.
An independent contract audit found no production parity defect; it did expose
stale static contract ownership in the legal-consent and ghost-profile merge
tests, which now inspect the split service, live adapter, wire-model, and retry
policy owners. Supabase recursive formatting, Markdown formatting, Supabase
user-skill link validation, and whitespace checks also passed. No hosted
request, database mutation, deployment, or external publication was performed.
The follow-up review found no additional production or wire-contract defect and
added a regression guard that prevents another production owner from consuming
the necessarily module-internal wire namespace directly. The documentation
follow-up also names every Swift source and test read by
`ghostProfileMergeClientContract.test.ts`, including the relocated consent retry
policy, so a future rehome cannot silently leave its Deno URL stale.

### `ConsentManager` Local Ledger Repository

The third Core Security consent hygiene slice moves decoded local-ledger and
analytics-withdrawal-journal state, independent load uncertainty, JSON
validation, verified write publication, write-ahead recovery, account
activation, and ghost-to-permanent rebinding into
`Core/Security/Consent/Repositories/ConsentLedgerRepository.swift`. The focused
`@MainActor` repository injects the existing `ConsentLedgerStoring` boundary and
contains no network, provider SDK, task, Observation, or singleton dependency.
`ConsentLedgerStore` remains the raw atomic file/Keychain byte owner.

`ConsentManager` remains the only production repository consumer. It still owns
observable and derived state, consent-action creation, active-session and
generation fencing, synchronization order, Realtime lifecycle, restoration, and
PostHog application, but no longer encodes JSON or calls the raw store. The
repository publishes a candidate ledger only after the store verifies it. An
analytics revocation still closes the in-process gate first, records the exact
immutable event in the independent journal before the ledger, retains that
intent across a failed ledger write, and removes it only after the durable
ledger succeeds. Ghost handoff still rebinds the journal before the ledger and
recovery. The manager falls from 1,896 to 1,628 lines; the new repository is 347
lines. No initializer, nested model name, Codable field, file or Keychain key,
API payload, database contract, policy version/copy, navigation route, inference
gate, feature flag, or release control changes.

`ConsentLedgerRepositoryTests` directly cover launch recovery order, malformed
or independently unreadable storage, rejection without overwriting malformed
evidence, failed-write nonpublication and notification, exact write-ahead retry,
verified-ledger fallback when the journal write fails, and journal-first account
rebinding. `ConsentArchitectureTests` freeze the ten-file
Models/Policies/Repositories/Services inventory, private decoded-journal state,
raw-storage call confinement, sole-facade repository consumption, infrastructure
exclusions, and the 600-line ceiling. The cross-language Ghost contract reads
the repository directly and requires store persistence before in-memory
publication. The legal-consent and Ghost focused Deno contracts pass 15 tests;
the complete Edge Function suite passes 1,937 tests with zero failures and one
intentional ignore. Same-path XcodeGen output is byte-stable; generated-project
validation and source membership, Swift parsing, strict lint, Markdown and
Supabase formatting, Supabase skill-link validation, and whitespace checks cover
the static boundary. The final generic build and native runtime rerun were
unavailable when CoreSimulatorService failed before build or test discovery; the
immediately preceding focused Consent matrix passed after the production
extraction, before the final nonbehavioral repository encapsulation and
test-assertion additions. An independent contract audit found no P0-P3
implementation, contract, or documentation drift. No hosted request, database
mutation, deployment, or external publication was performed.

### `ConsentManager` Realtime Coordination

The fourth Core Security consent hygiene slice moves the account-scoped
analytics-consent subscription identity, listener and retry tasks, generation
fences, inactive-channel repair, and bounded retry state into
`Core/Security/Consent/Coordinators/ConsentRealtimeCoordinator.swift`. The
coordinator receives narrow subscription, timing, failure-reporting,
current-user, and synchronization closures and contains no Supabase, singleton,
logging, table, or SDK dependency.

`Core/Security/Consent/Services/ConsentRealtimeCoordinator+Live.swift` is now
the sole direct analytics-consent Supabase Realtime owner. It preserves the
exact owner-filtered `user_analytics_consent_events` INSERT channel, status
mapping, subscription, and removal operations. `ConsentManager` remains the
current-account and synchronization authority. Session observation,
foreground/current-session repair, inference preflight, and pre-OAuth shutdown
still occur at the same lifecycle points; only channel/listener/retry ownership
moved. The manager falls from 1,628 to 1,447 lines, the coordinator core is 279
lines, and the live adapter is 90 lines. No initializer call site, API payload,
table, RLS policy, RPC, persisted ledger or journal, Keychain key, policy
version/copy, provider, navigation route, inference gate, feature flag, or
release control changes.

`ConsentRealtimeCoordinatorTests` deterministically cover same-account
idempotency, inactive-channel replacement, account replacement, stale events,
stream completion, subscription failures, the exact bounded backoff sequence,
stop-time retry cancellation, explicit and deinitialization cleanup, coalesced
exactly-once removal, and disabled live behavior. A follow-up review replaced
synthetic subscription identity with reference identity and gave the
subscription a contained removal task. Listener completion, explicit shutdown,
and coordinator deinitialization now converge on the same removal operation;
deinitialization starts it independently of listener cancellation. Owner
deallocation therefore cannot strand a client-retained channel, and overlapping
teardown cannot remove one channel twice. `ConsentArchitectureTests` freeze the
twelve-file Models/Policies/Coordinators/Repositories/Services inventory,
coordinator state and manager wiring, separate PostgREST/RPC and Realtime
adapter confinement, and the 600-line extracted-owner ceiling. The
cross-language Ghost contract now reads the coordinator core and live adapter
directly to lock owner filtering, generation/current-user fences, retry
scheduling, and manager lifecycle wiring. Focused Swift parsing and strict lint,
direct compiler probes for the coordinator/live adapter/test harness, the
legal-consent and Ghost Deno contracts, XcodeGen, project validation, and source
membership pass. Native app build and runtime verification subsequently
recovered on the current host. A generic iOS Simulator build with code signing
disabled compiled both simulator architectures. On an iPhone 17 Pro iOS 26.4.1
Simulator, the focused coordinator and architecture matrix passed 13 tests, the
complete Consent matrix passed 64 tests, and the complete `merianTests` target
passed 4,964 parameter-expanded runs across 2,980 unique test identifiers with
zero failures, skips, or expected failures. The complete Edge Function suite
also passed 1,937 tests with one intentional ignore. No hosted request, database
mutation, deployment, or external publication was performed.

### `ConsentManager` Synchronization Coordination

The fifth Core Security consent hygiene slice moves scheduled and active
synchronization task identity, same-account single-flight behavior, generation
invalidation, retention and exact cancellation draining for every outstanding
task handle—including superseded and previously invalidated work—and unowned
evidence binding, stable pending-evidence pushes, authoritative fetch, and
verified merge sequencing into
`Core/Security/Consent/Coordinators/ConsentSynchronizationCoordinator.swift`.
The coordinator receives the existing ledger repository and remote service plus
narrow manager callbacks for identity, SDK identity, authority closure, merge
publication, and failure handling. It contains no direct Supabase, singleton,
logging, Observation, or SDK dependency.

`ConsentSynchronizationMergePolicy.swift` separately owns the value-only
remote-to-ledger upsert and derives the required-consent authority,
analytics-cloud authority, and reapproval stream-head result. The manager
remains the observable account/session facade and retains consent mutation,
session adoption, restoration and retry state, lifecycle decisions, durable
transition requests, and SDK application. The manager falls from 1,447 to 1,157
lines; the synchronization coordinator is 460 lines and the merge policy is 76
lines. All fourteen extracted production owners remain below the 600-line
Consent review ceiling. No initializer call site, API payload, table, RLS
policy, RPC, persisted ledger or journal, Keychain key, consent copy/version,
provider, inference gate, feature flag, navigation, or release control changes.

`ConsentSynchronizationCoordinatorTests` directly cover coalesced same-account
work with one failure publication, cancellation and exact task drain for
current, superseded, and previously invalidated work—including different-account
active-task replacement—stale-generation rejection before persistence, and the
complete adult/Terms/Gemini/PostHog pending-push order before authoritative
fetch. `ConsentSynchronizationMergePolicyTests` cover evidence upsert, duplicate
current/head values, authority derivation, and authoritative absence.
`ConsentArchitectureTests` now freeze the fourteen-file inventory, manager and
coordinator wiring, synchronization state/function relocation, dependency
exclusions, merge-policy ownership, and the existing 600-line ceiling. The
cross-language Ghost client contract reads the new coordinator, merge policy,
and focused test owner directly so its pending-consent-before-refetch and
persist-before-authority guarantees survive future rehomes.

Verification regenerated byte-stable XcodeGen output and passed generated-
project resource and source-membership checks, full Consent Swift parsing,
strict whole-slice SwiftLint with zero violations, all fourteen mirrored Consent
test sources typechecking together against the compiled app module, recursive
Supabase formatting and lint, both affected cross-language contracts, and the
complete 1,937-test Edge suite with its one intentional disposable-database
ignore. A generic iOS Simulator build compiled the production target for both
architectures, and ten focused tests—six synchronization-coordinator, two
merge-policy, and two architecture—then passed on an iPhone 17 Pro iOS 26.4.1
Simulator. The subsequent review added a directly typechecked different-account
supersession regression. Attempts to rebuild and execute that added test, the
complete Consent matrix, and the complete `merianTests` target were blocked
before compilation or execution when the host's CoreSimulator service
disconnected and its nested SwiftPM package sandbox could not start; those
attempts are not counted as passed. No hosted request, database mutation,
deployment, or external publication was performed.

### `ConsentManager` Required-Consent Restoration Coordination

The sixth Core Security consent hygiene slice moves the launch-restoration state
machine, automatic retry budget, UUID-keyed outstanding-task registry and stable
identity, compare-before-clear completion, cancellation snapshot and exact Auth
transition drain, manual retry admission, duplicate-session preservation, and
account/SDK-session/synchronization-generation fences into
`Core/Security/Consent/Coordinators/RequiredConsentRestorationCoordinator.swift`.
The coordinator receives narrow context, publication, synchronization,
failure-reporting, scheduling-policy, and sleep closures. It has no direct
Supabase, Auth-client, singleton, logging, Observation, PostHog, or test-runtime
dependency.

`ConsentManager` remains the sole observable facade and synchronously mirrors
the coordinator's presentation state. Its existing initializer and public
restoration interfaces remain source-compatible, while the synchronization
coordinator still owns the remote pipeline and outstanding task drain. The
manager falls from 1,157 to 1,050 lines; the restoration coordinator is 290
lines, and all fifteen extracted Consent production owners remain below the
600-line review ceiling. No API payload, table, RPC, RLS rule, persisted ledger
or journal, Keychain key, consent copy/version, provider, inference gate,
feature flag, navigation, or release control changes.

`ConsentRestorationCoordinatorTests` directly cover duplicate-session retry
preservation, automatic failure-budget escalation, manual reset, an old
cancellation-uncooperative retry remaining retained and drainable while account
replacement fences it, and an old retry completing after it has scheduled a
replacement. The last two cases prove exact cancellation drain, post-suspension
identity fencing, and stable compare-before-clear task ownership. A further
overlap case forces manual retry to reuse the same account, generation, and
attempt number, then proves caller cancellation prevents the old timer from
reentering. `ConsentArchitectureTests` now freeze the fifteen-file inventory,
restoration state/task relocation, manager drain wiring, dependency exclusions,
centralized retry-policy access, and the existing line ceiling. The
cross-language Ghost client contract reads the new coordinator and focused test
owner directly so future rehomes cannot silently discard those guarantees.

Verification regenerated byte-stable XcodeGen output and passed generated-
project resource and source-membership checks, event-routing validation, full
Consent Swift parsing, strict all-source SwiftLint with zero violations, a
generic iOS Simulator production build, and a complete generic
`build-for-testing`. Both affected cross-language contracts passed 15 tests; the
complete Edge suite passed 1,937 tests with one intentional disposable-database
ignore, and recursive Supabase format, lint, and tooling gates passed. A focused
iPhone 17 Pro iOS 26.4 Simulator run reported no behavioral-suite failure and
exposed only the new coordinator's missing centralized-retry-policy allowlist
entry in `ConsentArchitectureTests`; that guard was corrected and compiled in
the subsequent `build-for-testing`. CoreSimulatorService disconnected before the
immediate post-fix executable rerun. A later final-audit rerun is recorded
below; the complete `merianTests` runtime target is not claimed as passed. No
hosted request, database mutation, deployment, or external publication was
performed.

A subsequent lifetime audit found that invalidation canceled and released the
restoration retry handle before a cancellation-uncooperative sleep actually
completed. The coordinator now keeps every retry in a UUID-keyed registry until
that exact task's completion defer runs, returns a cancellation snapshot, and
lets `ConsentManager` drain restoration and synchronization work before an Auth
replacement. The overlap tests use bounded XCTest expectations and prove that
the drain remains open until the canceled timer truly finishes. Strict Swift 6
production and focused XCTest typechecking, affected-source SwiftLint,
byte-stable XcodeGen, project/source/routing guards, focused Ghost and legal
Deno contracts, recursive Supabase formatting, Markdown validation, and diff
checks passed. A fresh Xcode build and executable-test rerun remained blocked
before compilation by the unavailable CoreSimulator service and the host's
SwiftPM nested-sandbox restriction; neither is claimed as passed.

A final overlap review found that retaining a canceled timer was not sufficient
when manual retry reset the counter and a replacement failure reused the same
account, generation, and attempt number. Retry admission now also rejects a
canceled caller directly. A continuation-controlled regression resumes the old
timer only after the replacement has entered the identical waiting state and
proves the old task cannot synchronize or advance presentation. The two Realtime
teardown overlap tests also use explicit bounded start/finish expectations
rather than scheduler-yield timing.

### Consent-wide Integration Audit

The post-extraction integration audit traced consent from onboarding and app
root restoration through Auth replacement, Ghost rebinding, persistence,
inference admission, PostHog application, Realtime repair, and all remote
receipt/event adapters. It found no P0/P1, wire-shape, persistence-order,
actor-isolation, stale-merge, policy-copy/version, or provider-head defect. It
did close three fail-closed gaps before leaving the domain.

`ConsentRemoteService` now distinguishes a genuinely empty successful query from
a present row whose enum or timestamp cannot map. The latter throws
`MerianError.invalidResponse`, so malformed evidence cannot resolve required-
consent restoration as authoritative absence. Adult and Terms receipt inserts
also accept an ID/owner-scoped read-back only when every immutable field matches
the attempted receipt and the server timestamp is present. A mismatch after a
successful insert is an invalid response; a valid but mismatched row after an
ambiguous transport failure preserves that original failure. Causal-event
matching and the server-rebased revocation-parent exception remain unchanged.

`ConsentRealtimeCoordinator` now retains every started subscription removal in a
UUID-keyed teardown registry through exact completion. The renamed
`ConsentManager.cancelAndAwaitAccountBoundWorkForAuthTransition()` barrier stops
new Realtime work and awaits synchronization, restoration, and physical channel
teardown before `SupabaseManager` may mutate the SDK session. Stale event
generation fences remain defense in depth, while deterministic tests hold
removal behind a cancellation-uncooperative continuation and prove both the
coordinator drain and manager Auth barrier remain open until release. The audit
also corrected Core Security documentation to distinguish the live adapters'
exclusive PostgREST/RPC/Realtime ownership from `ConsentManager`'s intentional
authenticated-session and account-work-lease authority.

All fifteen extracted production owners remain below the 600-line ceiling; the
largest is the 598-line remote service and the Realtime coordinator is 298
lines. The complete app and every test bundle compiled for both generic iOS
Simulator architectures. Strict affected-source SwiftLint passed with zero
violations; byte-stable XcodeGen, project/resource/source membership,
event-routing and adversarial routing, Swift parsing, Supabase skill links,
recursive Supabase format/lint, changed-Markdown formatting, and whitespace
gates passed. The focused legal/Ghost contracts passed 15 tests, and the
complete Edge suite passed 1,937 tests with zero failures and one intentional
disposable-database ignore. After correcting two stale architecture assertions
to check actual state declarations and the current combined-drain body, the
focused Consent restoration, Realtime, and architecture matrix executed 20 tests
on an iPhone 17 Pro iOS 26.4 Simulator with zero failures. The complete
`merianTests` runtime target is not claimed as run. No hosted request, database
mutation, deployment, or external publication was performed.

### `RevenueCatManager` Value and Policy Ownership

The first RevenueCat hygiene slice moves thirteen source-compatible value and
policy declarations out of the 917-line live manager into four focused owners:
`RevenueCat/Models/RevenueCatModels.swift` and
`RevenueCat/Policies/{RevenueCatIdentityPolicies,RevenueCatAccessPolicies,RevenueCatPrivacyPolicies}.swift`.
Models, canonical identity, account-kind, mutation, and rebind decisions are
Foundation-only. Access policy imports RevenueCat solely for verification and
store value types; privacy policy owns severity-only log messages and the exact
legacy attribute deletion map. None of the extracted owners configures or calls
the SDK, creates tasks, mutates observable state, logs, or resolves an app
singleton.

The review also replaces two copies of the eight legacy subscriber-attribute
strings with one typed `RevenueCatLegacySubscriberAttributeKey` registry. Legacy
publication and stable-principal deletion now consume the same source of truth,
preventing a future attribute addition from silently escaping the PII scrub list
while preserving every emitted key and the existing dictionary API.

At the end of this first slice, `RevenueCatManager.swift` fell to 644 lines and
remained the sole live SDK facade, retaining every serialized configure/login
effect, task and generation fence, observable paid-state projection, offering
read, purchase/restore, entitlement handoff, UIKit subscription-management
action, and log emission. The existing 539-line test suite was rehomed under the
mirrored `Core/Security/RevenueCat` test package with only three instances of
pre-existing trailing whitespace removed. A new architecture suite froze exact
declaration ownership and dependency confinement, capped extracted owners at 200
lines, and applied a temporary 650-line manager guard. The identity slice below
supersedes that temporary boundary with the final 600-line guard.

This pass changes no product identifier, App User ID casing, subscriber
attribute key, error copy, verification or store-provenance decision, provider
call, JSON payload, SwiftData/Keychain schema, feature flag, or release control.

Swift parsing, strict affected-source SwiftLint, direct iOS typechecking of all
four extracted owners, architecture-test macro typechecking, rehome comparison
apart from the documented whitespace cleanup, byte-stable XcodeGen,
project/resource/source membership, changed-Markdown formatting, and whitespace
checks pass. The complete purchase-principal contract suite passes all 23 tests.
An independent read-only contract audit found no behavioral, identity/privacy,
provider, wire, test, project-grouping, or documentation drift and prompted a
broader architecture guard against any future `Purchases.` access in
deterministic owners. The follow-up review extended that guard to declaration
uniqueness across the source tree and every common task/task-group construction
form, then consolidated the two legacy attribute-key copies into the typed
registry described above. A fresh generic Simulator build and runtime tests are
not claimed: CoreSimulator is unavailable and the host rejects SwiftPM's nested
package sandbox before source compilation.

### RevenueCat Identity Coordination Ownership

The second RevenueCat hygiene slice moves live requested/linked identity state,
account-kind and binding-generation fences, handoff and account-grant readiness,
request and monotonic handoff-fence generations, and serialized task lifetime
into the focused `RevenueCatIdentityCoordinator`. The `@MainActor @Observable`
coordinator runs only per-link injected reset and link closures. It imports no
RevenueCat SDK, Supabase, UIKit, application singleton, or logger;
`RevenueCatManager` remains the sole provider facade and supplies every
configure, login, attribute, CustomerInfo, offering, purchase, restore, UIKit,
and logging effect.

The coordinator preserves the existing provider ordering contract. A newer
identity request publishes its requested state immediately, waits for any older
provider operation even if that operation ignores cancellation, rechecks its
exact generation before executing, and is the only request allowed to commit.
Explicit purchase-identity resolution invalidates in-flight work without asking
RevenueCat to create an anonymous customer. A same-provider Auth or binding
change retains the stable App User ID while immediately clearing account-bound
readiness, and task cleanup uses exact-ID compare-before-clear semantics. A
follow-up race audit also closes account-grant readiness when a handoff begins
while provider work is suspended: the older request may still commit its exact
identity, but its captured grant permission cannot override the newer monotonic
handoff fence even when the handoff clears before the operation resumes. A fresh
exact binding begun after that fence remains eligible to commit its permission
once the handoff is clear.

`RevenueCatManager.swift` remains below the final 600-line guard, and its
existing initializer and callable surface remain unchanged. Computed
read-throughs preserve observation of the nested coordinator without exposing
its mutation surface. The deterministic coordinator suite covers overlapping
cancellation-uncooperative links, invalidation, stale commits, same-provider
rebinding, handoff readiness, and stable-versus-legacy sign-out; the manager
suite adds a nested-observation regression. The architecture suite now freezes
the coordinator dependency boundary and final manager ceiling.

The ownership extraction changes no provider call or order, product identifier,
App User ID, subscriber attribute, API payload, persistence schema, feature
flag, or release control. The follow-up race fix intentionally tightens only the
fail-closed account-grant decision during a handoff/link overlap. Swift parsing,
strict affected-source SwiftLint, direct manager/coordinator and test
typechecking, byte-stable XcodeGen, project/source membership,
purchase-principal contracts, Markdown formatting, and whitespace validation
pass; the purchase-principal suite reports 23 passing tests, its cross-surface
migration contract reports 16, and the complete Edge suite reports 1,937 with
zero failures and one intentional disposable-database ignore. A follow-up
read-only contract audit found and corrected a stale Deno assertion that still
assigned relocated serialization policy to the manager, taught the
declaration-ownership matcher to recognize `final class`, and corrected
documentation that described the directly constructed coordinator as
initializer-injected. Host-side execution of the coordinator overlap cases and
architecture suite body also passes. The documentation follow-up records the
coordinator and monotonic overlap rule in the canonical purchase-principal RFC,
links the local ownership guide back to that contract, and distinguishes the
durable handoff state from its in-memory generation fence. Generic Xcode build
and simulator runtime tests remain unclaimed: this host cannot initialize
CoreSimulator and rejects SwiftPM's nested package sandbox before source
compilation.

### Purchase Principal Resolver Ownership

The Purchase Identity hygiene slice reduces the 702-line
`PurchasePrincipalResolver.swift` aggregate to a focused orchestration facade
and moves its declarations into feature-owned
`PurchaseIdentity/{Models,Policies,Stores,Services}` files. Domain mapping and
wire DTOs, deterministic capability/intent/fallback/secret policy, verified
capability and resolver-state persistence, secure randomness, and typed remote
operations now have distinct owners. The live remote adapter is the only new
owner that imports Supabase; it keeps all four exact request payloads private
and remains the sole caller of `resolve-purchase-principal` on iOS. The existing
`PurchasePrincipalResolver(client:keychain:)` construction and callable surface
remain source-compatible.

The review also narrows route-fallback classification to failures thrown by the
remote resolve operation. Local response validation can no longer enter the
compatibility fallback even if a future injected classifier is overly broad.
Definite route absence remains eligible only before stable activation; after
activation, it fails closed. No endpoint name, request or response field,
protocol version, Keychain key or accessibility, persistence format, provider
operation, feature flag, Auth-transition order, or release control changes.

The existing resolver tests move into the mirrored Purchase Identity package,
with new secure-state, injected interaction, and architecture suites. They
freeze typed resolve/prepare/claim/cancel forwarding, response and continuity
mapping, route-missing-only fallback, stable-activation downgrade prevention,
verified persistence, declaration uniqueness, dependency confinement, private
payload ownership, and a 250-line ceiling for every production file inside the
folder. The cross-language purchase-principal migration contract follows the
protocol and live-route declarations to their new owners.

A generic iOS Simulator build and the complete app/test build-for-testing pass
for both architectures. The focused runtime matrix passes 47 tests on an iPhone
17 Pro iOS 26.4.1 Simulator, including all 12 purchase-safe sign-out workflow
cases. The complete `merianTests` target then passes 3,020 tests with zero
failures or skips. Its first pass exposed one stale Core Network integration
assertion that still treated the Purchase Identity folder as a two-file journal
package; the correction leaves that suite responsible only for journal
integration and the new Purchase Principal architecture suite responsible for
the exact package inventory. Strict SwiftLint reports zero violations, and Swift
parsing, byte-stable XcodeGen, project/resource/source membership, event-routing
and adversarial routing, the 16-case cross-language purchase-principal contract,
all 1,937 Edge tests with one intentional disposable-database ignore, recursive
Supabase formatting/linting, DTO and tooling gates, skill-link validation,
changed-Markdown formatting, and whitespace checks pass.

A subsequent adversarial review closed two invariants exposed by extraction. The
now-module-visible secure-state owner validates an exact 64-character lowercase
SHA-256 activation fingerprint before invoking secure persistence. The shared
purchase identity timestamp policy now uses cached formatters and accepts both
the fractional PostgreSQL RFC 3339 value emitted by the Edge route and the
whole-second form already present in local evidence. Server-shaped interaction
and journal fixtures cover the fractional form; malformed and oversized values
remain fail-closed. This corrects client acceptance of an existing response
contract without changing any payload, Keychain format, expiry authority, or
rollout behavior.

### Core Security-wide Integration Audit

The 2026-09-06 integration audit reviews the joined boundary from Supabase Auth
adoption through purchase-principal resolution, RevenueCat identity/read state,
server entitlement, scan admission, and consent. The extracted owners remain
appropriately scoped: deterministic policy and secure persistence stay below
`Core/Security`, live Auth and Supabase orchestration stay in `SupabaseManager`,
and the one provider facade remains `RevenueCatManager`. Immutable RevenueCat
identity request/link snapshots now live with the other value models; nested
coordinator typealiases preserve existing call sites without compressing the
coordinator against its line ceiling. No new singleton, general raw-network
escape hatch, wire field, persistence schema, provider product, feature flag, or
navigation contract is introduced.

The audit closes three cross-owner gaps:

- An Auth listener event that replaces either the UUID or anonymous/account kind
  now invalidates the purchase-principal binding, RevenueCat paid readiness, and
  current-launch server entitlement synchronously before publishing the new
  session. A replacement account can no longer observe the prior account's paid
  or complimentary state while its asynchronous identity link is starting.
- RevenueCat CustomerInfo, offerings, purchases, restores, and subscription-
  management presentation capture an exact App User ID plus monotonic identity-
  request and handoff generations. A completion that crosses either fence is
  discarded, including a same-provider-principal rebind or a handoff that starts
  and finishes while provider work is suspended. The trusted handoff-only
  StoreKit synchronization bypasses pending-handoff purchase readiness so it can
  execute the protocol, but captures and rechecks that same monotonic context.
- `ScanAdmissionManager` no longer constructs an ad hoc unpinned bearer-token
  session. Its PostgREST callback can dispatch only the exact authenticated
  `get_my_scan_admission_preview` RPC through `MerianNetworkClient` and the
  existing certificate-pinned session; missing or blank bearer and anon-key
  credentials fail before dispatch. `PinnedNetworkTransport` provides the
  existing no-cache, no-connectivity-wait two-second request and wall-clock
  deadline; PostgREST still performs no retry, and its private response value
  retains compiler-checked `Sendable` isolation without an unchecked
  conformance.

The production deploy workflow's `main` push scope now follows the extracted iOS
cross-surface contract owners: `SupabaseManager`, the exact scan-admission
bridge in `MerianNetworkClient`, `PinnedNetworkTransport`,
`Core/Network/Auth/**`, and `Core/Security/**`, in addition to the generated
inference DTO and Supabase tree. Workflow-security and candidate-detector
regressions freeze representative Auth, consent, purchase-principal,
scan-admission, and pinned-transport paths so a later ownership move cannot
silently skip the complete predecessor gate. This trigger widening does not
authorize deployment; the existing candidate validation, source hold, Production
approval, exact-SHA evidence, and smoke gates remain unchanged.

Regression coverage now locks account-replacement ordering, every provider-read
fence generation, handoff-only StoreKit context capture before provider
suspension and recheck afterward, exact scan-admission route/header confinement,
bounded pinned dispatch including cancellation of a non-completing request at
its deadline, sole URLSession ownership, no-retry admission, and the updated
workflow scope. The audit retains the established 600-line ceilings for the live
RevenueCat and Core Network facades.

### Core Data OfflineSync Foundation

The first Core Data OfflineSync pass removes the 1,227-line
`OfflineSyncTypes.swift` aggregate and gives its declarations focused owners
under `OfflineSync/Models`, `Policies`, and `Coordinators`. It also extracts
retry/storage policy, SwiftData job lookup helpers, and the private diagnostics
implementation from `OfflineQueueDurability.swift` into the corresponding
`Policies`, `Persistence`, and `Services` owners. The residual durability file
contains only the live `OfflineQueueManager` state mutations and retry
orchestration. Every extracted owner and that residual stay below the 600-line
review ceiling.

The pass preserves every declaration name and call-site signature, current and
legacy URLSession task-description formats, persisted metadata keys, upload
manifest semantics, SwiftData model shape, queue transition, retry decision,
endpoint, feature-flag, authentication, and lifecycle contract. Models and
stateless policies cannot resolve singletons, own observable state, or launch
detached work. The main-actor generation task registry retains private mutable
entries; diagnostic DTOs, redaction policy, and pruning remain private to the
diagnostics service implementation.

Existing tests are rehomed without dropping test names: staging manifest and
budget policy, server-authoritative staging identity, exact upload-completion
accumulation, inference task identity, retry/backoff, and generation task
cancellation now mirror their production owners.
`OfflineSyncFoundationArchitectureTests` freezes exact declaration locations,
framework imports, file ceilings, dependency restrictions, private state, the
retired aggregate, and the existing external-import retry fence. Integrated
queue, actor, URLSession, and endpoint behavior remains with the established
suites. The
[Offline Sync README](../../apps/ios/Merian/Core/Data/OfflineSync/README.md)
records these boundaries and identifies the behavior-heavy queue, sync, and
URLSession extensions as the work remaining after the first slice. The sync
owner is closed by the following slice; queue and URLSession extraction remain
separate work.

Verification for this pass includes byte-stable XcodeGen output, generated
project/resource and source-membership checks, the iOS build/test workflow and
complete CI-tooling regression suite, Swift parsing, strict SwiftLint with zero
violations across production and affected tests, changed-Markdown formatting,
and whitespace validation. The generic iOS Simulator build and complete
build-for-testing both pass with code signing disabled. The focused OfflineSync
matrix passes 108 tests on an iPhone 17 Pro iOS 26.4.1 Simulator; after the
final test-helper cleanup, the directly affected manager, architecture, and
inference task-contract subset passes again. The complete `merianTests` target
passes 3,030 tests with zero failures or skips.

A follow-up review expanded the architecture guard from representative owners to
every relocated declaration and the exact focused-file/framework-import
inventory. It also corrected documentation that had described file-inspecting
storage/staging policy and jittered retry timing as pure or deterministic; these
owners are stateless, while their inputs can include filesystem state and
bounded randomness. After that correction, byte-stable XcodeGen, project and
source-membership guards, the iOS build/test workflow, CI-tooling tests, generic
Simulator build-for-testing, Swift parsing, strict SwiftLint across 1,043 Swift
files, Markdown formatting, and whitespace validation pass. CoreSimulatorService
then refused connections, so runtime tests could not be repeated after the
guard-only correction; the earlier 108-test focused run and 3,030-test complete
run remain the runtime evidence for the behavior-identical source split.

### Core Data OfflineSync Sync Orchestration

The second Core Data OfflineSync slice removes the 1,666-line
`OfflineQueueManager+Sync.swift` aggregate. Cloud deletion and collection sync
now have focused owners under `Services/CloudDeletion` and
`Services/Collections`. Media upload is separated under `Services/MediaUpload`
into orchestration, generation lifecycle, preparation, and dispatch/recovery
files. No production file in this slice exceeds the 600-line review ceiling.

The move preserves all 34 sync declarations and their implementation bodies. The
private `UploadDispatchResult` carrier becomes a labeled tuple so it does not
need broader visibility after the split. Three formerly file-private helper
bridges—upload preparation, dispatch, and signing-failure handling—are narrowly
module-internal because their callers now live in the sibling orchestration
file; file-local mutable dispatch state and every other local helper remain
private. Endpoint calls, queue transitions, actor hops, generation fences, retry
accounting, task-description formats, authentication leases, and background
URLSession behavior are unchanged.

Existing cloud-deletion, collection-sync, upload batching, and request-policy
tests move from `OfflineQueueManagerTests` into focused mirrored suites without
changing or dropping a test declaration. A namespaced `OfflineSyncTestSupport`
owner provides the shared isolated-store and repository-source fixtures rather
than coupling the new suites to private helpers in the residual aggregate suite.
`OfflineQueueSyncArchitectureTests` freezes the current eight-file inventory,
declaration and framework-import ownership, responsibility boundaries, private
state, retired aggregate, and 600-line ceiling. Follow-up review removed the
isolated-store helper's hidden singleton mutation: each serialized caller now
explicitly installs and restores the manager context, and the architecture suite
rejects a return to implicit shared-state installation.

The iOS build-and-test workflow contract now follows the focused owners instead
of inspecting the retired aggregate. It requires the two live-task
reconciliation scans in `UploadSync`, the third in `UploadDispatch`, and keeps
request policy, durable activation, Auth-lease retention, and
activation-before-resume ordering checks with the dispatch owner.

Documentation closure redirects current upload/retry references to the focused
owners and corrects the historical-ingest checkpoint documentation from 50 to
the then-existing centralized value of 100. Neither correction changes runtime
policy.

Verification for this slice includes byte-stable XcodeGen output, project and
source-membership validation, the complete iOS CI-tooling regression suite, an
exact 34-declaration implementation-body comparison, the complete 77-test
selector/rehome inventory, the 34-owner architecture mirror, Swift parsing,
strict SwiftLint across every changed Swift file, changed-Markdown formatting,
and whitespace validation. A generic iOS Simulator build-for-testing passes for
both Simulator architectures with code signing disabled, including the complete
app, `merianTests`, and UI test bundles. Runtime execution of the focused matrix
and complete unit target could not run because CoreSimulatorService refused the
device-set connection at Simulator discovery; no runtime result is inferred from
the successful build.

### Core Data OfflineSync Queue Maintenance

The third Core Data OfflineSync slice moves queue count projection, failed-state
tombstoning, main-context flushes, explicit deletion, and purge out of
`OfflineQueueManager+Queue.swift`. `Services/QueueMaintenance` separates the
state mutations from the destructive workflow; both focused production files
remain below the 600-line review ceiling. The residual aggregate retains
funding, Field Trip replay, capture admission, retry/cancel, and uploaded-scan
inference replay.

The extraction preserves the public manager signatures, queue transitions,
notification behavior, persistence locking, generation and server-poll fences,
URLSession cancellation, adopted-media exclusions, database-first commit, file
cleanup, scheduling, and library-change publication. The formerly private
offline-job lookup and preferred-goal-hint deletion are not widened on the
manager. They become narrow `ModelContext` persistence helpers consumed by all
queue owners.

`QueueMaintenanceTests` rehomes the aggregate's tombstone, automatic-work count,
purge, and flush coverage and adds an explicit retained-attention failure plus
goal-hint cleanup assertions. Existing `OfflineQueuedScanDeletionTests` retain
the generation-fenced and disk-deletion integration cases.
`OfflineQueueMaintenanceArchitectureTests` freezes exact declaration and file
ownership, framework imports, private destructive helpers, persistence-lock
ordering, database-before-file deletion, and the 600-line ceiling.

The post-extraction audit compared the token stream of all seven moved manager
methods with their pre-extraction definitions, allowing only the intentional
calls through the new `ModelContext` helpers. It also corrected the manager's
source ownership inventory and closed a test-isolation leak:
`QueueMaintenanceTests` now restores the published unsynced count as well as the
injected context after every case. These review fixes do not change production
behavior.

Verification includes byte-stable XcodeGen output, project and source-membership
validation, the complete iOS CI-tooling and event-routing contract suites, the
seven-method equivalence comparison, full current-source Swift semantic
typechecking, focused maintenance-test semantic typechecking, Swift parsing,
strict SwiftLint with zero violations, changed-Markdown formatting, and
whitespace validation. A current `xcodebuild build-for-testing` and simulator
runtime execution remain unavailable in this environment because
CoreSimulatorService cannot provide a device set and SwiftPM cannot write its
manifest diagnostics cache through the sandbox. No build or runtime result is
inferred from the semantic checks.

This slice changes no endpoint, payload, task-description, SwiftData schema,
queue-state, retry, authentication, funding, lifecycle, feature-flag, or
navigation contract.

### Core Data OfflineSync Queue Admission and Replay

The fourth Core Data OfflineSync slice retires the 1,598-line residual
`OfflineQueueManager+Queue.swift`. Seven focused owners under
`Services/CaptureAdmission`, `Services/Funding`, `Services/FieldTripProgress`,
and `Services/InferenceReplay` separate capture-file persistence, visual and
nonvisual admission, the Describe compatibility entry point, live foreground
handoff, funding reconciliation, durable goal-hint replay, and uploaded-scan
inference reconciliation. No production file in the slice exceeds 600 lines.

All 26 manager method implementations are token-equivalent to the pre-split
source after mapping the four calls into the stateless
`OfflineCaptureFileStore`. Six additional equivalence checks cover byte
estimation, shared file-list persistence, the removed duplicate audio/video
wrappers, single-file moves, and captured-media serialization. Public manager
signatures, actor isolation, funding claims, queue transitions, file rollback,
media ordering and source indices, task descriptions, generation fences, status
recovery, URLSession dispatch, and Field Trip semantics are unchanged.

Ten existing tests move from the 2,812-line aggregate into
`CaptureAdmissionTests`, `LiveCaptureLifecycleTests`, and `InferenceReplayTests`
without dropping or duplicating a declaration. Capture tests now install and
restore shared manager state explicitly and await visual queue persistence
through the existing completion callback instead of fixed sleeps. The XCResult
validator follows the exact protected replay and durable capture cases to their
new suites, and its positive, missing-suite, missing-case, duplicate, failed,
skipped, and incomplete-result fixtures remain green.
`OfflineQueueAdmissionArchitectureTests` freezes the seven production owners,
exact declarations and imports, private helper containment, the exact
`OfflineCaptureFileStore` consumer allowlist, durable-before-dispatch and
persistence-lock ordering, the three mirrored test owners, the retired
aggregate, and the 600-line ceiling.

A post-split review found no production behavior or concurrency defect. It
closed one encapsulation and test-contract gap by limiting
`OfflineCaptureFileStore` references to the store declaration and
`OfflineQueueManager+CaptureEnqueue.swift`, and by freezing each mirrored
suite's exact Swift type, display name, `.serialized` trait, and
`.sharedProcessState(.offlineQueueManager)` lease. These guardrails protect the
XCResult selectors and process-wide singleton fixtures without changing runtime
code.

Verification includes byte-stable XcodeGen output, project/resource and source-
membership validation, the complete iOS CI-tooling regression suite, 26 manager
method and six file-store equivalence checks, current-source Swift parsing,
focused iOS semantic typechecking with compiler macros loaded in process, and
strict SwiftLint with zero violations. A generic Simulator build-for-testing
passed after the production split and compiled the app, unit target, and UI
target. After the test rehome, a fresh build and runtime attempt could not enter
dependency resolution because CoreSimulatorService disconnected and SwiftPM
attempted to emit diagnostics into the sandboxed user cache; no runtime result
is inferred from the prior build or current semantic checks.

This slice changes no endpoint, JSON payload, task-description, SwiftData
schema, persistence, queue-state, retry, Auth, funding, Field Trip, lifecycle,
feature-flag, or navigation contract.

### Core Data OfflineSync Background Transfer Ownership (Pass 5A)

The fifth Core Data OfflineSync slice begins the 3,123-line
`OfflineQueueManager+URLSession.swift` extraction without widening its private
terminal-validation helpers. At that checkpoint, `Services/BackgroundTransfer`
established ownership of the lock-protected
`BackgroundURLSessionTerminalWorkTracker`, the system-completion fence, task
Auth-lease retention and bounded durable retirement, Auth-transition quiescence,
and the sole nonisolated URLSession delegate conformance. The root manager
retains only stored background-session, completion-handler, tracker, and lease
state; the residual URLSession pipeline retained private relaunched-task
validation plus upload/inference processing for the following slices.

The extracted tracker, completion boundary, five account-work methods, and
delegate extension are token-equivalent to their pre-split definitions. The
split preserves synchronous tracker registration before every asynchronous
handoff, durable retirement before transport cancellation, exact-session lease
reacquisition before the first actor suspension, terminal persistence before
lease/tracker release, and tracker drain before the iOS completion handler.

Seven tests move from `OfflineQueueManagerTests` into the serialized
`BackgroundTransferOwnershipTests` suite without changing or duplicating a test
name. `BackgroundTransferArchitectureTests` initially froze the three focused
files, exact declaration/import ownership, private tracker state, exact tracker
and lease-map consumers, residual private validation, registration and
quiescence ordering, mirrored test ownership, and the 600-line ceilings.

Verification includes a generic iOS Simulator build-for-testing for the app,
unit-test, and UI-test bundles plus 46 focused tests covering the new suites,
the residual manager suite, and media-upload sync on an iPhone 17 Pro iOS 26.4.1
Simulator. The complete `merianTests` target subsequently passed 3,047 top-level
tests, representing 5,031 parameterized executions, with zero failures or skips
on the same destination. Its canonical XCResult check exposed six stale suite
owners retained from the earlier queue-maintenance, staging, media-upload, and
cloud-deletion extractions. The validator and its positive, missing-suite,
missing-case, retired-owner, duplicate, failed, skipped, and incomplete fixtures
now bind those unchanged test names to their focused suites; validation against
the real complete-target result passes. XcodeGen regeneration, project/source
membership, Swift parsing, strict SwiftLint, the iOS CI-tooling suite, Markdown
formatting, and whitespace validation remain part of the slice closure.

A post-split concurrency review removed the tracker's production
`activeCountForTesting` surface and strengthened its tests to cover multiple
tokens, multiple concurrent waiters, exactly-once handler consumption, duplicate
finishes, and the idle fast path through observable behavior. The review also
corrected the pipeline documentation: `URLSession.allTasks` is only an
active-sibling wait signal; advancement requires the generation-scoped
successful-key accumulator to cover the exact expected media manifest. Current
Swift source parsing, focused iOS test-target typechecking, strict SwiftLint,
project generation, source membership, and documentation checks pass. A fresh
native build and runtime rerun could not start because CoreSimulatorService was
unavailable and SwiftPM attempted to write manifest diagnostics outside the
workspace sandbox; the earlier native results above remain historical evidence
and are not presented as execution of the added idle-path case.

This slice changes no endpoint, JSON payload, task-description, background-
session identifier, SwiftData schema, persistence transition, queue state,
retry, Auth, funding, lifecycle, feature-flag, or navigation contract.

### Core Data OfflineSync Background Terminal Routing (Pass 5B)

The next URLSession slice moves private relaunched-task owner validation and
adoption plus the three upload/inference terminal bridges into
`Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift`.
The routing owner verifies or atomically adopts exact-session work before it
forwards accepted callbacks to the residual upload/inference processors. A
rejected callback instead completes its bounded durable retirement before it
invalidates an upload generation or finishes a matching process-local inference
generation.

The shared rejected-work retirement mutation lives with Auth-bound account work
because both terminal routing and inference dispatch require the same
durable-before-cancel fence. Its internal visibility is constrained by an exact
three-file consumer allowlist. The two owner-validation helpers remain private
to terminal routing, and stored lease/generation state remains on the root
manager. Including the post-review guards below, this reduces
`OfflineQueueManager+URLSession.swift` from 2,740 to 2,500 lines without
changing callback order, actor isolation, cancellation, generation fencing,
background-session completion, or queue transitions.

`BackgroundTransferArchitectureTests` now freezes four focused production files,
the relocated declaration owners, private validation containment, exact
tracker/lease/retirement consumers, and registration, adoption, retirement, and
terminal-release ordering. A post-extraction review also closed a pre-existing
fail-closed mismatch in inference dispatch: exhausted retirement of a newly
created but unresumed task now preserves its active process generation alongside
the durable `.inferencing` owner instead of finishing the generation before the
queue transition commits. The same review now closes the complementary delayed
success path: an Auth sweep or rejected terminal callback that later commits
retirement immediately finishes the exact process generation; the Auth sweep
does so before transport cancellation. The architecture suite freezes the
successful retirement/completion/cancellation path, the completion consumer
allowlist, and failed-retirement preservation. The focused iPhone Simulator
matrix passes 58 tests across the architecture, ownership, residual
queue-manager, media-upload, and sync-state suites on iOS 26.5. The complete
`merianTests` target passes 3,049 tests with zero failures or skips from the
same current build products. Swift parsing, strict SwiftLint, byte-stable
XcodeGen regeneration, project and source-membership validation, the iOS
CI-tooling suite, and a generic iOS Simulator build also pass.

This slice changes no endpoint, JSON payload, task-description, background-
session identifier, SwiftData schema, persistence transition, queue state,
retry, Auth, funding, lifecycle, feature-flag, or navigation contract.

### Core Data OfflineSync Upload Completion and Queue Extraction (Pass 5C)

The third URLSession slice moves generation-fenced upload callback processing
into `Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift`. That
focused owner retains successful-member accumulation, transport and HTTP
fallback classification, exact-manifest confirmation, durable `.staged` commit,
unsupported-audio quarantine, foreground-inference exclusion, preparation
ownership, and the handoff to background inference. Its completion-only metadata
and fallback helpers remain private. Upload generation validation/invalidation
moves beside sync completion and expiry in `UploadLifecycle`; stored generation
and callback state stays on the root manager.

`Persistence/OfflineQueueManager+QueuedScanExtraction.swift` now owns the
main-actor mapping from an `OfflineQueuedScan` SwiftData row to the Sendable
`ExtractedScanData` replay snapshot. The mapper uses the reusable
`ModelContext.preferredGoalHint(scanId:)` read paired with deletion in
`ModelContext+FieldTripGoalHints.swift`, so upload completion, inference replay,
and completed-server recovery do not duplicate the goal-hint fetch. The mapper
has no singleton, endpoint, URLSession, or application-container resolution.
These moves reduce the residual `OfflineQueueManager+URLSession.swift` from
2,500 to 1,924 lines; it now owns inference dispatch/result recovery plus retry
and probe lifetime rather than upload finalization.

Six deterministic queue-mapping tests move from the aggregate manager suite to
`QueuedScanExtractionTests` without changing their names or assertions. That
suite creates isolated stores without installing shared manager state. Seven
upload-generation, manifest, callback-token, durable-staging, and audio-format
fencing tests move to the serialized `MediaUploadCompletionTests` suite, which
retains the offline-queue shared-process lease and explicitly restores the
manager context it installs. `OfflineSyncFoundationArchitectureTests` freezes
mapper ownership, focused test ownership, and the exact
extraction/preferred-goal consumer allowlists.
`OfflineQueueSyncArchitectureTests` freezes the seventh live sync source,
completion-private helpers, generation-lifecycle ownership, mirrored test
ownership, exact imports, and the 600-line ceiling.

Verification includes current-source Swift parsing, strict SwiftLint with zero
violations, byte-stable XcodeGen regeneration, project/resource and source
membership validation, the complete iOS CI-tooling contract, Markdown
formatting, and a generic iOS Simulator build-for-testing that compiled the app,
unit-test, and UI-test targets. Runtime Simulator execution could not start
because CoreSimulatorService was unavailable; no runtime result is inferred from
the successful build.

A follow-up review rechecked completion-token lifetime, generation precedence
and invalidation, exact-manifest accumulation, durable staging outcomes,
unsupported-audio quarantine, foreground-inference exclusion, queued-row
mapping, and preferred-goal lookup semantics. No production correction was
required. The review corrected the current cleanup inventory and reliability
source map, then aligned the Audio, Field Trips, AI architecture,
database-actor, test-strategy, and codebase-map references with the focused
owners. Swift parsing, strict SwiftLint, byte-stable XcodeGen, project/source
membership, the complete iOS CI-tooling contracts, Markdown formatting, Supabase
tree formatting, and whitespace validation pass on the reviewed tree. A focused
runtime attempt could not start after CoreSimulatorService disconnected again
and SwiftPM was unable to emit diagnostics into the sandboxed user cache; it
supplies no test result.

This slice changes no endpoint, JSON payload, task-description, background
session identifier, SwiftData schema, persistence transition, queue state,
retry, Auth, funding, Field Trip, lifecycle, feature-flag, or navigation
contract.

### Core Data OfflineSync Background Inference Dispatch (Pass 5D)

The fourth URLSession slice moves the exact process-generation claim,
validation, and completion methods into
`Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift`. Its
sibling dispatch owner contains server-status preflight, generation checks
across every suspension, bounded request preparation, exact Auth-work lease
transfer, durable `.inferencing` activation, task identity, resume, and status-
probe handoff. Dispatch no longer reads the active-generation map directly; the
focused lifecycle seam is its only process-owner query.

`Policies/BackgroundInferencePolicy.swift` is the actor-independent owner of
platform-route and response classification, media-restaging decisions,
server-status recovery, retry-date parsing, dispatch admission, and the stable
consent-attention message. Keeping those decisions off the `@MainActor` manager
allows deterministic policy tests without creating a queue instance. The
residual `OfflineQueueManager+URLSession.swift` falls from 1,924 to 1,325 lines
and now owns accepted result processing, server-result hydration/recovery, and
retry/probe lifetime.

The extracted preparation race also closes two pre-existing timeout edges. It
emits the explicit timeout before cancelling the losing preparation and uses a
first-result stream boundary so returning does not depend on that operation
cooperatively observing cancellation. Late values are ignored. An actual caller
cancellation still surfaces as `CancellationError`, while an elapsed timeout
cannot nondeterministically look like preparation cancellation.

`BackgroundInferenceLifecycleTests` covers exact and idempotent claims, retired
generation rejection, legacy adoption, and replacement-generation completion
fencing under the shared offline-queue lease. `BackgroundInferenceDispatchTests`
covers preparation success, deterministic timeout/cancellation behavior, a
non-cooperative losing operation, suspension-point revalidation, and durable
retirement ordering. `BackgroundInferencePolicyTests` rehomes route, response,
restaging, status-recovery, and dispatch-admission cases from the aggregate
manager suite. `BackgroundInferenceArchitectureTests` freezes the three focused
owners, imports, declarations, exact cross-file consumers, direct-map
containment, mirrored test ownership, and both focused and residual line
ceilings.

A follow-up integration review corrected the remaining durability caller from
the retired manager-qualified retry-date parser to
`BackgroundInferencePolicy.parseRetryAfterDate`; the architecture suite now
freezes that qualified consumer. It also removed the permanently disabled
WeatherKit/geocoding branch from background request construction. Replay still
sends the same already-persisted telemetry without waiting on optional
enrichment.

Verification includes byte-stable XcodeGen output, project/resource and source-
membership validation, the complete iOS CI-tooling suite, current-source Swift
parsing, focused cached-module typechecking for lifecycle, dispatch,
architecture, and media-upload source guards, a standalone semantic typecheck of
the current actor-independent policy and its tests, and strict SwiftLint with
zero violations. Markdown formatting, the Supabase function/script format gate,
and whitespace validation also pass. The first generic Simulator
`build-for-testing` compiled both production architectures but exposed the
rehomed policy suite's missing actor context in the unit target; that issue is
fixed and covered by the successful focused typechecks. A fresh full build and
runtime rerun could not enter package resolution after CoreSimulatorService
became unavailable and SwiftPM attempted to emit manifest diagnostics into the
sandboxed user cache. No current full-build or runtime result is inferred from
the partial build or semantic checks.

This slice changes no endpoint, JSON payload, task-description, background
session identifier, SwiftData schema, persistence transition, queue state,
retry, Auth, funding, Field Trip, lifecycle, feature-flag, or navigation
contract.

### Core Data OfflineSync Background Inference Completion (Pass 5E)

The fifth URLSession slice moves accepted background inference task completion
into
`Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift`.
That focused owner now contains `processInferenceDownloadResult`,
`handleInferenceTaskNetworkFailure`, and the file-private
`cancelInferenceStatusProbe` helper. It owns response disposition, exact
generation claim and retirement, task-result file cleanup, final persistence
handoff, stale-completion revalidation, post-persistence side effects, and
transport-failure routing. Delegate adaptation remains under
`Services/BackgroundTransfer`; server-result recovery and retry/probe lifetime
remain in the residual URLSession extension.

The move preserves the critical ordering. Completion claims its generation
before mutating task state, cancels only the matching status probe, persists and
cleans the scan before user-facing side effects, revalidates ownership after
each suspension-sensitive phase, and retires only the exact claimed generation.
A stale callback still removes its task-specific result file but cannot clear a
replacement active generation, completion lock, dispatch timestamp, or status
probe. The residual falls from 1,325 to 945 lines; the completion owner is 390
lines, and every focused Background Inference production file remains below the
600-line review ceiling.

`BackgroundInferenceCompletionTests` adds serialized shared-state coverage for
exact cancellation retirement and probe cleanup, stale transport-failure
fencing, and stale result-file cleanup while preserving the replacement active
generation, completion lock, dispatch timestamp, and status-probe owner.
`BackgroundInferenceArchitectureTests` now freezes four production owners,
completion imports and declaration ownership, the exact lifecycle/helper
consumer sets, absence of direct network-client/background-session access in
completion, result-file cleanup registration before generation claim,
compare-before-clear completion teardown, persistence ordering, the mirrored
test suite, and a 1,000-line residual ceiling. The transfer and foundation
architecture suites were updated for the relocated consumers.

The stale comment that implied dispatch performed a WeatherKit backfill now
accurately states that completion consumes telemetry persisted before dispatch.
The follow-up review also made completion-lock diagnostics truthful: an exact
owner reports that its lock was cleared, while a stale teardown reports that the
replacement lock was preserved. No state transition, optional enrichment, or
direct endpoint call was added.

Verification includes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, current-source Swift parsing, strict SwiftLint
with zero violations, all six executable focused architecture tests, the
completion suite's strict iOS semantic typecheck, and every portable iOS
CI-tooling contract. Generic Simulator and device build-for-testing attempts
could not enter compilation because CoreSimulatorService was unavailable and the
local sandbox rejected SwiftPM's package-manifest helper. No completion runtime
result is inferred from those blocked attempts.

This slice changes no endpoint, JSON payload, task-description, background
session identifier, SwiftData schema, persistence transition, queue state,
retry, Auth, funding, Field Trip, lifecycle, feature-flag, or navigation
contract.

### Core Data OfflineSync Background Inference Watchdog (Pass 5F)

The sixth URLSession slice moves delayed inference status probing and exact
background-task inspection/retirement into
`Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift`. That
focused owner now contains `scheduleInferenceStatusProbe`,
`isLiveInferenceTask`, and the private exact-generation cancellation and active
task-count helpers. The residual URLSession extension retains server-result
hydration/recovery plus retry and server-poll lifetime.

The move preserves the existing cumulative 10-, 30-, and 65-second probe
schedule, server recovery before task cancellation, compare-before-clear probe
ownership, exact generation checks around every suspension-sensitive phase,
generation completion before retry, current and legacy task-description parsing,
and OS-owned background-session recovery. A replacement probe or generation
therefore cannot be cleared by the stale watchdog it displaced. The residual
falls from 945 to 766 lines; the watchdog owner is 196 lines, and every focused
Background Inference production file remains below the 600-line review ceiling.

`BackgroundInferenceWatchdogTests` adds serialized shared-state coverage for
probe replacement, current and legacy parsed task identity with terminal-state
rejection, and recovery-before-cancellation plus retirement-before-retry source
ordering. `BackgroundInferenceArchitectureTests` now freezes five production
owners, the watchdog's Foundation-only import and exact declaration ownership,
task/session and probe-registry consumer sets, mirrored test ownership, and an
800-line residual ceiling.

The follow-up review closed the remaining suspension fence inside the extracted
owner. Both `backgroundSession.allTasks` cancellation paths now revalidate the
exact probe token and active generation after task enumeration and before
clearing either owner. The focused ordering test requires those post-suspension
checks in both the server-owned and watchdog-deadline branches.

Verification includes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, current-source Swift parsing, strict SwiftLint
with zero violations, all six executable focused architecture tests, the
watchdog suite's focused iOS semantic typecheck, every portable iOS CI-tooling
contract, Markdown formatting, documentation-contract tests, and whitespace
validation. The CI workflow fixture preserves the former residual file's 12
connectivity-guard occurrences as an exact 11-in-residual plus 1-in-watchdog
ownership split; dispatch retains its separate five occurrences. A fresh generic
Simulator build could not enter compilation because CoreSimulatorService was
unavailable and the local sandbox rejected SwiftPM's package-manifest helper; no
runtime result is inferred from that blocked build.

This slice changes no endpoint, JSON payload, task-description, background
session identifier, SwiftData schema, persistence transition, queue state, probe
timing, retry policy, Auth, funding, Field Trip, lifecycle, feature-flag, or
navigation contract.

### Core Data OfflineSync Background Inference Recovery and Retry (Pass 5G)

The seventh URLSession slice retires the 766-line
`OfflineQueueManager+URLSession.swift` aggregate. Server-result lookup, durable
server-ownership evidence, targeted and full historical hydration, queue
cleanup, and server-owned orphan detection now live in
`Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift`.
Recovery also owns retryable server-status persistence and its
durable-wake-first post-save fence. Compare-before-clear server-poll ownership,
general transport-retry preflight/persistence, server polling, and generic retry
wake restoration live in
`Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift`.

Recovery is 598 lines after the follow-up concurrency fence, so its hydration
policy, retryable-status transition, and private mutation helpers stay
co-located rather than widening across files. Retry is 180 lines. The two
poll-ownership helpers consumed by Recovery are module-internal, and the
pre-existing retry entry point remains shared only by its focused pipeline
consumers; the architecture suite freezes all three exact consumer sets. All
seven focused Background Inference production owners—the stateless policy and
six service files—are below the 600-line review ceiling, and the retired
aggregate has no replacement catch-all.

`BackgroundInferenceRecoveryTests` rehomes the durable-found-evidence and
terminal-contract-mismatch cases. `BackgroundInferenceRetryTests` rehomes the
critical durable server-failure marker case and adds deterministic replacement
poll-token coverage. Both suites remain serialized and lease
`.offlineQueueManager` process state. The architecture suite freezes the new
owners, declarations, imports, cross-file consumers, mirrored suite ownership,
retired aggregate, and uniform production-file ceiling. The critical XCResult
gate now expects `scheduledServerFailureMarkerIsReadFromDurableStore` under the
Retry suite.

The final review closed a post-persistence ABA window in the retryable
server-status path. Once `scheduleInferenceRetry` commits, Recovery restores the
central persisted wake before checking task cancellation, network eligibility,
any supplied server-poll token, and inference-generation ownership. Only a
current caller may then replace the keyed process-local poll. This preserves the
durable retry when the awaiting poll is cancelled or replaced while preventing
stale work from displacing a newer poll. The architecture suite freezes that
exact order, and Recovery fixtures cancel any shared scheduler wake before
restoring the singleton manager context.

The OfflineSync-wide integration audit found and closed the equivalent window in
the general inference-retry path. Retry now restores the central persisted wake
immediately after the actor commits, before task cancellation, poll-token, or
generation revalidation can reject its process-local continuation. The
executable Retry suite proves a committed deadline can still arm from a
cancelled process owner, while the architecture suite freezes the production
persist/wake/revalidate/local-task order and forbids another suspension between
the persistence return and central wake restoration.

Verification includes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, portable CI-workflow and critical-result fixture
tests, Swift parsing, strict SwiftLint with zero violations, a direct semantic
typecheck of the complete current main-target source set, and executable
architecture coverage across all 22 OfflineSync ownership tests. The workflow
guard preserves the connectivity predicates as nine Recovery, three Retry, five
Dispatch, and one Watchdog occurrence; no reachability gate was dropped during
the move. The final review also completed a generic iOS Simulator build and full
build-for-testing with code signing disabled, the focused Background Inference
runtime suites, and the complete `merianTests` target: 893 XCTest cases plus
2,184 Swift Testing cases, 3,077 top-level tests and 5,061 expanded executions,
with zero failures or skips. The UI-test bundle compiled but was not executed.

This slice changes no endpoint, JSON payload, task-description, background
session identifier, SwiftData schema, persistence transition, queue state,
server-poll timing, retry policy, Auth, funding, Field Trip, lifecycle,
feature-flag, or navigation contract.

### Core Data Collection Sync Transaction Boundary

The first `BackgroundDatabaseActor` slice removes collection DTO construction,
live Supabase invocation, Auth-work handling, and acknowledgement orchestration
from the 3,266-line aggregate. The residual actor is 3,139 lines and no longer
imports Supabase. `BackgroundDatabaseActor+CollectionSync.swift` now owns only
the bounded non-Favorites relationship projection and conditional local purge;
`CollectionSyncSnapshot` is the immutable domain value; `CollectionSyncService`
owns the initializer-injected snapshot/request/commit transaction; and
`MerianNetworkClient+Collections.swift` owns the private snake-case request DTO
plus authenticated HTTP call. The existing `OfflineQueueManager` extension
retains durable job/retry, dirty-revision, single-flight, background-time, and
Auth-quiescence state.

The review closes a pre-existing stale-acknowledgement race rather than carrying
it into the new state owner. The service validates its exact outer account-work
lease after snapshot extraction and after the response. It then creates a fresh
database actor whose purge predicate includes both the acknowledged IDs and
`isPendingDeletion == true`. If another local context reactivates a collection
while the request is in flight, that row survives and the manager's newer dirty
revision drives the next desired-state push. The endpoint path, JSON keys,
timestamp formatting, body-ignoring 2xx semantics, server behavior, SwiftData
schema, job/retry policy, and call-site signatures remain unchanged. Moving the
call from the Supabase SDK's direct function invocation to the shared pinned
client gives it an explicit 30-second deadline and the existing transport
handling; the mutation gains no idempotency key or ambiguous-failure replay. The
shared encoded-body bridge retains classified-401 recovery by default, but
collection sync explicitly returns that failure to its durable retry owner.
Ordinary recovery quiesces the same collection task and outer account-work
lease, so initiating it from inside this request would create a self-wait.

`CollectionSyncTests` now owns the former actor-level projection and Auth-fence
regressions together with deterministic lease-acquisition, pre-dispatch,
post-response, remote-failure, confirmed-purge, and concurrent-reactivation
coverage. `CollectionSyncEndpointTests` owns exact request mapping through the
scoped client transport. The OfflineSync foundation/sync and Core Network
integration architecture suites freeze the model, service, actor extension,
endpoint, test rehome, dependency exclusions, and 600-line focused-owner
boundaries.

The candidate passes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, event-routing and CI-tooling guards, Swift
parsing, strict affected-source SwiftLint, Markdown formatting, and whitespace
validation. Generic iOS Simulator source and test-bundle compilation succeeds
for both architectures with code signing disabled; asset catalogs are excluded
from that pass's compile-only workaround because the host could not provide
Simulator runtimes at the time. A subsequent host recovery enabled the complete
`merianTests` runtime recorded in the next section, which also covers the
collection-sync suites; the earlier pass does not claim a separate focused
runtime result.

### Core Data Species Metadata Persistence Boundary

The second `BackgroundDatabaseActor` slice moves seven existing species-metadata
operations from the aggregate into the 307-line
`BackgroundDatabaseActor+SpeciesMetadata.swift` extension: Wikipedia and
reference-image patching, inference enrichment, bounded lookalike-cache
clearing, identification-override admission and mutation, override-species
hydration, and legacy unflagging. The shared fetch-mutate-save helper and the
destructive identification-presentation reset helper remain private to that
file. No call site, actor type, method signature, SwiftData schema, stored
value, endpoint, payload, Auth, feature flag, or UI contract changes; the
residual aggregate is 2,835 lines.

The ten pre-existing persistence regressions move without renaming into
`SpeciesMetadataPersistenceTests`, joined by a complete positive enrichment
field-persistence case. A shared isolated-container fixture removes duplicated
test setup while leaving each test responsible for its own store. The companion
architecture suite inventories the complete production and test Swift trees and
freezes all seven methods and all 11 behavior tests to one owner each. It also
locks the exact Foundation and SwiftData imports, private helper containment,
networking/Auth/file/UI dependency exclusions, and 600-line ceilings for the
focused production and behavior-test files. A follow-up review widened this
inventory from the immediate database folder and legacy aggregate test file so
the documented sole-owner guarantee is now repository-wide.

Fresh verification covers byte-stable XcodeGen output, generated-project and
source-membership validation, event-routing guards, Swift parsing, strict
affected-source SwiftLint with zero violations, Markdown formatting, and
whitespace validation. The generic iOS Simulator app build and complete
build-for-testing both succeed for arm64 and x86_64 with code signing disabled.
Runtime verification passes all 14 focused species-metadata persistence and
architecture tests, all 56 residual `BackgroundDatabaseActorTests`, and the
complete `merianTests` target. The complete result contains 3,088 passing
top-level tests and 5,072 passing expanded executions, with zero failures,
skips, or expected failures.

### Core Data Non-Biological Retention Persistence Boundary

The third `BackgroundDatabaseActor` slice moves the existing erasure payload,
purge result, bulk-delete transaction, and bounded expired-record purge from the
aggregate into the 132-line
`BackgroundDatabaseActor+NonBiologicalRetention.swift` extension. The residual
aggregate is 2,744 lines. The focused owner retains the actor, nested-type
identities, and method signatures; its mixed-media payload member is accurately
named `mediaPaths`. Commit-time biological revalidation, idempotent
`PendingCloudDeletionTask` creation, rollback behavior, save-before-path-return
ordering, retention batch size, and oldest-first selection remain intact. A
follow-up review also makes the shared transaction distinguish accepted erasure
work from rows actually deleted. `ScanRepository` drains local paths and cloud
tombstones for accepted missing rows, publishes library changes only for real
row deletion, and emits no effects for stale candidates rejected during
revalidation. The focused owner imports only Foundation and SwiftData and
performs no endpoint, Auth, file, or UI work. No SwiftData schema, endpoint,
wire payload, navigation, feature-flag, or persistence contract changes.

The four pre-existing actor regressions move without renaming into
`NonBiologicalRetentionPersistenceTests`. They cover commit-before-file handoff,
existing tombstone reuse, commit-time reclassification fencing, and expired-only
mixed-media purge. Follow-up cases freeze idempotent missing-row cleanup and the
oldest-first batch limit. The companion architecture suite inventories the
complete production and test Swift trees, freezes both methods, both nested
values, and all six behavior tests to one focused owner each, and enforces exact
imports, committed-count fencing, repository effect routing, dependency
exclusions, and 600-line ceilings. The shared database-actor test support now
owns the repository Swift-source inventory used by both this guard and the
species-metadata guard.

Fresh verification passes byte-stable XcodeGen regeneration, generated-project
resource and source-membership validation, event-routing guards, Swift parsing,
strict affected-source SwiftLint with zero violations, Markdown formatting, and
whitespace validation. The generic iOS Simulator build succeeds for arm64 and
x86_64 with code signing disabled. Before the follow-up cases were added,
runtime verification passed the original seven focused non-biological-retention
persistence and architecture tests, all 52 residual
`BackgroundDatabaseActorTests`, and the complete `merianTests` target. That
complete result contained 3,091 passing top-level tests and 5,075 passing
expanded executions, with zero failures, skips, or expected failures. The
focused Non-biological Collections Back-navigation UI regression also passed.

The follow-up correctness and documentation review passes byte-stable XcodeGen,
project/resource and source-membership validation, event-routing guards, Swift
parsing, strict affected-source SwiftLint with zero violations, Markdown
formatting, Supabase candidate formatting, and whitespace validation. Simulator
build and runtime selectors could not be repeated in the restricted review
environment because CoreSimulatorService was unavailable and SwiftPM manifest
sandboxing could not start; those checks remain required in CI and are not
represented as passed by the follow-up.

### Core Data Unsupported Queued-Audio Fence

A follow-up producer audit found no supported installed population for the
queued-audio conversion path. Standalone iOS audio capture and video companion
tracks have written local WAV files since their initial implementations. The
only M4A capture producer is watchOS, which has no supported receiver into the
iOS inference queue. Historical Explore publication playback and restore are a
separate domain. The speculative conversion state machine, its actor extension,
its transient value types, and its repair-specific suites were therefore removed
rather than retained as unexercised queue complexity.

The replacement is a smaller fail-closed boundary. Upload preparation rejects
unsupported audio before signing. Upload completion checks the persisted media
snapshot and quarantines a surviving callback before durable `.staged`
finalization. Staged replay applies the same quarantine before dispatch, and
`BackgroundDatabaseActor.tryClaimForInference` independently refuses any remote
or non-WAV audio reference. `QueuedInferenceMediaPolicy` owns the storage-aware,
manifest-only decision instead of placing queue behavior on the persisted media
model. Queue Maintenance owns the shared needs-attention boundary: ordinary rows
receive `queued_media_invalid`, while a completed cloud-result marker and
funding evidence remain intact so retry can hydrate that result without another
provider request. No queue owner transcodes or rewrites persisted inference
media.

`QueuedInferenceMediaPolicyTests` freezes the accepted local-WAV manifest
boundary; `MediaStagingBudgetTests`, `MediaUploadCompletionTests`,
`QueueMaintenanceTests`, and `BackgroundDatabaseActorTests` cover pre-signing
rejection, callback quarantine ordering, completed-result and funding
preservation, durable attention state, and the final claim fence. OfflineSync
architecture suites freeze the policy, preparation, completion, replay, and
maintenance ownership. The released V49+ `queueSchemaRepairGeneration` property
remains inert in V51, preserving the schema shape without carrying runtime
repair semantics.

The initial removal slice passed a fresh generic iOS Simulator
build-for-testing, all 118 focused queue/audio selections, and the complete
`merianTests` target at 3,093 top-level tests (5,077 expanded parameterized
cases), with zero failures and zero skips. The follow-up ownership and
completed-result corrections add one deterministic recovery case after that
execution. On the corrected tree, byte-stable XcodeGen regeneration,
project/resource and source-membership validation, migration guardrails, the
complete iOS CI-tooling contract, Swift parsing, and strict affected-source
SwiftLint with zero violations pass. Changed Markdown, the complete Supabase
Function/script tree, the 26-test documentation contract, changelog JSON, and
whitespace validation also pass. Clean build and simulator-test reruns for the
corrected tree are not represented as passed because CoreSimulatorService and
SwiftPM manifest sandboxing are unavailable in the current environment.

### Core Data Queue Selection Persistence Boundary

Pending upload selection and empty-media quarantine now live in the 253-line
`BackgroundDatabaseActor+QueueSelection.swift` extension. The actor method
signatures and Media Upload call sites are unchanged. The focused owner
preserves complete pending-set paging, retry deadlines, live-transfer
exclusions, current video eligibility and forced-video exceptions,
deferred-Flash exclusion, stable funding-tier priority, and the independently
bounded media-less candidate set. It reuses the existing
`ModelContext.fetchOfflineJob` helper rather than adding another job lookup.

A follow-up correctness review closes two swallowed SwiftData error paths.
Unreadable funding jobs now fail selection closed instead of collapsing every
row into the legacy compatibility tier. A matching-job fetch failure now rolls
back the quarantine batch instead of allowing scan and event state to commit
without updating an existing job. Missing jobs remain supported for legacy rows,
and there are no success-path ordering or transition changes.

Quarantine re-fetches candidates in the actor context and mutates only rows that
are still pending, are not already marked for attention, and still have no local
upload media. The scan failure, matching job state, and diagnostic event remain
one atomic save with rollback on failure when that job exists. `UploadSync` is
the sole production consumer and continues to own transient upload/network
decisions. No SwiftData schema, stored value, queue transition, funding, retry,
endpoint, payload, authentication, file, or UI contract changes in this slice.
The residual actor aggregate is 2,195 lines.

Four existing actor cases moved to `QueueSelectionPersistenceTests`, and a
deterministic funding-priority case was added there. The focused architecture
suite freezes declaration and behavior-test ownership, the exact Upload Sync
consumer allowlist, shared-helper reuse, dependency exclusions, and both focused
files' 600-line ceilings. The quarantine fixture covers both an existing
matching job and the supported legacy missing-job path. The critical-XCResult
validator now maps its protected paging, funding-priority, and quarantine
regressions to the focused suite. XcodeGen includes the three new Swift files;
project and source-membership validation, migration guardrails, Swift parsing,
strict affected-source SwiftLint, and a generic code-signing-disabled Simulator
build pass. A fresh queue-selection build and runtime pass executes all 56
focused, residual actor, and Upload Sync tests with zero failures. The same
candidate's serialized complete `merianTests` run passes 3,103 top-level tests
and 5,087 expanded executions with zero failures, skips, or expected failures.
An earlier Simulator host exited before XCTest connected and executed no
assertions; the clean rebuilt and complete passes supersede that runner failure.

### Core Data Upload Lifecycle Persistence Boundary

Upload claim, staging commit, and orphaned-upload release now live in the
356-line `BackgroundDatabaseActor+UploadLifecycle.swift` extension.
`ScanStagingTransitionOutcome` moved with its sole persistence producer. Actor
method signatures and every Media Upload or Inference Replay call site remain
unchanged; signing, URLSession enumeration, live path policy, callback
accumulation, and orchestration stay outside the database owner.

The scan/job retry mirror is also no longer a private method stranded in the
aggregate. The 59-line `BackgroundDatabaseActor+RetryMirror.swift` extension
contains that shared mutation, and an architecture allowlist admits only the
residual inference transitions and the upload-lifecycle extension. Compiler
actor isolation prevents the helper from becoming an unisolated SwiftData
mutation boundary. It creates no singleton or mutable process state. The
aggregate falls from 2,195 to 1,836 lines without a SwiftData schema, stored
value, queue transition, retry, task-description, endpoint, payload,
authentication, file, or UI contract change.

Ten existing actor cases moved unchanged to `UploadLifecyclePersistenceTests`.
They cover pending-only claim, all four staging outcomes, scheduled server-retry
preservation, scan/job orphan release, empty active-task recovery, and the
existing task-snapshot plus candidate fences. `UploadLifecycleArchitectureTests`
freezes declaration and outcome ownership, exact production consumers,
actor-isolated retry-support consumers, narrow dependencies, mirrored test
ownership, both focused 600-line ceilings, and a 1,900-line residual-aggregate
non-growth cap. The critical-XCResult contract now maps scheduled retry survival
and durable orphan release to the focused suite.

The follow-up review also removes the two remaining swallowed matching-job
lookups. Claim and orphan recovery now use the shared throwing lookup and roll
back the complete batch when SwiftData cannot determine whether a matching job
exists; a successful lookup returning no legacy job remains supported. The
architecture suite prevents `try?` from reintroducing partial scan/job commits.

Verification passes byte-stable XcodeGen regeneration, project and source
membership validation, migration guardrails, the complete iOS CI-tooling
contract, Swift parsing, strict affected-source SwiftLint with zero violations,
the code-signing-disabled generic Simulator build, and the complete app-and-test
build-for-testing. Markdown formatting and whitespace validation also pass.
Runtime Simulator execution is not represented as passed because the local
CoreSimulatorService is unavailable; the moved behavior remains covered by the
same compiled test bodies and protected critical-XCResult selectors.

### Core Data Background Account Work Persistence Boundary

Durable background-account activation, exact-owner validation, candidate
selection, and retirement now live in the 326-line
`BackgroundDatabaseActor+BackgroundAccountWork.swift` extension. The actor and
four public method signatures are unchanged. Background Transfer retains Auth
leases, transition quiescence, terminal routing, and URLSession cancellation;
Media Upload retains request dispatch and its signing-failure retirement call
site. The extracted owner performs only SwiftData reads and mutations.

Activation still commits the exact Auth UUID, generation, and upload/inference
phase before a task resumes. Retirement still verifies that exact owner and
commits pending queue state, clears source-account staging keys, and removes the
marker before transport cancellation. All three scan/job decision paths now use
throwing reads, log the private SwiftData error, and fail closed instead of
silently treating SwiftData failure as a missing record. This is a diagnostic
and safety tightening; it does not change the missing-row compatibility behavior
or any schema, stored field, task description, endpoint, payload,
authentication, navigation, file, or UI contract.

The three existing actor regressions moved unchanged to the 337-line
`BackgroundAccountWorkPersistenceTests`, which also proves activation creates
the missing ingestion job for a legacy scan. The 249-line
`BackgroundAccountWorkArchitectureTests` freezes sole declaration and test
ownership, exact Background Transfer and Media Upload consumers, throwing reads,
balanced per-scan persistence fences, narrow dependency exclusions, 400-line
focused owner/test ceilings, and a 1,600-line residual-aggregate cap. The
aggregate falls from 1,836 to 1,559 lines.

Verification passes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, migration guardrails, Swift parsing, strict
affected-source SwiftLint with zero violations, the complete iOS CI-tooling
contract, event-routing validation and adversarial fixtures, Markdown
formatting, and whitespace validation. The generic code-signing-disabled
Simulator build and complete `build-for-testing` action pass. Runtime
verification passes the exact Background Transfer/Inference Dispatch/Media
Upload caller matrix, every focused and residual database-actor suite, and the
complete `merianTests` target. The complete result records 5,103 successful
expanded executions with zero failures, skips, or expected failures.

### Core Data Inference Persistence Boundaries

Durable inference lifecycle and retry mutations now live in the 564-line
`BackgroundDatabaseActor+InferenceLifecycle.swift` and 290-line
`BackgroundDatabaseActor+InferenceRetry.swift` extensions. The lifecycle owner
contains server-owned eligibility reads, staged/inferencing claims and retreats,
background/live generation validation, telemetry hydration, and timestamp-fenced
orphan release. The retry owner contains general and server-result recovery
retry commits. Offline Sync call-site spelling is unchanged; orphan
reconciliation is now explicitly asynchronous so it can wait for the shared
persistence fences. Process generations, scheduling, URLSession/network effects,
task cancellation, Auth, file I/O, finalization, and UI remain with their
established owners.

The extraction closes the residual silent-read ambiguity. Every lifecycle and
retry scan/job decision uses a throwing fetch and private diagnostic context, so
storage failure cannot be interpreted as an absent legacy row. Genuine
missing-job compatibility remains: an unfenced legacy claim or relaunch retry
creates the ingestion job only after all required reads succeed. Orphan
reconciliation acquires candidate fences in stable ID order, rereads durable
eligibility in a fresh context after waiting, and preloads every candidate job
before its first mutation. Newer terminal work wins and one failed lookup still
aborts the full batch. Claim, retreat, and both retry entry points also release
the per-scan persistence fence when cancellation is already observed after
acquisition.

The moved behavior lives in the 576-line `InferenceLifecyclePersistenceTests`
and 435-line `InferenceRetryPersistenceTests`; focused cases add missing-job
compatibility for claims and both retry modes, cancellation fence release, and
post-wait terminal-state preservation during orphan recovery. The 456-line
`InferencePersistenceArchitectureTests` freezes sole declaration/test ownership,
exact production consumers, throwing read counts, orphan-batch preload, private
helper containment, balanced fences, narrow dependencies, 600/400-line
production ceilings, 600-line behavior-suite ceilings, and the 1,000-line
residual aggregate cap. The aggregate falls from 1,559 to 942 lines. The
critical-XCResult validator now maps monotonic retry authority and
cloud-complete veto to the focused retry suite.

Verification passes byte-stable XcodeGen regeneration, project/resource and
source-membership validation, migration guardrails, Swift parsing, strict
affected-source SwiftLint with zero violations, the complete iOS CI-tooling
contract, Markdown formatting, and whitespace validation. The generic
code-signing-disabled Simulator app build and complete `build-for-testing`
action pass. Runtime verification passes the focused lifecycle/retry,
architecture, aggregate, and neighboring upload-lifecycle matrix plus the
complete `merianTests` target on iOS 26.5.

### Core Data Scan Finalization Boundary

The former 942-line `BackgroundDatabaseActor` aggregate is now a
declaration-only 9-line `@ModelActor`. Live visual/nonvisual persistence,
prepared offline-result persistence, shared actor-isolated scan-record support,
complete record mapping, and ordered captured-media serialization have focused
owners. Every production file in this slice is below 600 lines. The existing
`saveLiveScanRecord` and `saveNonVisualRecord` signatures, media order, field
note preservation, discovery rules, generation fences, rollback behavior, and
main-context queue-deletion contract remain unchanged.

Background URLSession completion now enters
`BackgroundInferenceFinalizationService`, which injects response preparation and
a fresh persistence actor. `InferenceResponsePreparationService` is the single
stateless foreground/background owner for JSON decoding, usable-success
validation, request-appropriate response-ID comparison, `SpeciesData` mapping,
and immutable funding-settlement projection; it performs no account or queue
effects. Background and other client-ID-bearing paths require an exact echo;
queue-less nonvisual compatibility retains the server-assigned response ID. The
finalizer never awaits `InferenceProcessingActor` while holding
`ScanInferencePersistenceCoordinator`; that dependency direction avoids a cycle
with a foreground parse already waiting for the same scan fence. SwiftData
validation and commits remain on the database actor, file adoption remains on
`FileIOActor` behind narrow closures, and queue deletion remains on the main
actor after exact-generation revalidation.

The settlement crosses the actor boundary as checked-Sendable domain values and
remains inert until that exact queue deletion commits. The focused Offline Sync
funding owner then applies entitlement, advisory usage, and funding-reservation
effects under account-work leases retained through its injected, coalesced,
Auth-drained `InferenceFundingReconciliationOwner`.

`CapturedMediaPersistenceServiceTests` deterministically cover explicit and
default timeline order, invalid-item filtering, video companions, and
standalone-audio source identity. `ScanFinalizationArchitectureTests` freezes
declaration ownership, focused size/dependency limits, coordinator containment,
shared response preparation, compiler-checked response/result sendability, and
the no-finalizer-to-processing-actor rule.
`BackgroundInferenceArchitectureTests` inventories the finalization service and
its sole consumers; the later Core Data-wide audit adds reconciliation as the
eighth focused service. Existing `BackgroundDatabaseActorTests` retain
end-to-end persistence, collision, generation, malformed-success, and
confidence-zero behavior.

XcodeGen regeneration, Swift parsing, the generic code-signing-disabled
Simulator app build, and the complete app-and-test `build-for-testing` action
pass after the extraction. Runtime XCTest execution is not represented as passed
for this candidate because the local CoreSimulatorService is unavailable. No
SwiftData schema, migration, JSON DTO, endpoint, task description, queue state,
feature flag, navigation, or UI contract changes in this slice.

A follow-up review replaced the prepared response's unchecked sendability with
compiler-checked conformances across `SpeciesData`, its nested values, and both
foreground/background result carriers. A generic-constrained test now makes that
value graph fail compilation if a non-`Sendable` stored value is introduced; the
architecture suite also rejects restoring `@unchecked Sendable` to
`PreparedResponse`. The same review replaced a strict-lint three-field tuple
with a named declaration owner. XcodeGen remained byte-stable, and
project/source membership, migration and event-routing guardrails, Swift
parsing, strict affected-source/test lint, CI workflow validators, Markdown
formatting, and whitespace validation passed. The post-review annotations could
not be rebuilt or executed locally because CoreSimulatorService was unavailable
and package resolution was blocked by the restricted network and nested SwiftPM
sandbox; the preceding extraction build and `build-for-testing` evidence
therefore remains distinct from this later static review.

### Core Data-wide Integration Audit

The cross-surface audit closes the remaining ambiguity between a genuinely
missing SwiftData row and a failed read. Every production `fetch` and
`fetchCount` under `Core/Data` now propagates or handles its error explicitly;
no `try?` fetch may manufacture an empty scan, job, collection, membership,
Favorites set, or repository reconciliation result. The safety rule is
fail-closed: mutations and network dispatch stop, the context rolls back when it
has pending changes, and private diagnostics retain the failure without logging
persisted user content.

`OfflineQueueDurableAuthorityReader` is the single fresh-context projection for
the error markers, attempt counts, and required-video count mirrored across an
`OfflineQueuedScan` and its ingestion job. Missing manager persistence throws
rather than returning a synthetic empty authority. The background-inference
server-owned scan projection moved to the 40-line
`OfflineQueueManager+InferenceReconciliation.swift`, keeping Recovery at its
600-line ceiling and all nine Background Inference production owners below the
guard. Direct and logging authority consumers are explicitly bounded.

Queued-scan extraction and Field Trip goal-hint access are throwing boundaries.
An unavailable snapshot schedules the established durable background-inference
retry or restores the persisted upload wake; only a successful fetch returning
no row may follow missing-row cleanup. Scan finalization rechecks cancellation
after acquiring the per-scan lock, performs throwing support reads, and rechecks
record absence after awaited media preparation. `ScanRepository` now aborts
library/collection reconciliation when local reads fail instead of treating the
store as empty.

The audit follow-up closes the caller-visible half of that contract as well:
`HistoricalDatabaseActor` now rethrows scan, membership, and save failures;
targeted completed-result hydration maps them to its durable transient-retry
outcome instead of returning `.reconciled`. Checkpoint failures abort the page,
the inserted count includes only validated rows, and explicit cancellation rolls
back before collection pruning so an interrupted traversal cannot delete
unprocessed local collections.

Collection transport requires a committed `.running` job claim. A failed job
read remains conservatively pending but cannot start the service or endpoint.
Cloud deletion preloads task/job pairs, commits every claim before transport,
and retains the pending task if its result cannot be applied to the durable job.
Funding, queue deletion/state, diagnostics, inference replay, media upload, and
Field Trip progress use the same explicit read-failure policy. These fixes
change no SwiftData model or migration, JSON contract, endpoint, task identity,
queue state, Auth/funding policy, navigation, or UI behavior on successful
storage paths.

`CoreDataIntegrationArchitectureTests` freezes the exact 13-file
`BackgroundDatabaseActor` inventory, import sets, declaration-only aggregate,
600-line ceilings, Core Data-wide silent-fetch ban, one-context authority read,
consumer allowlists, and the throwing cross-surface boundaries.
`ScanRepositoryTests` proves invalid-timestamp rows are excluded from insertion
counts and pre-cancelled collection reconciliation preserves local rows.
Existing persistence and Offline Sync suites retain the remaining behavior
coverage, with a new finalization overlap case proving cancellation while
waiting for the scan lock cannot commit afterward and a missing-context
authority case proving the reader does not synthesize empty state.

The completed audit passed byte-stable XcodeGen, project and source-membership
validation, migration and event-routing guardrails, CI workflow contract tests,
Swift parsing, strict affected-source lint, Markdown formatting, and whitespace
validation. A generic iOS Simulator app build and complete `build-for-testing`
succeeded with code signing disabled. The canonical Inference/Core Data/Offline
Sync runtime matrix exposed and then verified corrections to five relocated
architecture expectations; the final complete `merianTests` run passed all 3,148
tests on an iPhone 17 Pro simulator running iOS 26.5 with no failures or skips.

### Core Data Historical Sync Ownership

The former 1,332-line `ScanRepository.swift` mixed main-actor orchestration,
Auth/PostgREST effects, row decoding, wire DTOs, and actor-isolated SwiftData
reconciliation. Historical hydration now has four focused owners under
`Core/Data/Database/HistoricalSync`: Models contains request values, typed
outcomes, and unchanged DTOs; Decoding contains per-row quarantine using the
production PostgREST decoder; Services contains the sole live account-lease and
scan/collection query adapter; and Persistence contains
`HistoricalDatabaseActor`. `ScanRepository` retains push-before-pull ordering,
page advancement, account fencing, Explore share-state reconciliation, and app
events without importing Supabase or constructing queries.

The existing scan projection is byte-identical after relocation, including the
captured-media compatibility columns, nullable biological classification,
identification-review values, and owner-visible Explore relation. Query filters,
ordering, ranges, collection projection, decoder behavior, actor implementation,
live method signatures, and the 33 existing repository tests are preserved. The
uncalled `reconcileAllHistoricalData` test-compatibility shim was removed after
the review confirmed it had no production or test consumer. The test aggregate
is now a selector-compatible suite root with focused decoding, ingestion,
reconciliation, model-persistence, and deletion files; a new injected-client
test covers account-lease and request-value forwarding. The ingestion timestamp
guard exercises the production actor rather than duplicating its parsing
implementation inside a deletion test.

`CoreDataIntegrationArchitectureTests` freezes the exact four-file production
inventory and imports, 600-line ceilings, Supabase/SwiftData dependency
direction, sole query ownership, repository boundary, and mirrored Historical
Sync test inventory. This slice changes no JSON field, endpoint, SwiftData
schema or migration, persistence semantics, feature flag, navigation route, or
visible behavior.

Verification passed byte-stable XcodeGen, project/resource and source-membership
guards, event-routing validation and adversarial fixtures, migration guardrails,
the generated Captured Media DTO contract, user-skill link validation,
individual Swift parsing, strict affected-file SwiftLint, Markdown formatting,
and whitespace validation. A generic code-signing-disabled iOS Simulator build
passed for both simulator architectures and its production lint phase reported
zero violations across 1,097 files. After the corrective review, a clean generic
Simulator `build-for-testing` compiled the app, unit-test, and UI-test source
graphs. The focused Historical Sync/Scan Repository review matrix passed 41
tests in three suites, including the actor-backed malformed-timestamp case. The
complete `merianTests` action then passed; Swift Testing reported 2,253 tests in
325 suites alongside the successful XCTest suites.

### Core Data Image Loading Ownership

The former 1,427-line `LocalImageLoader.swift` mixed load orchestration,
concurrency admission, URL and retry policy, local recovery evidence, legacy
SQLite indexing, and authenticated cloud repair. Those responsibilities now have
focused owners: the loader root plus `Concurrency`, `Policies`, `Recovery`, and
`Services` files under `Core/Data/Images`. Every production Swift file in that
area remains at or below the 600-line review guard.

`LocalImageLoader` keeps its shared entry point, signatures, isolated session,
cache/coalescing behavior, and detached cancellation semantics. Its small
injected `Dependencies` value exposes deterministic recovery, decode, fetch,
diagnostic, and repair seams while `.live` preserves the existing behavior.
`CloudScanImageRepairActor` similarly injects its clock, file evidence,
endpoint/upload operations, and library event. The review closed one
pre-existing race: a canonical source URL now remains in the actor's
queued-or-in-flight set throughout inspection, signing, upload, and repair, so
an enqueue during suspension cannot start a duplicate workflow.

The second-pass review closed the remaining equivalent-URL gap: recovery now
uses one canonical credential-free HTTPS identity across its resolver, mapping
registry, and cloud repair actor. Scheme/host case, an explicit default port,
query parameters, and fragments can no longer create duplicate registry or
repair work. The lock-protected registry was extracted into its own focused file
to preserve the line ceiling. The decode permit pool also returns a just-granted
slot to the pool when cancellation races waiter resumption, and Startup Safety
now explicitly selects the relocated cloud-repair and architecture suites that
its source-scope detector watches.

`LocalImageLoaderTests` moved into the mirrored Core Data Images test tree
without changing its selector type and now uses an injected probe for
deterministic request coalescing. `CloudScanImageRepairActorTests` covers the
exact missing-image pipeline order and the equivalent-URL in-flight duplicate
fence. Recovery tests also cover canonical registry identity.
`ImageLoadingArchitectureTests` freezes declaration ownership, dependency
direction, focused imports, the test rehome, and the line ceiling. Value-only
media storage DTOs gained `Sendable` conformance for the injected boundary;
their JSON shape is unchanged.

Initial verification passed XcodeGen, project/resource and source-membership
guards, Swift parsing, strict SwiftLint with zero violations, a
code-signing-disabled generic iOS device build, and complete app/unit/UI
`build-for-testing`. The initial focused simulator matrix executed 28 tests with
zero failures, and the complete `merianTests` action then passed; its result
bundle reports 3,157 tests, zero failures, and zero skips. After the second-pass
corrections, byte-stable XcodeGen, project/source membership, CI-tooling,
migration, Markdown, Swift parsing, standalone permit strict-concurrency, and
full-graph SwiftLint gates passed. A fresh 30-test image matrix and compiled
build could not start because CoreSimulatorService disconnected and the sandbox
denied SwiftPM's manifest diagnostics-cache writes; no post-correction runtime
result is inferred from that environment failure. No API payload, SwiftData
schema, persistence, feature flag, navigation, Supabase, deployment, or
external-publication change is included.

### Core Data Store Recovery Ownership

The former 965-line `ModelStoreRecoveryCoordinator.swift` mixed production store
configuration, migration selection, error classification, metadata inspection,
diagnostic persistence, archive creation, privacy filtering, and all supporting
values. Store Recovery now has focused `Models`, `Policies`, and `Services`
owners behind the source-compatible coordinator façade. Production files remain
below the 600-line review guard, and tests moved from the App test bucket into
the mirrored `Core/Data/StoreRecovery` tree without changing the existing XCTest
suite name or recovery entry points.

The extraction preserves the configured SwiftData store URL, V42–V50 source
selection, checksum-distinct V50 routing, corruption quarantine, legacy rescue,
safe-mode copy, diagnostic schema, archive layout, and startup call signatures.
The review also corrected pre-existing privacy and archival-integrity defects.
`recovery-manifest.json` retains the error code and allowlisted stable domains,
fingerprints custom domains plus localized description/failure prose, and must
be atomically written before archive success. Startup diagnostics fingerprint
captured Core Data metadata strings and keys. Partial moves and manifest-write
failures restore completed artifact moves in reverse order; an incomplete
rollback leaves its archive as evidence and still fails. No SwiftData schema,
migration stage, JSON API contract, Auth/session state, feature flag, navigation
route, deployment, or external publication changed.

The focused suites cover configuration and migration policy, diagnostic
projection, exact SQLite/WAL/SHM archiving, metadata/domain/private-text
exclusion, partial-move and manifest-write rollback, declaration ownership,
pure-layer imports, auth/session isolation, test ownership, and the line
ceiling. Startup Safety and the source guardrails follow the new files and
select all four Store Recovery suites. Verification includes byte-stable
XcodeGen, project/source membership, migration and CI workflow guardrails, Swift
parsing, strict SwiftLint, Markdown formatting, and whitespace checks. A clean
generic Simulator `build-for-testing`, the 44-test focused Store Recovery
matrix, and the complete 5,151-test `merianTests` target all passed with the
same serial execution policy used by CI.

### Core Data Post-Refactor Integration Audit

The closure audit joined the three slices completed after the earlier Core
Data-wide review: Historical Sync, Core Data Images, and Store Recovery. It
confirmed their payload, schema, migration, queue, route, and visible behavior
contracts remain unchanged, then found one cross-slice startup defect. App
initialization synchronously opened the legacy rescue index and fetched the
complete `LocalScanRecord` table on the main actor; the read also used `try?`,
so an unavailable store was indistinguishable from an empty library.

Full-library rescue registration now belongs to the actor-isolated
`ScanMediaRecoveryRegistrationService`. `ScanRepository` schedules and owns that
work after configuration, cancels it on reconfiguration, and accepts completion
only while the exact configured `ModelContainer` remains current. The service
creates a fresh context per page, uses throwing reads capped at 200 records, and
checks cancellation between every batch. Its first complete pass registers
strong scan-ID and media-order evidence; its second pass is globally ordered by
timestamp and scan ID before applying the constrained fallback. This two-pass
boundary prevents a timestamp guess in an early page from consuming a file that
stronger evidence on a later page should own. A follow-up concurrency review
also made evidence priority a registry invariant, so Historical Sync or Scan
Library work interleaved with the background rebuild cannot preserve a timestamp
group after stronger URL or local-file evidence arrives. Timestamp groups are
admitted and evicted atomically, preventing partial recovery state.

`LocalScanMediaRecoverySnapshot` is the immutable current/historical scan bridge
to the resolver. Historical Sync and Scan Library retain their bounded mapping
call sites; timestamp mappings remain add-only, while strong mappings can evict
only lower-confidence conflicts. `QueueActorCacheTests` now mirrors the existing
Profile cache regression, proving both long-lived database actors are reused
only for their exact container. Architecture tests freeze the post-startup
ownership, bounded throwing reads, two-pass evidence order, registry-level
priority, cancellation, and container fence. No endpoint, JSON, Auth, SwiftData
schema or migration, persistence format, feature flag, navigation, copy, or
deployment contract changed.

Initial verification passed byte-stable XcodeGen; project/resource and
source-membership validation; migration, event-routing, Startup Safety scope,
and iOS workflow contract gates; Swift parsing; strict affected-source SwiftLint
with zero violations; Markdown formatting; and whitespace checks. A
code-signing-disabled generic iOS Simulator `build-for-testing` compiled the
complete app, unit-test, and UI-test graph. On an iPhone 17 Pro / iOS 26.5
simulator, the joined Historical Sync, Images, Store Recovery, V51 migration,
Core Data integration, and exact-container cache matrix passed 166 tests with
zero failures or skips. The complete `merianTests` target then passed from the
same products; its result bundle reports 5,157 expanded test cases (3,173 named
tests), zero failures, and zero skips.

The follow-up registry correction passed exact registry/resolver typechecking
against local contract stubs and an executable precedence/atomicity harness,
Swift parsing, strict SwiftLint, byte-stable XcodeGen, all
project/source/migration/event/CI-tooling guardrails, Markdown formatting, and
whitespace checks. A fresh Xcode build and simulator run could not start because
the local CoreSimulator and nested SwiftPM sandbox services were unavailable;
Startup Safety owns the added regression for the next runnable CI environment.

The September 9, 2026 working-tree follow-up closed three additional gaps.
Direct filenames are now reserved during the strong-evidence pass even when no
rescued row exists. Cloud repair admits only direct filename or registered
strong evidence for the exact local URL, rechecks evidence across suspension,
and allows a verified retry after evidence loss. Timestamp guesses remain local
display fallbacks. Source revisions also invalidate cache/coalescing identities;
a shared Core UI modifier refreshes retained Scan, gallery, Profile, Explore,
and composer images, with cancellation checks preventing stale publication.

Startup Safety now uses unfiltered events, complete Git history, and exact push
or PR merge-base comparisons. Unresolved ranges require simulator verification;
manual, scheduled, and merge-queue runs always select it. Regression fixtures
cover shallow history, empty diffs, PR divergence, renames, malformed events,
and comparison failures. Workflow contracts preserve the new image UI trigger
inventory and suite selectors; the migration guardrail verifies V50 coverage in
the canonical detector.

Follow-up validation passed generated-project, migration, event-routing, and
complete iOS CI-tooling gates, affected-source SwiftLint, and formatting checks.
A standalone macOS harness executed 16 focused recovery/architecture tests using
synthetic app adapters and a UIKit substitute. Changed source and focused tests
also passed an iOS 17.2 SDK typecheck with real UIKit/SwiftUI and synthetic app
adapters. These checks do not establish an integrated application build or
simulator result: sandbox restrictions blocked full Xcode/SwiftPM and
CoreSimulator execution. Production sign-off still requires the real build,
simulator/device checks, and exact-candidate release evidence. No production
hold was cleared and no deployment was performed.

Documentation closure synchronizes the iOS and Core Data ownership summaries,
Store Recovery and Core Data Images READMEs, startup/lifecycle/concurrency
contracts, image pipeline, testing strategy, codebase map, and this cleanup
ledger. Detailed recovery evidence remains canonical in the image pipeline;
higher-level pages summarize and link that contract without creating a second
source of truth.

### Core Hardware Camera Foundation

The first Core Hardware slice moved only value and deterministic task-policy
owners out of the 1,790-line `CameraManager.swift`. Recording result,
generation, and scheduled-action values now live in `Camera/Models`; the
already-granted microphone rule and pure generation/action gate live in
`Camera/Policies`; and the latest-state FPS debouncer lives in
`Camera/Coordination`. At that checkpoint, the live manager remained the sole
owner of the capture stack, serial camera queue, session/device/output access,
delegates, continuations, lock-protected recording state, and observable
hardware state. No public initializer, capture behavior, layout, copy, route,
endpoint, payload, persistence, feature-flag, or deployment contract changed.

`CameraArchitectureTests` inventories the exact declaration owners, locks their
framework dependencies, prevents deterministic support code from acquiring
capture/network/UI effects, confirms the live AVFoundation and request state
remain co-located, and preserves the existing behavioral test selector. The
three extracted production files are capped at 100 lines. The root manager is
1,646 lines at that checkpoint and has an interim 1,650-line non-growth ceiling;
it has not yet reached the usual 600-line completion guard. Subsequent camera
work must move a complete queue- or lock-owned subsystem rather than splitting
mutable state across owners.

Verification for this slice passed declaration-equivalence checks against the
pre-extraction source, Swift parsing and focused Simulator-SDK typechecking,
strict SwiftLint with zero violations, all four standalone camera architecture
tests, and a native policy harness covering microphone reuse, generation/action
replacement, callback URL correlation, and cancellation-ignoring FPS debounce.
XcodeGen was byte-stable, and project validation, source membership, event-
routing guards, the complete iOS CI-tooling contract suite, Markdown formatting,
and whitespace validation passed. A fresh Xcode Simulator build and test run is
not recorded as passing: CoreSimulatorService disconnected in this environment,
and earlier attempts stopped before compilation at nested SwiftPM sandbox/cache
access. The focused Xcode selectors, complete `merianTests` target, and
on-device AVFoundation matrix remain required in the next runnable environment;
the canonical commands live in the
[testing strategy](../development-guides/08-testing-strategy.md#camera-verification).

### Core Hardware Camera Photo Request Lifecycle

The second Camera slice moved the complete still-photo continuation subsystem
into `Camera/Coordination/CameraPhotoCaptureCoordinator.swift`. The coordinator
owns request reservation, checked-continuation registration, the five-second
timeout task, cancellation, and atomic terminal-result claiming under one
`OSAllocatedUnfairLock`. `CameraManager` still owns `AVCapturePhotoSettings`,
the serial camera queue, flash/rotation/resolution/depth configuration,
`capturePhoto`, the delegate entry point, and accepted photo-to-`Data`
conversion.

Reservation now occurs before the task cancellation handler is installed. An
already-cancelled or concurrently cancelled task therefore marks the reserved
ID; registration consumes that state as `CancellationError` and never queues a
hardware shutter. Timeout, setup failure, delegate completion, and active
cancellation remove state before resuming outside the lock, preserving the
existing error codes and making every terminal race exactly-once. At that
checkpoint, the manager was 1,599 lines with an interim 1,610-line non-growth
ceiling, while the focused coordinator was capped at 220 lines.

Six deterministic coordinator tests cover cancellation before registration,
active cancellation, completion/late-result exclusion, a simultaneous
cancellation/completion race, the existing timeout error contract, and
tombstone-free ID reuse. All six and the four Camera architecture tests execute
in normal and Thread Sanitizer standalone Swift Testing harnesses; the new
source and tests typecheck against the iOS Simulator SDK, and the entire
device-only `CameraManager` branch typechecks for arm64 iOS with real Apple
frameworks and narrow stubs for unrelated app globals. Project generation,
project validation, source membership, parsing, strict affected-source
SwiftLint, Markdown formatting, and whitespace checks pass. A complete Xcode
build is not recorded as passing because SwiftPM could not write its host
diagnostics cache before compilation, and CoreSimulatorService remains
disconnected. Focused/full Xcode execution and the physical-device shutter
matrix remain required in the next runnable environment.

### Core Hardware Camera Video Request Lifecycle

The third Camera slice moved the complete lock-owned video request subsystem
into `Camera/Coordination/CameraVideoRecordingCoordinator.swift`. One private
request now owns the generation gate, checked continuation, start metadata,
timeout task, automatic-stop task, and stop state under a state-owning
`OSAllocatedUnfairLock`. At that checkpoint, `CameraManager` retained the
`AVCaptureMovieFileOutput`, serial camera queue, session/audio and stabilization
configuration, file cleanup and logging, delegate entry points, and
generation-fenced MainActor presentation.

Scheduled actions preserve the existing install-before-launch and
compare-before-attach fences. Replacing a task updates the action UUID under the
coordinator lock, and a task that loses attachment is canceled. Stop, timeout,
cancellation, and finish callbacks can take the active request only once; task
cancellation and continuation resumption happen after the lock is released. A
callback must still come from the configured movie output and match the exact
generation-derived URL before the coordinator exposes its completion. The live
manager was 1,408 lines at that checkpoint, with an interim 1,420-line
non-growth ceiling; the focused coordinator was 367 lines with a 380-line
ceiling.

Six deterministic coordinator tests cover active-generation ownership, one-shot
start claiming, copied-completion double-resume rejection, stop-before-start
propagation, timeout/stop replacement, cancellation-ignoring sleep, callback URL
correlation, terminal clearing, and 100 simultaneous
cancellation/delegate-completion races. The combined 16-test Camera coordinator
and architecture harness passes normally and under Thread Sanitizer. Production
coordinators and their tests typecheck with strict concurrency and warnings as
errors against the iOS Simulator SDK, and the complete device-only
`CameraManager` branch typechecks for arm64 iOS with real Apple frameworks and
narrow stubs for unrelated app globals. XcodeGen is byte-stable; project,
source-membership, iOS CI-tooling, parsing, strict affected-source SwiftLint,
Markdown-format, and whitespace gates pass. Full Xcode build/test execution is
not recorded as passing: local attempts stop before compilation because
CoreSimulatorService is unavailable and SwiftPM package manifests cannot enter
their nested sandbox. The focused/full Xcode selectors and physical-device
recording matrix remain required in the next runnable environment.

### Core Hardware Camera Video AVFoundation Boundary

The fourth Camera slice moved the complete movie-output AVFoundation boundary
into `Camera/Services/CameraVideoRecordingService.swift`. `CameraManager`
creates the root capture stack and serial camera queue, injects the queue plus a
lazy session provider into the service, and retains its existing public record,
stop, and cancel methods plus generation-fenced observable presentation. The
service lazily creates and exclusively owns the movie output, output attachment,
audio preparation, rotation and stabilization, camera-queue recording
operations, timeouts, file cleanup, hardware logging, and recording delegate
entry points. A review caught and repaired an intermediate eager-initialization
regression: manager/service construction now evaluates neither the session
provider nor the movie-output factory, and a focused regression test freezes
that cold-launch contract. No route, payload, persistence, feature flag, layout,
copy, or Capture initializer changed.

The service composes `CameraVideoRecordingCoordinator`; it does not duplicate
request state or expose observable state. Its narrow `@unchecked Sendable`
conformance is documented and architecture-tested: preparation cache access is
MainActor-only, and capture-object mutation is confined to the injected serial
queue. The manager's session-state lock and the coordinator's request lock stay
non-nesting. `CameraManager` is now 919 lines with a 925-line interim guard, and
the 598-line recording service remains below its 600-line ceiling.

Architecture coverage now separates manager-owned video, depth, and photo
delegates from the service-owned movie output and file-output delegate. It also
freezes the injected session-provider, queue, movie-output-factory, and
coordinator seams and excludes network, persistence, and UI dependencies. The
generic Simulator build, `build-for-testing`, and 31-test focused Camera matrix
passed before the final lazy-construction repair. The repaired production source
passes strict simulator/device typechecking, and its added 32nd test passes
strict Simulator typechecking. XcodeGen, project/source-membership validation,
parsing, Markdown formatting, and whitespace checks also pass. Execution of the
current-source focused and complete targets could not start after
CoreSimulatorService disconnected on the host; those selectors and the
physical-device recording matrix therefore remain separate release evidence.

### Core Hardware Camera Session and Device-Control Boundary

The fifth Camera slice moved the complete root session/device/output mutation
boundary into `Camera/Services/CameraSessionController.swift`. Its private,
lock-backed capture stack lazily creates the session plus video, depth, and
photo outputs; its serial queue owns configuration, lifecycle, device discovery
and locking, rotation, frame-rate, zoom, focus, torch, and hardware still-photo
execution. `CameraManager` is now the MainActor observable facade and retains
frame/depth/photo delegate processing, photo request composition and accepted
data conversion, HardwareOrchestrator/ViewfinderIntelligence integration, and
generation-fenced recording presentation. `CameraVideoRecordingService`
continues to own the movie output on the controller's injected queue.

Pure zoom and frame-duration decisions moved to
`Camera/Policies/CameraSessionPolicy.swift`. Manager, controller, and recording
service construction remains inert: the session and outputs are created only by
preview access or explicit capture work, and concurrent root-session access is
lock-coalesced to one instance. The non-LiDAR gate still avoids creating or
attaching the depth output during setup. The manager's remaining lock contains
only frame/depth throttle timestamps and the inference-pause mirror; controller
and coordinator locks remain private and non-nesting. No route, payload,
persistence, feature flag, layout, copy, public Capture initializer, or
deployment contract changed.

`CameraManager.swift` is now 571 lines and `CameraSessionController.swift` is
555 lines, so both use the normal 600-line architecture ceiling rather than an
interim non-growth allowance. Four policy tests cover optical-stop and zoom
bounds plus supported frame-duration clamping and update order. Three controller
tests prove inert construction, no-op controls and idempotent stop completion
before first resolution, and exactly-one session creation under concurrent
access. `CameraArchitectureTests` freezes the new AVFoundation ownership split
and dependency exclusions.

Verification passed XcodeGen, project/source-membership validation, Swift
parsing, strict affected-source SwiftLint, the generic iOS Simulator build, and
a current-source `build-for-testing`. A follow-up review closed three
lazy-lifecycle gaps in the extracted owner: device controls and both stop APIs
now inspect an already-resolved session instead of creating capture hardware for
a no-op; callback stop always delivers completion when the session is absent or
already stopped; and photo capture reads only an already-configured depth output
so the non-LiDAR path does not create an unused depth object. The 39-test
focused Camera selector matrix passes on the selected iOS Simulator. The
complete current-source `merianTests` target passes 3,205 tests with zero
failures or skips (5,193 device/configuration-level passes when dynamic
parameter runs are expanded). Pure tests do not exercise physical optics;
session start/stop, torch, zoom/lens switching, focus, LiDAR and non-LiDAR depth
behavior, photo rotation, interruption recovery, thermal FPS, and recording
stabilization still require the documented physical-device matrix before
release.

### Core Hardware Audio Review Playback Boundary

The first Audio Capture slice moved the complete review-player lifetime,
progress-task, completion-task, and playback-session lifetime from
`AudioCaptureManager.swift` into
`AudioCapture/Services/AudioReviewPlaybackController.swift`.
`AudioCaptureManager` remains Capture Record's stable `@MainActor @Observable`
facade and preserves every play, stop, seek, review-state, file-handoff, and
initializer signature. The focused controller owns one exact player plus its
generation, tasks, and playback lease. Its small dependencies inject player
construction, session effects, and waits; the live edge alone resolves
`AVAudioPlayer` and `AudioSessionCoordinator.shared`.

Stop clears controller ownership before cancellation. A non-cooperative session
activation that returns afterward deactivates its lease and never starts audio;
a stale progress or completion task must match both generation and player
identity before it may publish or finish. Playback cleanup therefore cannot
clear the recording controller's resources or lease, and stopped playback cannot
reset its replacement. Failed player starts and completion-wait errors finalize
the exact playback immediately, and manager reset always stops its independent
playback owner. The manager fell from 750 to 692 lines at this stage and carried
a temporary 700-line non-growth ceiling. The 236-line controller is capped at
250 lines. The following recording-engine pass completed the planned extraction
and replaced the interim manager ceiling.

Six deterministic playback tests cover stop-before-activation with late-lease
cleanup, failed player start, completion-wait failure, cancelled completion
versus replacement, scrubbed manager resume plus natural finalization, and
manager-reset lease cleanup. `AudioCaptureArchitectureTests` freezes declaration
ownership, dependency exclusions, delegation, regression-suite presence, and
both interim line ceilings. The current-source generic Simulator build and the
37-test focused Audio/Record matrix pass with zero failures or skips; strict
affected-source SwiftLint reports zero violations. The complete current-source
`merianTests` target passes 3,214 tests with zero failures or skips (5,202
device/configuration-level passes when dynamic parameter runs are expanded).
XcodeGen is byte-stable; project/resource membership, event-routing, Swift
parsing, Markdown-format, and whitespace gates also pass. No route, endpoint,
payload, persistence, feature flag, UI copy/layout, or deployment contract
changed.

### Core Hardware Audio Recording Engine Boundary

The second Audio Capture slice moved the complete recording-engine lifetime,
input tap, canonical WAV writer, bounded PCM stream, detached DSP consumer,
startup/resume operation identity, partial-file cleanup, and recording-session
lease into `AudioCapture/Services/AudioRecordingEngineController.swift`.
`AudioCaptureManager` remains the stable `@MainActor @Observable` facade and
retains its public initializer and record, pause, resume, stop, review, and
submission signatures. It now owns presentation state, countdown, bounded
spectrogram display history, noise-guidance hold policy, and file handoff—not
AVFoundation recording resources.

`AudioRecordingEngineModels` carries the sendable input-format and evaluated-
column values, while `AudioRecordingWAVFormatPolicy` owns the explicit signed
Int16 interleaved PCM contract. The controller's narrow dependencies inject
engine construction, session activation/deactivation, route-recovery wait,
temporary-file naming, and deletion. Exact recording and operation identities
fence lease acceptance, start/resume, and DSP publication. Failure or
cancellation clears ownership before finishing the stream, removing the tap,
stopping the engine, cancelling DSP, releasing the matching lease, and deleting
the partial WAV; successful finish retains the WAV for review or submission.

Seven deterministic controller tests cover completed-file retention and teardown
order, engine-start cleanup, bounded route recovery and exhaustion,
cancellation-ignoring late activation, controller-level duplicate-resume
coalescing, and resume retry after activation failure. The controller's
deactivation dependency accepts only a concrete lease, so owner teardown cannot
emit a synthetic nil release. Two WAV-policy tests freeze the format contract
and invalid-input rejection. `AudioCaptureArchitectureTests` freezes relocation,
dependency exclusions, delegation, teardown order, regression-suite presence,
and the focused ceilings: 600 lines for the 516-line manager, 550 for the
533-line recording controller, and 250 for the 236-line playback controller. The
exact current source passes the generic Simulator build-for-testing and all 48
focused Audio/Record tests. The complete `merianTests` target passes 3,225
logical tests with zero failures or skips (5,213 device/configuration-level
passes after dynamic parameter expansion). Strict affected-source SwiftLint
reports zero violations; XcodeGen is byte-stable, and project,
source-membership, event-routing, Markdown-format, Swift-parse, and whitespace
gates pass. No route, endpoint, payload, persistence, feature flag, UI
copy/layout, or deployment contract changed. Physical microphone, speaker,
route-handoff, and interruption QA remains required before release.

### Core Hardware Haptic Feedback Boundary

The next Core Hardware slice retained `HapticManager` as the source-compatible
`@MainActor @Observable` facade while moving platform resources and pure policy
into focused `Haptics/{Models,Policies,Services}` owners. The facade fell from
470 to 257 lines and now owns only the two global gates, semantic trigger and
sequence timing, suppression diagnostics, and latest-attempt presentation.
Public trigger names, initializer defaults, settings behavior, expedition-mode
suppression, diagnostic copy, and UIKit delivery behavior remain stable.

`HapticFeedbackController` owns four impact, one selection, and two notification
generator wrappers plus a lazy Core Haptics engine. Engine stopped/reset
callbacks are fenced by exact UUID so a callback from an obsolete engine cannot
clear its replacement. Hardware construction, triggering, capability, and audio
session effects are initializer-injected. Impact and selection retain the
established UIKit delivery on every admitted request and add the Core Haptics
transient when available; unsupported or failed Core Haptics therefore produces
the UIKit-only outcome. The 300-millisecond deferred warmup remains off the
initialization path and uses a weak facade capture.

`HapticAudioSessionAdapter` is the only haptic file that imports AVFoundation or
inspects `AVAudioSession.sharedInstance()`. Its best-effort recording-category
configuration is separate from `AudioSessionCoordinator`, which remains the
token-aware recording/playback lease owner. `HapticFeedbackModels` and
`HapticFeedbackPolicy` contain platform-neutral values, admission, suppression
key, profile, and intensity logic.

The follow-up audit removed three unreachable branches that the first extraction
had carried over from exhaustive UIKit switches: the internal `.soft` impact,
`.warning` notification, and unobservable intermediate `.coreHaptics` attempt
outcome. The remaining domain cases now match the facade's actual routes. It
also made every injected generator, engine, audio-session, and clock closure
explicitly `@MainActor`, preserving isolation even when a dependency value is
copied. Deterministic facade and controller probes now assert the exact
generator owner that fires, including success versus error, plus the delayed
error and both stale stopped/reset callbacks.

Four policy tests, five controller tests, and four architecture tests cover
global eligibility, profiles and clamping, generator construction/routing, UIKit
fallback, engine replacement fencing, audio-session injection, declaration
ownership, dependency exclusions, and focused ceilings. Capture's pure control
feedback policy subsequently moved from Core UI to
`Features/Capture/Shared/Models`, with its mirrored
`CaptureControlHapticPolicyTests` suite under `Features/Capture/Shared`; the
five manager tests retain facade/global-gate coverage. The ceilings are 300
lines for the 257-line facade, 125 for the 91-line models, 100 for the 48-line
policy, 400 for the 361-line controller, and 100 for the 37-line adapter.

The exact current source passes XcodeGen, project/source-membership validation,
Swift parsing, strict affected-source SwiftLint, and the generic iOS Simulator
build-for-testing. The five focused haptic/Capture suites pass 23 tests with
zero failures or skips. The complete `merianTests` target passes 3,238 logical
tests with zero failures or skips (5,226 device/configuration-level passes after
dynamic parameter expansion). Physical-device haptic/audio-recording interaction
remains required before release. No route, endpoint, payload, persistence,
feature flag, UI copy/layout, or deployment contract changed.

### Core Hardware Environment Context Boundary

The next Core Hardware slice retained `EnvironmentContextManager` as the
caller-compatible `@MainActor @Observable` facade while moving deterministic
values and live effects into `EnvironmentContext/{Models,Policies,Services}`.
The facade fell from 469 to 210 lines and now owns live dependency composition,
observable location-state projection, and the existing authorization, location,
tracking, deferred, and historical methods. The retired 12-line root
`EnvironmentContext.swift` model is now grouped with the focused placemark,
weather-reading, and location-snapshot values in the 38-line Models file.

`EnvironmentLocationPolicy` owns the established authorization and prompt rules,
composing/shutter profiles, inclusive 0...30 m accurate-fix boundary, two-second
timeout, 200-entry geocode limit, three-decimal cache key, placemark display,
and ISO-region normalization. `EnvironmentLocationController` is the sole
`CLLocationManagerDelegate` and Core Location resource owner. Its 356 lines
contain authorization coalescing, passive authorized lookup, live tracking,
one-shot continuations, request-scoped cancellation, and exact UUID timeout
generations. An obsolete cancellation-ignoring timeout can no longer resolve a
replacement request. The review pass also rejected negative-accuracy updates,
kept coarse timeout results out of the accurate cache, fenced the high-level
cached return after cancellation, and flushed in-flight one-shot work when
authorization is revoked.

`EnvironmentGeocodingService` is the sole `CLGeocoder` owner. Its 115 lines
coalesce equal rounded coordinates and share one successful placemark plus a
bounded insertion-order cache between location-name and ISO-region projections;
failed and projection-empty lookups remain retryable. The 41-line
`EnvironmentWeatherService` is the sole WeatherKit owner and maps current and
date-pinned hourly values into a small reading. The facade preserves concurrent
current geocoding/weather work, weather-failure location names, historical
capture dates, passive no-prompt behavior, and small initializer-injected
dependencies without adding a broad protocol or singleton.

The retired 85-line aggregate manager test was replaced by 31 deterministic
tests across policy, controller, geocoding, facade, and architecture suites.
They cover prompt/accuracy boundaries, invalid-fix rejection, overlapping waits,
request cancellation and revocation, stale timeout generations, accurate/coarse
cache ownership, tracking authorization, cache coalescing/retry/eviction,
independent service concurrency and failure, state projection, passive lookups,
framework ownership, compatibility names, retired aggregates, and focused line
ceilings. The exact final candidate passed the 31-test focused matrix and the
complete `merianTests` target: 3,264 logical tests, 5,252 expanded
device/configuration runs, zero failures, and zero skips. It also passed the
generic iOS Simulator build, independent focused-source type-check, `swiftc`
parsing, strict affected-source SwiftLint with zero violations, byte-stable
XcodeGen, project/resource validation, generated-project source membership,
event-routing checks, Markdown formatting, and whitespace validation. No route,
endpoint, payload, persistence, feature flag, UI copy/layout, or deployment
contract changed; real authorization, GPS accuracy, background/foreground
tracking, geocoding, and WeatherKit remain in the physical-device release
matrix.

### Core Notifications Boundary

The next Core slice moved system authorization, APNs registration, local
scheduling/routing, and app-icon badge ownership out of `Core/Hardware` into
`Core/Notifications`. Stable `PushNotificationManager` and
`AppIconBadgeCoordinator` entry points preserve every existing caller. Focused
Models and Policies contain immutable values and deterministic token, route,
presentation, descriptor, and badge decisions. Services alone resolve
`UserDefaults`, the current Supabase account scope, `UNUserNotificationCenter`,
notification-related `UIApplication` APIs, and the push-registration and
unread-count endpoints. Explore Notifications retains its catalog and mark-read
adapters plus visible activity state.

`PushRegistrationCoordinator` now drains the newest token/settings/account
snapshot admitted while a request is suspended instead of dropping it behind the
old Boolean in-flight guard. The normalized account scope affects local
coalescing only and is omitted from the unchanged six-field wire payload, so an
old account's authenticated call cannot satisfy an otherwise-identical request
for its replacement. Matching trailing work coalesces after success and retries
after failure. `AppIconBadgeController` contains the prior static task, cache,
and state-generation ownership behind injected dependencies. Local mark-read
mutations and accepted account cleanup both invalidate older badge loads, so a
cancellation-ignoring response cannot restore stale unread state. Cache reuse
also rejects backward clock movement, and badge aggregation saturates instead of
overflowing. Native authorization prompts invalidate older permission reads and
defer new polling until the user decision resolves; UI completion now fires
before remote synchronization, and unchanged status does not rewrite defaults.
Inference notification deduplication now distinguishes pending from
system-accepted scan IDs, so a failed scheduling request remains retryable
without permitting simultaneous duplicates.

The retired Hardware and Utilities notification tests were replaced with 34
deterministic tests across policy, remote-registration coordination, manager,
badge-controller, and architecture suites. They run without mutating global OS,
route, defaults, network, or badge state. Architecture coverage enforces
source-compatible facades, sole live-effect owners, retired aggregate paths, and
a 400-line production-file ceiling. No route, payload, persistence,
feature-flag, visible UI, backend, or deployment contract changed. Canonical
directory, lifecycle, concurrency, logging, routing, API, Settings, Explore,
account-cleanup, and testing documents now use that same ownership boundary and
point to the focused Core Notifications guide.

The exact candidate rebuilds successfully as part of complete simulator test
execution. The focused Core Notifications plus Settings boundary matrix passes
39 tests. The complete `merianTests` target passes 3,288 logical tests (5,276
expanded runs) with zero failures or skips. The generic iOS Simulator build and
complete build-for-testing passed before the final review corrections; their
redundant final rerun was blocked before compilation by the host's unavailable
CoreSimulator and SwiftPM sandbox services. All 32 changed Swift files parse,
strict SwiftLint reports zero violations across 1,147 production files, XcodeGen
is byte-stable, and project/resource, generated-project source-membership,
event-routing, adversarial routing, Markdown-format, and whitespace gates pass.
Physical-device notification permission, APNs delivery/actions,
Focus/time-sensitive behavior, attachments, and Home Screen badges remain in the
release acceptance matrix.

### Core Hardware-wide Integration Audit

The integration audit following the Camera, Audio, Haptics, Environment Context,
and Notifications slices checked their shared lifecycle edges across Capture,
Explore, Insights, Scans, Profile, app lifecycle, and reusable media. It found
cross-owner correctness gaps rather than ownership drift or an API contract
change.

`CameraSessionController` had committed its one-time configuration reservation
before proving that a required video input existed. A transient discovery or
input failure could therefore make every later start skip configuration and
publish a start callback for a session that was not running. Configuration now
preflights the required input plus video/photo outputs, releases the reservation
on failure, attaches optional depth only after required outputs, and publishes
`onStarted` only after `AVCaptureSession.isRunning` succeeds and the start still
owns the current lifecycle generation. A stop therefore suppresses its queued
stale start callback. The observable facade independently generation-fences
start and stop presentation, preventing an older MainActor completion from
overwriting a newer lifecycle transition. Its extracted pure state coalesces
duplicate same-intent starts or stops so they cannot invalidate the one callback
that converges observable state. Deterministic policy and retry tests exercise
both paths without camera hardware, while the architecture suite locks both
callback fences.

Environment Context now restores the complete composing profile after an idle
one-shot request: hundred-meter accuracy and the 100 m distance filter. The
facade also gates `lastKnownLocation` on current authorization, so permission
revocation cannot expose retained accurate or coarse fixes through Capture,
Explore, or Map. It rechecks authorization after a suspended one-shot request so
mid-request revocation cannot use the retained fallback or start downstream
geocode/weather effects. Three deterministic regressions raise the focused
Environment matrix from 31 to 34 tests.

Explore's published-audio surface no longer configures or deactivates the
process-wide audio session directly. Core Media's
`AudioPlaybackSessionController` owns its `.playbackDucking` lease, coalesces
activation, verifies a retained token before reuse, retries failure, releases
cancellation-ignoring late acquisition, fences teardown during lease validation,
drains cancelled activation before replacement, and deactivates only its exact
current lease. UI-task cancellation now explicitly invalidates pending
controller activation. The process-wide coordinator rejects a task already
cancelled before activation mutates `AVAudioSession`, while a deliberately
non-cooperative late acquisition is released. The Explore playback state retains
that controller and its UI-timed activation task, preserving selection, focus,
pause, recovery, and reset timing while preventing stale cleanup from
deactivating Capture recording, speech, or a replacement player. Focused Core
Media controller tests cover each overlap and teardown boundary; the Core
Hardware coordinator suite remains scoped to process-wide token and
configuration semantics.

Reusable Core UI and Explore audio now await the same controller immediately
before every audible start—including play-button, seek-resume, loop, and
fallback-player paths. A merely mounted page acquires no process-wide lease, so
opening disabled playback UI cannot replace active recording or speech. The
pre-start check closes the stale-session window when another owner replaces a
retained lease while a page remains visible. Lifecycle and player-identity
fences prevent a suspended validation from starting the old player after
teardown or replacement. The former synchronous `AVAudioPlayer` session-mutation
closure and AVFoundation import were removed from `MediaPlaybackDependencies`.
Its existing async `activatePlaybackAudio` closure remains the narrow
unmuted-`AVPlayer` admission seam and delegates to the coordinator; feature
adapters do not configure or deactivate the session themselves.

No route, endpoint, payload, persistence, feature flag, visible copy/layout,
backend, or deployment contract changed. Physical-device camera startup and
permission recovery, GPS authorization/accuracy, haptic delivery, recording,
speech, audio-route interruption, and APNs behavior remain in the release
acceptance matrix.

The exact final candidate passes the generic iOS Simulator build and the 67-test
coordinator, reusable/Explore playback, and carousel architecture matrix. The
complete `merianTests` target passes 3,303 logical tests (5,291 expanded runs)
with zero failures or skips. All 22 changed Swift files parse and pass strict
SwiftLint with zero violations. XcodeGen is byte-stable, and project/resource,
generated-project source-membership, build/test workflow, event-routing,
adversarial routing, Markdown-format, and whitespace gates pass.

### Core UI milestone feedback

The 924-line `AchievementToastPresenter.swift` aggregate is retired. Immutable
toast payloads and session values now live in `Feedback/Models`; account/scan
identity, deduplication, Field trip receipt mapping, and dictionary eligibility
live in `Policies`; the bounded FIFO presenter and host registry live in
`Presentation`; session control and scan completion/retry sequencing live in
`Coordination`; and the clock plus live adapters live in `Services`. Every
production Feedback file remains below 600 lines. Compatibility aliases retain
the established `AchievementToastPresenter` and `AchievementToastItem` names, so
call sites, previews, layout, copy, accessibility, ordering, timeout, retry,
route, Field trip, achievement, dictionary, and Offline Sync semantics remain
unchanged.

`ScanMilestoneCoordinator` no longer resolves authenticated identity,
`MerianNetworkClient`, `OfflineQueueManager`, `GamificationManager`, or feature
flags directly. Its small initializer-injected dependency value owns account,
acknowledgement, first-Field-trip cache, and notification-eligibility effects;
the existing resolver seams own progress and SwiftData-backed award loading.
`Services/ScanMilestoneDependencies.swift` is the sole live owner, while
`AppDIContainer` explicitly composes `.live` alongside its injected
`AppEventSending` capability. Presentation and policy layers therefore remain
effect-free without adding a singleton or broad protocol.

The 1,178-line test aggregate is replaced by focused presenter, achievement
policy, scan coordinator, and scan policy suites plus shared fixtures. All 40
existing test identities were retained, and injected-effect routing plus scan
identity normalization gained explicit regressions. A source-architecture suite
locks declaration ownership, live-effect isolation, retired aggregate paths,
focused test ownership, and the 600-line ceilings. Coordinator tests construct
their subjects through an isolated dependency factory instead of falling back to
live Auth, Offline Sync, cache, or gamification owners. The generic Simulator
build compiled the extracted production source and strict SwiftLint reported
zero production violations. Direct current-source semantic typechecking also
passed for every extracted production file and all focused milestone suites. A
subsequent complete build-for-testing attempt was blocked before compilation
when CoreSimulatorService and SwiftPM diagnostics cache access became
unavailable; focused and complete runtime execution still require this
candidate's CI or a recovered local simulator. No backend, SwiftData schema,
deployment, or external publication change is part of this slice.

### Core UI capture control ownership

The 707-line `Core/UI/Components/CaptureControlBar.swift` aggregate is retired.
Rendered control-row ownership now lives in
`Features/Capture/Shell/Components/CaptureControls`: the 391-line bar composes
the row and retains its cancellable audio-start task, the 243-line primary
action owns press and 180-millisecond visual-hold timing, and the 125-line
secondary-control group owns the mode-specific buttons. The existing bar
initializer, visible copy, accessibility identifiers, geometry, animations,
button actions, audio/video lifecycle timing, and staging behavior remain stable
for an uninterrupted interaction. A review correction now invalidates a pending
press on mode, inactive-scene, suppression, disablement, or disappearance
transitions and fences its eventual release. This closes a stale visual-hold
race that could otherwise begin video or dispatch the newly selected mode after
the interaction context changed. Pro availability is also read when the hold
matures instead of being frozen at touch-down.

Deterministic visibility, capacity, staged-action, recording-chrome, and haptic
projection lives in the 111-line Shell presentation model. The fixed 17-line
layout contract and 76-line platform-neutral haptic vocabulary moved to
`Capture/Shared/Models` because Scan, Record, Describe, and Shell consume them.
The 52-line `CaptureControlDependencies` service is the only live capture-row
owner for entitlement reads, keyboard dismissal, paywall telemetry, and haptic
delivery. Components no longer resolve `HapticManager`, RevenueCat-derived
entitlement state, `UIApplication.shared`, or telemetry directly. A final parity
review also fenced latent audio state to Audio mode so a pending or paused audio
session cannot alter Visual or Describe chrome.

The pure haptic suite moved from Core UI to
`MerianTests/Features/Capture/Shared/CaptureControlHapticPolicyTests.swift`.
`CaptureControlBarPresentationTests` adds deterministic capacity, visibility,
staging, progress, and cross-mode isolation coverage, while the Shell
dependencies and architecture suites lock injected effects, retired paths,
feature ownership, complete leaf-control reference confinement, primary-press
lifecycle fences, platform-neutral models, and the 600-line ceiling. Before the
review correction, the focused Capture/Record/Scan/Haptics matrix passed 36
tests with zero failures or skips on the iOS 26.5 Simulator and the complete
`merianTests` target passed 3,321 logical tests (5,309 expanded
device/configuration runs) with zero failures or skips. After the correction,
production parsing, the generic iOS Simulator build, and complete test-target
compilation passed again; local runtime execution was unavailable because
CoreSimulatorService could not initialize. Strict SwiftLint reported zero
violations. XcodeGen remained byte-stable, while project/resource,
source-membership and adversarial source-membership, event-routing and
adversarial routing, Markdown-format, and whitespace gates passed.

No endpoint, payload, persistence, schema, feature flag, navigation, copy,
layout, or deployment contract changed. The only behavior correction is the
stale primary-press invalidation above. Physical camera, microphone, speaker,
VoiceOver, Dynamic Type, and long-press interaction remain release-device QA.

### Core UI capture chrome ownership

The remaining one-off Capture chrome is no longer housed in Core UI.
`MainTabBar.swift`, `ActiveScanToolbar.swift`, `MediaModeToggle.swift`, and
`CaptureFlashButton.swift` moved to their narrow feature owners, and the retired
Core paths were removed. The pure `CaptureMode` value now lives in
`Capture/Shared/Models`; Shell owns the native mode selector, workspace
navigation, and flash control; and Staging owns the active mixed-media toolbar.
The later Core UI integration audit confirmed that `FloatingNavigationMenu` is
also Capture-only and moved it beside `MainTabBar`. Core UI retains the shared
cropper and circular-material primitives that have consumers outside this
Capture surface.

`CaptureNavigationDependencies` is the live boundary for Explore feed badge
loading, app-badge coordination, settings mutation, and route feedback.
`CaptureNavigationViewModel` owns the local notification badge and uses a UUID
generation fence so only the newest overlapping refresh may publish and a
completion after disappearance is ignored. An unavailable notification count
preserves its last known value; the established failed-feed behavior continues
to clear the external-post badge. The navigation view retains its original
bindings, copy, identifiers, layout, and mount/foreground/Explore-dismissal
refresh triggers without resolving networking or haptics directly.

`CaptureStagingToolbarPresentation` deterministically projects the canonical
chronological node sequence, existing coverless-video filter, established
visible tray capacity rule, Identify/Analyze copy, and submit availability.
Staging's small live dependency value supplies the Photo Library, keyboard
dismissal, cancel feedback, and process-session tooltip state. Picker
presentation, admission-task cancellation, tooltip visibility, and shimmer
animation remain component-local. Private modality badges and tooltip rendering
remain co-located with the media row, avoiding unnecessary module-internal API.

The selector tests moved from Core UI to Capture Shell without changing their
test identity. Focused navigation tests cover badge projection, unavailable
data, overlap, disappearance invalidation, and feedback injection; focused
Staging tests cover ordering, coverless video, tray capacity, and submit state.
Architecture suites lock the new owners, retired paths, platform-neutral shared
model, live-effect boundaries, and 600-line feature ceilings. No endpoint,
payload, persistence, schema, feature flag, route, visible copy, layout,
backend, deployment, or publication contract changed. The intentional behavior
corrections reject stale overlapping navigation badge results and propagate the
native selector's primary-action event described below.

A second-pass interaction review reproduced a focused iOS 26.5 UI failure in
which an XCUI tap reached the accessible **Record** segment but the selector
remained on **Scan**. The bridge now converges UIKit's documented `valueChanged`
and `primaryActionTriggered` signals; its existing binding guard collapses the
normal dual emission to one action callback. The coordinator also snapshots the
installed-image inputs and skips redundant segment rewrites during unrelated
SwiftUI updates, avoiding control mutation while UIKit may be tracking a touch.
The hosted selector suite mounts the real SwiftUI/UIKit hierarchy in a window
and locks hit testing, both native event routes, and duplicate-event
suppression. This is an accessibility and UI automation correction only: copy,
geometry, ordering, pager ownership, and navigation contracts are unchanged.

Before the selector follow-up, the ownership candidate passed the generic iOS
Simulator build with code signing disabled and a 40-test focused Shell/Staging
matrix on the iOS 26.5 Simulator. The complete `merianTests` target passed 5,323
expanded test executions with zero failures. XcodeGen was byte-stable;
project/resource, generated-project source-membership, Markdown-format, Swift
parsing, strict SwiftLint, and whitespace checks passed. Physical-device camera,
Photo Library, VoiceOver, large Dynamic Type, foreground badge refresh, and
staged-toolbar interaction remain release QA.

The corrective source and tests pass focused typechecking, Swift parsing, strict
affected-file SwiftLint, and project/source-membership validation. The mounted
value-change regression passed immediately before CoreSimulatorService became
unavailable; the new primary-action cases and corrected focused UI test still
require a fresh simulator execution, and no interrupted run is recorded as a
pass.

### Core UI-wide integration audit

The Core UI integration audit reconciles declared ownership against every
production reference. `FloatingNavigationMenu` moved to Capture Shell;
`FlowLayout` moved to Explore Shared because only Feed and Field Trips use it;
`FadingScrollView` moved beside the Profile contribution heatmap;
`ComplimentaryScanDisplayState` moved to Profile Settings Plan; and the
drag-to-confirm pill plus staggered card entrance moved to their respective
Insights subareas. The post-identification permission sheet is reused by Capture
and Profile Settings, so it moved to Core Notifications rather than a feature or
generic Core UI package. The retired Core UI paths are removed.

Presentation owners no longer resolve the live haptic, hardware, notification,
or app-container singletons introduced by those declarations. `SlideToConfirm`
consumes Identification Review feedback, `InsightCardEntranceModifier` receives
hardware eligibility through Insight Content dependencies, notification-sheet
callers inject authorization, and the milestone stack receives app-root-composed
haptic closures through its SwiftUI environment. Existing copy, accessibility,
geometry, animation, dismissal, permission, and route behavior remain unchanged.

`CoreUIArchitectureTests` locks the relocated owner inventory, rejects live
process resolution outside Core UI Services, and applies a 600-line ceiling to
every production Core UI file. `AudioPlaybackCarouselPage` remains just below
that ceiling as one mounted lifecycle boundary: splitting its player, observer,
replacement, boost, seek, and teardown state would require widening private
mutable state across files. The test instead freezes private `@State` and
private lifecycle helpers so a future organizational split must first introduce
a genuinely contained state owner.

The regenerated project, project/resource and source-membership guards, generic
iOS Simulator build, complete build-for-testing, Swift parsing, and strict
SwiftLint pass after the audit. Focused Core UI, notification, Capture Shell,
Profile Settings, Insight Content, and Identification Review suites cover the
new boundaries. No endpoint, payload, persistence, schema, feature flag,
navigation, visible copy/layout, backend, deployment, or publication contract
changes.

### Core Routing foundation

The first Core Utilities hygiene slice moves process-local cross-feature event
and root-route infrastructure into `Core/Routing`. Immutable event, route,
envelope, source, and outcome values live under `Models`; deterministic
coalescing, account-sensitivity, source, and outcome rules live under
`Policies`; and narrow capabilities plus the only mutable event and route
delivery state live under `Coordination`. The former Utilities aggregate files
are removed.

The existing module-internal type and initializer surfaces remain stable.
`AppEventPublisher` is still a synchronous, reentrant, DI-owned `@MainActor` bus
with a private subject. `AppRouteCoordinator` retains the same queue bounds,
priority/FIFO ordering, semantic coalescing, expiry, account/session fences,
outcomes, and one-request presentation identity. No payload, persistence,
navigation, endpoint, feature-flag, copy, or visual behavior changes.

Mirrored Core Routing suites now separate pure policy, mutable coordinator,
event-delivery, and architecture coverage. The architecture suite locks the
exact source inventory and imports, effect-free Models and Policies, retired
Utilities paths, feature-consumption test ownership, and the 600-line production
ceiling. The Capture-specific missing-target regression lives with the concrete
root route consumer under Capture Shell rather than importing feature
composition into the Core coordinator suite. The event-routing guard reads the
canonical event model and publisher owner independently, preserving its
fail-closed event, subject, raw-sink, and platform-notification checks.

XcodeGen is byte-stable. Project/resource and generated-source membership,
production and adversarial event routing, the complete iOS CI-tooling contract,
Swift parsing, focused production/test typechecking, strict SwiftLint, Markdown
formatting, and whitespace checks pass. The code-signing-disabled generic iOS
Simulator build passes. On the iOS 26.5 Simulator, the focused Core Routing plus
Capture missing-target matrix passes 29 tests (28 Swift Testing cases and one
XCTest), and the complete `merianTests` target passes 932 XCTest cases plus
2,424 Swift Testing cases with zero failures.

### Core preference-key and account-deletion security ownership

The second Core Utilities hygiene slice retires the residual
`Core/Utilities/UserDefaultsKeys.swift` aggregate. The exact 70 unchanged
`UserDefaults` strings now live in `Core/Preferences/UserDefaultsKeys.swift`,
while the exact 10 unchanged Keychain strings live in
`Core/Security/KeychainKeys.swift`. Source-level registry tests freeze the full
maps so a future organizational move cannot omit or rename installed state.

Account-deletion recovery now has a focused
`Core/Security/AccountDeletion/{Models,Stores}` package. Models own the exact
installed recovery-phase raw values, fail-closed classification, prepared
capability value, and existing localized storage error. Stores separately own
the read-back-verified defaults phase, manual Apple-revocation notice, protocol
v2 capability envelope, legacy protocol-v1 decoding, secure random generation,
verified Keychain writes/removal, and pre-Auth barrier restoration. The former
flat Security capability file is removed. Existing type and initializer
surfaces, raw values, storage keys, accessibility, event timing, singleton live
defaults, network workflow, payloads, routes, persistence formats, and UI remain
unchanged.

The capability store remains network-free. Core Network Auth retains workflow
phase order through injected effects, `SupabaseManager` retains live Auth and
endpoint assembly, and the Settings adapter retains accepted-account purge.
Mirrored store suites now own tests previously mixed into `AppDIContainerTests`;
the container suite retains container identity, preview isolation, and
launch/root-presentation policy coverage. The Security architecture suite
freezes the exact source/test inventory, declaration uniqueness, effect-free
models, local-only stores, retired paths, and the 600-line production ceiling.
The cross-language account-deletion source contract follows the relocated model
and stores.

Verification passes byte-stable XcodeGen, project/resource and generated-source
membership, production and adversarial event routing, the complete iOS CI
tooling contract, Swift parsing, strict focused production/test typechecking,
strict SwiftLint, exact 70-key defaults and 10-key Keychain comparisons, the
six-test cross-language account-deletion contract, recursive Supabase
functions/scripts formatting, Markdown formatting, and whitespace checks. Full
Xcode build and Simulator execution are not claimed for this local run:
CoreSimulatorService is unavailable, and the managed host rejects SwiftPM's
nested `sandbox-exec` before package compilation even with writable caches.

### Core image and Capture Vision ownership

The third Core Utilities hygiene slice retires three misplaced media helpers.
The cross-feature, stateless `ImageDownsampler` now lives with bounded image
preparation and loading in `Core/Data/Images`. The Vision focus detector is
Capture-only and therefore lives in `Features/Capture/Shared/Services`, where
Scan, Shell imports, and Staging crop confirmation share it. Optional
LiDAR/Vision physical-size estimation has one production consumer and now lives
beside its telemetry composition in `Features/Capture/Submission/Services`.

The existing callable type and static method names remain unchanged. Focus
deadline, cancellation, candidate resolution, telemetry, and normalized-region
semantics are unchanged. The stateless size-estimation namespace is an `enum`
instead of an actor with only a static method; its bounded decode, Vision
request, 70-degree field-of-view model, 4:3 projection, and optional result are
unchanged. No payload, persistence, schema, endpoint, navigation, copy, or
visual contract changes.

Tests mirror the three owners. Core Data Images architecture coverage freezes
the downsampler declaration, imports, test location, retired Utilities paths,
and 600-line ceiling. Capture Shared architecture coverage freezes sole focus-
detector ownership, effect exclusions, test location, and the same ceiling.
Capture Submission architecture coverage freezes size-estimator ownership,
framework/effect exclusions, mirrored tests, and its existing ceiling.

Verification passes byte-stable XcodeGen, project/resource and generated-source
membership, recursive Swift parsing, strict SwiftLint with zero violations, the
complete iOS CI-tooling contract, Markdown formatting, and whitespace checks.
The code-signing-disabled generic iOS Simulator build passes. On the booted iOS
26.5 Simulator, the six focused image/Capture suites pass 27 tests, and the
complete `merianTests` target passes 3,369 reported tests with zero failures or
skips; XCResult records 5,357 passing executions after dynamic parameter
expansion.

That complete run also exposed and corrected two stale guards from the preceding
Preferences/Security slice: the now import-free exact defaults-key registry no
longer expects `Foundation`, and the account-deletion model guard rejects live
`UserDefaults.standard` access without treating explanatory comment text as an
effect.

### Core UI loading and system presentation ownership

The fourth Core Utilities hygiene slice removes the remaining shared UI from the
generic Utilities folder. `GlowPulsingSkeletonView` and its two-style value now
live under `Core/UI/Components/Loading`, matching their use across Explore,
Field Trips, Insights, Profile, Scans, and Species Dictionary. The extraction
preserves the exact fill, glow, border, shadow, animation, Reduce Motion, corner
radius, and raised-grid behavior. The unreferenced `ShimmerModifier` and
`View.shimmering()` API are deleted.

The app-target share namespace is renamed from `ShareSheetUtility` to
`ShareSheetPresenter` and moved to `Core/UI/Services`. Its main-actor UIKit
bridge retains unavailable-root dismissal, caller-prepared activity items,
main-actor completion delivery, traversal to the topmost presented controller,
centered iPad popover anchoring, and animated presentation. The shared bridge
now owns the existing asynchronous actor hop from UIKit completion; Explore Feed
restores its overlay token directly without launching a second task. Explore
Feed, Insight Shell, Profile Shared, and Scans Library call the focused owner;
each retains its existing payload and task, overlay, or playback lifecycle
policy.

`CoreUIArchitectureTests` freezes both sole declaration owners, retired
Utilities paths, removal of the unused shimmer symbols, the only permitted
`UIApplication.shared` lookup in Core UI, the presenter's bounded UIKit
contract, and the existing 600-line ceiling. The Insight integration guard
follows the renamed effect boundary. No payload, persistence, schema, endpoint,
route, copy, layout, animation, accessibility, or share-content contract
changes.

Verification passes byte-stable XcodeGen, project/resource and generated-source
membership, affected-file Swift parsing, strict SwiftLint with zero violations,
Markdown formatting, agent-asset validation, and whitespace checks. The
code-signing-disabled generic iOS Simulator build passes. On the booted iOS 26.5
Simulator, the focused Core UI, Insight integration/export, Explore share-copy,
Profile share-content, and Scans Library matrix passes, followed by the complete
`merianTests` target with zero failures. Physical-device and manual VoiceOver,
large Dynamic Type, Reduce Motion, iPad popover, and share-destination
regression remain release QA.

### Explore Shared error presentation ownership

The fifth Core Utilities hygiene slice moves `ExploreErrorFormatter` from the
generic Utilities folder to `Features/Explore/Shared/Models`. The unchanged pure
mapping owns customer-safe generic, publication, Field Trip detail, Recent
activity, and observation-statistics error copy. Explore Feed, Author Profile,
Map, Identify, Field Trips, Notifications, and Shell consume it directly;
Insights sharing, Scans publication, Species Dictionary, and Species Reference
use it only when adapting an Explore-owned experience. Each caller retains its
existing task cancellation, retry, logging, toast, and presentation lifetime.
The formatter resolves no network, persistence, singleton, or UI effect.

All sixteen behavior cases move intact from the mixed Core Utilities
`MerianConfigTests.swift` file to
`MerianTests/Features/Explore/Shared/ExploreErrorFormatterTests.swift`.
`ExploreSharedArchitectureTests` freezes the sole production declaration,
repository-wide focused test ownership, retired Utilities path, exact
Foundation-only effect boundary, and the 600-line ceiling across every Explore
Shared production source. No error copy, matching order, cancellation
classification, payload, endpoint, persistence, route, or presentation behavior
changes.

Verification passes byte-stable XcodeGen, project/resource and generated-source
membership, affected-file Swift parsing, strict SwiftLint with zero violations,
and a cold code-signing-disabled generic iOS Simulator build using isolated
DerivedData. On the booted iOS 26.5 Simulator, the focused formatter,
architecture, and retained Core configuration suites pass; the ten-suite
cross-feature consumer matrix passes; and the complete `merianTests` target
finishes with zero failures.

### App configuration and Field Trips availability ownership

The sixth Core Utilities hygiene slice retires the misleading
`FieldTripsAvailability.swift` aggregate. The app-wide `FeatureFlag` registry
and `FeatureFlags` resolver now live beside environment and build resources in
`Configuration/FeatureFlags.swift`. The Field Trips-only
`FieldTripSharingAvailability` policy now lives in the feature's `Models/`
directory beside the presentation policies that consume it. The three production
declarations move byte-for-byte without changing callable names, flag cases, raw
values, defaults, titles, summaries, or the installed
`Merian.DebugFeatureFlag.<rawValue>` persistence contract.

The former mixed Utilities suite is split into
`MerianTests/Configuration/FeatureFlagsTests.swift` and
`MerianTests/Features/Explore/FieldTrips/FieldTripSharingAvailabilityTests.swift`.
The configuration suite retains the release/default and retired-Events cases and
additionally freezes every exact installed DEBUG override key.
`FeatureFlagsArchitectureTests` enforces sole declaration and test ownership,
the retired production/test paths, effect boundaries, and the 600-line ceiling.
The behavior suite uses isolated preferences, freezes every installed DEBUG
override key, and verifies that resetting overrides restores every code default.
The static DwC-A launch-gate test reads the new configuration owner, and the
Species Dictionary retirement guard follows that same registry rather than
attempting to open the removed aggregate.

Verification passes byte-stable XcodeGen, project/resource and generated-source
membership, production and adversarial event-routing guards, all iOS CI-tooling
contract tests, privacy/ATS/versioning/migration validation, Swift parsing,
direct production typechecking, focused DEBUG and Release test-source
typechecking, strict SwiftLint with zero violations, the focused two-case DwC-A
launch-gate test, recursive Supabase functions/scripts formatting, focused Deno
lint, Markdown formatting, and a clean generic iOS Simulator build-for-testing
of the app, unit-test, and UI-test targets. Actual Simulator test execution is
not claimed for this local run because CoreSimulatorService is unavailable. No
endpoint, payload, backend, authorization, persistence, schema, navigation,
copy, layout, or release-state behavior changes.

### Domain-owned Core policy constants

The seventh Core Utilities hygiene slice retires `MerianConfig.swift`, which had
become a dependency hub for unrelated AI, image, database, offline-queue, and
media decisions. Each unchanged value now lives beside its behavior:

- `InferenceConfidencePolicy`, `ScanningPhrasePolicy`, and
  `InferenceLookalikeCachePolicy` live under `Core/AI/Inference`;
- `HistoricalSyncPolicy` and `NonBiologicalRetentionPolicy` live under
  `Core/Data/Database`;
- `ImagePreparationPolicy` lives under `Core/Data/Images/Policies`;
- `OfflineQueueBatchPolicy`, `MediaStagingContract`, and
  `OfflineQueueStoragePolicy` live under `Core/Data/OfflineSync/Policies`; and
- `ScanMediaPayloadPolicy` lives under `Core/Media` because Capture, Images,
  OfflineSync, Network, Profile, and Media share its byte ceilings.

The split preserves the exact retention and purge limits; queue batch, fetch,
count, and storage limits; historical page and checkpoint sizes; cache reset
version; image quality and dimensions; Flash/Pro confidence bands and fallback;
Vision thresholds and phrase cadence; and image/audio/video payload and playback
targets. It changes no endpoint, JSON, SwiftData schema, persistence state,
navigation, feature flag, entitlement, layout, copy, or runtime effect.

The mixed `MerianConfigTests.swift` suite is removed. Environment validation now
lives in `MerianTests/Configuration/MerianEnvironmentTests.swift`; focused AI,
Database, Images, OfflineSync, and Media suites freeze their own values and
helper semantics. `CorePolicyOwnershipArchitectureTests` enforces one
declaration per owner with an exact name boundary, focused test presence,
effect-free imports and bodies, selected live image-policy consumer links, the
retired source/test paths, and a 200-line ceiling for the pure policy files.
Existing domain architecture inventories include the new sources and tests.

Initial verification covered byte-stable XcodeGen output, project/resource and
source membership, recursive Swift parsing, strict SwiftLint, the
code-signing-disabled generic iOS Simulator build-for-testing for app,
unit-test, and UI-test targets, Markdown formatting, and whitespace validation.
On the booted iOS 26.5 Simulator, the initial 26-test focused policy and
architecture matrix passed across 11 suites. The complete `merianTests` target
also passed with zero failures; its result bundle reported 3,395 passed tests,
while Swift Testing reported 2,458 tests across 375 suites.

A follow-up audit found four live recrop/display paths that still embedded the
same 1,024 or 2,048 pixel values and a declaration-owner matcher that admitted
longer names sharing a policy prefix. The live paths now reference
`ImagePreparationPolicy`; its maximum inference cap is derived from the Flash
and Pro caps; and the architecture matcher requires a declaration boundary and
freezes those consumer links. The focused matrix therefore contains 27 tests
across the same 11 suites. Byte-stable XcodeGen, project/source membership,
recursive Swift parsing, strict SwiftLint, and the generic build-for-testing
pass on the reviewed source. CoreSimulatorService became unavailable before the
revised 27-test matrix or complete target could be executed at that checkpoint.
The later Core Utilities-wide integration audit's final complete `merianTests`
run covered the corrected policy links and strengthened guards and passed 2,467
tests across 380 suites. The final documentation audit records the domain owners
in their local READMEs, the Core map, testing and manager guides,
image/offline/AI architecture contracts, and the canonical API threshold
contract; no current document points to `MerianConfig` as a live owner.

### Core Utilities-wide integration audit

The eighth and closing Core Utilities slice audits every remaining declaration
and consumer instead of preserving the folder as a generic holding area.
`Core/Utilities` now contains exactly two Foundation-only mechanical value
helpers: cached ISO 8601 formatters and trim-to-non-empty string normalization.
Both remain effect-free and below 100 lines.

Declarations with a narrower responsibility now live beside that behavior:

- `AppLifecycleManager` and its tests move to `App/Lifecycle`;
- `DetachedWork` moves out of `AppDIContainer` into `Core/Concurrency`;
- `FieldNotesRepository` and its tests move to `Core/Data/FieldNotes`;
- `BackgroundTaskWrapper` and `ScanConnectivityFailurePolicy` move with their
  tests to `Core/Data/OfflineSync`;
- `MerianError` moves to `Core/Errors` without absorbing retry or presentation
  policy;
- `Publisher.sinkOnMainActor` moves with its focused ordering test to
  `Core/Hardware/Utilities`;
- bounds-safe array access moves to `Core/UI/Utilities`; and
- species common-name normalization and fuzzy deduplication move to
  `Features/SpeciesReference/Models` with explicit namespace calls from Explore
  and Insights.

The unused generic `Array.removingDuplicates()` API is removed. The mixed
`EventDeliveryTests` aggregate is split between Hardware publisher delivery and
Core Media playback observation. The Field Notes move also closes a correctness
gap exposed by Core Data's existing fail-closed architecture rule: SwiftData
fetch failures now log and return failure instead of collapsing into “row
absent” and allowing a stale defaults value to override unreadable durable
state. Successful reads, writes, legacy promotion, public-to-local repair,
visible behavior, callable production names, payloads, schemas, routes, and
platform behavior remain unchanged.

`CoreUtilitiesArchitectureTests` freezes the exact two-file inventory, imports,
effect exclusions, 100-line ceiling, sole declaration and member owners,
mirrored tests, removed helpers, throwing Field Notes reads, and retired paths.
Existing Core Data, policy, inference, event-routing, project, and
source-membership gates remain part of the closure matrix. The local READMEs,
Core map, lifecycle, error, manager, testing, concurrency, routing, and feature
ownership contracts now point to the focused owners.

Final verification covered byte-stable XcodeGen output, project/resource and
source membership, recursive Swift parsing, strict SwiftLint, the
code-signing-disabled generic iOS Simulator build-for-testing for app,
unit-test, and UI-test targets, the focused Utilities matrix, event-routing
validation and adversarial tests, Markdown formatting, and whitespace
validation. The first complete target run exposed that the relocated scan
connectivity policy was missing from Offline Sync's exact owner inventory; the
inventory now freezes its declaration, path, imports, and effect-free policy
boundary. Its focused architecture suite then passed 5 tests, and the final
complete `merianTests` rerun passed 2,467 tests across 380 suites on the booted
iOS 26.5 Simulator.

A final review found that the whole-folder architecture suite froze the
relocated `DetachedWork` executor but not its coupled `DetachedWorkCategory`
taxonomy. The owner inventory now freezes both exact declarations in
`Core/Concurrency/DetachedWork.swift`, and the local owner README, codebase map,
concurrency architecture, manager guide, and testing strategy state that
boundary explicitly. The same review corrected the earlier policy-checkpoint
note so it no longer obscures the later successful complete-target run. No
production source or runtime contract changed.

Post-review verification passed repeated byte-stable XcodeGen, project/resource
and source-membership guards, event-routing validation, the complete iOS CI
tooling suite, Swift parsing, strict lint, Markdown and Deno formatting, and
whitespace validation. A code-only unsigned generic iOS device
`build-for-testing` compiled the app and test targets with asset catalogs and
storyboards excluded. Full resource compilation and Simulator execution were not
rerun because CoreSimulatorService was unavailable; the preceding complete
Simulator build and 2,467-test run remain the behavioral evidence for the
unchanged production source.

### Post-refactor Core-wide integration audit

After the domain-by-domain Core passes, a cross-domain audit reviewed the final
ownership graph rather than selecting another large file immediately. The Core
root now has an explicit local contract: only `AppDIContainer.swift` and
`MerianLog.swift` are root Swift owners, every domain supplies its own README,
Policies remain bounded and stateless, and reusable Core UI components do not
read transport or persistence directly. The Core guard bans network, SwiftData,
application, preference, task, and singleton acquisition from Policies while an
exact allowlist records the already-documented local-file, clock, and jitter
inputs in Offline Sync, Store Recovery, and RevenueCat access policy.

The audit found two identification-review reads in `InferenceEngine` that used
`try?` and therefore treated an unreadable SwiftData store like an absent row.
`InferenceReviewSnapshotService` now owns one bounded, throwing projection of
the durable species UUID and original AI reasoning. AppDI injects the live
value. Confirmation and reset preflight that read and return before changing
presentation, action generations, local state, or cloud state when durable
authority cannot be read. A missing row retains the established optional-value
compatibility path. Focused tests cover the live projection and both fail-closed
engine paths.

The same audit made raw local file paths, media filenames, localized error
descriptions, and a server-supplied terminal failure message private in the
reviewed Core database, Offline Sync, and camera diagnostics. Stable internal
scan/generation/status identifiers remain public where they are necessary to
correlate lifecycle events; no payload, response body, credential, account
state, or raw coordinate was added to logs.

`CoreIntegrationArchitectureTests` freezes the root/domain inventory, README
coverage, policy boundaries and exact local-input exceptions, the Core-wide ban
on `try?` SwiftData fetches, and privacy-safe diagnostic interpolation. Its
privacy patterns self-test raw errors, multiline localized descriptions, server
messages, and local paths while permitting bounded error kinds and fixed safe
messages. At that audit checkpoint, before the later Phase 3 network-model
splits, it recorded these exact residual production files above the 600-line
review ceiling:

- `Core/AI/InferenceEngine.swift`
- `Core/Network/ExploreAPIModels.swift`
- `Core/Network/FieldTripAPIModels.swift`
- `Core/Network/SupabaseManager.swift`
- `Core/Security/ConsentManager.swift`

That checkpoint inventory prevented silent growth or drift; it did not exempt
the owners from later behavior-preserving splits. The Explore and Field Trips
aggregates are retired below, and subsequent slices reduce the current
large-owner inventory to `SupabaseManager.swift` in the Core README and codebase
map. This audit changed no endpoint, JSON, SwiftData schema, migration,
persistence state, route, entitlement, copy, layout, or deployment contract.

Candidate verification includes byte-stable XcodeGen output, project/resource
and source-membership guards, event-routing validation, recursive Swift parsing,
strict SwiftLint, static mirrors of the new architecture assertions, Markdown
and Deno formatting, whitespace validation, and a code-signing-disabled generic
iOS device `build-for-testing` of the app, unit-test, and UI-test targets. The
current source and all new tests compile. CoreSimulatorService became
unavailable before the focused or complete runtime suites could be rerun; the
latest complete Simulator baseline remains 2,467 tests across 380 suites, and
runtime execution is explicitly outstanding for this candidate.

A follow-up review corrected the initial Core-wide wording, which had described
every Policy as deterministic and effect-free even though the established
Offline Sync contract explicitly permits stateless local-file inspection and
bounded jitter, Store Recovery accepts an injected file manager, and two policy
owners default their clock input. The architecture suite now freezes those exact
exceptions instead of silently omitting them, expands the shared-component
effect exclusions, and proves its diagnostic regexes reject sensitive public
interpolation without rejecting bounded public error kinds. The review snapshot
suite also locks the missing-row result separately from store failure. These are
guard, test, and documentation corrections only; production behavior is
unchanged.

Documentation closure cross-checked the iOS structure, Core root/AI/Data
READMEs, codebase map, manager guide, AI architecture and system overview,
testing strategy, and this RFC against the final source and test owners. It
corrected the last global effect-free-policy wording and attributes composition
guarantees to the Core-wide and domain suites together. Post-correction
verification passed repeated byte-stable tracked XcodeGen output, the unsigned
generic iOS device `build-for-testing`, project/resource and source-membership
guards, event-routing validation and adversarial tests, the complete iOS
CI-tooling suite, Swift parsing, strict SwiftLint with zero violations across
2,384 files, changed-Markdown and exact Supabase Deno formatting, and whitespace
validation. The booted iOS 26.5 Simulator became visible again, but
CoreSimulatorService failed when `xcodebuild` connected, so focused runtime
execution remains outstanding and the preceding 2,467-test baseline remains the
latest complete Simulator evidence.

## Phase 3: Ownership Cleanup

After the large files are split, move code to clearer long-term homes:

- Explore-specific network DTOs and endpoint wrappers should live under the
  narrowest Explore product area when only one area uses them, or under
  `apps/ios/Merian/Features/Explore/Shared/Network/` when reused across multiple
  Explore areas. Only move them outside Explore when another feature depends on
  the same contract.
- Insight-only media ordering, scan-to-export mapping, focus, analysis motion,
  and result composition should stay under `apps/ios/Merian/Features/Insights/`.
  Reusable export/playback processing belongs in `Core/Media`, reusable
  gallery/audio/video/card/toolbar/feedback presentation belongs in `Core/UI`,
  species-level reference presentation belongs in `Features/SpeciesReference`,
  and shared private conversation UI belongs in `Features/FieldChat`.
- Capture modality code should stay under
  `apps/ios/Merian/Features/Capture/<Scan|Record|Describe>/`.
- `Core/UI` should contain reusable primitives only; one-off feature chrome
  should move back into the feature.
- `Core/Utilities` should shrink over time. New utilities belong there only when
  at least two features use them. Process-local cross-feature event and root
  route infrastructure belongs in `Core/Routing`.

### Explore network model ownership

The first Phase 3 slice retires the 1,978-line
`Core/Network/ExploreAPIModels.swift` aggregate. Its unchanged declarations now
live in focused contract-family files under `Core/Network/Models/Explore/`:
browsing data and query values, Community Identification, author profile, Map,
post detail, comments, sharing, media incidents, notifications, public profile,
and Community feedback. Every focused production owner stays below 600 lines.

The cross-feature `ExploreLocationPrivacy` policy moves to
`Core/Models/ExploreLocationPrivacy.swift`, reflecting its use by environment
context, inference/recovery, Explore, Insights, and Profile rather than treating
semantic-location redaction as a network concern. Type names, access levels,
Codable conformances, coding keys, defaults, compatibility decoding, endpoint
signatures, JSON contracts, UI state, and presentation behavior are unchanged.

The second-pass audit also removed an inverted dependency that the aggregate had
masked. The Codable/raw-value `ExplorePostLocationSharing` contract moved from
Feed's composer model into its own Core Network model, while the existing
labels, SF Symbols, and explanatory copy moved to an Explore Shared presentation
extension. Core DTOs no longer depend on Feed's composer model for that wire
enum, and visible copy plus decode behavior remain unchanged. The resulting
focused inventory has thirteen files.

`ExploreNetworkModelArchitectureTests` freezes the thirteen-file inventory,
representative single declaration ownership, the retired aggregate, effect
exclusions, privacy placement, layered post-location-sharing ownership, and the
600-line ceiling. Core Network's integration guard now applies the same ceiling
to `Models/`; the Core-wide residual-large-owner inventory no longer includes
the retired aggregate.

Candidate verification passed byte-stable XcodeGen output, generated-project and
source-membership validation, event-routing validation and adversarial tests,
Swift parsing, focused iOS SDK typechecking including the Swift Testing macros,
strict SwiftLint with zero violations across 1,215 files, the complete iOS
CI-tooling regression suite, changed-Markdown formatting, and whitespace
validation. The declaration inventory and a whitespace-insensitive
reconstruction of the retired aggregate also matched the focused owners exactly.
The required unsigned generic iOS Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the safety wrapper exited before invoking
Xcode because this sandbox denied the process inspection needed to prove that no
other `xcodebuild` was active. No new build or Simulator-runtime result is
claimed for this slice.

### Field Trips network model ownership

The second Phase 3 slice retires the 928-line
`Core/Network/FieldTripAPIModels.swift` aggregate. Its 49 unchanged
network-model declarations now live in eight focused contract-family owners
under `Core/Network/Models/FieldTrips/`: achievement, capture, catalog, Events,
community queries, profile, progress, and publications. Backend `Challenge`
names, type access, Codable conformances, coding behavior, default values, and
endpoint signatures remain unchanged; every focused production owner is below
600 lines.

Responsibilities hidden by the aggregate now sit with their actual consumers.
Field Trips feature models own community labels, guide fallback, lifecycle, and
publication presentation. Insights Shell owns scan-contribution route mapping.
Core UI Feedback owns credited-progress fallback and first-Field-trip milestone
projection/merging. Core Preferences owns the exact account-qualified
`UserDefaults` compatibility store. The move changes no JSON, action, request,
response, persistence key, SwiftData schema, navigation, copy, or visible
behavior.

`FieldTripNetworkModelArchitectureTests` freezes the eight-file inventory, all
49 production-wide declaration owners, effect exclusions, relocated non-wire
responsibilities, retired aggregate, and 600-line ceiling. At this checkpoint,
the Core-wide residual-large-owner inventory contained `InferenceEngine.swift`,
`SupabaseManager.swift`, and `ConsentManager.swift`. Field Trips decoding and
endpoint behavior remain covered by their existing suites;
`FieldTripModelPresentationTests` owns the relocated feature accessors, while
Insights, UI Feedback, Preferences, and Author Profile tests retain their domain
behavior coverage. The dedicated `FirstFieldTripProgressStoreTests` suite owns
normalized account isolation, persistence round trips, and invalid-value
rejection.

Candidate verification passed byte-stable XcodeGen, generated-project/resource
and source-membership guards, event-routing validation and adversarial tests,
the complete iOS CI-tooling suite, recursive app/test Swift parsing, focused
iOS-SDK source and test typechecks, exact 49-declaration and architecture
mirrors, and strict SwiftLint with zero violations across the complete iOS app
and test source paths. Changed Markdown formatting and whitespace validation
also passed. The required generic iOS Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the safety wrapper refused before
invoking Xcode because this sandbox could not inspect whether another
`xcodebuild` was active. No fresh build or Simulator runtime result is claimed
for this slice.

### Consent facade completion

The final Core Security Consent slice reduces `ConsentManager.swift` from 1,050
to 597 lines and removes it from the residual large-owner inventory. The public
initializer and method surface, nested compatibility types, observable state,
policy copy and versions, durable ledger and Keychain formats, table/RPC and
Realtime contracts, Auth-transition drain, inference gate, and lifecycle timing
remain unchanged.

Four focused owners receive the responsibilities that had remained in the
facade. `ConsentManagerRuntime` constructs the repository, mutation service, and
coordinators and wires their narrow callbacks. `ConsentMutationService` creates
adult, Terms, Gemini, and PostHog evidence and preserves the exact
privacy-close-before-write and journal recovery ordering through deterministic
clock, UUID, and app-metadata dependencies; its separate live adapter owns those
process and `Bundle.main` values. `ConsentStateProjectionPolicy` derives account
ownership, required-consent and cloud-readiness gates, account-qualified pending
counts, reapproval, and fail-closed analytics SDK permission.
`ConsentCloudSessionCoordinator` owns ordinary and transition-authorized session
adoption, account-work lease fencing, scheduled synchronization, inference cloud
admission, and verified Ghost evidence rebinding. Its separate live dependency
adapter is the only owner that resolves Supabase Auth, account-work leases,
account-deletion cleanup state, and bounded failure logging for those workflows.

All twenty-one extracted production owners and the observable facade remain at
or below the 600-line review ceiling. `ConsentStateProjectionPolicyTests`,
`ConsentMutationServiceTests`, and `ConsentCloudSessionCoordinatorTests` add
deterministic coverage for the new boundaries. `ConsentArchitectureTests`
freezes the exact inventory, type ownership, runtime wiring, effect confinement,
and line ceiling. The cross-language Ghost client contract now reads the facade,
runtime, cloud-session core/live adapter, state projection, and focused tests in
addition to the existing synchronization, restoration, Realtime, repository, and
retry owners, so the relocated lease and session fences cannot silently leave
that contract.

The completion audit closed one first-scan admission race exposed by the new
state owner. Creating an anonymous session could publish the session before the
coordinator decided whether the previously unowned required evidence remained
eligible, causing the owner projection to hide that evidence before
synchronization could bind it. The coordinator now snapshots complete unowned
required evidence before adoption, admits it only when no ledger account already
owns it, and rechecks the account-work lease plus synchronization generation
after suspended work. Cancellation and stale lease/generation exits are resolved
before missing proof is interpreted, so an invalidated first-scan task cannot
persist or publish reapproval for the replacement context. Focused tests cover
the successful first-scan path through the real synchronization-service
pipeline, cross-account rejection, stale lease, stale generation without
reapproval, and final-session Ghost rebind verification.

The slice changes no API payload, SwiftData schema, database migration, RLS or
grant, persistence key or format, policy statement/version, provider, feature
flag, navigation, copy, layout, or release control. The current Core residual
inventory is `SupabaseManager.swift`.

Candidate verification passed byte-stable XcodeGen output, generated-project,
resource, source-membership, event-routing, and adversarial routing guards,
Swift parsing, focused iOS-SDK source and test typechecks, strict
affected-source SwiftLint, the complete iOS CI-tooling suite, the focused Ghost
and legal-consent contracts, all 1,944 Edge Function tests, the complete
Supabase function/script format check, changed-Markdown formatting,
documentation contracts including local links, and whitespace validation. The
required unsigned generic iOS Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the safety wrapper exited before invoking
Xcode because this sandbox could not inspect whether another `xcodebuild` was
active. No fresh build or Simulator runtime result is claimed for this slice.

### SupabaseManager Account Deletion Orchestration

The sixth `SupabaseManager` hygiene slice moves fresh account-deletion
orchestration and durable recovery routing out of the live facade. The public
manager deletion and recovery signatures remain unchanged and now delegate to
`AccountDeletionCoordinator` and `AccountDeletionRecoveryCoordinator`.
`AccountDeletionCoordinationDependencies` groups narrow purchase-handoff,
local-state, exact-session, cached-session, sign-out, and diagnostics closures;
the coordinators acquire no Supabase/provider SDK, singleton, or logger and
create no task. `SupabaseManager` remains the composition root for those live
effects.

The pure `AccountDeletionWorkflow` remains the owner of reusable phase-ordering
primitives. The fresh coordinator selects prepared v2 versus compatible v1
intake, fences every suspended result to the owned Auth transition, and
sequences accepted cleanup, acknowledgement, and proof retirement through that
workflow. The recovery coordinator routes every installed marker, legacy and v2
capability, definitive noncommit restoration, accepted cleanup, acknowledgement,
and retirement. Deferred restoration still adopts and revalidates the exact
cached source while the durable marker is present, removes that marker as its
final failable step, then publishes without suspension.

This reduces `SupabaseManager.swift` from 5,389 to 4,870 lines. All three new
production owners remain below the 600-line review ceiling.
`AccountDeletionCoordinatorTests` covers fresh v2 phase/effect order and both
preflight fences. `AccountDeletionRecoveryCoordinatorTests` covers no-marker,
legacy replay, v2 accepted and noncommitted recovery, stale-session refusal,
acknowledgement retention, proof-only restoration, and final retirement.
`CoreNetworkIntegrationArchitectureTests` freezes the resulting twelve-file Auth
inventory and prevents the manager from reacquiring the removed recovery
helpers. The cross-language account-deletion source contract reads both new
coordinators alongside the pure workflow.

A second-pass review also closed two installed-state edge cases exposed by the
new owner. A pre-capability `intake_pending` marker with no proof now creates a
read-verified raw protocol-v1 proof and keeps every retry in the legacy hash
domain; it can no longer create a v2 envelope, submit that recovery value to the
v1 route, and relaunch into a mismatched v2 lookup after an ambiguous response.
A proofless `capability_prepared_pending` marker now cancels against only the
exact cached source session because non-destructive preparation completed but
commit had not started. Store tests pin v1 creation/reuse and reject v2
reinterpretation; recovery tests cover proofless prepared cancellation and an
ambiguous v1 request followed by relaunch with the same proof. The review also
accounts for devices that already persisted the former mixed state: v2 unknown
at intake/cleanup now probes legacy recovery and keeps both proof and barrier
unless that domain returns a positive match.

The structural extraction changes no JSON payload, endpoint action, Auth
transition value, persisted key name or supported encoding, SwiftData schema,
provider behavior, copy, route, feature flag, deployment, or release control.
The second-pass fixes intentionally tighten installed recovery routing without
changing either endpoint contract.

Candidate verification passed byte-stable XcodeGen output, generated-project,
resource, source-membership, event-routing, transport-security, and iOS
CI-tooling guards, Swift parsing, focused iOS-SDK source and test typechecks,
strict affected-source SwiftLint, a native deterministic mixed-domain recovery
probe, the focused six-test cross-language deletion contract, 1,944 passing Edge
Function tests with one ignored, the complete Supabase function/script format
check, changed-Markdown formatting, all 26 documentation contracts and
local-link checks, and whitespace validation. The required unsigned generic iOS
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the safety wrapper exited before invoking Xcode because this sandbox could not
inspect whether another `xcodebuild` was active. No fresh build or Simulator
runtime result is claimed for this slice.

### SupabaseManager Purchase-safe Sign-out Coordination

The seventh `SupabaseManager` hygiene slice moves purchase-safe sign-out route
policy out of the live facade while preserving `transitionToGhostSession()`,
`retryPendingSignOutPurchaseHandoff()`, and the recovery-owned Ghost-reset path.
`PurchaseIdentitySignOutCoordinator` now owns ordinary versus linked routing,
stable-principal versus compatibility selection, installed-proof continuation or
exact-source abandonment, failed-attempt source restoration, and exact anonymous
retry admission. It continues to delegate phase checkpoints and
proof-removal-last ordering to `PurchaseIdentitySignOutWorkflow`.

`PurchaseIdentitySignOutCoordinationDependencies.swift` defines the narrow
SDK-session snapshot, Auth-transition, journal, provider-readiness, restoration,
and diagnostics closure boundaries. Its session snapshot preserves the exact SDK
`User` only inside an injected telemetry closure, so the coordinator remains
provider-neutral without substituting a later manager-published user.
`SupabaseManager` remains the composition root and sole owner of Supabase,
RevenueCat, entitlement, Keychain, endpoint, logging, and task effects. The
coordinator and dependency package create no task, import no provider SDK, and
resolve no singleton.

This reduces `SupabaseManager.swift` from 4,870 to 4,772 lines. The 315-line
coordinator and 91-line dependency owner remain below the 600-line Core Network
review ceiling. Fourteen deterministic coordinator tests cover both purchase
modes, initial and post-retirement unreadable journals, existing anonymous
destinations, unrelated stable and legacy linked sources, failed preparation
restoration, unverified linked sessions, ordinary anonymous replacement, exact
recovery retry, and recovery-only reset admission. The architecture suite
expands the Auth inventory from twelve to fourteen files and prevents live
routing from returning to the manager.

The second-pass review restores the fail-closed RevenueCat readiness fence when
a stable proof is retired but the verifying journal reread fails. It also limits
the coordinator's manager-owned reset entry point to `.recovery` transitions and
adds exact-transition checks before and after suspended linked-source discovery
and stable preparation. These are safety corrections to indeterminate and stale
local state; they do not change a successful sign-out path or any wire contract.

The extraction changes no API payload, endpoint action, durable journal shape or
key, Auth transition value, provider behavior, entitlement rule, SwiftData
schema, feature flag, navigation, copy, deployment, or release control.

Candidate verification passed byte-stable XcodeGen output, generated-project,
resource, source-membership, event-routing, transport-security, and iOS
CI-tooling guards, full Swift parsing, focused iOS-SDK production and test
typechecks, strict repository-wide SwiftLint with zero violations, a native
deterministic sign-out route probe, the focused 42-test purchase-principal and
documentation contract matrix, the complete Supabase function/script format
check, changed-Markdown formatting, and whitespace validation. The required
unsigned generic iOS Simulator `build-for-testing` was attempted through
`make ios-local-build`, but the safety wrapper exited before invoking Xcode
because this sandbox could not inspect whether another `xcodebuild` was active.
No fresh build or Simulator runtime result is claimed for this slice.

### SupabaseManager Purchase-handoff Completion

The eighth `SupabaseManager` hygiene slice moves stable-rotation claim and
legacy compatibility completion out of the live facade while preserving the
existing private completion entry point and every public sign-out/retry
signature. `PurchaseIdentityHandoffCoordinator` owns the single-flight keyed by
destination, Auth generation, and transition owner; the stable-versus-
compatibility completion route; post-suspension session and cancellation fences;
terminal-only compatibility retirement, restored-source abandonment, and
proof-removal-last boundary. `PurchaseIdentityHandoffCoordinationDependencies`
groups exact-session, journal, provider, entitlement, remote-operation, and
diagnostics closures without acquiring a live dependency.

The public completion entry rejects cancellation before task admission, and the
coordinator-owned task checks again before journal selection. Transition
ownership is part of the task key, so a transition-owned call replaces older
ownerless work even when destination and Auth generation are unchanged.

`LegacyPurchaseHandoffRemoteService` is the typed compatibility boundary. Its
live adapter is the sole owner of the private prepare/bind/complete/cancel DTOs,
all four operations across three `transfer-signout-purchases` SDK invocation
paths, exact response-identity validation, and terminal
`handoff_expired`/`handoff_invalid` classifier. `SupabaseManager` constructs
that adapter and supplies the live Supabase Auth, purchase resolver, RevenueCat,
entitlement, journal, telemetry, and logging effects. It no longer stores the
four handoff task/key fields or owns the completion algorithms.

This reduces `SupabaseManager.swift` from 4,772 to 4,516 lines. The 409-line
coordinator, 87-line dependency package, and both compatibility-service files
remain below their review ceilings. Eleven coordinator tests cover
already-cancelled caller preflight, stable and compatibility order, same-context
convergence, same-session transition-owner replacement, replacement-generation
cancellation before proof removal, late cancelled-task mutation suppression,
stale-session retention, terminal versus transient proof retirement, unreadable
selection, and restored-source abandonment. Two service tests cover typed
operation forwarding and exact terminal classification. The Core Network
architecture guard expands the Auth inventory from fourteen to sixteen files,
prevents the retired helpers/task fields from returning to the manager, and
follows stable/compatibility generation fences in the coordinator. The
purchase-principal architecture and cross-language migration contracts pin the
new service ownership and live route shape.

The extraction changes no request or response body, endpoint action, Auth
transition value, durable journal key/encoding, RevenueCat identity, entitlement
rule, SwiftData schema, feature flag, navigation, copy, deployment, or release
control. Proof removal still occurs only after successful provider/server work,
a current entitlement projection, cancellation checks, and exact anonymous
session revalidation.

Candidate verification passed generated-project and source-membership checks,
full changed-Swift parsing, strict affected-source SwiftLint, focused production
and test typechecks, a warnings-as-errors typecheck of all 1,281 app sources,
the 14-case native Network/Purchase Identity architecture runner, the 16-case
cross-language purchase-principal contract, the complete Supabase Edge Function
suite (1,944 passed, zero failed, one ignored), and the complete Supabase
function/script format check. The required generic Simulator `build-for-testing`
was attempted through `make ios-local-build`, but the safety wrapper stopped
before invoking Xcode because this sandbox could not inspect whether another
`xcodebuild` was active. No fresh build or Simulator runtime result is claimed
for this slice.

### SupabaseManager Auth-coordinator Integration Audit

The integration audit after the account-deletion, purchase-safe sign-out, and
purchase-handoff completion extractions reviewed transition admission,
account-work quiescence, durable journal checkpoints, cancellation, source
restoration, and proof retirement as one lifecycle rather than as isolated
owners. It found six cross-owner gaps. A foreground purchase-handoff retry could
read its anonymous SDK session while earlier account-bound work was still
admitted; purchase-safe sign-out did not honor cancellation between its identity
phases; already-cancelled deletion and sign-out callers could open a transition
or single-flight; pending-proof recovery could complete after a cancelled
anonymous-session initialization; and cancelled source-restoration work could
continue toward proof or readiness mutation after suspension. A follow-up review
also found that a classified `401` cancelled during session refresh could
proceed into Ghost regeneration or local-session cleanup.

The corrected lifecycle now rejects cancellation before transition or
single-flight admission, drains account-bound work before a recovery retry reads
the SDK session, and rechecks cancellation between preparation, local sign-out,
anonymous initialization, and completion. Stable and compatibility preparation
continue to persist every returned one-use proof before cancellation is honored,
so a stopped task cannot lose the credential required for relaunch recovery.
Pending-proof recovery revalidates cancellation, transition ownership, and the
exact anonymous destination after initialization and before completion.
Source-only abandonment and failed-sign-out restoration recheck cancellation and
exact transition/session ownership after suspension and before proof or
readiness mutation. The request executor now rechecks cancellation after every
suspended unauthorized-recovery decision, while the public Ghost-reset boundary
checks before transition admission and after each SDK, purchase-link,
entitlement, and final-session suspension.

Focused coverage grows the Auth foundation single-flight suite to nine cases,
the fresh-deletion coordinator suite to four, and both the sign-out workflow and
route-coordinator suites to sixteen and seventeen cases, respectively. The
request-executor suite now has eleven cases, including cancellation during an
unauthorized refresh before Auth mutation. The Core Network architecture test
freezes the new admission and phase order, while the cross-language
purchase-principal contract pins recovery quiescence and
persistence-before-cancellation ordering alongside the unchanged Edge protocol.

This audit changes no request or response body, endpoint operation, durable
journal key or encoding, Auth transition value, purchase-provider identity,
entitlement rule, SwiftData schema, feature flag, navigation, copy, deployment,
or release control.

After these audit fixes, `SupabaseManager.swift` is 4,541 lines. That count is
recorded as remaining facade debt: the enforced 600-line review ceiling applies
to the extracted Core Network owners and `MerianNetworkClient`, not to
`SupabaseManager` itself.

Candidate verification passed byte-stable XcodeGen output, generated-project,
source-membership, event-routing, transport-security, and iOS CI-tooling guards;
changed-Swift parsing; strict affected-source SwiftLint with zero violations;
focused production and XCTest semantic typechecks; the 11-case native request
executor suite; the 13-case native Core Network architecture suite; the 16-case
cross-language purchase-principal contract; all 1,944 Edge Function tests with
one ignored; the complete function/script format check; all 26 documentation
contracts and local-link checks; changed-Markdown formatting; and whitespace
validation. The required generic Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the safety wrapper refused to invoke Xcode
because this sandbox cannot inspect active `xcodebuild` processes. No fresh
Simulator build or XCTest runtime result is claimed for the audit.

### SupabaseManager OAuth Sign-in Coordination

The ninth `SupabaseManager` hygiene slice moves provider-neutral Apple and
Google completion out of the live facade while preserving the public sign-in
entry points, Apple delegate, provider presentation, visible behavior, and every
wire or persistence contract. `OAuthSignInCoordinator` now owns pending
purchase-handoff admission; direct same-UUID identity linking versus provider-
bound Ghost fallback; exact-session adoption; credential registration required
for Apple and forbidden for Google; exact provider-to-transition agreement;
normalized metadata persistence; telemetry and purchase-identity readiness;
entitlement; public-author refresh/event publication; and the authenticated-
OAuth marker. `OAuthSignInCoordinationDependencies` exposes those effects as
narrow main-actor closures and creates no task.

`OAuthSignInWorkflow` owns cancellation-aware SDK-session replacement around the
analytics-suppression boundary and bounded same-registration Apple credential
retry. `OAuthIdentityTokenPolicy` owns the bounded, control-character-safe
provider-subject extraction needed by the conflict fallback, while
`OAuthSignInModels` owns provider-neutral credential, exact-session, completion,
normalized metadata, and workflow-error values. `SupabaseManager` remains the
only live provider/Supabase composition root: Google and Apple bridges prepare
those values, inject SDK/Edge/RevenueCat/Keychain/telemetry and lifecycle
effects, and retain failure cleanup.

The split reduces `SupabaseManager.swift` from 4,541 to 4,391 lines. All five
new production owners remain below the 600-line review ceiling and import only
Foundation. Four focused suites own token parsing, metadata normalization,
session replacement, Apple retry, direct-link and Ghost-fallback routing,
completion order, fail-closed provider/transition and registration
configuration, cancellation, required-credential failure, and nonfatal-metadata
failure behavior. Rehomed workflow test method names remain stable. The Core
Network architecture guard now freezes the exact twenty-one-file Auth inventory,
new ownership boundaries, live-effect exclusions, and retired aggregate helper
names. The Apple and Ghost Deno source contracts read the extracted coordinator,
workflow, and token policy directly.

This slice changes no endpoint, payload, response, Supabase Auth action,
Keychain key or encoding, RevenueCat identity, entitlement decision, SwiftData
schema, feature flag, navigation, copy, layout, deployment, or release control.
Local verification covered byte-stable XcodeGen; generated-project source and
resource membership; event-routing, transport-security, and iOS CI-tooling
guards; Swift parsing; focused iOS-SDK production and XCTest semantic
typechecks; strict affected-source SwiftLint with zero violations; the 14-case
Apple/Ghost cross-language matrix; all 1,944 Edge Function tests with one
intentional ignore; the complete 852-file Function/script format check; all 26
documentation and local-link contracts; changed-Markdown formatting; and
whitespace validation. The required generic Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the safety wrapper refused to
invoke Xcode because this sandbox cannot inspect active `xcodebuild` processes.
No fresh Simulator build or XCTest runtime result is claimed for this slice.

### SupabaseManager Auth-session Lifecycle Coordination

The tenth `SupabaseManager` hygiene slice moves provider-neutral Auth-event
projection and restored-session recovery ordering out of the live facade while
preserving the Supabase stream, listener task, SDK mapping, public observable
state, and every external contract. `AuthSessionLifecycleModels` owns the event
origin, adoption/session/generation envelope, and fixed diagnostic categories.
`AuthSessionLifecycleCoordinationDependencies` defines narrow state, durable-
fence, purchase/entitlement, synchronization, and diagnostic closures.
`AuthSessionLifecycleCoordinator` owns account-deletion and active-transition
deferral; independent fail-closed Ghost and purchase-journal projection;
authenticated, awaiting-refresh, and signed-out state order; anonymous and
restored-source purchase handoff; immediate local server-verified entitlement
projection closure behind an accepted deletion barrier; entitlement order;
post-suspension exact-generation/transition fencing; and historical-sync
admission. It creates no task and imports no provider SDK.

`SupabaseManager` remains the sole live composition root. It advances the Auth
generation and transition owner, maps each SDK callback into the
provider-neutral event, injects Supabase, RevenueCat, consent, telemetry,
entitlement, durable-store, and synchronization effects, and retains the
listener and scheduled history tasks. The split reduces `SupabaseManager.swift`
from 4,391 to 4,375 lines. All three new production owners remain below the
600-line review ceiling.

`AuthSessionLifecycleCoordinatorTests` owns thirteen deterministic cases for
both early deferrals, independent durable-store read failures, anonymous handoff
before entitlement, identity-change reset order, restored-source abandonment and
relinking, deletion-barrier local entitlement projection closure, stale
generation and transition overlap after purchase or entitlement suspension,
awaiting-refresh projection, sign-out overlap, signed-out cleanup order, and
inconsistent events. The Core Network architecture guard freezes the exact
twenty-four-file Auth inventory, lifecycle ownership, effect exclusions, and
production ordering. The purchase-principal cross-language contract reads the
new coordinator directly for awaiting-refresh, accepted-deletion
purchase/entitlement closure, and sign-out ordering.

This slice changes no endpoint, payload, response, Supabase Auth action,
RevenueCat identity, entitlement policy, durable journal key or encoding,
SwiftData schema, feature flag, navigation, copy, layout, deployment, or release
control. Its review follow-up clears the local server-verified entitlement
projection when the Auth listener observes accepted deletion cleanup as its
barrier; it does not mutate server entitlement. Candidate verification covered
byte-stable XcodeGen; generated-project and source-membership validation;
event-routing, transport-security, and iOS CI-tooling guards; Swift parsing;
strict affected-source SwiftLint with zero violations; focused production,
XCTest, and architecture semantic typechecks; the 16-case purchase-principal
cross-language contract; all 1,944 Edge Function tests with one intentional
ignore; all 26 documentation and local-link contracts; the complete 852-file
Function/script format check; changed-Markdown formatting; and whitespace
validation. The required generic Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the safety wrapper refused to invoke Xcode
because this sandbox cannot inspect active `xcodebuild` processes. No fresh
Simulator build or XCTest runtime result is claimed for this slice.

### SupabaseManager Purchase-identity Session Readiness

The eleventh `SupabaseManager` hygiene slice moves provider-neutral purchase-
identity session state, keyed resolution, foreground repair, and the legacy
profile lookup out of the live Auth facade. `PurchaseIdentitySessionCoordinator`
owns active binding and last-linked-user state plus one resolution task keyed by
the exact Auth session, capability fingerprint, and creation policy. It
republishes every durable handoff read to the provider mutation fence, closes
that fence on unreadable evidence, rejects late results from superseded task
keys, and revalidates the published session before and after provider work.
`PurchaseIdentityReadinessCoordinator` owns foreground account-work admission,
SDK-session validation, anonymous handoff completion or restored-source
retirement, identity and entitlement readiness, and the final
SDK/session/provider fence.

`LegacyPurchaseIdentityProfileService` provides the typed profile lookup; its
live adapter is the sole Supabase/private-DTO owner for the established `users`
projection. `PurchaseIdentitySessionCoordinationDependencies` keeps the
coordinators independent of Supabase, RevenueCat, entitlement, Keychain,
logging, and singleton resolution. `SupabaseManager` remains the live
composition root and public compatibility facade and, at this intermediate
slice, still supplied those effects and retained the Supabase Auth
stream/listener and provider SDK calls. The later
[`Purchase Identity Session Live Boundary Extraction`](#supabasemanager-purchase-identity-session-live-boundary-extraction)
slice moved ordinary provider, entitlement, resolver, profile-query, and
diagnostic acquisition into the focused Core Security live adapter. The split
reduces the manager from 4,375 to 4,244 lines; every new production owner is
below 250 lines.

Focused suites cover stable/legacy resolution, durable-handoff fence projection
and fail closure, stale generation and final-admission cache rejection,
already-ready elision, same-context single-flight, differently keyed task
supersession, foreground admission and lease completion, restored-source
recovery, entitlement and final-session fences, and typed legacy-profile
forwarding. The Purchase Principal architecture and cross-language migration
contracts freeze the new inventory, effect exclusions, task ownership, and live
query shape.

This slice changes no request or response body, endpoint action, Auth transition
value, durable journal key or encoding, RevenueCat identity, entitlement rule,
SwiftData schema, feature flag, navigation, copy, deployment, or release
control.

Candidate verification covered byte-stable XcodeGen; generated-project and
source-membership validation; event-routing, transport-security, and iOS CI-
tooling guards; a warnings-as-errors iOS Simulator SDK module compile of all
1,295 app-target Swift sources; focused iOS-SDK test typechecking; 16 native
coordinator/profile/ownership tests; all 13 Core Network integration
architecture tests; the 16-case purchase-principal cross-language contract; all
1,944 Edge Function tests with one intentional ignore; strict SwiftLint; the
complete Function/script format check; documentation and local-link contracts;
changed-Markdown formatting; and whitespace validation. The required generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the safety wrapper refused to invoke Xcode because this sandbox cannot inspect
active `xcodebuild` processes. No fresh Simulator build or XCTest runtime result
is claimed for this slice.

A subsequent correctness review found that the direct session-resolution route
read the durable handoff journals without also refreshing RevenueCat's in-memory
mutation fence. The shared handoff boundary now publishes every successful read
and publishes a closed fence on failure. The same review added a controlled
differently keyed overlap regression proving a cancelled predecessor cannot
publish over the newer binding or clear its task state. Follow-up verification
passed 17 native coordinator/profile/ownership cases, all 13 Core Network
integration architecture cases, focused warnings-as-errors iOS-SDK source and
test typechecking, strict SwiftLint, byte-stable XcodeGen, project/source
membership, event-routing, transport-security, complete portable iOS CI tooling,
the 16-case purchase-principal cross-language contract, documentation contracts,
Markdown formatting, and whitespace validation. The canonical Simulator build
was attempted again, but the local wrapper stopped before Xcode because this
sandbox cannot inspect active `xcodebuild` processes; no new Simulator build or
runtime result is claimed.

The documentation follow-up synchronized the iOS root and Core Security
ownership guides, the foreground lifecycle sequence, and the Keychain authority
contract with that correction. They now state that both direct resolution and
foreground repair publish every durable handoff read to the provider mutation
fence, publish pending state on an unreadable journal, and reject late
differently keyed resolution results. The API, revenue/identity, system
architecture, Core-manager, test-ownership, codebase-map, and purchase-principal
RFC descriptions already carry the same boundary. No backend payload,
deployment, persisted format, or release procedure changed.

### SupabaseManager Ghost-profile Merge Coordination

The twelfth `SupabaseManager` hygiene slice moves provider-bound Ghost merge
preparation, queue-wide completion, retry, analytics-suppression projection,
terminal cleanup, and keyed task lifetime into
`Core/Network/Auth/Coordinators/GhostProfileMergeCoordinator.swift`. Its narrow
dependency package carries exact Auth-session and account-work admission,
secure-queue operations, purchase and consent synchronization, terminal error
classification, suppression, and privacy-safe diagnostics without acquiring a
live SDK, singleton, or logger. Completion is keyed by the exact permanent
target UUID and optional Auth-transition owner; a new key cancels the old task,
and task UUID ownership prevents a late predecessor from clearing the newer
handle.

`Core/Security/GhostProfileMerge/Services` now owns a closure-backed typed
remote boundary and its sole live Supabase adapter. The live file contains all
private `merge-ghost-profile` prepare, complete, and identity-refresh DTOs and
Function calls plus provider-conflict and terminal-error mapping. The manager
constructs that service and the existing secure store, injects Auth, RevenueCat,
consent, Keychain, and logging effects, and preserves its existing entry points.
The split reduces `SupabaseManager.swift` from 4,244 to 3,998 lines; all four
new production files remain below the 600-line review ceiling.

The preparation path rejects a provider-mismatched Auth transition before its
first remote effect and deliberately secures a capability returned by the server
before honoring caller cancellation, so response-time cancellation cannot lose
relaunch recovery authority. It also revalidates the exact source after the
response and before persistence. Completion rechecks cancellation and
exact-session ownership around every remote/provider/local-evidence phase and
before terminal evidence synchronization or proof removal. An invalid retained
source marks that item unresolved but does not block later handoffs, preserving
the installed queue semantics. No request/response field, endpoint operation,
Keychain key, persisted JSON, valid Auth-transition behavior, RevenueCat action,
consent contract, SwiftData schema, feature flag, UI, deployment, or release
control changed.

`GhostProfileMergeCoordinatorTests` adds deterministic coverage for returned-
proof cancellation durability, stable source replacement, provider-transition
mismatch, post-response source-session drift, same-key single-flight, target and
owner supersession, unreadable-queue fail closure, transient retention, terminal
synchronization-before-clear, cancelled terminal responses, later-proof
progress, empty-queue suppression reopening, and source-scoped clearing.
`GhostProfileMergeRemoteServiceTests` owns typed prepare/complete/refresh
forwarding and both live error classifiers. The Core Network architecture guard
now freezes twenty-six Auth files, the third structured task owner, the Core
Security model/service/store inventory, sole live DTO/call ownership, test
rehomes, and aggregate-manager exclusions. The cross-language Ghost client
contract reads the new coordinator, dependencies, service/live adapter, and
focused tests directly.

A second review corrected the aggregate-ownership guards to use every exact
retired manager helper name, including the former preparation, queue,
completion, classification, and task-cancellation owners. Both the native
architecture test and cross-language client contract now fail if any of those
implementations drift back into `SupabaseManager`.

Candidate verification passed Swift parsing; warnings-as-errors iOS SDK
typechecking of the coordinator core and live remote adapter; focused iOS SDK
test and architecture typechecking; strict affected-source SwiftLint with zero
violations; the eight-case Ghost client contract and complete 1,944-test
Function suite with one intentional ignore; XcodeGen byte stability,
generated-project and source-membership validation; event-routing,
transport-security, and iOS CI-tooling guardrails; recursive Function/script
formatting; changed-Markdown formatting; documentation contracts; and whitespace
validation. The required generic Simulator `build-for-testing` was attempted
through `make ios-local-build`, but its safety wrapper refused before Xcode
because this sandbox cannot inspect active `xcodebuild` processes. No new
Simulator build or XCTest runtime result is claimed. No hosted request, live
identity/provider mutation, deployment, or external publication was performed.

### SupabaseManager Auth-session Bootstrap Coordination

The thirteenth `SupabaseManager` hygiene slice moves reusable-session admission,
existing-session resolution, anonymous creation, and bootstrap task lifetime
into `Core/Network/Auth/Coordinators/AuthSessionBootstrapCoordinator.swift`.
`AuthSessionBootstrapCoordinationDependencies.swift` carries only a provider-
neutral identity/expiry snapshot and narrow state, transition, account-work,
session-operation, publication, purchase-readiness, public-author refresh, and
diagnostic closures. Neither extracted owner imports Supabase, resolves a
singleton, emits logs directly, or knows the SDK `User` type.

The coordinator waits for active sign-out, reuses an already-published usable
session only behind an exact-session account-work lease, and drains admitted
account work before resolving another SDK session. Ownerless callers may join
only a task whose complete transition token remains the exact active anonymous-
bootstrap owner; a different or replacement transition owner is rejected.
Cancellation before admission or during sign-out waiting stops before lease,
transition, or SDK-session work. Loaded or created identities must be adopted
before publication and must still match the manager-published nonexpired SDK
session after purchase readiness. Only the injected stable missing-session
classifier reaches anonymous creation, so network or expiry failures preserve
the existing identity. Task UUID cleanup prevents a cancelled predecessor from
clearing a replacement handle.

`SupabaseManager.initializeGhostSession(ownedBy:) -> User?` remains unchanged as
the live adapter. The facade still owns the SDK session reads, anonymous
sign-in, `AuthError` classification, observable publication, public-author
scheduling, purchase effects, and privacy-safe log messages, then maps the
coordinator's exact identity back to the current SDK user. Sign-out now cancels
and awaits the coordinator-owned task through the same existing flow. The split
reduces the manager from 3,998 to 3,994 lines and raises the guarded Auth
inventory from 26 to 28 production files. The architecture guard freezes all
four explicit Auth task owners and rejects the former manager task fields and
private bootstrap performer.

`AuthSessionBootstrapCoordinatorTests` adds eighteen deterministic cases
covering test/deletion and preflight-cancellation gates, cancellation during
sign-out waiting, sign-out and quiescence ordering, current-session reuse, stale
account-work rejection, exact-token ownerless sharing, replaced-transition and
different-owner isolation, true-missing anonymous creation and creation failure,
network-failure identity preservation, cancellation and transition drift around
session load, compare-before-clear task replacement, resolved-session
publication order, and session replacement during purchase readiness. The
focused production and XCTest sources pass iOS SDK semantic typechecking, the
same eighteen cases pass in a native deterministic harness, and the complete
13-case Core Network architecture suite passes in its native source harness.
Swift parsing, strict affected-source SwiftLint, byte-stable XcodeGen,
project/resource and generated-source membership, event-routing and adversarial
fixtures, transport-security and fixtures, the complete portable iOS CI-tooling
suite, changed-Markdown formatting, all 26 documentation and local-link
contracts, and whitespace validation pass. The required generic Simulator
`build-for-testing` was attempted through `make ios-local-build`, but its safety
wrapper refused before Xcode because this sandbox cannot inspect active
`xcodebuild` processes; no new full-target build or Simulator runtime result is
claimed. No endpoint, request or response payload, successful Auth or purchase
flow, persisted format, Keychain key, SwiftData schema, feature flag, UI,
deployment, or release contract changed. The follow-up review intentionally
narrows bootstrap admission for cancelled callers and stale transition tokens;
no hosted operation was performed.

### SupabaseManager Auth-session Recovery Coordination

The fourteenth `SupabaseManager` hygiene slice moves authenticated-request
session refresh, anonymous replacement recovery, and terminal local cleanup into
`Core/Network/Auth/Coordinators/AuthSessionRecoveryCoordinator.swift`.
`AuthSessionRecoveryCoordinationDependencies.swift` carries provider-neutral
session capabilities and narrow state, transition, operation, and diagnostic
closures. Neither extracted owner imports a provider SDK, resolves a singleton,
emits a log directly, or creates a task.

Ordinary refresh owns one recovery transition; a deletion or OAuth caller that
already owns a transition uses the same coordinator without opening or finishing
a nested owner. Both paths capture the exact expected session before draining
account work and reject cancellation, ownership loss, or session replacement
after SDK suspension. Anonymous recovery preserves pending purchase handoffs and
requires purchase identity, entitlement, captured-generation, and final SDK
readback agreement before request replay. Terminal cleanup checks cancellation
before mutation, but once local SDK sign-out begins it completes observable,
Keychain-marker, analytics, and purchase cleanup even if the SDK call fails or
cancellation arrives.

At this extraction stage, `SupabaseManager` preserved the existing public
refresh, reset, and clear signatures and remained the sole live Supabase,
RevenueCat, entitlement, persistence, analytics, and logging composition root.
The then-named `SupabaseAuthSessionRecoveryDiagnostics.swift` retained the
established privacy-safe log copy outside the provider-neutral coordinator; the
later recovery-live-boundary slice below records its subsequent relocation. The
split reduces the manager from 3,994 to 3,961 lines and raises the guarded Auth
inventory from 28 to 30 production files; all extracted production files remain
below 600 lines.

`AuthSessionRecoveryCoordinatorTests` adds fifteen deterministic cases for
ordinary and transition-owned refresh, cancelled admission and in-flight work,
expected-session drift, anonymous purchase/entitlement/final-readback admission,
pending-handoff preservation, local SDK sign-out failure, cancellation after SDK
sign-out begins, and caller-owned transition lifetime. The Core Network
architecture suite freezes the new owners, five facade delegations,
live-diagnostic boundary, retired aggregate helpers, provider/singleton/task
exclusions, and exact 30-file Auth inventory. The 15 focused cases and 13
architecture cases pass in native Swift 6 harnesses, and strict affected-source
SwiftLint reports zero violations. Swift parsing, byte-stable XcodeGen,
generated-project/resource and source membership, event-routing and
transport-security production/adversarial checks, the complete portable iOS
CI-tooling suite, all 56 focused cross-language client and documentation
contracts, recursive Function/script formatting, changed-Markdown formatting,
and whitespace validation pass. The required generic Simulator
`build-for-testing` was attempted through `make ios-local-build`, but its safety
wrapper refused before Xcode because this sandbox cannot inspect active
`xcodebuild` processes. No new full-target build or Simulator runtime result is
claimed.

The documentation follow-up synchronizes the iOS/Core ownership maps, API and
revenue/identity contracts, app lifecycle, concurrency and system architecture,
Core-manager responsibilities, and both test inventories. It distinguishes the
refresh and anonymous-replacement cancellation fences from terminal cleanup's
commit boundary: cancellation stops terminal clear before mutation, but once
local SDK sign-out starts the coordinator still invokes observable-state,
secure-marker, analytics, and purchase-identity cleanup. It does not claim that
a failed SDK sign-out discarded the provider's cached session.

No endpoint, request/response JSON, error copy, retry count, successful Auth or
purchase flow, durable format, Keychain key, SwiftData schema, feature flag, UI,
backend, deployment, or release contract changes in this slice. Admission is
intentionally narrower only for cancelled callers and stale transition/session
continuations. No hosted operation was performed.

### SupabaseManager Public-author Identity Refresh Coordination

The fifteenth `SupabaseManager` hygiene slice moves direct and restored-session
public-author identity refresh sequencing into the provider-neutral
`Core/Network/Auth/Coordinators/PublicAuthorIdentityRefreshCoordinator.swift`.
`PublicAuthorIdentityRefreshCoordinationDependencies.swift` carries only narrow
session, account-work, retained-Ghost-completion, remote-refresh, event, and
diagnostic closures. Neither extracted Auth owner imports a provider SDK,
resolves a singleton, logs directly, or constructs endpoint transport.

The restored-session route owns one target-account-keyed task with a unique task
ID. A replacement cancels its predecessor, and compare-before-clear cleanup
prevents that predecessor from erasing the newer handle. The route retains the
established outer account-work lease, completes queued Ghost handoffs, and then
uses the existing nested ownerless refresh lease. Cancellation and lease state
are revalidated after every suspension; the completed-account marker and
identity-change event are admitted only while the manager-published user still
matches the target. The direct OAuth route retains its transition-owned exact-
session preflight and postflight without opening another account-work lease.

`SupabaseManager` remains the live effect assembler and public-signature owner.
It maps SDK users into provider-neutral sessions and injects the existing Ghost
remote service, transition/lease checks, and current-user projection.
`SupabasePublicAuthorIdentityRefreshLiveEffects.swift` is the explicit owner of
the application event and privacy-safe diagnostic copy outside the Auth
foundation. The split reduces `SupabaseManager.swift` from 3,961 to 3,916 lines,
raises the guarded Auth inventory from 30 to 32 production files, and raises the
explicit Auth task-owner count from four to five. Every extracted production
file remains below the 600-line review ceiling.

`PublicAuthorIdentityRefreshCoordinatorTests` owns eighteen deterministic cases
for scheduling gates and stale-target rejection; Ghost/lease/refresh/publication
order; same-target coalescing; replacement cleanup; cancellation before direct
or scheduled admission and across remote suspension; cancellation-diagnostic
suppression; stale outer and nested leases; published-user drift; remote
failure; transition-owned preflight and postflight session fencing; ownerless
refresh; and completed-marker reset. The initial independent concurrency review
prompted the explicit stale-transition preflight regression. A follow-up review
then closed stale-target replacement and direct/scheduled cancellation gaps. The
Core Network architecture suite freezes the two new Auth owners, sole
live-effects owner, aggregate-manager exclusions, single keyed task, and
eighteen-test inventory. The cross-language Ghost client contract now reads the
coordinator and dependency package directly and freezes
retained-handoff-before-refresh ordering plus the live remote-service injection.

Candidate verification passed byte-stable XcodeGen; generated-project/resource
and source-membership validation; event-routing production and adversarial
guards; Swift parsing; strict affected-source SwiftLint with zero violations;
all 18 focused coordinator tests; all 13 Core Network architecture tests; the
eight-case Ghost client contract; all 1,944 Edge Function tests with one
intentional ignore; the 26-case documentation contract; complete Function and
script formatting; changed-Markdown formatting; portable iOS CI tooling; and
whitespace validation. The required generic Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the safety wrapper refused before
Xcode because this sandbox cannot inspect active `xcodebuild` processes. No new
full-target build or Simulator runtime result is claimed.

This slice changes no JSON field, endpoint action, error mapping, Auth
transition value, account-work semantics, durable journal, RevenueCat identity,
entitlement, SwiftData schema, feature flag, navigation, copy, backend behavior,
deployment, or release control. No hosted operation was performed.

### SupabaseManager Apple Credential-Revocation Coordination

The sixteenth `SupabaseManager` hygiene slice moves Apple credential-revocation
notification coordination into
`Core/Network/Auth/Coordinators/AppleCredentialRevocationCoordinator.swift`. Its
dependency package carries only provider-neutral current-identity, transition,
lookup, terminal-clear, and diagnostic closures. The coordinator owns one
retained task, notification coalescing, Auth-transition deferral, a monotonic
Auth-context generation, exact session/provider-subject postflight, and
compare-before-clear cleanup.

`AppleCredentialRevocationLiveProvider.swift` is the sole AuthenticationServices
notification-token and credential-state lookup owner.
`AppleCredentialRevocationLiveDiagnostics.swift` maps value-only outcomes to the
existing privacy-safe log copy. `SupabaseManager` retains public signatures and
acts only as the composition root: it maps the current SDK user to the exact
provider-neutral identity, invalidates revocation work before Auth transitions
and SDK lifecycle publication, resumes deferred work after stable publication,
and injects terminal Auth recovery. Signed-out and terminal local-clear paths
cancel any retained attempt.

This closes two predecessor races without changing fail-closed policy. A
same-user SDK refresh now invalidates an older lookup by generation, so its late
unsafe result cannot clear the refreshed session. A notification received during
an in-flight lookup retains exactly one follow-up instead of running overlapping
unowned callbacks. Identity replacement, transition overlap, cancellation, and
task replacement all reject stale postflight before local clear.

The split reduces `SupabaseManager.swift` from 3,916 to 3,909 lines, raises the
guarded Auth inventory from 32 to 34 production files, and raises explicit Auth
task ownership from five to six. `AppleRevocationCoordinatorTests` adds thirteen
deterministic cases for admission, deferral, every provider outcome, generation
and identity drift, overlap, cancellation, coordinator release during a
suspended lookup, and exactly-once clear; `AppleRevocationLiveProviderTests`
owns the SDK-state mapping, exact observer lifecycle, and off-main delivery into
the main-actor handler. The live provider holds the non-`Sendable` Foundation
token inside a self-cleaning registration, so provider teardown does not cross
the main-actor boundary from a nonisolated deinitializer or require an unsafe
`Sendable` conformance. Its injected lookup closure captures only that provider,
while the retained task keeps its coordinator weak across the SDK suspension; a
stalled callback therefore cannot retain the manager through the coordinator.
The Core Network architecture and cross-language Apple deletion contracts freeze
the new owners and reject the retired manager observer, pending flag, callback,
and state-policy helper.

Candidate verification passed byte-stable XcodeGen; generated-project/resource
and source-membership validation; event-routing production and adversarial
guards; Swift parsing; strict affected-source SwiftLint with zero violations;
Swift 6 complete-concurrency production and focused-test typechecking with
warnings as errors; all 17 focused coordinator/live-provider XCTest cases in a
host-compatible harness; native generation/overlap/transition and observer-
lifecycle runtime audits; all 13 Core Network architecture tests; the six-case
account-deletion source contract; the 26-case documentation contract; complete
Function and script formatting; changed-Markdown formatting; and whitespace
validation. The required generic Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the safety wrapper refused before Xcode
because this sandbox cannot inspect active `xcodebuild` processes. No new
full-target build or Simulator XCTest result is claimed.

No endpoint, request/response JSON, server revocation receipt, Auth transition
value, persistent state, Keychain key, RevenueCat behavior, SwiftData schema,
feature flag, navigation, visible copy, backend behavior, deployment, or release
control changes in this slice. The client continues to preserve only an
authoritative `.authorized` credential and otherwise clears the exact
still-matching local Apple session; it never reports server provider completion.

### SupabaseManager Auth Integration Audit — Lifecycle Replay and OAuth Cancellation

The post-extraction Auth integration audit closes two cross-coordinator races
without returning orchestration to `SupabaseManager`. An SDK Auth event received
while a transition owns the session is no longer discarded permanently.
`AuthLifecycleReplayCoordinator` records only a genuinely deferred event and
owns one replacement-safe main-actor task that snapshots the current SDK
session, expiry, and Auth generation after transition finish. A newer SDK event
cancels synthetic replay, while a newly admitted transition cancels the running
attempt and carries the obligation to its next stable finish boundary. UUID
compare-before-clear cleanup prevents a stale attempt from erasing replacement
task state. The lifecycle coordinator also revalidates the exact nil SDK and
published session, generation, cancellation state, and absence of a transition
after suspended purchase sign-out before it clears linked-user, public-author,
Apple-revocation, or Ghost-merge state.

OAuth completion now treats cancellation as a first-class state at every
suspension boundary. `OAuthSignInWorkflow` reports an explicit `installed`,
`failed`, or `cancelled` replacement disposition, checks cancellation before and
after SDK installation, and never retries cancelled Apple credential
registration. `OAuthSignInCoordinator` repeats the fence after replacement,
credential registration, metadata persistence, authenticated publication,
telemetry, entitlement, exact-session readback, and public-author refresh.
Pre-install cancellation may restore only the exact still-valid source session;
post-install cancellation fails closed. The recovery coordinator's narrow
`completeMutatedOAuthSession` entry policy then permits that already-mutated
transition to complete terminal local cleanup despite caller cancellation. The
ordinary recovery and pre-mutation paths retain active-caller admission, and
pending purchase-handoff evidence remains fail-closed.

At this audit checkpoint, the guarded Auth inventory contained 35 production
files with seven explicit task owners. `SupabaseManager.swift` was 4,067 lines
and remained the SDK/provider/live effect composition facade. Lifecycle coverage
grows from 13 to 15 deterministic cases; the new replay suite owns five
state/task cases; recovery grows from 15 to 16 cases; six OAuth suspension-gate
cases cover replacement, Apple registration, metadata, telemetry, entitlement,
and public-author refresh. The architecture guard freezes the new owner, task
wiring, current-session postflight, cancellation disposition, cleanup entry
policy, focused test names, and then-current 35-file inventory.

A second integration review found that prebuilt lifecycle dependencies with
strong facade captures defeated the replay scheduler's outer weak capture. The
live assembly now captures `SupabaseManager` weakly for every lifecycle effect
and returns a no-op or conservative unavailable value after facade teardown. The
architecture suite rejects a strong capture and pins the weak purchase-principal
and linked-user cleanup bindings. The deferred signed-out regression now enters
through `AuthLifecycleReplayCoordinator` and asserts the complete cleanup
sequence instead of calling the lifecycle handler directly.

Verification passed byte-stable XcodeGen; generated-project/resource and source-
membership guards; event-routing production and adversarial guards; the complete
portable iOS CI-tooling suite; recursive Auth and focused architecture parsing;
strict affected-source SwiftLint with zero violations; focused iOS Simulator SDK
frontend typechecking for lifecycle replay, lifecycle projection, recovery,
OAuth workflow/completion/cancellation, and the Swift Testing architecture
source; all 56 focused cross-language Auth/deletion/purchase/documentation
tests; the complete 1,944-test Edge Function suite with zero failures and one
intentional ignore; recursive Function/script formatting across 852 files;
changed-Markdown formatting; and whitespace validation. The canonical generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the wrapper refused before invoking Xcode because this environment cannot verify
whether an `xcodebuild` process is active. No fresh iOS build, Simulator XCTest
execution, or complete `merianTests` runtime result is claimed.

The follow-up review additionally passed focused lifecycle/replay Swift
typechecking, Swift Testing architecture-source typechecking, strict affected-
source SwiftLint, byte-stable XcodeGen, project/source-membership and routing
guards, the complete portable iOS CI-tooling suite, the focused eight-test
Ghost/OAuth contract set, changed-Markdown formatting, and whitespace
validation. The same local-build wrapper restriction remained, so the follow-up
adds no Simulator runtime claim.

This audit changes no endpoint, request/response JSON, Auth transition value,
provider contract, Keychain format, RevenueCat identity, entitlement contract,
SwiftData schema, feature flag, navigation, visible copy, backend behavior,
deployment, or release control. No hosted operation was performed.

### SupabaseManager OAuth Provider Authorization Coordination

The post-audit OAuth provider slice removes Apple/Google framework presentation,
provider callback handling, nonce/hash utilities, and presentation-context
resolution from `SupabaseManager`. The facade preserves its public
`signInWithGoogle()` and `startAppleSignIn()` signatures and now only assembles
live Supabase session completion, authenticated Apple credential registration,
and rollback effects.

`OAuthProviderSignInCoordinator` owns transition admission, Google provider-
return verification/recovery, Apple callback acceptance, and one retained Apple
completion task with UUID compare-before-clear cleanup and immediate cancel-and-
release teardown. Its injected dependency package contains only provider-neutral
closure boundaries. The existing `OAuthSignInCoordinator` remains the single
owner of session installation, direct same-UUID linking or provider-bound Ghost
fallback, metadata, purchase, entitlement, public-author, and
authenticated-marker completion.

Focused Auth Services now own the live edges:

- `GoogleOAuthAuthorizationLiveProvider` owns Google SDK presentation, result
  mapping, and cancellation checks immediately before SDK entry and after
  provider return.
- `AppleOAuthAuthorizationLiveProvider` owns the exact authorization controller,
  delegate and presentation callback, anchor, nonce, SHA-256 hash, raw
  credential extraction, and mapping of the one-use authorization code into an
  identity-token-free provider-neutral durable-registration value. The OAuth
  credentials remain the sole native identity-token owner, and the facade
  adapter forwards that exact token after session installation. The provider
  rejects an overlapping start and releases only the matching attempt.
- `OAuthPresentationContextResolver` owns the existing
  key-window/root-controller policy, and `OAuthProviderSignInLiveDiagnostics`
  owns privacy-safe provider-stage logging.

The guarded Auth inventory is now 41 production files with eight explicit task
owners, and `SupabaseManager.swift` is 3,862 lines. Fourteen
provider-coordinator, five Google live-provider, and ten Apple live-provider
cases freeze ordering, mapping, cancellation, callback/transition ownership,
controller retention, overlap rejection, mutation-aware rollback, credential
validation, nonce, and hash behavior. The Core Network architecture guard
freezes the new owners, focused test inventory, provider-neutral dependency
exclusions, sole framework Services, exact facade delegation/assembly, and
removal of every retired provider concern from the manager. The cross-language
account-deletion contract now reads the Apple provider, provider coordinator,
facade registration assembly, and shared OAuth completion owners directly.

The follow-up review removed a duplicated Apple identity-token field from the
registration presentation value. Swift architecture and cross-language guards
now reject reintroducing a second token source or forwarding a token other than
the exact OAuth credential used to install the session. It also requires
provider-task cancellation to release its retained handle and UUID before
issuing cancellation.

The final documentation audit names the live Apple authorization provider as the
raw-credential mapper, the provider coordinator as callback/task owner, and
`SupabaseManager` only as the Supabase session and authenticated registration
endpoint effect assembler. The testing matrix likewise assigns provider SDK
presentation, mapping, cancellation, and observer behavior to the focused
provider suites rather than the aggregate manager suite.

Verification passed byte-stable XcodeGen; generated-project/resource and source-
membership guards; event-routing production and adversarial guards; recursive
Swift parsing; strict affected-source SwiftLint with zero violations; warnings-
as-errors Swift 6 complete-concurrency typechecking of the extracted production
owners and all three focused XCTest sources; Swift Testing macro typechecking of
the Core Network architecture source; the complete portable iOS CI-tooling and
Supabase tooling/DTO contract suites; the focused six-case account-deletion and
26-case documentation Deno contracts; recursive Function/script formatting
across 852 files; Supabase skill-link verification; changed-Markdown formatting;
and whitespace validation. The canonical generic Simulator `build-for-testing`
was attempted through `make ios-local-build`, but the wrapper refused before
invoking Xcode because this sandbox cannot verify whether an `xcodebuild`
process is active. Focused typechecking is supplemental evidence, not a full
target compile. No fresh iOS build, Simulator XCTest, or complete `merianTests`
runtime result is claimed.

This slice changes no endpoint, JSON payload, Apple registration semantics,
Supabase Auth transition value, persistent state, Keychain key, RevenueCat or
entitlement behavior, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### SupabaseManager Apple Credential-registration Transport Extraction

This Auth slice moves the Apple revocation-credential Function boundary out of
`SupabaseManager.swift` without moving transition authority. The provider-
neutral `AppleOAuthCredentialRegistrationService` owns the injected operation
and strict `success == true`, `status == "registered"` receipt contract. Its
`+Live` adapter alone imports Supabase and owns the private snake-case request
and response DTOs, lowercased registration UUID, and authenticated
`register-apple-revocation-token` invocation. The manager continues to bracket
that injected suspension with the exact active transition and expected-user
checks, and `OAuthSignInWorkflow` continues to own the bounded same-registration
retry.

The guarded Auth inventory is now 43 production files, and
`SupabaseManager.swift` is 3,844 lines. Three focused service cases freeze exact
value forwarding, acceptance of only the registered receipt, and unchanged
transport-error propagation. The Core Network architecture guard freezes sole
wire ownership, exactly one live invocation per service call, the absence of
adapter-owned retry policy, asynchronous task, facade, or alternate transport,
manager composition and fencing, provider-neutral dependency exclusion,
lowercase UUID serialization, and the focused test inventory. The cross-language
account-deletion guard reads both new owners, repeats those adapter-ownership
assertions, and rejects route or DTO reacquisition by the manager.

The documentation follow-up records that boundary in the Auth and Core Network
READMEs, codebase map, API and Apple deletion contracts, testing strategy,
manager and identity guides, Supabase overview, and affected Function READMEs.
The executable documentation contract now requires the canonical surfaces to
retain the one-invocation-per-call boundary and state that the adapter owns
neither retry policy nor asynchronous task state.

This slice changes no Function route, JSON field, retry count, Apple credential
source, receipt semantics, Auth transition, session-cleanup behavior, persisted
state, Keychain contract, SwiftData schema, feature flag, navigation, visible
copy, backend implementation, deployment, or release control. No hosted
operation was performed.

Verification passed byte-stable XcodeGen; generated-project resource and source-
membership guards; event-routing production and adversarial guards; affected-
source Swift parsing; strict affected-source SwiftLint with zero violations;
warnings-as-errors Swift 6 complete-concurrency typechecking of both production
service owners and the focused XCTest source; Swift Testing macro typechecking
of the Core Network architecture source; the complete portable iOS CI-tooling
and Supabase tooling/DTO contract suites; the focused six-case account-deletion
and 26-case documentation contracts; recursive Function/script formatting across
852 files; Supabase skill-link verification; changed-Markdown formatting; and
whitespace validation. The canonical generic Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the wrapper refused before
invoking Xcode because this sandbox cannot verify whether an `xcodebuild`
process is active. Focused typechecking is supplemental evidence, not a full
target compile. No fresh iOS build, Simulator XCTest, or complete `merianTests`
runtime result is claimed.

### SupabaseManager Fallback Authentication Callback Coordination

This Auth slice moves fallback authentication URL admission, session replacement
sequencing, same-account target validation, purchase-identity and entitlement
ordering, completion, and mutation-aware failure recovery out of
`SupabaseManager.swift`. The provider-neutral
`AuthenticationCallbackCoordinator` and its injected dependency package own the
workflow without creating an asynchronous task. The focused live diagnostics
adapter owns the existing privacy-safe log messages.

The public `handleAuthenticationCallbackURL(_:)` signature and its caller
contract remain unchanged. `SupabaseManager` remains the live composition edge:
the focused OAuth live adapter converts the URL through Supabase Auth, after
which the manager adapts the captured SDK session, publishes observable Auth
state, resolves RevenueCat purchase identity, starts the entitlement session,
writes the authenticated-OAuth Keychain marker, and performs transition-owned
local cleanup. No singleton or provider SDK crosses into the coordinator.

The extracted policy preserves the existing product boundary. A fallback URL may
establish a session when there is no local source session or refresh the exact
existing linked account. It cannot upgrade an anonymous profile or replace a
different linked account. Pending purchase handoffs and concurrent Auth
transitions reject the callback before session installation. The shared OAuth
replacement workflow preserves cancellation classification and reconciliation,
and cleanup occurs when an SDK session mutation was observed or the exact source
session was not restored. A post-preflight cancellation stops before
installation, while a sign-out state observed after installation prevents the
callback from republishing or completing the session.

A post-extraction review closed the remaining cleanup race in both OAuth and
fallback-callback replacement. Immediately after a live SDK install returns, the
facade now records the mutation and adopts that exact SDK identity as the active
transition expectation before any post-install cancellation check. This
expectation is recovery evidence rather than callback acceptance: source/target
policy still runs before publication, while cancelled or rejected work can now
clear the exact installed identity without permitting cleanup of a later,
unrelated account. Focused cancellation, recovery, callback, and architecture
regressions freeze that ordering.

The guarded Auth inventory is now 46 production files, with eight asynchronous
task owners. Every new production owner remains below the 600-line review
ceiling. `SupabaseManager.swift` is 3,860 lines; this extraction deliberately
prioritizes isolating orchestration and live-effect ownership over a net
line-count reduction in the composition facade.

Fifteen deterministic `AuthenticationCallbackCoordinatorTests` cases cover
success ordering, pending-handoff, transition and sign-out overlap, anonymous
and different-account refusal, exact-account refresh, installation failure
before and after SDK mutation, pre-install and suspended-phase cancellation,
mutation-aware cleanup, purchase readiness, and final-session drift. The Core
Network architecture contract freezes the thin facade, live effect assembly,
provider-neutral exclusions, diagnostic copy, test inventory, and exact Auth
owner inventory.

Verification passed byte-stable XcodeGen regeneration; generated-project and
source-membership validation; event-routing production and adversarial guards;
focused Swift parsing; strict affected-source SwiftLint with zero violations;
warnings-as-errors Swift 6 complete-concurrency typechecking of the extracted
production and test owners; an executable 15-case host-compatible coordinator
harness; an executable focused Core Network architecture check; the complete
portable iOS CI-tooling and Supabase tooling/DTO contract suites; recursive
Function/script formatting across 852 files; Supabase skill-link verification;
changed-Markdown formatting; and whitespace validation. The canonical generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the wrapper refused before invoking Xcode because this sandbox cannot verify
whether an `xcodebuild` process is active. Focused typechecking is supplemental
evidence, not a full target compile. No fresh iOS build, Simulator XCTest, or
complete `merianTests` runtime result is claimed for this slice.

This slice changes no endpoint, JSON payload, Auth provider policy, callback
route, SwiftData schema, persistent-state shape, feature flag, navigation,
visible copy, backend implementation, deployment, or release control. No hosted
operation was performed.

### Final Auth Integration Audit

The 2026-09-15 Auth-wide integration audit reviewed all forty-six extracted
production Auth files, the eight coordinator-owned structured tasks, the
manager-owned SDK listener and sign-out task, lifecycle replay, OAuth and
fallback completion, deletion/recovery, public-author refresh, Ghost merge, and
stable/compatibility purchase-continuity handoffs as one system. The independent
read-only trace found no P1 regression and confirmed that transition, session,
Auth-generation, durable-proof, and compare-before-clear ownership remains
centralized and non-overlapping.

The audit and its adversarial follow-up close six narrower completion gaps:

- loaded and newly created bootstrap sessions now repeat cancellation after
  purchase-identity readiness and cannot return an identity from a cancelled
  coordinator task;
- an unsafe Apple credential-state result reaches local recovery only through a
  live exact-identity/no-replacement-transition admission. Rejection retains the
  notification for the next stable Auth context;
- terminal cleanup repeats its expected/current-session fence after account-work
  quiescence, so a replacement session cannot be signed out;
- a purchase-handoff-blocked recovery reports a distinct outcome, retains the
  Apple signal without immediately starting another lookup, and resumes it when
  the centralized aggregate handoff publication becomes false. A clear
  diagnostic is emitted only after cleanup completes;
- an Auth context change that finishes while terminal clear is suspended is
  detected when a deferred result returns, so the stale attempt revalidates
  instead of losing the earlier lifecycle wakeup; and
- a stale Apple provider callback idempotently finishes its superseded token
  without disturbing the replacement transition.

Two new bootstrap cases, the replacement-during-quiescence recovery case, and
four Apple revocation cases make those races deterministic. The focused
inventories are now twenty bootstrap tests, seventeen recovery tests, seventeen
Apple revocation coordinator tests, and fourteen provider-sign-in coordinator
tests. `CoreNetworkIntegrationArchitectureTests` freezes both post-readiness
cancellation fences, typed terminal-clear outcomes, the live exact-identity
adapter, post-quiescence session fencing, stable-context replay, aggregate
handoff-fence wakeup, deferred-clear context-change replay, direct-setter
centralization, and stale-callback token retirement. The Auth package remains at
forty-six production files, every extracted owner remains below 600 lines, and
`SupabaseManager.swift` is 3,878 lines.

The synchronized documentation now carries that terminal-clear contract through
the Auth and Core Network ownership guides, app lifecycle, system overview, API
contracts, Apple account-deletion guidance, revenue and identity guidance,
logging operations, testing strategy, codebase map, documentation index, and
changelog. The executable documentation contract asserts the post-quiescence
session fence, typed completion/deferral result, aggregate purchase-handoff
wakeup, lost-wakeup replay, and completion-only clearing diagnostic so those
cross-document claims cannot silently drift.

Verification for the adversarial follow-up passed direct Swift parsing;
warnings-as-errors Swift 6 complete-concurrency typechecking of the focused
production owners, test sources, and live assembly shape; an executable 68-case
host-compatible bootstrap/recovery/revocation/provider matrix; and all thirteen
executable Core Network integration architecture contracts. The 26-case
documentation contract, recursive Function/script formatting across 852 files,
format checks for all 39 changed Markdown files, production and adversarial
event-routing guards, source-membership guard, versioning and Xcode release-
workflow invariants, Supabase skill-link verification, and whitespace validation
also pass. `make xcodegen`, generated-project/resource validation, the remaining
portable iOS tooling scripts, the canonical generic Simulator build, and strict
affected-source SwiftLint are blocked before meaningful execution because the
local Xcode license is not accepted; SwiftLint consequently cannot load
SourceKitten. Focused typechecking and the host-compatible runner are
supplemental evidence, not a fresh app-target build or Simulator XCTest result.
Neither a complete `merianTests` runtime result nor Simulator execution is
claimed for this audit.

This audit changes no endpoint, JSON payload, SDK Auth transition value,
provider contract, Keychain or purchase-proof format, RevenueCat identity,
entitlement contract, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### SupabaseManager Purchase-continuity Source Handoff Extraction

This Auth slice moves the remaining source-side purchase-continuity journal,
preparation, exact-source abandonment, and failed-sign-out restoration logic out
of `SupabaseManager.swift`. `PurchaseIdentitySourceHandoffCoordinator` owns the
aggregate fail-closed projection and exact-session orchestration through a
narrow dependency package. `PurchaseIdentityHandoffAuthJournal` is the sole Auth
adapter over Core Security's store and preserves the established distinction:
load/persist store failures become Auth-transition errors, while verified clear
failures retain their underlying diagnostic.

Core Security's `PurchaseHandoffPreparationCoordinator` owns proof construction
and durability order. Protocol-3 preparation writes `preparing` evidence before
remote work and the server-authorized `prepared` evidence before honoring
post-response cancellation. Compatibility preparation maps and persists the
returned proof before its cancellation checkpoint. `SupabaseManager` remains the
live composition root and the sole direct publisher into RevenueCat's
purchase-handoff mutation fence; it no longer owns journal codecs, source-side
phase sequencing, or proof construction.

The guarded Auth inventory is now 49 production files and
`SupabaseManager.swift` is 3,692 lines. Fourteen source-coordinator cases, three
Auth-journal cases, and five preparation-coordinator cases freeze fail closure,
session drift, exact-source retirement, unowned account-work lifetime,
pre-dispatch and pre-removal invalidation, stale-cancel proof retention,
restoration order, exact error adaptation, durability checkpoints, and
stable/compatibility cancellation behavior. The Core Network and Purchase
Principal architecture suites plus the cross-language purchase-principal
contract freeze the new owner inventory, dependency exclusions, manager
delegation, retired helper absence, and unchanged route linkage.

Verification passed byte-stable XcodeGen regeneration; generated-project and
source-membership validation; Swift parsing and strict affected-source
SwiftLint; warnings-as-errors complete-concurrency typechecking; executable
focused source-handoff, journal, preparation, Core Network architecture, and
Purchase Principal architecture tests; and the 16-case cross-language
purchase-principal contract. The canonical Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the wrapper refused before Xcode
because this sandbox cannot inspect active processes. No fresh app-target build,
Simulator XCTest, or complete `merianTests` runtime result is claimed.

This slice changes no endpoint, JSON field, request action, server behavior,
local journal format, Keychain key or accessibility, RevenueCat behavior,
entitlement order, Auth transition contract, SwiftData schema, feature flag,
navigation, visible copy, deployment, or release control. No hosted operation
was performed.

### Auth Post-extraction Integration Audit

The closure audit reviewed the complete 49-file Auth package together with its
Core Security purchase-proof owners, `SupabaseManager` live composition, and
both purchase-continuity Edge contracts. The package remains within its hygiene
guard: 6,684 production lines total and no production file above 520 lines.
Stable and compatibility payloads, exact-session and account-work fences,
write-ahead proof durability, fail-closed journal projection, same-context
single-flight behavior, and proof-removal-last ordering remain aligned across
iOS and the server parsers. Independent concurrency/security and cross-surface
contract reviews found no P1 or P2 implementation defect.

One P3 cancellation inconsistency was corrected. Compatibility source
preparation now checks cancellation immediately after its final suspended SDK
session read, so a cancelled transition cannot return success or publish the
preparation-success diagnostic. A deterministic suspension test cancels during
that exact read and freezes the no-completion behavior. The source-coordinator
inventory is therefore fifteen cases; the canonical Auth, Core Network, Purchase
Identity, codebase map, API, architecture, Keychain, revenue, and testing
ownership documents now agree, and the executable documentation contract
requires both that inventory and the final-read regression. The preceding
extraction record deliberately retains its fourteen-case executed baseline; this
audit adds the fifteenth case without claiming fresh Simulator execution.

Verification passed byte-stable XcodeGen regeneration; generated-project and
source-membership validation; Swift parsing and focused production/Swift Testing
typechecking; strict affected-source SwiftLint with zero violations;
event-routing validation and adversarial tests; the full portable iOS CI-tooling
suite; the 26-case documentation contract; the 16-case purchase-principal
contract; all 265 standard Supabase tooling tests; both isolated DTO suites with
19 cases; both shared wire-contract suites with 20 cases; recursive formatting
checks across 852 Function/script files; Markdown format validation; and
whitespace validation. The canonical generic Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the wrapper refused before
invoking Xcode because this sandbox cannot inspect whether `xcodebuild` is
active. No fresh app-target build, Simulator XCTest, or complete `merianTests`
runtime result is claimed for this audit.

The audit changes no endpoint, JSON field, action, persisted proof shape,
Keychain key or accessibility, RevenueCat identity behavior, entitlement order,
Auth transition contract, SwiftData schema, feature flag, navigation, visible
copy, deployment, or release control. No hosted operation was performed.

### SupabaseManager Auth Runtime State Extraction

This slice moves the remaining process-local Auth transition bookkeeping out of
`SupabaseManager.swift` and into the 181-line, main-actor observable
`AuthRuntimeState`. The new owner composes the existing value-state machines and
owns the active transition, Auth-session generation, transition analytics
generations, exact-session work leases and drain waiters, and local sign-out
state. It acquires no provider or Supabase SDK, singleton, store, endpoint,
logger, or asynchronous task. `SupabaseManager` remains the live Auth facade: it
retains the SDK listener and facade sign-out task, supplies live effects, and
delegates mutable runtime bookkeeping through unchanged external entry points.

Listener ordering remains explicit and guarded. Each SDK event advances the
runtime generation, notifies Apple credential-revocation coordination that the
Auth context changed, and only then lets the transition state observe the event.
This preserves invalidation timing while allowing the transition owner to adopt
the exact event generation. Transition finish still removes and returns its
analytics generation before the facade reopens inference writes and resolves the
account projection. Account-work drains still resume only after every exact
lease is released.

The guarded Auth inventory is now 50 production files and 6,865 lines, with no
production owner above 520 lines; `SupabaseManager.swift` is 3,666 lines. The
six-case `AuthRuntimeStateTests` suite freezes observable transition
invalidation, exclusive transition and analytics completion, expected and
unexpected event generations, dual-projection exact-session lease admission,
multi-lease drain completion, and sign-out invalidation. The Core Network
architecture suite freezes the new owner, retired facade storage, dependency
exclusions, exact 50-file inventory, 600-line ceiling, focused-test inventory,
and live-listener order.

Verification passed byte-stable XcodeGen regeneration; generated-project,
resource, and source-membership validation; Swift parsing; strict affected-file
SwiftLint with zero violations; Swift 6 warnings-as-errors complete-concurrency
typechecking of the focused production owner and XCTest suite; all thirteen
executable Core Network architecture tests; all six executable Auth runtime
state tests; and the complete portable iOS CI-tooling suite. The 26-case
documentation contract, formatting checks for all changed Markdown,
event-routing guard, and whitespace validation also pass. The canonical generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the wrapper refused before invoking Xcode because this sandbox cannot inspect
whether `xcodebuild` is active. No fresh app-target build, Simulator XCTest, or
complete `merianTests` runtime result is claimed for this slice.

This extraction changes no endpoint, JSON field, request action, SDK Auth
transition value, observable public signature, persisted shape, Keychain key or
accessibility, RevenueCat identity behavior, entitlement order, SwiftData
schema, feature flag, navigation, visible copy, backend behavior, deployment, or
release control. No hosted operation was performed.

### SupabaseManager OAuth SDK Session Boundary Extraction

This slice moves the remaining OAuth-specific Supabase Auth adaptation out of
`SupabaseManager.swift` and into the focused, initializer-injected
`OAuthSessionService` plus its `+Live` adapter. The service maps Apple and
Google provider-neutral credentials to OIDC credentials, projects SDK sessions
back to the provider-neutral identity, and constructs the established
`full_name` / `name`, `given_name`, `family_name`, `avatar_url` / `picture`
metadata aliases. The live adapter alone performs the OAuth session
read/current-session snapshot, identity link, ID-token or callback-URL
installation, and user-metadata update calls.

Transition ownership does not move. `SupabaseManager` still performs exact-
session admission before and after suspended work, replacement reconciliation,
current-user/authenticated publication, provider-specific privacy-safe
diagnostics, and mutation-aware cleanup. `OAuthSignInCoordinator` and
`OAuthSignInWorkflow` retain provider-neutral completion order, cancellation,
and installed/failed/cancelled disposition policy. The new service creates no
task, resolves no singleton, owns no logger, and introduces no broad protocol.

The guarded Auth inventory is now 52 production files and 7,020 lines, with no
production owner above 520 lines; `SupabaseManager.swift` falls from 3,666 to
3,654 lines after the integration-audit safety fix. Nine deterministic
`OAuthSessionServiceTests` cases freeze SDK session read/snapshot forwarding,
Apple and Google credential mapping, callback-URL forwarding and error
propagation, identity projection, canonical metadata aliases, empty-update
suppression, and error propagation. The Core Network architecture guard freezes
both service owners, retired facade helpers, exact 52-file inventory, and
focused-test inventory. Its whole-Network scan requires OIDC and
`UserAttributes` construction to remain exclusive to the service core and direct
Supabase Auth link, ID-token install, callback-URL install, and metadata-update
calls to remain exclusive to the `+Live` adapter. The Ghost merge cross-surface
contract now requires manager delegation for both direct identity linking and
replacement-session installation, requires the live adapter to own both SDK
operations, and rejects either direct call or the retired credential helper
returning to the facade. A second review found no production defect; it closed
these two executable-contract gaps before handoff.

The subsequent Auth/SupabaseManager integration audit found and fixed two
cross-slice lifecycle defects. Facade teardown now explicitly cancels the
extracted purchase-handoff and purchase-identity resolution tasks, preserving
the pre-extraction shutdown contract. OAuth replacement now forwards a mutation
observer to the actual live SDK-install boundary and raises it before the
workflow's post-install cancellation check; recovery can no longer misclassify
an installed session when cancellation prevents the helper from returning. A
follow-up review closed the remaining exact-cleanup gap by recording the
installed SDK identity as the owning transition's expectation at that same
boundary. The deterministic cancellation harness models that exact overlap, and
the Core Network architecture suite freezes observer/adoption order, both
replacement branches, the complete facade teardown list, and the reviewed
generic Supabase Auth calls that intentionally remain in `SupabaseManager`.

The documentation follow-up reconciles the Core overview with the final
3,654-line facade, distinguishes recovery-only exact-target transition adoption
from successful account publication, and carries that invariant through the iOS
ownership map, product identity guide, Apple authorization contract, Ghost merge
Function README, and canonical API contract. The cross-language Ghost contract
also follows the renamed `replaceAndAdoptSession` boundary and exact-target
cancellation regression. No endpoint, payload, persistence, or hosted behavior
changes in this documentation pass.

Verification passed byte-stable XcodeGen regeneration; generated-project,
resource, and source-membership validation; Swift parsing; strict affected-file
SwiftLint with zero violations; warnings-as-errors Swift 6 focused production
and XCTest typechecking; all thirteen executable Core Network architecture
tests; the Ghost merge and account-deletion client-source contracts; the
canonical Supabase test task with 1,944 passes and one intentional ignore; the
portable iOS CI-tooling suite; recursive Supabase Function/script formatting;
Markdown formatting; and whitespace validation. The canonical generic Simulator
`build-for-testing` was attempted through `make ios-local-build`, but the
wrapper refused before invoking Xcode because this sandbox cannot inspect
whether `xcodebuild` is active. No fresh app-target build, Simulator XCTest, or
complete `merianTests` runtime result is claimed for this slice.

The integration-audit follow-up again passed byte-stable XcodeGen, generated-
project/source-membership and event-routing guards, strict affected-source
SwiftLint, Swift parsing, Swift 6 complete-concurrency production and focused
XCTest typechecking, the executable 13-case Core Network architecture suite, a
host-executable mutation/cancellation overlap, the Ghost merge, account-
deletion, and purchase-principal client contracts, the complete portable iOS CI
tooling suite, the canonical Supabase tooling task, recursive Function/script
formatting, Markdown formatting, and whitespace validation. The canonical
generic Simulator build was attempted in both shared and isolated wrapper modes;
both refused before invoking Xcode because the host cannot inspect active
`xcodebuild` processes. No fresh app-target build or Simulator XCTest result is
claimed.

This extraction changes no endpoint, JSON field, request action, SDK Auth
transition rule, observable public signature, persisted shape, Keychain key or
accessibility, RevenueCat identity behavior, entitlement order, SwiftData
schema, feature flag, navigation, visible copy, backend behavior, deployment, or
release control. No hosted operation was performed.

### SupabaseManager Auth Session Lifecycle Live Boundary Extraction

This slice moves SDK Auth stream/task ownership, SDK-state mapping, exact
current-session replay validation, lifecycle diagnostics, and retained
historical-synchronization work out of `SupabaseManager.swift`. The focused
`AuthSessionLifecycleLiveProvider` owns one replaceable listener task, composes
the existing provider-neutral replay coordinator, and calls the existing
session-lifecycle coordinator through weak facade dependencies. Replacing the
listener cancels its task and clears the replaced listener's deferred replay
obligation; a post-coordinator cancellation fence rejects the replaced
operation's trailing credential effect. Its `+Live` adapter alone subscribes to
`authStateChanges` and reads the current lifecycle session.
`AuthHistoricalSessionSyncLiveService` retains every admitted history task and
cancels outstanding work on teardown; its `+Live` adapter alone owns the model-
context, timestamp, preferred-name, and historical-scan effects.
`AuthSessionLifecycleLiveDiagnostics` owns privacy-safe log adaptation.

Listener semantics remain exact. Each SDK event advances the Auth generation,
invalidates Apple credential-revocation context, updates transition state, reads
the deletion barrier, records deferred-replay state, runs provider-neutral
lifecycle projection, and only then resumes deferred credential revalidation.
Synthetic replay captures one SDK snapshot and rejects cancellation, a new Auth
generation, an active transition, expiry drift, or identity drift both before
projection and before revocation resume. Historical synchronization stamps its
throttle before preferred-name work, repeats the exact published-session fence
before scan history, and cannot survive facade teardown.

The guarded Auth inventory is now 57 production files and 7,360 lines, with no
production owner above 520 lines; `SupabaseManager.swift` falls from 3,654 to
3,545 lines. Seven deterministic lifecycle-provider cases freeze SDK-state
projection, listener prelude order, deferred current-state replay, stale
snapshot rejection, replacement-listener cleanup, canceled trailing-effect
rejection, and suspended-listener teardown. Three deterministic history-service
cases freeze stamp/preference/scan order, post-preference session drift, and
suspended-work teardown. The Core Network architecture suite freezes the exact
inventory, sole live SDK stream owner, weak facade captures, retained task
owners, listener order and replacement cleanup, cancellation fencing,
diagnostics ownership, focused tests, facade teardown, and absence of the
retired listener/replay fields and helpers.

The review follow-up closed two replacement edges in that live owner. Starting a
replacement listener now clears a deferred replay obligation created by its
predecessor, and a listener canceled while lifecycle coordination is suspended
cannot resume deferred Apple credential work after it returns. Dedicated
regressions suspend and replace the listener to prove both boundaries.

The documentation follow-up carries those replacement and trailing-effect
boundaries through the Core, Core Network, Core Security, app-lifecycle,
core-manager, Revenue and Identity, Onboarding, codebase-map, system-overview,
and purchase-principal ownership summaries. The focused Auth README, testing
strategy, and event-routing guide retain the detailed owner and regression
matrix.

The review rerun used the installed Swift 6.4 compiler while retained Supabase
modules were still built with Swift 6.3.3. The changed production and XCTest
sources therefore also passed strict complete-concurrency typechecking against a
temporary minimal `User` boundary; that supplemental check does not replace the
earlier real-SDK typecheck or a fresh Xcode build.

Verification passed XcodeGen regeneration, generated-project/resource and
source-membership validation, Swift parsing, strict affected-source SwiftLint
with zero violations, focused iOS Simulator SDK production and XCTest
typechecking, standalone Swift Testing architecture-suite typechecking, the
exact Auth owner inventory comparison, skill-link validation, and whitespace
validation, plus changed-Markdown formatting and all 26 documentation/local-link
contracts. The canonical generic Simulator `build-for-testing` was attempted
through `make ios-local-build`, but the wrapper refused before invoking Xcode
because this sandbox cannot inspect whether `xcodebuild` is active. No fresh
app-target build, Simulator XCTest, or complete `merianTests` runtime result is
claimed for this slice.

This extraction changes no endpoint, JSON field, request action, SDK Auth
transition or cold-start rule, observable public signature, persistence,
Keychain, RevenueCat or entitlement ordering, SwiftData schema, feature flag,
navigation, visible copy, backend behavior, deployment, or release control. No
hosted operation was performed.

### SupabaseManager Auth Session Bootstrap Live Boundary Extraction

This slice moves bootstrap-only Supabase Auth adaptation out of
`SupabaseManager.swift`. `AuthSessionBootstrapLiveService` projects cached,
loaded, and newly anonymous SDK sessions into the established bootstrap identity
and expiry value and owns the existing exact `AuthError.sessionMissing` plus
compatibility-description classification. Its `+Live` adapter is the sole owner
of bootstrap `session`, `currentSession`, and `signInAnonymously()` calls.
`AuthSessionBootstrapLiveDiagnostics` owns the unchanged privacy-safe log copy.

Transition and product behavior do not move. `AuthSessionBootstrapCoordinator`
continues to own sign-out waiting, account-work quiescence, complete-token keyed
task lifetime, true-missing-only anonymous creation, cancellation, adoption,
publication order, purchase readiness, and final exact-session admission.
`SupabaseManager` composes the SDK user into those injected publication and
readiness effects and preserves `initializeGhostSession(...) -> User?` without
acquiring the SDK operations or error classifier directly.

The guarded Auth inventory is now 60 production files and 7,490 lines, with no
production owner above 520 lines; `SupabaseManager.swift` falls from 3,545 to
3,520 lines. Five deterministic bootstrap-live-service cases freeze cached and
loaded identity/expiry projection, newly anonymous fresh-session projection, SDK
and compatibility missing-session classification, unrelated-error rejection, and
SDK failure forwarding. The Core Network architecture suite freezes the three
focused owners, sole anonymous-sign-in ownership, facade delegation, diagnostics
ownership, exact inventory, and focused tests. A second-pass security and
concurrency review found no remaining actionable issue, and the checked-in
Supabase Swift 2.54.1 resolution and source confirm the session, expiry,
missing-session, and anonymous-sign-in APIs used by the live adapter. No
corrective production edit was required after that review.

Verification passed byte-stable XcodeGen regeneration, generated-project
resource and source-membership validation, Swift parsing, strict affected-source
SwiftLint with zero violations, strict Swift 6 complete-concurrency production
and XCTest typechecking against a temporary minimal Supabase boundary, and the
host-executable thirteen-case Core Network architecture suite. The canonical
generic Simulator `build-for-testing` was attempted through
`make ios-local-build`, but the wrapper refused before invoking Xcode because
this sandbox cannot inspect whether `xcodebuild` is active. No fresh app-target
build, Simulator XCTest, or complete `merianTests` runtime result is claimed for
this slice.

This extraction changes no endpoint, JSON field, request action, SDK Auth
transition or bootstrap rule, observable public signature, persistence,
Keychain, RevenueCat or entitlement order, SwiftData schema, feature flag,
navigation, visible copy, backend behavior, deployment, or release control. No
hosted operation was performed.

### SupabaseManager Auth Session Recovery Live Boundary Extraction

This slice moves the recovery-specific Supabase Auth SDK calls and diagnostics
out of `SupabaseManager.swift`. `AuthSessionRecoveryLiveService` projects
refreshed and loaded SDK sessions into the established provider-neutral recovery
identity while retaining the SDK user only for facade-owned adoption and
publication, public-author refresh, purchase-identity, entitlement, and
generation-fence effects. Its `+Live` adapter is the sole owner of the recovery
`refreshSession()`, session read, and local sign-out calls;
`AuthSessionRecoveryLiveDiagnostics` retains the unchanged privacy-safe log
copy.

Transition and product policy do not move. `AuthSessionRecoveryCoordinator`
continues to own ordinary and transition-owned recovery admission, account-work
quiescence, cancellation and exact-session fences, anonymous replacement,
purchase and entitlement readiness, final readback, and terminal cleanup
completion. `SupabaseManager` only composes adoption, publication, purchase,
entitlement, observable-state, secure-marker, analytics, and purchase identity
effects around the injected live boundary. Existing public and internal recovery
signatures remain unchanged.

The guarded Auth inventory is now 63 production files and 7,633 lines, with no
production owner above 520 lines. `SupabaseManager.swift` is 3,522 lines: the
explicit injected service property and composition add two facade lines while
removing direct recovery SDK and logging ownership. Five deterministic live-
service cases freeze refreshed/loaded identity and SDK-user projection,
exactly-once local sign-out, and refresh, load, and sign-out error forwarding.
The Core Network architecture suite freezes the three focused owners, facade
delegation, sole refresh ownership, the reviewed residual local-sign-out
inventory, exact Auth inventory, and focused tests.

Verification passed strict Swift 6 complete-concurrency production and XCTest
typechecking against a temporary minimal Supabase/XCTest boundary, Swift
parsing, strict affected-source SwiftLint with no cache and zero violations, the
host-executable thirteen-case Core Network architecture suite, byte-stable
XcodeGen regeneration, generated-project resource and source-membership checks,
event routing, changed-Markdown formatting, all 26 documentation contracts,
skill-link validation, and whitespace validation. An independent read-only Auth
and concurrency review of the recovery boundary found no actionable issue. A
subsequent whole-diff audit replaced nullable Apple/Google live dependencies
with explicit zero-argument live initializers plus nonoptional injected
initializers; the architecture guard now prevents nullable dependency injection
from returning. The same audit added the historical-session `+Live` adapter to
the explicit `AppDIContainer.shared` ownership inventory, matching its reviewed
offline-queue context and scan-repository composition role. The canonical
generic Simulator `build-for-testing` was attempted through
`make ios-local-build`, but the wrapper refused before invoking Xcode because
this sandbox cannot inspect whether `xcodebuild` is active. No fresh app-target
build, Simulator XCTest, or complete `merianTests` runtime result is claimed for
this slice.

This extraction changes no endpoint, JSON field, request action, Auth transition
or recovery rule, observable public signature, persistence, Keychain, RevenueCat
or entitlement order, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### SupabaseManager Local Sign-out Coordination and Live Boundary Extraction

This slice moves retained local-sign-out task lifetime and direct Supabase SDK
invalidation out of `SupabaseManager.swift`. The provider-neutral
`AuthLocalSignOutCoordinator` now owns single-flight joining, account-work
quiescence, exact transition checks, observable-state begin/finish, bootstrap-
task cancellation handoff, cancellation before SDK mutation, best-effort SDK
failure handling, external purchase cleanup, diagnostics order, and task-UUID
comparison before clearing retained state. Its dependency package contains only
narrow main-actor closures and values; the facade supplies those closures with
weak captures so a suspended sign-out task cannot form a retain cycle back to
the manager. Explicit cancellation leaves the canceled task registered until its
deferred observable-state cleanup finishes, so an overlapping request cannot
start against half-closed sign-out state.

`AuthLocalSignOutLiveService+Live` is the sole direct owner of
`signOut(scope: .local)`. Ordinary sign-out, account cleanup, and Auth recovery
share that adapter. `AuthSessionRecoveryLiveService+Live` is correspondingly
narrowed to recovery refresh and session reads, while
`AuthLocalSignOutLiveDiagnostics` preserves the established privacy-safe SDK-
failure and completion copy. Public sign-out, account-deletion, recovery,
RevenueCat, transition, request-gate, and observable-state behavior remains
unchanged.

The guarded Auth inventory is now 68 production files and 7,787 lines, with no
production owner above 520 lines; `SupabaseManager.swift` is 3,546 lines. Eight
coordinator tests freeze phase order, overlap sharing, best-effort SDK failure,
failed quiescence, transition loss, cancellation during bootstrap teardown,
canceled-task ownership through deferred cleanup, and post-SDK external cleanup.
The colocated facade suite retains the request-gate timing regression rehomed
from `SupabaseManagerTests`, while two live-service tests freeze exactly-once
delegation and error forwarding. The recovery live-service suite is narrowed to
its three remaining refresh/read projection and failure cases. The integration
architecture guard freezes all five new production owners, the sole direct SDK
call, weak facade capture, retired manager task storage, exact 68-file
inventory, and focused-test rehome.

Verification passed byte-stable XcodeGen regeneration; generated-project and
source-membership validation; event-routing validation and adversarial tests;
Swift parsing; strict repository SwiftLint with zero violations; Swift 6
warnings-as-errors complete-concurrency typechecking of the extracted owners and
all eleven focused host tests; all thirteen host-executable Core Network
architecture tests; changed Markdown formatting; all 26 documentation-contract
tests; and the complete portable iOS CI-tooling suite. The canonical generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the wrapper refused before invoking Xcode because this sandbox cannot inspect
whether `xcodebuild` is active. No fresh app-target build, Simulator XCTest, or
complete `merianTests` runtime result is claimed for this slice.

This extraction changes no endpoint, JSON field, request action, Auth transition
or recovery rule, observable public signature, persistence, Keychain, RevenueCat
or entitlement order, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### SupabaseManager Fallback Callback SDK Boundary Extraction

This follow-up closes the last fallback-callback-specific Supabase Auth seam in
`SupabaseManager`. The existing initializer-injected `OAuthSessionService` now
accepts a callback URL installation operation, and its `+Live` adapter is the
sole owner of `client.auth.session(from:)`. The callback assembly also reads the
SDK snapshot through that service. A second protocol or microservice is not
introduced.

The public `handleAuthenticationCallbackURL(_:)` signature, app-root task
ownership, callback acceptance policy, and exact effect order remain unchanged.
After the awaited live install returns, the facade still invokes the mutation
observer, adapts the SDK session, adopts that exact user as the transition
expectation, and only then returns the coordinator-facing session capabilities.
The callback coordinator continues to own admission, source/target validation,
cancellation, purchase/entitlement sequencing, and mutation-aware cleanup; the
facade continues to own observable publication and live effects.

The guarded Auth inventory remains 68 production files and is now 7,800 lines,
with no production owner above 520 lines; `SupabaseManager.swift` is 3,547
lines. Two new `OAuthSessionServiceTests` cases freeze exact URL forwarding,
single invocation, returned SDK-session identity, and unchanged error
propagation, bringing that suite to nine cases. The integration architecture
guard requires the callback SDK call to have exactly one owner in the OAuth live
adapter, rejects its return to the facade, freezes service delegation and
current-session readback, and preserves install-mutation-adoption order. A
follow-up review broadened the ownership token so a different URL variable name
cannot evade the scan and explicitly rejects direct `client.auth.currentSession`
access in callback assembly.

Verification passed Swift parsing; strict affected-source SwiftLint with zero
violations; warnings-as-errors Swift 6 complete-concurrency typechecking of the
production service/live adapter and all nine focused XCTest cases against a
temporary minimal Supabase/XCTest boundary; all thirteen host-executable Core
Network architecture tests; byte-stable XcodeGen regeneration; validation of the
generated project, source membership, and event routing; the complete portable
iOS CI-tooling suite; changed-Markdown formatting; all 26 documentation contract
tests; and whitespace validation. The canonical generic Simulator
`build-for-testing` was attempted through `make ios-local-build`, but the
wrapper refused before invoking Xcode because this sandbox cannot verify whether
`xcodebuild` is active. No fresh app-target build, Simulator XCTest, or complete
`merianTests` runtime result is claimed for this slice.

This extraction changes no endpoint, JSON field, request action, Auth transition
or recovery rule, observable public signature, persistence, Keychain, RevenueCat
or entitlement order, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### SupabaseManager Purchase Identity Session Live Boundary Extraction

This slice moves ordinary Purchase Identity live-effect acquisition and legacy
profile-to-provider mapping out of `SupabaseManager.swift`. The task-free,
initializer-injected `PurchaseIdentitySessionLiveService` owns Auth-over-public
profile precedence, anonymous/authenticated account-kind mapping, legacy
provider-link request construction, session snapshot construction, and assembly
of the existing provider, entitlement, and diagnostic dependency boundaries. It
imports no Supabase or provider SDK, resolves no singleton, logs no account
value, and creates no asynchronous task. The service is a reference lifetime
anchor weakly captured by deferred snapshot linking and entitlement refresh, so
both preserve the facade's previous fail-closed teardown behavior.

`PurchaseIdentitySessionLiveService+Live` is the explicit composition edge for
`RevenueCatManager`, `EntitlementManager`, `PurchasePrincipalResolver`,
`LegacyPurchaseIdentityProfileService`, the Supabase client needed by
entitlement refresh, and privacy-safe diagnostics. `SupabaseManager` retains
Auth observable state, exact-session/account-work admission, durable-handoff
closures, lifecycle sequencing, and the source-compatible public entry points.
Resolution task lifetime, keyed supersession, active binding, and foreground
repair remain in the existing Purchase Identity coordinators. The retired facade
helper and direct provider/entitlement dependency assembly cannot return under
the Purchase Principal and Core Network architecture guards.

The Core Security Purchase Identity inventory is now 22 production Swift files
and 2,016 lines; its largest owner is 204 lines. `SupabaseManager.swift` falls
from 3,547 to 3,463 lines. Six focused live-service tests freeze legacy profile
precedence, blank-Auth public fallback, query-failure fallback, exact account-
kind mapping, provider/entitlement/diagnostic forwarding, and exact-account
legacy readiness, plus owner-release rejection for deferred legacy linking and
entitlement refresh. The cross-language purchase-principal contract now reads
the focused live adapter and rejects direct legacy provider linking in the
facade.

Verification passed Swift parsing; strict affected-source SwiftLint with zero
violations; Swift 5 production typechecking; all six host-executable focused
service tests; the host-executable Purchase Principal architecture case; all
thirteen host-executable Core Network integration architecture cases;
byte-stable XcodeGen regeneration; generated-project, source-membership, and
event-routing validation; the 16-case purchase-principal migration contract;
recursive Supabase Function/script formatting; and user-skill link validation.
The canonical generic Simulator `build-for-testing` was attempted through
`make ios-local-build`, but the wrapper refused before invoking Xcode because
this sandbox cannot verify whether `xcodebuild` is active. No fresh app-target
build, Simulator XCTest, or complete `merianTests` runtime result is claimed for
this slice.

This extraction changes no endpoint, JSON field, request action, Auth transition
or recovery rule, observable public signature, persistence, Keychain, RevenueCat
or entitlement order, SwiftData schema, feature flag, navigation, visible copy,
backend behavior, deployment, or release control. No hosted operation was
performed.

### Supabase Auth SDK Adapter Consolidation and Extraction ROI Check

The post-extraction review found that the Auth work had improved isolation and
testability but had crossed the useful boundary into wrapper proliferation. The
three stateless request adapters for OAuth, recovery, and local sign-out all
wrapped the same `SupabaseClient.auth` capability, owned no lifecycle, task,
retry, or product policy, and forced one cohesive SDK boundary across multiple
micro-files. Continuing to optimize only the `SupabaseManager.swift` line count
would have hidden that total production code had grown.

This corrective slice consolidates those pass-through adapters into the
task-free, initializer-injected `SupabaseAuthSessionService` and its single
`+Live` composition edge. The core service owns provider-neutral OIDC and
profile-metadata mapping plus SDK-session projection; the live adapter owns the
request-scoped session read/current snapshot, refresh, identity link, ID-token
and callback-URL install, profile update, and local sign-out calls. Recovery and
local-sign-out diagnostics are colocated with that live boundary. The retained
`AuthLocalSignOutCoordinator` now colocates its narrow dependency values because
they exist only to configure that coordinator. Transition admission, task
lifetime, cancellation, recovery policy, publication, purchase and entitlement
sequencing, and cleanup remain in their existing coordinators and facade.

The consolidation reduces the Auth production inventory from 68 files and 7,800
lines to 61 files and 7,734 lines. `SupabaseManager.swift` moves from 3,463 to
3,461 lines, while the unchanged 22-file Purchase Identity inventory remains
2,016 lines. Across those three measured production surfaces, the total
therefore falls from 13,279 to 13,211 lines: seven fewer files and 68 fewer
lines. The focused adapter coverage is consolidated into one fourteen-case test
suite without removing the recovery, local-sign-out, callback, OIDC, metadata,
projection, or failure-forwarding assertions. Historical extraction sections
above remain point-in-time records rather than being rewritten to describe the
current tree.

This correction does not erase the macro cost of the full extraction round.
Before the round, `SupabaseManager.swift` plus Auth and Purchase Identity
totaled 7,099 production lines across 21 files: 5,389 facade lines, 747 Auth
lines in nine files, and 963 Purchase Identity lines in eleven files. The
current combined total is 13,211 lines across 84 files. The facade is 1,928
lines smaller, but its supporting Auth and Purchase Identity code is 8,040 lines
larger, for a net increase of 6,112 lines, or approximately 86%. That growth
bought explicit concurrency, security, persistence, transport, and executable
ownership contracts, but it is not a size reduction and must not be reported as
one. Further `SupabaseManager` extraction is therefore paused for this round
unless a correctness defect requires it; follow-up work should consolidate or
delete owners, or demonstrate a net-negative affected production delta. The Core
Network architecture suite enforces the four current production budgets so
another split cannot silently grow one surface or their combined total.

The resulting rule is explicit: facade line count is not a sufficient cleanup
metric. A new production owner must acquire a durable responsibility such as
state, task lifetime, policy, protocol translation, persistence, or a distinct
transport boundary. A one-method or pass-through wrapper around the same SDK
capability should be folded into the existing domain adapter unless independent
lifecycle or security semantics require separation. Each future slice must
report both the aggregate-file delta and the total affected production file/line
delta; a slice that only redistributes code needs a concrete complexity or
correctness benefit and an integration guard that proves it.

Verification passed Swift parsing; strict affected-source SwiftLint with zero
violations; strict complete-concurrency production and fourteen-case focused
test typechecking against a minimal Supabase boundary and the real XCTest
interface; the thirteen-case host-executable Core Network integration
architecture suite; byte-stable XcodeGen regeneration; generated-project and
source-membership validation; event-routing validation and adversarial tests;
the complete portable iOS CI-tooling suite; the eight-case cross-language Ghost
merge client contract; the sixteen-case purchase-principal migration contract;
recursive Supabase Function/script formatting; changed-Markdown formatting; and
whitespace validation. The canonical generic Simulator `build-for-testing` was
attempted through `make ios-local-build`, but the wrapper refused before
invoking Xcode because this sandbox cannot inspect whether `xcodebuild` is
active. No fresh app-target build, Simulator XCTest, or complete `merianTests`
runtime result is claimed for this consolidation.

A follow-up code and documentation audit found no production defect. It
corrected the test-ownership wording across the canonical strategy, codebase
map, and Auth READMEs: `AuthLocalSignOutCoordinatorTests` owns the eight
provider-neutral coordinator cases, while the separate colocated
`AuthLocalSignOutFacadeTests` suite owns the rehomed authenticated-request-gate
regression.

This consolidation changes no endpoint, JSON field, request action, Auth
transition or recovery rule, observable public signature, persistence, Keychain,
RevenueCat or entitlement order, SwiftData schema, feature flag, navigation,
visible copy, backend behavior, deployment, or release control. No hosted
operation was performed.

### App-root Integration Audit and Debug-fixture Ownership

The App-root audit reviewed the complete `MerianApp.swift` composition path,
including application-delegate callbacks, root presentation, URL precedence,
scene-phase forwarding, account-deletion recovery, SwiftData bootstrap, and the
Debug UI-test fixture surface. It found no behavioral or concurrency defect. The
overlapping deletion-recovery triggers remain protected by the existing
single-transition downstream owner, and the app root still evaluates the Google
callback before app-route, file-import, and fallback Supabase handling.

The first App slice moves the 876-line compile-condition block into the focused
`App/UITesting/UITestSeedCoordinator.swift` owner, keeping its Debug fixture
implementation and signature-compatible Release no-ops together. The UIKit
delegate bridge moves to `AppDelegate.swift`; deterministic launch and startup
notice presentation moves to `Presentation/AppRootPresentation.swift`; and
value-only URL classification moves to `Routing/AppURLRouting.swift`.
`MerianApp` remains the sole `WindowGroup`, scene-phase, dependency-composition,
and fallback Auth-task owner. Existing presentation and URL-classification tests
move beside their App owners, while a new architecture suite freezes the
inventory, root-only effects, exact Debug/Release seed boundary, and one
remaining oversized production owner.

`MerianApp.swift` falls from 2,221 to 1,177 lines. The four focused
App-extracted sources total 1,053 lines, including the 880-line Debug-fixture
owner; total App source therefore grows by 9 lines for imports, formatted
delegate signatures, and ownership documentation rather than claiming a size
reduction. Excluding the compile-time-gated fixture owner, every focused App
production file is at or below 600 lines except `MerianApp.swift`. Its remaining
bulk is the migration-sensitive ModelContainer construction, checksum fallback,
quarantine, rescue, and safe-mode ladder. That work is deliberately deferred to
a separate SwiftData-startup slice instead of being mechanically moved during
this audit.

A second code review found one cross-layer ownership issue without finding a
runtime defect: Analytics, Security, Network, Data, Offline Sync, App startup,
and Debug fixtures all consumed `TestExecutionCoordinator`, but its declaration
still lived in `MerianApp.swift`. The unchanged process signals now have one
`Configuration/TestExecutionCoordinator.swift` owner with pure parameterized
policy entry points. The cloud-image repair live adapter's remaining direct
XCTest-environment read now delegates to the same policy. Focused tests freeze
the UI-test marker, XCTest configuration marker, loaded-runtime fallback, false
case, and sole raw-signal owner; the portable workflow and startup-safety scope
guard the new boundary.

The portable iOS workflow now reads seed markers from the focused fixture source
while continuing to verify the call order in `MerianApp`. Startup-safety scope
includes App lifecycle, presentation, routing, delegate, fixture, and App test
changes. Canonical ownership documentation also corrects the stale claim that
Core retained two oversized production files; its executable guard tracks only
`SupabaseManager.swift`.

This slice changes no SwiftData schema or migration plan, endpoint, JSON field,
Auth rule, route value, URL precedence, root presentation decision, fixture
value, visible copy, persistence, feature flag, backend behavior, deployment, or
release control. No hosted operation was performed.

### SwiftData Startup Bootstrap Ownership

The remaining App-root slice moves migration-sensitive SwiftData construction
out of `MerianApp.swift` without changing V51, any historical schema, migration
stage, recovery classification, store location, archive rule, telemetry field,
or user-visible recovery copy. `ModelContainerFactory` owns the Objective-C-
exception-safe construction boundary, exhaustive recent-source plan switch,
attempt recording, and ordered duplicate-checksum fallback.
`ModelContainerBootstrapper` owns launch diagnostics and the normal,
corruption-quarantine, legacy-rescue, in-memory safe-mode, and terminal blocked
outcomes. One colocated model file owns the bootstrap result—including its
optional `ModelContainer` reference—plus value-only state, notice, and telemetry
values. `MerianApp` now requests one bootstrap result, attaches its container
and presentation values, and emits the returned telemetry after analytics
admission; it no longer constructs a `ModelContainer`, names a migration plan,
or invokes quarantine/rescue effects.

`MerianApp.swift` falls from 1,177 to 447 lines. The affected production
boundary—`MerianApp`, App-root presentation, and Store Recovery—moves from 2,608
to 2,751 lines across the extraction, a transparent increase of 143 formatted
lines rather than a claimed size reduction. The increase buys two durable
responsibility owners, explicit value ownership, testable safe-mode outcomes,
and executable prevention of bootstrap logic returning to the composition root;
it does not introduce a pass-through service or another singleton. Every Release
App and Store Recovery production owner is now at or below 600 lines.

Focused tests add a successful in-memory safe-mode case and the terminal blocked
case, preserve the existing disk-backed migration fixtures, and move Objective-C
exception wrapping calls to the new factory. App and Store Recovery architecture
suites freeze the sole declaration owners, root delegation, Auth/session
exclusions, mirrored tests, and line ceilings. Migration source guardrails now
read the factory and bootstrapper directly, keep recent-source dispatch
compiler-exhaustive, pin checksum retry order, and reject direct
`ModelContainer` construction in `MerianApp`. Startup Safety selects the new
bootstrapper and App-root suites alongside the existing recovery and migration
matrix.

This slice changes no SwiftData schema or migration plan, endpoint, JSON field,
Auth/session behavior, root presentation decision, visible copy, persistence
location, feature flag, backend behavior, deployment, or release control. No
hosted operation was performed.

A follow-up implementation and documentation audit found no production defect.
It reconfirmed exact V42...V50 source routing and checksum retry order,
quarantine/rescue eligibility and mutation semantics, recovery copy,
diagnostics, telemetry, actor isolation, generated-project membership, and
Startup Safety selection. The audit corrected six documentation-only drifts: the
bootstrap outcome is not described as value-only because it carries the
container; the schema guide points to the checked-in SwiftData migration skill
instead of the compatibility-only legacy workflow pointer; the architecture
overview names Store Recovery as the container creator; and the migration-plan
initialization test is scoped to independent full-plan validation. The startup
contract also names the focused safe-mode and terminal- blocked bootstrap
coverage, while the codebase map distinguishes environment attachment from
post-admission telemetry emission. Swift parsing, strict affected-source
SwiftLint, byte-stable XcodeGen, project/source membership, migration and
event-routing guards, portable CI-tooling tests, agent-asset validation,
Markdown formatting, and whitespace validation passed. The generic Simulator
`build-for-testing` remained unrun because the required local-build wrapper
could not inspect active `xcodebuild` processes and refused before invoking
Xcode; the safety check was not bypassed.

A subsequent App and Store Recovery integration audit found one recovery-
hardening defect: the empty in-memory safe-mode container still supplied the
full historical `MerianMigrationPlan`. A malformed historical stage could
therefore defeat both persistent startup and the last-resort workspace. The
factory now creates safe mode from `CurrentSchema` without a migration plan,
while `MigrationPlanTests` continues to validate the full plan independently.
The live bootstrap regression constructs that production fallback; architecture
and shell guardrails reject migration-plan coupling inside the safe-mode
factory; and the shell guardrail's adversarial fixture proves that
reintroduction fails. A second adversarial fixture rejects weakening the
independent full-plan initialization test to a recent-source plan. This changes
no schema, migration stage, store location, archive policy, visible copy, or
persistent-store selection. Swift parsing, strict affected-source SwiftLint,
byte-stable XcodeGen, project/source membership, migration and event-routing
guardrails, portable CI-tooling tests, agent-asset validation, Markdown
formatting, and whitespace validation passed. The required local-build wrapper
again refused before invoking Xcode because this environment cannot verify
whether `xcodebuild` is active; the safety check was not bypassed, so simulator
build and test execution remain unrun for this follow-up.

### Models Species Value-Graph Ownership

The first Models hygiene slice removes the mixed 823-line
`Models/SpeciesData.swift` aggregate. Cross-feature, Foundation-only domain
values now live in four cohesive files under `Models/Species`: the core
`SpeciesData` value, deterministic presentation and identity policy, supporting
observation values, and rich lookalikes. Inference-owned `CaptureTelemetry` and
the handwritten `EdgeResponse` mapping now live in two files under
`Core/AI/Models`. Type names, initializer labels and defaults, Codable shapes,
sanitization, display policy, edge mapping, and all call sites remain stable. No
SwiftData model, migration stage, wire payload, endpoint, task, service,
singleton, or navigation contract changes.

This is an ownership improvement rather than a claimed volume reduction. The
production surface moves from one 823-line file to six files totaling 879 lines:
five additional files and 56 additional formatted lines for explicit imports,
extensions, readable boundaries, and preservation of the aggregate's domain-
contract comments. Every new owner is under 600 lines, and no file exists only
as a forwarding wrapper. The former 942-line behavior suite is split by the same
responsibilities, `CaptureTelemetryTests` moves beside Core AI Models, and the
Edge adapter's twelve behavior tests move into a colocated
`SpeciesDataEdgeResponseTests` suite rather than leaving wire coupling under
shared Models. All 41 pre-split behavior test names remain present.
`SpeciesModelsArchitectureTests` locks exact inventories, declaration
uniqueness, Foundation-only shared models, absence of live effects, Core AI
adapter and test ownership, aggregate retirement, and the local line ceiling. An
additional parameterized regression freezes every legacy unresolved-name
sentinel. The Capture-owned zoom-policy regression moves out of the Core AI
telemetry suite into the existing Capture Submission policy suite. The Models
README records the boundary and the unchanged SwiftData migration rules.

The second-pass audit found no behavior or initializer drift. It corrected the
zoom-policy test ownership, completed the focused-test selector inventory,
restored domain-contract comments that were lost during extraction, and added a
parameterized unresolved-sentinel regression. All 41 original Species behavior
test names remain present and each extracted production declaration has one
owner. Repeated XcodeGen output was byte-stable; project/resource and source-
membership validation, migration and event-routing guardrails, the full iOS CI-
tooling suite, Swift parsing, strict SwiftLint, Markdown formatting, and
whitespace validation passed. The required local-build wrapper refused before
invoking Xcode because the host denied process inspection, so simulator
compilation and runtime test execution remain unrun for this slice.

### Models Captured Media Value-Graph Ownership

The second Models hygiene slice retires the mixed 1,115-line
`Models/ActiveSchema/SerializedMediaItem.swift` aggregate. Foundation-only
observation, storage-reference, ordered timeline, snapshot, summary, and JSON
values now live under `Models/Media`. The unchanged V51 `CapturedMediaEntry`
declaration remains in `Models/ActiveSchema`; local and approved-HTTPS
resolution lives in `Core/Media`; cloud hydration/replacement, timeline
serialization with injected file adoption, and scalar/relationship mirror
persistence live in `Core/Data/CapturedMedia`; and Capture Submission owns its
transport projection. No view or value owner gained networking, authentication,
persistence, or live singleton resolution.

This split is an ownership improvement, not a size-reduction claim. The directly
affected production surface moves from four files and 1,394 lines to eight files
and 1,420 lines: four additional cohesive owners and 26 additional formatted
lines. The former aggregate mixed deterministic values, SwiftData declaration,
cloud compatibility, filesystem resolution, and persistence conversion; every
replacement owner is below 600 lines and none is a pass-through wrapper.
`ObservationContext` moves from Capture Shared to the cross-feature value graph
without changing its initializer, Codable shape, normalization, or submitted
text. The active persisted declaration is byte-equivalent in stored shape, so
V51, model names, checksums, relationships, and migration plans remain
unchanged; no V52 is created.

Focused behavior coverage now mirrors the production layers.
`CapturedMediaValuesTests` owns observation normalization and Codable behavior
plus deterministic timeline values; Core Media owns resolution tests; Core Data
owns hydration, serialization, and scalar-first relationship-fallback tests; and
`CapturedMediaArchitectureTests` freezes unique declaration ownership,
effect-free value files, the exact V51 stored-property inventory, retired paths,
focused suite placement, and the 600-line ceiling. The empty historical
`ObservationContextTests` suite and aggregate captured-media tests are removed
after their executable cases are rehomed.

The second-pass review found no behavioral or schema drift. It corrected the
database documentation's former synthetic inverse-relationship claim, made the
cross-feature observation owner explicit, and strengthened the active-schema
guard from a required-field subset to the exact ordered stored-property list.
Swift parsing, strict SwiftLint, byte-stable XcodeGen, project/source
membership, migration and event-routing guards, focused source typechecking,
Markdown and Supabase formatting, and whitespace validation passed. The required
local-build wrapper refused before invoking Xcode because it could not inspect
active build processes, so no fresh Simulator compilation or runtime result is
claimed for this slice.

### Models-wide Integration Audit

The Models-wide closure audit reviewed the root cross-feature values,
`Models/Species`, `Models/Media`, every V51 `ActiveSchema` source, the
historical snapshots, the ordered migration registry, and mirrored tests. It
found two material ownership violations. `QueuedScanContext` performed local
filesystem inspection and decoded Capture's `IdentifyVisualMediaItem` directly,
while `ActiveSchema/PendingCloudDeletionTask.swift` also owned a `ModelContext`
fetch/insert workflow.

The correction keeps `QueuedScanContext` as the cross-feature route snapshot but
makes it deterministic. The existing queued-scan extraction persistence owner
now projects a live SwiftData row into that detached value and asks
`OfflineQueueStoragePolicy` for its byte estimate. The policy consolidates
capture-file sizing and deduplicated queued-media footprint inspection formerly
split between the model and `OfflineCaptureFileStore`, and the projection
decodes captured media only once. The existing Insight media-presentation
extension owns queued-to-`ActiveScanMedia` mapping and focus-descriptor
restoration. The cloud-deletion task declaration becomes a 13-line schema owner;
its idempotent task/job/event insertion moves beside the existing offline-job
helpers in `Core/Data/OfflineSync/Persistence`. No new production file or
wrapper is added.

Across the thirteen touched production files, the correction adds 180 lines and
removes 162, a net increase of 18 formatted lines for explicit projection,
storage, presentation, and persistence boundaries. `QueuedScanContext` falls
from 167 to 95 lines, `PendingCloudDeletionTask.swift` from 56 to 13, and
`OfflineCaptureFileStore` from 144 to 117. The existing storage policy grows
from 32 to 96 lines, queued-scan extraction from 70 to 101, offline-job
persistence from 54 to 98, and Insight media presentation from 274 to 291; each
remains below 600 lines.

`ModelsIntegrationArchitectureTests` freezes the exact root and active-schema
inventories, Foundation-only root values, absence of live effects and
`ModelContext` workflows, sole queued-row/byte/presentation/persistence adapter
ownership, V51/no-V52 state, and the nonhistorical 600-line ceiling. The audit
deliberately keeps `ScanQueueState` and `UserReviewState` at the root because
persistence, Core, and features share their stable vocabulary. It also keeps the
4,293-line `SchemaVersions.swift` as one compiler-reviewed migration and
plan-order registry; mechanically splitting that file would make migration
sequencing harder to audit without removing a runtime responsibility. This is
the stop point for Models extraction in this round.

The change preserves queue-byte calculations, focus restoration, cloud-deletion
idempotency, routes, initializer data, SwiftData fields, migration plans,
endpoints, payloads, copy, feature flags, and release controls. No V52 schema or
hosted operation is introduced.

The closure review also corrected two guardrail defects before handoff. The
effect-free source check now ignores documentation-only line comments, so its
own `OfflineQueuedScan` explanation cannot fail the suite, and the live-row
projection is explicitly `@MainActor` with matching Models and Offline Sync
source guards. Focused storage-policy tests register cleanup before writing
their temporary fixtures. The documentation closure now names the main-actor
projection consistently across Models, Offline Sync, Scans, the codebase map,
the offline pipeline, and the test strategy; distinguishes Scans Shell's grid
snapshot from the richer Insight route snapshot; records the consolidated
storage-policy consumers; and attributes queued active-media adaptation to
Insight. Privacy documentation names `OfflineQueueStoragePolicy`, not the
detached value, as the file-metadata owner. The canonical Models focused matrix
lists the value, persistence, adapter, migration, and architecture selectors and
still requires the complete `merianTests` target.

Verification passed Swift parsing; strict affected-source SwiftLint with zero
violations; native typechecking of the Foundation-only media, queue-state,
queued-context, and storage-policy boundary; byte-stable XcodeGen regeneration;
project/resource and source-membership validation; migration, event-routing, and
versioning guardrails; the complete portable iOS CI-tooling suite; changed-
Markdown and recursive Supabase Function/script formatting; all 26 executable
documentation contracts; and whitespace validation. The canonical generic
Simulator `build-for-testing` was attempted through `make ios-local-build`, but
the wrapper refused before invoking Xcode because this environment cannot
inspect whether `xcodebuild` is active. The new focused projection, sizing, and
architecture tests are checked into the target, but no fresh Simulator XCTest or
complete `merianTests` runtime result is claimed for this audit.

### iOS-wide Hygiene Closure Audit

The final cross-app audit reviewed the App, Configuration, Core, Features,
Models, and Resources ownership boundaries after the folder-by-folder passes. It
found one ordinary production source above its documented guard:
`ExplorePostDetailView.swift` had reached 602 physical lines. The excess came
from a private method that only forwarded to `ExplorePostDetailViewModel`.
Callers now invoke that injected state owner directly, removing the pass-through
without moving lifecycle, selection, sheet, focus, persistence, or route state.
The host is 598 physical lines and remains behaviorally unchanged.

The audit also reviewed the smallest extracted owners for wrapper proliferation.
Three Field Notes files contained only a tightly coupled visibility request,
feedback enum, or caller configuration. The request and feedback are now
colocated with `FieldNotesEditPolicy`; the configuration is colocated with
`FieldNotesEditorDependencies`. This removes three production files while
preserving type names, access, call sites, visible feedback, async save
behavior, and dependency direction. Across the affected production Swift
sources, the closure adds 31 lines and removes 32, for a net reduction of one
line and three files. Tiny owners that isolate a live SDK, process, filesystem,
persistence, schema-alias, or feature-flag boundary remain separate because
their boundary is independently testable rather than a line-count artifact.

`IOSHygieneClosureArchitectureTests` now scans all main-app Swift sources and
freezes the exact oversized inventory: the Debug-only UI-test seed coordinator,
the measured residual `SupabaseManager` facade, and the cohesive ordered
`SchemaVersions` migration registry. The latter two retain their existing Core
budget and Models migration guards; the global inventory is not a growth
allowance. Configuration totals only three focused Swift owners, Resources owns
only bundled static data, and neither area warrants another extraction slice.
This closes the planned organization round rather than beginning a new sequence
of mechanical file splits.

No endpoint, payload, Auth transition, SwiftData schema or migration stage,
persistence behavior, feature flag, navigation contract, visible copy,
accessibility value, backend behavior, deployment, or release control changes.

Verification passed Swift parsing, standalone typechecking of the consolidated
Field Notes value owner, strict affected-source SwiftLint with zero violations,
byte-stable XcodeGen regeneration, project/resource and source-membership
validation, event-routing, migration, and versioning guardrails, the complete
portable iOS CI-tooling suite, changed-Markdown formatting, the exact oversized-
owner inventory, declaration-uniqueness checks, and whitespace validation. The
second-pass review also corrected the shared architecture-test line counter: a
terminal newline is now treated as a terminator instead of an extra physical
line, with focused empty, terminated, and unterminated cases in the closure
suite. The canonical generic Simulator `build-for-testing` was attempted through
`make ios-local-build`, but the wrapper refused before invoking Xcode because
this environment cannot inspect whether `xcodebuild` is active. Focused and
complete Simulator XCTest execution therefore remain unrun for this closure.

## Validation Gates

Every cleanup PR should run the narrowest relevant checks, plus the full app
build for moved Swift files:

```bash
git diff --check
make ios-local-build ARGS='simulator -- build-for-testing -configuration Debug -destination "generic/platform=iOS Simulator"'
```

For web changes:

```bash
cd apps/web
npm run typecheck
npm run build
```

For Supabase function changes:

```bash
cd services/supabase/functions
deno check --config deno.json <changed-entrypoint>.ts
deno task test
```

## Stop Conditions

Pause the cleanup slice and make a smaller plan when:

- a file move requires behavior changes,
- a split touches more than one feature boundary,
- generated Xcode project changes become noisy,
- tests need large rewrites just to follow a mechanical move,
- or an in-progress product bug would become harder to isolate.
