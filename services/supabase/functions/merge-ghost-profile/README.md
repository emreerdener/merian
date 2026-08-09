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
  species ledger, then verifies exact ledger counts against scans for both
  users;
- coalesces conflict-prone Community Identify actors and normalizes RevenueCat
  event, watermark, and reconciliation state before their references move;
- adds non-blocking `NOT VALID` Auth foreign keys to pre-profile ingestion
  ledgers, so new writes serialize with a merge while historical orphan cleanup
  remains an independent rollout;
- reparents append-only AI usage explicitly under transaction-local
  source/target authorization; this ledger intentionally does not receive an
  Auth FK because normal account deletion has a separate guarded account-linkage
  clearing path;
- reparents and deduplicates complimentary-usage rows by original analysis,
  preserves historical consumption, releases excess held rows deterministically,
  and derives the merged balance from one lifetime grant of three rather than
  combining the source and destination grants;
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

The normative merged-entitlement rules are documented in
[Three Complimentary Pro Scans](../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Concurrency and provider-repair contract

Parent identities are locked before merge-sensitive child state. In particular,
both the merge and `public.apply_revenuecat_reconciliation(...)` must lock
`public.users` before `internal.revenuecat_reconciliation_queue`. Reconciliation
must then lock and revalidate its claim before changing entitlement or watermark
state. Claim expiry uses the wall clock both under the queue lock and in the
completion write; transaction-start time is not a valid final lease fence. If
completion resets or replaces the lease first, the stale callback fails closed
instead of applying an obsolete provider snapshot.

Completion must unconditionally upsert a destination reconciliation row. The row
uses the permanent uppercase UUID as `lookup_app_user_id`, is due immediately, resets
`attempt_count`, clears all claim/error fields, and exists whether or not the
anonymous source had a queue row. The foreground RevenueCat `logIn` call and
webhook delivery are accelerators; this destination queue is the durable repair
authority for a completely missed webhook.

Community activity actors use the writer-compatible activity-group-before-actor
order. The merge handler updates the existing target actor and deletes the
redundant source actor only for collision groups. Non-colliding source actors
remain for the reviewed reparent pass. The handler must not insert/upsert a
destination actor after locking actors, because that can acquire an
activity-group foreign-key lock in the inverse order of a normal activity
append.

Both scan-ledger invariant diagnostics—`ghost_merge_species_ledger_mismatch` and
`user_species_scan_count_underflow`—are retryable HTTP 503
`merge_temporarily_unavailable` responses with the exact guest-data-unchanged
message. The transaction rolls back before either reaches the Edge mapper.

## Pre-deployment status

Forward migration
`20260801220318_harden_ghost_merge_concurrency_and_provider_repair.sql` and the
Edge mapper implement the four concurrency/provider-repair requirements above
without editing committed migration history. Static and Edge tests cover their
source contracts, and `ghostProfileMergeConcurrencyDb.test.ts` provides the two
session deadlock schedules. `ghostProfileMergeClientContract.test.ts` pins proof
persistence before the session switch, retry on permanent-session restoration,
device-only Keychain storage, and terminal-only deletion. Do not deploy or
enable the existing-account conflict fallback until the production workflow's
exact-CLI disposable replay, complete catalog and Edge suites, two-session
schedules, strict lint, and advisors clear the release hold in the
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

The scheduled **Ghost Profile Merge Health Monitor** and the production
post-deploy audit call
`services/supabase/scripts/monitor_ghost_profile_merges.ts` through one
short-lived, read-only owner connection. They publish aggregate 12-hour receipt
counts, overdue Auth-cleanup counts/ages, and 24-hour missing, misdirected, or
unrefreshed destination RevenueCat queue anomalies without emitting handoff/user
IDs, proof hashes, or provider subjects. Migration
`20260802025258_index_ghost_merge_health_audits.sql` supplies predicate-matched
time indexes for both rolling windows. A prepared receipt is a prompt to confirm
Edge telemetry and proof-capable Keychain retries; it is not permission to edit
a receipt or manually reparent data. See the deployment runbook for thresholds
and recovery.

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

The database mapper reparents only rows already synchronized to Supabase. The
iOS append-only consent ledger is a separate authority. After confirmed server
completion, the client now transforms the complete local ledger in one verified
write: every ghost-owned adult, Terms, Gemini, and analytics record moves to the
permanent UUID; records synchronized to the ghost become synchronized to the
permanent UUID, while every other synchronization owner is cleared so the record
remains pending. IDs, displayed text, client/server timestamps, policy versions,
platform, and app metadata remain unchanged.

The durable Keychain handoff suppresses analytics before and throughout this
sequence, including after process restart. The client cancels stale ledger sync
work and normalizes any canceled required-consent retry back to reconciliation
under the new generation, pushes pending permanent-account actions, refetches
authoritative state, then performs a final in-merge fence over task
cancellation, observed account, the Supabase SDK's synchronous session, and
synchronization generation before any evidence, persistence, or analytics
change. It removes the handoff only afterward with a throwing,
read-after-write-verified Keychain operation. Any persistence, synchronization,
refetch, cancellation, identity drift, or removal failure retains the handoff
for an idempotent retry. Only server-terminal `handoff_expired` and
`handoff_invalid` responses discard a handoff without rebinding local evidence;
those paths still refetch the permanent account before verified removal.
Analytics can resume only after the durable queue is empty and permanent state
is authoritative. Keychain read/decode uncertainty retains the original bytes
and keeps analytics suppressed instead of treating the queue as absent. This
closes `CONSENT-002` in source; hosted exact-SHA test execution remains required
by the
[production consent readiness record](../../../../docs/legal/production-consent-readiness-2026-08-03.md).

The OAuth session switch itself uses a separate generation-fenced analytics
transition. Capture and the prior consent Realtime channel close before
`signInWithIdToken`; success or failure then reconciles the Supabase SDK's
actual current session. The durable handoff suppression above remains in force
after that transition until server completion, local rebind/synchronization, and
verified queue removal all succeed.

The legacy payload cannot be made backward-compatible: it switches sessions
before calling the server and carries no source-session proof. Treat this as a
coordinated security rollout:

1. Clear every release hold and run **Supabase Candidate Validation** on the
   exact release SHA. Its production-isolated disposable database must pass the
   fresh replay, complete catalog and Edge suites, two-session concurrency
   schedules, strict lint, and advisors. No hosted staging project or manual SHA
   variable is required, and this evidence run does not deploy anything.
2. Ship the proof-capable iOS client (or place the OAuth-conflict path behind a
   minimum-version gate).
3. Deploy the reviewed Edge Function with the expanded mapper; deploy the Auth
   cleanup worker from the same SHA. The production workflow detects any Ghost
   merge migration or Function delta since the last successful release and
   predeploys both Functions before `db push`; manual dispatch and an unsafe
   baseline do the same.
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
SUPABASE_DB_TEST_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  deno test \
  --config services/supabase/functions/deno.json \
  --allow-env=SUPABASE_DB_TEST_URL,PGAPPNAME,PGDATABASE,PGHOST,PGOPTIONS,PGPASSWORD,PGPORT,PGUSER \
  --allow-net=127.0.0.1:54322 \
  services/supabase/functions/_tests/ghostProfileMergeConcurrencyDb.test.ts
deno test \
  --config services/supabase/functions/reconcile-ghost-profile-merges/deno.json \
  services/supabase/functions/reconcile-ghost-profile-merges/worker_test.ts
supabase --workdir services db reset
make test-supabase-privileged-routines
supabase --workdir services db lint --local --schema public,internal \
  --level warning --fail-on warning
supabase --workdir services db advisors --local --type security \
  --level warn --fail-on error
supabase --workdir services db advisors --local --type performance \
  --level warn --fail-on error
```

Database lint warnings block release. Advisor warnings remain visible for the
reviewed historical backlog, while advisor errors block release. Warning-level
advisor blocking requires an explicit baseline so existing debt cannot strand
deploys.

Supabase CLI `2.109.1` is exact-pinned. Static migration tests or a focused SQL
file do not substitute for clean replay plus every checked-in catalog test. A
database-test connection skip is not proof; release validation sets
`SUPABASE_DB_TEST_URL` so a connection failure is fatal.
