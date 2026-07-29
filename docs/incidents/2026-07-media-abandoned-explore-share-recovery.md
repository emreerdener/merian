# Media-Abandoned Legacy Explore Share Recovery

**Date:** 2026-07-29\
**Severity:** Critical compatibility failure\
**Affected flow:** Existing local scan → Explore composer → cloud owner repair →
local media restoration → publication\
**Repository status:** Remediated\
**Production status:** Open until the ordered database/Edge/iOS rollout and
legacy-record smoke test satisfy the closure gates below

## Summary

TestFlight app `1.0.2 (235)` produced the retained trace. A new scan completed
`/identify-multimodal` and successfully published to Explore, while an older
scan in the same account and app session failed. The older record was healthy
in local SwiftData but had no `public.scans` owner row. Its server ingestion
ledger reported:

```text
job_status = failed
job_stage = media_reconciliation_abandoned
```

iOS correctly classified the absent row as a candidate for guarded local
recovery. Recovery then failed before the first media PUT:

```text
Explore share missing cloud scan; attempting local scan recovery
Scan persistence unavailable ... media_reconciliation_abandoned
generate-upload-urls → 503 service_unavailable
```

The primary Explore publication path was healthy. The defect was a
legacy-record compatibility rule that made this explicit terminal state
impossible to repair.

## Customer Impact

- Newly analyzed observations could share normally.
- An existing observation with surviving local result/media but an abandoned
  server staging generation could never share, Ask the Community, or become a
  Field Chat subject.
- Retry showed a temporary-service error even though no transient service
  outage caused the rejection.
- Recapture appeared to be the only workaround, violating the app’s
  zero-data-loss and offline-first contract.

Identifiers from the retained device trace are intentionally omitted.

## Root Cause

Two fail-closed controls disagreed with the product recovery contract:

1. `recover_missing_owned_scan(...)` allowed a complete-but-missing ledger or
   exact `terminal_reason_code = replay_exhausted`, but rejected
   `media_reconciliation_abandoned`.
2. `createStagedScanMediaAssets(...)` rejected every
   `scan_ingestion_jobs.status = failed_terminal` before checking the exact
   terminal reason or the explicit `scan_share_restore` purpose.
3. Adversarial review found the media worker could overwrite any noncomplete
   job—including an existing policy terminal—with
   `media_reconciliation_abandoned`. The terminal label alone was therefore
   not sufficient provenance for safe repair.

`media_reconciliation_abandoned` is not a moderation or provider-policy
rejection. It is written by the service-side media reconciler after stale
capture-upload objects cannot be promoted or repaired before the abandonment
TTL. The owner’s device can still hold the validated local observation and
original media. Older producers also wrote `failed_scan_ingestions` only after
a provider result had passed its wire contract and post-result scan
finalization failed. The exact owner/scan pairing of that service-only row
distinguishes the reported validated-result drift from a pre-result abandoned
generation. Treating the proven operational media-loss outcome like a content
policy decision permanently disconnected durable local state from the only
guarded repair path.

`supabase-js` returns PostgREST/database write failures in `{ error }`; awaiting
the query does not throw. The multimodal producer now checks that returned
error as well as thrown transport failures and emits
`multimodal/dead_letter_write_failed` when the proof row cannot be persisted.
This improves diagnostics and future recoverability without weakening the
historical proof requirement.

The generated 503 was therefore deterministic. The signer caught its internal
registration rejection and translated it to a generic retryable response.

## Resolution

### Exact terminal-reason allowlist

The service-only atomic owner-row recovery routine now allows:

- a `complete` ingestion ledger whose owner row is absent;
- `failed_terminal / replay_exhausted`; or
- `failed_terminal / media_reconciliation_abandoned` only when the exact
  owner/scan also has the service-written post-result
  `failed_scan_ingestions` row.

Every other active, retryable, policy, deletion, unproven-abandonment, unknown,
missing, or arbitrary terminal state still returns `deferred`.

The new forward migration
`20260729173000_recover_media_abandoned_owned_scans.sql` replaces the routine
without weakening its existing boundary:

- `internal.require_service_role()` is mandatory;
- execution remains revoked from `PUBLIC`, `anon`, and `authenticated`;
- the authenticated Edge layer normalizes a bounded non-media payload and
  derives its owner from the user JWT;
- the transaction takes the same per-scan generation advisory lock as
  ingestion;
- an owner-scoped ingestion job is required and row-locked;
- abandoned-media recovery requires exact owner/scan post-result dead-letter
  provenance, backed by an exact-match `(user_id, scan_id)` index;
- permanent deletion tombstones return `deleted`;
- existing owner rows are never overwritten;
- foreign UUID collisions return `id_collision`; and
- owner-row insert plus `client_recovery_complete` ledger transition commit
  together under the completion fence.

### Compatible restore signing

`scan_share_restore` registration uses the same exact terminal allowlist and
provenance rule. Before returning any URL, it requires:

