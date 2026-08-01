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

The completed transaction contract:

- resolves duplicate likes, follows, blocks, reports, chat conversations, Field
  Trip progress, and other unique-key conflicts;
- requires every eligible single-column user foreign key to match the private,
  source-controlled merge-policy manifest before the first mutating helper;
- executes only reviewed ownership moves, preserves immutable administrative,
  audit, session, and moderator attribution, and fails closed on unsupported,
  stale, blocked, or composite topology;
- moves scans first so statement-level OLD/NEW deltas maintain the private
  species ledger, then verifies exact ledger counts against scans for both users;
- coalesces conflict-prone Community Identify actors and normalizes RevenueCat
  event, watermark, and reconciliation state before their references move;
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

Catalog discovery verifies coverage and resolves reviewed objects; it never
chooses merge semantics. If a future migration adds, removes, or retargets an
eligible user foreign key without updating the manifest, introduces an
unsupported composite key, or creates a new uniqueness conflict, the transaction
fails and rolls back instead of cascading or misattributing data. The policy and
required handler must be extended in the same forward schema change.

## Concurrency and provider-repair contract

Parent identities are locked before merge-sensitive child state. In particular,
both the merge and `public.apply_revenuecat_reconciliation(...)` must lock
`public.users` before `internal.revenuecat_reconciliation_queue`. Reconciliation
must then lock and revalidate its claim before changing entitlement or watermark
state. If completion resets or replaces the lease first, the stale callback
fails closed instead of applying an obsolete provider snapshot.

Completion must unconditionally upsert a destination reconciliation row. The
row uses the permanent UUID as `lookup_app_user_id`, is due immediately, resets
`attempt_count`, clears all claim/error fields, and exists whether or not the
anonymous source had a queue row. The foreground RevenueCat `logIn` call and
webhook delivery are accelerators; this destination queue is the durable repair
authority for a completely missed webhook.

Community activity actors use the writer-compatible
activity-group-before-actor order. The merge handler updates the existing target
actor and deletes the redundant source actor only for collision groups.
Non-colliding source actors remain for the reviewed reparent pass. The handler
must not insert/upsert a destination actor after locking actors, because that can
acquire an activity-group foreign-key lock in the inverse order of a normal
activity append.

Both scan-ledger invariant diagnostics—`ghost_merge_species_ledger_mismatch`
and `user_species_scan_count_underflow`—are retryable HTTP 503
`merge_temporarily_unavailable` responses with the exact guest-data-unchanged
message. The transaction rolls back before either reaches the Edge mapper.

## Pre-deployment status

The pending schema-aware migration implements the manifest, topology preflight,
scan-first transfer, and exact ledger check. The current draft does **not** yet
provide all concurrency/provider-repair guarantees above. Do not deploy or
enable the existing-account conflict fallback until a new forward migration,
the Edge error mapping, full pgTAP replay, and staging concurrency probes clear
the release hold in the
[deployment runbook](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).

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

That worker repairs only the obsolete anonymous Auth shell. RevenueCat provider
state is repaired independently through
`internal.revenuecat_reconciliation_queue`; a successful Auth cleanup does not
prove that the destination provider queue exists or has reconciled.

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

1. Clear every release hold and evidence gate in the deployment runbook.
2. Ship the proof-capable iOS client (or place the OAuth-conflict path behind a
   minimum-version gate).
3. Deploy the reviewed Edge Function with the expanded mapper; deploy the Auth
   cleanup worker from the same SHA.
4. Apply every pending merge migration immediately afterward in the same change
   window.
5. Enable the conflict fallback only for proof-capable clients and retire the
   old version according to the release policy.

A new client against the old endpoint fails `prepare` before it switches away
from its guest session. An old client against the new endpoint is rejected
because it cannot prove source consent, so it must be upgrade-gated to avoid
stranding guest data.

## Verification

```bash
bash services/supabase/scripts/require_supabase_cli_version.sh
make validate-supabase-migrations

deno check --config services/supabase/functions/merge-ghost-profile/deno.json \
  services/supabase/functions/merge-ghost-profile/index.ts
deno test --config services/supabase/functions/merge-ghost-profile/deno.json \
  services/supabase/functions/_tests/mergeGhostProfile.test.ts
deno test \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/worker_test.ts
supabase --workdir services db reset
make test-supabase-privileged-routines
```

Supabase CLI `2.109.1` is exact-pinned. Static migration tests or a focused SQL
file do not substitute for clean replay plus every checked-in catalog test.
