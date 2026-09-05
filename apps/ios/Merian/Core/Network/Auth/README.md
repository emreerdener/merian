# Core Network Auth

This folder owns the value-only foundation used to serialize Merian account
transitions and fence account-bound work, plus deterministic account-deletion
classification, ghost-profile-merge policy, and closure-injected deletion,
purchase-safe sign-out, and ghost-merge phase sequencing. It does not own
Supabase SDK calls, OAuth presentation, durable Keychain journals,
purchase-identity mutation, endpoint transport, local-data purge, or application
lifecycle effects.

## Ownership

- `Models/SupabaseAuthTransitionModels.swift` owns transition providers, kinds,
  phases, sessions, tokens, state, cold-start adoption outcomes, account-work
  leases, and the existing user-facing transition errors.
- `Policies/AccountPresentationPolicy.swift` owns the deterministic decision
  that maps a missing or anonymous Auth session to Guest presentation.
- `Policies/AuthTransitionPolicy.swift` owns deterministic transition admission,
  transition-owned request and listener fencing, provider-callback acceptance,
  OAuth rollback and metadata guards, exact anonymous-to-permanent provider-link
  admission, cold-start session classification, and purchase-identity
  handoff/restoration decisions.
- `Policies/AccountDeletionTransitionPolicy.swift` owns exact cached-session
  restoration eligibility and the stable HTTP/code classifications for
  definitive intake rejection, matched expired recovery, and unknown v2 recovery
  proof.
- `Policies/GhostProfileMergePolicy.swift` owns stable queue replacement and the
  exact terminal server codes that permit durable handoff retirement.
- `Coordinators/AuthTransitionCoordinators.swift` owns the value-state machines
  for exclusive transition admission and exact-session work leases, plus the
  main-actor Boolean single-flight used by sign-out.
- `Coordinators/AccountDeletionWorkflow.swift` owns deterministic ordering for
  durable and prepared intake, accepted cleanup, capability retirement,
  rejection-proof retirement, deferred-session restoration, and pending local
  cleanup through injected closures. Accepted cleanup verifies a successful
  `pending|completed` receipt before invoking its first persistence or erasure
  effect. It owns no live dependency or task.
