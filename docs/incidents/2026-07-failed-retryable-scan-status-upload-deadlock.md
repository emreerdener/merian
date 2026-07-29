# Failed-Retryable Scan Status / Upload Deadlock

**Date:** 2026-07-29\
**Severity:** Release-blocking\
**Affected flow:** Library queued scan → media re-stage → status preflight →
Identify → Insight / Field Chat / Explore\
**Repository status:** Remediated\
**Production status:** Open until the database/Edge rollout, matching iOS
build, and retained-device verification satisfy the closure gates below

## Summary

TestFlight 1.0.2 (235) could accept a scan into the durable offline queue but
never send the Identify request needed to recover it. Opening the scan library
made the failure visible as an endless one-second cycle:

1. `/check-scan-status` returned `not_found`,
   `job_status = failed_retryable`, and
   `job_stage = background_ingestion_failed`.
2. iOS scheduled a retry and forced a fresh media upload.
3. The upload returned HTTP 200 and the queue advanced to `.staged`.
4. The pre-Identify status check saw the same retryable server row and
   classified it as server-owned.
5. iOS skipped `/identify-multimodal`, returned to step 1, and uploaded the
   same retained media again.

The app was not waiting for Gemini. It was preventing itself from sending any
Identify request.

## Customer Impact

- Queued camera scans remained blocked in the library indefinitely.
- Successful R2 uploads consumed network, battery, and device background work
  without advancing analysis.
- Insight never received a result, so the same observation could not support
  Field Chat, field-trip completion, owner sync, or Explore publication.
- Opening the library amplified diagnostics and pipeline wakeups, making the
  app appear continuously active even without user interaction.
- Automatic retry accounting remained at one, so the safety cap could never
  stop the loop.

The supplied session contained two affected observations. Identifiers and the
authenticated account id are intentionally omitted from this document.

## Runtime Evidence

One retained TestFlight trace contained:

| Event                                                                     | Count |
| ------------------------------------------------------------------------- | ----: |
| `/check-scan-status` requests                                             |    64 |
| `/generate-upload-urls` requests                                          |    48 |
| successful background upload dispatches/completions                       | 61/61 |
| one-second `scheduleRetryableServerFailure` schedules                     |    62 |
| “server owns or completed; skipping duplicate inference” decisions        |    61 |
| `/identify`, `/identify-multimodal`, `/identify-describe`, or `audio-spec` |     0 |
| persisted one-second scheduler wakes                                      |   203 |
| library queue refresh diagnostics                                         |   106 |

This is a definitive negative signal: every prerequisite before Identify was
healthy, while no scan-producing request left the device.

## Root Cause

The history audit covered the latest 100 first-parent commits through
`b2c7a241acfe12bcc9f77e853715aa94c9855f17`. This repository had zero merge
commits in that window, so the requested “last 100 merges” review was performed
against its linear first-parent history and each relevant scan-path change.

Commit `fab31d92a5985c7c02669c33cadfcc2b1091e3a8` joined three individually
reasonable recovery changes into a closed state machine:

- retryable server failures could require local media re-staging;
- successful upload completion reset generic retry metadata; and
- every background Identify dispatch consulted status first and treated
  `failed_retryable` as proof that the server still owned the generation.

`scheduleRetryableServerFailure` persisted
`queueLastErrorCode = server_retryable_failure`, incremented the retry attempt,
and returned the scan to `.pending` or `.staged`. When re-staging was required,
`markScanAsStaged` then cleared the marker and reset the attempt count. The next
status preflight therefore could not distinguish:

- the first observation of a retryable server failure, which must schedule a
  bounded local retry; from
- the exact retry after its delay and optional re-upload, which must be allowed
  to reclaim the backend attempt by sending Identify.

The backend status endpoint also runs a narrow service-only reconciliation over
the scanless job and committed quota reservation. That operation makes a new
metered same-UUID retry safe, but the compatibility response intentionally
continues to expose the durable job as `failed_retryable`. The client needed a
durable local latch; repeatedly interpreting the same response as active server
ownership could never make progress.

The first remediation preserved the latch through staging, but trusted only
`OfflineQueuedScan.queueLastErrorCode` and
`OfflineQueuedScan.queueAttemptCount`. The same values were already mirrored on
the scan's `OfflineJobRecord`. A later archived build reproduced the loop on a
migrated V50 store: the queue-row scalar snapshot no longer exposed the marker
while the job row still did. Staging classified the upload as ordinary,
reset both rows, and every later status observation committed “retry 1” again.
Fresh reads also consulted only the scan row, so the surviving job authority
could not stop the loop. The single-row fix was therefore correct for a clean
test store but incomplete for the released migration/context topology.

## Resolution

### Durable retry latch

iOS now gives the exact `server_retryable_failure` code state-machine meaning:

1. the first retryable status observation writes one generation-fenced retry;
2. retry ownership is mirrored on the queued scan and its durable job;
3. fresh marker reads consult both copies, retry accounting uses their
   nonnegative monotonic maximum, and serialized claim/retry/staging transitions
   repair a drifted copy before mutation;
