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
`FieldTripFeaturedMediaTests` owns featured-source ordering, fallback, stable
goal identity, and the reference/user reuse boundary. Pair it with
`InsightMediaGalleryTests` and `InsightMediaCarouselArchitectureTests` whenever
the shared Core pager, page identity, zoom host, pagination, or top-edge
treatment changes.
