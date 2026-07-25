# Safe Account Deletion

Executes the irreversible right-to-erasure protocol for the user established by
the verified request session. The caller cannot nominate another user ID.

## Durable state machine

Migration `20260725030308_durable_account_deletion.sql` replaces the former
Auth-first sequence with a private `internal.account_deletion_jobs` state
machine:

1. `request_account_deletion(user_id)` inserts or returns the active `pending`
   job. This durable receipt is always the first mutation.
2. `claim_account_deletion_jobs(...)` assigns a five-minute UUID lease using
   `FOR UPDATE SKIP LOCKED`.
3. Every claimed attempt, including an `auth_pending` retry, calls
   `complete_account_deletion_cleanup(job_id, claim_token)`. It writes the
   idempotent `pending_storage_deletions` outbox row, calls
   `apply_user_tombstone`, verifies that no public profile or scan still
   references the user, and advances or preserves `auth_pending` in the same
   transaction.
4. Only an `auth_pending` claim may call `supabaseAdmin.auth.admin.deleteUser`.
   HTTP `404` and exact Auth code `user_not_found` are idempotent success.
5. `finish_account_deletion_attempt(...)` either records `completed` and erases
   the terminal job's direct user UUID, or releases the lease with bounded
   database-calculated backoff.

The initiating request tries one claimed job synchronously. It returns `200`
when deletion completes immediately or `202` after durable acceptance when a
retry is required or another worker owns the lease. Both are successful
responses; the iOS client signs out locally and purges its local store. A
failure before the intake receipt returns `500` and performs no destructive
work.

The scheduled `reconcile-account-deletions` function resumes due jobs every five
minutes. A crashed worker cannot clear or finish another worker's claim, and a
lost success response is safe: the reaper sees either a completed row or an
`auth_pending` job whose already-deleted Auth identity resolves as idempotent
success.

An internal `BEFORE INSERT` trigger rejects recreation of `public.users` while a
deletion job is active. This prevents Auth metadata synchronization or a trusted
backend upsert from resurrecting a profile between verified cleanup and the
external Auth deletion.

## Authorization and data minimization

All four state-machine RPCs and `apply_user_tombstone(uuid)` are public-schema
discovery names, not client-callable APIs. Execution is revoked from `PUBLIC`,
`anon`, and `authenticated`; only the reviewed `service_role` allowlist can
execute them, and every routine calls `internal.require_service_role()`. The
private job table has RLS enabled and no direct API-role privileges.

Do not accept a target UUID from either HTTP body. `/safe-delete` derives it
only from the verified session; the service reaper claims targets only from the
database. Active jobs retain the UUID only while work remains. Completion sets
the job's `user_id` to `NULL`; the storage-cleanup outbox retains the identifier
only for its separate cleanup lifecycle.

## Operations

Alert on:

- `account_deletion_attempt_deferred`
- `account_deletion_reconciliation_deferred`
- repeated active jobs whose `attempt_count` is increasing or whose
  `next_attempt_at` is overdue

Do not manually delete an Auth user to recover a pending job. Repair the
underlying cleanup failure and invoke the service reaper. For a legacy
Auth-first incident that predates this migration, an operator may create a
durable job for the recorded UUID through the service-only intake RPC, then run
the reaper. Review the target and current relational state before doing so.

## Source layout

- `index.ts` owns verified-session and POST-only routing.
- `handler.ts` persists intake and maps immediate versus queued success.
- `worker.ts` owns cleanup-before-Auth ordering, retries, and claim recovery.
- `db.ts` owns the four RPC wrappers and idempotent Auth Admin deletion.
- `reconcile-account-deletions/` is the scheduled service-only reaper.

Focused source, migration-contract, and pgTAP tests live in
`functions/_tests/safeDelete.test.ts`,
`functions/_tests/accountDeletionCoverage.test.ts`,
`functions/_tests/accountDeletionMigrationContract.test.ts`, and
`tests/account_deletion_security.sql`.
