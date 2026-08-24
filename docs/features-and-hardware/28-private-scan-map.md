# Private Scan Map

The Private Scan Map is the owner-only spatial index for the local Scans
library. It appears in Collections and uses the exact saved coordinates of the
current owner's mapped scans. It is deliberately independent of Explore Map,
Nearby, public post location settings, and social state.

## Product Contract

- The feature is available to every user with at least one mappable scan. It is
  not Pro-gated, feature-flagged, or entitlement-backed.
- **Private** describes access to the map surface. It is not a filter. Shared,
  unshared, open, obscured, and private scans all remain visible to their owner
  at the exact coordinate saved on the scan record.
- The feature adds no SwiftData schema, Supabase/API payload, backend query,
  deployment dependency, or public projection.
- The Collections preview never requests current location. Only the interactive
  map requests location, using the app's existing Core Location permission and
  privacy declarations.

## Eligible Scans

The application path builds value-only projections through a short-lived
`PrivateScanMapDatabaseActor`. Its private SwiftData context reads the durable
library away from the UI actor and returns detached scalar values to
`PrivateScanMapIndexService`; neither MapKit surface retains a
`LocalScanRecord`. A record is included only when all of the following are true:

- it is a completed `LocalScanRecord`, not an `OfflineQueuedScan`;
- `isBiological == true`;
- latitude and longitude are both present and finite;
- latitude is in `-90...90` and longitude is in `-180...180`; and
- the coordinate is not the invalid `0,0` sentinel. A valid coordinate on only
  one equator or prime-meridian axis remains eligible.

The index publishes two immutable siblings. `PrivateScanMapPreviewSnapshot`
contains only scan ID and saved coordinate. `PrivateScanMapSnapshot` contains
the names, timestamp, optional location label, species category, local
media-type flags, and thumbnail references needed by the interactive page. The
database actor prefers the scalar captured-media JSON and faults the media
relationship only for legacy records where that JSON is absent. The index parses
a changed record's media payload once, reuses unchanged point values, and sorts
newest first with scan ID as a deterministic tie-breaker.

The index has separate monotonic content and spatial revisions. A name,
thumbnail, category, or media-only update refreshes the interactive values but
does not regenerate the Collections map image. Insertions, deletions, and
coordinate changes advance the spatial revision. An unchanged refresh advances
neither revision. A fresh database actor is used for every refresh so a
long-lived SwiftData context cannot return a stale library after background sync
or deletion.

Explore publication state and post-level location sharing are intentionally not
inputs. The map must not round, obscure, or remove an owner coordinate based on
its public representation.

## Collections Entry

Collections renders one full-width **Scan map** card above **Featured scans**
when the eligible projection contains at least one point. The card:

- is hidden when there are no eligible points;
- shows `N mapped scans` and a lock-backed **Private** label;
- uses a non-interactive MapKit preview with no pan, zoom, selection, or live
  location request;
- fits the complete eligible extent, including the shortest wrapped longitude
  arc for an extent crossing the antimeridian; and
- participates in collection search, result counts, and empty-state decisions.

The card does not host a live SwiftUI `Map`. A shared actor renders an
`MKMapSnapshotter` image asynchronously, draws the bounded point/cluster overlay
off the main actor, and keeps at most four variants in memory by spatial
revision, pixel size, and appearance. While MapKit is loading or unavailable,
the card remains tappable over a lightweight placeholder. Images and derived
coordinates are never written to disk.

`PrivateScanMapStore` owns the process-local index and listens to the
loss-tolerant `scanLibraryChanged` event. Refresh coalescing must be lossless: a
request received while another refresh is in flight represents a later
generation and must remain pending even if the current attempt fails. A failed
attempt may report its error, but it must schedule or preserve the newer
generation rather than leave the map indefinitely stale. The Collections view
observes the store's coordinate snapshot instead of synchronously hashing or
projecting the full library during `body` evaluation. A transient zero-sized
preview produces no render request.

