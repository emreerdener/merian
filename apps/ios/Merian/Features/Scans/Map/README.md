# Private Scan Map

`Scans/Map` owns the device-local spatial view of the current owner's scan
library. It is independent of Explore map DTOs, endpoints, publication state,
and social interactions.

The normative product, privacy, accessibility, verification, and candidate
release contract is in the
[Private Scan Map documentation](../../../../../../docs/features-and-hardware/28-private-scan-map.md).

## Projection

`PrivateScanMapDatabaseActor` creates detached record values from a fresh
private SwiftData context. `PrivateScanMapIndexService` owns the resulting
actor-isolated index, reuses unchanged rich points, and publishes two immutable
snapshots: a coordinate-only `PrivateScanMapPreviewSnapshot` for Collections and
a `PrivateScanMapSnapshot` with the local presentation values needed by the
interactive page. MapKit and SwiftUI never retain the model objects.

The index exposes separate content and spatial revisions. Presentation-only
changes update the interactive snapshot without regenerating the card image;
coordinate changes, insertions, and deletions update both. Repeating a refresh
against unchanged durable values advances neither revision. The database path
prefers captured-media JSON and faults the legacy media relationship only when
that scalar payload is absent.

Both snapshots prevent map rendering from retaining SwiftData models while the
library changes. They include every completed biological record with finite,
in-range saved GPS except the invalid `0,0` sentinel. Queued, non-biological,
missing-coordinate, and invalid rows are excluded.

The projection deliberately does not inspect Explore publication or per-post
location-sharing state. Shared and unshared scans both use the owner's exact
saved GPS because every surface in this module is private to the owner. Exact
coordinates stay in memory: the feature does not log them, add telemetry, or
persist rendered map previews.

## Ownership

- `Models/` owns detached preview/rich snapshots, index values, region and
  annotation geometry, and display-only labels.
- `Services/` owns SwiftData projection, the revisioned actor index, lossless
  refresh coalescing, sensitive-state reset fencing, MapKit/Web-Mercator screen
  projection, clustering, viewport work, startup and current-location request
  sequencing, and the bounded preview renderer.
- `ViewModels/` owns filter, selection, camera, and cancellable viewport
  presentation state.
- `Views/` owns the destination lifecycle and MapKit composition.
- `Components/` owns the passive Collections card, waypoint, preview, filter
  sheet, and private scan-list sheet.

Views and components do not fetch SwiftData or call endpoints. The map view
receives shared services through SwiftUI environment injection, including haptic
feedback, and emits only the selected scan ID to the Scans route owner. Every
production file in this folder remains below the 600-line review guard.

## Surfaces

Collections shows a non-interactive, full-width **Scan map** card only when the
projection contains at least one point. The card does not embed a live `Map`.
`PrivateScanMapPreviewRenderer` uses `MKMapSnapshotter` asynchronously, draws
bounded clusters away from the UI actor, and holds at most four rendered
variants in process memory. The preview fits the complete point extent,
including extents that cross the antimeridian, never requests live location, and
never persists its image. A placeholder remains responsive while MapKit is
loading or degraded.

`PrivateScanMapStore` is injected once at the app root. It serializes successful
refreshes, recovers durable state after `scanLibraryChanged`, and allows
Collections and the interactive destination to share revisions without hashing
the all-library query in a view. The destination awaits this store and installs
its rich snapshot before making the one-shot location request, so denied or
unavailable location can fall back to the newest mapped scan. Duplicate events
with unchanged durable values do not rebuild map state.

Refresh generations are lossless across failure: when a later request arrives
during a failing attempt, the store drains that pending generation without an
unbounded retry of an isolated failure. `PrivateScanMapStartupSequence` checks
cancellation immediately after the awaited refresh and again around location
lookup, so a departed destination cannot begin or publish one-shot location
work. `PrivateScanMapLocationRequestSequence` applies the same
current-generation check to an explicit **Locate me** request and distinguishes
invalidated work from a current request whose location is merely unavailable.

`PrivateScanMapViewportProjector` owns a one-degree spatial bucket index for the
filtered dataset and computes exact viewport membership on an actor. Pan, zoom,
filter, and dataset changes cancel the prior generation, and only the newest
result can update the main-actor view model. Its deterministic cluster grid uses
wrapped MapKit/Web-Mercator positions, so the interactive 56-point cells retain
their physical screen size at ordinary and high latitudes and across the
antimeridian. Saved polar coordinates remain eligible and are clamped only for
rendering projection. Preview clustering uses `MKMapSnapshotter`'s completed
coordinate-to-point transform so MapKit aspect fitting cannot diverge from the
drawn overlay.

Tapping the card pushes `PrivateScanMapView` in the existing Scans navigation
stack. `ScansSheetView` owns both typed route values: the card appends
`ScansNavigationRoute.privateScanMap`, and the map emits only a selected scan ID
for the root to append as `ScanInsightRoute`. The Map-owning view never installs
or mutates its own Insight navigation destination. This keeps route commits
independent of MapKit's render lifecycle and preserves one native back stack.
The page:

