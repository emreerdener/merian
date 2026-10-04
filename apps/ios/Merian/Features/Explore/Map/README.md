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
  cache. Codable map DTOs remain in
  `Core/Network/Models/Explore/ExploreMapAPIModels.swift`.
- `Services/` supplies the live `MerianNetworkClient` closure for
  `ExploreMapViewModel.Dependencies`. It is the only Map layer that calls the
  network client.
- `ViewModels/` owns `@MainActor @Observable` spatial state, camera-settle
  policy, request generations, cache application/revalidation, filters,
  selection, focused-post continuity, loading, and recoverable errors.
  `ExploreMapDiscoveriesViewModel` separately owns each discoveries sheet's
  immutable viewport/filter request, list rows, count, loading, retry, and
  cancellation state.
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

The map layer extends through the top safe area beneath the transparent
navigation toolbar, with its top scroll-edge effect hidden. Overlay controls
keep their safe-area positioning so the map remains visible behind the toolbar.
The native distance scale stays visible at the bottom trailing edge, opposite
the Apple Maps attribution and below the floating controls and preview carousel.

The native user-location annotation uses Core UI's shared blue person pin,
anchored at its tip. Its enclosing MapKit annotation receives maximum normal and
selected Z priorities plus required display priority so it stays above clusters
and observation waypoints, including the selected observation. MapKit retains
ownership of live location updates; SwiftUI declaration order alone does not
establish annotation stacking.

The bottom preview carousel uses native regular Liquid Glass on iOS 26 and
later, retaining its 32-point corners and 20-point content padding. Older iOS
versions and the discoveries-list sheet retain the existing material cards.
Carousel gestures, reactions, menus, and the primary discovery action are
unchanged.

Discoveries-list cards stack a 4:3 image across the full content width above the
species details, location, reactions, and discovery action. They request the
hero image rather than the small grid thumbnail and retain rounded image corners
and the card's content inset. The overflow menu stays beside the species
details. The floating map carousel retains its compact side-by-side header.

The discoveries-count button snapshots the committed viewport and current
filters. When the map holds clusters, the sheet requests individual posts using
the existing map-points loader with zoom 20 and limit 500; zoom selects the
response representation without changing geographic bounds or the map camera.
Already loaded post-mode rows display immediately. The sheet keeps the reported
total while loading, shows a retryable error on failure, and presents an
explicit empty state only for an empty result. Loading and cancellation belong
to the sheet and never overwrite the map cache, clusters, or selection.
Dismissed and superseded requests cannot publish. Successful unpublish, report,
block, and canonical location-privacy changes also remove affected sheet cards.

The current endpoint selects at most 500 candidates and returns at most 160
individual posts, without pagination. When its total exceeds the returned rows,
the sheet displays **Showing X of Y discoveries** and suggests zooming in rather
than presenting the bounded list as complete.

Preview-card overflow menus include **View profile** above the destructive
actions. The discoveries-list sheet dismisses before handing the selected author
to Shell's existing profile navigation callback. Both map previews and list
cards retain **Block user** and **Report post** for other authors, and
**Unpublish post** for the viewer's own posts.

## State and data flow

`ExploreMapViewModel` accepts a small initializer-injected `Dependencies` value.
The existing `init(mapPointsLoader:)` seam remains available for source and test
compatibility. The live adapter sends the current bounding region, derived zoom,
500-row limit, selected species groups, and selected media types to
`/get-explore-map-points`.

The view model keeps the last successful results while the camera moves. A
meaningful settled pan exposes **Search this area** and schedules a 1.5-second
cancellable search. Cluster taps search the final settled viewport immediately,
superseding requests for the previous view. Zooming while clusters are displayed
also refreshes on settle, including small changes across an integer zoom
boundary. Recent responses are cached by compatible viewport, integer zoom
bucket, and both filter groups, capped at 8 regions and 1,400 cluster/post
items, and considered fresh for 90 seconds. A broader zoom bucket cannot supply
cached clusters to a closer one. Stale entries render immediately and then
revalidate.

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

`ExploreMapDiscoveriesViewModelTests` covers cluster-to-list loading for 120
discoveries, viewport/filter snapshots, unchanged map state, bounded results,
loading failures and retry, empty results, cancellation, and card removal.

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

## Observation reactions

Discovery and selected-post previews use the shared Comment → Heart → Add
reaction → emoji chips row. Share remains in the post-detail toolbar. They
resolve the latest `ExplorePostStore` entry rather than keeping marker-local
reaction state. Map markers stay lightweight: Feed hydrates their missing
summary through the single-post endpoint and serializes that hydration with
writes. Geometry, coordinates, and map-cache ownership are unchanged. The Map
hydration/mutation regression lives in `ExploreReactionStateTests`; see the
[reaction contract](../../../../../../docs/rfcs/explore-page.md#emoji-reactions-update-2026-09-18).

## Shared navigation controls

The horizontal glass toolbar and search sheet follow the
[shared map navigation contract](../../../../../../docs/features-and-hardware/24-explore-bottom-menu.md#shared-map-navigation).
Core Maps owns injected MapKit search and cancellable location admission; this
feature owns camera framing and discovery loading after the camera settles. Both
map styles preserve filters and selection. Place selection clears the preview.
Valid search bounds frame the whole selected place with modest clearance;
results without bounds retain MapKit item framing. The shared Core Maps owner
validates these ephemeral bounds and carries them through search selection. Both
maps use Core Maps' `MapLocateCameraPolicy`. Explore's **Locate me** clears the
preview and requests a view roughly 1 km across, preserving a closer viewport's
width in meters. The location's horizontal-accuracy diameter sets a minimum
width when the fix is coarse. Empty results do not widen the camera. Locate
requests use the same immediate search on camera settle as place selection;
initial map framing is unchanged. Selecting a place searches the first settled
destination immediately, without the normal pan debounce or movement threshold.
It uses the final visible bounds and current filters, with the existing cache
and manual retry behavior. Pending responses from before navigation cannot
replace destination results. Later pans retain the normal 1.5-second debounce.

Destination loads retire prior request ownership and start without waiting for
an older viewport request to finish. Older completions cannot clear the current
loading state or drain its queued refresh. Repeated destination camera-settle
callbacks reuse the pending search; revised destination bounds replace it
immediately. User-positioned camera changes retain the normal pan debounce.

## Report invalidation

Visibility changes cancel pending requests/debounces, clear region caches and
clusters/facets, remove hidden posts and reload the current region. Map previews
and discoveries also consult shared visibility before rendering fallback models.
