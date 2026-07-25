# Safe Account Deletion

Executes the irreversible right-to-erasure protocol for the user established by
the verified request session. The caller cannot nominate another user ID.

## Durable state machine

Migration `20260725030308_durable_account_deletion.sql` replaces the former
Auth-first sequence with a private `internal.account_deletion_jobs` state
machine. Migration `20260725052337_enforce_account_storage_erasure.sql` makes
verified R2 erasure a required durable phase:

Migration `20260725035737_repair_tombstone_profile_seed.sql` is an explicit
executable no-op compatibility bridge for production run 1461. Its superseded
public-only sentinel insert could not satisfy production's
`public.users.id → auth.users.id` foreign key. Migration
`20260725041308_ownerless_account_deletion_tombstones.sql` is the forward fix:
retained scans become ownerless tombstones, exact coordinates/elevation and
free-form intervention notes are cleared, and no synthetic Auth or public user
is created. A validated constraint permits a null scan owner only for a
tombstone. The public profile's restrictive Auth foreign key also rejects any
Auth-first delete until cleanup has removed that profile. The scan-ingestion
replay worker treats an ownerless tombstone as terminal and never dispatches
another AI request for it.

1. `request_account_deletion(user_id)` inserts or returns the active `pending`
   job. This durable receipt is always the first mutation.
2. `claim_account_deletion_jobs(...)` assigns a five-minute UUID lease using
   `FOR UPDATE SKIP LOCKED`.
3. Every account claim, including a later `auth_pending` retry, calls
   `complete_account_deletion_cleanup(job_id, claim_token)`. It writes the
   idempotent storage job, calls `apply_user_tombstone`, and verifies that no
   public profile or scan still references the user. Tombstoning clears every
   scan media URL/manifest, exact location, device/location context, custom tag,
   and free-form intervention field before making the retained observation
   ownerless. Until storage is verified the job is `storage_pending`, with no
   account-worker lease.
4. `claim_pending_storage_deletions(...)` leases bounded R2 prefix pages. The
   worker claims at most four rows per Edge invocation, deletes at most 50 keys
   per page with eight deletes in flight, and traverses the user's free/pro
   media, staging, avatar, and export prefixes. The four-page ceiling keeps
   provider timeout waves within the Edge wall-clock budget; later cron runs
   resume remaining rows. Cursor advancement is claim-fenced and monotonic.
5. After the first complete sweep, the outbox waits 25 hours—longer than any
   pre-intake staging PUT signature—then repeats all five prefixes as a
   verification sweep. New upload signatures are denied while deletion is
   active. Only an empty terminal verification may mark storage `completed` and
   transactionally wake the account job as `auth_pending`.
6. Only an `auth_pending` claim with a completed storage receipt may call
   `supabaseAdmin.auth.admin.deleteUser`. HTTP `404` and exact Auth code
   `user_not_found` are idempotent success.
7. `finish_account_deletion_attempt(...)` independently rechecks the completed
   storage receipt, then either records `completed` and erases the terminal
   job's direct user UUID, or releases the lease with bounded
   database-calculated backoff.

The initiating request tries the relational phase synchronously. A new request
normally returns `202` because delayed storage verification is deliberately
asynchronous; `200` is possible only when an already verified idempotent job can
finish immediately. Both are successful responses. The iOS client signs out
locally and purges its local store. A failure before the intake receipt returns
`500` and performs no destructive work.

The scheduled `reconcile-account-deletions` function resumes due account jobs
and storage pages every five minutes. It performs a bounded account pass,
bounded storage pass, then a second account pass only when storage completed in
that invocation. A crashed worker cannot clear or finish another worker's claim,
and a lost success response is safe: the reaper sees either a completed row or
an `auth_pending` job whose already-deleted Auth identity resolves as idempotent
success.

An internal `BEFORE INSERT` trigger rejects recreation of `public.users` while a
deletion job is active. This prevents Auth metadata synchronization or a trusted
backend upsert from resurrecting a profile between verified cleanup and the
external Auth deletion.

## Authorization and data minimization

All account and storage state-machine RPCs plus `apply_user_tombstone(uuid)` are
public-schema discovery names, not client-callable APIs. Execution is revoked
from `PUBLIC`, `anon`, and `authenticated`; only the reviewed `service_role`
allowlist can execute them, and every routine calls
`internal.require_service_role()`. The private job and outbox tables have RLS
enabled and no direct API-role privileges.

Do not accept a target UUID from either HTTP body. `/safe-delete` derives it
only from the verified session; the service reaper claims targets only from the
database. Active jobs retain the UUID only while work remains. Completion sets
the job's `user_id` to `NULL`; the storage-cleanup outbox retains the identifier
only for its separate cleanup lifecycle.

## Operations

Alert on:

- `account_deletion_attempt_deferred`
- `account_deletion_reconciliation_deferred`
- `account_storage_erasure_deferred`
- repeated active jobs whose `attempt_count` is increasing or whose
  `next_attempt_at` is overdue

Do not manually delete an Auth user to recover a pending job. Repair the
underlying cleanup failure and invoke the service reaper. For a legacy
Auth-first incident that predates this migration, an operator may create a
durable job for the recorded UUID through the service-only intake RPC, then run
the reaper. Review the target and current relational state before doing so. Do
not create an all-zero Auth/profile sentinel or weaken the profile foreign key;
ownerless tombstones are the only supported retained-observation state.

## Source layout

- `index.ts` owns verified-session and POST-only routing.
- `handler.ts` persists intake and maps immediate versus queued success.
- `worker.ts` owns cleanup-before-Auth ordering, retries, and claim recovery.
- `db.ts` owns account RPC wrappers and idempotent Auth Admin deletion.
- `storageDb.ts` owns claim-fenced storage-outbox RPC wrappers.
- `storageWorker.ts` owns bounded R2 list/delete/verification processing.
- `reconcile-account-deletions/` is the scheduled service-only account and
  storage reaper.

Focused source, migration-contract, and pgTAP tests live in
`functions/_tests/safeDelete.test.ts`,
`functions/_tests/accountDeletionCoverage.test.ts`,
`functions/_tests/accountDeletionMigrationContract.test.ts`, and
`tests/account_deletion_security.sql`. R2 page and deadline behavior is covered
by `_shared/aws_test.ts` and `safe-delete/storageWorker_test.ts`.
