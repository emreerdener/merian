# Video Scan Canonical-Finalization Regression

**Date:** 2026-07-28\
**Severity:** Release-blocking\
**Affected flow:** Video capture → Identify → Insight → Field Chat / Explore
sharing / owner sync\
**Repository status:** Remediated by a forward migration\
**Production status:** Open until exact-SHA catalog, deployment, joined-flow,
and observation evidence satisfies the closure gates below

## User Impact

A video scan could finish provider analysis, promote its playback clip, and
insert the authenticated owner's scan, but still fail the complete-last
database transaction with `canonical_scan_media_incomplete`. The endpoint then
returned retryable `503 scan_persistence_failed` instead of a stable completed
Insight. Until recovery completed, Field Chat and Explore publication could not
rely on the shared completed-scan boundary.

The defect also blocked the service-only repair for an already-owned mixed video
generation. It did not permit a cross-owner write, expose private media, or mark
an incomplete generation complete; it rejected valid media too strictly.

## Detection and Isolation

`Deploy Merian to Supabase` workflow run 1552 evaluated commit
`7e54a1ade9806f40654c937fe9eaf6f7d93439e9`. It rebuilt the disposable
PostgreSQL catalog, applied the complete migration history, discovered all 24
pgTAP files, and completed 22 files.

`inline_scan_manifest_recovery_security.sql` ran 15 of its 23 planned
assertions without an assertion failure. Assertions 13–15 prove that the
inline-image recovery, ledger normalization, and ready canonical image path all
completed. The next statement is the recovery call for deterministic mixed
video scan `...f112`; that call raised before TAP assertion 16. This locates the
failure inside strict finalization of the video case rather than fixture setup,
profile creation, image recovery, or a later offline-image assertion.

The run stopped at the disposable catalog gate before production connection
preparation, `db push`, Edge Function deployment, or production smoke testing.
It made no production mutation.

## Root Cause

Three representations have intentionally different jobs:

1. `scans.image_storage_urls` remains a compatibility and inference surface.
   For video scans it may contain five sampled video frames.
2. `scans.captured_media` is the app-facing timeline. It pairs one playback
   video with its poster thumbnail so sampled frames do not render as
   standalone images.
3. `refresh_scan_visual_media_assets` mirrors that timeline. For a legacy row it
   calculates `standalone images = image URLs - (video URLs × 5)`, creates only
   those image rows, and creates one ready playback row per video.

