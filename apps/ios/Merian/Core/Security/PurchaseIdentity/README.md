# Purchase Identity Handoff Storage

This folder owns the two durable on-device purchase-continuity journals used
while iOS changes Supabase Auth identity. It does not own Supabase requests,
RevenueCat mutation, entitlement refresh, Auth-session mutation, task lifetime,
or user-facing presentation.

## Ownership

- `Models/PurchaseIdentityHandoffModels.swift` defines the exact persisted
  legacy handoff and protocol-3 stable-rotation shapes. Explicit coding keys
  freeze the existing camel-case JSON fields used by installed clients.
- `Stores/PurchaseIdentityHandoffStore.swift` owns encoding/decoding,
  fail-closed shape validation before writes and after reads, exact Keychain-key
  selection, `WhenUnlockedThisDeviceOnly` accessibility, byte-for-byte write
  verification, and verified removal. Its small closure dependencies are
  initializer-injected; the store resolves no singleton and performs no network
  or provider work.

`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns the
deterministic sign-out and legacy completion order through injected effects.
`SupabaseManager` constructs the live store with `KeychainManager`, maps its two
domain failures to the existing auth-transition errors, and retains Auth,
endpoint, RevenueCat, entitlement, recovery, and lifecycle orchestration.

Malformed evidence is rejected before storage and malformed or unreadable
restored evidence is never treated as absence. A write is not accepted until the
exact bytes can be read back. Stable `preparing` evidence has no expiry; only
the server can supply the expiry in `prepared` evidence. The legacy proof and
stable journal retain their existing key names and wire-neutral local JSON
formats.

## Verification

`PurchaseIdentityHandoffStoreTests` covers absence, exact persisted field names,
legacy/stable compatibility, state-specific expiry rules, malformed evidence,
rejection before secure-storage dispatch, failed or unverifiable writes,
device-only accessibility, exact-key removal, and secure-store error
propagation. `PurchaseIdentitySignOutWorkflowTests` freezes cancellation before
the legacy server destination bind, preparation-before-sign-out, and
proof-removal-last sequencing. The Core Network integration architecture suite
prevents these declarations and storage rules from drifting back into the
aggregate manager.
`services/supabase/functions/_tests/purchasePrincipalMigrationContract.test.ts`
also pins the manager's fail-closed readiness boundary: it must reread both
store-backed journals, publish the derived pending state, and return pending
when either secure read is unavailable. Moving this store or its manager adapter
requires an atomic cross-language contract update.

See the canonical
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
[revenue identity guide](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
and
[purchase-principal RFC](../../../../../../docs/rfcs/purchase-principal-auth-separation.md).
