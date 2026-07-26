# July 2026 Account-Scoped R2 Image Loss

**Status (2026-07-26):** Contained in the repository; production deployment
and runtime verification are still pending. Device-assisted recovery is in
progress and is incomplete.

## Summary

One account's captured images stopped loading in both the Scan Library and its
Explore posts. The relational scan and post rows still existed, but the
account-owned Cloudflare R2 objects referenced by those rows returned HTTP 404.
Other owners' Explore media remained available.

This is an account-scoped object-loss incident, not a feed-filtering issue and
not a Supabase Storage outage. Naturebook stores scan/post metadata and public
media URLs in Supabase Postgres. The image bytes at those URLs live in
Cloudflare R2 object storage. Keeping a URL in Postgres does not preserve the
corresponding R2 object.

The strongest code-level explanation is a historical account-deletion outbox
row that was made actionable by the 2026-07-25 storage-erasure migration. That
explanation fits the owner-prefix scope and timing exactly, but remains the
**leading cause**, not a production-log-proven root cause. The production
outbox row, worker claim, and R2 delete audit evidence have not yet been
verified.

## Impact and Scope

- 335 active cloud scan rows remained for the impacted owner.
- Those rows referenced 347 unique cloud image URLs: 162 under the free prefix
  and 185 under the Pro prefix.
- Sampled objects from both owner prefixes returned genuine HTTP 404 responses.
- Sampled media belonging to other Explore owners continued to load.
- The same missing objects affected Scan Library and Explore because both
  surfaces ultimately referenced the same owner-scoped R2 media.
- Likes, comments, taxonomy labels, scan rows, and post rows remaining in
  Postgres do not imply that the underlying image bytes remain in R2.
- A separate presentation inconsistency made the incident look even less
  coherent: the owner profile count used a legacy publication query, the
  nine-tile preview mixed five canonical server posts with four local cached
  share rows, and the full grid returned only the five canonical server posts.
  This mismatch was a global code defect triggered by this account's unusual
  media state; it is not evidence that four additional R2 objects existed.

No evidence currently indicates a bucket-wide loss.

### Profile projection mismatch

The observed `38` count, `9` preview tiles, and `5` full-grid tiles came from
three different inputs:

- `38`: a legacy profile count that did not apply the complete media-health
  quarantine projection;
- `9`: five canonical remote posts plus four locally cached share-state tiles;
  and
- `5`: the canonical remote author-post endpoint.

Migration `20260726174555_align_explore_author_publication_contract.sql` moves
the visible profile count onto `explore_projected_post_cards(self_id)`. The iOS
preview no longer promotes local share cache into a public grid, and the
author-post endpoint now returns explicit continuation metadata. Preserved
publication intent and media-recovery totals remain available separately to the
owner.

## Evidence Classification

### Confirmed

- The impacted account's relational scan/post data remains.
- The impacted account's sampled R2 object keys return 404.
- Other owners' sampled Explore objects return successfully.
- The repository's intended lifecycle policy expires only temporary
  `quarantine/`, `exports/`, and `staging/` objects and aborts incomplete
  multipart uploads after seven days. It does not expire durable
  `public_uploads/free/`, `public_uploads/pro/`, or `avatars/` objects.
- A separate SwiftData migration failure occurred on 2026-07-10 and moved the
  old local store into `Library/Application Support/store-rescue/`. That event
  explains the local “archived”/rebuilt-library behavior, but it cannot delete
  account-scoped objects from R2.

### Leading Cause

The following sequence is consistent with every observed cloud symptom:

1. Before the 2026-04-05 safe-delete correction, account deletion could enqueue
   `pending_storage_deletions` before later tombstone/Auth steps completed.
2. If a later deletion step failed, the account could remain live while a stale
   storage marker survived.
3. Migration
   `20260725052337_enforce_account_storage_erasure.sql` upgraded and reset all
   historical unconsumed markers to pending five-prefix sweep jobs.
4. Its original `claim_pending_storage_deletions` implementation checked queue
   status, due time, and lease state, but did not require a matching
   `storage_pending` account-deletion job and did not reject a live public user
   or owned scans.
5. If the impacted owner had such a stale marker and the migration/worker were
   active in production, the scheduled worker could delete
   `public_uploads/free/{owner}/` and `public_uploads/pro/{owner}/` while leaving
   all Postgres references intact.

