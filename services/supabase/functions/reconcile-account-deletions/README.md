# Account Deletion Reconciler

Service-only worker for durable account deletion. Account-owned data and stored
media are erased, while each submitted observation remains in `public.scans` as
mandatory ownerless Scientific Data under the
[canonical retention contract](../../../../docs/backend-and-data/17-scientific-observation-retention.md).
The `reconcile_account_deletions_every_five_minutes` database cron invokes this
route with a platform-managed current or legacy server credential. Opaque keys
use `apikey` only; legacy JWT keys use both supported headers.

> **Production evidence pending:** source treats the provider email ID as
> dispatch evidence only, waits without deleting Auth, and resumes only after
> the signed webhook commits a matching `email.delivered` event. See the
> [canonical rollout gate](../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md#rollout-and-production-exit-gate).

Each invocation leases at most 100 due jobs through
`claim_account_deletion_jobs`. For every `pending` or `auth_pending` claim, the
worker first calls `complete_account_deletion_cleanup`, which idempotently and
atomically:

1. inserts the idempotent storage-cleanup outbox row;
2. detaches retained scans, clears their account-owned fields, and removes the
   public profile without changing exact coordinates or other scientific facts;
   and
3. verifies that no scan or public profile still references the user.

Only a job advanced to `auth_pending` can continue. If it has a stored Apple
credential, the worker first reads the Vault token under the active claim, calls
Apple's `/auth/revoke`, and transactionally destroys the token before the
provider substage completes. Provider failure retains the credential and Auth
identity for database-calculated retry. A legacy Apple identity without a
captured token carries a durable manual-fallback disposition. Only a resolved
provider substage with no remaining credential can continue. For that legacy
branch, the worker reads the confirmed Auth email only under the active claim,
sends Apple's official manual-removal instructions through Resend with a durable
attempt tag, records send API acceptance, and releases the claim while retaining
the private restrictive Auth-fence row. A later reaper pass returns
`manual_revocation_delivery_waiting` until the signed webhook confirms delivery.
Delayed events keep waiting; bounced, failed, and suppressed events create a
new-attempt retry state. An Auth `404` or `user_not_found` is idempotent
success. Every other synchronous failure is reduced to a bounded code, the lease
is released with database-calculated backoff, and a later invocation resumes it.
If an invocation dies, the five-minute lease expires and another worker can
claim the job.

`manual_required` is the provider disposition. Delivery progresses through
`pending`, `accepted`/`delivery_delayed`, optional `retry_required`, and
`delivered`; no `completed` delivery state exists. The supporting client's local
notice is defense-in-depth. Only a signature-verified `email.delivered` event
for the current attempt and provider email ID may release the Auth fence.
Production also requires a real Apple private-relay smoke and an
oldest-supported-binary deletion smoke under the canonical Apple deletion
contract.

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

Migration `20260807034322_deliver_legacy_apple_revocation_instructions.sql` adds
identity-free pending, accepted, delayed, retry-required, delivered, and
historically unverifiable manual-delivery counts. Delayed and retry-required
states warn. Any unverifiable count is critical and cannot be cleared by editing
a job; preserve it for release-owner and counsel review.

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

On alert, repair cron/Vault configuration or the failing
R2/Apple/Resend/private-relay/Auth dependency and let claim-fenced retries
resume. Never mutate queue cursors or leases and never delete Auth, copy an
Apple token, or forge provider completion, send acceptance, or delivery to clear
a pending job. Provider and delivery failures remain part of the existing
`auth_pending` and retry-error aggregates; webhook failures are also visible in
Edge logs without recipient data.

See the
[canonical Sign in with Apple deletion contract](../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md)
for the provider state machine, secrets, legacy fallback, and rollout gate.
