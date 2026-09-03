# Field Trips iOS ownership

This directory owns the iOS presentation and interaction layer for Outings and
Events. The product, lifecycle, privacy, and backend behavior remain defined by
the canonical
[Field Trips contract](../../../../../../docs/features-and-hardware/25-field-trips.md).

## Directory ownership

- `Models/` contains feature presentation models and policies plus the typed
  template, publication, Event, and Event-entry routes consumed by Explore,
  Profile, Feed, Author Profile, and Insights. Codable wire DTOs remain in
  `Core/Network/FieldTripAPIModels.swift`.
- `Services/` adapts `MerianNetworkClient` operations into small, typed closure
  endpoints. It is the only feature layer that supplies live networking
  closures.
- `ViewModels/` owns asynchronous loading and mutation state. Every view model
  is `@MainActor @Observable` and accepts an initializer-injected `Dependencies`
  value or typed endpoint.
- `Views/` contains screen and navigation wrappers. Keep gallery selection,
  focus, scroll-proxy, highlight, and other animation-sensitive UI state here.
- `Components/` contains feature-owned UI grouped by catalog, detail, media,
  publications, profile, and shared use. Views and components do not call the
  network client directly.

The shared wire implementation lives in
`Core/Network/Endpoints/MerianNetworkClient+FieldTrips.swift`, which owns
request actions, payload construction, and typed response projections for this
feature and its cross-feature callers. Feature Services adapt those operations;
they do not own the shared transport. `MerianNetworkClient.swift` retains
private session, Auth, retry, and cancellation behavior behind one narrow JSON
POST bridge. See the [Core Network guide](../../../Core/Network/README.md) for
that boundary.

## Shared feature flows

- `FieldTripPublishedContent` normalizes outing publications and Event entries
  for one detail renderer and one interaction view model.
  `FieldTripPublishedContentEndpoint` retains their distinct load, like,
  comments, and reply actions. The existing publication and Event-entry views
  remain thin route-compatible wrappers.
- `FieldTripPublishForm` and `FieldTripPublishViewModel` own shared form state.
  `FieldTripPublishEndpoint` preserves the separate outing-publication and
  Event-entry requests plus their typed completion values.
- Featured-media source selection, fallback, and layout policy live in
  `Models/FieldTripFeaturedMedia.swift`; the carousel owns rendering and
  view-local page/failure state only. It projects the stable goal-derived ID and
  existing reference/user source-family boundary into the domain-neutral pager
  in `Core/UI/Components/MediaCarousel`; Field Trips does not depend on the
  Insight-specific carousel page model.
- Profile ordering, visibility, patch, and cover decisions live in
  `Models/FieldTripProfilePresentation.swift`. Profile components render those
  decisions and do not reconstruct them.

## Compatibility guardrails

- Keep existing screen, route, and profile-component initializer signatures
  stable. Keep selection, gallery, focus, scroll-proxy, highlight, and other
  animation-sensitive state in the owning view.
- Do not move presentation state or filtering extensions back into
  `Core/Network/FieldTripAPIModels.swift`. That file owns Codable DTOs and wire
  compatibility only.
- This organization boundary does not change API actions, JSON payloads,
  SwiftData or persistence schemas, feature flags, navigation contracts, or
  Outings/Events behavior.
- Production Swift files in this directory must remain below 600 lines.

## Tests

Add presentation, policy, dependency-adapter, and view-model tests under
`MerianTests/Features/Explore/FieldTrips`. Shared fixtures belong in
`FieldTripTestFixtures.swift`. Keep only JSON decoding and wire-contract
compatibility coverage in `FieldTripAPIModelsTests`.

`MerianTests/Core/Network/Endpoints/FieldTripEndpointTests.swift` owns request
mapping, typed response, error, refresh, replay, and cancellation coverage with
a private client and scoped mock transport per network case.
`MerianNetworkArchitectureTests.swift` guards the extracted endpoint owner and
private transport boundary. Payload assertions preserve JSON scalar types and
null/omission while ignoring object-key order; do not replace them with
Foundation dictionary equality, which conflates Booleans with numeric 0/1.

`MerianTests/Core/Network/Endpoints/NetworkEndpointTestSupport.swift` owns the
per-case client/session fixture, handler-marked mock responses, and JSON
comparison used across the extracted Core endpoint groups. It is separate from
the feature's `FieldTripTestFixtures.swift`. The shared POST assertion also
returns one captured body/key/timeout snapshot for retry comparisons;
`NetworkEndpointTestSupportTests` verifies it for data- and stream-backed
bodies. For support or any shared JSON POST bridge changes, follow all
requirements in the
[Core Network verification guide](../../../Core/Network/README.md#endpoint-verification),
including the helper suite, every linked endpoint matrix, and the complete
`merianTests` target. Never substitute the shared client's overrides or the
legacy global endpoint-handler registry for per-case transport isolation.

`FieldTripFeaturedMediaTests` owns featured-source ordering, fallback, stable
goal identity, and the reference/user reuse boundary. Pair it with
`InsightMediaGalleryTests` and `InsightMediaCarouselArchitectureTests` whenever
the shared Core pager, page identity, zoom host, pagination, or top-edge
treatment changes.

Use the canonical
[Field Trips verification matrix](../../../../../../docs/features-and-hardware/25-field-trips.md#verification)
for the focused selector list, complete `merianTests` target, and manual checks.
