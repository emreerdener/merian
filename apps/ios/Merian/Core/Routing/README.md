# Core Routing

`Core/Routing` owns Merian's process-local, cross-feature event and root-route
infrastructure. It does not own durable domain state, feature navigation, or
platform notification registration.

## Ownership

- `Models/` contains immutable `AppEvent`, `AppRoute`, envelope, source,
  priority, deferral, rejection, and outcome values.
- `Policies/` contains deterministic route coalescing, account sensitivity,
  source priority/lifetime/session survival, and outcome terminality.
- `Coordination/` contains the producer/consumer capabilities, the synchronous
  event bus, and the bounded mutable route state machine.

`AppEventPublisher` is a DI-owned, synchronous `@MainActor` bus for
loss-tolerant invalidations and lifecycle hints. Producers receive
`AppEventSending`; consumers receive `AppEventStreaming`. Its subject is
private, it has no singleton, and every consumer must recover authoritative
state from its owning store or service.

`AppRouteCoordinator` is the delivery-critical root-navigation state machine.
Its process-local queue retains stable request identity, source priority,
expiry, semantic coalescing, account/session fencing, explicit outcomes, and a
single in-flight request. The pending queue remains capped at 16 envelopes and
the outcome history at 64 records. Durable imports and other recoverable work
remain in their owning stores.

The routing package does not perform networking, persistence, singleton
resolution, or view presentation. `AppDIContainer` assembles one instance of
each service, `CaptureWorkspaceViewModel` consumes root routes, and
`CameraSheetRouter` remains the sole app-level sheet host.

## Verification

- `MerianTests/Core/Routing/AppRoutePolicyTests.swift` locks deterministic
  policy independently of mutable coordination.
- `MerianTests/Core/Routing/AppRouteCoordinatorTests.swift` locks queue and
  state-machine behavior.
- `MerianTests/Core/Routing/AppEventPublisherTests.swift` locks synchronous,
  reentrant delivery and cancellation.
- `MerianTests/Core/Routing/CoreRoutingArchitectureTests.swift` locks source
  ownership, imports, effect-free Models/Policies, retired paths, feature route
  consumption in feature-owned suites, and the 600-line production-file ceiling.
- `scripts/check-ios-event-routing.sh` and its adversarial test enforce the
  canonical split owners, event inventory, subject ownership, raw-sink review,
  and platform-notification boundaries.

Run the four Core suites with Capture's concrete missing-target consumer
regression for the 29-test focused matrix:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/AppRoutePolicyTests \
  -only-testing:merianTests/AppRouteCoordinatorTests \
  -only-testing:merianTests/AppEventPublisherTests \
  -only-testing:merianTests/CoreRoutingArchitectureTests \
  -only-testing:merianTests/CaptureWorkspaceViewModelRefinementTests/testMissingScanIsRejectedAndDoesNotStallTheQueue
```

The source and adversarial boundaries run separately:

```sh
make validate-ios-event-routing
make test-ios-event-routing
```

See the canonical
[Event and Presentation Routing contract](../../../../../docs/system-architecture/10-event-and-presentation-routing.md).
