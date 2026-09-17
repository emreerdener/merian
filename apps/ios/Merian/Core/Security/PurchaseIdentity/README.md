# Purchase Identity Ownership

This folder owns the iOS purchase-principal domain, secure device state, route
adapters, provider-neutral session readiness, and the two durable purchase-
continuity journals used while iOS changes Supabase Auth identity. It also owns
the narrow live-effects adapter that binds provider-neutral session readiness to
RevenueCat, entitlement, resolver, and legacy-profile operations. It does not
own Supabase Auth mutation, RevenueCat or entitlement state/task lifetime,
sign-out task lifetime, user-facing presentation, or the server-side resolver
implementation.

## Ownership

- `Models/PurchasePrincipalModels.swift` owns the source-compatible resolution,
  binding, rotation result, and resolver-error values. It strictly maps decoded
  responses into validated domain values.
- `Models/PurchasePrincipalWireModels.swift` owns the protocol version and the
  exact decoded response DTOs for resolve and stable sign-out rotation.
- `Models/PurchaseIdentitySessionModels.swift` owns the provider-neutral exact
  Auth-session context, legacy Auth/profile projection and link request, SDK
  snapshot, provider-readiness projection, and account-work lease used by
  identity resolution and foreground repair.
- `Policies/PurchasePrincipalPolicies.swift` owns deterministic capability
  fingerprint, binding-intent generation, legacy-fallback, bounded server
  timestamp, base64url, and rotation-secret rules. The timestamp policy accepts
  20–40 UTF-8-byte values in the fractional PostgreSQL form returned by Edge or
  the whole-second form retained by installed local evidence through the shared
  cached formatters. The fingerprint policy accepts only the exact 64-character
  lowercase SHA-256 shape. These owners perform no storage, networking, or task
  work.
- `Stores/PurchasePrincipalCapabilityStore.swift` owns verified creation and
  retrieval of the 256-bit installation capability.
  `PurchasePrincipalSecureStateStore.swift` owns the stable-activation
  fingerprint and monotonic binding-intent generation. Both use the narrow
  `PurchasePrincipalSecureStore` boundary and preserve the established Keychain
  keys, `WhenUnlockedThisDeviceOnly` accessibility, and exact read-back
  verification.
- `Services/PurchasePrincipalRemoteService.swift` is the closure-injected, typed
  operation boundary. `PurchasePrincipalRemoteService+Live.swift` is the sole
  owner of the private request payloads, Supabase dependency, four
  `resolve-purchase-principal` invocations, and definite-404 classification.
  `PurchasePrincipalSecureRandom.swift` is the single purchase-identity owner of
  `SecRandomCopyBytes`.
- `Services/LegacyPurchaseHandoffRemoteService.swift` is the typed compatibility
  boundary for prepare, bind, complete, cancel, and terminal-proof
  classification. `LegacyPurchaseHandoffRemoteService+Live.swift` alone owns its
  private wire DTOs, Supabase import, all four compatibility operations across
  three `transfer-signout-purchases` SDK invocation paths, response identity
  validation, and exact `handoff_expired`/`handoff_invalid` terminal classifier.
  Complete and cancel share one validated operation helper without changing
  either request action.
- `Services/LegacyPurchaseIdentityProfileService.swift` owns the typed legacy
  profile lookup boundary. Its live companion is the sole owner of the private
  profile DTO, Supabase import, and established `users` projection/query used to
  link legacy provider attributes. The service changes no row or wire shape.
- `Services/PurchaseIdentitySessionLiveService.swift` owns the task-free,
  initializer-injected assembly of legacy attribute precedence, snapshot
  linking, provider resolution/binding, entitlement readiness, and diagnostics.
  It imports no provider SDK, Supabase, logger, or singleton. Its reference
  lifetime is the fail-closed teardown fence for deferred snapshot linking and
  entitlement refresh; both closures weakly capture that owner and cannot start
  their live effect after the Auth facade releases it.
  `PurchaseIdentitySessionLiveService+Live.swift` is the explicit composition
  edge for `RevenueCatManager`, `EntitlementManager`, the resolver, the legacy
  profile query service, the Supabase client required by entitlement refresh,
  and privacy-safe diagnostics. It owns no Auth state, transition admission,
  handoff journal, observable publication, or asynchronous task.
