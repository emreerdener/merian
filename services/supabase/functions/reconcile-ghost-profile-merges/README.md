# Reconcile Ghost Profile Merges

Durable service-role worker for the final Auth cleanup step of an anonymous
profile merge.

`merge-ghost-profile` commits all data ownership changes before deleting the
obsolete anonymous `auth.users` row. If the request is interrupted, the Auth
Admin API is temporarily unavailable, or the client never opens again, the
database receipt remains authoritative and this worker completes the cleanup.

## Authorization

The function is not a user API. Its `config.toml` entry deliberately uses
`verify_jwt = false` so `pg_net` can reach the handler with the service-role
credential. The handler then requires an exact
`Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` match using
`timingSafeCompare`. No browser or iOS client may call it or receive the
service-role key.

## Schedule and lease

Migration `20260723043447_secure_atomic_ghost_profile_merge.sql` schedules the
worker every five minutes. The service-role claim RPC:

- durably marks expired prepared handoffs;
- returns at most 100 merged receipts whose `auth_deleted_at` is null;
- leases each row with a random claim token and `FOR UPDATE SKIP LOCKED`;
- reclaims an abandoned lease after ten minutes; and
- backs off repeated failures from one to fifteen minutes.

For each claim, the worker calls `auth.admin.deleteUser(ghost_user_id)`. HTTP
404 and the exact Auth code `user_not_found` are idempotent success; a generic
message containing “not found” is not. The claim-token-bound finish RPC records
success or the bounded error code. A source Auth row is never deleted by the
database merge transaction itself.

## Manual invocation

Use only a server-side environment:

```bash
curl --fail-with-body \
  -X POST "$SUPABASE_URL/functions/v1/reconcile-ghost-profile-merges" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data '{"limit":25}'
```

The response reports `claimed`, `deleted`, `failed`, and per-receipt errors. A
successful HTTP response can still contain retryable row failures; inspect
`failed` rather than treating HTTP 200 alone as a clean queue.

## Verification

```bash
deno check \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/index.ts
deno test \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/worker_test.ts
supabase --workdir services test db --local \
  services/supabase/tests/ghost_profile_merge_security.sql
```

Operational SQL and rollout/rollback steps are in
`docs/backend-and-data/06-supabase-deployment-runbook.md`.