The interactive page's initial task awaits the shared store refresh and installs
the rich snapshot before making its one-shot location request. It must check for
task cancellation after the refresh and before requesting location, so using
Back during startup cannot trigger a permission prompt or location lookup from a
departed destination. Denied or unavailable location can then fall back to the
newest mapped scan without a sequencing race. Later content revisions refresh
the view model without requesting location again; snapshot arrival also recovers
a still-unframed fallback defensively. Duplicate events whose durable values
have not changed do not advance a revision or rebuild map state.

The search aliases are `scan map`, `map`, `private`, `locations`, and
`your scans`; partial, case-insensitive matches are accepted.

The card is a virtual library entry, not a `ScanCollection`. It must not be
persisted, synchronized through `/sync-collections`, added to collection edit
flows, or included in collection mutation telemetry.

## Interactive Map

Tapping the card pushes `PrivateScanMapView` inside the existing Scans
`NavigationStack`. The destination uses the inline title **Scan map** and the
native back item **Collections**, preserving interactive edge-swipe navigation.
It does not show the Scans root X, Scans/Collections picker, add button, bottom
search field, Explore Feed/Map tabs, notification bell, or app bottom
navigation.

On first presentation, the page makes one location request:

1. A valid current location centers the initial camera around the user and
   allows MapKit's system user annotation to render.
2. A denied, unavailable, invalid, or missing location falls back to the newest
   eligible scan.
3. Saved scans remain usable when location is denied. The **Locate me** action
   can request again, routes a denied user to Settings, and reports temporary
   unavailability without hiding scan data.

When the filtered library contains scans but the current viewport contains none,
the map presents **Show scans** and fits the complete filtered extent. When
filters remove every point, it presents **Reset filters**. If the last eligible
scan is deleted while the page is open, the page remains stable and shows its
mapped-scans empty state.

The count and locate controls sit directly above the bottom safe area, in the
space normally occupied by the app's bottom navigation. `N discoveries in view`
is the true number of filtered scan points in the current region; it is not the
number of rendered annotations or clusters.

## Filters, Annotations, and Selection

Species-category and media-type filters are computed locally from the snapshot.
Selected species categories compose with selected media types using AND;
multiple selected media types use OR. Filters never issue a network request or
change the underlying library.

Viewport work runs in `PrivateScanMapViewportProjector`, not on the UI actor. It
keeps a fixed one-degree spatial bucket index for the current filtered dataset,
queries only buckets intersecting the wrapped viewport, and rejects candidates
outside the exact region. Every pan, zoom, dataset, or filter change cancels the
previous generation; only the newest completed projection may update the UI.
This preserves antimeridian correctness and prevents stale results from a large
library.

Annotations use deterministic 56-point screen-space cells. The 56-point distance
is measured after projecting coordinates into MapKit/Web-Mercator space and
wrapping the visible map rect across the antimeridian; dividing raw latitude and
longitude by the visible coordinate span is not screen-space clustering and does
not satisfy this contract, especially at high latitudes.

With that projection:

- broad zoom shows simple scan dots and numeric cluster bubbles;
- zoom level 11.5 and closer uses circular scan thumbnails when an individual
  point is rendered;
- tapping a non-coincident cluster zooms to its fitted extent; and
- coincident points that cannot be separated further remain available through
  the scan-list sheet.

Tapping a point selects it and displays a compact owner-only preview. The
required interaction contract is that selecting the preview opens the existing
embedded private Insight. Tapping the visible-count control or an inseparable
cluster presents a medium/large sheet titled **Your scans**, with a text-only
**Private** subtitle. Selecting a sheet row first dismisses the sheet and only
then pushes Insight, so sheet and navigation presentation state cannot race.

### Thumbnail Sources and Recovery

An individual waypoint, selected preview, or **Your scans** row must prefer the
owner's captured image. When that bitmap is absent or unreadable,
`ScanThumbnail` tries the scan's existing sanitized `referenceImageUrl`. If no
reference has been saved, the map may request one on demand for the current
effective biological identification.

