# Sync Collections

The central reconciliation endpoint strictly for Offline-First Data. If the iOS
app goes offline to scan deep in the woods, the database states diverge. Upon
re-connection, the SwiftData infrastructure calls this endpoint to merge local
offline scans, resolve timestamp conflicts, and securely re-align the server
with the mobile app's reality.

## Architecture

To safely manage complex many-to-many Postgres states across highly distributed
offline mobile clients, the logic is aggressively decoupled:

- **`index.ts`** The lightweight HTTP router. It validates the array structure
  bounds (maximum 200 items per batch to prevent payload timeouts), maps iOS
  models by their `is_deleted` flags, and sequentially orchestrates the three
  Database operations explicitly.

- **`types.ts`** Stores exact interfaces for `SyncCollectionPayload` and
  `MembershipRow` so Deno strictly tracks Swift codable arrays.

- **`db.ts`** Contains isolated Postgres wrappers, specifically handling the
  algorithmically complex `syncMembershipDelta(...)`. To prevent hammering the
  Supabase instance, it utilizes an advanced `O(N)` String-Set differencing
  engine (mapping `collection_id::scan_id`). Existing memberships are hydrated
  for all owned collections with one paginated `.in("collection_id", ownedIds)`
  query ordered by `collection_id, scan_id`, avoiding the old N+1 per-collection
  pagination loop while staying bounded in V8 memory. It batches changes into
  groups to hit single-index queries, prevents Foreign-Key anomalies via
  pre-validation against the `scans` table, and explicitly ignores duplicates.

  Pagination is keyset-based: every full page records its final
  `(collection_id, scan_id)` primary key and the next query resumes strictly
  after that cursor. Do not replace this with `.range(...)`/OFFSET pagination;
  large membership sets would pay progressively more database work before the
  same delta calculation.

The iOS caller supplies deterministically sorted desired memberships projected
from each non-Favorites `ScanCollection.scans` relationship. It must not rebuild
that payload by paging across unrelated `LocalScanRecord` rows.
