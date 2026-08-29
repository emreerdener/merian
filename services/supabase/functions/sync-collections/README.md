# Sync Collections

Authenticated offline-first reconciliation for custom scan collections and their
many-to-many scan memberships. The caller sends its current bounded local state
after reconnecting; the route applies only owner-safe collection writes and the
membership delta.

Foreign collection IDs and unavailable scans are intentionally skippable. One
stale offline UUID must not block unrelated collections, but no skipped record
may be reparented or joined across owners.

## Request

`POST /functions/v1/sync-collections` with a verified user access JWT:

```json
{
  "collections": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "name": "Backyard",
      "created_at": "2026-08-03T12:00:00Z",
      "scan_ids": ["22222222-2222-4222-8222-222222222222"],
      "is_deleted": false
    }
  ]
}
```

The canonical current iOS payload uses `is_deleted`; the route also accepts
`isDeleted` as a backwards-compatible alias for historical Swift encoder output.
Senders do not need to include both keys. In the active iOS V50 model,
`ScanCollection.isPendingDeletion` maps to the released SwiftData `isDeleted`
column with `@Attribute(originalName:)` and is explicitly projected to
`is_deleted`. This source-only rename does not change the persisted V50 model or
the wire contract. Bounds are enforced before database work:

- at most 200 collections per request; and
- at most 5,000 `scan_ids` per collection.

The iOS caller supplies deterministically sorted memberships projected directly
from each non-Favorites `ScanCollection.scans` relationship. It must not rebuild
the payload by paging across unrelated `LocalScanRecord` rows.

Success remains additive and does not enumerate skipped IDs:

```json
{
  "success": true,
  "message": "Collections synchronized successfully."
}
```

Rejected collection IDs and unavailable memberships are emitted only as bounded
structured server warnings for operational monitoring.

## Owner-safe reconciliation

The route resolves `user.id` from the JWT. Ownership is never read from request
JSON.

1. Active rows are passed to service-only
   `upsert_owned_collections(p_user_id, p_collections)`. One atomic
   `INSERT ... ON CONFLICT ... DO UPDATE` inserts new rows and updates only
   `name` and `created_at` when a collision already belongs to `p_user_id`.
   Every input ID is returned as accepted or rejected. A foreign or concurrent
   UUID collision is rejected without modifying its row.
2. Only accepted IDs continue to membership hydration and delta calculation. If
   the guarded upsert errors, the exception stops all downstream membership work
   and the route returns a retryable server failure.
3. Explicit collection tombstones are deleted with both ID and `user_id`
   predicates. Foreign IDs affect zero rows. A database error is not treated as
   success.
4. Existing memberships for accepted collections are read in bounded pages
   ordered by `(collection_id, scan_id)`. Each full page resumes strictly after
   its final composite primary key; range/OFFSET pagination is not used.
5. Obsolete memberships are removed only from accepted owner collections.
   Additions use service-only
   `insert_owned_collection_scans(p_user_id, p_rows)`, which joins both the
   collection and scan parents to `p_user_id`. Missing or foreign scans are
   skipped until a later offline-sync pulse rather than raising a foreign-key
   failure for the whole batch.

The delta engine is O(N) over `collection_id::scan_id` set keys and writes only
additions and removals. It never deletes and recreates every membership.

## Database defense in depth

Migration `20260803180211_harden_collection_ownership_and_memberships.sql` owns
the database boundary. Its forward repair,
`20260803215309_fix_collection_owner_upsert_ordinality.sql`, replaces the
collection upsert with valid JSON-array ordinality parsing while preserving the
same accepted/rejected-ID semantics. Its paired
`20260803215310_grant_collection_sync_invoker_privileges.sql` grants only the
table operations required by the invoker routines; it does not restore
table-wide owner updates. The follow-up
`20260804002819_fix_collection_membership_conflict_ambiguity.sql` replaces an
ambiguous PL/pgSQL conflict-column list with the canonical composite primary key
constraint:

- `service_role` has no table-wide collection UPDATE and may directly update
  only `name` and `created_at`; it cannot reassign `user_id`;
- both RPCs are `SECURITY INVOKER`, use empty search paths with fully qualified
  objects, revoke default/public execution, and grant execute only to
  `service_role`;
- an invoker trigger rejects every membership insert or parent-ID update unless
  both parents exist and have the same owner, including direct service-key
  access;
- the migration removes provably cross-owner historical memberships before
  enabling that trigger; and
- authenticated RLS separately permits select/delete through an owned collection
  and insert only through an owned collection plus an owned scan. Membership
  updates are unsupported.

Ghost-account collection reparenting remains available only through the existing
reviewed privileged merge function. Do not restore broad `service_role` UPDATE
to support merges or future route code.

## Modules

- `index.ts` owns bounded JSON parsing, delete-flag normalization, operation
  ordering, and the HTTP response.
- `types.ts` owns `SyncCollectionPayload` and `MembershipRow`.
- `db.ts` owns guarded RPC adapters, owner-scoped deletion, composite-key
  hydration, and membership delta writes. RPC/read/write errors always throw;
  none are downgraded to an empty ownership result.

## Verification

Regression coverage must prove:

- foreign and concurrently colliding collection IDs remain foreign-owned while
  accepted collections still return success;
- an ownership-RPC failure performs no membership fetch or write;
- missing and foreign scans are skipped through the insertion RPC;
- cross-owner inserts fail through the RPC, direct `service_role` table access,
  and authenticated RLS;
- direct `service_role` owner changes fail while mutable-field updates succeed;
- the owner-match trigger rejects parent updates as well as inserts;
- keyset membership hydration never uses OFFSET; and
- Ghost merge can still reparent collections through its privileged function.

Source and migration-shape tests live beside this route and under
`functions/_tests/collectionOwnershipMigrationContract.test.ts`. Executable
catalog/ACL/RLS behavior lives in `tests/collection_ownership_security.sql` and
must run against a fresh disposable database before promotion.
