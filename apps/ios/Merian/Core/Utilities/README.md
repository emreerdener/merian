# Core Utilities

The `Utilities` directory owns lightweight cross-cutting helpers and the typed
process-local coordination primitives used across feature boundaries.

## Typed event and route coordination

- `AppEventPublisher` is a DI-owned, synchronous `@MainActor` bus for
  loss-tolerant invalidations and lifecycle hints. Producers receive
  `AppEventSending`; consumers receive `AppEventStreaming`. The subject is
  private, there is no `AppEventPublisher.shared`, and an event never replaces
  a read from the authoritative SwiftData, UserDefaults, Supabase, or service
  state.
- `AppRouteCoordinator` is the bounded delivery state machine for root
  navigation and presentation actions. Typed envelopes carry stable identity,
  source priority, expiry, semantic coalescing, and account/session generations. Route envelopes are
  process-local; durable imports and other recoverable work stay in their
  owning stores.
- `CaptureWorkspaceViewModel` is the sole root route consumer, and
  `CameraSheetRouter` is the sole app-level sheet host. A feature must not add a
  second global bus or sibling root sheet.

Reference-type event subscribers retain and cancel their `AnyCancellable` and
capture themselves weakly. SwiftUI `.onReceive` subscriptions are owned by the
mounted view lifecycle.

## Framework publisher bridge

`Publisher.sinkOnMainActor` is only for Apple/framework publishers whose
originating executor is unknown. It preserves Combine ordering while hopping
asynchronously to the main queue before entering the main actor. Do not apply it
to `AppEventPublisher`: app-event delivery is intentionally synchronous and
reentrant on `@MainActor`.

`UserDefaultsKeys.swift` is the one Utilities-owned NotificationCenter boundary.
It retains the exact observer token, captures its owner weakly, hops explicitly
to the main actor, and removes the token during teardown. Application-defined
notification names and posts are forbidden.

See the canonical
[Event and Presentation Routing contract](../../../../../docs/system-architecture/10-event-and-presentation-routing.md).
