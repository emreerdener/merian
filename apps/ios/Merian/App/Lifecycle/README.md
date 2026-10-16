# App Lifecycle

`AppLifecycleManager.swift` is the app-owned `@MainActor` scene-phase
orchestrator. `MerianApp` constructs it from `AppDIContainer` and forwards
active, inactive, and background transitions.

The manager preserves two admission gates: completed onboarding precedes consent
synchronization and purchase-identity repair, while current required consent
precedes hardware, notification, usage, historical-sync, and durable queue
maintenance. Local reanalysis erasure is the explicit privacy exception:
foreground requests receipt-bound filesystem cleanup before either gate, without
starting network or Auth work. Repository configuration and committed parent
deletion also request that same coalesced owner. Failed receipts remain pending
for a later lifecycle opportunity; they never create network scheduler wakes.
Foreground also requests owner-bound reanalysis recovery before the UI consent
route: stored results and local prepared files can recover, while fresh
admission retains its current-consent and network checks. After asynchronous
consent synchronization, the original account and current consent are rechecked
before sending an explicit advisory grant wake. A stale account's completion
cannot rearm another owner's held submission. The dedicated advisory timer can
recover local files offline and is awaited during Auth teardown.
Capture-specific interruption and claim release remain in Capture state owners.
Durable wake ordering remains in
`Core/Data/OfflineSync/OfflineJobScheduler.swift`.

Initializer-injected callbacks isolate the admission matrix without replacing
the live maintenance route. Tests live in
`MerianTests/App/Lifecycle/AppLifecycleManagerTests.swift`; the Utilities-wide
architecture suite freezes the app-owned path.

See the canonical
[App Lifecycle Management](../../../../../docs/development-guides/02-app-lifecycle.md)
contract.
