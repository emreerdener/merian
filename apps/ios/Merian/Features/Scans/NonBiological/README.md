# Scans Non-Biological

The `NonBiological` directory isolates captures that the system identified as inanimate objects or non-biological subjects.

## Structure

- **Views**: Contains the grid and detail views specifically scoped to non-biological items.

## Purpose
By separating non-biological captures from the main library, the app keeps the primary `Library` focused purely on ecology and nature. This area provides a dedicated space where users can still review and manage scans of everyday objects, while ensuring these items eventually age out according to the retention window policy.

## Bulk deletion feedback

Delete All first copies lightweight erasure payloads, then performs database and
file cleanup away from the main actor. Its compact progress badge has hit
testing disabled, so scrolling and navigation are not covered by an invisible
full-screen blocker. The affected grid is temporarily noninteractive and hidden
from accessibility, and the destructive toolbar action is disabled until the
snapshot completes; unrelated presentation chrome remains available.

Completion sends the loss-tolerant `AppEvent.scanLibraryChanged` invalidation
only after durable mutation. The result is a typed `ToastPayload` rendered by
`merianSystemFeedback`; its identity-checked structured task is ephemeral
feedback and never acts as deletion authority.