The request uses the existing bounded thumbnail-backfill path: the Species
Dictionary cache is checked first, followed by the existing Wikipedia and GBIF
fallbacks. Requests are deduplicated by scan ID, drained in batches of at most
12, and held to a 15-minute retry interval. A corrected identification is used
as the lookup key without reusing the former taxon's GBIF key. Unresolved
identifications, people, domestic cats, and domestic dogs remain ineligible for
third-party reference imagery.

Only a successfully sanitized URL is stored in the existing
`LocalScanRecord.referenceImageUrl` field. A real write prewarms the shared
image loader and advances the interactive content revision so every visible map
surface can replace its placeholder without reopening the page. This recovery
does not change the coordinate or spatial revision, persist a map image, add a
schema field, or use an Explore DTO. When offline, the map makes no reference
request and retains its placeholder; connectivity restoration may start the
request through the thumbnail's normal retry identity.

The reusable thumbnail accepts online availability as an explicit scalar. The
map owner resolves that value before constructing MapKit annotation content and
passes it through waypoints, previews, and sheet rows. An annotation must never
perform its own required observable-environment lookup: MapKit may host the
annotation outside the ordinary SwiftUI environment chain as zoom changes
instantiate thumbnail waypoints. A connectivity change produces a new scalar and
restarts only the relevant remote thumbnail task.

`ScansSheetView` is the sole navigation owner. The Collections card appends the
typed `ScansNavigationRoute.privateScanMap` value; `PrivateScanMapView` emits a
selected scan ID but owns no Insight route or `.navigationDestination`; the
Scans root converts that ID to `ScanInsightRoute` on its existing
`NavigationPath`. Keeping presentation mutation outside the Map-owning subtree
decouples destination commits from MapKit's render lifecycle, keeps one native
Back stack, and removes responsibility for committing the Insight transition
from the populated Map subtree.

MapKit remains retained lower in that navigation stack during the push. The view
model cancels and suspends only Merian's viewport projection, then resumes it
when the map becomes visible again. The shared local-Insight loader performs one
fetch-limited lookup for the selected ID after the destination mounts, hydrates
`InferenceEngine`, and only constructs `InsightSheetView` after that exact
record is ready. The sheet recognizes this route-owned load and does not cancel
and restart the same hydration. Neither layer searches or retains an all-library
SwiftData query. A record deleted after snapshot creation produces **Scan
unavailable** rather than stale Insight content.

## Privacy and Data Boundaries

Exact coordinates are allowed here because the surface is scoped to the current
owner's local scan library. That exception does not make exact coordinates safe
for other UI or data paths.

The module must never:

- send the snapshot through an Explore DTO, RPC, endpoint, or cache;
- use `explore_posts.location_sharing` or public-coordinate fields as its
  source;
- log a coordinate or include one in telemetry, crash breadcrumbs, or test
  artifacts;
- pass a coordinate to Species Dictionary, Wikipedia, GBIF, or thumbnail
  recovery; those requests receive only the current effective species identity;
- write a map-preview image or derived coordinate cache to persistent storage;
  the bounded preview image cache is process memory only and its keys contain
  only revision, pixel dimensions, and appearance; or
- expose social actions, public profiles, **Search this area**, or public post
  detail from the private map.

Process-memory retention is still sensitive. Destructive account cleanup or a
local destructive library purge must synchronously empty the store's observable
snapshots, invalidate the actor index, cancel in-flight projection and preview
work, and clear every rendered preview variant before the affected UI can render
again. A stale task must not repopulate those values after reset. Posting an
eventual `scanLibraryChanged` notification is not an adequate erasure boundary.

MapKit may obtain ordinary system map tiles through Apple's services. That is
separate from the app uploading the owner's scan-coordinate projection. When
tiles are unavailable offline, local annotations, counts, filters, list
recovery, and Insight routing must remain functional over MapKit's degraded
base-map presentation.

