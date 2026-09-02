# Explore Map iOS ownership

This directory owns the public, privacy-safe Map mode inside Explore's
Observations surface. Product behavior is defined by the canonical
[Explore root-navigation contract](../../../../../../docs/features-and-hardware/24-explore-bottom-menu.md)
and the
[Explore Map RFC](../../../../../../docs/rfcs/explore-page.md#explore-map-addendum).
The owner-only local map is a separate Scans feature; review the
[Private Scan Map contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md)
before changing either boundary.

## Directory ownership

- `Models/` owns focus targets, feature request values, presentation and camera
  policy, local filtering, region math, and the bounded in-memory response
  cache. Codable map DTOs remain in `Core/Network/ExploreAPIModels.swift`.
- `Services/` supplies the live `MerianNetworkClient` closure for
  `ExploreMapViewModel.Dependencies`. It is the only Map layer that calls the
  network client.
- `ViewModels/` owns `@MainActor @Observable` spatial state, camera-settle
  policy, request generations, cache application/revalidation, filters,
  selection, focused-post continuity, loading, and recoverable errors.
- `Views/` owns the route-compatible screen and animation-sensitive camera,
  annotation-tap, preview-anchor, drag-axis, drag-offset, and swipe-commit
  state.
- `Components/Filters/` owns the species quick filters and complete
  species/media sheet.
- `Components/Markers/` owns cluster bubbles plus dot/thumbnail waypoints and
  approximate-location treatment.
- `Components/Preview/` owns discovery-list and selected-post cards. Feed-owned
  mutations enter through callbacks and continue to synchronize through
  `ExplorePostStore`.
- `Components/Shared/` owns Map-only loading/error/status presentation.

Views and components do not perform direct networking.

## State and data flow

`ExploreMapViewModel` accepts a small initializer-injected `Dependencies` value.
The existing `init(mapPointsLoader:)` seam remains available for source and test
compatibility. The live adapter sends the current bounding region, derived zoom,
500-row limit, selected species groups, and selected media types to
`/get-explore-map-points`.

The view model keeps the last successful results while the camera moves. A
meaningful settled change exposes **Search this area** and schedules the same
1.5-second cancellable search used before this organization pass. Recent
responses are cached by compatible viewport plus both filter groups, capped at 8
regions and 1,400 cluster/post items, and considered fresh for 90 seconds. Stale
entries render immediately and then revalidate.

Species choices OR together, media choices OR together, and the groups
intersect. Local filtering is used only while an unfiltered response is visible
and a new filter request is pending. Server-applied filtered responses remain
authoritative before clusters or waypoints render.

## Compatibility and privacy guardrails

- Keep `ExploreMapView`, `ExploreMapViewModel`, `ExploreMapFocusTarget`, and
  their existing initializer/callback signatures stable.
- Preserve all visible copy, accessibility labels, material/layout values,
  camera thresholds, haptics, telemetry entry points, loading/error states,
  preview gestures, sheet detents, and the two-step preview-to-detail route.
- Keep camera, drag, carousel-anchor, annotation-tap, and swipe-commit timing
  state in `ExploreMapView`; moving it into asynchronous models can change
  gesture cancellation or animation completion order.
- Consume only post-owned, server-sanitized public coordinates. A public Map
  post must have saved `location_sharing = open`; an open but approximate point
  keeps its uncertainty halo. Never derive a public point from exact private
  scan coordinates.
- Do not import the owner-only Scans map snapshot, index, filters, cache, or
  navigation into this feature. Likewise, public Map DTOs and social actions do
  not enter the private Scans map.
- This organization changes no endpoint action, JSON payload, DTO, SwiftData
  schema, persistence behavior, feature flag, navigation contract, or geoprivacy
  policy.
- Production Swift files in this directory must remain below 600 lines.

## Tests

Map presentation and view-model coverage lives in
`MerianTests/Features/Explore/Map/ExploreMapPresentationTests.swift` and
`ExploreMapViewModelTests.swift`. They lock visible count copy, camera zoom
thresholds, selection wrapping, filtered ordering, focus/camera continuity,
stale-response fencing, canonical post synchronization, public-detail mapping,
request construction, fresh/stale cache behavior, and stale-content error
recovery.

`Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift` owns the
stateless map-points wire method; the Map Services adapter and ViewModel still
own viewport requests and caching. Its payload, typed response, and transport
coverage lives in
`MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift` and
`ExploreBrowsingEndpointTransportTests.swift`, including deterministic
species/media filters, mode/facets, and media-only rows. DTO-only decoding
remains in `MerianTests/Core/Network/MerianNetworkClientTests.swift`.

After `make xcodegen` and build-for-testing, run the focused Map suite with:

```sh
xcodebuild test-without-building \
  -scheme Merian \
  -project Merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -only-testing:merianTests/ExploreMapPresentationTests \
  -only-testing:merianTests/ExploreMapViewModelTests
```

Wire changes also require the
[Core Network browsing matrix](../../../Core/Network/README.md#endpoint-verification).
The focused suite does not replace the complete `merianTests` target, generic
iOS Simulator build, XcodeGen/source-membership validation, SwiftLint,
documentation formatting, or manual MapKit regression on a candidate build.
