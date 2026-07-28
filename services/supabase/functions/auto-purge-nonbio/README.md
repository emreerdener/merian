# Auto Purge Non-Bio

`auto-purge-nonbio` is the service-only daily retention selector for cloud
captures whose canonical database row is non-biological and more than 30 days
old. It does not delete R2 objects or scan rows in its HTTP invocation.

## Durable deletion flow

1. The route accepts only `POST` and applies the shared exact server-key
   authorization policy.
2. It calls `public.request_nonbiological_scan_retention_deletions(integer)` in
   bounded batches until the queue is drained, the 10,000-request cap is
   reached, or its 40-second runtime budget expires.
3. The database routine discovers candidates oldest first, then acquires the
   canonical per-scan generation locks in UUID order. It rechecks the age,
   biological classification, `is_tombstoned = false`, non-null/non-reserved
   owner, and absence of an existing generation tombstone under the scan row
   lock.
4. Each accepted generation receives a permanent private deletion tombstone. Any
   incomplete ingestion ledger is made terminal before the transaction commits.
5. `reconcile-scan-deletions` independently leases the work, reloads the fenced
   canonical row, deletes only media in the exact owner's
   `public_uploads/{free|pro}/{owner}/...` namespace, and removes the database
   row only after media erasure succeeds.

Separating selection from external deletion closes the legacy ABA window in
which a service finalizer could append a new media URL after the purge route
captured its URL list but before the route deleted the scan row. Interrupted R2
or database work is retryable, and the permanent tombstone prevents delayed
inference or replay from reconstructing the deleted generation.

## Response

```json
{
  "success": true,
  "requested_count": 42,
  "runtime_deadline_reached": false
}
```

`requested_count` counts newly fenced generations, not completed R2 deletions.
Operational completion and SLA status are reported by
`get_scan_deletion_health()` and the independent scan-media health monitor.

The selector RPC has an empty fixed `search_path`, authorizes the effective
service role internally, and is executable only by `service_role`. `PUBLIC`,
`anon`, and `authenticated` remain revoked. Failure responses use the shared
stable public-error envelope and request ID; logs contain only the processing
step, exception class, aggregate requested count, and deadline flag—never scan
IDs, owner IDs, or media URLs.
