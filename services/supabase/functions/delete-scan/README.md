# Delete Scan

Handles secure single-scan deletion and coordinates cleanup of all associated
durable image, video, standalone-audio, and derived spectrogram-thumbnail media
in Cloudflare R2 (`media.merian.app`).

## Architecture

To enforce clean routing boundaries and prevent IDOR exploits, the logic is
decoupled:

- **`index.ts`**: The HTTP orchestrator. Validates the JSON payload, checks the
  `scanId` constraint, and passes the verified owner UUID to the service-only
  deletion RPC. Only after that transaction commits does it collect source and
  derived media, require every R2 delete to return 2xx/idempotent 404, and call
  the completion RPC that removes the database row.
- **`db.ts`**: Persists the owner-bound deletion request, distinguishes a real
  missing row from a database failure, reads the now-immutable canonical media
  snapshot, and completes deletion through the guarded RPC. Relational or RPC
  failures bubble to the shared public error boundary.

`internal.scan_deletion_tombstones` is the durable generation fence. It is
written before external erasure and retained after completion. Scan
insert/update, inference claim, finalization, replay, and owner-row recovery all
fail closed for a tombstoned UUID. A lost HTTP response is therefore safe: the
iOS `PendingCloudDeletionTask` retries, R2 absence is idempotent, and no stale
device can recreate the observation while deletion is incomplete or after it
finishes. The owner UUID exists only while erasure is pending; successful
completion or account deletion clears that linkage without removing the scan
UUID fence.

The iOS `PendingCloudDeletionTask` provides the immediate retry path, but is not
the sole durability mechanism. `reconcile-scan-deletions` leases and
deadline-drains pending server tombstones every five minutes, with
compare-before-release retry semantics. The independent Scan Media Health
Monitor alerts on expired leases, backlog, and oldest-pending age even when the
database scheduler or Vault dispatch configuration is absent.

The media helper does not rely on a prefix alone. Every candidate must be an
exact HTTPS URL on `media.merian.app` whose key has the flat canonical shape
`public_uploads/{free|pro}/{verified-owner-uuid}/{safe-filename}`. URLs for a
different owner, nested/dot paths, query strings, credentials, fragments,
avatars, staging objects, and malformed names are rejected without logging the
value. This prevents a poisoned database row from turning the service-role
delete path into cross-user object deletion.

Authenticated Data API roles cannot insert/delete scans or update ownership,
media, privacy, or model-result columns. Current iOS releases use the
owner-derived `update_owned_scan_custom_tags` and
`update_owned_scan_identification_review` RPCs. A temporary five-column UPDATE
grant remains solely for already-installed clients and must be removed after the
minimum supported app version contains those RPC call sites.
