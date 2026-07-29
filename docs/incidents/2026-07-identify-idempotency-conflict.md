# July 2026 Identify Idempotency Conflict

**Status (2026-07-28):** Root cause confirmed and corrected in the repository.
The database migration, five affected Edge Function deployments (the four scan
producers plus `check-scan-status`), and matching iOS recovery behavior still
require exact-SHA production promotion and authenticated smoke evidence.

## Summary

New and queued scans could reach `/identify-multimodal` twice with the same
`client_scan_id`. This is expected after a transient transport failure and can
also occur when the foreground and durable queue paths converge on the same
scan. The AI quota ledger correctly prevented a second paid provider call, but
the duplicate request received HTTP `409 ai_request_already_completed` or
`409 ai_request_in_progress` instead of the first invocation's successful scan
response.

iOS classified that handler-owned conflict as a generic network failure and
showed **Network timeout**. The durable queue retained the scan, but its later
status or URLSession recovery could not replace the visible error after the live
attempt cleared `activeScanId`. The customer therefore saw an incomplete local
scan. Explore sharing and Field Chat were unavailable because both require the
completed local result and authenticated `public.scans` owner row.

This was not caused by scan age and does not require rescanning older
observations.

## Evidence

- Production returned `POST 409` from the existing
  `/functions/v1/identify-multimodal` route on 2026-07-28.
- The route was present and executing; this was distinct from the earlier
  platform `404 NOT_FOUND` deployment-router incident.
- Every Capture submission generated a new UUID. The same UUID was reused only
  by that scan's foreground request, idempotency header, queued record, status
  polling, and background recovery.
- The 409 codes are emitted by Merian's AI-quota or scan-ingestion duplicate
  guards. They are not listed among Supabase's platform Edge gateway status
  codes.

The retained incident record excludes user IDs, scan IDs, coordinates, media
keys, IP addresses, and request bodies.

## Root Cause and Regression Window

Commit `161025c9f` introduced the authoritative server AI-quota reservation on
2026-07-23. Before that change, a repeated request could reach the existing
duplicate-safe scan insert and receive another successful response. After the
change, `reserveAIProviderCall` intentionally rejected a replay of a committed
or still-owned request before scan completion was checked.

The active route reserved quota before `beginScanIngestion` and treated an
already-complete ingestion job as `409 scan_already_finalized`. The combination
converted normal at-least-once HTTP delivery into a terminal-looking client
failure. The quota protection itself was correct; the missing behavior was
idempotent response replay.

A second client race made recovery invisible. The live task retired its
presentation generation before the background queue downloaded or synchronized
the completed row. Recovery then required `engine.activeScanId == scanId`, but
the retiring task's defer had already cleared that value.

## Repository Remediation

### Server response coalescing

All four scan-producing functions—`identify-multimodal`, `identify`,
`identify-describe`, and `audio-spec`—now:

1. validate one canonical UUID from `client_scan_id`/`Idempotency-Key`;
2. look for an owner-scoped stored completion or exact reconstructible durable
   owner row before resolving staging media or reserving AI;
3. wait up to 70 seconds for the invocation that owns an in-progress or
   committed quota reservation to create that durable response surface inside
   the client's 90-second request bound;
4. return the validated Identify envelope with HTTP `200` and
   `X-Merian-Idempotent-Replay: stored|reconstructed`; and
5. never dispatch a second provider request for a durable/concurrent replay.

Migration `20260728220000_persist_idempotent_scan_responses.sql` adds the
bounded canonical `response_envelope` to `scan_ingestion_jobs` and stores it
through the service-only
`complete_scan_ingestion_finalization_with_response(...)` transaction. Existing
completed ingestion jobs are supported by contract-validated reconstruction from
the exact owner scan and species rows. The same reconstruction is safe for an
exact post-insert owner row whose canonical ledger is still processing,
finalizing, retrying, or `failed_retryable`; the marked replay is immediately
usable while reconciliation finishes through the canonical finalizer, without
another provider call.

The stored response is immutable for a completed generation, contains no raw
media bytes, and is cleared immediately when owner deletion is requested, when
the scan is deleted, or when ownership changes.

The response-aware finalization routine remains service-only at both boundaries:
its body calls `internal.require_service_role()`, its ACL revokes `PUBLIC`,
`anon`, and `authenticated`, and its exact service-role signature is recorded in
`internal.privileged_routine_grants` as
`public.complete_scan_ingestion_finalization_with_response(uuid,uuid,jsonb,jsonb,text[])`.
Workflow run 1547 caught the initially missing catalog registration before
production `db push`; no migration or function from that failed run was
promoted.

### iOS recovery handoff

`InferenceEngine` recognizes only the four exact handler-owned 409 codes as
ambiguous accepted-work outcomes. It retains the exact failed presentation scan
ID after the live generation retires. A matching background response or
status-synchronized `LocalScanRecord` may replace **Restoring scan** only when:

- the retained presentation ID matches;
- the recovered response/record carries the same scan ID; and
- no newer scan owns the presentation.

Starting another scan, loading a library record, or canceling the presentation
clears that recovery fence. Generic or malformed 409 responses cannot use it.

Customer copy now says:

> Your scan reached Naturebook safely. We’re restoring its saved result now, and
> it will appear here or in Scans automatically.

### Durable queued-retry wake

Follow-up QA found a separate client durability gap: `queueNextRetryAt` was
persisted and displayed, but after a future date was filtered out of a
foreground/reconnect drain there was no general timer guaranteed to wake at that
date. The per-flow delayed task could be cancelled by connectivity loss and
could not survive termination. The queued sheet also rounded away seconds and
held a value snapshot, so reaching the displayed minute did not prove an attempt
had begun.

`OfflineJobScheduler` now reconstructs one actual token-fenced wake from the
earliest active scan/job deadline after every retry write, reconnect, foreground
activation, and queued-sheet presentation. Needs-attention rows are excluded,
stale dates use a bounded one-second wake, and the atomic inference claim clears
both persisted deadlines. The queued sheet refreshes once per second, shows a
relative countdown/starting/offline state, and allows immediate retry during
backoff. This repair applies to retained old and new queue rows; it does not
require another scan.

## Deployment and Verification

Deploy the migration before the affected functions. The normal path-filtered
Supabase workflow discovers the new shared dependencies and selects
`audio-spec`, `check-scan-status`, `identify`, `identify-describe`, and
`identify-multimodal`; its graph-derived fleet probe must still reach every
configured production Edge route.

Do not close this incident until one exact production SHA proves:

1. a new still scan returns `200`, status is immediately `found`, Field Chat
   opens, and Explore sharing succeeds;
2. an eligible older scan also opens Field Chat and shares without rescanning;
3. a synthetic lost-response retry with the same UUID returns `200`, carries the
   replay header, returns the same `scan_id`, and creates only one AI provider
   reservation and one scan row;
4. a faulted post-row finalizer returns `503` to the fresh multimodal request,
   then a same-UUID retry reconstructs the marked response without provider
   redispatch while canonical repair remains eligible;
5. a concurrent duplicate waits for the winner rather than returning 409;
6. cross-owner UUID probes reveal no response or row;
7. deletion request immediately clears the persisted response;
8. the matching iOS build restores the exact still-presented queued scan without
   overwriting a newer presentation; and
9. a persisted future queued retry visibly counts down, transitions through an
   atomic claim at eligibility, and is reconstructed after force-quit,
   foreground, and offline/reconnect without duplicate inference.

Follow
[Scan Owner-Row Durability and Recovery Rollout](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout)
for the complete release unit and rollback constraints. The normative joined
behavior is
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
