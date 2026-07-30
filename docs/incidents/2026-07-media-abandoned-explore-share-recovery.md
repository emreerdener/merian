# Media-Abandoned Legacy Explore Share Recovery

**Date:** 2026-07-29\
**Severity:** Critical compatibility failure\
**Affected flow:** Existing local scan → Explore composer → cloud owner repair →
local media restoration → publication\
**Repository status:** Core runtime remediation committed as
`a21155a3299598e81be0ec322ce339adbff62ff1`; the joined presentation-identity,
offline-handoff, response-validation, and bounded-backlog follow-up is committed
on `main` as `cc664a20d6212299966b4579f733e612ed836514`\
**Production status:** Open until the ordered database/Edge/iOS rollout and
legacy-record smoke test satisfy the closure gates below

## Summary

TestFlight app `1.0.2 (235)` produced the retained trace. A new scan completed
`/identify-multimodal` and successfully published to Explore, while an older
scan in the same account and app session failed. The older record was healthy in
local SwiftData but had no `public.scans` owner row. Its server ingestion ledger
reported:

```text
job_status = failed
job_stage = media_reconciliation_abandoned
```

iOS correctly classified the absent row as a candidate for guarded local
recovery. Recovery then failed before the first media PUT:

```text
Explore share missing cloud scan; attempting local scan recovery
Scan persistence unavailable ... media_reconciliation_abandoned
check-scan-status(recovery_scan) → 503 service_unavailable
```

The primary Explore publication path was healthy. The defect was a legacy-record
compatibility/deployment boundary that made this explicit terminal state
impossible to repair. The retained device response proves the failure reached
Merian's recovery handler; it does not expose whether the production database
routine was absent, stale in the Data API schema cache, or rejected internally.
Database logs and the new exact readiness probe are the authority for that
distinction.

The retained device trace was captured at `2026-07-29 12:13:28 -05:00`. Commit
`a21155a32`, which contains the composite-proof migration and hardened recovery
boundary, was created at `2026-07-29 16:24:13 -05:00`. The trace therefore
predates the remediation by about four hours and is valid failure evidence, but
it cannot establish whether the remediated source has since deployed or passed
the legacy-record smoke test.

## Customer Impact

- Newly analyzed observations could share normally.
- An existing observation with surviving local result/media but an abandoned
  server staging generation could never share, Ask the Community, or become a
  Field Chat subject.
- Retry showed a temporary-service error even though no transient service outage
  caused the rejection.
- Recapture appeared to be the only workaround, violating the app’s
  zero-data-loss and offline-first contract.

Identifiers from the retained device trace are intentionally omitted.

## Beta Cohort Disposition

A later `1.0.2 (235)` beta trace found exactly two tested observations that
could not use the cloud-backed actions. Both resolved to the same owner-scoped
terminal ledger state:

```text
job_status = failed
job_stage = media_reconciliation_abandoned
```

The same session reported zero pending, runnable, staged, uploading, polling,
or server-owned offline-queue work. Observations captured before and after this
pair continued to work, including a newer Explore share, and Field Chat
requests for working observations completed normally. One of the two stranded
observations was then deleted successfully through `/delete-scan`; the visible
library count fell by one and Edge confirmed deletion.

This is consistent with a bounded historical ingestion cohort, not corruption
of the SwiftData store or a currently looping offline queue. Because these are
disposable beta-test observations, deleting the remaining stranded record with
the tester's consent and recapturing it is an acceptable data disposition. It
is not justification for weakening the composite-proof boundary, manually
inserting an owner row, bulk-deleting terminal records, or classifying an
arbitrary terminal state as recoverable.

This evidence also does not close the incident. Build `235` was already
distributed through TestFlight before the remediation; a later archive that
still reports `235` cannot replace that successfully uploaded TestFlight
binary. The repository also still declared build `235` when this trace was
reviewed. A fresh, globally higher build number is therefore required before
the iOS remediation can be tested through TestFlight. The session's adjacent
Explore media-health response drift is further evidence that the running binary
does not prove the current compatibility decoder. A later manual build-`235`
smoke did successfully retain an ordinary scan while Wi-Fi and cellular were
disabled and complete it after connectivity returned. That is positive
tester-observed offline-queue evidence, but its attached console did not capture
the exact transaction and it did not exercise legacy
`media_reconciliation_abandoned` repair or the later iOS source. The ordered
deployment evidence, eligible legacy-recovery smoke test, and exact-build
online/offline production verification below remain required.

