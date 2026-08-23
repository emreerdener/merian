# Private Scan Map

`Scans/Map` owns the device-local spatial view of the current owner's scan
library. It is independent of Explore map DTOs, endpoints, publication state,
and social interactions.

The normative product, privacy, accessibility, verification, and candidate
release contract is in the
[Private Scan Map documentation](../../../../../../docs/features-and-hardware/28-private-scan-map.md).

## Projection

`PrivateScanMapSnapshot` copies the required scalar values out of
`LocalScanRecord`. Current construction sites are main-actor SwiftUI views and
main-actor tests, and `sourceIdentity(for:)` is explicitly main-actor isolated.
The record-reading initializer still needs an explicit actor contract before
release acceptance; see
[Candidate Release Status](../../../../../../docs/features-and-hardware/28-private-scan-map.md#candidate-release-status).
The value snapshot prevents map rendering from retaining SwiftData models while
the library changes. It includes every completed biological record with finite,
in-range saved GPS except the invalid `0,0` sentinel. Queued, non-biological,
missing-coordinate, and invalid rows are excluded.

The projection deliberately does not inspect Explore publication or per-post
location-sharing state. Shared and unshared scans both use the owner's exact
saved GPS because every surface in this module is private to the owner. Exact
coordinates stay in memory: the feature does not log them, add telemetry, or
persist rendered map previews.

## Surfaces

Collections shows a non-interactive, full-width **Scan map** card only when the
projection contains at least one point. The preview fits the complete point
extent, including extents that cross the antimeridian, and never requests live
location.

Tapping the card pushes `PrivateScanMapView` in the existing Scans navigation
stack. The page:

- requests a one-shot current location and shows the system user annotation;
- falls back to the newest mapped scan when current location is unavailable;
- offers **Show scans** whenever the current viewport contains no filtered
  scans;
- filters locally by species group and media type;
- clusters deterministically in 56-point screen cells;
- uses simple dots at broad zoom and circular thumbnails from zoom level 11.5;
- reports the true filtered viewport count independently of clustering;
- presents owner-only previews and a medium/large **Your scans** sheet;
- currently opens a preview's Insight through the explicit **View scan** action,
  while full-preview tap behavior remains a candidate acceptance item; and
- opens existing embedded private Insight destinations only after a list sheet
  has fully dismissed.

The pushed page owns no Explore tabs, bell, bottom navigation, offline API
banner, social actions, or **Search this area** behavior. Map tiles degrade
according to MapKit's normal offline behavior; the saved point projection
remains local and available.

## Verification

`PrivateScanMapTests` covers projection validity, exact-coordinate retention,
antimeridian fitting, location fallback, filtering, viewport counts, large
libraries, and deterministic/coincident clustering. The Debug-only
`-seedPrivateScanMapFlow` fixture supports the focused collection-to-map-to-
Insight UI test and is excluded from Release binaries.

That fixture suppresses the location prompt and therefore validates the
newest-scan fallback, not a real authorized location or system user annotation.
The complete automated commands, manual device matrix, and unresolved candidate
findings are maintained in the canonical
[Verification Contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md#verification-contract).
