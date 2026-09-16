# iOS Core

`Core` contains capabilities shared by more than one product feature. Feature
workflow, screen state, copy, navigation, and one-off presentation stay under
`Features`; backend implementation stays under `services/supabase`.

The canonical inventory is the [codebase map](../../../../docs/codebase-map.md),
and the staged cleanup history and residual owners are recorded in the
[codebase cleanup RFC](../../../../docs/rfcs/codebase-cleanup.md).

## Ownership boundaries

- The Core root contains only `AppDIContainer.swift`, which composes live
  dependencies, and `MerianLog.swift`, which defines logging categories.
- Each domain directory owns its local contract in a `README.md`. New code
  belongs in the narrowest domain; a generic utility is appropriate only when
  its semantics are genuinely mechanical and cross-domain.
- `Policies` contain bounded, stateless decisions and do not resolve live
  network, SwiftData, application, preference, task, or singleton effects. A
  small exact allowlist records the established local-file, clock, and jitter
  inputs used by Offline Sync, Store Recovery, and RevenueCat access policy;
  each domain README owns those semantics.
- Reusable `UI/Components` may render injected values and actions but do not
  issue requests or read persistence directly.
- SwiftData fetch errors are not collapsed with `try?`. A persistence boundary
  distinguishes an absent row from an unreadable store and callers fail closed
  when durable authority cannot be established.
- Local paths, media filenames, raw localized errors, server failure messages,
  credentials, account state, and response bodies remain private or absent in
  unified logging.

## Residual large owners

The post-refactor integration guard intentionally tracks the remaining Core
production file above the 600-line review ceiling:

- `Network/SupabaseManager.swift`

This is a residual inventory, not an exemption for new growth. Split these
owners in behavior-preserving slices, update the inventory in the same change,
and keep wire DTOs separate from UI policy.