The release archive inventory confirms the same boundary. At
`2026-07-30T02:13:13Z`, all 417 retained local archives were inspected. Forty-one
reported `1.0.2 (235)`, while zero archives contained the embedded source
revision, fingerprint, or clean/dirty state introduced by the remediation.
There is no provenance-bearing local candidate that can substitute for a fresh
higher build.

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
   `media_reconciliation_abandoned`. The terminal label alone was therefore not
   sufficient provenance for safe repair.

`media_reconciliation_abandoned` is written by the service-side media reconciler
after stale capture-upload objects cannot be promoted or repaired before the
abandonment TTL. It is normally an operational state, and the owner’s device can
still hold the validated local observation and original media. Older producers
also wrote `failed_scan_ingestions` only after a provider result had passed its
wire contract and post-result scan finalization failed. The affected producer
committed quota immediately before provider dispatch and did not mark that
reservation failed if owner-row persistence later failed. Its first normal
reservation can therefore remain `committed` even though the matching scan is
absent.

The dead letter alone is not sufficient recovery authority. Before the worker
fix, delayed media cleanup could overwrite a later moderation/provider-policy
terminal decision with `media_reconciliation_abandoned`, leaving an older dead
letter behind. Structured media-abandonment reasons became available on July 28,
after exact scan-inference quota reservations became mandatory on July 23. The
final repair therefore considers all eleven deterministic quota keys (the normal
key plus replay attempts 1–10), selects the latest charged authority, and
requires a matching post-result dead letter no earlier than that authority. It
additionally requires:

- no exact normal or replay reservation is currently `reserved`;
- every committed reservation retains ordered `reserved_at <= committed_at`, and
  every failed reservation additionally retains `committed_at <= failed_at`
  lineage;
- no capture-media lifecycle row records `moderation_rejected` or
  `moderation_pipeline_error`;
- for evidence written after the database rollout cutoff, the dead letter binds
  the latest reservation id/request id and records a validated provider result
  plus completed Identify safety evaluation; or
- for unstructured evidence, its exact dead-letter row ID was visible and
  snapshotted during the first hardening migration transaction, its timestamp
  predates that cutoff, and the latest authority is `failed`, or it is narrowly
  the vulnerable producer’s first committed normal attempt (`attempt_count = 1`)
  with no charged replay authority; and
- legacy evidence comes from the known `identify-multimodal` control flow with a
  nonempty post-safety failure message—not its only pre-safety throwing user
  prerequisite and not a moderation rejection/infrastructure error.

This distinguishes validated-result durability drift from pre-result abandonment
and from a later permanent policy authority. Unstructured evidence written by an
older Edge producer during the migration/function deployment gap is after the
database cutoff and remains fail-closed by design.

`supabase-js` returns PostgREST/database write failures in `{ error }`; awaiting
the query does not throw. The multimodal producer now checks that returned error
as well as thrown transport failures and emits
`multimodal/dead_letter_write_failed` when the proof row cannot be persisted.
This improves diagnostics and future recoverability without weakening the
historical proof requirement.

The generated 503 was therefore at the guarded owner-recovery RPC boundary,
before restore signing or media upload. The authenticated status handler
translated the internal database failure to a customer-safe retryable response.
New scans never exercise this compatibility routine, which explains why a new
scan could share successfully in the same production session.

## Resolution

### Exact terminal-reason allowlist

The service-only atomic owner-row recovery routine now allows:

- a `complete` ingestion ledger whose owner row is absent;
- `failed_terminal / replay_exhausted`; or
- `failed_terminal / media_reconciliation_abandoned` only when the exact
  owner/scan also has the composite dead-letter/quota/media-lifecycle proof.