Migration
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql` added a strict
post-refresh check that required every URL in `image_storage_urls` to have a
ready `kind = image` row. That contradicted the existing video-media contract:
sampled inference frames are thumbnail inputs, not standalone canonical images.
Even though refresh produced the correct ready playback video, finalization
looked for deliberately nonexistent image rows and raised
`canonical_scan_media_incomplete`.

This was not fixed by manufacturing image rows for inference frames. Doing so
would regress Insight and Explore into showing sampled frames as separate user
media.

## Remediation

Forward migration
`20260729012153_fix_video_scan_canonical_finalization.sql` adds two private
validators and replaces only the two exact contradictory checks in the deployed
finalizer.

`internal.scan_canonical_media_projection_complete(scan_id)`:

- uses valid image/video references from `captured_media` when that canonical
  visual timeline exists;
- otherwise projects the same standalone-image and playback-video set as the
  legacy media refresher;
- includes standalone audio from both `captured_media` and compatibility audio
  URLs;
- requires projected standalone-image and playback-video counts to equal the
  job's endpoint-normalized image count and validated `video_count`. Native
  counts already exclude frames; compatibility counts subtract their separately
  validated declared frame subset, so an omitted real capture cannot be
  relabeled as a frame;
- requires an exact scan, owner, kind, URL, and `ready` status for every
  projected item; and
- returns false for a missing scan.

Private
`internal.scan_media_reference_is_video_inference_frame(scan_id, user_id, url)`
handles the later captured-to-canonical check. It returns true only when the
exact scan owner and ingestion job agree, the job declares a positive numeric
`video_inference_frame_count`, the URL is present in the scan's compatibility
image array, the projected standalone-image count equals the job's
endpoint-normalized image count, the complete classified-frame set has exactly
the declared frame count, and the reference is outside the canonical
display-image set for a proven captured video or inside the exact legacy frame
suffix. A promoted standalone image, playback video, or audio capture still
requires its matching ready canonical row.

Both validators are `SECURITY INVOKER`, have empty search paths, and have
execute revoked from `PUBLIC`, `anon`, `authenticated`, and `service_role`. The
service-only finalizer calls them with its owner authority after refreshing
canonical rows.
The finalizer's existing caller check, storage-key manifest proof, promotion and
deletion counts, captured-to-canonical requirement for every non-frame capture,
completion fence, and complete-last update remain unchanged.

The migration obtains the current catalog definition with
`pg_get_functiondef`, requires exactly one byte-exact match for each old block,
requires exactly one installed call to each validator, and aborts otherwise. It
reasserts the finalizer's exact service-role ACL. The already-applied historical
migration is not edited.

## Regression Coverage

- `inline_scan_manifest_recovery_security.sql` is the live PostgreSQL
  regression. Its historical mixed-video recovery must return `completed`,
  preserve the real video manifest and upload session, promote the capture row,
  and create a ready playback row. Its direct production-shape case promotes
  five staged sampled-frame captures plus one staged playback capture, completes
  the ledger last, and requires exactly one ready playback row with no ready
  standalone frame images. It first proves that an incomplete declared frame
  count does not classify any frame as exempt. It also exercises both native
  standalone-image counts and legacy compatibility counts that include the
  declared frame subset. The fixture now plans 30 assertions; Run
  1552's historical source planned 23.
- `inlineScanManifestRecoveryMigrationContract.test.ts` pins canonical and
  legacy projection, inference-frame declaration and timeline classification,
  the five-frame rule, owner-matched ready rows, private ACLs, both guarded
  rewrites, refresh-before-validation order, and the absence of a blanket
  mixed-media image skip.
- Both exact historical guarded fragments are mechanically confirmed once in
  the migration source. The migration itself fails closed if the deployed
  routine differs.

Local repository evidence after the joined remediation is 178 passing migration
assertions across all 28 discovered migration contract files. The next
exact-SHA hosted catalog run also passed all 30 assertions in the live
inline/video fixture on a disposable PostgreSQL catalog. That is fresh-catalog
evidence for this regression, not staging joined-flow or production evidence.

The other Run 1552 failure,
`identity_merge_scan_recovery_security.sql`, is independent: its single
all-or-nothing block aborted before emitting TAP. The fixture now catches its
own exception, emits phase/SQLSTATE/message/detail/hint as a deterministic
warning, and returns one failed TAP assertion. The next run identified a
fixture-only `42702` at `ingestion-intent setup`: its synthetic `scan_id`
variable was ambiguous beside the ledger column. That variable is now
`fixture_scan_id`, and a source contract prevents the old declaration. The
latest hosted 26-file replay reached and passed identity merge/recovery as well
as this complete inline/video fixture. It completed 24 files; only the two new
atomic Explore and Community fixtures then stopped on their independent
service-role invoker privilege gap. The run stopped before production
preparation or mutation.

## Deployment and Closure

Apply the repository's complete migration history through the normal Supabase
workflow. Do not edit the applied finalization migration, run this migration
manually against linked production, or bypass the disposable catalog gate.

Close this incident only after retaining:

1. an exact-SHA disposable-catalog replay with all migrations and all catalog
   fixtures passing;
2. a staging video scan whose immediate owner status is `found`, whose playback
   asset is ready, and whose sampled frames are absent as standalone media;
3. Field Chat opening and Explore publication for that same completed scan;
4. a queued/relaunched video retry and the historical mixed-video recovery case
   without provider redispatch or quota refund;
5. ordered production migration/function deployment from the same reviewed
   SHA; and
6. a clean observation window with no new
   `canonical_scan_media_incomplete`, false success, missing playback, Field
   Chat prerequisite, or Explore snapshot failures.

The joined behavioral and rollout contracts remain
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
and
[Supabase Deployment Runbook](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout).
