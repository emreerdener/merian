# Merian iOS Structure

The iOS workspace is organized around product ownership first, then
implementation type. A developer should be able to find a user-facing area by
the name a user would use in the app before seeing folders such as `Views`,
`Models`, or `Components`.

## Top-Level Areas

```text
apps/ios/
  Merian/          Main iPhone app
  MerianTests/     Unit tests for the main app
  MerianUITests/   UI tests for the main app
  MerianPerformanceTests/  Report-only XCTest benchmarks
  TestSupport/     Canonical fixtures shared by test bundles only
  messages/        Messages extension and shared message-scan code
  photos/          Photos import extension and shared import code
  widgets/         Widget extension sources
```

The main app is organized as:

```text
Merian/
  App/              App entry, launch presentation, URL routing, lifecycle wiring, and Debug fixtures
  Assets.xcassets/  App, brand, persona, and reusable visual assets
  Configuration/    Build resources, environment/test detection, and app-wide client flags
  Core/             Cross-feature services, infrastructure, and UI primitives
  Features/         User-facing product areas
  Models/           Cross-feature value graphs and SwiftData schemas
  Resources/        Bundled JSON, release notes, and static app resources
```

[`App/README.md`](Merian/App/README.md) defines the composition-root,
presentation, routing, delegate, lifecycle, and UI-test ownership boundaries.
[`Models/README.md`](Merian/Models/README.md) defines cross-feature value,
active-schema, historical-snapshot, and migration-registry ownership.

## Runtime audit

`MerianPerformanceTests/` owns isolated, report-only XCTest measurements.
`scripts/config/ios-runtime-audit.json` selects the existing behavioral owners,
critical UI fixtures and separate benchmarks. Run the shared-cache audit through
`make ios-local-build ARGS='audit --destination "platform=iOS Simulator,id=UDID" --environment-label "hardware-runtime"'`.
See the
[canonical audit methodology](../../docs/development-guides/18-ios-runtime-quality-and-benchmarking.md)
for selectors, baselines, CI policy, evidence and unmeasured device gaps.

## Feature Folders

Feature folders are product-area-first. If a feature contains multiple
user-facing areas, those areas get their own folders before implementation
buckets appear.

```text
Features/<FeatureName>/
  Shell/          Root container, routing, tabs, pagers, and feature chrome
  <ProductArea>/  User-recognizable area such as Feed, Map, Settings, or Scan
  Shared/         Feature-owned helpers shared by multiple product areas
```

Inside a product area, use focused implementation folders only when they are
needed:

```text
<ProductArea>/
  Views/
  Components/
  Models/
  ViewModels/
  Services/
  Utilities/
```

Avoid parallel concepts such as `Screens/` and `Views/`. In SwiftUI, sheets,
detail routes, and full-screen pages are all views; folder nesting should
explain ownership.

## Core Versus Shared

Use the narrowest owner that fits:

- Put code in `<Feature>/Shared` when it is reused by multiple product areas
  inside one feature.
- Promote code to `Core` only when it is domain-neutral and reused across
  features or represents app infrastructure.
- Keep feature-specific business and presentation rules out of `Core` even when
  another feature's adapter invokes them to enter or present that experience.

[`Core/README.md`](Merian/Core/README.md) defines the root and cross-domain
guardrails. The Core root contains only dependency composition and logging;
domain READMEs and architecture suites own the detailed boundaries. The
Core-wide audit tracks the one residual production file above 600 lines instead
of treating its current size as a permanent exemption.

Examples:

- `Features/Scans/Shared` owns the Scans-only composite grid, queued-row value
  policy, and deletion interaction boundary.
- `Features/Explore/Shared` owns customer-safe Explore error presentation.
  Insights, Scans, Species Dictionary, and Species Reference adapters may
  consume that policy when they publish into or present Explore, but the policy
  remains Explore-owned.
- `Core/UI` owns `ScanThumbnail` and `EmptyStateView` because Explore, Scans,
  Profile, and Species Dictionary consume them.
- `Core/Data/OfflineSync` owns sync infrastructure rather than a
  feature-specific scan screen.
- `Core/Data/SpeciesPreferences` owns the cross-feature SwiftData and cloud
  reconciliation boundary for preferred species display names.
- [`Core/Routing`](Merian/Core/Routing/README.md) owns immutable app-event and
  root-route values, deterministic routing policy, and the DI-scoped
  coordination state machines.
- [`Configuration/FeatureFlags.swift`](Merian/Configuration/FeatureFlags.swift)
  owns the app-wide client-build flag registry—release gates plus the advisory
  scan-meter control—and DEBUG-only local overrides. Feature-specific
  availability policy remains with its feature; Field Trips owns standard-outing
  sharing availability in its `Models/` directory.

Cross-feature wire operations can live in `Core/Network/Endpoints/` even when
grouped by feature. Field Trips, Community Identification browsing/contribution,
the eight Explore browsing reads, 12 Explore interaction methods, four
notification methods, four public-profile methods, six Explore post-management
methods, six inference entry points, two direct scan-publication methods, 17
Field Chat methods, six Species Dictionary method variants, four scan lifecycle
methods, two scan enrichment/context methods, one export method, two product
feedback methods, three media storage methods, and six account deletion/recovery
methods are extracted. Both raw `uploadToR2` overloads, foreground
`uploadStagedVideoFiles`, and publication-media restoration live in
`Core/Network/Media/`; owned-row publication and Field Chat recovery live in
`Core/Network/Recovery/`. Existing feature adapters, shared Profile state, Core
Notifications' push/badge owners, and Core's social guard retain their callers
and state. `Core/Network/Transport/` owns stateless route/error/replay and Auth
recovery policy, including the value-only `UnauthorizedRefreshTarget`, the
request-scoped executor that applies those decisions, the sole pinned
`URLSession`/TLS owner, and the per-attempt Auth dispatcher. The dispatcher owns
account leases and headers, transition validation, constrained-network headers,
URLSession cancellation, and its file-local upload delegate. The network client
is the façade that injects those two stateful transports behind typed-response,
body-ignoring, encoded-body, and raw-response JSON POST bridges. Dictionary
detail/stats use fixed-result cache-aware bridges whose GET helper stays
private. The typed POST bridge preserves optional idempotency keys and
endpoint-specific decoding-error mapping without intercepting transport
failures. Field Chat's encoded-body bridge returns bytes to its stateless
`Decoding/FieldChatResponseDecoder.swift`; it does not own another retry policy.
Dictionary schema/identity checks live in
`Decoding/SpeciesDictionaryResponseValidator.swift`; its two locked per-client
memos live in `Caching/SpeciesDictionaryResponseCache.swift`. The client keeps
that cache instance private; only its fixed-result bridges can populate it,
after authenticated loading and schema/identity validation. The internal
configuration guard preserves URL-validation-before-cache ordering without
exposing transport state. Scan status DTOs live in
`ScanLifecycleAPIModels.swift`; `Decoding/ScanLifecycleResponseDecoder.swift`
owns explicit-key decoding, single/bulk identity checks, and deletion
confirmation. `Endpoints/MerianNetworkClient+Inference.swift` owns prewarm and
the `/identify` and `/identify-multimodal` request entry points;
`Core/Network/Inference/` owns immutable request values plus stateless payload,
inline-media, staged-owner, and recoverable-conflict policy. The endpoint owns
cancellation-aware off-main body preparation through
`.inferenceRequestPreparation`; its narrow bridges reuse the shared request
executor, pinned transport, and authenticated dispatcher. The raw-response
bridge forwards the recovery owner's UUID to the existing private Auth boundary.
Enrichment's prepared-JSON bridge preserves serialization-before-UUID validation
and exact body bytes. Signing and scan-image inspection DTOs move unchanged to
`MediaStorageAPIModels.swift`. The account-bound encoded bridge preserves
signing's frozen body/transport UUID; raw PUT bridges reuse the private session
without adding Auth or replay. Queue manifest/task authority, live inference
attempt fencing, image repair, and avatar promotion remain caller-owned. Account
deletion uses two route-fixed value bridges for authenticated intake and
capability-only recovery. Its dedicated preparation receipt, strict
accepted/recovery receipt, status DTOs, and v2 preparation/commit payloads live
in `AccountDeletionAPIModels.swift`; three request-only DTOs remain private to
its endpoint file. Pure operation-specific receipt and proof/timestamp
validation live in `Decoding/AccountDeletionResponseDecoder.swift` and
`AccountDeletionRecoveryValidation.swift`. `Core/Network/Auth/` owns value-only
transition and lease models, presentation and transition-decision policies,
coordinators, `AuthRuntimeState` as the effect-free observable owner for
transition, generation, transition-analytics, exact-session lease/drain, and
local sign-out state, provider-neutral Auth-session bootstrap
snapshots/dependencies and coordination, lifecycle models, coordination, and
conditional deferred-event replay, provider-neutral OAuth models, identity-token
policy, shared sign-in workflow/completion coordinator, provider-presentation
admission coordinator, and focused Apple/Google presentation, mapping,
nonce/controller, diagnostics, and OAuth SDK-session Services—including fallback
callback URL installation—the fallback authentication-callback dependency
package, coordinator, and live diagnostics, the sign-out single-flight,
account-deletion classification, and ghost-profile queue/error policy plus
dependency-injected deletion, purchase-safe sign-out phase sequencing and
stable/legacy recovery routing, stable/compatibility completion keyed by
destination, Auth generation, and transition owner, and Ghost durable
preparation plus completion keyed by target and transition owner. Fresh deletion
and recovery have separate coordinators over one narrow
local-state/exact-session dependency package. Suspended deletion results are
admitted only for the transition's exact expected session and generation;
deferred noncommit recovery revalidates the cached source before making marker
removal its final failable stage. The public-author refresh dependency package
and coordinator own exact transition refresh plus the keyed restored-session
Ghost-completion/refresh/publication sequence. The Apple credential-revocation
dependency/coordinator pair owns transition deferral, notification coalescing,
Auth-context generation, exact session/subject postflight, and retained lookup
task lifetime. That task keeps the coordinator weak across provider suspension,
and the live assembly captures the provider rather than the manager, so a late
callback cannot retain or mutate a released owner. Public-author refresh rejects
stale scheduling targets before replacement and cancellation before lease/remote
admission or after remote suspension. `AuthSessionLifecycleLiveProvider` retains
the SDK Auth stream/listener, maps SDK values into lifecycle events, and
composes transition-deferred exact-current-state replay; replacing its listener
also clears the replaced listener's replay obligation, and cancellation fences
the replaced operation's trailing credential effect. The focused bootstrap
service projects SDK sessions, classifies stable missing-session evidence, and
delegates cached/loaded reads plus anonymous sign-in to its sole `+Live`
adapter; bootstrap task lifetime and publication remain
coordinator/facade-owned. `SupabaseManager` retains that provider, the
historical-sync service, and local-sign-out coordinator, adapts bootstrap
identities back to the stable SDK `User` result, preserves the public provider
entry points, and supplies the coordinators with the runtime owner's current
transition projections plus Supabase session, exact-session registration
assembly, endpoint, logging, local cleanup, journal, proof-retirement, and
public-author event effects. The historical-sync service's `+Live` adapter is
the reviewed Auth owner of `AppDIContainer.shared` for offline-queue context and
scan-repository composition. Apple and Google provider admission/presentation
and completion share extracted coordinators; provider callbacks and
provider-value mapping live in focused Auth Services. Those providers expose
separate zero-argument production and nonoptional injected-dependencies
initializers. A separate typed Auth service validates the Apple registration
receipt, while its `+Live` adapter alone owns the Function DTOs and invocation.
Before installing a session, the completion coordinator requires the credentials
to match the provider encoded in the owned transition, requires the Apple
credential-registration effect, and rejects that Apple-only effect for Google.
Cancellation is checked after every suspended OAuth completion phase; the
replacement workflow distinguishes installed, failed, and cancelled outcomes,
and an already-mutated cancelled transition is admitted only to terminal
cleanup. The existing `MerianApp.onOpenURL` task remains the fallback URL's
async caller; its coordinator creates no task, stops after preflight
cancellation, rejects adoption when sign-out begins during SDK installation, and
keeps exact-session fences around purchase and entitlement completion.
Already-cancelled deletion or sign-out requests cannot open a transition;
purchase-safe sign-out rechecks cancellation between every identity phase, and
recovery drains account-bound work before reading the anonymous session. A
returned one-use preparation proof is always persisted before cancellation can
stop subsequent Auth work; a cancelled or superseded completion cannot
synchronize target evidence or remove proof. `Core/Security/GhostProfileMerge/`
owns the exact handoff/queue models, legacy migration, fail-closed validation,
device-only Keychain persistence, byte verification, verified removal, and the
typed remote service whose live adapter alone owns the Supabase Function DTOs
and calls. `Core/Security/PurchaseIdentity/` owns the purchase-principal domain
and wire values, deterministic policies, capability and resolver-state Keychain
stores, secure random generation, typed remote services, and exact legacy/stable
journal models and persistence. Its route-specific live adapters alone import
Supabase and issue the four resolver operations or four compatibility operations
across three live SDK invocation paths; `PurchasePrincipalResolver` remains the
source-compatible orchestration facade. Other wire-model owners stay unchanged:
enrichment responses remain hand-written in Core AI, while survey requests
remain Settings Feedback-owned. `Core/Network/Transport/` owns stateless HTTPS
endpoint construction, unavailable-route/error classification, retry allowlists
and account binding, and value-only Auth-recovery decisions. Its request-scoped
`AuthenticatedRequestExecutor` applies those policies and injected Auth,
entitlement, and consent effects across one logical request.
`PinnedNetworkTransport` owns the single configured session and TLS delegate;
its lock-backed first-use path prevents concurrent callers from constructing
multiple production sessions, and its host policy matches only `supabase.co` and
true subdomains. A matching server-trust challenge cancels when its certificate
chain is unreadable, fails platform validation, or is unmatched instead of
falling through to ordinary ATS. `AuthenticatedTransportDispatcher` owns each
attempt's Auth/session fence and injects that same session transport. The client
façade owns neither implementation nor a second session. Publication, recovery,
and restore orchestration do not acquire another transport; record-recovery
polling propagates caller cancellation without resuming a later status probe.
The closure audit leaves the façade at 545 lines after removing an unused
self-recursive public-GET helper. Shared legacy and scoped URLProtocol fixtures
now have a dedicated
`MerianTests/Core/Network/NetworkTransportTestSupport.swift` owner instead of
living in the aggregate client suite. See the
[Core Network guide](Merian/Core/Network/README.md) for the endpoint, transport,
and mirrored test boundaries.