- `Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns ordinary sign-out
  ordering plus the purchase-safe preparation, local sign-out, anonymous
  replacement, provider/server verification, cancellation checkpoints, and
  proof-removal-last contract through injected closures. It owns no live
  dependency, logger, or task.
- `Coordinators/GhostProfileMergeWorkflow.swift` owns server completion,
  purchase synchronization, local-evidence rebind, cancellation checkpoints, and
  proof-removal-last ordering through injected closures. It owns no live
  dependency, logger, or task.

`SupabaseManager.swift` remains the live orchestrator. It owns the Supabase Auth
listener, applies the extracted session-adoption decision, invokes OAuth
providers, advances the extracted transition state, drains account-bound work,
coordinates purchase identity and consent, and assembles the live SDK, endpoint,
Keychain, sign-out, purge, logging, and lifecycle effects supplied to the
extracted workflows. Durable ghost-merge and purchase-handoff models,
validation, and verified Keychain persistence live in
[`Core/Security/GhostProfileMerge`](../../Security/GhostProfileMerge/README.md)
and
[`Core/Security/PurchaseIdentity`](../../Security/PurchaseIdentity/README.md),
respectively. Provider-dependent Apple credential state remains manager-owned.
Existing externally consumed signatures, access levels, error copy, actor
isolation, and transition behavior remain unchanged.

Token ownership alone is not sufficient after a suspension. Every
account-deletion preparation, commit, intake, recovery, and acknowledgement
result that can advance or retire durable state is admitted only while the
coordinator still owns the exact expected UUID, anonymous/account kind, and Auth
generation. Prepared-v2 failures are checked before outer recovery
classification. That check applies to failure results as well as success, so a
stale definitive rejection cannot clear a newer session's deletion fence.
Ordinary `401` recovery likewise accepts only a refreshed copy of its original
exact session; it cannot adopt a replacement account.

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

No file in this folder may import AuthenticationServices, GoogleSignIn, or the
Supabase SDK, resolve a live singleton, or add a second task owner. Keep wire
DTOs and endpoint transport with their existing Core Network owners.

## Verification

`MerianTests/Core/Network/Auth/AuthTransitionFoundationTests.swift` owns the
deterministic coordinator—including the expected signed-out event path—lease,
presentation, error-copy, and single-flight tests rehomed from
`SupabaseManagerTests`. `AuthTransitionPolicyTests.swift` owns the adoption,
transition admission, listener/request fence, provider callback, OAuth
rollback/metadata, exact direct-link upgrade, purchase-handoff, and explicit
nil-session and ownerless-request defaults across eleven deterministic cases.
`AccountDeletionTransitionPolicyTests.swift`,
`AccountDeletionIntakeWorkflowTests.swift`, and
`AccountDeletionCleanupWorkflowTests.swift` own the pure classification,
prepared/durable intake, cleanup, retirement, and deferred-restoration
regressions rehomed from the aggregate. Their overlap cases additionally prove
that stale legacy or prepared-v2 failures cannot retire deletion intent and that
a cached session cannot be published after failed exact-session revalidation.
Cleanup coverage also proves unsuccessful, prepared, and `not_committed`
receipts cannot persist a cleanup marker, sign out, or erase local data.
`PurchaseIdentitySignOutWorkflowTests.swift` owns the ordinary and purchase-safe
sign-out ordering regressions rehomed from the aggregate manager suite,
including cancellation before and immediately after the legacy server
destination bind and proof retention after a failed provider stage.
`GhostProfileMergePolicyTests.swift`, `GhostMergeEndpointErrorTests`, and
`GhostProfileMergeWorkflowTests.swift` own stable queue replacement, terminal
error adaptation, phase ordering, proof retention, and cancellation before and
after every asynchronous phase. The Core Network integration architecture suite
freezes all nine production owners, the four deletion-policy functions, nine
deletion-workflow helpers, and three purchase-sign-out helpers plus the
ghost-merge policy/workflow inventories; enforces their dependency boundary and
600-line ceiling; prevents the aggregate manager from reacquiring either the
current or legacy declarations and helper names; and locks the live result,
refresh, telemetry, deferred-restoration, and failed-sign-out paths to the exact
session coordinator. It also freezes direct provider-link ordering so durable
ghost-merge recovery cannot retire before the same-UUID permanent destination is
adopted and revalidated. `PurchaseIdentityHandoffStoreTests.swift` independently
locks exact local JSON field compatibility, fail-closed journal validation
before writes and after reads, device-only accessibility, write verification,
and exact-key removal. `GhostProfileMergeStoreTests.swift` independently locks
the equivalent ghost queue boundary, including legacy migration, server-owned
expiry, and proof-preserving migration failure. `ConsentManagerRestorationTests`
remains the consumer-level regression proving an expired cached session keeps
its launch root qualified to that account while SDK refresh is pending.

The Edge client-source contracts deliberately read these extracted owners.
`accountDeletionCoverage.test.ts` pins the manager adapter to
`AccountDeletionWorkflow`; `purchasePrincipalMigrationContract.test.ts` pins the
two-journal fail-closed readiness reread; and
`ghostProfileMergeClientContract.test.ts` pins the Ghost store, policy,
workflow, endpoint-error adapter, and target-consent ordering. Any owner or test
rehome must update the corresponding Deno path and focused contract atomically.

See the canonical
[Core manager guide](../../../../../../docs/development-guides/09-core-managers.md#supabasemanager),
[purchase-principal contract](../../../../../../docs/rfcs/purchase-principal-auth-separation.md),
and [Core Network guide](../README.md).
