# Scans Collections

The `Collections` directory contains the logic and UI for managing user-created
collections (albums) of scans. It also hosts the entry card for the owner-only
Scan map.

## Structure

- **Views**: Contains screens for viewing a list of collections, viewing a
  specific collection's contents, and the flow for creating or editing
  collections.
- **Components**: Reusable UI elements specific to collections (e.g., collection
  grid tiles, header views).
- **Models**: Defines the local SwiftData and synchronization models for
  collections and their many-to-many relationships with individual scans.
- **Map entry**: Observes the Scans-owned, actor-backed coordinate snapshot and
  places a non-interactive, full-width map preview above Featured scans. The
  card uses an asynchronous static MapKit image rather than a live map, so
  collection rendering does not fetch SwiftData rows, decode scan media, cluster
  the full library, or wait for map tiles on the main actor. It participates in
  result counts, empty-state logic, and searches for map, private, location, and
  "your scans" terms.

## Purpose

This area allows users to organize their captures into custom groups. It handles
the display of these groups and integrates with the backend synchronization
pipeline to ensure collections are persisted via Supabase.

The Scan map card is not a synchronized `ScanCollection`. It appears only when
at least one local record can be mapped and pushes the Scans-owned private map
as a typed value in the existing Scans navigation path. The preview always fits
the complete extent of the owner's mapped scans and does not request current
location. `PrivateScanMapStore` serializes successful durable-library refreshes
and uses a spatial-only revision to avoid rebuilding the preview for name,
media, or thumbnail changes. Its lossless refresh generation retains a later
invalidation when an in-flight attempt fails, then drains the pending durable
generation. The bounded rendered-image cache is memory-only; neither the image
nor derived coordinates are persisted.

Memory-only data is still owner-sensitive. Destructive account or local-library
cleanup must synchronously clear the observable map snapshots, actor index,
pending work, and every rendered preview variant. An eventual
`scanLibraryChanged` notification is sufficient for ordinary library refresh,
but not for a destructive erasure boundary. The app-owned
`PrivateScanMapStore.resetSensitiveState` boundary now empties those values,
retires active snapshotters, rejects old-epoch completion, and replaces the
store-owned index and renderer before SwiftData deletion. A failed purge emits a
normal library invalidation so still-durable records can be projected again.

Collections does not construct the map destination in a closure. It appends
`ScansNavigationRoute.privateScanMap`; `ScansSheetView` owns destination
construction and every later `ScanInsightRoute`. This single path preserves
native Back/edge swipe behavior and prevents the Map-owning subtree from also
owning presentation state.

See the
[Private Scan Map contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md)
for eligibility, search/count behavior, antimeridian framing, privacy, and
release verification.