- `Coordinators/PurchaseIdentitySessionCoordinationDependencies.swift` defines
  narrow session-state, provider, handoff, entitlement, and diagnostic closure
  boundaries. `PurchaseIdentitySessionCoordinator.swift` owns active binding and
  last-linked-user state plus one resolution task keyed by exact Auth session,
  capability fingerprint, and creation policy. It revalidates the published
  session before and after every provider suspension, republishes each durable
  handoff read to the provider mutation fence, and publishes a closed fence when
  that state is unreadable. A differently keyed attempt cancels and supersedes
  older resolution work without allowing its late result to publish.
- `Coordinators/PurchaseIdentityReadinessCoordinator.swift` owns foreground
  repair behind an account-work lease: exact SDK-session validation, fail-closed
  journal projection, anonymous completion or restored-source abandonment,
  identity resolution, entitlement readiness, and a final SDK/session/provider
  fence. Both coordinators acquire every live effect through injected closures.
- `PurchasePrincipalResolver.swift` remains the source-compatible `@MainActor`
  facade. It composes the stores and remote service, validates operation
  continuity, persists stable activation, and permits the legacy compatibility
  fallback only for a definite missing route before stable activation.
- `Models/PurchaseIdentityHandoffModels.swift` defines the exact persisted
  legacy handoff and protocol-3 stable-rotation shapes. Explicit coding keys
  freeze the existing camel-case JSON fields used by installed clients.
- `Stores/PurchaseIdentityHandoffStore.swift` owns handoff encoding/decoding,
  fail-closed shape validation before writes and after reads, exact Keychain-key
  selection, device-only accessibility, byte-for-byte write verification, and
  verified removal. Its small closure dependencies are initializer-injected; the
  store resolves no singleton and performs no network or provider work.
- `Coordinators/PurchaseIdentityHandoffPreparationCoordinator.swift` contains
  `PurchaseHandoffPreparationCoordinator`, which owns construction and durable
  checkpointing of source-side continuity evidence. Stable preparation writes
  the exact `preparing` proof before remote work and the server-authorized
  `prepared` proof before honoring post-response cancellation. Compatibility
  preparation maps and persists the returned proof before its cancellation
  checkpoint. The coordinator receives its clock, randomness, persistence, and
  typed remote operations through narrow closures; it owns no Auth-session
  admission, live dependency, or task lifetime.