Every other active, retryable, current/later policy, deletion,
unproven-abandonment, unknown, missing, or arbitrary terminal state still
returns `deferred`.

Forward migrations `20260729173000_recover_media_abandoned_owned_scans.sql` and
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql` replace the
routine and centralize the final proof without weakening its existing boundary:

- `internal.require_service_role()` is mandatory;
- execution remains revoked from `PUBLIC`, `anon`, and `authenticated`;
- the authenticated Edge layer normalizes a bounded non-media payload and
  derives its owner from the user JWT;
- the transaction takes the same per-scan generation advisory lock as ingestion;
- an owner-scoped ingestion job is required and row-locked;
- abandoned-media recovery requires exact owner/scan composite provenance,
  including every deterministic replay quota key and the full capture-media
  lifecycle;
- the database stores a private singleton rollout cutoff and immutable exact
  dead-letter-ID snapshot, so legacy unstructured authority cannot grow after
  migration—even when a DDL-blocked producer insert resumes with a backdated
  transaction-start timestamp;
- hardened producer rows bind exact quota identity, validated provider output,
  and completed Identify safety evaluation;
- historical rows must match the audited multimodal post-safety error lineage;
- a bounded service-only proof RPC gives restore signing the same database
  decision as owner-row reconstruction;
- the quota pruner retains every exact failed/committed normal and replay
  reservation as chronological recovery/security authority while the owner/scan
  remains unresolved `media_reconciliation_abandoned`; ordinary 30-day pruning
  resumes after recovery or explicit operator resolution, and malformed legacy
  text scan IDs are conditionally excluded without an unsafe UUID cast that
  could abort hourly cleanup;
- both privileged recovery RPC signatures are registered in
  `internal.privileged_routine_grants`;
- permanent deletion tombstones return `deleted`;
- existing owner rows are never overwritten;
- foreign UUID collisions return `id_collision`; and
- owner-row insert plus `client_recovery_complete` ledger transition commit
  together under the completion fence.

### Compatible restore signing

`scan_share_restore` registration uses the same exact terminal allowlist and
provenance rule. Before returning any URL, it requires:

- authenticated owner, canonical scan UUID, and deterministic scan/category
  filename;
- explicit `scan_share_restore` purpose;
- canonical media kind/role/content type and bounded byte size;
- exact `terminal_reason_code`, not a stage substring or customer-provided
  message;
- exact composite dead-letter/quota/media-lifecycle proof for media abandonment;
- a fresh unrestricted scan read when the job is complete or safely terminal; an
  existing row must be active and owned, while an absent row may only stage for
  the later guarded reconstruction;
- no moderation-rejected or moderation-pipeline-failed lifecycle row; and
- no mixed ordinary/repair manifest or active staging-budget overflow.

Signing and lifecycle registration grant no publication or scan-write authority.
The share endpoint still reloads the exact owner row, binds every restored key
to its owner/scan/kind/role ledger row, promotes only safe media, persists URLs
with proven-absence rollback semantics, and publishes post/media/ hashtags
through the atomic Explore transaction.

### iOS sequencing

New iOS code first resolves a read-only local restore plan and rejects missing,
empty, or over-budget surviving media before any owner-row mutation. It then
asks `/check-scan-status` to commit the guarded non-media owner-row repair before
signing that exact plan. This matches Field Chat and Ask the Community, avoids
uploading when database recovery will defer, and lets the signer validate a
completed active owner row.

The Edge signer and inline share repair also retain the older released-client
sequence—stage exact local media first, then attach `recovery_scan` to Share.
This compatibility is necessary to repair the current TestFlight cohort before
the next iOS build reaches testers. If the owner row is absent, Share requires
at least one validated restored staging key and returns
`409 scan_restore_media_required` before invoking owner recovery for a
media-less request.

The reconciler now refuses to invoke terminal marking for an already complete or
terminal job. Its database update independently excludes both states. This
prevents delayed media cleanup from erasing moderation/provider-policy
provenance.

## Why This Remains Secure

The allowlist expands one operational recovery reason, not general client scan
creation:

| State                                                                                                                                                                                                                                                 | Recovery  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `complete` but owner row absent                                                                                                                                                                                                                       | allowed   |
| `failed_terminal / replay_exhausted`                                                                                                                                                                                                                  | allowed   |
| `failed_terminal / media_reconciliation_abandoned` + exact generation-appropriate composite proof                                                                                                                                                     | allowed   |
| same reason with no charged authority/dead letter, an active reservation, dead letter older than latest authority, invalid timestamps, unstructured evidence absent from the migration snapshot or at/after the cutoff, or incomplete safety evidence | deferred  |
| same reason with moderation rejection or moderation-pipeline failure                                                                                                                                                                                  | deferred  |
| processing/finalizing/retrying/`failed_retryable`                                                                                                                                                                                                     | deferred  |
| moderation/provider policy rejection                                                                                                                                                                                                                  | deferred  |
| legacy unknown or arbitrary terminal reason                                                                                                                                                                                                           | deferred  |
| no owner-scoped ledger                                                                                                                                                                                                                                | deferred  |
| deletion tombstone                                                                                                                                                                                                                                    | deleted   |
| foreign existing scan id                                                                                                                                                                                                                              | collision |

A modified client cannot select the terminal reason, owner, ledger row,
service-only dead letter, quota state, or media lifecycle. It cannot provide
direct media URLs, bypass the staged-key binding, overwrite an existing scan,
resurrect deletion, or invoke the database proof/recovery routines directly.

## Verification

The repository now locks:

- both recoverable terminal reasons and the composite media-abandonment
  provenance proof in migration and Edge signing source contracts;
- UUIDv8 SHA-256 parity between Edge and SQL for all claimed replay request
  keys;
- worker and database defenses that preserve an existing terminal decision;
- current/later policy and legacy-unknown terminal deferral;
- exact repair-purpose gating so ordinary capture staging remains terminal;
- fresh owner/tombstone validation for terminal repair;
- atomic owner-row/ledger completion;
- bounded media registration, restoration ledger binding, and atomic Explore
  publication;
- iOS owner repair before media upload;
- stable-code-first activation for handler-owned missing scans; and
- exact engine/local-record/snapshot identity fences around Explore and Field
  Chat, including a captured chat presentation ID across asynchronous preflight;
- a Field Chat subject generation that rejects late load, send, delete,
  feedback, summary, and prompt completions from another private thread;
- a monotonic persisted-record action generation plus captured IDs for deletion,
  identification review, candidate delays, Explore/Community/Field Notes
  editors, nested Share sheets, New Collection, and Explore onboarding;
- exact queued-scan refresh and result-promotion checks, direct parent A → B
  presentation replacement, scan-scoped Retry release, and replaceable
  completion-handoff single-flight, preventing an old queued callback from
  restoring, promoting, or clearing UI for the wrong observation;
- scan/scientific-name/latest-action identification hydration fences and a
  serial local/cloud review-write tail, making the newest review action the
  durable final writer;
- exact post/request UUID revalidation for same-scan publication mutations,
  advisory-detail failure preservation, and target-scoped dismissal bindings;
  and
- handler-confirmed owner absence clearing only the affected scan's obsolete
  local publication marker, so its next deliberate share reaches guarded
  recovery instead of a stale Edit action.

The exact runtime source committed as `cc664a20d` passes the complete portable
Edge, migration, deployment-tooling, documentation, iOS source/parser,
changed-scope lint, and CI-evidence contract set. Those results are source
evidence only. Fresh hosted PostgreSQL catalogs, full Xcode tests plus archive,
and ordered production deployment remain mandatory closure evidence. A
same-account legacy-record smoke test is also mandatory.

The final PostgreSQL fixture calls the real proof and recovery routines for the
affected legacy committed lineage, modern structured lineage, unproven,
post-rollout backdated-but-unsnapshotted, later-authority, replay-authority,
moderation rejection, moderation-pipeline failure, moderation-only legacy
evidence, pre-safety legacy evidence, wrong-producer endpoint, incomplete
structured safety, active replay, corrupt timestamp lineage, and unknown
terminal states. It also proves all exact failed/committed normal and replay
authority plus the active replay fence survives quota pruning while refunded and
unrelated old reservations are removed. Deno tests execute terminal signing
insertion/rejection paths, reject malformed proof responses, and prove the media
worker cannot rewrite an existing terminal decision. The production workflow now
calls both service-only recovery RPCs with null inputs and requires their exact
SQLSTATE `22023` no-write validation responses; it separately proves every
public API key is denied.

## Ordered Rollout

1. Predeploy the exact-SHA fail-closed `generate-upload-urls`,
   `check-scan-status`, and `share-scan-to-explore` consumers. They must require
   the hardening migration's proof RPC before any legacy owner recovery or
   restore signing, and must preserve local media behind retryable `503` while
   it is unavailable. Do not predeploy the structured Identify producer.
   Keep `request-community-identification` in the final cumulative exact-SHA
   plan as well. Although it imports Explore publication helpers, it neither
   accepts `recovery_scan` nor invokes owner-row recovery, so it is not a
   migration-gap consumer.
2. Apply, in order, `20260729173000_recover_media_abandoned_owned_scans.sql` and
   `20260729200000_harden_media_abandoned_scan_recovery_proof.sql`. The pinned
   CLI executes them as separate migration-file transactions, so even one
   uninterrupted `db push` has a committed inter-file boundary. Never stop after
   the first migration or exercise owner recovery until the hardened routine,
   ACL, and privileged-grant catalog checks have passed.
3. Confirm the exact service-only function ACL, privileged-grant ledger, quota
   authority retention, and catalog fixture.
4. Deploy `identify-multimodal` and the final
   `generate-upload-urls`/`check-scan-status`/`share-scan-to-explore` bundles
   from the same reviewed SHA through the cumulative compatibility plan.
5. Require the production no-write validation probes for
   `recover_missing_owned_scan` and `get_media_abandoned_scan_recovery_proofs`
   to pass before handler smoke tests.
6. Verify the current released/TestFlight client can stage, recover, and share
   one eligible older observation.
7. Promote the matching iOS build that repairs the owner row before upload.

An unguarded function-first deployment would make the structured producer fields
and proof RPC unavailable. An unguarded migration-first deployment would expose
the baseline recovery definition between the two file transactions. The split
order above closes both windows: only the three legacy-repair consumers deploy
first and fail closed, the migrations establish proof authority next, and the
schema-dependent producer deploys last. Any old producer still running after the
database cutoff can write operational history, but its new unstructured row
cannot become automatic recovery authority. No post can publish until the owner
row is reconstructed.

## Required Production Verification

Do not close this incident until:

1. a newly captured scan still completes Identify, status `found`, composer
   media, and Explore publication;
2. an eligible existing `media_reconciliation_abandoned` scan recovers its exact
   owner row, restores surviving local media, and publishes without recapture,
   with the matching composite service proof confirmed in restricted
   diagnostics;
3. Field Chat and Ask the Community can use that recovered observation;
4. relaunch or lost responses during signing, upload, owner-row recovery, media
   persistence, and publication resume idempotently;
5. moderation/provider-policy, moderation-pipeline failure, active or
   later-authority normal/replay attempts, invalid timestamp lineage,
   post-rollout unsnapshotted or post-cutoff unstructured evidence, incomplete
   structured safety evidence, unproven abandonment, unknown-terminal,
   no-ledger, cross-owner, tombstoned, malformed, and over-budget attempts
   remain blocked, and delayed media reconciliation does not rewrite policy;
6. restored media returns successfully from the canonical public origin; and
7. retained logs contain no generic 503 for an otherwise eligible
   `media_reconciliation_abandoned` repair; and
8. rapid scan A → B and A → B → A switches while chat, candidate hydration,
   queued refresh/promotion, editors, onboarding, collection, deletion, and
   sharing callbacks are suspended produce no cross-scan state or mutation; and
9. the exact higher-build offline/reconnect smoke retains its Settings → Beta
   Diagnostics artifact before observation deletion, binding the bounded
   queue/upload/staging/inference/completion sequence to the embedded clean
   source revision/fingerprint without private content.