`CoreNetworkIntegrationArchitectureTests` owns the cross-slice source guard: it
freezes the 19 endpoint owners, prevents duplicate aggregate entry points,
enforces the 600-line ceiling across extracted Auth, Endpoint, Inference, Media,
Recovery, and Transport owners, and applies the same ceiling to the client
façade. It freezes ownership of the exact sixty-one Auth paths, relocated
declarations and helper functions—including the effect-free observable runtime
owner for transition, generation, analytics-token, exact-session lease/drain,
and local sign-out state; the focused live listener/current-state and
historical-sync owners; the live listener's generation/context/transition-
observation order and replacement cleanup; the bootstrap dependency/coordinator
pair plus SDK service/live adapter and diagnostics owner; the recovery
dependency/coordinator pair and local-sign-out coordinator with its colocated
dependency boundaries; the one shared task-free Supabase Auth service/live
adapter and diagnostics owner for OAuth, recovery, and local sign-out; and the
lifecycle model/dependency/coordinator plus the conditional replay owner; the
OAuth model, token policy, workflow, completion dependency package/coordinator,
provider-admission dependency package/coordinator, focused live-provider
Services, and the Apple credential-registration service/live-adapter pair, plus
canonical metadata mapping and sole callback-URL SDK installation; the fallback
authentication-callback dependency/coordinator/live-diagnostics split; the
shared deletion dependency package, separate fresh/recovery coordinators,
purchase-safe sign-out workflow, route, source-handoff, and destination-handoff
coordinators plus dependency boundaries, the Auth handoff-journal adapter, the
Core Security preparation owner, ghost-merge policy/sequencing, the
public-author refresh and Apple credential-revocation dependency/coordinator
pairs, and former helper names—the ten explicit main-actor task owners,
provider-neutral SDK/singleton exclusion, and narrow provider-service exception.
Its live-owner inventory permits `AppDIContainer.shared` in the
historical-session `+Live` adapter for its two documented composition effects
and rejects nullable Apple/Google provider dependencies. It also freezes the
ghost-merge and purchase-handoff model/store owners in Core Security. For direct
anonymous provider linking, it requires SDK readback, same-UUID
permanent-session admission, transition adoption, and exact-session validation
before durable ghost-merge recovery retirement. It also requires exactly one
endpoint owner for every safe-read or idempotency-aware replay classification
and exactly six Transport owners: three stateless policies, the request-scoped
executor, the pinned session, and the authenticated dispatcher. The guard
freezes sole-session injection and keeps per-attempt Auth leasing out of both
the façade and executor while the executor owns bounded retry state and applies
ordinary versus transition-owned refresh through injected closures. Its joined
live-manager checks also require listener and anonymous-bootstrap continuations
to retain the exact manager-published user, nonexpired SDK session, and captured
Auth generation after suspension. A signed-out lifecycle event repeats that
fence after purchase cleanup, and an event deferred by an active transition is
replayed only from an exact current SDK snapshot after the transition finishes.
Stable and compatibility purchase-continuity completion must retain that session
plus valid transition context and cancellation state through proof removal;
Google provider return, direct provider linking, and the extracted OAuth
replacement workflow must retain cancellation fences before mutation and after
every suspended completion phase. A successful live SDK install records both the
mutation and exact target transition expectation before cancellation can escape,
while an already-mutated cancelled session reaches exact-target, fail-closed
cleanup; and restored-session public-author work must use coordinator-owned
target-account and task-ID compare-before-clear ownership. The sole live
event/logging adapter remains outside the provider-neutral Auth package. The
same guard freezes the provider-to-transition match and
Apple-required/Google-forbidden credential-registration configuration before
session installation. `get-filtered-discovery-feed` remains a documented backend
function but is intentionally absent from the iOS replay set because the app has
no endpoint owner or caller for it. See the
[integration-audit contract](Merian/Core/Network/README.md#core-network-integration-audit).

## Core Data Offline Sync Ownership

[Core Data Offline Sync](Merian/Core/Data/OfflineSync/README.md) owns durable
scan admission, staging, retry, background URLSession recovery, and inference
replay. Its focused `Models`, `Policies`, `Coordinators`, `Persistence`, and
`Services` files separate Sendable values, stateless decisions, process-local
task ownership, SwiftData helpers, diagnostics, cloud deletion, collection sync,
media-upload preparation/dispatch/completion, queued-scan extraction, queue
maintenance, capture admission, funding, Field Trip progress, inference replay,
background inference, and background transfer. Background Inference separates
actor-independent response/status policy, exact process-generation lifecycle,
generation-fenced request dispatch, accepted task completion, injected
response-to-persistence finalization, and delayed watchdog probing/task
retirement with compare-before-clear replacement-owner preservation. Background
Transfer separates lock-protected terminal tracking, exact-session lease
quiescence, private terminal owner validation/adoption, main-actor terminal
routing, and nonisolated URLSession delegate routing from the remaining result
pipeline. `OfflineQueueDurability.swift` retains live durable mutations and
retry orchestration.

Collection sync keeps durable job/revision and single-flight state on
`OfflineQueueManager`, while `CollectionSyncService` owns the injected
account-lease transaction. A focused database-actor extension projects immutable
desired-state snapshots and revalidates tombstones in a fresh context at commit;
`MerianNetworkClient+Collections.swift` alone maps those snapshots to the
unchanged `/sync-collections` wire contract. This prevents a collection
reactivated during an in-flight request from being purged locally. Its
classified-401 path returns to the durable retry owner instead of starting Auth
recovery from inside the exact task and account lease that recovery must drain.

The root `OfflineQueueManager` retains stored state and background-session
construction; the focused inference-completion extension owns accepted result
and transport-failure processing plus generation-tagged completion-lock
teardown. `BackgroundInferenceFinalizationService` owns durable-generation,
shared-response, and fresh-actor persistence ordering without awaiting
`InferenceProcessingActor` under the per-scan lock. The watchdog extension owns
exact-generation status probing and background-task inspection/cancellation, the
recovery extension owns server-result hydration, durable recovery, and retryable
server-status persistence, while the retry extension owns general
transport-retry preflight/persistence and server-poll execution. The former sync
aggregate is eight focused service files under `CloudDeletion`, `Collections`,
and `MediaUpload`; media-upload completion and generation fencing have explicit
owners, while queued SwiftData rows map to inference snapshots under
`Persistence`. Queue count, tombstone, flush, deletion, and purge behavior is
split under `QueueMaintenance`. The former queue aggregate is split under
`CaptureAdmission`, `Funding`, `FieldTripProgress`, and `InferenceReplay`; retry
mutations remain with `OfflineQueueDurability`. These ownership splits change no
SwiftData schema, payload, endpoint, queue state, retry, or task-description
contract. The foundation, sync, queue-maintenance, and admission/replay
architecture suites freeze declaration ownership, focused-file/import
inventories, private state, durable ordering, responsibility boundaries,
mapper/goal-hint consumer allowlists, mirrored test ownership, retired
aggregates, and the 600-line review ceilings. The admission/replay guard also
keeps file-store access inside capture enqueue and freezes the exact focused
test identities plus their serialized offline-queue process-state leases. The
background-transfer guard freezes delegate and private terminal-routing
ownership, tracker, lease-state, rejected-retirement and inference-completion
consumers, synchronous terminal registration, durable-before-cancel Auth
quiescence, preservation of the active inference generation when durable
retirement fails, and exact process-generation completion when it later
succeeds. The background-inference guard freezes
policy/lifecycle/dispatch/completion/finalization/watchdog/recovery/retry
ownership, imports and consumers, generation revalidation, completion
persistence ordering, stale callback fencing, post-task-enumeration
probe/generation revalidation, exact probe/task retirement ordering, durable
dispatch ordering, the hard preparation deadline that cancels and ignores late
non-cooperative work, caller-cancellation identity, durable-wake restoration
without an intervening suspension in both retry paths before post-save
poll/generation revalidation and optional process-local replacement, shared
response preparation without a finalization-to-processing-actor hop, and the
600-line production-file ceiling.

## Core Data Database Actor Ownership

The [Core Data guide](Merian/Core/Data/README.md) is the canonical ownership
inventory for SwiftData actors. `BackgroundDatabaseActor.swift` now contains
only the `@ModelActor` declaration; focused sibling extensions keep collection
synchronization, pending queue selection and empty-media quarantine, upload
claim/staging/orphan recovery, durable background-account ownership, inference
lifecycle/retry persistence, live and offline scan finalization, shared
scan-record support, species metadata, and non-biological retention separate
behind the existing call-site names and persistence contracts. Queue selection
pages past delayed and locally blocked rows, preserves the existing funding-tier
order, fails closed when funding state is unreadable, and atomically revalidates
empty-media candidates before committing scan, job, and event attention state.
The upload-lifecycle owner contains only the durable
`.pending → .uploading → .staged` mutations and timestamp-fenced orphan release;
Media Upload and Inference Replay retain URLSession enumeration, network policy,
and orchestration. Claim and orphan-recovery batches roll back when their
matching durable-job lookup fails, while an absent legacy job remains supported.
The background-account owner contains only activation, current-owner validation,
candidate projection, and durable retirement. Its throwing scan/job reads
distinguish storage failure from absence. Activation creates an absent legacy
ingestion job in the same durable save, while persistence failures retain
private diagnostic context and fail closed. Background Transfer and Media Upload
retain Auth leases, URLSession task cancellation, and orchestration. The
inference-lifecycle owner contains durable eligibility, claims, retreats,
generation validation, telemetry, and timestamp-fenced orphan recovery; its
retry sibling contains general and server-result recovery retry commits. Their
throwing reads fail closed, genuine missing legacy jobs remain supported, and
orphan recovery acquires candidate persistence fences in stable ID order,
rereads durable eligibility through a fresh context after waiting, and loads all
candidate jobs before mutating the batch. Only stable scan IDs cross the fence
wait; no SwiftData model is carried across suspension. Background Inference and
the other Offline Sync services retain process state, scheduling, task/network
effects, and orchestration. The live-scan extension preserves the
visual/nonvisual save signatures and shares their
fence/media/replacement/rollback flow. The offline-finalization extension
accepts prepared domain data and owns only durable generation
validation/adoption plus the final commit. Shared actor-isolated helpers, the
stateless complete-record factory, and the injected ordered-media serializer
have separate owners. Foreground and background completion use one stateless
response-preparation service, avoiding both semantic drift and an actor
dependency cycle while the per-scan persistence lock is held. Unsupported queued
inference audio is rejected by upload preflight, quarantined by staged replay
and surviving upload callbacks, and refused again by the serialized inference
claim. The internal non-biological payload label is `mediaPaths` because it
carries image, audio, and video paths. That extension owns only erasure values,
bounded retention selection, and the atomic record/cloud-tombstone commit. Its
purge result distinguishes accepted erasures from rows actually deleted so
`ScanRepository` can drain files/tombstones without publishing a false library
mutation. Local file cleanup remains in `FileIOActor`. The focused extensions
contain no endpoint, authentication, file, or UI dependency. Mirrored behavior
suites preserve the persistence contracts, while architecture suites scan the
complete production and test Swift trees for sole method and test ownership,
cross-owner effect routing, exact selection/upload-lifecycle consumer ownership,
bounded actor-isolated retry-mirror use, and the 600-line review ceiling.

Historical hydration is split under
[`Core/Data/Database/HistoricalSync`](Merian/Core/Data/Database/HistoricalSync/README.md):
Models owns request values and unchanged PostgREST DTOs, Decoding owns
row-isolated scan-page decoding, Services owns the sole live Auth/PostgREST
adapter, and Persistence owns `HistoricalDatabaseActor` SwiftData work.
`ScanRepository` remains the main-actor ordering, pagination, lease-fencing, and
event orchestrator. The actor is created ad hoc per sync and streams one scan
page at a time. Its scan, collection, membership, and save boundaries throw:
storage failure aborts the current reconciliation instead of becoming an empty
successful result, targeted completed-result hydration maps local failure to
durable transient recovery, and cancellation rolls back before collection
pruning and commit. Historical insertion metrics include only rows with valid
timestamps that reached the successful save path.

## Core Image Ownership

[Core Data Images](Merian/Core/Data/Images/README.md) separates the shared
stateless `ImageDownsampler` from `LocalImageLoader` orchestration, decode
admission, external URL and retry policy, local scan-media recovery, and cloud
repair. Post-startup recovery-index registration uses a cancellation-aware
actor, fresh bounded SwiftData contexts, and two ordered passes so
scan-ID/media-order evidence across the whole library precedes timestamp
fallback. The process-local registry independently preserves that priority when
bounded callers interleave and admits or evicts a multi-image timestamp group
atomically. Direct filenames are reserved even without a rescued row. Recovery
revisions version cache/coalescing identities, and a shared Core UI modifier
reloads retained Scan, Explore, Profile, gallery, and composer images. Cloud
repair accepts only an exact local URL backed by direct filename or registered
strong evidence; timestamp guesses remain local display fallbacks. The injected
live adapters retain the existing network and app-event effects, while the
downsampler, pure policy, and recovery owners contain neither UI nor endpoint
calls. Focused behavior and architecture suites freeze bounded downsampling,
coalescing, recovery evidence, canonical single-flight repair, bounded
registration, imports, test ownership, retired Utilities paths, and the 600-line
production guard.

## Core UI Ownership

The [Core UI guide](Merian/Core/UI/README.md) is the canonical inventory for
cross-feature presentation primitives. Milestone feedback under
`Core/UI/Feedback` separates immutable models, pure identity/mapping policies,
the bounded FIFO presenter and host registry, scan-completion coordination, and
live adapters. The Core UI-wide integration audit moved Capture navigation,
Explore wrapping layout, Profile stats/plan presentation, Insight card entrance
and candidate confirmation, and the shared notification-permission sheet to
their narrowest feature or domain owners. Core UI views and modifiers now
receive milestone haptics through `MilestoneToastFeedbackDependencies`, while
Capture and Insight live adapters project haptics and hardware eligibility from
their injected dependency graphs. Only
`Services/ScanMilestoneDependencies.swift` may resolve Field trip networking,
authenticated account identity, Offline Sync, SwiftData-backed achievement
calculation, feature availability, or `GamificationManager`;
`ScanMilestoneCoordinator` consumes those effects through its small injected
dependency value and injected `AppEventSending` capability. `AppDIContainer`
explicitly selects live adapters, while previews and tests can build isolated
graphs. `CoreUIArchitectureTests` prevents feature-owned declarations or direct
live-service resolution from returning, pins current live lookups to their
explicit image-loading, share-presentation, or milestone adapter, and keeps
every production Core UI file at or below 600 lines. Cross-feature loading now
has one render-only owner at `Components/Loading/GlowPulsingSkeletonView.swift`,
and the single UIKit activity-controller bridge is
`Services/ShareSheetPresenter.swift`, including the actor hop that delivers
dismissal callbacks on the main actor. Features still own loading state,
prepared activity items, and playback or overlay lifetime. The unused shimmer
API and former Utilities share helper are retired. The legacy production and
test aggregates are retired without changing payloads, persistence, routes,
retry semantics, layouts, or visible feedback.

## Core Preferences Ownership

[Core Preferences](Merian/Core/Preferences/README.md) owns the observable
`AppSettings` boundary plus the small Explore-share and field-note bridges and
the preferred-name legacy-cleanup/account-metadata store. It also owns the
exact, read-back-verified account-cache inventory composed into accepted account
deletion. These extracted owners remain free of SwiftData, Supabase, networking,
and app-container lookup. Audited repairs persist the normalized 1...3 grid
count and prevent account-derived caches or process-local
gamification/badge/image projections from surviving the complete active-schema
purge. Badge refresh is generation-fenced across deletion; device preferences
and deletion recovery fences remain.

`Core/Preferences/UserDefaultsKeys.swift` owns the exact persisted-key registry.
The account-scoped SwiftData repository, conflict/resource policy, wire values,
local interruption-recovery owner, injected PostgREST client, and single-flight
coordinator live in
[Core Data/Species Preferences](Merian/Core/Data/SpeciesPreferences/README.md).
Only the narrow live client resolves Supabase. V51 discards unowned V50/defaults
values instead of assigning them to the next account; pending deletes,
freshness, and diagnostics are account-qualified. Scientific-name keyset paging,
a 1,000-species union bound, the server-aligned 200-character limit, monotonic
tombstone acknowledgement, and a post-upsert local refetch close pagination,
interruption, and mid-flight edit races. Account-deletion recovery models and
local stores live in
[Core Security/Account Deletion](Merian/Core/Security/AccountDeletion/README.md),
and `Core/Security/KeychainKeys.swift` owns the exact secure-key registry.
Mirrored Preferences, Species Preferences, and Security tests enforce these
dependency, race, purge-inventory, installed-key, and 600-line boundaries
without treating the defaults store as durable value or server authority.

## Core Notifications Ownership

[Core Notifications](Merian/Core/Notifications/README.md) owns system
authorization, APNs token/remote-registration lifecycle, local notification
scheduling and typed route parsing, foreground presentation policy, and the
aggregate app-icon badge. The stable `PushNotificationManager` and
`AppIconBadgeCoordinator` facades preserve existing callers while focused
Models, Policies, Services, Coordination, and Badges owners isolate
deterministic rules, operating-system effects, endpoint adapters, and mutable
task state.

Remote registration retains the newest settings/token/account snapshot admitted
during an active request. The account scope is a local coalescing fence and
never enters the payload. Local inference deduplication commits only after the
system accepts the notification request, so failed scheduling remains retryable.
Badge loads remain single-flight, reuse only successful counts for ten seconds,
and reject stale results after local mark-read or account cleanup with a state
generation. Native permission polling defers while an authorization prompt is
active, and permission completion does not wait for remote synchronization.
Mirrored Core Notifications tests enforce these concurrency contracts, the
stable facades, live-effect ownership, retired Hardware aggregates, and a
400-line production ceiling. Explore's in-app activity feed remains
independently owned by `Features/Explore/Notifications`.

## Core Consent Ownership

[Core Security Consent](Merian/Core/Security/Consent/README.md) owns the exact
policy/evidence values, source-compatible durable models, deterministic
authority and ownership policies, and the focused consent cloud boundary.
`ConsentRemoteService` maps immutable receipt/event values and validates causal
append outcomes through initializer-injected closures. It rejects malformed
present rows and requires exact immutable receipt/event read-back matches; only
its live adapter performs direct PostgREST table or RPC calls.
`ConsentLedgerRepository` owns decoded local state and verified ledger/journal
persistence over the existing raw store, including recovery and account
rebinding. `ConsentSynchronizationMergePolicy` owns value-only remote evidence
upsert and authority derivation. `ConsentSynchronizationCoordinator` owns
synchronization task identity, coalescing, generation cancellation, and
retention and exact drain of every outstanding handle, including superseded and
previously invalidated work. It also owns pending-evidence push order,
authoritative fetch, and verified merge sequencing without direct singleton
access. `RequiredConsentRestorationCoordinator` owns the restoration state
machine, retry budget, UUID-keyed outstanding-task retention,
compare-before-clear completion, cancellation snapshot and exact drain, manual
retry admission, and account, SDK-session, generation, and caller-cancellation
fences through injected effects. A canceled timer cannot regain admission if a
manual retry reuses the same attempt number. `ConsentManagerRuntime` composes
the focused owners and their narrow facade callbacks.
`ConsentCloudSessionCoordinator` owns account-work lease and session adoption,
scheduled synchronization, Ghost rebinding, and inference cloud admission; only
its live dependency adapter resolves Supabase for those workflows. Inference
snapshots complete bindable unowned evidence before session adoption and
revalidates cancellation, lease ownership, and synchronization generation after
remote work before it may interpret missing cloud proof; a stale authorization
context never persists reapproval. `ConsentMutationService` owns local evidence
construction and privacy-sensitive write ordering; its separate live adapter
alone reads the process clock, generates UUIDs, and resolves `Bundle.main` app
metadata. `ConsentStateProjectionPolicy` owns derived gates and SDK permission
projection. `ConsentManager` remains the sole observable facade and retains
mutable presentation state, lifecycle entry points, PostHog application, merge
publication, and the Auth-transition drain. `ConsentRealtimeCoordinator` owns
channel/listener/retry lifetime through injected effects. Explicit stop,
listener completion, and coordinator deinitialization converge on one coalesced
removal operation; deinitialization starts cleanup even if a listener suspension
ignores cancellation. Started removals remain retained until exact completion,
and the manager drains them with synchronization and restoration before Auth
session replacement. Its live adapter is the sole analytics-consent Supabase
Realtime owner. The extraction changes no API, persisted ledger, Keychain,
provider, or release contract.

## Core Purchase Identity Ownership

[Core Security Purchase Identity](Merian/Core/Security/PurchaseIdentity/README.md)
owns the iOS purchase-principal boundary. Models map exact resolver responses
into validated domain values; policies own fingerprinting, monotonic intent,
fallback, bounded fractional/whole-second server timestamps, encoding, and
rotation-secret decisions; injected stores own the device-only capability,
stable-activation fingerprint, intent generation, and sign-out journals. An
invalid activation fingerprint is rejected before secure persistence. The
closure-backed remote services keep typed operations separate from their
route-specific live Supabase adapters and private request payloads.
`PurchasePrincipalResolver` composes those owners without importing Supabase or
Security. The provider-neutral session coordinator owns the active binding,
last-linked user, and keyed resolution task, and updates the last-linked cache
only after final caller admission. Every resolution rereads the durable handoff
journals and republishes the result to RevenueCat's synchronous mutation fence;
an unreadable journal publishes pending state before the attempt fails closed. A
differently keyed attempt cancels the older resolver task, whose late result
cannot replace the newer binding or task state. The foreground-readiness
coordinator owns account-work admission, journal recovery, entitlement order,
and the final exact-session fence. The typed legacy-profile service separates
the established `users` lookup from both coordination and presentation. The
task-free `PurchaseIdentitySessionLiveService` owns legacy attribute precedence
and assembles provider, resolver, entitlement, and diagnostic boundaries; only
its `+Live` adapter acquires RevenueCat, `EntitlementManager`, the resolver,
legacy profile service, Supabase client, and logger. The manager is the
service's sole lifetime owner, and deferred legacy linking or entitlement
refresh fails closed after that owner is released.
`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutCoordinator.swift` owns
Auth-transition admission; stable/legacy and installed-proof routing; exact
anonymous retry; recovery-only reset admission; and fail-closed journal
verification. `PurchaseIdentitySourceHandoffCoordinator.swift` owns aggregate
fail-closed journal projection, exact-session source preparation, exact-source
proof abandonment, and failed-attempt source restoration through injected
boundaries. Cancellation after compatibility preparation's final SDK-session
read cannot report success or discard its already-durable recovery proof.
`PurchaseIdentityHandoffAuthJournal.swift` alone translates the Core Security
store's load/persist failures into established Auth errors while preserving
verified-removal diagnostics. `PurchaseIdentityHandoffCoordinator.swift` owns
stable/compatibility completion, single-flight task lifetime keyed by
destination, Auth generation, and transition owner, session/cancellation fences,
and proof removal. Core Security's
`PurchaseIdentityHandoffPreparationCoordinator.swift` owns the stable
`preparing` and `prepared` durability checkpoints and compatibility-proof
mapping without acquiring Auth, SDK, Keychain, or task authority.
`AuthSessionBootstrapCoordinator.swift` owns reusable-session admission and the
single-flight for existing-session resolution or anonymous creation. It stores
the task's complete transition token and shares only while that token remains
the exact active owner; an ownerless caller can join only the active
anonymous-bootstrap token. Cancellation before admission or during sign-out
waiting stops before account-work or SDK-session effects. The coordinator drains
account-bound work, creates an anonymous identity only for stable
missing-session evidence, and revalidates session publication after purchase
readiness, with a fresh cancellation fence before returning either identity.
`SupabaseManager` retains the live SDK session/error adapters and its public
SDK-typed entry point. For ordinary purchase readiness it supplies the focused
live service only with Auth state, exact-session/account-work, and durable-
handoff closures. `AuthSessionRecoveryCoordinator.swift` owns ordinary and
transition-owned exact-session refresh, anonymous recovery, and terminal local
cleanup with account-work, cancellation, purchase-handoff, and post-suspension
session fences. Its explicit mutated-OAuth entry policy lets a cancelled owner
finish only the cleanup made necessary by its prior SDK session mutation.
`AuthSessionLifecycleCoordinator.swift` owns Auth-session projection plus
purchase/entitlement/historical-sync admission and signed-out postflight.
`AuthLifecycleReplayCoordinator.swift` owns one replacement-safe task that
replays only an SDK event deferred by an active transition. Its live lifecycle
dependencies capture `SupabaseManager` weakly, so suspended synthetic replay
cannot retain the facade past teardown. When the listener observes an
accepted-deletion cleanup barrier, it clears the published Auth session,
purchase-principal binding/readiness, and the local server-verified entitlement
projection before recovery continues.
`PublicAuthorIdentityRefreshCoordinator.swift` owns transition-owned and keyed
restored-session public-author refresh behind injected exact-session and
account-work fences. `AppleCredentialRevocationCoordinator.swift` owns the
generation-fenced, overlap-safe credential lookup task;
`AppleCredentialRevocationLiveProvider.swift` alone owns its Apple framework
notification and state lookup. The lookup task retains the provider, not the
manager or coordinator, across callback suspension. Its terminal-clear boundary
rechecks the exact captured Apple identity and absence of a replacement
transition; recovery then repeats its expected/current-session check after
account-work quiescence and reports whether cleanup completed, changed context,
or was deferred by purchase continuity. Context changes retain the notification
for stable revalidation; purchase-handoff deferral retains it without a hot
lookup loop, and the centralized aggregate handoff publication resumes it when
that fence becomes false. A context generation changed while clear was suspended
replays after the deferred result instead of losing an earlier lifecycle wakeup.
Clear diagnostics follow completed cleanup only. The task-free
`SupabaseAuthSessionService` centralizes request-scoped OAuth, recovery, and
local-sign-out SDK adaptation; its `+Live` companion alone performs those Auth
calls and retains their privacy-safe recovery/sign-out diagnostics. The recovery
coordinator owns terminal-clear sequencing. The local-sign-out coordinator
separately owns ordinary and account-cleanup single-flight task lifetime and
sequencing. `SupabaseManager` retains the SDK stream/listener, local-sign-out
coordinator, and live SDK continuation tasks, records transition-deferred
listener events for conditional replay, launches the generation-fenced
historical-sync task, and owns provider SDK composition, public-author live
effects, and Auth dependency assembly. Purchase Identity's live adapter owns
ordinary RevenueCat/entitlement effect acquisition. The recovery coordinator
rejects cancellation before transition admission and after each suspended
readiness phase; terminal local clear also preserves a pending purchase handoff
and, after SDK sign-out begins, still invokes observable-state, secure-marker,
analytics, and purchase-identity cleanup if the SDK call fails or cancellation
arrives. The request executor independently stops a cancelled `401` chain before
reset or local-session cleanup. The split changes no endpoint, payload,
response, Keychain key, fallback, provider, or navigation contract.

## Core RevenueCat Ownership

[Core Security RevenueCat](Merian/Core/Security/RevenueCat/README.md) owns the
source-compatible value models, typed legacy subscriber-attribute registry, and
deterministic identity, access, offering, verification, provenance, and privacy
policies. Its provider-neutral observable identity coordinator owns requested
and linked identity, account/generation fencing, serialized task lifetime, and
stale-commit rejection through injected closures. `RevenueCatManager.swift`
remains the sole live SDK facade and retains provider calls, paid-state
projection, offering refresh, purchase/restore, subscription management, and
fixed-message logging. The split changes no product identifier, App User ID,
subscriber attribute, provider behavior, wire contract, or persistence schema. A
follow-up concurrency fix makes a monotonic handoff fence dominate account
grants captured by older suspended identity work; only an exact binding begun
after that fence may commit grants once the handoff clears. Mirrored manager,
coordinator, and architecture tests lock behavior, dependency confinement, and
the final 600-line live-manager ceiling.

## Onboarding Ownership

[Onboarding](Merian/Features/Onboarding/README.md) owns the first-run Welcome,
Camera, Location, and Ready sequence plus the Ready surface selected for a
returning user after authoritative consent restoration. Shell Services resolve
the narrow live settings, consent, telemetry, queue recovery, and hardware
animation adapters; the observable state owner only sequences steps and
completion. `MerianApp` injects the exact app-scoped managers used by the root.

Steps own copy, layout, bindings, accessibility, and UI-only consent projection.
Native camera and location requests remain in `Permissions`, and Core Security
retains durable consent, account restoration, and provider-admission authority.
The one-shot location adapter returns its nonisolated delegate callback to the
main actor before reading authorization state; the shell then submits the source
step to the view model's duplicate/late-completion fence. Feature tests mirror
the Onboarding boundary, while the Core consent suites stay with their security
owner.

## Field Chat Ownership

[Field Chat](Merian/Features/FieldChat/README.md) is a cross-feature product
owner because Insights, Explore, and Species Dictionary all present the same
private conversation experience. Its Models, Services, ViewModels, Views, and
grouped Components separate deterministic presentation, live endpoint/effect
adapters, asynchronous state, and rendering.

Only Field Chat Services resolve the live network client, haptics, telemetry,
clipboard, clock, or request-ID factory. Host features own eligibility,
entitlement, navigation, and their presentation slot; Core Network owns Codable
DTOs, the shared Field Chat endpoint extension and stateless response decoder,
and private transport. Stable `InsightChat...` type names remain compatibility
names and do not place the shared implementation under Insights.

## Scans Ownership

Scans is composed from product-area owners rather than one root implementation:

- [Shell](Merian/Features/Scans/Shell/README.md) owns the root record and
  collection SwiftData queries, typed navigation stack, tab/pager state, and
  root presentation.
- [Library](Merian/Features/Scans/Library/README.md),
  [Collections](Merian/Features/Scans/Collections/README.md), and
  [Map](Merian/Features/Scans/Map/README.md) own their respective product
  behavior and receive prepared records or value snapshots from the Shell.
- [Non-Biological](Merian/Features/Scans/NonBiological/README.md) derives its
  projection from the Shell's timestamp-sorted records and owns its mutation
  orchestration, but it does not mount another persistence query.
- [Shared](Merian/Features/Scans/Shared/README.md) owns the Scans-only grid,
  queued-row value policy, and single-delete interaction shared by multiple
  Scans product areas. Cross-feature thumbnail and empty-state rendering lives
  in `Core/UI`.

`ScanThumbnail` delegates media work to the Core UI loader service, whose
post-suspension cancellation checks prevent cache-filling work from publishing
into a reused tile. Its task identity includes source, policy, target-size,
placeholder, and relevant connectivity inputs. Scans queued-row and Insight
snapshots share `ScanQueueState.isManualRetryEligible`; mutation owners still
re-fetch and revalidate the live row before changing durable state.

For bulk non-biological deletion, view state supplies immutable candidate
snapshots while the focused
`BackgroundDatabaseActor+NonBiologicalRetention.swift` extension remains the
commit-time authority. It re-fetches each ID and skips a row that has since
become biological before any record, local-path, or cloud-deletion mutation is
accepted. For automatic retention, accepted missing-row cleanup is reported
separately from actual row deletion: the former still drains files and cloud
tombstones, while only the latter publishes `scanLibraryChanged`.

## Profile Ownership

Profile is split by user-facing responsibility:

- [User Profile](Merian/Features/Profile/UserProfile/README.md) owns the visible
  identity card, local stats and achievements, persona and terrarium
  presentation, and the signed-in user's published scans.
- [Settings](Merian/Features/Profile/Settings/README.md) owns preferences,
  export, resources, and account actions. Its root Models, Services, ViewModels,
  Views, and grouped Components separate presentation from live side effects.
  Plan and Feedback mirror that full shape, Notifications uses
  Models/Services/ViewModels/Views, and Changelog remains a local Models/Views
  catalog.
- `Profile/Shared` owns account and public-identity state consumed across
  Profile product areas. UserProfile view models depend on narrow live adapters
  rather than resolving shared managers or endpoints in views.

Within UserProfile, `Models`, `Services`, `ViewModels`, `Views`, and grouped
`Components` define the ownership boundary. `ProfileDatabaseActor` prepares
immutable stats and achievement projections off-main. Its post-inference actor
is cached only for the exact `ModelContainer` identity, and `calculateAwards()`
refreshes the value projection before every evaluation so in-place inference
updates cannot reuse stale fields. Avatar preparation and upload are
request/account fenced and consult the view's live typed-presentation slot
before publishing a preview or error.

Within Settings, closure-based Services are the only owners that resolve
endpoints, Supabase SDK writes, notification authorization, platform actions, or
RevenueCat actions. The Profile Shell composes the account-fenced geoprivacy and
hardware-reconciliation adapters that require its environment-owned managers;
other Settings state owners use their subarea's narrow default live dependency.
Observable state owners coordinate lifecycle operations, while leaf views retain
navigation and other UI-only timing. A feature test enforces this boundary and a
600-line production-file ceiling.

## Species Dictionary Ownership

Species Dictionary has two vertical product areas and one cross-surface model
boundary. The concise ownership map lives in
[Species Dictionary](Merian/Features/SpeciesDictionary/README.md):

- [Catalog](Merian/Features/SpeciesDictionary/Catalog/README.md) owns Explore
  Identify/Species overview, category search, pagination, and region browsing.
- [Detail](Merian/Features/SpeciesDictionary/Detail/README.md) owns the public
  species reference page, reference gallery, share action, and Community
  sightings.
- `Shared/Models` owns the route/entry-point values, taxonomy bridge, and public
  reference-image labels/attribution consumed by more than one Dictionary or
  Explore surface.

Within Catalog, Models own normalized browse selections and page requests plus
typed routes, Services alone resolve the live endpoint, cached image loader,
geocoder, and map snapshotter, and generation-fenced ViewModels own
catalog/overview/map loading. Views retain search, refresh, navigation, and
presentation timing while recording a changed selection before the search
debounce; grouped Components render without direct networking or concrete
singleton lookup. Codable wire DTOs remain in
`Core/Network/SpeciesDictionaryAPIModels.swift`. Core Network also owns strict
schema/identity validation and the bounded detail/stats memos, while Explore
Shell owns the navigation stack, Identify/Species selection, and the overview
model's lifetime for one Explore presentation. Catalog's overview model reuses
successful same-country content for five minutes on navigation and keeps stale
content visible during refresh; closing Explore releases it. See the
[overview lifecycle contract](../../docs/features-and-hardware/16-species-dictionary.md#ios-catalog-ownership-and-request-lifecycle).
Mirrored feature tests enforce those boundaries, cross-selection race handling,
and a 600-line production-file ceiling.

Within Detail, platform-neutral Models own request, state, share, presentation,
telemetry, and hero-edge policy; Services alone resolve the live dictionary and
Community endpoints, telemetry, entitlement, haptic, Explore, and Field Chat
dependencies; and generation-fenced ViewModels own page and Community loading.
The standalone shell and shared content View retain navigation, presentation,
scroll, and lifecycle timing. Grouped Community, Content, Gallery, Loading, and
Shared components render without direct networking. Mirrored Detail tests lock
the latest-load and refresh/pagination contracts, endpoint adapters, ownership
boundaries, and the same 600-line ceiling.

## Capture Ownership

Reanalysis composes the original evidence, one additional media item, and a
reserved supplementary description. **+** stages text explicitly; **Analyze**
automatically includes a nonempty draft. Tray edits/removal supersede pending
supplementary text, and replacement sessions clear old evidence. This changes
local composition only, preserving existing request and queue formats. See the
[Describe behavior contract](../../docs/features-and-hardware/11-describe-and-voice-dictation.md)
and
[verification matrix](../../docs/development-guides/08-testing-strategy.md#reanalysis-description-verification).

[Capture Shell](Merian/Features/Capture/Shell/README.md) owns the ordered
Scan/Record/Describe pager, fixed capture chrome, root presentation and route
handoffs, external-import recovery, and the root capture state owner. Its
`Models`, `Services`, `ViewModels`, `Views`, `Modifiers`, and grouped
`Components` separate deterministic presentation policy from live work.

Only Shell Services construct the live network-client, URL-session,
connection-prewarm, remote-media, share/account lookup, keyboard platform, and
haptic adapters. `CaptureControlDependencies` specifically owns live entitlement
reads, capture-row keyboard dismissal, paywall telemetry, and semantic haptic
delivery. `CaptureNavigationDependencies` owns Explore badge loading, app badge
coordination, settings mutation, and navigation feedback; its focused view model
generation-fences overlapping refreshes and disappearance. The keyboard service
owns raw UIKit notification publishers and actions; the mounted modifier only
binds those publishers to SwiftUI state. Models remain deterministic. The view
model receives small closure-based dependencies and keeps mutable operation
tasks and one-shot handoff state inside an encapsulated owner with private
mutable storage. Views and components retain UI-only selection, scrolling,
focus, expansion, gesture/task cancellation, and dismissal timing and issue no
endpoint calls. The primary Capture action invalidates a pending press across
mode, inactive-scene, suppression, disablement, and disappearance transitions
before a stale release can dispatch; the matured visual hold reads Pro
eligibility at action time. Feature tests mirror this structure and enforce the
live-service and deterministic Models boundaries, feature ownership of the
control surface, press-lifecycle and badge-refresh fences, raw-notification
confinement, and a 600-line ceiling for production Shell files.

Capture-wide layout and interaction vocabulary lives in `Capture/Shared`,
including the fixed control-row geometry consumed by Shell, Scan, Record, and
Describe; the pure `CaptureMode` value; the haptic policy shared by Shell and
Scan; and the composing-center environment value supplied by Shell and consumed
by Record. Capture Shared Services also owns the bounded Vision focus detector
used by Scan, Shell imports, and Staging crop confirmation. The rendered control
row, flash control, native mode selector, workspace navigation, and their
deterministic presentation projections live in Shell. The selector converges
UIKit value-change and primary-action events through one binding guard, while
its installed-image snapshot prevents unrelated SwiftUI updates from rewriting
segment artwork during interaction. The cross-feature immutable `CGImage`
concurrency wrapper lives in `Core/Media` because Insights also consumes it.

The modality folders remain independent: `Scan` owns camera and video input,
`Record` owns audio presentation and interaction, `Describe` owns typed and
dictated observations, `Staging` owns the ephemeral mixed-media draft,
chronological nodes, image bundles, toolbar projection and components, injected
toolbar platform effects, and crop presentation, and `Submission` owns
conversion into the shared live/offline timeline, descriptors, projection, and
analysis pipeline. Shell owns staging mutation and disposable-file cleanup; the
toolbar consumes Staging order without deriving another sort.

[Capture Staging](Merian/Features/Capture/Staging/README.md) documents that
boundary and its paired Shell/Submission verification.
[Capture Submission](Merian/Features/Capture/Submission/README.md) separates
deterministic admission/media/goal policy and normalized payload values in
`Models`, narrow live admission/context/deferred-update adapters and telemetry
in `Services`, including the Submission-only LiDAR/Vision physical-size
estimator, and visual/nonvisual/Describe orchestration in
responsibility-specific `CaptureWorkspaceViewModel` extensions. Submission has
no view layer; Shell and modality views retain UI-only timing. The actor-backed
150 ms context race transfers only a sendable snapshot and bounds
environment-context waiting, not total dispatch preparation. A branch with no
foreground consumer cancels its captured lookup; only a timeout-losing lookup
remains for late enrichment, and that task retains the injected service and
bounded telemetry inputs rather than the workspace view model or full
display-image collection. The deferred-context service updates the durable local
queue before `/update-scan-context` and performs at most one remote retry after
500 ms; endpoint, transport, or task cancellation is terminal. View-model
extensions make no endpoint calls, mirrored tests enforce the ownership
boundary, and every production Submission file remains within the 600-line
review guard.

[Capture Scan](Merian/Features/Capture/Scan/README.md) separates
platform-neutral media requests/results, narrow live
camera/context/library/media/feedback adapters, bounded still/video/WAV
preparation, leased temporary media artifacts, cancellation-propagating detached
workers, generation-fenced still/pre-recording/recording tasks, and viewfinder
UI. Shell lifecycle and presentation transitions invalidate pending still and
pre-recording work while gracefully stopping an active video. Scan views perform
no networking or global service resolution; the preview uses its injected camera
owner for session and zoom state. Every production Scan file remains within the
600-line review guard. The reusable crop processor and crop UI live in
`Core/Media` and `Core/UI` because Profile also consumes them. The
presentation-only `CaptureFlashButton` and its complete control row live in
Capture Shell, which supplies camera mutation and feedback through injected
actions. Capture-specific editable image context remains in `Capture/Shared`;
Profile owns its own avatar-crop presentation value.

[Capture Record](Merian/Features/Capture/Record/README.md) separates immutable
audio presentation and layout policy, narrow manager/haptic adapters, idle and
scrub state, a thin full-screen view, and focused components. Only Record
Services reference the concrete `AudioCaptureManager` or shared haptic manager;
the Shell resolves those live dependencies and supplies the view with an
immutable snapshot plus closure actions. Core Hardware's focused recording and
review controllers own the engine/input-tap/WAV/DSP and player/task lifecycles
behind the stable `AudioCaptureManager` facade; shared raster construction and
the SwiftUI spectrogram surface live in `Core/Media` and `Core/UI`; and the
audio/video countdown badge lives in `Capture/Shared`. Capture controls retain
permission, record/pause/resume/stop/review actions, while Submission retains
queue-before-inference orchestration. Record views issue no endpoint calls, and
focused tests enforce the ownership boundary and 600-line production-file guard.

[Capture Describe](Merian/Features/Capture/Describe/README.md) separates pure
prompt, subject, tag-ranking, and text-composition Models; narrow live
preference/feedback/keyboard/speech Services; generation-fenced prompt and
lifecycle ViewModels; workspace-scoped Views; and layout-focused Components.
Describe views and components resolve no singleton or platform action, and view
models do not construct concrete hardware adapters. Focus, scrolling,
questions-sheet presentation, and tag auto-advance timing remain UI-owned. The
cross-feature `SpeechManager` lives in `Core/Hardware`, while the Describe
lifecycle observer crosses the composition boundary explicitly and the Services
layer converts that manager into initializer-injected speech, delay, and subject
inference closures. Pending speech startup is canceled and awaited before a
replacement may enter the shared manager, avoiding concurrent configuration and
teardown. Focused tests mirror these boundaries and enforce the 600-line
production-file guard.

[Core Hardware](Merian/Core/Hardware/README.md) keeps `CameraManager.swift` as
the observable facade and frame/depth/photo delegate bridge.
`Camera/Services/CameraSessionController` owns the lock-backed lazy capture
stack, serial queue, session lifecycle, output setup, active-device locking, and
hardware photo execution. The manager shares that controller's queue and lazy
session provider with `CameraVideoRecordingService`, which lazily owns the movie
output, audio/stabilization preparation, recording operations, file/delegate
handling, and no UI state. Constructing those owners resolves no AVFoundation
capture object; pre-preview controls and stop requests do not resolve the lazy
stack merely to perform a no-op. Required topology is preflighted before
mutation. The controller's hardware-lifecycle generation suppresses a queued
start callback after stop, while the facade's `CameraSessionPresentationState`
prevents either older start or stop publication after a newer intent; duplicate
starts or stops share the current presentation generation. `Camera/Models`,
`Camera/Policies`, and `Camera/Coordination` contain recording identities,
deterministic session/zoom/frame-rate and microphone/generation policy,
lock-owned photo and video request lifecycles, and the latest-state FPS
debouncer. Architecture tests freeze those dependencies and keep every live
camera owner at or below its focused line ceiling.

The same Core Hardware boundary keeps `AudioCaptureManager` as Capture Record's
stable observable recording/review facade. The focused
`AudioRecordingEngineController` owns the lazy engine, input tap, canonical WAV,
bounded PCM stream, DSP task, operation identity, temporary-file cleanup, and
recording lease. `AudioReviewPlaybackController` exclusively owns the review
player, playback tasks, generation/player fences, and playback lease.
`AudioSessionCoordinator` remains the process-wide token-aware session owner.
Core Media's reusable playback owner acquires no lease merely by mounting and
validates its exact lease before every audible start. Construction, session
effects, waits, and recording file effects are initializer-injected for
deterministic overlap and failure tests; feature views continue to receive only
Record's immutable presentation and narrow actions. Both controllers reject
stale activation, the recording controller rejects a second pending resume
before session activation, and teardown releases only a concrete exact lease.
Manager reset stops each active owner without crossing their lease or file
responsibilities.

Core Hardware also keeps `HapticManager` as the stable observable feedback
facade. It owns global admission, semantic trigger timing, diagnostics, and the
latest attempt projection. `Haptics/Models` and `Haptics/Policies` contain
platform-neutral values and deterministic decisions; `HapticFeedbackController`
owns UIKit generators and the identity-fenced lazy Core Haptics engine; and
`HapticAudioSessionAdapter` is the sole haptic owner of direct audio-session
inspection. Features should receive the manager or narrow semantic closures
rather than constructing feedback hardware.

`EnvironmentContextManager` likewise remains the stable observable facade for
Capture, Explore, Scans, Insights, and Profile. Its `EnvironmentContext/Models`
and `Policies` contain context values and deterministic location rules;
`EnvironmentLocationController` is the sole Core Location delegate and owns
authorization, live tracking, one-shot continuations, and exact-generation
timeouts. It rejects invalid fixes, separates accurate and coarse caches,
restores both hundred-meter accuracy and the 100 m distance filter after a
one-shot request, and fences cancellation and authorization revocation before
returning a location. The facade exposes retained cached coordinates only while
current authorization permits access and rechecks that authority after a
suspended one-shot request before starting geocoding or weather work.
`EnvironmentGeocodingService` is the sole `CLGeocoder` owner and shares bounded
placemark work between name and region projections; and
`EnvironmentWeatherService` is the sole WeatherKit owner. Platform effects and
the UI-test prompt gate are initializer-injected, while the facade retains
existing caller signatures and observable state.

## Insights Integration Ownership

[Insights](Merian/Features/Insights/README.md) defines the top-level result
boundary and its cross-feature extraction rules. Insight owns scan-bound
composition and presentation lifetime; Core owns reusable media export,
playback, gallery, card, toolbar, and feedback primitives; Species Reference
owns species-level reference presentation; and Field Chat owns shared private
conversation UI. The integration architecture suite locks that inventory and the
feature-wide 600-line ceiling.

## Insight Shell Ownership

[Insight Shell](Merian/Features/Insights/Shell/README.md) owns the root result
presentation, embedded navigation, completed/queued scan handoff, root
presentation hosts, and scan-bound state owner. Its `Models`, `Services`,
`ViewModels`, `Views`, `Components`, and `Modifiers` separate deterministic
presentation policy, live adapters, observable state, and UI-only timing.

`InsightShellDependencies` is the only Shell declaration that resolves live
network clients, authentication, repositories, feature access, app routing,
badge updates, or haptic feedback. Views and view-model extensions consume its
narrow initializer-injected closures and issue no endpoint calls. Presentation,
gallery, scrolling, focus, and dismissal timing remain view-owned. Mirrored
Insights tests enforce deterministic Models, the live-resolution boundary,
removal of aggregate source/test files, and a 600-line ceiling for production
Shell Swift files.

`Insights/Media/Carousel` applies the same product-area boundary below the
Shell: platform-neutral Models own presentation policy, Builders own page
assembly and availability, Services alone resolve audio/boost/telemetry/haptic
effects, and Playback owns AVPlayer observation lifetimes. Pages and Components
retain private mounted UI state. Carousel views perform no networking, stable
call-site initializers keep an optional trailing live dependency default, and
mirrored Media tests enforce folder ownership and the 600-line ceiling. The
cross-feature `AsyncLocalImageView` renderer lives in `Core/UI/Components`, with
its live loader adapter isolated in `Core/UI/Services`. The native pager, page
identity value, zoom host, pagination dots, and hero scroll-edge treatment used
by Insights and Field Trips also live in `Core/UI/Components/MediaCarousel`;
each feature supplies its own page ordering and reuse-key projection. Models
depend only on a platform-neutral selection-candidate contract, while the Core
pager preserves controllers for equal ID/reuse keys and invalidates its native
data-source cache when either identity changes.

The root view-model extensions are split into lifecycle, records, capabilities,
content presentation, media presentation, and presentation identity. Root view
extensions separately own content routing, chat actions, lifecycle attachment,
toolbar assembly, typed presentation hosts/bindings, and Explore composition.
Queued-completion polling is generation-, subject-, and cancellation-fenced, so
a dismissed or replaced destination cannot publish after its delay. Existing
call sites retain their initializer signatures; the optional trailing Shell
dependency defaults to the live adapter.

## Insight Content Ownership

[Insight Content](Merian/Features/Insights/Content/README.md) separates
platform-neutral fact, user-tag, queued-retry, and phrase policy Models; narrow
live repository, Supabase, scheduler, event, and feedback Services; contained
fact, tag, queue-operation, name-preference, and Content-action ViewModels;
composition Views; and grouped render-only Components. The Shell-owned
`InsightSheetViewModel` accepts an optional trailing Content dependency while
retaining its existing initializer call sites.

Views and components issue no endpoint calls or direct SDK writes. Queue polling
and the 350-millisecond delayed refresh remain view-owned, while the observable
queue state owner fences retry completion by request identity. Tag mutations
enforce the server's count, byte, and control-character bounds plus the iOS
64-character display limit. They restore their prior local value on save failure
and publish neither Supabase nor search-index effects before commit. Committed
cloud snapshots are serialized in mutation order and retain the authoring
account ID for the exact Auth work lease, preventing an older add from
overwriting a newer removal or crossing an account transition. Mirrored Content
tests enforce these contracts, rehomed presentation and mutation behavior,
Services-only live resolution, legacy-owner removal, and the 600-line
production-file ceiling. The display-only `NamePickerSheet` is shared from
`Core/UI/Components`; each feature retains persistence and feedback.

## Insight Field Notes Ownership

[Insight Field Notes](Merian/Features/Insights/FieldNotes/README.md) separates
platform-neutral prompt, edit, visibility-request, and feedback Models;
Services-only persistence, speech, visibility-action, and haptic adapters; an
observable editor plus the focused root-state extension in ViewModels;
composition Views; and Card/Editor Components. The Core-owned
[`FieldNotesRepository`](Merian/Core/Data/FieldNotes/README.md) remains the
shared local reconciliation boundary, while the Shell-owned
`InsightSheetViewModel` accepts an optional trailing Field Notes dependency for
deterministic persistence and feedback tests.

The editor view model owns draft, save, validation, and generation-fenced
dictation state. Views retain focus, keyboard, confirmation animation, actual
dismissal, and interactive-dismissal task timing. Explicit stop or automatic
speech termination invalidates the editor's session before a late transcript can
mutate the draft; automatic termination does not repeat shared teardown. A
replacement dictation waits for canceled startup teardown before entering the
shared `SpeechManager`, and a disappearing editor neither duplicates an active
save nor commits an unchanged draft. Existing screen and initializer signatures,
copy, accessibility, navigation, queued-scan identity, persistence, and Explore
visibility contracts remain stable. Mirrored Field Notes tests enforce those
lifecycle fences, Services-only live effects, the view networking ban, retired
aggregate paths, and the 600-line production-file ceiling; Core repository and
Sharing cache behavior remain in their domain test suites.

## Insight Identification Review Ownership

[Insight Identification Review](Merian/Features/Insights/IdentificationReview/README.md)
owns completed-result candidate confirmation and confidence explanation.
Candidate and Confidence each separate platform-neutral Models, Services-only
live effects, observable ViewModels, composition Views, and interaction-grouped
Components; `Shared` contains only their subject identity, haptic adapter, and
narrow SwiftData snapshot actor. Views retain gesture, animation, detent,
paywall, and actual dismissal timing, while all engine mutations, persistence
fetches, routing, Settings access, action-time entitlement checks, and
candidate-image live dependencies cross injected service boundaries. The
explanation view observes the environment-provided entitlement state only to
keep Pro presentation reactive.

Every nested action carries scan ID plus presentation generation and resumes
only from the owning sheet's real `onDismiss`; state owners refuse to vend a
pending action while its source sheet is still presented and clear it when the
current scan disappears. Generation-fenced refinement loads, modal ownership,
and cancellation/generation checks around local thumbnail decoding prevent stale
work or bindings from affecting a replacement scan. Dependency values are inert
by default for tests and previews, while the stable public view initializers
explicitly compose `.live`. Mirrored Identification Review tests lock those
lifecycles, presentation copy, Services-only live resolution, platform-neutral
Models, retired paths, and the 600-line production-file ceiling.

## Species Reference Ownership

[Species Reference](Merian/Features/SpeciesReference/README.md) owns the
reusable observation charts, habitat and GBIF map, taxonomy, lookalikes, and
fallback reference imagery presented by Insight, Species Dictionary, Explore
detail, and identification review. Its platform-neutral Models contain chart and
heatmap presentation policy; Services alone resolve SwiftData, network,
image-loader, haptic, and enrichment effects; generation-fenced ViewModels
publish asynchronous state; the chart composition root lives in Views; and
domain-grouped Components retain rendering and UI-only timing.

Changing or clearing a species or taxon identity invalidates older work, while
an already-cancelled valid load cannot claim generation ownership or clear valid
presentation. The observation-stat owner clears cross-species values before
awaiting replacements but retains the current values during a same-species
refresh. Immutable GBIF artwork crosses the service boundary through the shared
`Core/Media` `SendableCGImage`; the feature declares no unchecked sendability.
Mirrored Species Reference tests enforce those lifecycle rules, Services-only
live resolution, platform-neutral Models, retired aggregate paths, and the
600-line production-file ceiling.

## Insight Sharing Ownership

[Insight Sharing](Merian/Features/Insights/Sharing/README.md) separates
platform-neutral Share copy/action models; Services-only endpoint, cache, event,
repository, and feedback adapters; focused root-view-model extensions; a
contained share-state request/revision owner; the observable Community request
draft; and thin Views and Components. The Shell-owned `InsightSheetViewModel`
remains the single root state owner and accepts an optional trailing Sharing
dependency for deterministic tests.

Sharing views and components issue no endpoint calls and resolve no live
singleton. Async share-state hydration, publication, editing, and Community
request work retain the existing scan/generation fences; same-scan mutations
invalidate older reconciliation, and a replacement Community request rejects a
late detail response from its predecessor. Existing screen and component
initializers, visible copy, accessibility labels, routes, and endpoint contracts
remain stable. Mirrored Sharing tests enforce those races, deterministic
presentation, ownership folders, aggregate removal, Services-only live
resolution, and the 600-line production-file ceiling.

## AI And Foreground Analysis

`Merian/Core/AI/` owns remote inference orchestration and the ephemeral local
analysis that improves foreground scanning copy. `InferenceEngine` remains the
stable observable facade consumed by SwiftUI and delegates live visual/nonvisual
startup to `Inference/Pipeline/InferenceLiveSubmissionCoordinator`. That focused
main-actor owner sequences Auth/payload admission, lifecycle replacement,
media/telemetry staging, activation, optional local visual analysis, first-
render timing, immutable request construction, callback selection, and task
registration without storing another task or resolving live effects.
`Inference/Assembly/InferenceEngineAssembly.swift` is the one-shot `@MainActor`
composition boundary that constructs the focused owner graph in its existing
order from the engine initializer's dependencies. It starts no task and retains
no mutable runtime state; the engine still retains each runtime owner privately,
while `AppDIContainer` remains the production source of external live
dependencies supplied by the app graph. Existing defaults remain available to
direct engine initializers.
`Inference/Facade/InferenceEngineCompatibility.swift` owns source-compatible
nested modality values and pure static adapters. `Inference/Diagnostics/`
contains the existing DEBUG API and an ephemeral scenario coordinator; both
files compile out of Release and receive exact focused-owner references through
one DEBUG-only facade factory without widening their private retention.
`Inference/Presentation/InferencePresentationState` owns the stored processing,
copy, media, species, queued-presentation, loading, and telemetry values behind
source-compatible read-through accessors. The effect-acquisition-free
`Inference/Lifecycle/InferenceSessionLifecycleCoordinator` sequences new-scan,
analysis replacement, success, exact background/queued result recovery,
queued-record handoff, queue handoff, dismissal, cancellation, historical
loading, application activity, and Auth quiescence across the focused state/task
owners without acquiring another task or mutable registry.
`Inference/State/InferenceLiveAttemptCoordinator` owns the non-observable
foreground task, scan, process-local attempt, durable generation, and recovery
identity; its injected `InferenceLiveQueueService` delegates every claim,
current-owner lookup, deferred-upload release, retirement, exact-generation
deletion, and terminal rejection to the sole `+Live` queue adapter. The attempt
owner atomically detaches identity and the exact task before durable callbacks,
retains the cancelled displaced handle until completion for Auth quiescence, and
lets recovered-result commits perform the same cancellation before observable
publication. Offline Sync therefore never cancels the facade task after a
recovered-result call returns.
`Inference/Presentation/InferencePresentationCoordinator` separately owns the
process-local prepared/active presentation identity, exact visual handoff
phrase/media context, and pending first-render timestamp. It has no observable
UI model or effects; `InferencePresentationState` applies the existing
synchronous value commits around its decisions. Auth admission and post-drain
cleanup clear its owners and queued visual context without consuming a pending
first-render metric. An admitted visual replacement instead clears the displaced
owner, queued visual context, and timestamp before installing the new owner,
preventing a same-scan retry without a new clock from logging the prior tap
interval. After exact admission, a queue-less completion moves its pending clock
from the temporary client identity to the server scan ID before publication;
stale callbacks cannot move or consume it. The presentation state creates no
task or effect and explicitly clears prior subject distance for a new scan, a
nonvisual scan, or cancellation. Historical replacement clears displaced
hydration loaders before installing the record projection.
`Inference/Media/InferenceLiveMediaProjector` separately normalizes visual and
nonvisual inputs into one immutable timeline, provider projection, optional
explicit owner timeline, and `ActiveScanMedia` value. Its narrow live
dependencies contain only Documents/temporary path lookup and HTTPS video
validation; focused tests replace them without touching the filesystem. The
projector preserves display-image selection, focus regions, explicit poster
suppression/fallback, distinct stills adjacent to video, persisted-image
remapping, and the legacy nonvisual modality decision. The
`Inference/Pipeline/InferenceLivePipelineCoordinator` owns the shared execution
path after the submission coordinator publishes that projected visual or
nonvisual presentation: exact admission and activation, circuit gating,
request/result handoff, accepted-result preparation, benchmark placement
(including the exact one-shot rendered-frame duration routed by the submission
coordinator), durable finalization, failure dispatch, modality-specific
follow-up order, and exact-owner cleanup. Its core contains no live singleton or
logger. Its `+Live` adapter binds the circuit, quota-refund, and logging effects
captured by `AppDIContainer`; narrow callbacks carry observable publication,
hydration scheduling, local-analysis timing, typed failure actions, and final
cleanup. Queue-less nonvisual authorization remains synchronous, while only
queue-backed finalization uses the existing suspension. The
effect-acquisition-free
`Inference/Pipeline/InferenceLivePresentationCoordinator` is the sole production
constructor of both callback bundles. It synchronously fences accepted result
identity before persisted-media projection or publication, then routes the
biological completion event, finish, typed failure, captured hydration policy/
container, visual local-analysis cancellation, and request-body session tuple to
their focused owners without creating a task, suspension, mutable registry, or
engine retention cycle.
`Inference/Completion/InferenceLiveCompletionCoordinator` owns the shared
visual/nonvisual accepted-result boundary: discovery marking, replacement
handoff, circuit success, scan telemetry, the biological completion event, and
post-commit notification/milestone authorization. Queue-backed follow-ups
require exact durable deletion while the full local/durable tuple remains
current; retirement or replacement during deletion fails closed. Queue-less
nonvisual completion retains a synchronous authorization path that accepts only
the nil scan/durable identity, and only the coordinator can construct its typed
permit. Its core resolves no singleton or task, while its `+Live` adapter
bridges concrete dependencies captured by `AppDIContainer`. The
live-presentation coordinator commits through the lifecycle/presentation owners
and routes hydration to `InferenceSpeciesPresentationCoordinator`; the engine
retains its stable facade, while the pipeline coordinator preserves benchmark
placement and modality-specific effect order. The `Inference/Hydration` sibling
privately owns live, historical, and identification-review hydration task
lifetime, Auth draining, request deduplication, the enriched-species TTL cache,
and temporary backoff. GBIF work stays a structured child of the owning
hydration task. `InferenceSpeciesHydrationCoordinator` carries the exact
scan/species/presentation/review identity and owns the complete live
Wikipedia-enrichment-GBIF sequence plus the shared exact-presentation operations
invoked by historical and review flows, bounded reference merging, and immutable
persistence-work emission. The registered live task validates that complete
identity before its first loader publication or provider request, and deferred
loader cleanup validates it again before changing state. Each external
suspension is followed by a cancellation check, so an explicitly cancelled
hydration owner cannot publish or persist a cancellation-ignoring response.
`InferenceHistoricalLoadCoordinator` owns historical-load admission, active-scan
identity, live-media release, persisted projection, compatibility-reset
scheduling, synchronous presentation publication, review-generation capture, and
registered follow-up scheduling. `InferenceHistoricalHydrationCoordinator` owns
the deferred decode, override, parallel Wikipedia/enrichment, and
enrichment-before-GBIF sequence; task lifetime remains in
`InferenceHydrationCoordinator`. The engine retains the stable `load(from:)`
facade and observable-state read-throughs;
`InferenceSpeciesPresentationCoordinator` exposes identity checks and admitted
writes through the shared hydration callback bundle;
`InferenceReviewWorkflowCoordinator` owns review-action sequencing and
registered review hydration. Historical follow-up validates the same exact
identity at entry and after suspension; an eligible loader that receives no
usable provider image terminates as empty only while that presentation remains
current. The private-state enrichment sub-coordinator owns independent scope
loading, one taxonomy-gated retry, and 403/429 policy. The effect-free
lookalike-cache reset service isolates historical compatibility; only its
`+Live` adapter reads UserDefaults, coalesces process-wide reset work, and
constructs the database actor. `InferenceHistoricalRecordProjection` snapshots
each persisted SwiftData record on `@MainActor` into value-only presentation,
media, hydration plan, and deferred decode state, so the historical task never
retains the managed record. Historical presentation replacement releases prior
live-media buffers before constructing that projection. The immutable
`InferenceSpeciesEnrichmentService` maps typed scoped responses into domain
patches, and only its `+Live` adapter calls the Core Network enrichment
endpoint. `InferenceHydrationPersistenceService` accepts already-admitted
reference, metadata, and lookalike snapshots; only its `+Live` adapter
constructs the database actor and encodes rich lookalikes off-main.
`Inference/State` also privately owns bounded background and ordered
identification write sequencing; species-changing review hydration and
same-species confirmation have independent action generations on the shared
final-writer tail. The shared injected `Core/SpeciesReference/Services` boundary
owns the isolated Wikipedia/GBIF session, wire parsing, and request construction
used by Inference and thumbnail recovery. Observable presentation values remain
behind the engine facade in `InferencePresentationState`;
`InferenceSpeciesPresentationCoordinator` constructs the hydration callback
bundle and owns bounded-write admission, while hydration and write operation
lifetime remain in their focused coordinators. `AppDIContainer` composes all
live services and effect adapters.
`Inference/LocalAnalysis/InferenceLocalAnalysisCoordinator.swift` privately owns
the classification, deterministic-trait, Foundation-cue, and phrase-clock task
slots plus the bounded derivative, provisional classification, phrase cursor,
request-body gate, inactivity pause/resume state, and the Foundation stage's
power/thermal subscription and explicit stream-cancellation lifetime. The engine
supplies an exact-session predicate and receives phrase values; raw handles and
mutable local-analysis state do not escape the coordinator. Its sibling files
separate the Vision classifier/category policy, bounded image builder,
deterministic pixel-trait extractor, staged Apple Foundation Models adapter,
Foundation cue contract and validation, runtime eligibility, and phrase
coordination. `AppDIContainer` owns the live implementations and start feedback;
direct/default engine instances use inert feedback.
`Inference/Request/InferenceLiveRequestService.swift` is the injected
visual/nonvisual request boundary. It owns base64 filtering, MIME selection,
observation-context JSON, descriptor forwarding, staged-video upload, and the
single provider invocation, while the pipeline coordinator supplies exact-
attempt validation and owns provider-ready/body-sent timing. The engine retains
staging, and the live-presentation coordinator owns the local-analysis callback.
The provider-ready fail-safe and body-sent callback retain the attempt
coordinator independently for durable queue release; the local-analysis update
weakly captures only its focused bridge.
`Inference/Result/InferenceLiveResultService.swift` normalizes visual/nonvisual
inputs for the existing parse/save actor, forwards the exact persistence fence,
and returns typed persisted, confidence-zero no-record, or rejected outcomes.
`Inference/Services/InferenceResponsePreparationService.swift` supplies both
foreground and background completion with one stateless JSON decode, usable
response validation, request-appropriate scan-ID comparison, domain mapping, and
immutable entitlement-settlement projection. It owns no account or queue effect.
Background finalization calls it directly instead of waiting on the parse/save
actor while holding a scan persistence fence. Its prepared value,
`EntitlementStateSnapshot`, the complete `SpeciesData` graph, and both
finalization result carriers are compiler-checked `Sendable` values. The
pipeline supplies exact-attempt validation before and after persistence. The
completion coordinator handles shared success effects and delegates exact-
generation queue completion to the attempt coordinator. Offline Sync then
applies any carried settlement after successful persistence and required queue
deletion; `InferenceFundingReconciliationOwner` retains all accepted account
leases through its Auth-drained trailing-pass task. Reanalysis metadata safety
remains in `Inference/Result/InferenceScanReplacement.swift`: a replacement must
be visible in a fresh store context and its metadata save must succeed before
repository-owned deletion of the original. No-record results and failed saves
keep the original. The immutable
`Core/Network/Inference/InferenceIdentificationReviewService` separately owns
the exact-name Species Dictionary projection and owned-scan review RPC. Every
live operation is fenced by an account-work lease. The AppDI-owned
`Inference/IdentificationReview/InferenceReviewSnapshotService` separately
performs the bounded, throwing SwiftData projection needed before confirmation
or reset. Store failure returns before review presentation, action generations,
local writes, or cloud work can change; a missing row remains an optional
compatibility result.
`Inference/IdentificationReview/InferenceIdentificationReviewCoordinator` owns
review action admission, ordered local persistence, the network-service call,
and post-success Explore refresh and milestone effects. Its singleton-free core
receives typed dependencies; its `+Live` adapter alone constructs the database
actor and binds the AppDI-captured event/milestone collaborators.
`Inference/IdentificationReview/InferenceReviewWorkflowCoordinator` owns the
complete override, confirmation, reset, and historical displayed-override
sequences. It performs snapshot preflight before mutation, preserves atomic
local admission before lookup/cloud work, owns the registered review hydration
slot, and fences every resumed lookup against the exact presentation and review
generation. `IdentificationReviewPresentation` returns the matching full-value
`SpeciesData`, reference-media, and persistence-patch actions without effects.
The engine retains stable public methods.
`InferenceSpeciesPresentationCoordinator` coordinates observable commits through
`InferencePresentationState`; supplies the workflow's single hydration callback
bundle for current presentation, generation, identity, and persistence
admission; and starts review generations for newly installed live and historical
presentations. Interactive review sequencing, persistence implementation,
transport, and cross-feature invalidation remain outside it. `AppDIContainer`
owns the production request, result, queue, completion, failure-effect,
enrichment, hydration-persistence, review transport, review snapshot, and
review-effect values. `Inference/Recovery` contains stateless
interruption/failure classification and recovery presentation plus the
singleton-free synchronous failure coordinator. That coordinator snapshots exact
ownership, sequences cancellation and queued handoff, delegates release,
retirement, and rejection to the attempt coordinator, and orders injected
telemetry, circuit, logging, paywall, and feedback effects without creating a
task or suspension. It revalidates the local owner after synchronous queue
callbacks before emitting later presentation effects. Its `+Live` adapter owns
the concrete effect bridge. `InferenceLivePresentationCoordinator` applies only
recoverable-ID, queued-presentation, and error-value actions to observable
state. The current toolchain derives five image-specific observations covering
dominant colors, color saturation, lighting, light contrast, and surface detail.
They render as plain visible descriptions such as **Reviewing softly colored
areas** and **Observing light and shadow areas**, not `Kind: detail` labels or
internal statistical buckets such as “moderate” and “balanced.” Active visual
live-to-queue handoff preserves the ephemeral contextual deck and in-memory
carousel media only for an exact scan-and-attempt owner. Prepared visual work
transfers generic copy without media; audio and Describe are typed nonvisual
owners. That exact handoff also retains the canonical scan ID, selected carousel
page, focus state, and time-derived analysis sweep through pending, uploading,
staged, and inferencing queue states while none requires attention; ordinary
queued scans animate only while inferencing. The trailing Insight toolbar slot
stays mounted and fades in its queued delete action only after the durable ID is
bound. The same visual cursor survives save and connectivity changes, while
dismissal or Auth removes contextual phrase/media exposure without blocking
durable result recovery. `AppleFoundationVisualCueProvider` is implemented for
Swift 6.4 / iOS 27 behind the default-on `foundationVisualCues` release flag.
Eligible devices use on-device visual observations automatically. Debug Settings
can disable them or clear a saved override for comparison testing; older
toolchains and OS versions silently retain deterministic cues. Hosted and
physical-device validation remain outstanding under the canonical AI engineering
checklist.

Gemini remains the sole authority for identification and completed Insight
content. Local classifications and cue text are never persisted, logged,
analyzed as product telemetry, or added to Gemini's payload. See the
[Core AI README](Merian/Core/AI/README.md),
[Core Species Reference README](Merian/Core/SpeciesReference/README.md),
[Capture submission README](Merian/Features/Capture/Submission/README.md), and
[Insight content README](Merian/Features/Insights/Content/README.md) for the
ownership and dispatch contracts. The
[Insight media README](Merian/Features/Insights/Media/README.md) and
[toolbar README](Merian/Features/Insights/Toolbars/README.md) own the carousel
clock, page continuity, and trailing-action presentation rules.

`Core/Data/OfflineSync/Policies/OfflineQueueRetryPolicy.swift` owns retry
classification and timing rather than an Insight view;
`OfflineQueueDurability.swift` applies those decisions to durable state. Scan
analysis uses a five-second minimum, jittered exponential backoff, a 30-second
ordinary local maximum, and ten automatic attempts; safe server-directed
minimums may be longer, while maintenance keeps its 15-minute maximum.
`QueuedRetryPresentation` translates stable codes into safe customer copy,
countdowns, and actions without rendering stored error text. Offline retryable
work exposes no countdown or **Retry now**, and a due deadline adds no redundant
helper. See the [Core Data README](Merian/Core/Data/README.md),
[Insight content README](Merian/Features/Insights/Content/README.md), and
[offline sync contract](../../docs/backend-and-data/01-offline-sync-pipeline.md).

## Hygiene closure guard

`MerianTests/IOSHygieneClosureArchitectureTests.swift` scans the complete main-
app Swift source tree and requires every file above the 600-line review ceiling
to be part of one explicit inventory:

- `App/UITesting/UITestSeedCoordinator.swift` is a Debug fixture owner whose
  Release branch is a signature-compatible no-op.
- `Core/Network/SupabaseManager.swift` is the measured residual facade. Further
  extraction is paused unless it fixes a correctness boundary or produces a
  net-negative affected production delta.
- `Models/SchemaVersions.swift` is the ordered migration registry kept cohesive
  so version and stage sequencing remain compiler-reviewed in one place.

This inventory is not permission for new large files or growth in the tracked
facade. Domain suites retain their tighter budgets. Related declarations should
remain together when separation would create only pass-through or single-value
files; a small live adapter remains justified when it isolates an SDK, process,
filesystem, persistence, or singleton boundary for deterministic testing. The
suite uses the shared architecture-test physical-line counter: empty source is
zero lines, and a terminal newline ends the final line rather than creating an
additional empty line. Focused cases freeze those semantics so local and
app-wide ceilings use the same measurement.

## Tests

Use `make ios-local-build` for local command-line validation so simulator and
device builds reuse checkout-local caches. Use `make ios-build-storage` to
inspect disk use and `make ios-clean-build-cache` to preview cleanup. The
[local build storage procedure](../../docs/development-guides/08-testing-strategy.md#local-ios-build-storage)
defines commands, isolated checks, disk thresholds, and retained test evidence.

Unit tests should mirror the production owner:

```text
MerianTests/
  Support/
  Core/<CoreArea>/
  Features/<Feature>/<ProductArea>/
```

If a test primarily exercises a Core manager, place it under `MerianTests/Core`,
even if the behavior appears in a feature screen. If it exercises a product
area's view model, policy, or local helper, place it under that feature product
area.

Tests that mutate a process-global resource must also claim its keyed gate from
`MerianTests/Support/SharedProcessStateTestTrait.swift`. Swift Testing's
`.serialized` trait orders descendants only within one suite; it does not
exclude a peer suite. Use `.sharedProcessState(.networkClientOverrides)` for
temporary `MerianNetworkClient` or shared request-interceptor ownership,
`.sharedProcessState(.offlineQueueManager)` for queue fixtures,
`.sharedProcessState(.gamificationManager)` for the shared gamification owner,
and `.sharedProcessState(.appIconBadgeCoordinator)` for persisted/OS badge
state. Inject a private `AppRouteCoordinator` through the available
route-request closure when testing notification routing; do not drain the
app-host process singleton. Apply a keyed gate at suite scope when every case
owns the resource and at test scope for isolated cases. Cases needing multiple
resources claim them together in one trait. The underlying
`SharedProcessStateGate` leases complete resource sets atomically and handles
cancelled waiters. Capture's `OfflineQueueTestCase` base joins the same gate
across XCTest setup/teardown. Queue scopes restore the previous model context;
tests still restore other mutated fields and await their own work. Do not nest
overlapping traits or cancel app-host tasks during fixture cleanup. Generic
Insight contexts no longer configure the shared queue. Lifecycle admission tests
inject inert foreground actions instead of launching production maintenance; the
Core Data scheduler suite separately exercises ordered drain dispatch and
fixture-owned wake cancellation through its narrow injected operations.

## Assets

Asset folders describe what the asset is, not where it was first used:

```text
Assets.xcassets/
  App/
  Brand/
  Graphics3D/
  Personas/
```

Avoid prefixes such as `pw_`, `desc_`, or `dictionary-` when artwork is
reusable. Prefer stable descriptive names such as `bird-cardinal`,
`camera-lens`, or `persona-naturalist`.

## Privacy Manifest

The main app owns `Merian/Configuration/PrivacyInfo.xcprivacy`. Keep it in the
`Merian` Resources phase exactly once through `project.yml`; never attach it to
another target merely to satisfy a warning. Before adding a required-reason API,
SDK, executable, analytics property, or off-device data flow, follow the
[iOS App Privacy Manifest Contract](../../docs/development-guides/16-ios-privacy-manifest.md).

After changing the declaration or target membership, run from the repository
root:

```bash
make xcodegen
make validate-ios-project
make validate-ios-privacy-manifest
make test-ios-ci-tooling
```

## Transport Security

The main application uses App Transport Security defaults and has no broad or
domain-scoped exception. `SecureTransportPolicy` accepts backend-provided remote
URLs only when they are credential-free HTTPS; app-owned file URLs and local
paths remain available for captured media. The Supabase origin is validated
under the same rule before client construction. Release requests to
`supabase.co` and its true subdomains additionally require both Apple's platform
trust evaluation and a matching certificate-chain pin; unreadable, untrusted, or
unmatched chains are cancelled. Other HTTPS origins retain ordinary ATS
handling, and Debug builds intentionally skip pinning for local test proxies.

Run `make validate-ios-transport-security` for the tracked plist and
`make test-ios-transport-security` for adversarial fixtures. Archive and IPA
validation inspect the final built `Info.plist`, and hosted archive evidence
must contain `transport_security: "ats-default"`. That marker proves the plist
contract, not pin freshness, so release candidates must also compile the Release
TLS branch and pass the focused pinned-transport suite. See the
[iOS App Transport Security Contract](../../docs/development-guides/17-ios-transport-security.md)
for the complete boundary and release gate.