This would affect exactly one owner, blank both Scan Library and Explore, and
leave other owners' media untouched.

### Pending Verification

- Confirm the relevant migrations and Edge bundles actually reached production.
- Inspect historical `pending_storage_deletions` and
  `internal.account_deletion_jobs` state for the incident window.
- Correlate Supabase worker claims/logs with Cloudflare R2 delete/audit events.
- Determine whether any independent R2 replication, backup, or retained object
  version can recover otherwise unmatched bytes.

## Timeline

| Time | Event |
| --- | --- |
| 2026-04-05 | Safe-delete ordering was corrected so destructive cleanup no longer begins from an outbox marker alone. Historical markers were not purged by that code change. |
| 2026-07-10 04:16:39Z | App 1.0.1 (209) encountered `SwiftDataError 1`. The old local store was preserved under `store-rescue/2026-07-10T04-16-39Z-BE7C8548-CD59-4E95-A420-4602CE91D89B/default.store` with reason `legacy_migration_rescue`, and a fresh store was built. |
| 2026-07-25 | The repository introduced the storage-erasure migration that upgrades every historical unconsumed marker and schedules five-minute reconciliation. Missing owner media was reported in Scan Library and Explore; production migration/worker evidence remains pending. |
| 2026-07-26 | Repository safeguards, the owner-scoped repair API, and local recovery matching were implemented. A reversible Explore media-health quarantine, scheduled direct-origin reconciliation, owner recovery queue, and automatic repair restoration were added. Production deployment remains unverified. |
| 2026-07-26 | The `38` count / `9` preview / `5` full-grid mismatch was traced to legacy count projection plus local preview backfill. A canonical count/grid contract, owner recovery totals, explicit pagination cursor, and deploy-wide aggregate scope smoke were implemented in the repository. |

## Containment and Remediation

### Storage-Erasure Claim Fence

Migration `20260726041109_fence_storage_erasure_claims.sql` replaces the claim
routine. A storage row is now claimable only when all of these are true:

- a matching private account-deletion job exists;
- that job is exactly `storage_pending`;
- relational cleanup has completed;
- storage has not already completed;
- no live `public.users` row exists for the target; and
- no `public.scans` row is still owned by the target.

An orphaned outbox row is therefore inert. Queue status or age alone can never
authorize an owner-prefix sweep.

### Owner-Scoped Cloud Repair

Migration `20260726041338_repair_owned_scan_image_references.sql` and the
authenticated `/repair-scan-image` Edge Function provide the cloud repair
boundary:

1. Derive the owner from the JWT; callers cannot select another owner.
2. Confirm the source URL is referenced by an active scan owned by that user.
3. `HEAD` the source R2 object. A healthy source is never replaced.
4. Confirm the owner-scoped restored staging object exists.
5. Promote that object to a new durable free/Pro owner key.
6. Atomically replace the exact source URL across `scans.image_storage_urls`,
   structured `captured_media`, `scan_media_assets`, and owner Explore media
   snapshots.
7. Delete the newly promoted object if the metadata transaction fails.

The atomic transaction also updates matching Explore snapshots, so this route
repairs both product surfaces together and does not grant arbitrary R2 write or
metadata-rewrite access.

### Device-Assisted Recovery

The installed iPhone still contained 548 WebP files in the app's Documents
directory. Local recovery deliberately uses evidence in descending order of
confidence:

1. exact promoted/local filename compatibility;
2. scan-ID alignment against the preserved `store-rescue` database; and
3. high-confidence timestamp groups for scans absent from the rescue database.

Timestamp recovery accepts only a single `_scan` file plus contiguous
`_additional_N` files written in the same second, an exact remote/local media
count, a local write no more than 60 seconds before the scan row, a minimum
three-second margin over the next candidate, and globally one-to-one file use.
Bare nearest-time matching was rejected because calibration showed
approximately 70% precision.

Calibration against known pre-rescue mappings found the correct `_scan` file
for all 77 matched candidates inside the 60-second one-way window. Direct
filename matching covered 68 URL references/63 covers; rescue-store scan-ID
alignment covered 139 URL references/129 covers. Because those lanes overlap,
their combined pre-timestamp coverage was 161 URL references/150 covers.
Constrained timestamp matching then added 84 URL references across 79
post-rescue scans.