The current Auth extraction leaves `SupabaseManager.swift` at 3,520 lines. The
facade retains its sign-out task and live-effect assembly while the focused
`AuthSessionLifecycleLiveProvider` owns the Supabase stream/listener task, SDK
value mapping, and deferred current-state replay. Replacing that listener
cancels both the superseded task and its replay obligation, and a
post-coordinator cancellation fence prevents the superseded operation from
resuming deferred credential revocation. The retained
`AuthHistoricalSessionSyncLiveService` owns listener-admitted synchronization
tasks and cancels them on teardown. The facade delegates the active transition,
Auth-session generation, transition-analytics generations, exact-session work
leases and drain waiters, and local sign-out flag to the effect-free main-actor
`Network/Auth/Coordinators/AuthRuntimeState.swift` owner. The focused bootstrap
service owns cached/loaded SDK-session projection, anonymous sign-in, and
missing-session classification. Its `+Live` adapter alone invokes those Supabase
Auth operations, and bootstrap diagnostics have a separate privacy-safe log
owner. The facade retains transition admission, publication, purchase readiness,
and the stable `User?` compatibility result. The typed Apple
credential-registration service and its sole Supabase live adapter own strict
receipt validation and Function transport, while the facade retains
exact-session assembly around that effect. The adapter performs exactly one
authenticated invocation per service call and owns neither retry policy nor
asynchronous task state. The injected OAuth session service and its live adapter
now own OIDC credential mapping, session reads/link/install calls, canonical
profile-metadata construction, and the SDK metadata update; the facade retains
transition admission, replacement reconciliation, diagnostics, and observable
publication. Provider-neutral bootstrap task state, lifecycle projection,
conditional deferred-event replay, authenticated-request recovery sequencing,
OAuth provider admission/presentation and completion, task-free fallback
authentication-callback coordination, public-author refresh coordination,
generation-fenced Apple credential revalidation, source-side purchase-handoff
fencing/restoration, Auth journal error adaptation, and historical sync
admission live under `Network/Auth/`. Keyed purchase resolution, binding state,
foreground repair, and stable/compatibility proof construction and checkpointing
live under `Security/PurchaseIdentity/`. Recovery captures the exact expected
session before account-work quiescence. Refresh and anonymous-replacement paths
fence cancellation and transition/session drift after their suspended phases;
terminal clear preserves durable purchase handoffs and invokes the remaining
local and purchase-identity cleanup after SDK sign-out has begun, even if
cancellation arrives. The bootstrap coordinator continues to share work only
while its complete token is the exact active owner, and anonymous creation
remains limited to stable missing-session evidence. The replay coordinator owns
one replacement-safe task and replays only an SDK event deferred by an active
transition; signed-out handling revalidates exact nil-session and generation
state after purchase cleanup. Facade-facing lifecycle dependencies capture the
manager weakly, so suspended synthetic replay cannot keep it alive past teardown
or prevent coordinator cancellation. OAuth replacement records installed,
failed, or cancelled disposition, fences cancellation before/after provider
return and after every suspended completion phase, and admits a cancelled owner
to terminal cleanup only after it has already mutated the SDK session. The live
install boundary records that mutation and the exact installed identity as the
transition expectation before cancellation can escape. That expectation exists
only to fence recovery; successful account publication still follows the
source/target, purchase, entitlement, and final-session checks. The app-root
`onOpenURL` task remains the fallback callback's sole asynchronous caller; the
coordinator stops after preflight cancellation, blocks adoption when sign-out
begins during SDK installation, and retains exact-session fences after purchase
and entitlement suspension. The public-author coordinator rejects stale
scheduling targets before task replacement, fences lease and remote work against
cancellation, and publishes only after the exact current account survives
validation after suspension. Its application-event and privacy-safe logging
effects remain in
`Network/SupabasePublicAuthorIdentityRefreshLiveEffects.swift`. Apple framework
notification/state lookup and privacy-safe outcome logging live in
`Network/AppleCredentialRevocationLiveProvider.swift` and
`Network/AppleCredentialRevocationLiveDiagnostics.swift`; the manager only
assembles those effects and maps its SDK user into the provider-neutral exact
identity. The coordinator remains weak across the suspended provider lookup, and
assembly captures the provider directly, so a delayed SDK callback cannot retain
or mutate a released manager/coordinator owner. The purchase identity owner
projects every durable handoff read into RevenueCat's synchronous mutation
fence, fails closed when the journals are unreadable, and rejects late results
from a superseded resolution key. The accepted-deletion barrier still closes the
published Auth session, purchase identity, and local server-verified entitlement
projection before recovery proceeds.

`InferenceEngine.swift` is now below the ceiling as the source-compatible
observable facade. Its internal graph is constructed once by
`AI/Inference/Assembly/InferenceEngineAssembly.swift`; pure compatibility
adapters live under `AI/Inference/Facade/`, and DEBUG-only simulator/test
operations live under `AI/Inference/Diagnostics/`. Lifecycle, presentation,
pipeline, hydration, recovery, review, and write ownership stays with the
focused `AI/Inference/` owners.

The retired `Network/ExploreAPIModels.swift` aggregate is now split under
`Network/Models/Explore/`; the cross-feature semantic-location redaction policy
lives in `Models/ExploreLocationPrivacy.swift`. Focused architecture coverage
locks both ownership boundaries and the 600-line model ceiling.

The retired `Network/FieldTripAPIModels.swift` aggregate is split into eight
network-model contract-family owners under `Network/Models/FieldTrips/`.
Presentation extensions remain feature-owned, Insights owns contribution-route
projection, UI Feedback owns milestone projection, and Preferences owns the
account-qualified compatibility store.

`Security/ConsentManager.swift` is now a 597-line observable compatibility
facade. Runtime composition, cloud-session and account-lease orchestration,
local mutation construction, and derived state projection live in focused owners
under `Security/Consent/`; every production owner there remains at or below 600
lines.

## Verification

`MerianTests/Core/Architecture/CoreIntegrationArchitectureTests.swift` freezes
the root/domain inventory, local README coverage, residual large owners,
stateless policy boundaries and their exact documented local inputs,
transport/persistence-free shared components, throwing SwiftData reads, and
privacy-safe diagnostics. Domain suites remain authoritative for behavior; the
Core-wide suite prevents ownership drift between those domains.
