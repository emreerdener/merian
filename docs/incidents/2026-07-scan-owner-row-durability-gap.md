# July 2026 Scan Owner-Row Durability Gap

**Status (2026-07-27):** Corrected and reviewed in the repository. Production
remediation is still pending deployment of three Edge Functions and the
matching iOS build, followed by runtime verification.

## Summary

iOS could receive `200 OK` from `/identify-multimodal`, save the returned
observation locally, and then find no authenticated owner row in
`public.scans`. Explore sharing returned `Scan not found`, and Insight Field
Chat was unavailable because both features require that same row.

A brand-new July 27 scan reproduced the sequence: staging upload succeeded,
identify returned `200`, the local scan saved, and immediate status/share calls
could not find the cloud row. This rules out the theory that only scans created
before recent backend work were affected. Scan age was not the cause.

The first customer screenshot exposed
`service_role authorization required`. That separate server-key/database-guard
incident can also block Explore publication, but it does not explain a new
identify success followed by a missing scan row. Its remediation and production
verification remain tracked in
[July 2026 Server-Key Authorization Mismatch](./2026-07-server-key-authorization-mismatch.md).

## Impact and Scope

- Affected observations appeared complete in the private iOS library but could
  not be shared to Explore.
- Insight Field Chat failed for the same records, confirming a shared
  owner-row dependency rather than an Explore-only UI problem.
- Ask the Community and other owner actions could encounter the same
  local/cloud drift.
- Retrying with a newly captured scan did not guarantee success.
- The technical backend error text was exposed in a customer-facing toast.

No evidence indicates that the AI result itself, the local SwiftData write, or
the staging upload was the missing dependency. The absent durable
`public.scans` row was the common boundary.

## Evidence and Root Cause

### Confirmed from runtime evidence

1. Owner-scoped staging upload returned success.
2. `/identify-multimodal` returned `200` after provider work.
3. iOS persisted the result locally.
4. `/check-scan-status` reported the row absent.
5. `/share-scan-to-explore` returned a missing-scan response.
6. Field Chat was unavailable for the same observation.

The attached logs contained user, network, and observation identifiers. This
incident record intentionally retains only the request sequence and outcome,
not those values.

### Code-level root cause

The active route scheduled moderation, media promotion, primary species
resolution, and `insertScan` through its background execution helper after
constructing the AI response. HTTP success therefore meant “AI response
created,” not “owner row durably available.” A background task can fail or
outlive the useful request interval, while iOS correctly interpreted `200` as
completion and removed the successful scan from its retry path.

Two related correctness gaps amplified the failure:

- duplicate-safe insertion did not read the row back by both scan and owner, so
  a no-op conflict or cross-owner UUID collision could look successful; and
- downstream recovery attempts had no single server-owned contract for
  distinguishing active/retryable ingestion, terminal policy rejection, and
  eligible legacy drift.

This was a false-success API contract, not a requirement to rescan old
observations and not a reason to grant iOS direct table-write authority.

## Repository Remediation

### Durable identify success

`/identify-multimodal` now awaits all work required to make the returned
`scan_id` usable:

1. moderation and abuse-strike persistence;
2. required image, playback-video, and standalone-audio promotion;
3. primary species resolution and dictionary materialization;
4. duplicate-safe `public.scans` creation; and
5. owner-scoped read-back by both `id` and authenticated `user_id`.

Only analytics, group tags, and candidate enrichment remain behind
`EdgeRuntime.waitUntil`.

Operational moderation, promotion, species-resolution, insertion, or read-back
failure returns:

```json
{
  "code": "scan_persistence_failed",
  "error": "We couldn’t finish saving this observation. Please try again."
}
```

The status is `503` with `Retry-After: 5`. iOS must not save that response as a
successful observation. Terminal moderation rejection returns generic
`400 observation_rejected` and also creates no successful local scan.

### Compatibility owner-row recovery

`_shared/scanRecovery.ts` defines one bounded non-media `recovery_scan`
contract. The server derives the canonical owner from the JWT, validates UUIDs,
ranges, enums, text limits, and privacy projection, rejects direct media URLs,
and uses a duplicate-safe write followed by owner reload.

Recovery is allowed only for:

