# Ghost Profile Merge

This folder owns the durable on-device handoff queue and typed remote boundary
used when an anonymous profile must be merged after a provider-bound permanent
session replaces it. It does not own RevenueCat mutation, consent
synchronization, Auth-session mutation, orchestration task lifetime, logging, or
user-facing presentation.

## Ownership

- `Models/GhostProfileMergeModels.swift` defines the exact persisted handoff and
  version-1 queue shapes. Explicit coding keys freeze the existing camel-case
  JSON fields used by installed clients.
- `Stores/GhostProfileMergeStore.swift` owns encoding and decoding, legacy
  single-record migration, fail-closed validation before writes and after reads,
  the established Keychain key, `WhenUnlockedThisDeviceOnly` accessibility,
  byte-for-byte write verification, and verified removal. Its small closure
  dependencies are initializer-injected; the store resolves no singleton and
  performs no network or provider work.
- `Services/GhostProfileMergeRemoteService.swift` defines the closure-backed,
  provider-neutral prepare, complete, identity-refresh, and error-classification
  boundary. `Services/GhostProfileMergeRemoteService+Live.swift` is the sole iOS
  owner of the private `merge-ghost-profile` request/response DTOs, Supabase
  Function invocation, provider-conflict classification, and terminal
  handoff-error mapping.

`Core/Network/Auth/Policies/GhostProfileMergePolicy.swift` owns stable queue
replacement and terminal server-code classification.
`Core/Network/Auth/Coordinators/GhostProfileMergeWorkflow.swift` owns the
deterministic completion order through injected effects.
`GhostProfileMergeCoordinator` owns durable preparation, exact source and
provider-transition admission, exact target admission, target-and-owner-keyed
completion task replacement, queue-wide retry, analytics suppression, terminal
cleanup, and proof removal. Its narrow dependency package contains no live SDK
or singleton. A returned server capability is persisted before caller
cancellation may stop subsequent OAuth work; a cancelled or superseded
completion cannot synchronize target evidence or remove proof. `SupabaseManager`
constructs the live store and remote service, injects Auth, RevenueCat, consent,
Keychain, and diagnostics effects, and remains the compatibility facade.

Malformed evidence is rejected before storage and malformed or unreadable
restored evidence is never treated as absence. A write is not accepted until the
exact bytes can be read back. If a legacy proof remains readable but its
best-effort queue migration cannot be verified, the proof stays usable and the
migration is retried on a later load. The store validates the server timestamp
shape but does not classify expiry from the device clock; only the idempotent
server completion endpoint decides that a handoff is terminal.

## Verification

`GhostProfileMergeStoreTests` covers absence, exact persisted field names, queue
round trips, legacy migration and deferred migration, malformed or unsupported
evidence, server-owned expiry, rejection before secure-storage dispatch, failed
or unverifiable writes, device-only accessibility, case-insensitive exact
removal, and secure-store error propagation. `GhostProfileMergePolicyTests` and
`GhostProfileMergeWorkflowTests` freeze stable replacement, cancellation
boundaries, phase order, and proof-removal-last sequencing.
`GhostProfileMergeCoordinatorTests` covers durable preparation under
cancellation, stable replacement, provider-transition mismatch and post-response
source-session drift, keyed single-flight and supersession, unreadable-queue
fail closure, retryable and terminal outcomes, later-proof progress, suppression
reopening, and source-scoped clearing. `GhostProfileMergeRemoteServiceTests`
owns typed forwarding plus provider and terminal error classification. The Core
Network integration architecture suite prevents these declarations, wire DTOs,
orchestration, and storage rules from drifting back into the aggregate manager.
`services/supabase/functions/_tests/ghostProfileMergeClientContract.test.ts`
reads `SupabaseManager`, the OAuth owner and SDK session service/live adapter,
Ghost coordinator and dependencies, typed merge service and live adapter, store,
policy, workflow, and focused tests, plus the Consent owners. Those direct
inputs require the manager to delegate both direct identity linking and
replacement-session installation, require the live adapter to own both SDK
operations, reject direct SDK reacquisition by the facade, and require a
successful replacement to record its mutation and exact target transition
expectation before post-install cancellation. They also keep durable
preparation, keyed retry, terminal-only retirement, cancellation/stale-account
fences, provider and local evidence completion, verified consent persistence,
and proof-removal-last joined to the Edge contract. Moving any input requires
updating and running that Deno contract in the same change.

See the canonical
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
[API contract](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-merge-ghost-profile-edge-node),
and
[revenue identity guide](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md).
