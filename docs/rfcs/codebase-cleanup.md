# Codebase Cleanup Plan

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

| File                                                     | Cleanup Direction                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/ios/Merian/Core/AI/InferenceEngine.swift`          | Integration audit and scoped safety fixes merged; user-confirmed GitHub Actions pass accepted as the baseline. Request/result adaptation, recovery, hydration, bounded writes, reference transport, and local-analysis ownership are split.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `apps/ios/Merian/Core/Network/MerianNetworkClient.swift` | Complete for this hygiene round. Seventeen endpoint owners cover the extracted feature, inference, publication, lifecycle, enrichment, feedback/export, storage, and account-deletion operations. Stateless inference policy lives in `Inference/`; signed transfers and publication-media restoration live in `Media/`; owned-row recovery lives in `Recovery/`; route/error/replay policy, the request-scoped executor, the sole pinned session/TLS owner, and the per-attempt authenticated dispatcher live in `Transport/`. The client stays below the 600-line façade ceiling, injects those focused owners, and retains endpoint configuration, shared response/cache bridges, and capability-only account-deletion recovery transport.                                                                                                                                                              |
| `apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift`  | Complete for this hygiene round. `Core/Preferences` owns `AppSettings`, keyed compatibility stores, the verified accepted-account-deletion cache inventory, and an injected post-persistence runtime reset; `Core/Data/SpeciesPreferences` owns SwiftData CRUD, normalization/conflict policy, exact PostgREST values, the narrow injected live client, focused local-mutation recovery, and contained single-flight cloud coordination. The residual aggregate is 450 lines and imports only Foundation. Mirrored suites cover settings/store behavior, schema-complete local erasure, explicit-null wire encoding, stable pagination, account fencing, clock skew, interruption recovery, mid-upsert edit fencing, trailing reconciliation, and process-state reset delegation. Account-deletion recovery state and Keychain keys intentionally remain for their separately reviewed security ownership. |

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
  pause/resume. `InferenceEngine` retains exact presentation authority and
  observable phrase publication through narrow callbacks. AppDI now supplies the
  live light-impact start feedback while direct/default engine instances use an
  inert default. The former `LocalVisualAnalysis.swift` aggregate was replaced
  by focused classifier, bounded-image, deterministic-trait, Foundation
  contract/validation/eligibility, phrase-policy, and lifecycle files, each
  below 600 lines. A follow-up integration review made repeated
  inactive/background callbacks idempotent so the normal scene transition
  preserves only one pending exact-session cadence resume and cannot restart
  completed local model work. The generic simulator build, focused and complete
  `merianTests` suites, XcodeGen/source-membership checks, parsing, strict lint,
  and documentation gates passed after that correction.
- The fourth slice moved shared visual/nonvisual request preparation and live
  provider dispatch into the initializer-injected `InferenceLiveRequestService`.
  It owns base64 filtering, MIME detection, observation-context serialization,
  aligned descriptor forwarding, staged-video upload, and the single Identify
  call. `InferenceEngine` supplies exact-attempt validation after encoding,
  video upload, and provider return and retains its provider-ready timer,
  request-body queue effects, presentation, response parsing, persistence, and
  recovery policy. AppDI owns the production live value; tests inject three
  narrow closures without a broad protocol or new singleton. No payload field,
  request ordering, timeout, endpoint, callback, navigation, persistence schema,
  or observable UI contract changed. A follow-up review restored MIME and
  observation-context helpers to file-private visibility and added an explicit
  stale-after-image-encoding fence test.
- The fifth slice added the injected `InferenceLiveResultService` for shared
  visual/nonvisual parse/save input normalization and typed result outcomes.
  `InferenceProcessingActor` retains its existing decoding, entitlement,
  storage, media cleanup, and durable-completion rules. The service forwards the
  exact model context, canonical media, original observation-context JSON, and
  persistence fence; the engine supplies attempt validation before/after the
  actor call. Both persisted and confidence-zero no-record completion keep the
  original engine publication/queue path. Rejected or stale results cannot enter
  it. Discovery feedback, replacement metadata, notifications, milestones,
  hydration, failure policy, and their existing ordering remain in the engine.
  Mirrored service and integration suites use injected dependencies and
  continuation gates, with architecture checks preventing direct parse/save
  mapping from returning to the engine. No DTO, payload, schema, endpoint, or
  presentation contract changed.
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
  unchanged. Queue mutation, paywall requests, circuit accounting, logging,
  haptics, and observable publication stay engine-owned. The engine shrank by
  337 lines in this slice; both new production files remain below 600 lines.
  Pure policy/presentation suites and queue-less engine integration cases cover
  those decisions, known conflicts, decoding, and non-cooperative stale or
  cancelled failures. Result/recovery fixtures now share contained test support
  and a continuation gate instead of duplicating setup. Circuit-breaker XCTest
  unit cases now use a fresh manager instead of resetting the singleton used by
  Swift Testing integration suites. The architecture suite locks the effect-free
  policies and synchronous ownership-to-commit boundary. Parsing, strict
  affected-source lint, byte-stable XcodeGen, project/source membership,
  event-routing and workflow-contract checks, and isolated policy/presentation
  source and test typechecking against cached dependencies passed. A follow-up
  review (2026-09-02) found no additional code fixes necessary. All new
  result/recovery service and integration tests, shared fixtures, policy and
  presentation tests, architecture tests, and the isolated circuit XCTest passed
  focused frontend typechecking against the exact current engine/result/recovery
  declarations and cached unchanged dependencies. That verifies test bodies, not
  full engine compilation or runtime behavior. Simulator discovery is available
  again, but the generic Simulator build and `build-for-testing` still stop at
  denied SwiftPM manifest-cache writes, before candidate tests can execute.
  Direct engine/current-app compilation also stops at the environment's Apple
  macro sandbox restrictions. Focused and full runtime acceptance remain
  outstanding at that slice's handoff; the integration audit below follows it.
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
  navigation, or backend contract changed. `InferenceEngine.swift` remains a
  large orchestrator and should continue through small, behavior-preserving
  slices.
- The Inference-wide source integration audit (2026-09-02) traced visual, audio,
  and Describe requests through result, recovery, hydration, writes, Auth, and
  exact queue completion. It repaired an existing reanalysis data-loss path:
  `InferenceScanReplacement` requires a typed persisted result and a distinct
  store-visible replacement, saves tags/collections/notes before deletion, and
  preserves the original on no-record outcomes or lookup/save failure. Scoped
  save rollback leaves unrelated user edits intact. The repository's existing
  deletion/outbox commit still owns destruction; its post-commit cleanup now has
  an optional completion handle so tests can await their own work.
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
  inventory. The residual `UserDefaultsKeys.swift` aggregate is Foundation-only
  and 450 lines; account-deletion recovery state and Keychain keys remain for a
  separately reviewed security slice. Mirrored suites and architecture guards
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
  background-task authority, inference attempt fencing, LocalImageLoader repair,
  Profile avatar promotion, and main-client publication/restore orchestration do
  not move in that storage slice; the later scan-publication slice above moves
  the publication owners without changing these primitives. No API, schema,
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
- Documentation synchronization also covers Settings-to-Hardware push
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
  test locks the live-service boundary and 600-line ceiling. Cross-feature
  complimentary-scan display state moved to `Core/UI/Models`. The Profile Shell
  composes the environment-owned geoprivacy and hardware adapters. Geoprivacy
  writes are account-fenced, serialized, and latest-selection-coalesced;
  expedition mode persists before constraint reevaluation; notification
  refreshes discard stale generations; and sign-out, deletion, export, survey,
  purchase, restore, and redemption actions reject conflicting overlap.
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
  view and presentation-only flash control moved to `Core/UI`. Capture-specific
  source/ crop metadata remains in `Capture/Shared`, and Profile owns its own
  bounded avatar-crop presentation value. Callers inject haptic/camera effects
  so the shared controls remain passive. Detached media work now propagates
  parent cancellation, and newly created WAV/compressed-playback files remain
  leased until staging accepts them so timeout-losing or otherwise unconsumed
  results cannot leak artifacts. A staged video finalizes its recording
  generation and cancel UI before the optional PhotoKit save completes, while
  the capture task still retains the original recording through that save.
  Mirrored tests lock sampling, playback presentation, task replacement,
  lifecycle overlap rejection, temporary-file transfer and cleanup, detached
  cancellation, dependency routing, ownership, platform-neutral Models, and the
  line ceiling.
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
  are unchanged. `ActiveScanToolbar` consumes the canonical staged order without
  a duplicate sort. Mixed tests were rehomed to Staging, Shell, Submission, and
  Core Utilities owners, with deterministic projection/descriptor tests and a
  new Staging architecture/600-line guard.
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
  resolving haptics. Manager-owned start/resume handles plus a generation fence
  reject late activation, DSP, and countdown commits across lifecycle changes;
  duplicate resume requests coalesce. The coordinator commits one-shot lease
  ownership only after successful activation. Failed replacement restores the
  prior configuration; failed rollback or first activation deactivates partial
  state instead of publishing unknown ownership. Reusable palette/raster/layout
  policy moved to `Core/Media`, the SwiftUI spectrogram moved to `Core/UI`, and
  the audio/video countdown badge moved to `Capture/Shared`. Mirrored feature,
  hardware, and media suites lock presentation, scrubbing, feedback injection,
  DSP/noise-floor and raster behavior, transition/lease concurrency, ownership
  boundaries, platform-neutral Models, and the 600-line production-file ceiling
  without changing the 15-second WAV, confirmation, staging, submission, copy,
  accessibility, or audio-session contracts.
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
SwiftData repair. V50's complete relationship-bearing graph is frozen in
`Models/Schema/SchemaV50Snapshots.swift`, including its historical
`ScanCollection.isDeleted` field and goal-hint companion. The source bridge
`MerianActiveSchemaV50` maps `isPendingDeletion` with
`@Attribute(originalName: "isDeleted")`, so the application tombstone survives
save/refetch while the persisted V50 model and Supabase/JSON field `is_deleted`
remain unchanged.

V51 subsequently made preferred species names account-scoped without changing
the collection shape. Released V50 stores now use the source-isolated V50→V51
plan; the V49 plan applies V49→V50→V51. The full historical plan is linear
through V42→V49→V50→V51, while V43...V48 keep source-isolated repair plans. Disk
fixtures prove metadata-based plan selection and multi-row preference deletion
from the frozen V50 source before V51 materializes its new unique identity. The
source guardrail also pins every V35...V48 preference alias to the immutable V34
shape so the new active fields cannot alter retired checksums. The fixtures
continue to prove tombstone true/false values, relationship and goal-hint
retention, and second-context reads. Collection mutation and database-actor
suites cover exact payload projection, inbound reconciliation fencing, rollback,
and acknowledgement-only purge. Recovery dispatch treats V51 as current, and
checksum fallback tries V50 before the exhaustive V49...V42 source-isolated
ladder.

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
leases now fence every live request across Auth transitions, while the engine
retains review generations, local persistence, presentation, and post-success
effects. Architecture tests lock this ownership and the Core Network singleton,
query, and RPC inventory. No Identify payload, navigation contract, collection
wire field, or non-preference SwiftData shape changed.

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

`RevenueCatManager.swift` is now 577 lines, below the final 600-line guard, and
its existing initializer and callable surface remain unchanged. Computed
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
  at least two features use them.

## Validation Gates

Every cleanup PR should run the narrowest relevant checks, plus the full app
build for moved Swift files:

```bash
git diff --check
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
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
