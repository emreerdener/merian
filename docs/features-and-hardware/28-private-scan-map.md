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

`PrivateScanMapSnapshot` builds a value-only projection from the
`LocalScanRecord` rows already loaded by the Scans library. A record is included
only when all of the following are true:

- it is a completed `LocalScanRecord`, not an `OfflineQueuedScan`;
- `isBiological == true`;
- latitude and longitude are both present and finite;
- latitude is in `-90...90` and longitude is in `-180...180`; and
- the coordinate is not the invalid `0,0` sentinel. A valid coordinate on only
  one equator or prime-meridian axis remains eligible.

The projection copies only the scalar and presentation values needed by the map:
scan ID, saved coordinate, names, timestamp, optional location label, species
category, local media-type flags, and thumbnail references. It sorts newest
first with the scan ID as a deterministic tie-breaker. Map rendering and
clustering operate on these values rather than retaining SwiftData model
objects.

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

Annotations use deterministic 56-point screen-space cells:

- broad zoom shows simple scan dots and numeric cluster bubbles;
- zoom level 11.5 and closer uses circular scan thumbnails when an individual
  point is rendered;
- tapping a non-coincident cluster zooms to its fitted extent; and
- coincident points that cannot be separated further remain available through
  the scan-list sheet.

Tapping a point selects it and displays a compact owner-only preview. The
required interaction contract is that selecting the preview opens the existing
embedded private Insight. Tapping the visible-count control or an inseparable
cluster presents a medium/large sheet titled **Your scans**, with a lock-backed
**Private** subtitle. Selecting a sheet row first dismisses the sheet and only
then pushes Insight, so sheet and navigation presentation state cannot race.

Before opening Insight, the destination resolves the selected ID against the
current `LocalScanRecord` query. A record deleted after snapshot creation must
produce **Scan Unavailable** rather than opening stale content.

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
- persist a map-preview image or derived coordinate cache; or
- expose social actions, public profiles, **Search this area**, or public post
  detail from the private map.

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

| Area                                                                      | Owner                                                                                     |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Collections placement, search/count/empty-state integration               | `apps/ios/Merian/Features/Scans/Collections/`                                             |
| Snapshot, region math, clustering, card, filters, map, preview, and sheet | `apps/ios/Merian/Features/Scans/Map/`                                                     |
| Native push/back behavior and embedded Insight destination                | `apps/ios/Merian/Features/Scans/Shell/`                                                   |
| Existing location permission and one-shot lookup                          | `EnvironmentContextManager`                                                               |
| Public map and public coordinate projection                               | `apps/ios/Merian/Features/Explore/Map/` and Supabase Explore contracts; never `Scans/Map` |

The implementation-local ownership notes live in the
[Scans Map README](../../apps/ios/Merian/Features/Scans/Map/README.md).

## Verification Contract

### Automated coverage

`PrivateScanMapTests` must cover:

- inclusion and coordinate validation;
- exact-coordinate preservation for shared and unshared records;
- category/media projection and corrected species names;
- full-extent fitting across the antimeridian;
- current-location preference and newest-scan fallback;
- local filter composition and the true viewport count;
- **Show scans** recovery;
- snapshot refresh after deletion;
- the zoom 11.5 thumbnail threshold; and
- deterministic 56-point clustering, large libraries, and coincident points.

The focused Debug UI fixture `-seedPrivateScanMapFlow` must cover card
visibility/order, native navigation, removed root/Explore chrome, bottom-control
placement, filters, **Your scans / Private**, sheet-row dismissal before
Insight, and Back returning to Collections. Synthetic fixture locations must be
obviously non-personal. The fixture and its identifiers must remain Debug-only,
and the Release archive marker denylist must reject them.

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
| No scans in the current region                           | **Show scans** fits every filtered scan without clearing filters.                                                                                                               |
| Deletion while map, preview, list, or Insight is active  | Deleted selection clears or reports **Scan Unavailable**; remaining points/counts update; deleting the last point leaves a stable empty map; Back still returns to Collections. |
| Coincident points                                        | The cluster remains selectable at maximum zoom and opens all coincident scans in the private sheet.                                                                             |
| Large library                                            | Pan, zoom, filtering, clustering, and sheet presentation remain responsive and memory-stable.                                                                                   |
| Dynamic Type                                             | Card, filters, bottom controls, preview, and medium/large sheets remain readable without clipped required actions.                                                              |
| VoiceOver                                                | Labels, values, selected traits, traversal order, preview action, sheet rows, and Back behavior are correct.                                                                    |
| Light and dark appearance                                | Map overlays, materials, text, selected states, and thumbnails retain contrast.                                                                                                 |
| Offline/degraded tiles                                   | Local points, filters, counts, **Show scans**, list, and Insight navigation continue to work even when base-map tiles are missing or stale.                                     |

### Candidate Release Status

The source candidate is implemented but must not be described as shipped until
the following findings and evidence gaps are closed:

1. `PrivateScanMapSnapshot.init(records:)` reads SwiftData-backed
   `LocalScanRecord` values without an explicit `@MainActor` contract. Current
   construction sites are main-actor views and tests, but the type boundary must
   enforce that invariant before acceptance.
2. The compact preview currently opens Insight through its **View scan** button
   only. The complete preview must satisfy the required tap contract, and the UI
   suite must add point -> preview -> Insight coverage.
3. The focused UI fixture does not prove live location permission or the user
   annotation, and it proves sheet-row -> Insight rather than the preview route.
4. The required manual location, deletion/presentation, accessibility,
   appearance, large-library, and offline matrix has not yet been recorded
   against a candidate build.

These are candidate defects or missing evidence, not accepted product
limitations. Closing them does not authorize TestFlight distribution, App Store
submission, or any deployment.