`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns the
deterministic sign-out and legacy completion order through injected effects,
including cancellation before entry and between preparation, local sign-out,
anonymous initialization, and completion.
`PurchaseIdentitySignOutCoordinator.swift` owns stable-versus-legacy selection,
pending-proof continuation, exact anonymous retry admission, recovery-only reset
admission, and fail-closed post-retirement journal verification through a
separate narrow dependency package. Its retry drains account-bound work before
reading the anonymous SDK session.
`PurchaseIdentitySourceHandoffCoordinator.swift` in Core Network Auth owns
source-side exact-session fencing, aggregate fail-closed journal projection,
exact-source abandonment, and failed-attempt restoration. Cancellation during
compatibility preparation's final SDK-session read cannot report success; the
already-durable proof remains recoverable. Its focused Auth journal adapter
translates store load/persist failures without moving Keychain ownership. Both
abandonment routes repeat their transition or unowned account-work fence after
the initial suspended SDK read and before remote cancellation; stable
abandonment repeats it again after the final SDK read and before durable proof
removal. `PurchaseIdentityHandoffCoordinator.swift` owns completion task
lifetime keyed by destination, Auth generation, and transition owner; protocol-3
claim and compatibility completion routing; exact-session/cancellation fences;
and proof-removal-last policy through an independent dependency package. The
provider-neutral `AuthSessionLifecycleCoordinator` owns listener-driven
readiness projection, including purchase and local entitlement closure behind an
accepted-deletion barrier. `SupabaseManager` constructs the live resolver, the
three route/query services, the session live-effects adapter, the session-
readiness coordinators, and the Auth journal around the handoff store.
`PurchaseIdentityHandoffAuthJournal` maps domain load/persist failures to the
existing Auth-transition errors. The manager retains Auth-owned observable
state, exact-session/account-work admission, handoff closures, and lifecycle
sequencing; the session live-effects adapter exclusively acquires RevenueCat,
entitlement, resolver, profile-query, and diagnostic dependencies for ordinary
session readiness. Source-handoff coordination revalidates that manager-owned
exact transition around linked-source discovery and stable preparation. Each
returned stable or compatibility preparation proof is persisted before
cancellation can stop the next Auth phase. The handoff coordinator rejects an
already-cancelled caller before task admission and its owned task checks
cancellation again before selecting or reading either journal. Before either
journal is removed, it revalidates task cancellation, the exact anonymous
manager-published user, nonexpired SDK session, captured Auth generation, and
transition context. A completion without a transition owner fails as soon as
another Auth transition opens, including before its first SDK event.

Malformed evidence is rejected before storage and malformed or unreadable
restored evidence is never treated as absence. A write is not accepted until the
exact bytes can be read back. This includes rejecting an invalid activation
fingerprint before the secure-store write closure is invoked. Stable `preparing`
evidence has no expiry; only the server can supply the expiry in `prepared`
evidence. The capability, activation fingerprint, binding-intent generation,
legacy proof, and stable journal retain their existing key names and
wire-neutral local formats.

## Verification

The mirrored `MerianTests/Core/Security/PurchaseIdentity/` package separates
deterministic model, policy, capability-store, and response validation from
secure-state and resolver-interaction coverage. The interaction suite verifies
typed request forwarding, stable activation, route-missing-only fallback, and
prepare/claim/cancel mapping with the fractional server timestamp shape. Store
coverage rejects malformed activation evidence before any secure write and
accepts both supported timestamp forms. The architecture suite freezes
declaration uniqueness, the exact owner inventory, dependency confinement, all
three route/query live adapters plus the session live-effects adapter, private
payload ownership, facade delegation, and file-size ceilings.

`PurchaseIdentityHandoffStoreTests` covers both installed journal formats,
validation, exact keys, accessibility, verified writes/removal, and secure-store
failures. `PurchaseIdentitySignOutWorkflowTests` freezes cancellation and phase
ordering across every identity boundary;
`PurchaseIdentitySignOutCoordinatorTests` freezes route selection, pending
recovery, unrelated-source refusal, source restoration, initial and
post-retirement unreadable-journal handling, exact anonymous retry, recovery
quiescence, cancelled admission, and recovery-only reset admission.
`PurchaseIdentitySourceHandoffCoordinatorTests` covers fifteen deterministic
cases for aggregate fail closure, stable and compatibility preparation fences,
cancellation during compatibility preparation's final SDK-session read,
exact-source abandonment, stale-cancel proof retention, unowned account-work
lifetime and pre-dispatch/pre-removal invalidation, failed-sign-out restoration,
pending-proof refusal, and preflight cancellation.
`PurchaseIdentityHandoffAuthJournalTests` freezes exact error translation and
clear-error propagation, while
`PurchaseIdentityHandoffPreparationCoordinatorTests` covers stable checkpoint
order, stable and compatibility post-remote cancellation, compatibility mapping,
and invalid-binding refusal. `PurchaseIdentityHandoffCoordinatorTests` covers
cancelled-caller preflight, stable and compatibility completion order,
same-context single-flight, transition-owner and stale-generation replacement,
session-proof fencing, terminal-only retirement, unreadable-journal behavior,
and restored-source abandonment. `LegacyPurchaseHandoffRemoteServiceTests`
freezes typed operation forwarding and terminal classification.
`PurchaseIdentitySessionCoordinatorTests` covers stable and legacy linking,
pending/unreadable journal projection and fail closure, stale-generation
rejection, stale final-admission cache rejection, already-ready elision,
same-context single-flight resolution, and differently keyed task supersession.
`PurchaseIdentityReadinessCoordinatorTests` covers foreground admission,
account-work completion, fail-closed journal publication, anonymous completion,
restored-source retirement, already-ready identity/entitlement reuse, and the
final post-entitlement generation fence.
`PurchaseIdentitySessionLiveServiceTests` freezes legacy profile precedence,
blank-Auth public fallback, profile-failure fallback, account-kind mapping,
provider/entitlement/diagnostic forwarding, exact-account legacy readiness, and
owner-release rejection for deferred legacy linking and entitlement refresh
independently of Supabase and the provider SDK.
`LegacyPurchaseIdentityProfileServiceTests` freezes exact account and projection
forwarding independently of Supabase. The cross-language
`purchasePrincipalMigrationContract.test.ts` pins the iOS protocol and live
route linkage, including the three route/query live adapters and the session
live-effects adapter, both session-readiness coordinators, the source-handoff/
Auth-journal owners, and the preparation coordinator alongside the Edge and
database contracts.

See the canonical
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
[API contract](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-resolve-purchase-principal-edge-node),
[revenue identity guide](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
and
[purchase-principal RFC](../../../../../../docs/rfcs/purchase-principal-auth-separation.md).