- a legacy scan with no ingestion ledger row;
- a `complete` job whose scan row is unexpectedly absent; or
- a non-policy operational `failed_terminal` job.

Recovery is refused while ingestion is processing, finalizing, retrying, or
`failed_retryable`. It is also refused for exact known terminal moderation,
`SAFETY`, and `PROHIBITED_CONTENT` signals. Exact sentinels are used so an
unrelated operational message containing words such as “rejected” cannot
accidentally become an irreversible policy decision.

The feature paths are deliberately different:

- single `/check-scan-status` can repair non-media owner state; bulk status is
  read-only;
- `/share-scan-to-explore` can combine owner-row recovery with validated
  owner-staged image, video, and audio restoration;
- Ask the Community repairs through status first, then uses its existing
  staged-image restoration; and
- Insight Field Chat repairs non-media state during toolbar preflight.

No path accepts caller-selected ownership, overwrites an existing row, restores
media from direct URLs, or upserts `public.scans` directly from iOS.

### Customer-facing feedback

Known technical failures are translated at the UI boundary:

- service-key/backend availability:
  `Explore is temporarily unavailable. Please try again in a few minutes.`
- missing owner row:
  `This observation is still syncing. Please wait a moment and try sharing again.`
- Field Chat preflight:
  `This observation is still syncing. Please try Field chat again in a moment.`

A transient still-syncing Field Chat result no longer marks the action
permanently unavailable; the customer can retry after the server state changes.

## Review and Validation Evidence

The repository correction received a second contract review covering owner
read-back, non-video moderation rejection, exact policy classification,
server-side recovery guards, and retryable Field Chat state. The review found
and corrected each of those edge cases before handoff.

Completed local evidence:

- complete Edge tooling suite: `1185 passed`, `0 failed`;
- focused identify/recovery suite: `60 passed`, `0 failed`;
- migration contracts: `137 passed`, `0 failed`;
- generated DTO contract tests: `16 passed` and `10 passed`;
- Deno format, lint, and type-check gates;
- Swift source parse for all changed Swift files;
- production SwiftLint with zero findings;
- `make validate-ios-project`; and
- `git diff --check`.

Two environment-limited checks remain missing:

- full Xcode compilation could not enter source compilation because nested
  SwiftPM sandboxing failed with
  `sandbox-exec: sandbox_apply: Operation not permitted`; and
- disposable Supabase database integration could not reach the Docker socket
  from the workspace sandbox.

Neither limitation is a passing result. CI and disposable database evidence
remain required before production promotion.

## Timeline

| Date | Event |
| --- | --- |
| 2026-07-27 | Explore share screenshot exposed a technical `service_role authorization required` toast. Customer-facing translation and the separate key-boundary review began. |
| 2026-07-27 | Logs from older observations showed identify/local-save followed by status/share failure. The initial compatibility recovery path was implemented. |
| 2026-07-27 | A brand-new scan reproduced the same sequence, ruling out scan age and exposing the active false-success durability contract. |
| 2026-07-27 | Field Chat was confirmed unavailable for the same scans, identifying the missing owner row as the shared dependency. |
| 2026-07-27 | Durable identify success, guarded server recovery, staged-media repair, retryable Field Chat behavior, customer-facing toasts, tests, and documentation were corrected in the repository. Production deployment remains pending. |

## Required Production Verification

Follow
[Scan Owner-Row Durability and Recovery Rollout](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout).
Do not mark this incident resolved until:

1. production deployment records tie the deployed versions of
   `identify-multimodal`, `check-scan-status`, and
   `share-scan-to-explore` to the reviewed exact SHA;
2. the matching iOS build reaches the intended release cohort;
3. a new identify `200` is followed immediately by owner status `found`, Field
   Chat opens, and Explore publication succeeds;
4. operational failure returns retryable `503`, policy rejection returns
   terminal `400`, and neither creates a successful phantom local scan;
5. legacy recovery, active/retryable deferral, policy blocking, cross-owner
   isolation, and owner-staged media restoration pass in staging/production
   smoke as applicable; and
6. the observation window contains no identify-success/missing-owner-row pairs
   or fresh-scan dependence on compatibility recovery.
