# Core Network Auth

This folder owns the value-only foundation and effect-free observable runtime
used to serialize Merian account transitions and fence account-bound work, plus
deterministic account-deletion classification, ghost-profile-merge policy, and
dependency-injected deletion, purchase-safe sign-out, Auth-session bootstrap and
lifecycle projection, OAuth provider presentation admission and completion,
fallback authentication callback coordination, Auth-session recovery,
ghost-merge orchestration, and public-author identity refresh coordination. Its
focused Services own Apple/Google framework presentation and value mapping,
bootstrap SDK-session projection, missing-session classification, live reads,
anonymous sign-in, and diagnostics; recovery SDK-session projection, refresh,
read, local sign-out, and diagnostics; fallback-callback live diagnostics; the
typed Apple credential-registration boundary and its sole Supabase Function
adapter; plus the narrow OAuth session SDK adapter. It does not own other
Supabase Auth SDK mutation, durable Keychain journals, purchase-identity
mutation, other endpoint transport, local-data purge, or application lifecycle
effects.

## Ownership

- `Models/SupabaseAuthTransitionModels.swift` owns transition providers, kinds,
  phases, sessions, tokens, state, cold-start adoption outcomes, account-work
  leases, and the existing user-facing transition errors.
- `Models/OAuthSignInModels.swift` owns provider-neutral credentials, exact
  session/completion and provider-authorization values, normalized optional
  profile metadata, identity-token-free Apple credential-registration evidence,
  Google provider outcomes, stable provider diagnostics, the
  installed/failed/cancelled session-replacement disposition, and the internal
  registration-receipt and provider-configuration errors. The identity token has
  one owner in the OAuth credentials and is not duplicated in the registration
  value. This file contains no provider SDK type.
- `Policies/AccountPresentationPolicy.swift` owns the deterministic decision
  that maps a missing or anonymous Auth session to Guest presentation.
- `Policies/AuthTransitionPolicy.swift` owns deterministic transition admission,
  transition-owned request and listener fencing, provider-callback acceptance,
  OAuth rollback and metadata guards, exact anonymous-to-permanent provider-link
  admission, cold-start session classification, and purchase-identity
  handoff/restoration decisions.
- `Policies/OAuthIdentityTokenPolicy.swift` owns bounded, control-character-safe
  provider-subject extraction from the identity token used only when a direct
  anonymous identity link reports an existing account.
- `Policies/AccountDeletionTransitionPolicy.swift` owns exact cached-session
  restoration eligibility and the stable HTTP/code classifications for
  definitive intake rejection, matched expired recovery, and unknown v2 recovery
  proof.
- `Policies/GhostProfileMergePolicy.swift` owns stable queue replacement and the
  exact terminal server codes that permit durable handoff retirement.
- `Coordinators/AuthTransitionCoordinators.swift` owns the value-state machines
  for exclusive transition admission and exact-session work leases, plus the
  main-actor Boolean single-flight used by sign-out. An already-cancelled caller
  cannot open that single-flight or run its operation.
- `Coordinators/AuthRuntimeState.swift` is the observable, main-actor owner for
  process-local transition state, Auth-session generation, transition analytics
  generations, exact-session work leases and drain waiters, and the local
  sign-out flag. It composes the value-state machines without acquiring an SDK,
  singleton, store, endpoint, logger, or asynchronous task. The listener keeps
  generation advancement separate from transition observation so the live facade
  can preserve credential-revocation notification order.
- `Models/AuthSessionLifecycleModels.swift` owns the provider-neutral Auth-event
  origin, adoption/session/generation envelope, and fixed diagnostic categories.
- `Coordinators/AuthSessionLifecycleCoordinationDependencies.swift` defines
  narrow observable-state, durable-fence, purchase/entitlement, synchronization,
  and diagnostics closure boundaries. It acquires no live dependency.
- `Coordinators/AuthSessionLifecycleCoordinator.swift` owns deletion-barrier and
  active-transition deferral; immediate Auth, purchase-identity, and local
  server-verified entitlement projection closure while accepted deletion cleanup
  is pending; independent fail-closed Ghost and purchase-journal projection;
  authenticated, awaiting-refresh, and signed-out state order; restored-source
  handoff retirement; exact-generation checks after purchase and entitlement
  suspension; a signed-out postflight fence after purchase cleanup; and
  historical-sync admission. It creates no task.
- `Coordinators/AuthLifecycleReplayCoordinator.swift` owns the one
  replacement-safe main-actor task that replays the current SDK Auth state only
  when a listener event was deferred by an active transition. A newer SDK event
  cancels the synthetic replay, a newly admitted transition retains the replay
  obligation for its next stable finish boundary, and task cleanup compares its
  UUID before clearing shared state. SDK snapshots and lifecycle effects remain
  injected by the focused live provider.
- `Services/AuthSessionLifecycleLiveProvider.swift` owns the retained listener
  handle, exact listener prelude order, SDK-state projection, current-state
  snapshot validation, and composition of conditional replay. Replacing the
  listener cancels both its task and its deferred replay obligation; a
  post-coordinator cancellation fence rejects the replaced operation's trailing
  credential effect. Listener and replay closures retain neither the provider
  nor the facade across suspension.
- `Services/AuthSessionLifecycleLiveProvider+Live.swift` is the sole owner of
  `authStateChanges` subscription and the lifecycle current-session SDK read.
- `Services/AuthSessionLifecycleLiveDiagnostics.swift` maps fixed lifecycle
  outcomes to the privacy-safe Auth log without logging session values.
- `Services/AuthHistoricalSessionSyncLiveService.swift` retains every admitted
  history task, repeats cancellation and exact-session admission between
  preferred-name and scan synchronization, and cancels outstanding work on
  teardown. Its `+Live` adapter alone resolves the model context, timestamp,
  repositories, and concrete synchronization effects. That adapter is the
  reviewed Auth owner of `AppDIContainer.shared` for offline-queue context and
  scan-repository acquisition; the retained service receives only prepared work
  closures.
- `Coordinators/AppleCredentialRevocationCoordinationDependencies.swift` defines
  provider-neutral current-identity, transition, lookup, identity-bound
  terminal-clear outcome, and diagnostic boundaries.