See [Geoprivacy](./22-geoprivacy.md) for the owner/public projection boundary
and the [Explore page RFC](../rfcs/explore-page.md) for public map eligibility.

## Accessibility and Adaptation

The map must preserve:

- a descriptive card label containing **Scan map**, the mapped count, and
  **Private**;
- spoken names for individual points and scan counts for clusters;
- explicit labels for **Map filters**, **Locate me**, the visible-count action,
  **Your scans**, and **Private**;
- native selected traits on active filter pills;
- a minimum 44-point action target where an element is interactive;
- readable controls and sheets at supported Dynamic Type sizes;
- visible material contrast in light and dark appearance; and
- native back-button and edge-swipe behavior rather than a custom X or manual
  gesture.

VoiceOver must be able to move from map/filter controls to recovery state,
visible count, locate, selected preview, and sheet rows without exposing
decorative map geometry as duplicate elements.

## Code Ownership

| Area                                                                                                                              | Owner                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Collections placement, search/count/empty-state integration                                                                       | `apps/ios/Merian/Features/Scans/Collections/`                                             |
| Database actor, revisioned index, preview renderer, spatial projection, region math, clustering, filters, map, preview, and sheet | `apps/ios/Merian/Features/Scans/Map/`                                                     |
| Typed map/Insight path ownership and native push/back behavior                                                                    | `apps/ios/Merian/Features/Scans/Shell/`; the map only emits selection values              |
| Value-route lookup, one-time engine hydration, and embedded Insight construction                                                  | `apps/ios/Merian/Features/Insights/Shell/`                                                |
| Existing location permission and one-shot lookup                                                                                  | `EnvironmentContextManager`                                                               |
| Public map and public coordinate projection                                                                                       | `apps/ios/Merian/Features/Explore/Map/` and Supabase Explore contracts; never `Scans/Map` |

The implementation-local ownership notes live in the
[Scans Map README](../../apps/ios/Merian/Features/Scans/Map/README.md).

## Verification Contract

### Automated coverage

`PrivateScanMapTests` must cover:

- inclusion and coordinate validation;
- exact-coordinate preservation for shared and unshared records;
- category/media projection and corrected species names;
- captured-image/reference fallback projection, missing-visual recovery
  eligibility, corrected-identification fencing, and suppression for unresolved,
  human, and domestic-pet scans;
- full-extent fitting across the antimeridian;
- current-location preference and newest-scan fallback, including snapshot
  arrival after an unavailable-location result;
- cancellation after a delayed initial refresh, proving a departed map never
  begins its one-shot location request;
- local filter composition and the true viewport count;
- **Show scans** recovery;
- snapshot refresh after deletion;
- lossless refresh coalescing when a request arrives during an attempt that
  fails, followed by a successful retry of the pending generation;
- synchronous sensitive-state reset, including empty observable snapshots,
  invalidated spatial and preview caches, and rejection of stale completions;
- stable actor-index revisions for unchanged data, content-only changes,
  coordinate changes, and deletion;
- spatial-index candidate correctness across the antimeridian;
- the zoom 11.5 thumbnail threshold;
- deterministic projected 56-point screen-space clustering at ordinary and high
  latitudes, across the antimeridian, with large libraries and coincident
  points; and
- coordinate-only preview projection, presentation-field isolation, and
  deterministic large-library preview clustering, including zero-size layout
  deferral before and after a nonzero viewport.

The focused Debug UI fixture `-seedPrivateScanMapFlow` supplies 305 synthetic
mapped records and must cover card visibility/order and responsiveness, typed
root-owned navigation, removed root/Explore chrome, bottom-control placement,
filters, zooming across the dot/thumbnail threshold without losing the MapKit
gesture surface or app responsiveness, point selection, full-preview tap to
Insight, **Your scans / Private**, sheet-row dismissal before Insight, and Back
returning to Collections. Synthetic fixture locations must be obviously
non-personal. The fixture code and identifiers must remain behind `#if DEBUG`,
and the Release archive marker denylist must reject `-seedPrivateScanMapFlow`.

