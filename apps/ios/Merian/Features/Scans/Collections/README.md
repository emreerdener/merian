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
- **Map entry**: Builds a value snapshot of completed biological scans with
  valid GPS and places a non-interactive, full-width map preview above Featured
  scans. The card participates in collection result counts, empty-state logic,
  and searches for map, private, location, and "your scans" terms.

## Purpose

This area allows users to organize their captures into custom groups. It handles
the display of these groups and integrates with the backend synchronization
pipeline to ensure collections are persisted via Supabase.

The Scan map card is not a synchronized `ScanCollection`. It appears only when
at least one local record can be mapped and pushes the Scans-owned private map
inside the existing navigation stack. The preview always fits the complete
extent of the owner's mapped scans and does not request current location.

See the
[Private Scan Map contract](../../../../../../docs/features-and-hardware/28-private-scan-map.md)
for eligibility, search/count behavior, antimeridian framing, privacy, and
release verification.
