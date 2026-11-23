# Reconcile Scan Deletions

Internal, service-role-only worker for durable per-scan erasure.

`delete-scan` first writes an owner-bound row to
`internal.scan_deletion_tombstones`. The fence prevents delayed inference,
replay, recovery, or a stale device from reconstructing that scan UUID before
any external media is touched. This worker independently resumes pending erasure
if the deleting device never retries.

Each invocation:

1. authenticates with an exact timing-safe server API key comparison;
2. leases due jobs with `FOR UPDATE SKIP LOCKED`;
3. loads the canonical fenced media set and accepts only exact
   `public_uploads/{free|pro}/{claimed-owner-uuid}/{safe-filename}` objects;
4. treats R2 `2xx` and `404` deletion responses as success;
5. removes the owner scan row only after all media deletes succeed; and
6. compare-before-releases failures with bounded exponential backoff.

It drains in 25-row waves, processes at most 100 jobs with concurrency four, and
stops claiming near a 40-second runtime deadline. PostgreSQL schedules it every
five minutes. The independent Scan Media Health Monitor also evaluates the
service-only backlog summary, warning at 15 minutes and becoming critical at one
hour, any expired lease, or 100 pending jobs.

Completed UUID fences are retained without the user identifier. They contain no
observation content and are required to make stale recovery permanently
non-resurrecting.

Required runtime secrets are the existing Supabase server credentials and R2
delete credentials. The route accepts no caller-controlled job identity.
Foreign-owner URLs, malformed paths, and non-scan prefixes are skipped and
reported only as aggregate rejection counts; they can never nominate an R2
object for deletion.

## Capture staging obligations

The source implementation also runs one exact-object retirement pass after scan
job reconciliation. It claims at most 25 retired staging keys, stops starting
objects after 40 seconds, and uses bounded R2 requests. The configured backend
digest and owner namespace must match before DELETE or HEAD. Only HEAD 404
records an absence observation; failed I/O, other statuses, or unknown
acknowledgement remain unresolved. There is no completed/garbage-collection
transition.

`capture_object_retirement` in the response/log contains per-pass counts and an
aggregate `health` snapshot: unresolved, due, leased, error counts and oldest
retired age. These are separate from the existing scan-row completion counts and
`health_status`. An absent object may still be written by an already-issued PUT;
its permanent no-rebind fence and scheduled recheck survive that observation.
Successful absence schedules a recheck after the outstanding capability expiry
and at least one hour; errors retry after five minutes. Leases expire after two
minutes. Backend mismatch remains an unresolved obligation, never a delete
against a different configured bucket.

This is containment for registered staging keys, not complete physical-erasure
qualification. COPY/publication targets, legacy unknown capabilities, and draft
abandonment remain open. No new hosted schedule or deployment was performed.
