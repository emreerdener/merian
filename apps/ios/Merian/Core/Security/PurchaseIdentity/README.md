# Purchase Identity Ownership

This folder owns the iOS purchase-principal domain, secure device state, and
route adapter, plus the two durable purchase-continuity journals used while iOS
changes Supabase Auth identity. It does not own Supabase Auth mutation,
RevenueCat SDK work, entitlement refresh, sign-out task lifetime, user-facing
presentation, or the server-side resolver implementation.

## Ownership

- `Models/PurchasePrincipalModels.swift` owns the source-compatible resolution,
  binding, rotation result, and resolver-error values. It strictly maps decoded
  responses into validated domain values.
- `Models/PurchasePrincipalWireModels.swift` owns the protocol version and the
  exact decoded response DTOs for resolve and stable sign-out rotation.
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

`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns the
deterministic sign-out and legacy completion order through injected effects.
`SupabaseManager` constructs the live resolver and handoff store, maps domain
failures to the existing auth-transition errors, and retains Auth, RevenueCat,
entitlement, recovery, and lifecycle orchestration. Before either journal is
removed, that live adapter must revalidate caller cancellation, the exact
anonymous manager-published user, nonexpired SDK session, captured Auth
generation, and transition context. A completion without a transition owner
fails as soon as another Auth transition opens, including before its first SDK
event.

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
declaration uniqueness, the exact owner inventory, dependency confinement, the
sole live Supabase adapter, private payload ownership, and file-size ceilings.

`PurchaseIdentityHandoffStoreTests` covers both installed journal formats,
validation, exact keys, accessibility, verified writes/removal, and secure-store
failures. `PurchaseIdentitySignOutWorkflowTests` freezes cancellation and phase
ordering. The cross-language `purchasePrincipalMigrationContract.test.ts` pins
the iOS protocol and live route linkage alongside the Edge and database
contracts.

See the canonical
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
[API contract](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-resolve-purchase-principal-edge-node),
[revenue identity guide](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md),
and
[purchase-principal RFC](../../../../../../docs/rfcs/purchase-principal-auth-separation.md).