- `Coordinators/AppleCredentialRevocationCoordinator.swift` owns the retained
  credential-state lookup task, transition deferral, notification coalescing,
  Auth-context generation, exact Apple session/subject postflight, and
  compare-before-clear task cleanup. A stale or cancelled lookup cannot clear a
  replacement session; an overlapping notification retains one follow-up lookup
  for the final stable Auth context. The retained task never promotes the
  coordinator across a provider lookup suspension, and the live assembly
  captures the provider rather than its manager. Releasing the owner cancels the
  retained task without waiting for the provider callback, and a late result has
  no coordinator through which to apply. Immediately before recovery, the live
  boundary admits only the exact captured Apple identity while no replacement
  transition is active. Recovery then repeats the captured transition session
  after account-work quiescence and returns a typed cleared, rejected, or
  purchase-handoff-blocked outcome. A context change retries only when stable; a
  recovery deferral retains the notification without a hot loop. Publishing the
  aggregate purchase-handoff fence as resolved explicitly wakes that retained
  work. Clear diagnostics are emitted only after local cleanup completes.
- `Coordinators/AuthSessionBootstrapCoordinationDependencies.swift` defines the
  provider-neutral SDK-session snapshot and narrow test/deletion gates,
  observable state, transition, account-work, session-operation, purchase
  readiness, public-author refresh, and diagnostics boundaries. The package
  imports no SDK and acquires no singleton.
- `Coordinators/AuthSessionBootstrapCoordinator.swift` owns exact-session reuse,
  transition admission, account-work quiescence, and the keyed single-flight for
  existing-session resolution or anonymous creation. Ownerless callers may join
  only when the task's complete transition token is still the exact active
  anonymous-bootstrap owner, while a differently owned or replaced transition is
  rejected. A caller cancelled before admission or while awaiting sign-out stops
  before account or SDK-session work. Existing and newly anonymous sessions are
  adopted, published, made purchase-ready, and revalidated behind cancellation
  and transition fences, including an explicit cancellation check immediately
  after purchase readiness returns. Only the injected stable missing-session
  classification may reach anonymous creation; network and expiry failures
  preserve the existing identity.
- `Services/AuthSessionBootstrapLiveService.swift` projects cached, loaded, and
  newly anonymous Supabase sessions into the bootstrap identity/expiry value and
  owns the established SDK plus compatibility missing-session classification.
- `Services/AuthSessionBootstrapLiveService+Live.swift` is the sole owner of the
  bootstrap `session`, `currentSession`, and `signInAnonymously()` SDK calls. It
  owns no task, retry, transition, publication, purchase, or entitlement state.
- `Services/AuthSessionBootstrapLiveDiagnostics.swift` maps bootstrap outcomes
  to the privacy-safe Auth log without logging SDK session values.
- `Services/AuthSessionRecoveryLiveService.swift` projects refreshed and loaded
  Supabase sessions into the provider-neutral recovery identity while retaining
  the SDK user only for facade-owned adoption, publication, public-author
  refresh, purchase-identity, entitlement, and generation-fence effects. It owns
  no transition, task, retry, purchase, entitlement, or cleanup policy.
- `Services/AuthSessionRecoveryLiveService+Live.swift` is the sole owner of the
  recovery-specific `refreshSession()`, session read, and local SDK sign-out
  calls. `Services/AuthSessionRecoveryLiveDiagnostics.swift` maps recovery
  outcomes to the established privacy-safe Auth log.
- `Coordinators/AuthSessionRecoveryCoordinationDependencies.swift` defines
  provider-neutral SDK-session capabilities plus narrow state, transition,
  operation, and diagnostic boundaries for authenticated-request recovery. It
  acquires no live dependency and exposes no provider SDK value.
- `Coordinators/AuthSessionRecoveryCoordinator.swift` owns ordinary and
  transition-owned exact-session refresh, anonymous replacement recovery, and
  terminal local cleanup. It drains admitted account work before SDK mutation,
  snapshots and repeats the exact expected/current session after quiescence,
  rejects cancellation and transition/session drift around suspended phases,
  returns an explicit clear outcome, keeps purchase-handoff evidence
  fail-closed, permits a cancelled OAuth owner to enter cleanup only after that
  owner has already mutated the SDK session, and deliberately completes local
  cleanup once SDK sign-out has begun. It creates no task.
- `Coordinators/AccountDeletionWorkflow.swift` owns deterministic ordering for
  durable and prepared intake, accepted cleanup, capability retirement,
  rejection-proof retirement, deferred-session restoration, and pending local
  cleanup through injected closures. Preflight and post-persistence cancellation
  fences prevent a cancelled task from dispatching the first destructive intake
  or commit request while retaining any already-durable recovery marker.
  Accepted cleanup verifies a successful `pending|completed` receipt before
  invoking its first persistence or erasure effect. It owns no live dependency
  or task.
- `Coordinators/AccountDeletionCoordinationDependencies.swift` defines the
  value-only cached-session snapshot and narrow local-state, exact-session,
  diagnostics, and purchase-handoff closure boundaries shared by deletion intake
  and recovery. It acquires no live dependency.
- `Coordinators/AccountDeletionCoordinator.swift` owns fresh authenticated
  deletion orchestration: purchase/recovery preflight, transition admission,
  capability preparation, v1/v2 intake selection, accepted cleanup,
  acknowledgement, and proof retirement. It delegates phase order to
  `AccountDeletionWorkflow` and receives every effect through the shared
  dependency boundary. Caller cancellation is rejected before either preflight
  state is read or an Auth transition can begin.
- `Coordinators/AccountDeletionRecoveryCoordinator.swift` owns relaunch and
  foreground recovery routing for every installed marker and proof version. It
  handles proof-only noncommit restoration, accepted deletion cleanup, legacy
  replay, acknowledgement, and retirement while revalidating the exact cached
  session. Installed pre-capability intake persists and reuses the raw v1 proof
  format before calling the v1 endpoint, so an ambiguous response cannot
  relaunch into the v2 hash domain. A prepared-v2 marker with no proof cancels
  locally because destructive commit had not started. For an installed mixed
  state created by the former bug, a v2 unknown response at intake/cleanup
  checks the v1 recovery domain; only a positive legacy match may continue
  cleanup, while an unknown result retains the proof and barrier. The
  coordinator creates no task and acquires no SDK, endpoint, store singleton, or
  logger.
