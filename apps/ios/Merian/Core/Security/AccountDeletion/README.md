# Account Deletion Security Ownership

This package owns the device-local security state that makes account-deletion
intake and recovery fail closed across process termination. It does not own
Supabase Auth, HTTP endpoints or payloads, receipt admission, account-scoped
data erasure, workflow task lifetime, or user-facing presentation.

## Ownership

- `Models/AccountDeletionLocalRecoveryState.swift` owns the installed raw phase
  values and their cleanup/intake classification. Unknown future values remain
  fail closed as intake-pending state.
- `Models/AccountDeletionRecoveryCapabilityModels.swift` owns the prepared
  capability value and the existing secure-storage error presentation.
- `Stores/AccountDeletionRecoveryCapabilityStore.swift` owns distinct 256-bit
  recovery and acknowledgement capability generation, the protocol-v2 JSON
  envelope, legacy raw protocol-v1 decoding, exact Keychain accessibility,
  read-after-write verification, verified removal, and the pre-Auth bootstrap
  barrier. It performs no networking and does not decide whether a server
  receipt authorizes cleanup.
- `Stores/AccountDeletionLocalCleanupStore.swift` owns the single durable
  `UserDefaults` phase marker. It preserves the installed Boolean migration,
  persists and reads back every phase before publishing its routing event, and
  removes and verifies the marker before publishing resolution.
- `Stores/ManualAppleRevocationNoticeStore.swift` owns the durable fallback
  notice for legacy Apple-linked accounts and publishes the existing app event
  after setting the flag.

The exact defaults key strings live in
`Core/Preferences/UserDefaultsKeys.swift`; app-owned Keychain key strings live
in `Core/Security/KeychainKeys.swift`. Neither registry changes an installed key
or storage format. The stores keep their source-compatible live defaults while
accepting explicit `UserDefaults`, event-sender, secure-store, and generator
dependencies for isolated tests.

`Core/Network/Auth/Coordinators/AccountDeletionWorkflow.swift` owns phase order
through injected effects. `SupabaseManager` retains Auth and endpoint effect
assembly, and the Settings deletion adapter supplies the account-local purge
boundary. Only an admitted workflow result may advance recovery state or ask the
capability store to retire a proof.

## Invariants

- Capability material never enters `UserDefaults`, logs, analytics, URLs, crash
  metadata, app groups, backups, or server plaintext storage.
- A present or unreadable Keychain proof restores a conservative barrier before
  Auth bootstrap. Verified absence may remove only that lookup barrier.
- The protocol-v2 recovery and acknowledgement values are distinct and are not
  interchangeable. Legacy 32-byte capability data remains protocol-v1 readable.
- Accepted deletion clears account-local data before acknowledgement and
  verified capability retirement. Definitively uncommitted protocol-v2 intake
  may retire only its unused capability without erasing account-local data.
- Unknown recovery phases and uncertain storage remain fail closed.

## Verification

Mirrored tests live in `MerianTests/Core/Security/AccountDeletion/`:

- `AccountDeletionRecoveryCapabilityStoreTests.swift` covers generation,
  protocol compatibility, secure-storage uncertainty, exact accessibility, write
  verification, pre-Auth barrier restoration, and verified removal.
- `AccountDeletionLocalCleanupStoreTests.swift` covers every installed phase,
  legacy Boolean migration, unknown-state admission, persistence/event order,
  verified resolution, and the exact security-owned defaults keys.
- `ManualAppleRevocationNoticeStoreTests.swift` covers persistence before event
  delivery and explicit resolution.
- `AccountDeletionSecurityArchitectureTests.swift` freezes declaration and test
  ownership, exact imports and file inventory, local-only store boundaries,
  retired aggregate paths, and the 600-line production ceiling.
- `KeychainKeysTests.swift` and `Core/Preferences/UserDefaultsKeysTests.swift`
  freeze every exact installed storage key string.

The cross-language
`services/supabase/functions/_tests/accountDeletionCoverage.test.ts` contract
reads the relocated capability, recovery-state, and marker-store owners. Moving
them requires updating that executable source contract in the same change.

See the canonical
[account-deletion contract](../../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md),
[Keychain contract](../../../../../../docs/development-guides/05-keychain-and-secrets.md),
and
[Core Network verification matrix](../../Network/README.md#account-deletion-and-recovery-verification).
