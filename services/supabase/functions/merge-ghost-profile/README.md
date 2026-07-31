# Merge Ghost Profile

Securely moves an anonymous profile into an **existing** permanent Supabase
account.

This function is not used for the normal upgrade path. When Apple or Google can
be linked to the current anonymous user, Supabase Auth preserves the existing
user ID and no data merge is necessary. A merge is required only when the
provider identity is already attached to another permanent account.

## Protocol

The iOS client still owns the anonymous session when it discovers that direct
identity linking cannot succeed:

1. It reads the provider subject (`sub`) from the OAuth ID token.
2. It invokes this function with `operation = prepare`.
3. The function generates 256 bits of random secret material and stores only its
   SHA-256 hash.
4. The database binds the handoff to:
   - the authenticated anonymous source UUID;
   - the selected Apple or Google provider;
   - the exact provider subject;
   - a 30-day expiration.
5. The client stores the returned secret in a versioned
   `WhenUnlockedThisDeviceOnly` Keychain queue before switching sessions.
6. After signing in to the existing account, it invokes `operation = complete`.
7. The database proves that the destination account owns the bound provider
   identity, locks the handoff and both users, and performs the data merge in
   one transaction.
8. Only after that transaction commits does the Edge Function delete the empty
   anonymous Auth user.

The completion call is idempotent for the same destination and secret. If Auth
cleanup fails after the data transaction, the function returns a retryable 503;
repeating the same completion cannot move the data twice. The client removes
only successful or terminal invalid/expired queue entries. A service-role worker
also reconciles committed cleanup receipts every five minutes.

## Database guarantees

`public.consume_ghost_profile_merge_handoff` is the sole mutation entrypoint. It
uses `auth.uid()` as the destination rather than accepting a target UUID.

The transaction:

- resolves duplicate likes, follows, blocks, reports, chat conversations, Field
  Trip progress, and other unique-key conflicts;
- reparents every single-column foreign key that references `public.users` or
  externally references `auth.users`;
- adds non-blocking `NOT VALID` Auth foreign keys to pre-profile ingestion
  ledgers, so new writes serialize with a merge while historical orphan cleanup
  remains an independent rollout;
- reparents append-only AI usage explicitly under transaction-local
  source/target authorization; this ledger intentionally does not receive an
  Auth FK because normal account deletion has a separate guarded account-linkage
  clearing path;
- snapshots and preserves guest-customized public identity;
- verifies that no external foreign key still points to the source before
  deleting `public.users`;
- records a durable merge receipt for replay and cleanup auditing.

If a future migration introduces an unsupported composite user foreign key or a
new uniqueness conflict, the transaction fails and rolls back instead of
cascading user data away. The merge migration must then be extended alongside
that schema change.

## Operations

Rows in `internal.ghost_profile_merge_handoffs` with:

```sql
status = 'merged' AND auth_deleted_at IS NULL
```

represent committed data merges whose Auth cleanup should be retried. The client
retains the provider-bound handoff secret in Keychain until the endpoint
confirms cleanup. `reconcile-ghost-profile-merges` leases the same receipts with
a random claim token, ten-minute stale-lease recovery, and bounded retry
backoff, so cleanup does not depend on another app launch.

All handoff tables and helper routines are in the unexposed `internal` schema.
Public RPC wrappers revoke `PUBLIC`/`anon` access and grant only the minimum
required role.

## Authentication

`verify_jwt = true` is intentional. Both the anonymous prepare session and the
permanent completion session carry Supabase user JWTs; the gateway supports
legacy and asymmetric signing keys. `withEdgeHandler` then resolves the live
Auth user, and each database RPC independently derives authority from
`auth.uid()`.

## Rollout

The legacy payload cannot be made backward-compatible: it switches sessions
before calling the server and carries no source-session proof. Treat this as a
coordinated security rollout:

1. Ship the proof-capable iOS client (or place the OAuth-conflict path behind a
   minimum-version gate).
2. Apply the database migration and deploy this Edge Function in the same change
   window.
3. Enable the conflict fallback only for proof-capable clients and retire the
   old version according to the release policy.

A new client against the old endpoint fails `prepare` before it switches away
from its guest session. An old client against the new endpoint is rejected
because it cannot prove source consent, so it must be upgrade-gated to avoid
stranding guest data.

## Verification

```bash
deno check --config services/supabase/functions/deno.json \
  services/supabase/functions/merge-ghost-profile/index.ts
deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_tests/mergeGhostProfile.test.ts
deno test \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/worker_test.ts
supabase --workdir services test db --local \
  services/supabase/tests/ghost_profile_merge_security.sql
```