Current mapping coverage is:

| Recovery state | Recovered | Total |
| --- | ---: | ---: |
| Cloud image URL references with a local match | 245 | 332 |
| Scan covers with a local match | 229 | 315 |
| Unresolved cloud image URL references | 87 | 332 |
| Unresolved scan covers | 86 | 315 |

The 347 cloud-incident URL count and 332 device-recovery URL count are different
denominators: the first is the unique active cloud-row scope, while the second
is the current device's visual recovery projection after local
deduplication/exclusions. Neither count should be substituted for the other in
recovery reporting.

For mapped URLs, the iOS client can render the surviving local file immediately
and, while online, enqueue the authenticated cloud repair flow. These counts are
candidate/reference coverage, not proof that production re-upload completed.
The currently installed recovery build has not yet been visually/runtime
verified because the device was locked during remote launch.

The app-group media cache was absent, no Finder/iTunes backup was found, and
Save to Camera Roll defaults to off. A Photos-library search requires explicit
user permission and is a separate recovery step.

### Published Explore Behavior

Migrations `20260726144647` and `20260726144754` add the durable product
response for present and future media incidents. One client/CDN failure does
not change publication. Two direct R2-origin `404` checks at least five minutes
apart confirm a primary object as missing. Public projection then omits only
the confirmed-missing item; it system-quarantines an all-missing post without
changing `unshared_at`, moderation, the post row, likes, comments, or reports.

The owner receives one `media_missing` incident plus a persistent Scan Library
recovery banner. `get-explore-media-incidents` exposes only that owner's active
queue. A healthy origin result or successful atomic image repair restores
projection automatically when author and moderation state still permit it, and
creates an in-app-only `media_restored` event.

`reconcile-explore-media-health` is the five-minute source of truth.
`ingest-r2-media-events` optionally accelerates matching rows but cannot confirm
existence or loss. This prevents blank public posts and engagement destruction;
it does not recreate any bytes already lost in this incident.

See
[Explore Media Health and Quarantine](../backend-and-data/12-explore-media-health-and-quarantine.md).

## R2 Durability and Recoverability

Cloudflare R2 is object storage, not the relational database. R2 durability
protects stored objects against infrastructure failure; it does not undo a
valid intentional delete request. Object deletion is irreversible unless an
independent copy, backup, replication target, or surviving device file exists.

See Cloudflare's official documentation:

