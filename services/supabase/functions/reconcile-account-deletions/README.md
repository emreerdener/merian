# Account Deletion Reconciler

Service-only worker for durable account erasure. The
`reconcile_account_deletions_every_five_minutes` database cron invokes this
route with the Supabase service-role bearer credential.

Each invocation leases at most 100 due jobs through
`claim_account_deletion_jobs`. For every `pending` or `auth_pending` claim, the
worker first calls `complete_account_deletion_cleanup`, which idempotently and
atomically:

1. inserts the idempotent storage-cleanup outbox row;
2. tombstones retained scans and removes the public profile; and
3. verifies that no scan or public profile still references the user.

Only a job advanced to `auth_pending` can reach `auth.admin.deleteUser`. An Auth
`404` or `user_not_found` is idempotent success. Every other failure is reduced
to a bounded code, the lease is released with database-calculated backoff, and a
later invocation resumes it. If an invocation dies, the five-minute lease
expires and another worker can claim the job.

The cleanup is deliberately repeated on Auth retries, and a database trigger
rejects public-profile recreation while the job is active. Together these close
the interval between relational cleanup and the external Auth operation.

The endpoint accepts only `POST`, uses bounded JSON parsing, and compares the
full `Authorization: Bearer <service-role-key>` value in constant time. It never
accepts a user ID in its body.
