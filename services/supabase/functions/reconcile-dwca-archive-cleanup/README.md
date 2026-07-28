# DwC-A Archive Cleanup Reconciler

`reconcile-dwca-archive-cleanup` is the service-only deletion worker for private
DwC-A archives. Database cron wakes it every five minutes. It requires one exact
platform-managed server credential and never accepts a caller-supplied job,
object key, cursor, or lease.

Each invocation deadline-drains up to 100 oldest-due outbox rows in 25-row claim
waves with four concurrent deletes. Claims carry a UUID fencing token and a
two-minute lease. R2 `404` is idempotent success; other storage failures release
the row with database-calculated backoff. Expired leases are repaired by the
next claim.

Cleanup can be enqueued by:

- source/privacy revocation;
- grant expiry or explicit revocation;
- terminal export failure;
- a failed archive-staging/completion fence;
- export-job deletion; and
- migration of legacy completed jobs that exposed direct storage signatures.

Successful deletion marks the grant cleaned and purges the retained immutable
source DTOs. Storage outages therefore delay physical deletion without restoring
download authority.

Every invocation reads `get_dwca_archive_cleanup_health()` and emits a bounded
aggregate event. Warning thresholds are 25 pending rows or 15 minutes oldest-due
age; critical thresholds are 100 pending rows, one hour oldest-due age, or any
expired lease. The event contains no user, token, object-key, or raw provider
detail. The independently scheduled
`.github/workflows/dwca-export-health-monitor.yml` reads the same health RPC
even if this worker never starts, so absent cron/Vault configuration is
observable. Operators should repair cron/Vault/R2 configuration and let
claim-fenced retries resume; never edit leases or delete outbox rows manually.
