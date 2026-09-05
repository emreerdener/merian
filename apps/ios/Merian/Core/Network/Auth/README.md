# Core Network Auth

This folder owns the value-only foundation used to serialize Merian account
transitions and fence account-bound work. It does not own Supabase SDK calls,
OAuth presentation, durable Keychain journals, purchase-identity mutation,
account-deletion execution, or application lifecycle effects.

## Ownership

- `Models/SupabaseAuthTransitionModels.swift` owns transition providers, kinds,
  phases, sessions, tokens, state, cold-start adoption outcomes, account-work
  leases, and the existing user-facing transition errors.
- `Policies/AccountPresentationPolicy.swift` owns the deterministic decision
  that maps a missing or anonymous Auth session to Guest presentation.
- `Policies/AuthTransitionPolicy.swift` owns deterministic transition admission,
  transition-owned request and listener fencing, provider-callback acceptance,
  OAuth rollback and metadata guards, cold-start session classification, and
  purchase-identity handoff/restoration decisions.
- `Coordinators/AuthTransitionCoordinators.swift` owns the value-state machines
  for exclusive transition admission and exact-session work leases, plus the
  main-actor Boolean single-flight used by sign-out.

`SupabaseManager.swift` remains the live orchestrator. It owns the Supabase Auth
listener, applies the extracted session-adoption decision, invokes OAuth
providers, advances the extracted transition state, drains account-bound work,
coordinates purchase identity and consent, and executes the durable sign-out,
recovery, and account-deletion workflows. Provider-dependent Apple credential
state remains manager-owned. Existing externally consumed signatures, access
levels, error copy, actor isolation, and transition behavior remain unchanged.

No file in this folder may import AuthenticationServices, GoogleSignIn, or the
Supabase SDK, resolve a live singleton, or add a second task owner. Keep wire
DTOs and endpoint transport with their existing Core Network owners.

## Verification

`MerianTests/Core/Network/Auth/AuthTransitionFoundationTests.swift` owns the
deterministic coordinator—including the expected signed-out event path—lease,
presentation, error-copy, and single-flight tests rehomed from
`SupabaseManagerTests`. `AuthTransitionPolicyTests.swift` owns the adoption,
transition admission, listener/request fence, provider callback, OAuth
rollback/metadata, purchase-handoff, and explicit nil-session and
ownerless-request defaults. The Core Network integration architecture suite
freezes the four production owners, enforces their dependency boundary and
600-line ceiling, and prevents the aggregate manager from reacquiring their
declarations or policy functions. `ConsentManagerRestorationTests` remains the
consumer-level regression proving an expired cached session keeps its launch
root qualified to that account while SDK refresh is pending.

See the canonical
[Core manager guide](../../../../../../docs/development-guides/09-core-managers.md#supabasemanager),
[purchase-principal contract](../../../../../../docs/rfcs/purchase-principal-auth-separation.md),
and [Core Network guide](../README.md).