- [Delete objects](https://developers.cloudflare.com/r2/objects/delete-objects/)
- [Data durability](https://developers.cloudflare.com/r2/reference/durability/)
- [Object lifecycle rules](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)

## Required Production Verification

Do not mark this incident resolved until all of the following are complete:

1. Verify both new migrations are recorded in production.
2. Verify `safe-delete`, `reconcile-account-deletions`, and
   `repair-scan-image` are the expected deployed bundles.
3. Verify the installed claim routine contains every database authorization
   fence:

   ```sql
   WITH claim_definition AS (
     SELECT LOWER(
       pg_get_functiondef(
         'public.claim_pending_storage_deletions(integer)'::REGPROCEDURE
       )
     ) AS body
   )
   SELECT
     POSITION(
       'inner join internal.account_deletion_jobs' IN body
     ) > 0 AS joins_private_job,
     POSITION(
       'deletion_job.status = ''storage_pending''' IN body
     ) > 0 AS requires_storage_pending,
     POSITION(
       'deletion_job.cleanup_completed_at is not null' IN body
     ) > 0 AS requires_cleanup,
     POSITION(
       'from public.users as live_user' IN body
     ) > 0 AS vetoes_live_profile,
     POSITION(
       'from public.scans as owned_scan' IN body
     ) > 0 AS vetoes_owned_scans
   FROM claim_definition;
   ```

   Expected: every boolean is `true`.
4. Audit due rows that the fence should keep inert:

   ```sql
   SELECT COUNT(*) AS fenced_due_storage_rows
   FROM public.pending_storage_deletions AS deletion
   LEFT JOIN internal.account_deletion_jobs AS deletion_job
     ON deletion_job.user_id = deletion.target_user_id
   WHERE deletion.status IN ('pending', 'processing')
     AND deletion.next_attempt_at <= NOW()
     AND (
       deletion_job.status IS DISTINCT FROM 'storage_pending'
       OR deletion_job.cleanup_completed_at IS NULL
       OR deletion_job.storage_completed_at IS NOT NULL
       OR EXISTS (
         SELECT 1
         FROM public.users AS live_user
         WHERE live_user.id = deletion.target_user_id
       )
       OR EXISTS (
         SELECT 1
         FROM public.scans AS owned_scan
         WHERE owned_scan.user_id = deletion.target_user_id
       )
     );
   ```

   A nonzero count requires restricted operator review because it can reveal the
   historical stale-marker cohort. It is not proof that those rows are
   claimable under the fenced routine. Do not make them actionable or sweep
   their prefixes to clear the count.
5. On staging, create an orphaned storage marker for a live fixture account and
   prove the worker does not claim it.
6. On staging, run a legitimate safe-delete job and prove it becomes claimable
   only after cleanup removes the live profile and scan ownership.
7. Repair one known missing image with a surviving local file and verify the new
   durable object, Scan Library image, and Explore snapshot all load.
8. Verify both Explore media-health migrations and all three new Edge bundles
   are deployed, the `*/5` reconciliation cron is active, and recent
   reconciliation-run audit rows succeed.
9. Verify migration `20260726174555`, redeployed author-profile/post functions,
   and the service aggregate smoke. Record `affected_author_count` without
   owner identifiers; any value above the known incident cohort expands scope.
10. Verify profile visible count, preview posts, and every full-grid page agree,
    while preserved/recovery-needed totals remain owner-only.
11. On staging, complete the healthy -> degraded -> quarantined -> degraded ->
   healthy projection matrix, including two spaced origin checks, owner
   notification/banner behavior, unchanged author/engagement state, continuity
   through snapshot refresh, and automatic repair restoration.
12. Confirm lifecycle rules match `docs/r2-lifecycle.json` and contain no
   durable-prefix expiration.
13. Retain aggregate query output and request-correlated logs as incident
   evidence without publishing owner identifiers or object keys.

## Permanent Invariants

- A metadata URL is a reference, not a backup of object bytes.
- Only a matching durable account-deletion state machine may authorize an
  account-prefix sweep.
- A live profile or any scan still owned by the target is a hard storage-claim
  veto.
- Historical outbox rows must be audited before a migration makes them newly
  actionable.
- Durable R2 prefixes must never receive age-based lifecycle expiration.
- Destructive worker changes require an account-isolation canary and a
  production aggregate invariant check.
- Scan and Explore metadata for the same media must be repaired atomically.
- Unexpected media loss never auto-deletes or auto-unpublishes an Explore post.
  Confirmed-missing items are omitted; all-missing posts are reversibly
  quarantined with engagement intact.
- CDN/client/transport failure is never loss proof. Confirmation requires two
  spaced direct R2-origin `404` checks.
- Storage events are hints only; scheduled origin reconciliation is
  authoritative.
- Reference imagery never substitutes for missing observation evidence.
- Incident status must distinguish repository mitigation, production
  deployment, runtime verification, and data recovery.

## Relevant Source

- `services/supabase/migrations/20260726041109_fence_storage_erasure_claims.sql`
- `services/supabase/migrations/20260726041338_repair_owned_scan_image_references.sql`
- `services/supabase/migrations/20260726144647_add_explore_media_quarantine_lifecycle.sql`
- `services/supabase/migrations/20260726144754_implement_explore_media_quarantine_state_machine.sql`
- `services/supabase/migrations/20260726174555_align_explore_author_publication_contract.sql`
- `services/supabase/functions/repair-scan-image/`
- `services/supabase/functions/reconcile-explore-media-health/`
- `services/supabase/functions/get-explore-media-incidents/`
- `services/supabase/functions/ingest-r2-media-events/`
- `services/supabase/functions/safe-delete/`
- `apps/ios/Merian/Core/Data/Images/LocalImageLoader.swift`
- `docs/r2-lifecycle.json`
- `docs/backend-and-data/08-startup-store-recovery.md`
- `docs/backend-and-data/12-explore-media-health-and-quarantine.md`