- `Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns ordinary sign-out
  ordering plus the purchase-safe preparation, local sign-out, anonymous
  replacement, provider/server verification, cancellation checkpoints, and
  proof-removal-last contract through injected closures. It rejects cancellation
  before phase entry and between preparation, local sign-out, anonymous
  initialization, and completion. It owns no live dependency, logger, or task.
- `Coordinators/PurchaseIdentitySignOutCoordinationDependencies.swift` defines
  the SDK-session snapshot and narrow exact-session, journal,
  provider-readiness, restoration, and diagnostics closure boundaries used by
  sign-out and its foreground retry. It acquires no live dependency.
- `Coordinators/PurchaseIdentitySignOutCoordinator.swift` owns ordinary versus
  linked routing, stable-principal versus compatibility selection, pending-proof
  resume or source-only abandonment, exact-source restoration after a failed
  attempt, and recovery-owned retry admission. Its reset entry point accepts
  only a recovery transition, and a failed stable-journal verification keeps
  purchase readiness closed. Foreground recovery drains admitted account-bound
  work before it reads or completes against the anonymous SDK session. It
  delegates phase order to `PurchaseIdentitySignOutWorkflow`, creates no task,
  and acquires no SDK, singleton, store, endpoint, or logger.
- `Coordinators/PurchaseIdentitySourceHandoffCoordinationDependencies.swift`
  defines the exact-session, account-work, journal, preparation, cancellation,
  restoration, entitlement, and diagnostic closure boundaries used while the
  linked source still owns the Auth session. It acquires no live dependency.
- `Coordinators/PurchaseIdentitySourceHandoffCoordinator.swift` owns aggregate
  fail-closed journal projection, stable and compatibility preparation around
  exact-source session fences, exact-source proof cancellation and retirement,
  and failed-sign-out source restoration. It creates no task. Cancellation
  during compatibility preparation's final SDK-session read cannot report
  success or publish the preparation diagnostic; the already-durable proof
  remains recoverable. Abandonment that loses its source-session or account-work
  fence during an SDK read cannot dispatch a remote cancellation or remove
  proof. A lost final read fence retains the proof and republishes the pending
  mutation fence.
- `Coordinators/PurchaseIdentityHandoffCoordinationDependencies.swift` defines
  the narrow exact-session, journal, purchase-operation, and diagnostics
  boundaries used after an anonymous destination exists. It contains no live
  client, provider, store, or logger.
- `Coordinators/PurchaseIdentityHandoffCoordinator.swift` owns completion keyed
  by destination, Auth generation, and transition owner for both protocol-3
  stable rotations and installed compatibility proofs. It replaces ownerless
  work when an Auth transition takes ownership, cancels a stale generation,
  rejects already-cancelled callers and tasks before reading either journal,
  revalidates cancellation and the exact anonymous session around every
  suspended provider/server/entitlement phase, and removes proof only after the
  final session fence. Terminal-only compatibility retirement and restored-
  source abandonment remain explicit injected policies.
- `Services/PurchaseIdentityHandoffAuthJournal.swift` is the sole Auth adapter
  over the Core Security handoff store. It maps store-owned load and persistence
  failures to the established Auth-transition errors while preserving the
  underlying verified-removal diagnostics.
- `Coordinators/GhostProfileMergeWorkflow.swift` owns server completion,
  purchase synchronization, local-evidence rebind, cancellation checkpoints, and
  proof-removal-last ordering through injected closures. It owns no live
  dependency, logger, or task.
- `Coordinators/GhostProfileMergeCoordinationDependencies.swift` defines narrow
  exact-session, secure-queue, provider/local-evidence, analytics-suppression,
  and diagnostic boundaries. It acquires no live dependency.
- `Coordinators/GhostProfileMergeCoordinator.swift` owns preparation durability,
  exact source/provider-transition/target admission, target-and-transition-keyed
  completion task lifetime, queue-wide retry, terminal cleanup, and suppression
  projection. A server-returned capability becomes durable before cancellation
  is honored; cancellation and key supersession are rechecked before later
  evidence sync or proof removal.
- `Coordinators/PublicAuthorIdentityRefreshCoordinationDependencies.swift`
  defines the provider-neutral session, account-work, Ghost completion, remote
  refresh, event, and diagnostics boundaries. It acquires no live dependency.
- `Coordinators/PublicAuthorIdentityRefreshCoordinator.swift` owns direct and
  restored-session public-author refresh. Its restored path owns one
  target-account-keyed task with UUID compare-before-clear cleanup, completes
  retained Ghost handoffs before refreshing, nests the existing ownerless
  account-work lease inside the outer restored-session lease, and publishes only
  after cancellation, lease, and current-user revalidation. A stale scheduling
  input cannot replace the current user's task. Both scheduled and direct paths
  reject cancellation before lease or remote work and after suspension;
  cancellation does not emit a refresh-failure diagnostic. Transition-owned
  refresh uses its existing exact-session fence without opening a lease.
- `Coordinators/OAuthSignInWorkflow.swift` owns cancellation-aware SDK-session
  replacement around analytics suppression, explicit installed/failed/cancelled
  reconciliation, and bounded cancellation-aware Apple credential-registration
  retry. It receives every effect as a closure.
- `Coordinators/OAuthSignInCoordinationDependencies.swift` defines the narrow
  exact-session, Ghost-merge, metadata, telemetry, entitlement, and final-
  publication closure boundaries. It acquires no live dependency.
- `Coordinators/OAuthSignInCoordinator.swift` owns provider-neutral Apple and
  Google completion: pending purchase-handoff admission, direct same-UUID link
  or provider-bound Ghost fallback, exact-session adoption, exact provider-to-
  transition agreement, credential registration required for Apple and forbidden
  for Google, normalized metadata persistence, purchase identity readiness,
  entitlement, public-author refresh/event publication, and the
  authenticated-OAuth marker. It fences cancellation after every suspended phase
  and before the final synchronous publication. It creates no task.
- `Coordinators/OAuthProviderSignInCoordinationDependencies.swift` defines the
  narrow transition, provider authorization, shared completion/recovery, and
  diagnostics closure boundaries. It imports no provider framework and acquires
  no singleton.
- `Coordinators/OAuthProviderSignInCoordinator.swift` owns synchronous provider
  admission, Google return verification/recovery, Apple callback acceptance, and
  the single retained Apple completion task with UUID compare-before-clear
  cleanup plus immediate cancel-and-release teardown. It delegates session
  installation to `OAuthSignInCoordinator` and contains no provider SDK or
  logging dependency.
- `Coordinators/AuthenticationCallbackCoordinationDependencies.swift` defines
  provider-neutral transition, SDK-session capability, purchase/entitlement,
  recovery, marker, and diagnostic closure boundaries for the SDK's fallback
  Auth URL. It imports no provider SDK and acquires no singleton.
- `Coordinators/AuthenticationCallbackCoordinator.swift` owns fallback-callback
  transition and pending-handoff admission, anonymous-source rejection,
  installed/failed/cancelled replacement reconciliation, exact source/target
  policy, session adoption and publication, purchase and entitlement order,
  final exact-session verification, authenticated-marker publication, and
  mutation-aware cleanup. It creates no task; the invoking app lifecycle task
  retains cancellation ownership.
- `Services/OAuthPresentationContextResolver.swift` is the sole shared UIKit
  window/anchor policy for interactive OAuth. The Google and Apple live-provider
  services own their respective SDK presentation, provider-value mapping, and
  pre/post-return cancellation or controller-retention boundaries. The Apple
  provider also owns secure nonce generation and hashing. Both providers expose
  an explicit zero-argument production initializer and a separate nonoptional
  injected-dependencies initializer; optional live-dependency fallback is not
  part of the boundary. The live diagnostics services map provider and
  fallback-callback outcomes into privacy-safe logs. The resolver and Apple
  provider retain only their local missing-scene and stale-controller safety
  diagnostics.
- `Services/AppleOAuthCredentialRegistrationService.swift` owns the injected,
  provider-neutral registration operation and accepts only the exact
  `success == true`, `status == "registered"` receipt. Its `+Live` adapter alone
  owns the private request/response DTOs, lowercased registration UUID, and
  authenticated `register-apple-revocation-token` Function invocation. It
  performs exactly one authenticated Function invocation per service call. It
  owns neither retry policy nor asynchronous task state; `OAuthSignInWorkflow`
  remains the retry owner.
- `Services/OAuthSessionService.swift` owns the narrow SDK-facing OAuth
  adaptation surface: Apple/Google OIDC credential construction, SDK-session to
  provider-neutral identity projection, and canonical `full_name` / `name`,
  `given_name`, `family_name`, `avatar_url` / `picture` metadata construction.
  Its `+Live` adapter is the sole owner of OAuth session reads, current-session
  snapshots, identity linking, ID-token session installation, and user-metadata
  update calls. The service is initializer-injected, creates no task, resolves
  no singleton, logs no profile value, and owns no transition, rollback, or
  observable publication policy. Replacement receives a mutation observer from
  the completion owner; the facade invokes it immediately after the live SDK
  install returns, then records that exact SDK identity as the active
  transition's expectation before the replacement workflow can observe
  cancellation. Recovery therefore distinguishes post-install cancellation from
  a true pre-mutation failure and can clear only the exact installed target even
  when the helper never returns normally.

`SupabaseManager.swift` remains the live Auth facade and effect assembler. It
retains the facade sign-out task, injects weak observable-state and effect
closures into the lifecycle provider, and supplies SDK, consent, purchase
identity, endpoint, Keychain, sign-out, purge, logging, and lifecycle effects to
the session-bootstrap, session-lifecycle, session-recovery, Apple-revocation,
OAuth, fallback-callback, deletion, purchase-sign-out, purchase-handoff,
Ghost-merge, and public-author-refresh coordinators. The focused lifecycle
provider owns the Supabase Auth stream/listener, SDK-event mapping, deferred-
event registration, and exact current-state replay. It delegates
transition/generation bookkeeping, transition-scoped analytics generations,
exact-session work leases and drain waiters, and local sign-out state to
`AuthRuntimeState`. Source-side preparation and restoration delegate to
`PurchaseIdentitySourceHandoffCoordinator`; concrete journal error adaptation
delegates to `PurchaseIdentityHandoffAuthJournal`; and proof construction and
checkpoint persistence delegate to Core Security's
`PurchaseHandoffPreparationCoordinator`. Its stable public Apple/Google entry
points delegate to `OAuthProviderSignInCoordinator`, while its stable
fallback-URL entry point delegates to `AuthenticationCallbackCoordinator`. Its
OAuth assembly brackets the injected session and Apple credential-registration
services with exact transition/session checks, replacement reconciliation, and
observable publication. Lifecycle replay dependencies capture this facade
weakly, so a suspended synthetic replay cannot keep the manager alive after its
external owner is released; coordinator teardown remains able to cancel the
retained task. The facade uses `isolated deinit` so its existing cancellation
sequence runs on the main actor even when the final reference is released
elsewhere. Facade teardown also explicitly cancels the retained purchase-
handoff and purchase-identity resolution coordinators instead of relying on
their eventual deinitialization. Its public `initializeGhostSession(ownedBy:)`
entry point remains the source-compatible SDK-value adapter; the bootstrap
coordinator owns the task and returns only a provider-neutral exact-session
identity. Its Google and Apple provider SDKs, delegate callbacks, presentation
policy, nonce, and hashing are absent from the facade. The public-author
coordinator records both a task UUID and target account, so a cancelled
predecessor cannot clear a replacement handle; its completed-account marker is
written only after a successful exact-session refresh.
`SupabasePublicAuthorIdentityRefreshLiveEffects.swift` remains outside the
provider-neutral package and is the sole owner of its application-event and
privacy-safe logging effects. The recovery coordinator rejects cancellation
before opening a recovery transition and rechecks cancellation, ownership, and
exact session identity after quiescence, SDK refresh/load, purchase readiness,
entitlement, and final SDK readback, so a cancelled or stale `401` owner cannot
regenerate or publish Auth state. `AuthSessionRecoveryLiveService+Live.swift`
alone performs the recovery refresh, read, and local sign-out SDK operations;
`AuthSessionRecoveryLiveDiagnostics.swift` maps value-only outcomes to the
existing privacy-safe live log copy. Durable ghost-merge and purchase-handoff
models, validation, and verified Keychain persistence live in
[`Core/Security/GhostProfileMerge`](../../Security/GhostProfileMerge/README.md)
and
[`Core/Security/PurchaseIdentity`](../../Security/PurchaseIdentity/README.md),
respectively. The latter also owns keyed purchase resolution, binding state,
foreground readiness repair, and the typed legacy-profile query boundary; the
manager injects their live SDK, endpoint, persistence, and diagnostic effects.
`AppleCredentialRevocationLiveProvider.swift` alone owns the
AuthenticationServices notification token and credential-state lookup, while
`AppleCredentialRevocationLiveDiagnostics.swift` maps value-only outcomes to the
existing privacy-safe log copy. The manager owns only their composition and maps
its current SDK user to the exact provider-neutral identity. Existing externally
consumed signatures, access levels, error copy, actor isolation, and successful
transition behavior remain unchanged. Bootstrap admission is now intentionally
narrower for callers already cancelled, callers cancelled while waiting for
sign-out, and tasks whose stored transition token is no longer the active owner.

Token ownership alone is not sufficient after a suspension. Every
account-deletion preparation, commit, intake, recovery, and acknowledgement
result that can advance or retire durable state is admitted only while the
coordinator still owns the exact expected UUID, anonymous/account kind, and Auth
generation. Prepared-v2 failures are checked before outer recovery
classification. That check applies to failure results as well as success, so a
stale definitive rejection cannot clear a newer session's deletion fence.
Ordinary `401` recovery likewise accepts only a refreshed copy of its original
exact session; it cannot adopt a replacement account.

The Auth-session lifecycle coordinator revalidates the exact manager-published
user, nonexpired SDK session, Auth-event generation, and absence of an active
Auth transition after every suspending purchase or entitlement phase. Signed-out
handling repeats that fence after purchase cleanup before clearing linked-user,
public-author, Apple-revocation, or Ghost-merge state. When a listener event is
deferred by a transition, `AuthLifecycleReplayCoordinator` replays one snapshot
of the current SDK state after the transition finishes; a newer SDK event or
transition invalidates that snapshot and retained task. The manager-owned
deferred preferred-name and historical-scan task repeats the same exact-session
fence before each account-leased synchronization step.

A Google provider result checks cancellation both before presentation and after
provider return. Shared OAuth completion checks cancellation before direct
provider linking and after session replacement, Apple registration, metadata,
authenticated publication, telemetry, entitlement, expected-session readback,
and public-author refresh. The replacement workflow reports whether it
installed, failed, or was cancelled so cancellation after SDK installation
cannot republish the new target as successful. Cancellation before installation
reconciles the still-valid source; cancellation after any session mutation fails
closed, records the exact mutated target on the transition, and admits that
exact target to terminal local cleanup. Apple registration cancellation never
consumes a retry.

The fallback authentication-callback coordinator preserves the product rule that
callback URLs may establish a session only from no local session or refresh the
same permanent account; they cannot upgrade an anonymous identity or switch
accounts. It reuses the shared replacement disposition, rejects overlap and
pending purchase continuity before SDK mutation, and stops cancelled work after
preflight. Immediately after session installation, the live boundary records the
exact target as the transition expectation before cancellation can be observed.
That recovery-only adoption does not accept the callback: the coordinator still
validates cancellation, source/target policy, transition ownership, and sign-out
state before publication or completion. After purchase and entitlement
suspension it revalidates cancellation plus the exact transition session. An
already-mutated failed or cancelled callback enters completion-owned cleanup for
only that installed target. Supabase URL conversion, captured SDK-user
capabilities, purchase and entitlement effects, the authenticated marker, and
diagnostic copy remain live facade adapters.

The Auth-session bootstrap coordinator waits for active sign-out, stores and
rechecks the task's complete transition token, and shares work only while that
token remains the exact active owner. Ownerless callers may join only the active
anonymous-bootstrap token. The coordinator waits for admitted account work to
drain before resolving an SDK session. An already-published usable session is
reused only under an exact-session account-work lease. Caller cancellation is
checked both before and after sign-out waiting, before any lease, transition, or
SDK-session operation can begin. Every loaded or created session must be adopted
by the active transition before publication and must still match the
manager-published, nonexpired SDK session after purchase readiness completes.
Cancellation is checked again at that post-readiness boundary before an identity
can be returned. Cancelling bootstrap clears only its own keyed handle, so a
late predecessor cannot clear replacement work.

The focused bootstrap service performs only cached/loaded SDK-session
projection, anonymous sign-in, and missing-session classification.
`SupabaseManager` maps its SDK user into the established publication,
purchase-readiness, public-author-refresh, and final-session closures and
preserves the public `User?` result.

The Auth-session recovery coordinator opens one recovery transition for an
ordinary refresh, anonymous replacement, or terminal local clear. A caller that
already owns a deletion/OAuth transition uses the same coordinator without
opening or finishing a nested transition. Every refresh captures the exact
expected session before account-work quiescence and refuses a different SDK
identity afterward. Terminal clear applies the same captured expected/current-
session fence after quiescence and returns a typed outcome instead of implying
that a blocked cleanup succeeded. Anonymous recovery additionally requires
purchase identity, entitlement, captured-generation, and final SDK readback
agreement. Local clear checks cancellation before mutation and preserves the
session while any durable purchase handoff is pending; after local SDK sign-out
starts, observable, Keychain, analytics, and purchase cleanup completes even if
the SDK call fails or caller cancellation arrives. The explicit
`completeMutatedOAuthSession` entry policy is restricted to failure recovery for
an OAuth or authentication-callback transition that already changed the SDK
session; ordinary and pre-mutation cleanup still rejects a cancelled caller.

Both stable and legacy purchase-continuity completion verify cancellation, the
exact anonymous manager-published user, nonexpired SDK session, captured Auth
generation, and transition context after each suspended phase and immediately
before durable proof removal. When no transition owns a lifecycle retry, that
context requires the absence of any active transition; the completion becomes
invalid as soon as one opens, even before it produces an SDK event.

Linked-source discovery and stable rotation preparation also revalidate the
exact transition before and after their suspending telemetry, SDK, and resolver
work. Stable and compatibility preparation persist every returned one-use proof
before honoring cancellation, then stop before the next session or Auth phase.
If source-side stable proof retirement succeeds but its verification reread
fails, the coordinator restores the fail-closed purchase-readiness fence instead
of exposing an indeterminate journal as absent.

A successful direct provider link may retire durable provider-bound ghost-merge
recovery only after the SDK exposes a permanent session with the original
anonymous UUID, the policy admits that exact upgrade, and the active transition
adopts and revalidates it. Token ownership or a successful SDK call alone cannot
clear the queue.

Deferred noncommit recovery adopts and revalidates the exact cached source while
the durable marker still blocks account work, removes and reads back that
marker, then publishes the already-validated session without another failable or
suspending stage. Foreground lifecycle recovery owns optional telemetry and
entitlement retries after this commit point. Failed linked-account sign-out may
restore purchase readiness only after re-adopting its verified original source
into the same transition coordinator.

Provider-neutral Coordinators, Models, Policies, and service boundaries may not
import AuthenticationServices, GoogleSignIn, or the Supabase SDK, resolve a live
singleton, or add an unlisted task owner. The named provider Services and
SDK-facing OAuth session service are the only Auth owners that may acquire their
documented framework or Supabase edge. Task ownership is limited to the sign-out
single-flight in `AuthTransitionCoordinators.swift`, Auth-session bootstrap in
`AuthSessionBootstrapCoordinator.swift`, keyed purchase completion in
`PurchaseIdentityHandoffCoordinator.swift`, keyed Ghost-merge completion in
`GhostProfileMergeCoordinator.swift`, and restored-session public-author refresh
in `PublicAuthorIdentityRefreshCoordinator.swift`, plus Apple credential
revalidation in `AppleCredentialRevocationCoordinator.swift` and conditional
deferred-listener replay in `AuthLifecycleReplayCoordinator.swift`. Keep wire
DTOs and endpoint transport with their existing domain owners.

## Verification

`MerianTests/Core/Network/Auth/AuthTransitionFoundationTests.swift` owns the
deterministic coordinator—including the expected signed-out event path—lease,
presentation, error-copy, and single-flight tests rehomed from
`SupabaseManagerTests`. `AuthRuntimeStateTests.swift` owns six deterministic
cases for observable transition invalidation, exclusive transition/analytics
completion, expected and unexpected Auth-generation observation, dual-projection
exact-session work admission, multi-lease drain completion, and sign-out
generation invalidation. `AuthTransitionPolicyTests.swift` owns the adoption,
transition admission, listener/request fence, provider callback, OAuth
rollback/metadata, exact direct-link upgrade, purchase-handoff, and explicit
nil-session and ownerless-request defaults across ten deterministic cases.
`AuthSessionBootstrapCoordinatorTests.swift` owns twenty deterministic cases for
test/deletion and caller-cancellation gates, cancellation during sign-out
waiting, sign-out and quiescence ordering, current-session reuse, stale
account-work rejection, exact-token ownerless sharing, replaced-transition and
different-owner isolation, true-missing anonymous creation and creation failure,
network-failure identity preservation, cancellation and transition drift around
session load, compare-before-clear task replacement, resolved-session
publication order, cancellation during loaded and newly created purchase
readiness, and session replacement during purchase readiness. The aggregate
manager suite no longer owns bootstrap task serialization.
`AuthSessionBootstrapLiveServiceTests.swift` owns five deterministic cases for
cached/loaded identity and expiry projection, newly anonymous fresh-session
projection, exact SDK and compatibility missing-session classification,
unrelated-error rejection, and SDK failure forwarding.
`AuthSessionRecoveryCoordinatorTests.swift` owns eighteen deterministic cases
for ordinary and transition-owned refresh, preflight and in-flight cancellation,
expected-session drift, anonymous purchase/entitlement readiness, final SDK
replacement, pending-handoff preservation, local SDK sign-out failure,
cancellation after SDK sign-out begins, caller-owned transition lifetime,
completion-owned entry for a cancelled OAuth transition that already mutated its
session, exact adopted-target cleanup, and replacement-session rejection after
terminal-clear quiescence. The aggregate manager suite retains only live effect
assembly for those entry points. `AuthSessionRecoveryLiveServiceTests.swift`
owns five deterministic cases for refreshed/loaded identity and SDK-user
projection, exactly-once local sign-out, and refresh, load, and sign-out failure
forwarding. `AccountDeletionTransitionPolicyTests.swift`,
`AccountDeletionIntakeWorkflowTests.swift`, and
`AccountDeletionCleanupWorkflowTests.swift` own the pure classification,
prepared/durable intake, cleanup, retirement, and deferred-restoration
regressions rehomed from the aggregate. `AccountDeletionCoordinatorTests.swift`
and `AccountDeletionRecoveryCoordinatorTests.swift` cover fresh v2 ordering,
preflight fences, every material marker route, accepted and uncommitted
recovery, legacy replay, acknowledgement failure, retirement, and stale
cached-session refusal across the live closure boundary. They also lock
proofless prepared-v2 cancellation and raw-v1 proof continuity across an
ambiguous pre-capability replay, and prove that an installed mixed v2 envelope
checks legacy recovery before restoration. Together with the intake suite's
overlap cases, they prove that stale legacy or prepared-v2 failures cannot
retire deletion intent and that a cached session cannot be published after
failed exact-session revalidation. The intake suite also covers cancellation
before persistence, after the durable legacy marker, after non-destructive v2
preparation, and after both v2 markers; none may dispatch destructive work.
Cleanup coverage also proves unsuccessful, prepared, and `not_committed`
receipts cannot persist a cleanup marker, sign out, or erase local data.
`PurchaseIdentitySignOutWorkflowTests.swift` owns the ordinary and purchase-safe
sign-out ordering regressions rehomed from the aggregate manager suite,
including preflight cancellation, cancellation between every identity phase,
cancellation before and immediately after the legacy server destination bind,
and proof retention after a failed provider stage.
`PurchaseIdentitySignOutCoordinatorTests.swift` adds seventeen deterministic
route-level regressions for stable and legacy source preparation, initial and
post-retirement unreadable journals, existing anonymous destinations, unrelated
linked sessions, source-only restoration, unverified linked sessions, ordinary
anonymous replacement, exact anonymous recovery retry, recovery quiescence
failure, cancellation after anonymous initialization, cancelled transition
admission, and recovery-only reset admission.
`PurchaseIdentitySourceHandoffCoordinatorTests.swift` adds fifteen deterministic
cases for aggregate fail closure, stable and compatibility post-preparation
session drift, cancellation during compatibility preparation's final SDK-session
read, exact-source cancellation and retirement, stale-cancel proof retention,
unowned account-work acquisition/release, pre-dispatch and pre-removal
invalidation, failed-sign-out restoration order, pending-proof refusal, and
preflight cancellation. `PurchaseIdentityHandoffAuthJournalTests.swift` freezes
the exact legacy/stable Auth error mapping and underlying clear-error
propagation. Core Security's
`PurchaseIdentityHandoffPreparationCoordinatorTests.swift` freezes both stable
durability checkpoints, stable and compatibility post-remote cancellation, exact
compatibility-proof mapping, and invalid-binding refusal before side effects.
`PurchaseIdentityHandoffCoordinatorTests.swift` adds eleven deterministic cases
for already-cancelled caller preflight, stable and compatibility completion
order, same-context single-flight, same-session transition-owner replacement,
replacement-generation cancellation, suppression of late cancelled-task
projection/proof mutations, stale-session proof retention, terminal-only
compatibility retirement, unreadable-journal fail-closure, and restored-source
abandonment. `LegacyPurchaseHandoffRemoteServiceTests.swift` separately freezes
typed operation forwarding and the exact terminal proof classifier.
`PurchaseIdentitySessionCoordinatorTests.swift` covers stable and legacy
resolution, durable-journal fence projection and fail closure, exact-generation
rejection, stale final-admission cache rejection, ready-state elision, keyed
single-flight, and differently keyed task supersession;
`PurchaseIdentityReadinessCoordinatorTests.swift` covers account-work-fenced
foreground repair, restored-source handling, entitlement order, and its final
session/provider fence. `LegacyPurchaseIdentityProfileServiceTests.swift`
freezes typed profile forwarding without a live Supabase client.
`GhostProfileMergePolicyTests.swift`, `GhostProfileMergeWorkflowTests.swift`,
and `GhostProfileMergeCoordinatorTests.swift` own stable queue replacement,
durable preparation, provider-transition and changed-session rejection, keyed
completion/supersession, queue-wide retry, terminal cleanup, phase ordering,
proof retention, and cancellation before and after every asynchronous phase.
`GhostProfileMergeRemoteServiceTests.swift` owns typed operation forwarding plus
provider-conflict and terminal-error adaptation.
`PublicAuthorIdentityRefreshCoordinatorTests.swift` owns eighteen deterministic
cases for scheduling gates, stale-target rejection, merge/lease/refresh/
publication order, same-target coalescing, replacement compare-before-clear
safety, cancellation before scheduled or direct admission and across remote
suspension, cancellation-diagnostic suppression, stale leases, published-user
drift, remote failure, transition-owned preflight and postflight session
fencing, ownerless refresh, and completed-marker reset.
`AppleCredentialRevocationCoordinatorTests.swift` owns seventeen deterministic
cases for transition deferral, authorized preservation, fail-closed provider
states and lookup failure, same-identity generation drift, identity replacement,
transition overlap during lookup and at terminal-clear admission, exact-identity
revalidation at that admission boundary, recovery deferral without immediate
retry, explicit stable resume, context change during deferred clear without a
lost wakeup, notification coalescing, cancellation, coordinator release during a
suspended lookup, and exactly-once clear. The four-case
`AppleCredentialRevocationLiveProviderTests.swift` suite owns the Apple SDK
state-to-domain mapping plus observer replacement, explicit stop,
provider-deinitialization cleanup, and off-main notification delivery into the
main-actor handler. `OAuthIdentityTokenPolicyTests.swift`,
`OAuthSignInModelsTests.swift`, `OAuthSignInWorkflowTests.swift`,
`OAuthSignInCoordinatorTests.swift`, `OAuthSignInCancellationTests.swift`,
`OAuthProviderSignInCoordinatorTests.swift`,
`GoogleOAuthAuthorizationLiveProviderTests.swift`, and
`AppleOAuthAuthorizationLiveProviderTests.swift` own token validation, metadata
normalization, replacement disposition and registration retry, direct-link and
Ghost fallback, exact completion order, provider admission and callback/task
ownership, provider value mapping, Apple nonce/controller retention, Google
pre/post-return cancellation, provider/transition and registration
configuration, cancellation after each suspended completion phase, and failure-
stop behavior. `AppleOAuthCredentialRegistrationServiceTests.swift` separately
owns exact operation forwarding, strict receipt rejection, and transport-error
propagation. `OAuthSessionServiceTests.swift` owns seven deterministic cases for
SDK-session reads and snapshots, Apple/Google credential mapping, session
projection, canonical metadata aliases, empty-update suppression, and SDK-error
propagation. `AuthenticationCallbackCoordinatorTests.swift` owns fifteen
deterministic cases for success ordering, pending-handoff and active-transition
overlap rejection, pre-install cancellation, anonymous-source refusal, exact
account refresh, different-account cleanup, installation failure before and
after SDK mutation, sign-out overlap, cancellation during installation, purchase
readiness, and entitlement loading, purchase-identity failure, and final-session
drift. The workflow suite retains the rehomed test method names from
`SupabaseManagerTests`. The Core Network integration architecture suite freezes
all sixty production owners, including the effect-free observable runtime-state
owner, focused SDK listener/current-state adapter, retained historical-sync task
owner, lifecycle diagnostics, and the listener's
generation/context/transition-observation order; the fallback-callback
dependency package, coordinator, and diagnostics split, the Auth-session
bootstrap dependency/coordinator pair plus focused SDK service/live adapter and
diagnostics, the recovery dependency/coordinator pair, lifecycle
model/dependency/coordinator plus the lifecycle replay task owner, Apple
credential-revocation dependency/coordinator; provider-neutral OAuth
model/policy/workflow/completion and provider-admission coordinator boundaries;
and focused Apple/Google live-provider ownership, the one-invocation Apple
registration adapter, and the OAuth SDK session boundary. For that boundary it
scans every Core Network Swift source and requires OIDC and `UserAttributes`
construction to remain exclusive to the service core while direct Supabase Auth
link, install, and metadata-update calls remain exclusive to its `+Live`
adapter. It also freezes their absence of retry policy, asynchronous task,
facade, and alternate transport ownership, the four deletion-policy functions,
nine deletion-workflow helpers, the three purchase-sign-out workflow helpers,
and the sign-out, source-handoff, and destination-handoff coordinator/dependency
boundaries, the Auth journal adapter, and the Core Security preparation owner,
plus the ghost-merge policy/workflow/dependency/coordinator inventories;
enforces their dependency boundary, weak facade capture for replay, and 600-line
ceiling; prevents the aggregate manager from reacquiring either the current or
legacy declarations, task fields, and helper names; and locks the live result,
refresh, telemetry, deferred-restoration, and failed-sign-out paths to the exact
session coordinator. It also freezes direct provider-link ordering so durable
ghost-merge recovery cannot retire before the same-UUID permanent destination is
adopted and revalidated. The Ghost merge cross-surface contract separately pins
manager delegation for both direct identity linking and replacement-session
installation, and rejects either direct SDK call returning to the facade. The
replacement-cancellation regression suspends before simulated SDK mutation,
cancels the caller, then resumes through mutation and an immediate cancellation
check; it must record both the mutation and exact transition expectation while
refusing completion and publication. The architecture suite also freezes the
main-actor-isolated facade teardown list, including the two extracted task
owners, and the residual generic Supabase Auth operation inventory in
`SupabaseManager`. `PurchaseIdentityHandoffStoreTests.swift` independently locks
exact local JSON field compatibility, fail-closed journal validation before
writes and after reads, device-only accessibility, write verification, and
exact-key removal. `GhostProfileMergeStoreTests.swift` independently locks the
equivalent ghost queue boundary, including legacy migration, server-owned
expiry, and proof-preserving migration failure. `ConsentManagerRestorationTests`
remains the consumer-level regression proving an expired cached session keeps
its launch root qualified to that account while SDK refresh is pending.

The live-task integration case additionally freezes post-suspension listener
fences, conditional deferred-listener replay, signed-out postflight admission,
coordinator-owned anonymous-bootstrap publication, stable and compatibility
proof retirement in the handoff coordinator, Google provider cancellation,
post-mutation OAuth cleanup, and coordinator-owned compare-before-clear
public-author task ownership. It also requires Auth-context generation, exact
identity postflight, exact-identity terminal-clear admission, typed recovery
outcomes, no-loop deferral, deferred-clear context-change replay, aggregate
purchase-handoff resolution replay, and compare-before-clear cleanup for Apple
credential revalidation. It freezes the terminal-clear post-quiescence session
fence, post-readiness bootstrap cancellation, and stale Apple callback token
retirement. The direct-link source guard also requires cancellation immediately
before the SDK identity mutation. `SupabaseManagerTests` retains live Supabase
Auth adapter classification and facade assembly; provider authorization, Apple
credential-state, and observation behavior belong to the focused live-provider
suites. Deterministic provider admission, OAuth replacement, and completion no
longer depend on the aggregate manager suite.

`AuthSessionLifecycleCoordinatorTests.swift` owns fifteen deterministic cases
for deletion and transition deferral, independent durable-store fail closure,
identity-change reset order, anonymous and restored-source purchase handoffs,
stale Auth-generation and transition overlap after purchase and entitlement
suspension, awaiting-refresh projection, sign-out overlap, signed-out cleanup
order, replay-owner-driven deferred sign-out cleanup, stale signed-out
postflight rejection, and malformed-event rejection. The deletion-barrier case
requires the local server-verified entitlement projection to close before
recovery continues. `AuthLifecycleReplayCoordinatorTests.swift` owns five
deterministic cases for replacement cancellation, carrying an obligation across
a new transition, clearing it for a newer stable event, owner release during a
suspended replay, and the no-deferred-event no-op boundary.
`AuthSessionLifecycleLiveProviderTests.swift` owns seven deterministic cases for
SDK-state projection, exact listener prelude order, deferred current-state
replay, stale snapshot rejection, restart cleanup, canceled trailing-effect
rejection, and listener teardown without self-retention.
`AuthHistoricalSessionSyncLiveServiceTests.swift` owns three deterministic cases
for timestamp/preference/scan order, the post-preference exact-session fence,
and owner-release cancellation during suspended synchronization.

The Edge client-source contracts deliberately read these extracted owners.
`accountDeletionCoverage.test.ts` pins both deletion coordinators to
`AccountDeletionWorkflow` and reads the Apple authorization live provider,
provider sign-in coordinator, facade assembly, and OAuth coordinator/workflow
for one-use credential-capture routing, exact provider completion, and bounded
retry; `purchasePrincipalMigrationContract.test.ts` reads the Auth-session
lifecycle coordinator and pins awaiting-refresh, accepted-deletion
purchase/entitlement closure, and sign-out ordering alongside the two-journal
fail-closed reread, stable/compatibility completion coordinator, and
compatibility route adapter; and `ghostProfileMergeClientContract.test.ts` reads
`SupabaseManager`, the OAuth coordinator, models, token policy, replacement
workflow, SDK session service/live adapter, and cancellation suite, the Ghost
coordinator, dependencies, typed merge service/live adapter, store, policy,
workflow, and focused tests, plus the Consent facade, runtime, cloud-session
core/live adapter, state projection, synchronization, restoration, Realtime,
repository, retry, merge, and focused tests to pin Ghost completion, verified
consent persistence before publication, account-work lease/session adoption,
owner-filtered Realtime construction and retry fencing, complete
synchronization-task draining, UUID-keyed restoration retry retention through
exact completion and the combined Auth-transition drain, canceled-retry
admission after manual retry reuses an attempt number, stale-account rejection,
and target-consent ordering. Any owner or test rehome must update the
corresponding Deno path and focused contract atomically.

See the canonical
[Core manager guide](../../../../../../docs/development-guides/09-core-managers.md#supabasemanager),
[purchase-principal contract](../../../../../../docs/rfcs/purchase-principal-auth-separation.md),
and [Core Network guide](../README.md).