- requests a one-shot current location and shows the system user annotation;
- falls back to the newest mapped scan when current location is unavailable;
- offers **Show scans** whenever the current viewport contains no filtered
  scans;
- filters locally by species group and media type;
- renders deterministic 56-point projected screen-space clusters;
- uses simple dots at broad zoom and circular thumbnails from zoom level 11.5;
- reports the true filtered viewport count independently of clustering;
- presents owner-only previews whose complete card opens Insight, plus a
  medium/large **Your scans** sheet with a text-only **Private** subtitle; and
- opens existing embedded private Insight destinations only after a list sheet
  has fully dismissed. The Scans root then commits the value route while MapKit
  remains retained lower in the navigation stack. The map view model suspends
  its cancellable viewport projection; the shared local-Insight loader resolves
  and hydrates only the selected record after the destination has mounted.

The pushed page owns no Explore tabs, bell, bottom navigation, offline API
banner, social actions, or **Search this area** behavior. Map tiles degrade
according to MapKit's normal offline behavior; the saved point projection
remains local and available.

## Thumbnail Fallbacks

Every map thumbnail prefers the owner's captured visual. `ScanThumbnail` then
uses an already-saved, sanitized `referenceImageUrl` as its normal fallback. If
the captured path is absent or cannot be decoded and the scan has no saved
reference, the waypoint, selected preview, and **Your scans** row can request
the existing species-reference pipeline.

`PrivateScanMapStore` deduplicates those requests by scan ID, drains at most 12
at a time, and applies the same 15-minute retry interval as the shared backfill
actor. A private SwiftData actor revalidates the current record and effective
identification before the lookup. Unresolved identifications, people, domestic
cats, and domestic dogs remain ineligible. Corrected identifications do not
reuse a stale GBIF taxon key.

The lookup reuses the Species Dictionary cache and existing Wikipedia/GBIF
fallback, persists only the sanitized reference URL in the existing scan field,
prewarms `LocalImageLoader`, and refreshes the rich map revision after a real
write. It never receives or transmits the scan coordinate. No request starts
while offline; the thumbnail remains a safe placeholder and may retry after
connectivity returns.

`ScanThumbnail` receives online availability as an explicit value. The map view
reads that value from the app-owned queue manager before entering MapKit's
annotation builder and passes it through waypoints, the selected preview, and
sheet rows. Annotation content must not resolve an observable environment
dependency of its own: MapKit can host that content outside the ordinary SwiftUI
environment chain when zooming crosses the thumbnail threshold. Connectivity
changes still rebuild the value and restart only the affected remote thumbnail
task.

## Sensitive Reset

`ScanRepository.purgeAllData` requires its caller to provide a derived-state
reset. Account deletion and accepted cleanup recovery pass
`PrivateScanMapStore.resetSensitiveState`, which runs before SwiftData deletion.
The reset synchronously empties observable snapshots, cancels and detaches
refresh/backfill work, retires and cancels active MapKit snapshotters, replaces
the actor index and preview renderer, and bumps an epoch that rejects stale
completions. The active map also clears its camera, point, filter, selection,
annotation, alert, and viewport-projector state when that generation changes.
Startup/location results and the sheet-to-Insight dismissal handoff carry the
same generation, so neither can publish after reset. Detached actors erase their
caches after the synchronous access boundary. A failed database purge emits a
normal library invalidation so the still-durable records can be projected again.

## Candidate Status

The source-level reset, refresh, startup-cancellation, and projected-clustering
findings are closed. Release acceptance still requires recorded simulator and
physical-device evidence for live location permission/user annotation, deletion
and destructive purge presentation, accessibility, appearance, large libraries,
and offline/degraded tiles. The canonical status and manual matrix live in the
linked verification contract.

## Verification

The mirrored `PrivateScanMapTests`, `PrivateScanMapClusteringTests`,
`PrivateScanMapScreenProjectionTests`, and `PrivateScanMapLifecycleTests` suites
cover preview and rich projection, privacy eligibility, index revisions,
filter/camera/viewport state, bounded and coincident clustering, exact 56-point
projected cells at high latitude and the antimeridian, projected anchors,
lossless refresh retry, synchronous sensitive reset with stale-completion
rejection and durable recovery, startup cancellation before location, and reset
while startup or manual location is in flight. The Debug-only
`-seedPrivateScanMapFlow` fixture supplies 305 synthetic mapped records for the
focused collection-to-map-to-preview-to-Insight and sheet-to-Insight UI test and
is excluded from Release binaries.

That fixture suppresses the location prompt and therefore validates the
newest-scan fallback, not a real authorized location or system user annotation.
The complete automated commands, manual device matrix, and unresolved candidate
findings are maintained in the canonical
[Verification Contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md#verification-contract).
