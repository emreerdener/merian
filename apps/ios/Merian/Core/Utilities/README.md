# Core Utilities

The `Utilities` directory owns lightweight cross-cutting helpers and the typed
process-local coordination primitives used across feature boundaries.

`String+Trimming.swift` provides the single trim-to-non-empty normalization used
by the shared scan-thumbnail projection, renderer, and reference-image backfill
pipeline. Keep that mechanical normalization here instead of recreating
file-private variants across those layers.

## Field Notes reconciliation

`FieldNotesRepository.swift` is the shared `@MainActor` boundary for private
note reads, writes, clears, and public-to-local repair. It resolves active
`LocalScanRecord` state, queued `OfflineQueuedScan` state, and the legacy
`FieldNotesStore` bridge in durability order; public Explore notes may fill only
an entirely empty local/private state. Consumers use this repository rather than
mutating those stores directly. Insight Field Notes narrows that boundary
further through an injected adapter in `Features/Insights/FieldNotes/Services`,
while repository behavior is tested under
`MerianTests/Core/Utilities/FieldNotesRepositoryTests.swift`.

## Scan transport classification

`MerianError.swift` owns `ScanConnectivityFailurePolicy`, the shared bounded
classifier used before and after a scan becomes durable. Queue-only admission
accepts only reviewed offline and data-path URL failures, including wrapped
underlying errors; cancellation, authentication, TLS, certificate policy,
server, and malformed-response failures stay fail-closed. Once the normal queue
row exists, the durable-recovery policy additionally permits a generic secure
connection failure to relinquish foreground ownership to that queue. Specific
certificate, authentication, and ATS policy failures anywhere in the bounded
wrapper chain veto both recovery decisions; a broad outer transport error cannot
hide them. A chain that exceeds the reviewed depth also fails closed rather than
accepting only its inspected prefix.

## Foreground lifecycle

`AppLifecycleManager` keeps onboarding admission before consent synchronization
and purchase-identity retry, and current required consent before hardware,
notifications, or maintenance work. Its live maintenance path still drains the
durable `OfflineJobScheduler`. Narrow initializer-injected consent-sync,
identity-retry, and authorized-work callbacks let lifecycle tests exercise that
admission policy without launching real queue, Auth, notification, or cloud
maintenance. `AppLifecycleManagerTests` pairs the injected admission matrix with
a source guard for the live scheduler route. Core Data's
`OfflineJobSchedulerTests` separately executes scheduler ordering, awaits each
asynchronous drain, and verifies wake admission/cancellation with inert effects.
Those tests do not substitute for durable staged-claim or provider-replay
coverage. Fixtures must not restore a queue context while production lifecycle
tasks are still running, and background-phase tests restore the timestamp they
write to standard preferences.

## Typed event and route coordination

- `AppEventPublisher` is a DI-owned, synchronous `@MainActor` bus for
  loss-tolerant invalidations and lifecycle hints. Producers receive
  `AppEventSending`; consumers receive `AppEventStreaming`. The subject is
  private, there is no `AppEventPublisher.shared`, and an event never replaces a
  read from the authoritative SwiftData, UserDefaults, Supabase, or service
  state. The erased subscriber stream is constructed once with the private
  subject, so repeated `publisher` access does not allocate another wrapper.
- `AppRouteCoordinator` is the bounded delivery state machine for root
  navigation and presentation actions. Typed envelopes carry stable identity,
  source priority, expiry, semantic coalescing, and account/session generations.
  Route envelopes are process-local; durable imports and other recoverable work
  stay in their owning stores.
- `CaptureWorkspaceViewModel` is the sole root route consumer, and
  `CameraSheetRouter` is the sole app-level sheet host. A feature must not add a
  second global bus or sibling root sheet.

Reference-type event subscribers retain and cancel their `AnyCancellable` and
capture themselves weakly. SwiftUI `.onReceive` subscriptions are owned by the
mounted view lifecycle. The event-routing guard rejects raw `.sink` use outside
the reviewed lifetime-owner files; a new sink requires an explicit capture,
storage, cancellation, ordering, and actor-delivery review. The exact owner
matrix lives in the canonical routing contract; the allowlist is file-specific,
not a general permission for a directory or feature.

## Framework publisher bridge

`Publisher.sinkOnMainActor` is only for Apple/framework publishers whose
originating executor is unknown. It preserves Combine ordering while hopping
asynchronously to the main queue before entering the main actor. Do not apply it
to `AppEventPublisher`: app-event delivery is intentionally synchronous and
reentrant on `@MainActor`.

`Core/Preferences/AppSettings.swift` is the one Preferences-owned
`UserDefaults.didChangeNotification` boundary. It retains the exact observer
token, captures its owner weakly, hops explicitly to the main actor, and removes
the token during teardown. `UserDefaultsKeys.swift` remains the exact key
registry plus the staged account-deletion and Keychain compatibility owner; it
no longer imports Observation, UIKit, Supabase, or SwiftData. Durable species
preference reconciliation lives in `Core/Data/SpeciesPreferences`; verified
cleanup of account-derived defaults lives in
`Core/Preferences/AccountScopedPreferences.swift` and deliberately leaves the
Utilities-owned deletion marker and manual Apple notice intact.
Application-defined notification names and posts are forbidden.

See the canonical
[Event and Presentation Routing contract](../../../../../docs/system-architecture/10-event-and-presentation-routing.md).