- authenticated owner, canonical scan UUID, and deterministic
  scan/category filename;
- explicit `scan_share_restore` purpose;
- canonical media kind/role/content type and bounded byte size;
- exact `terminal_reason_code`, not a stage substring or customer-provided
  message;
- exact owner/scan post-result dead-letter proof for media abandonment;
- a fresh unrestricted scan read when the job is complete or safely terminal;
  an existing row must be active and owned, while an absent row may only stage
  for the later guarded reconstruction;
- no moderation-rejected lifecycle row; and
- no mixed ordinary/repair manifest or active staging-budget overflow.

Signing and lifecycle registration grant no publication or scan-write
authority. The share endpoint still reloads the exact owner row, binds every
restored key to its owner/scan/kind/role ledger row, promotes only safe media,
persists URLs with proven-absence rollback semantics, and publishes post/media/
hashtags through the atomic Explore transaction.

### iOS sequencing

New iOS code asks `/check-scan-status` to commit the guarded non-media owner-row
repair before signing surviving local media. This matches Field Chat and Ask
the Community, avoids uploading when database recovery will defer, and lets the
signer validate a completed active owner row.

The Edge signer and inline share repair also retain the older released-client
sequence—stage exact local media first, then attach `recovery_scan` to Share.
This compatibility is necessary to repair the current TestFlight cohort before
the next iOS build reaches testers.

The reconciler now refuses to invoke terminal marking for an already complete
or terminal job. Its database update independently excludes both states. This
prevents delayed media cleanup from erasing moderation/provider-policy
provenance.

## Why This Remains Secure

The allowlist expands one operational recovery reason, not general client scan
creation:

| State                                                     | Recovery |
| --------------------------------------------------------- | -------- |
| `complete` but owner row absent                           | allowed  |
| `failed_terminal / replay_exhausted`                      | allowed  |
| `failed_terminal / media_reconciliation_abandoned` + exact post-result dead letter | allowed  |
| `failed_terminal / media_reconciliation_abandoned` without that proof | deferred |
| processing/finalizing/retrying/`failed_retryable`         | deferred |
| moderation/provider policy rejection                      | deferred |
| legacy unknown or arbitrary terminal reason               | deferred |
| no owner-scoped ledger                                    | deferred |
| deletion tombstone                                        | deleted  |
| foreign existing scan id                                  | collision |

A modified client cannot select the terminal reason, owner, ledger row, or
service-only post-result dead letter. It cannot provide direct media URLs,
bypass the staged-key binding, overwrite an existing scan, resurrect deletion,
or invoke the database routine directly.

## Verification

The repository now locks:

- both recoverable terminal reasons and the media-abandonment provenance proof
  in migration and Edge signing source contracts;
- worker and database defenses that preserve an existing terminal decision;
- policy and legacy-unknown terminal deferral;
- exact repair-purpose gating so ordinary capture staging remains terminal;
- fresh owner/tombstone validation for terminal repair;
- atomic owner-row/ledger completion;
- bounded media registration, restoration ledger binding, and atomic Explore
  publication; and
- iOS owner repair before media upload.

The final PostgreSQL fixture calls the real routine for allowed, unproven, and
rejected terminal states. Deno tests execute terminal signing
insertion/rejection paths and prove the media worker cannot rewrite an existing
terminal decision.

## Ordered Rollout

1. Apply
   `20260729173000_recover_media_abandoned_owned_scans.sql`.
2. Confirm the exact service-only function ACL and catalog fixture.
3. Deploy `generate-upload-urls`, `check-scan-status`, and
   `share-scan-to-explore` from the same reviewed SHA.
4. Run marked production handler probes.
5. Verify the current released/TestFlight client can stage, recover, and share
   one eligible older observation.
6. Promote the matching iOS build that repairs the owner row before upload.

Function-first deployment would let an old schema defer recovery after media
upload. Migration-first keeps that interval fail-closed; no post can publish
until the owner row is reconstructed.

## Required Production Verification

Do not close this incident until:

1. a newly captured scan still completes Identify, status `found`, composer
   media, and Explore publication;
2. an eligible existing `media_reconciliation_abandoned` scan recovers its
   exact owner row, restores surviving local media, and publishes without
   recapture, with the matching service-written post-result dead letter
   confirmed in restricted diagnostics;
3. Field Chat and Ask the Community can use that recovered observation;
4. relaunch or lost responses during signing, upload, owner-row recovery, media
   persistence, and publication resume idempotently;
5. moderation/provider-policy, unproven abandonment, unknown-terminal,
   no-ledger, cross-owner, tombstoned, malformed, and over-budget attempts
   remain blocked, and delayed media reconciliation does not rewrite policy;
6. restored media returns successfully from the canonical public origin; and
7. retained logs contain no generic 503 for an otherwise eligible
   `media_reconciliation_abandoned` repair.