The configured UI-test launcher includes
`-seedLocationPermissionPromptSuppressed`. It therefore proves the saved-scan
fallback path, not a real permission prompt, authorized current location, or
system user annotation. A location-permission test must launch without that
argument.

Run the feature checks and iOS gates described in the
[testing strategy](../development-guides/08-testing-strategy.md#private-scan-map),
then record manual results against the exact candidate build.

### Required manual matrix

Before release acceptance, record pass/fail evidence for:

| Scenario                                                 | Required result                                                                                                                                                                 |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fresh permission, Allow Once/While Using                 | Initial camera centers on the real current position; one system user annotation appears; scans remain independent.                                                              |
| Denied, restricted, and temporarily unavailable location | Initial camera falls back to newest mapped scan; **Locate me** shows the appropriate Settings or unavailable path; saved scans remain usable.                                   |
| Back during initial refresh                              | The destination exits immediately and does not request location, present permission UI, or publish late map state.                                                              |
| No scans in the current region                           | **Show scans** fits every filtered scan without clearing filters.                                                                                                               |
| Deletion while map, preview, list, or Insight is active  | Deleted selection clears or reports **Scan Unavailable**; remaining points/counts update; deleting the last point leaves a stable empty map; Back still returns to Collections. |
| Destructive account or local-library purge               | Store snapshots, exact-coordinate index state, pending projections, and rendered preview variants clear synchronously; stale work cannot restore them.                          |
| Coincident points                                        | The cluster remains selectable at maximum zoom and opens all coincident scans in the private sheet.                                                                             |
| Large library                                            | Pan, zoom, filtering, clustering, and sheet presentation remain responsive and memory-stable.                                                                                   |
| Dynamic Type                                             | Card, filters, bottom controls, preview, and medium/large sheets remain readable without clipped required actions.                                                              |
| VoiceOver                                                | Labels, values, selected traits, traversal order, preview action, sheet rows, and Back behavior are correct.                                                                    |
| Light and dark appearance                                | Map overlays, materials, text, selected states, and thumbnails retain contrast.                                                                                                 |
| Offline/degraded tiles                                   | Local points, filters, counts, **Show scans**, list, and Insight navigation continue to work even when base-map tiles are missing or stale.                                     |

### Candidate Release Status

The source candidate now removes private-map SwiftData projection, full-library
identity hashing, media decoding, preview clustering, and viewport clustering
from the main actor. Collections uses an asynchronous static snapshot instead of
a live map, and the interactive page consumes the revisioned actor index with
cancellable spatial queries. The Scans root owns the typed map and Insight
routes, while the Map-owning view emits selection values and owns no destination
state. The 305-record UI fixture remains the automated responsiveness and
navigation-handoff floor. A physical-device retest remains part of the manual
large-library evidence below. It must not be described as shipped until the
following source findings and evidence gaps are closed:

1. Destructive account or local-library cleanup does not synchronously clear the
   app-scoped map store, actor index, in-flight work, and rendered preview
   cache.
2. A refresh requested during an in-flight attempt can be lost when that attempt
   throws, leaving a newer durable generation unprojected until another event.
3. The initial destination task does not check cancellation between the awaited
   refresh and its one-shot location request, so leaving during startup can
   still request location.
4. The viewport projector currently divides raw latitude and longitude into a
   56-cell coordinate grid. It is deterministic, but it is not a true 56-point
   projected screen-space grid and diverges at high latitude.
5. The focused UI fixture does not prove live location permission or the user
   annotation.
6. The required manual location, deletion/presentation, destructive-purge,
   accessibility, appearance, large-library, and offline matrix has not yet been
   recorded against a candidate build.

These are candidate defects or missing evidence, not accepted product
limitations. Closing them does not authorize TestFlight distribution, App Store
submission, or any deployment.
