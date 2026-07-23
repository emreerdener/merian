# Safe Account Deletion

Executes the irreversible right-to-erasure protocol for the user established by
the verified request session. The caller cannot nominate another user ID.

## Order and failure contract

1. `deleteAuthProfile` deletes the Supabase Auth user first, preventing refresh
   and making Auth-backed `getUser` checks fail. A previously issued signed
   access token can remain cryptographically valid until expiry, so database
   ACL/RLS and the tombstone are still required.
2. `applyUserTombstone` calls `public.apply_user_tombstone(uuid)` with that
   verified user ID. The RPC reassigns retained observations to the tombstone
   user, marks scans tombstoned, and deletes the public profile so relational
   cascades remove user-owned social/application rows.
3. `queueStorageDeletion` records best-effort Cloudflare R2 cleanup last.

If step 1 fails, no data mutation starts. If the tombstone fails after Auth
deletion, the endpoint returns `500` and emits
`safe_delete_partial_failure` with the user ID and the required manual repair.
The storage queue is intentionally non-throwing after Auth and relational
erasure have succeeded.

## Database authorization

`apply_user_tombstone(uuid)` is a public-schema discovery name, not a
client-callable RPC. Execution is revoked from `PUBLIC`, `anon`, and
`authenticated`, granted only through the reviewed `service_role` routine
allowlist, and checked again inside the function with
`internal.require_service_role()`. It uses `search_path = ''` and fully
qualified application objects.

Do not grant this routine to a client role or accept a target UUID from the
request body. Manual recovery must use an owner database session or a reviewed
service-role operator path, and must use the user ID recorded in the structured
partial-failure event.

## Source layout

- `index.ts` owns verified-session orchestration and partial-failure reporting.
- `db.ts` owns the Auth Admin call, tombstone RPC wrapper, and storage-deletion
  queue write.
