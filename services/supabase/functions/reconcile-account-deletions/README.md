# Account Deletion Reconciler

Service-only worker for durable account deletion. Account-owned data and stored
media are erased, while each submitted observation remains in `public.scans` as
mandatory ownerless Scientific Data under the
[canonical retention contract](../../../../docs/backend-and-data/17-scientific-observation-retention.md).
The `reconcile_account_deletions_every_five_minutes` database cron invokes this
route with a platform-managed current or legacy server credential. Opaque keys
use `apikey` only; legacy JWT keys use both supported headers.

Each invocation leases at most 100 due jobs through
`claim_account_deletion_jobs`. For every `pending` or `auth_pending` claim, the
worker first calls `complete_account_deletion_cleanup`, which idempotently and
atomically:

1. inserts the idempotent storage-cleanup outbox row;
2. detaches retained scans, clears their account-owned fields, and removes the
   public profile without changing exact coordinates or other scientific facts;
   and
3. verifies that no scan or public profile still references the user.

Only a job advanced to `auth_pending` can reach `auth.admin.deleteUser`. An Auth
`404` or `user_not_found` is idempotent success. Every other failure is reduced
to a bounded code, the lease is released with database-calculated backoff, and a
later invocation resumes it. If an invocation dies, the five-minute lease
expires and another worker can claim the job.

The cleanup is deliberately repeated on Auth retries, and a database trigger
rejects public-profile recreation while the job is active. Together these close
the interval between relational cleanup and the external Auth operation.

The endpoint accepts only `POST`, uses bounded JSON parsing, and timing-safely
matches one exact current or legacy server key through the shared request
boundary. Opaque keys are accepted only in `apikey`; legacy JWTs use matching
`apikey` and Bearer headers. It never accepts a user ID in its body.

## Independent health alert

The database cron is not its own health check. Migration
`20260727001630_monitor_account_deletion_health.sql` exposes the aggregate,
service-role-only `get_account_deletion_health()` RPC and supporting partial
indexes. The RPC reports active/due ages, phase/backlog counts, retry-error and
expired-lease counts, orphaned storage work, cron activity, and whether the
reaper URL and service credential are configured. It exposes no UUIDs or raw
errors. Credential health mirrors the reaper's Vault-first, NULL-only fallback:
a blank Vault entry is unhealthy and does not fall through to a legacy app
setting. This boolean checks only that the effective URL and credential are
nonblank; it does not validate their destination, authority, or equality with
the Edge secret.

Migration `20260727013416_future_proof_server_key_boundaries.sql` applies the
shared database `pg_net` transport policy to this cron. An opaque
`sb_secret_...` Vault value is sent only in `apikey`; a legacy service-role JWT
is sent in both `apikey` and Bearer Authorization. This endpoint compares the
received credential with the platform-managed current and legacy server-key
sets. Rotate the Vault value and project key together; never rotate only one
side.

`.github/workflows/account-deletion-health-monitor.yml` runs every five minutes
at a different offset and reads the RPC with a server key resolved through the
Supabase Management API. It neither invokes this reconciler nor depends on the
Vault values this reconciler needs. Therefore a disabled cron or absent Vault
configuration becomes a critical alert instead of silently stopping deletion
progress. The default end-to-end warning/critical thresholds are 27/36 hours to
include the mandatory 25-hour verification delay.

On alert, repair cron/Vault configuration or the failing R2/Auth dependency and
let claim-fenced retries resume. Never mutate queue cursors or leases and never
delete Auth to clear a pending job.