4. the retry marker and attempt count survive a successful required re-upload;
5. transient signer or PUT failures retain that machine latch, record their
   precise error in the append-only event stream, and advance from the maximum
   committed retry count rather than a cached main-context count;
6. a marker that proves the cloud result is complete has higher authority than
   either retry copy and cannot be overwritten by a late retry callback;
7. retry-budget reads use a fresh SwiftData context so background-actor commits
   cannot be hidden by a cached main-context model;
8. after the persisted delay, a `.retryAfter` preflight permits Identify only
   when that exact durable marker exists; and
9. recovered, processing/finalizing, terminal, manual, unrelated, or
   marker-free states still block duplicate provider dispatch.

The stable `client_scan_id` remains the request idempotency key. The Identify
route repeats the same server reconciliation before quota admission, so a
committed failed generation is not refunded and its replacement is independently
metered. Active leases, deletion tombstones, terminal policy outcomes, and
existing owner rows still win.

### Bounded failure behavior

Retryable server status now consumes the normal automatic retry budget.
Exhaustion moves the retained queue row to user-visible needs-attention state,
cancels its server poll, and stops automatic network/log churn. Manual Retry
creates a deliberate new attempt; Cancel/Delete remains available.

### Library diagnostics

The library still performs a lightweight fresh-context refresh while a queued
tile is visible to work around dropped presented-sheet SwiftData notifications.
It now logs only when the visible queue snapshot or local record list actually
changes. Throttled duplicate pipeline kicks are silent. The persisted scheduler,
not the visible library, remains the durable retry authority.

The replay/orphan driver is now process-local single-flight across Library,
scheduler, reconnect, and URLSession completion wakes. A concurrent wake records
at most one trailing pass rather than starting a second queue enumeration,
status probe set, or orphan transition. This preserves newly observed durable
work without the overlapping probes, retry inflation, and start-log storm seen
in the archived physical-device trace.

Late generation-fenced callbacks can also discover that another serialized
owner already committed the same retry, or that cloud completion superseded it.
Those are normal coalescing outcomes and no longer emit “persistence generation
changed” on every library/scheduler wake. A genuinely missing marker and
generation mismatch remains diagnostic.

### Adjacent media-health response drift

The same retained session showed four library refresh failures immediately
after `/get-explore-media-incidents` returned a two-byte empty `[]`. The current
handler contract is `{ "data": [] }`, but an older deployed handler returned
the array directly. This did not cause the status/upload deadlock, but
library-update events repeated the false decode error on the same screen.

iOS now accepts only those two exact response topologies and treats an empty
legacy array as no incidents. Incident entries still pass through the same
typed decoder, while any other malformed success body becomes
`MerianError.invalidResponse`. Rapid queue/library updates also coalesce this
independent read-only refresh without dropping one trailing trigger received
during an in-flight call. The expected account is revalidated before private
incidents enter view state. The backend continues to emit the canonical wrapped
envelope.

## Locked Invariants

- A first `failed_retryable` observation cannot immediately dispatch a second
  provider request.
- An exact scheduled retry cannot be blocked forever by the status preflight
  that created it.
- Re-upload success cannot erase the inference retry latch or retry accounting.
- A transient signer or PUT failure during re-stage cannot erase that latch or
  roll its committed count backward.
- Drift in either redundant SwiftData copy is repaired from the surviving
  marker and monotonic maximum before a queue transition can reset state.
- A generic error string, unrelated retry code, manual state, or stale
  generation cannot authorize Identify.
- A server `found` observation remains stronger than any later unavailable or
  inconsistent status response, wins over retry state in either copy, and never
  returns to provider eligibility.
- Automatic retries are finite and durable across relaunch; local media remains
  until atomic result persistence and queue cleanup commit.

## Verification

Repository regressions cover:

- the pure status-action / durable-marker dispatch matrix;
- fresh-context marker and attempt reads after a background actor commit,
  including a queue-row marker/counter erased while the job-row mirror
  survives;
- the full `.staged → .inferencing → failed retryable → .pending →
  .uploading → .staged` persistence sequence;
- process-local replay reconciliation coalescing across concurrent wake sources
  into one active driver and at most one trailing pass;
- mirror repair, monotonic count preservation, and cloud-complete precedence on
  upload completion and retry retreat; and
- retry-cap transition to retained needs-attention state.

Source parsing and deterministic repository gates are necessary but not
sufficient. The closure test must use the exact Release/TestFlight SHA with
real background `URLSession`, authenticated status, R2 upload, and Identify.

## Required Production Verification

Do not close this incident until all of the following are retained:

1. the reviewed backend migrations and scan functions deploy before the
   matching iOS build;
2. each previously blocked queue row performs at most one required re-stage,
   then emits an `/identify-multimodal` request;
3. Identify returns a validated usable response, owner status becomes `found`,
   the local result commits, and the queue row disappears atomically;
4. relaunch during the delay, upload, Identify, response download, local save,
   and cleanup resumes without duplicate analysis or lost media;
5. a forced repeated retryable failure reaches needs-attention without further
   automatic status/upload traffic;
6. opening and leaving the library open produces no unchanged-state diagnostic
   storm; and
7. the restored observation opens Insight and Field Chat and can publish to
   Explore.
