# Ghost Profile Merge Storage

This folder owns the durable on-device handoff queue used when an anonymous
profile must be merged after a provider-bound permanent session replaces it. It
does not own Supabase requests, RevenueCat mutation, consent synchronization,
Auth-session mutation, task lifetime, logging, or user-facing presentation.

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

`Core/Network/Auth/Policies/GhostProfileMergePolicy.swift` owns stable queue
replacement and terminal server-code classification.
`Core/Network/Auth/Coordinators/GhostProfileMergeWorkflow.swift` owns the
deterministic completion order through injected effects. `SupabaseManager`
constructs the live store with `KeychainManager`, adapts storage failures to the
existing Auth-transition error, and retains Auth, endpoint, RevenueCat, consent,
session-fence, retry, lifecycle, and logging orchestration.

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
removal, and secure-store error propagation. `GhostProfileMergePolicyTests`,
`GhostMergeEndpointErrorTests`, and `GhostProfileMergeWorkflowTests` freeze
stable replacement, terminal-error adaptation, cancellation boundaries, phase
order, and proof-removal-last sequencing. The Core Network integration
architecture suite prevents these declarations and storage rules from drifting
back into the aggregate manager.
`services/supabase/functions/_tests/ghostProfileMergeClientContract.test.ts`
reads `SupabaseManager`, the exact store, policy, workflow, policy test, and
endpoint-adapter test, plus `ConsentManager`,
`ConsentSynchronizationCoordinator`, `ConsentSynchronizationMergePolicy`,
`ConsentRealtimeCoordinator`, `ConsentRealtimeCoordinator+Live`,
`RequiredConsentRestorationCoordinator`, `ConsentLedgerRepository`,
`ConsentRetryPolicy`, `ConsentManagerAuthorityTests`,
`ConsentSynchronizationCoordinatorTests`, `ConsentRealtimeCoordinatorTests`, and
`ConsentRestorationCoordinatorTests`. Those direct source inputs keep this
native split joined to the Edge completion, verified consent persistence,
complete synchronization-task draining, UUID-keyed restoration retry retention
through exact completion and the combined Auth-transition drain, canceled-retry
admission after manual attempt-number reuse, stale-account fencing, Realtime
ownership/retry, and target-consent ordering contracts. Moving any of them
requires updating the cross-language path and running the focused Deno contract
in the same change.

See the canonical
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
[API contract](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-merge-ghost-profile-edge-node),
and
[revenue identity guide](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md).
