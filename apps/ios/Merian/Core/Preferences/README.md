# Core Preferences

`Core/Preferences` owns process-wide typed settings, small `UserDefaults`-backed
compatibility stores shared across features, and the verified account-local
preferences cleanup boundary. It does not own SwiftData models, cloud
synchronization, authentication, networking, or feature presentation.

## Owners

- `AppSettings.swift` is the `@MainActor @Observable` in-memory settings
  boundary. It preserves the existing `UserDefaults` defaults, writes, external
  change observation, preview factory, and `AppSettings.shared` compatibility
  entry point. Production composition should continue to inject the
  `AppDIContainer`-owned settings instance into consumers.
- `Stores/ExploreShareStateStore.swift` owns the legacy per-scan Explore post-ID
  cache.
- `Stores/FieldNotesStore.swift` owns the legacy per-scan field-note bridge.
  `Core/Utilities/FieldNotesRepository.swift` remains the SwiftData-first
  reconciliation authority.
- `Stores/SpeciesPreferredNameStore.swift` owns legacy preferred-name keys,
  pending-delete timestamps, and the `SpeciesPreferredNameSyncDiagnostics`
  support value. `Core/Data/SpeciesPreferences` owns the SwiftData repository,
  reconciliation policy, and injected cloud-sync boundary.
- `AccountScopedPreferences.swift` composes those keyed stores with the exact
  account-derived cache-key and prefix inventory used during accepted account
  deletion. It clears and read-back verifies scan badges, collection state,
  Explore state and unread count, legacy gamification state, feedback markers,
  historical-sync throttles, capture-goal and Field trip achievement envelopes,
  and account-keyed media/profile dismissal signatures while retaining
  device-level presentation and hardware choices.
- `AccountScopedRuntimeState.swift` is the injected, post-persistence reset
  boundary for observable settings, gamification state, the app-icon badge, and
  the in-memory image cache. It runs only after SwiftData and preference cleanup
  succeed.

`Core/Utilities/UserDefaultsKeys.swift` remains the single registry for exact
persisted key strings. Do not duplicate or rename those strings during an
ownership move. Account-deletion recovery state and Keychain key names remain in
that aggregate for their separately reviewed security slice.

## Boundaries

- Preference owners may use `Foundation`; `AppSettings` additionally uses
  Observation and UIKit for its existing observable lifecycle and device
  default.
- Preferences owners must not import Supabase or SwiftData, depend on
  `AppDIContainer`, create network sessions, or issue database queries.
- Keyed stores accept an explicit `UserDefaults` instance so tests and previews
  remain isolated.
- `AppSettings.gridColumns` clamps runtime mutations to the supported 1...3
  range and persists that normalized value.
- `ExploreShareStateStore` and `FieldNotesStore` clear only their own key
  prefixes. The species store must not erase unrelated defaults.
- Account cleanup must use `AccountScopedPreferences.purgeAndVerify`; it must
  not clear the deletion-recovery marker, manual Apple-revocation notice,
  consent evidence, APNs token, onboarding completion, or device settings.
- Process-local account projections must reset through
  `AccountScopedRuntimeState`. The app-icon owner generation-fences its network
  refresh so a response admitted before deletion cannot restore the prior
  account's badge count afterward.
- Defaults, trimming, key strings, notification behavior, and migration behavior
  remain stable. Behavior fixes in this slice persist a clamped runtime grid
  count and make accepted account deletion remove every classified account cache
  instead of only the Explore-share bridge.

## Verification

Mirrored tests live in `MerianTests/Core/Preferences/`:

- `AppSettingsTests.swift` covers defaults, normalized persistence, explicit
  reloads, and external-change observation.
- `KeyedPreferenceStoreTests.swift` covers normalization, clearing, and prefix
  isolation for Explore share and field-note bridges.
- `SpeciesPreferredNameStoreTests.swift` covers species scoping, prefix-safe
  clearing, pending-delete values, and sync diagnostics.
- `AccountScopedPreferencesTests.swift` locks the complete direct-cache
  inventory, verified erasure, preservation of device settings, and exact
  runtime-owner delegation.
- `PreferencesArchitectureTests.swift` freezes declaration ownership, exact
  extracted-file inventory, dependency boundaries, and the 600-line ceiling.

The process owners have direct reset/race coverage in
`MerianTests/Core/Analytics/GamificationManagerTests.swift` and
`MerianTests/Core/Hardware/AppIconBadgeCoordinatorTests.swift`. Both suites
claim keyed shared-process-state traits so peer suites cannot concurrently
mutate the same singleton-backed values.

Repository and cloud-convergence tests live under
`MerianTests/Core/Data/SpeciesPreferences/`; Preferences tests retain ownership
of only the legacy bridge, pending-delete store, and diagnostic persistence.
