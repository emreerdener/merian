# Logging and Debugging

Merian uses Apple's unified `os.Logger` API via a centralized `MerianLog`
namespace (`Core/MerianLog.swift`). This document explains which subsystem to
use where, when to use `.debug` vs `.error`, how privacy specifiers work, and
how to filter logs in Instruments or Console.

---

## The `MerianLog` Namespace

```swift
// Core/MerianLog.swift
import os

enum MerianLog {
    static let auth     = Logger(subsystem: "com.merian.app", category: "Auth")
    static let network  = Logger(subsystem: "com.merian.app", category: "Network")
    static let data     = Logger(subsystem: "com.merian.app", category: "Data")
    static let hardware = Logger(subsystem: "com.merian.app", category: "Hardware")
    static let exploreVideo = Logger(subsystem: "com.merian.app", category: "ExploreVideo")
    static let general  = Logger(subsystem: "com.merian.app", category: "General")
}
```

**Never use `print()` in production code.** `Logger` entries appear in
Console.app and Instruments, are filterable by category, respect privacy
specifiers, and have negligible performance overhead. `print()` does none of
these. The codebase has been fully audited — there are no remaining `print()`
calls outside of tests. Any new `print()` introduced during development must be
replaced before merge.

---

## Subsystem Selection

| Subsystem                | Use for                                                                                                                      |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `MerianLog.auth`         | `SupabaseManager` — sign in, Ghost sessions, JWT refresh, OAuth flows                                                        |
| `MerianLog.network`      | `MerianNetworkClient` — HTTP requests, R2 uploads, Edge function calls, status codes                                         |
| `MerianLog.data`         | All SwiftData actors, `OfflineQueueManager`, `ScanRepository`, `FileIOActor`, `ArchiveManager`                               |
| `MerianLog.hardware`     | `CameraManager` — AVFoundation locks, focus, torch, thermal states, video stabilization mode                                 |
| `MerianLog.exploreVideo` | Explore public video playback — active player changes, sheet overlay pause/resume, player/layer rebuilds, recovery watchdogs |
| `MerianLog.general`      | `InferenceEngine`, `CircuitBreakerManager`, `GamificationManager`, `PostHogManager`, `AppTelemetry`, everything else         |

When in doubt, use `MerianLog.general`. Do not create new `Logger` instances
outside of `MerianLog` — adding a new category requires updating the enum and
this document.

---

## Log Level Selection

| Level  | Method         | When to use                                                                                                                                      |
| ------ | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Debug  | `.debug(...)`  | Expected paths, performance timings, state transitions that are useful during development. Stripped from production builds by the OS by default. |
| Info   | `.info(...)`   | Informational messages that should survive to production logs. Use sparingly.                                                                    |
| Notice | `.notice(...)` | High-visibility operational state that should stand out from ordinary debug flow. Guard development-only reminders with `#if DEBUG`.             |
| Error  | `.error(...)`  | Any `catch` block where the failure represents a real problem (data loss risk, save failure, upload failure). Persists in production.            |
| Fault  | `.fault(...)`  | Reserved for programmer errors / invariant violations. Do not use in data paths.                                                                 |

**Rule: use `.error` in any `catch` that could cause data loss or
inconsistency.** Use `.debug` for anything that is part of normal flow. The
previous codebase used `.debug` for SwiftData save failures — those were
upgraded to `.error` during the concurrency audit.

Startup store recovery is a production support path:

- Log the initial persistent-store failure as `.error`.
- Log a successful quarantine/rescue retry as `.error` so it survives production
  log collection.
- Log a failed quarantine/rescue retry as `.fault` because the app is entering
  safe mode after a recovery attempt.
- Never log full local store paths, tokens, user IDs, scan IDs, or profile data.
  The quarantine/rescue `recovery-manifest.json` is the support artifact for
  sanitized context.

---

## Privacy Specifiers

Every interpolated value in a `Logger` message must have an explicit `privacy:`
label.

```swift
// Private — value is redacted in production logs
MerianLog.data.error("Save failed for scan \(scanId, privacy: .private): \(error, privacy: .private)")

// Public — value appears in production logs (safe for counts, statuses, durations)
MerianLog.data.debug("Reconciling \(allScans.count, privacy: .public) remote scans")

// Auto — redacted in non-development builds (default if omitted, but be explicit)
MerianLog.general.debug("Species: \(name, privacy: .auto)")
```

**Rules:**

- UUIDs, scan IDs, species names, GPS coordinates, user data → `.private`
- Reference/media URLs, object keys, local file paths, and summaries that pair a
  scan ID with species or media state → `.private`
- Counts, HTTP status codes, boolean flags, timing durations → `.public`
- Never log a raw `Error` without `privacy: .private` — error messages can
  contain user file paths or network URLs

---

## Reading Logs

### Console.app

1. Open Console.app → select the connected device
2. In the search bar, filter: `subsystem:com.merian.app`
3. Narrow by category: `subsystem:com.merian.app category:Data`

### Instruments (os_log)

1. Profile → Logging instrument
2. Filter by subsystem `com.merian.app`
3. Use category column to isolate the relevant layer

### Xcode Debug Console

During a debug build, all `.debug` messages appear in the Xcode console. To
filter in the console output stream, use `subsystem` as a filter prefix.

### Feature flag registry and local overrides

All client-build release gates are listed in the `FeatureFlag` enum in
`Core/Utilities/FieldTripsAvailability.swift`. Their `defaultValue` entries are
the values used by TestFlight and App Store builds.

DEBUG builds add a **Feature Flags** section to Settings. Its toggles persist
device-local overrides so unfinished or staged UI can be exercised without
editing and rebuilding. **Use code defaults** clears every override. Release
builds neither show these controls nor read the stored values, and no toggle
changes backend authorization. Production rollout or rollback still requires a
code-default change and a new iOS build.

### Field trip rollout reminder

Every non-test DEBUG app startup calls
`FieldTripEventsAvailability.logRolloutState()`. While Events are staged, the
General-category notice is:

```text
TODO(field-trip-events-release): Outings are public; Events remain staged to the tester allowlist and simulator builds.
```

Filter the Xcode console for `field-trip-events-release`, or use
`subsystem:com.merian.app category:General` in Console.app. The same named TODO
is beside the `.fieldTripEvents` registry default, and the canonical release
checklist is in
[`25-field-trips.md`](../features-and-hardware/25-field-trips.md#rollout-state-and-events-release-checklist).
The reminder is compiled only into DEBUG builds, contains no user data, and is
not product telemetry.

### Runtime Log Triage

Some noisy lines come from Apple frameworks or third-party development
configuration rather than Merian application faults:

| Log pattern                                                                                                                                                   | Meaning                                                                                                                                                                                                                                                                                                                                                                                                                 | Action                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FigCaptureSourceSimulator`, `FigCaptureSessionSimulator`, `FormatDescription`                                                                                | AVFoundation simulator capture stack probing unavailable or synthetic camera formats.                                                                                                                                                                                                                                                                                                                                   | Merian simulator builds use a no-preview camera path; investigate if these appear in a fresh build or if the preview is blank on physical devices.                                                                                                                                                                                                                                                                                                                               |
| `IOSurfaceClientSetSurfaceNotify failed`                                                                                                                      | Simulator/CoreAnimation surface notification failure.                                                                                                                                                                                                                                                                                                                                                                   | Treat as simulator noise unless paired with a reproducible rendering failure.                                                                                                                                                                                                                                                                                                                                                                                                    |
| `nw_connection_copy_connected_local_endpoint... no local endpoint`                                                                                            | Network framework inspected a socket before connection establishment completed.                                                                                                                                                                                                                                                                                                                                         | Usually harmless; investigate only with request failures in `MerianLog.network`.                                                                                                                                                                                                                                                                                                                                                                                                 |
| `AudioConverterOOP.cpp... Failed to prepare AudioConverterService: -302`                                                                                      | CoreAudio failed to prepare an out-of-process converter, most commonly while the simulator audio route is settling. The numeric code alone does not identify an app failure.                                                                                                                                                                                                                                            | Ignore an isolated line when recording and playback work. Reproduce on a physical device and inspect the active `AVAudioSession` route if audio is unavailable, silent, or interrupted.                                                                                                                                                                                                                                                                                          |
| `_dictationButton not yet initialized`, `System gesture gate timed out`                                                                                       | UIKit accessibility/dictation setup or a system gesture recognizer missed its timing window.                                                                                                                                                                                                                                                                                                                            | Treat as framework noise unless the matching dictation control, gesture, or transition visibly fails.                                                                                                                                                                                                                                                                                                                                                                            |
| `PostHog identity buffered until SDK configuration completes`                                                                                                 | Expected defensive path if identity arrives before setup in a future startup order.                                                                                                                                                                                                                                                                                                                                     | Should be rare because Supabase configures PostHog before auth listening.                                                                                                                                                                                                                                                                                                                                                                                                        |
| `Environment configuration degraded: Debug simulator is using production Supabase...`                                                                         | A Debug simulator resolved the production project. This is a warning, not a network block; auth, reads, writes, and anonymous-user creation still proceed.                                                                                                                                                                                                                                                              | Prefer local/staging for routine work. For a deliberate production smoke test, avoid reinstalling/clearing the session and set the documented scheme override only for that run.                                                                                                                                                                                                                                                                                                 |
| `DEBUG OVERRIDE ACTIVE: the advisory local free-scan meter is disabled...`                                                                                    | A DEBUG-only Settings or `MERIAN_DISABLE_FREE_SCAN_LIMIT=1` override is active. Release/TestFlight must not emit it. The server quota remains enforced.                                                                                                                                                                                                                                                                 | Clear the debug feature-flag/environment override when validating normal free-tier UX. If this appears in a Release build, stop the release and inspect the build configuration.                                                                                                                                                                                                                                                                                                 |
| `None of the products registered in the RevenueCat dashboard could be fetched from App Store Connect (or the StoreKit Configuration file...)`                 | RevenueCat fetched its offering metadata, but StoreKit could not resolve the mapped products. A successful RevenueCat login does not validate product availability.                                                                                                                                                                                                                                                     | First fix the selected store environment: Test Store key/products for fast simulator testing, or an attached StoreKit configuration/App Store Connect products with the production iOS key. Then verify the current offering returns `pro_week` and `pro_annual`.                                                                                                                                                                                                                |
| `RevenueCat returned no current offering`, `current offering has no available packages`, or `missing required products`                                       | StoreKit returned far enough for the app's own offering policy to run, but the dashboard-selected offering is absent or incomplete. Required product IDs are `pro_week` and `pro_annual`.                                                                                                                                                                                                                               | Fix RevenueCat current-offering selection and package mapping, then repeat the paywall smoke test.                                                                                                                                                                                                                                                                                                                                                                               |
| `RevenueCat is already using the same appUserID`                                                                                                              | The SDK was asked to log in the already-cached Supabase UUID.                                                                                                                                                                                                                                                                                                                                                           | Benign when followed by `RevenueCat login succeeded`; investigate only if identity or entitlement state is wrong.                                                                                                                                                                                                                                                                                                                                                                |
| `/revenuecat-webhook` returns `401`                                                                                                                           | The configured bearer credential or raw-body HMAC did not verify, or the signed timestamp fell outside the five-minute replay window. The handler performs no database or provider work.                                                                                                                                                                                                                                | Compare the RevenueCat integration's Authorization and HMAC configuration with the GitHub `Production` secrets, check delivery timestamps for clock drift, and rotate through the supervised runbook. Never disable HMAC or widen the replay window to clear retries.                                                                                                                                                                                                            |
| `[revenuecat-webhook] Required RevenueCat secrets are unavailable.`                                                                                           | One of the bearer, HMAC, or `sk_` server API credentials is absent or fails the runtime shape check. The route intentionally returns `503`.                                                                                                                                                                                                                                                                             | Configure `REVENUECAT_WEBHOOK_SECRET`, `REVENUECAT_WEBHOOK_SIGNING_SECRET`, and `REVENUECAT_SECRET_API_KEY` in GitHub `Production`, dispatch the Supabase deploy workflow, and confirm the secret-synchronization step succeeds. Do not log secret values.                                                                                                                                                                                                                       |
| `[revenuecat-webhook] RevenueCat CustomerInfo returned HTTP ...` or `Authoritative entitlement lookup failed`                                                 | The signed event was accepted, but RevenueCat's authoritative subscriber lookup timed out, was rate-limited, rejected the server key, or returned invalid state. No tier mutation was attempted.                                                                                                                                                                                                                        | Check RevenueCat status and the dedicated server key/project, retain non-2xx delivery retries, and compare the eventual CustomerInfo with the database ledger after recovery. Never infer access from `event.type`.                                                                                                                                                                                                                                                              |
| `[revenuecat-webhook] Database transition failed (...)`                                                                                                       | Durable duplicate lookup or the ordered state transaction failed. `revenuecat_event_id_conflict` means an existing ID arrived with different immutable fields; `revenuecat_user_mapping_ambiguous` means one RevenueCat identity group resolves to multiple live profiles.                                                                                                                                              | Inspect the private event/subject/customer-state tables with the owner-only runbook queries and preserve the ledger. Quarantine and escalate an event-ID conflict; for ambiguous mapping, finish the identity merge before retrying. Never update `users.subscription_tier` directly.                                                                                                                                                                                            |
| `[reconcile-revenuecat-subscribers] ... failed`                                                                                                               | The durable authoritative repair sweep could not fetch or claim-token-apply CustomerInfo. The queue releases the claim with bounded backoff; access is not upgraded from an error.                                                                                                                                                                                                                                      | Check RevenueCat/database health and the queue's `last_error_code`/attempt age with the owner-only runbook query. Let the next sweep retry; never edit tier or watermark state directly.                                                                                                                                                                                                                                                                                         |
| `{"event":"revenuecat_reconciliation_health",...}` or a failed `RevenueCat Reconciliation Health Monitor` run                                                 | The post-drain queue has an expired lease, its oldest due row crossed the 30-minute warning/60-minute critical age, or the worker reached its start-work cutoff with backlog remaining. The event contains only aggregate queue telemetry.                                                                                                                                                                              | Inspect `status`, `due_count`, `expired_claim_count`, and `oldest_due_age_seconds`, then correlate bounded queue error codes with RevenueCat/database status. Restore the dependency and let the next deadline-driven sweep drain; do not clear leases or edit tiers.                                                                                                                                                                                                            |
| `{"event":"dwca_export_step_complete","disposition":"failed",...}` or `{"event":"dwca_export_dispatch_failed",...}`                                           | A claim-fenced export phase failed and was released or made terminal, or the dispatcher could not complete discovery/health processing. Other due jobs continue when discovery remains available.                                                                                                                                                                                                                       | Correlate `request_id`, `failure_code`, and phase with database, R2, and Resend health. Preserve the job, claim, cursor, and manifest; restore the dependency and let bounded retry resume instead of manually replaying a stale token.                                                                                                                                                                                                                                          |
| DwC-A failure code `source_snapshot_changed`                                                                                                                  | At least one immutable source member no longer satisfies its creation-time privacy eligibility, or its durable invalidation fence changed. The worker makes the job terminal, revokes any application capability, and durably enqueues the uploaded/staged archive. If Resend accepted an in-flight request immediately before completion lost the fence, the email may exist but its URL no longer authorizes storage. | Treat this as expected privacy enforcement, not a retryable provider outage. Verify the job is failed, its source DTOs and private staged capability were purged, and the exact archive appears in the cleanup outbox. Let `reconcile-dwca-archive-cleanup` confirm deletion; never clear invalidation metadata, outbox rows, or republish the old URL.                                                                                                                          |
| `dwca_archive_cleanup_health` warning/critical                                                                                                                | Revoked/expired private archives are due too long, backlog crossed 25/100, or a deletion lease expired.                                                                                                                                                                                                                                                                                                                 | Repair cron/Vault/R2 configuration and let UUID-fenced retries resume. Inspect only aggregate health and restricted worker logs; never paste capability tokens/object keys into tickets or mutate leases/outbox rows.                                                                                                                                                                                                                                                            |
| `scan_deletion_health` warning/critical or `scan_deletion_cleanup_backlog`                                                                                    | Individual scan erasure reached the 15-minute/25-row warning or one-hour/100-row/expired-lease critical threshold. The signal contains aggregate queue state only.                                                                                                                                                                                                                                                      | Check the five-minute scheduler, Vault server dispatch, database, and R2 availability. Let token-fenced retry resume; never remove the permanent UUID fence or paste scan/user/media identifiers into tickets.                                                                                                                                                                                                                                                                   |
| `{"event":"auto_purge_nonbio_requested",...}`                                                                                                                 | The daily retention intake reports how many expired non-biological generations were newly fenced. `runtime_deadline_reached=true` means more selection work may remain; the event does not mean R2 or row erasure completed.                                                                                                                                                                                            | Inspect aggregate scan-deletion health and let the next selector/reaper invocations continue. Do not manually delete rows or media, remove generation fences, or treat `requested_count` as privacy-SLA completion.                                                                                                                                                                                                                                                              |
| `{"event":"auto_purge_nonbio_failed",...}`                                                                                                                    | Exact authorization succeeded, but bounded retention intake failed at the reported processing step. Only the exception class is logged; identifiers, SQL text, and provider details are intentionally absent.                                                                                                                                                                                                           | Correlate the request ID and step with database/cron health, restore the dependency, and rerun the service-only intake. Existing fenced jobs remain owned by `reconcile-scan-deletions`; never fall back to direct URL capture or inline deletion.                                                                                                                                                                                                                               |
| `r2_bulk_delete_failed`                                                                                                                                       | One or more bounded R2 object deletes returned a non-2xx/non-404 result or timed out. Object URLs and provider bodies are intentionally omitted.                                                                                                                                                                                                                                                                        | Correlate the aggregate count/time with R2 status and the owning deletion/finalization worker. Restore the dependency and retry the durable job rather than logging URLs or bypassing completion.                                                                                                                                                                                                                                                                                |
| `{"event":"dwca_unstaged_archive_delete_failed",...}`                                                                                                         | Assembly uploaded an attempt-fenced archive, but transactional staging rejected it and the compensating R2 delete also failed. No public job URL was published.                                                                                                                                                                                                                                                         | Preserve the terminal database fence, inspect the exact object through the server-only incident path, and delete that orphan after confirming it is not the winning staged key. Do not weaken the source fence or expose the URL; lifecycle policy remains the final orphan backstop.                                                                                                                                                                                            |
| `{"event":"dwca_export_queue_health",...}` or a failed `DwC-A Export and Archive Health Monitor` run                                                          | The oldest claimable job reached the five-minute warning/15-minute critical age, backlog reached 25/100 jobs, a claim expired, archive deletion reached its 15-minute/25-row warning or one-hour/100-row/expired-lease critical threshold, or the monitor could not read either aggregate health RPC. `queue_drained` means no export work is currently claimable and can coexist with leased or delayed backlog.       | Inspect `runtime_deadline_reached`, `step_limit_reached`, backlog/due counts, claim counts, archive-cleanup counts, and oldest-due ages. Repair database, cron/Vault, R2, or Resend availability and let claim-fenced draining recover. Do not clear claims or cleanup leases, rewrite cursors, or raise thresholds to silence the alert.                                                                                                                                        |
| `account_storage_erasure_deferred`                                                                                                                            | One claim-fenced R2 prefix page could not be listed, deleted, or advanced. Auth remains present because the account is still `storage_pending`.                                                                                                                                                                                                                                                                         | Check R2 credentials/provider health and the storage job cursor/attempt age. Restore the dependency and let the five-minute reaper resume. Never bypass storage completion or delete Auth manually.                                                                                                                                                                                                                                                                              |
| Scan Library/Insight sharing fails and Edge logs contain `Failed to sync public author identity: service_role authorization required`                         | The signed-in user reached the share route, but the database defense-in-depth helper did not recognize the active server-key role path. This is a server migration/key compatibility failure, not user or scan authorization.                                                                                                                                                                                           | Confirm both `20260727010340_fix_service_role_authorization_guard.sql` and `20260727013416_future_proof_server_key_boundaries.sql` are applied, run the immediate and broader read-only checks in the [privileged-routine release gate](../backend-and-data/06-supabase-deployment-runbook.md#privileged-routine-acl-release-gate), and retry both share paths. Never grant the RPC to `authenticated` or add a service key to iOS.                                              |
| Identify returns `200`, iOS saves locally, then immediate owner status is `not_found`; Explore reports `Scan not found` and Insight Field Chat is unavailable | The shared `public.scans` owner row is missing. For a brand-new scan this is a stale/incorrect `identify-multimodal` durability deployment or a new severity regression, not scan age.                                                                                                                                                                                                                                  | Verify production deployment records tie `identify-multimodal`, `check-scan-status`, and `share-scan-to-explore` to the reviewed SHA; inspect the owner-scoped ingestion job under restricted access; then run the [owner-row rollout smoke matrix](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout). Do not ask the customer to rescan as remediation, grant direct scan writes, or manually insert a row.                 |
| Opening Scan Library repeats signing, successful R2 PUTs, `failed_retryable / background_ingestion_failed` status, and one-second wakes without any Identify request | Build 1.0.2 (235)'s upload/status deadlock erased retry authority on upload success, then treated the same failed generation as permanently server-owned. The migrated-store variant lost the queued-scan copy while the durable-job copy survived, causing every cycle to persist retry one. Overlapping Library/scheduler/reconnect/URLSession replay wakes compounded the probes and logs; presentation refresh itself is not retry authority. | Require the `server_retryable_failure` latch/count to reconcile both durable copies, advance from their monotonic maximum, and survive re-stage; require the replay/orphan driver to be process-local single-flight with at most one trailing pass; then verify one delayed preflight sends Identify. Release the corrected iOS state machine; do not clear queue rows, rotate UUIDs, or make the presentation refresh loop dispatch work. |
| An older build logs `/get-explore-media-incidents … bytes=2`, followed by an invalid-response error while opening Scan Library | The old ambiguous `bytes` field measured the two-byte `{}` request, not the response. It cannot prove that the handler returned `[]` or identify the malformed response topology. This is media-alert contract drift, not evidence that a scan or post is missing. | Confirm the handler SHA and canonical `{data:[]}` response. In a corrected build, use `status`, `requestBytes`, and `responseBytes` as distinct fields. Corrected iOS also accepts a defensively retained exact direct-array topology and maps every other malformed 2xx body to `invalidResponse`; do not synthesize an incident or retry scan analysis. |
| A new scan shares successfully but an existing missing row reports `media_reconciliation_abandoned`, then recovery-capable `/check-scan-status` returns generic 503 | The primary Explore route is healthy; the legacy record failed at the guarded owner-recovery database boundary before restore signing or PUT. The reason is eligible only with matching composite dead-letter/quota/media-lifecycle proof. | Under restricted access, inspect all exact normal/replay reservation states and ordered commit/fail timestamps, the latest-authority/dead-letter chronology, producer-generation evidence fields, immutable migration-time legacy dead-letter-ID snapshot, private rollout cutoff, and both moderation failure reasons. Verify migrations `20260729173000_recover_media_abandoned_owned_scans.sql` and `20260729200000_harden_media_abandoned_scan_recovery_proof.sql`, privileged grants, quota-authority retention, both exact no-write RPC readiness probes, and matching Identify/signer/status/share versions. Unproven abandonment, active attempts, unsnapshotted or post-cutoff unstructured evidence, incomplete safety evidence, and current/later policy authority must remain closed. |

For a Debug/TestFlight offline smoke signed in as `erdener.emre@gmail.com`, use
Settings → Beta Diagnostics → **Generate offline queue diagnostics** after
the scan completes and share the artifact before deleting the observation.
Prefer this bounded durable ledger
over retaining a high-volume console stream. It supplies app version/build,
embedded source revision/fingerprint/state, lifecycle kinds, timestamps,
retry/error codes, HTTP status, and server status/stage while excluding media
paths/payload contents, descriptions, Field notes, location/GPS, raw metadata,
and arbitrary free-form messages. Every row section is capped at 500; retained
error/status/stage strings must be canonical lowercase machine tokens.
| `explore_media_health_reconciliation_failed`                                                                                                                  | The scheduled worker could not claim/check its batch or required R2 read configuration is unavailable. No client/CDN failure is converted into missing state.                                                                                                                                                                                                                                                           | Verify the dedicated bucket-scoped Object Read credentials, Supabase/Vault dispatch, and provider health. Review recent aggregate reconciliation-run rows; never bulk-mark media healthy or missing.                                                                                                                                                                                                                                                                             |
| `explore_media_health_reconciliation_runs.status = partial_failure`                                                                                           | One or more leased origin checks or result writes failed while the bounded run continued.                                                                                                                                                                                                                                                                                                                               | Correlate the sanitized per-row reasons with lease expiry, R2 status, and database health. Let retry scheduling recover dependency failures; sample object state directly before operator repair.                                                                                                                                                                                                                                                                                |
| `LocalImageLoader: remote media HTTP failure host=media.merian.app status=404`                                                                                | The CDN/R2 path answered successfully but the referenced object is absent. This is different from an offline/transport failure. Repeated 404s for one owner's images across Scan Library and Explore indicate shared object loss, even when Postgres rows still exist.                                                                                                                                                  | Inspect owner-scoped URL/key samples and compare another owner's media without logging complete URLs. Run the storage-claim invariant and incident procedure; do not “fix” rows by hiding posts or marking scans archived.                                                                                                                                                                                                                                                       |
| `LocalImageLoader: recovered durable scan image from Documents host=media.merian.app`                                                                         | A strongly evidenced local file was rendered instead of the durable URL. Cloud state may still be missing.                                                                                                                                                                                                                                                                                                              | Keep the app online and open the Scan Library so the repair actor can inspect/queue the object. Require the cloud repair success log and direct object/surface verification before calling it restored.                                                                                                                                                                                                                                                                          |
| `Cloud scan image repair restored ... scan record(s) and ... Explore media record(s).`                                                                        | The owner-authenticated repair endpoint promoted a new durable object and committed the atomic URL replacement. Counts contain no identifiers.                                                                                                                                                                                                                                                                          | Verify the new durable URL loads in Scan Library and the matching Explore post. A success for one URL does not imply unmatched account media was recovered.                                                                                                                                                                                                                                                                                                                      |
| `Cloud scan image repair paused after a failed request; retrying later.`                                                                                      | Inspection, signed upload, promotion, or atomic persistence failed; the in-memory client queue pauses for 15 minutes to avoid spinning.                                                                                                                                                                                                                                                                                 | Correlate the request ID with sanitized Edge logs and R2/Supabase availability. Preserve the local source file, fix the dependency/deployment, and let a later library refresh retry.                                                                                                                                                                                                                                                                                            |
| `field_trip_action_rejected`                                                                                                                                  | The Edge function received an unknown action; the structured field contains at most 64 characters and omits every other request field plus the derived user ID.                                                                                                                                                                                                                                                         | Compare the deployed `field-trips/actions.ts` allowlist with the client version. Usually indicates a stale client or a server action that was not deployed.                                                                                                                                                                                                                                                                                                                      |
| `Failed to register push device: invalid regular expression: invalid repetition count(s)`                                                                     | The database still has the obsolete APNs-token check using the unsupported PostgreSQL `{32,512}` regex bound. Receiving an APNs token from iOS does not mean the server saved it.                                                                                                                                                                                                                                       | Confirm migration `20260720174209_fix_push_device_token_constraint.sql` is deployed, then trigger notification-permission synchronization and require `/register-push-device` to return success.                                                                                                                                                                                                                                                                                 |
| Missing valid `aps-environment` entitlement                                                                                                                   | The signed app cannot register correctly with APNs.                                                                                                                                                                                                                                                                                                                                                                     | Inspect the archived app's signed entitlements, the explicit App ID capability, and the distribution provisioning profile. Release must resolve `APS_ENVIRONMENT=production`.                                                                                                                                                                                                                                                                                                    |
| `Invalid frame dimension` or non-finite SwiftUI geometry near Explore detail/audio                                                                            | A proposed layout or playback progress contained `NaN`/infinity/non-positive values.                                                                                                                                                                                                                                                                                                                                    | Current layout and spectrogram policies sanitize these values. Reproduce only if a new frame/offset calculation bypasses `ExploreDetailZoomLayoutPolicy` or `AudioSpectrogramSeekingPolicy`.                                                                                                                                                                                                                                                                                     |
| `AttributeGraph: cycle detected through attribute ...`                                                                                                        | SwiftUI detected a dependency cycle. The numeric attribute is process-local and does not identify a source view by itself. Capture previously combined eager off-screen pages, nested SwiftUI scroll containers, sheet state, and layout-preference feedback.                                                                                                                                                           | Record the screen and interaction that reproduce it, then use Instruments' SwiftUI View Properties instrument. Confirm the pager still uses `LazyHStack`, Describe still uses its UIKit vertical-scroll boundary with lifecycle/sheet ownership outside the pager, and the capture bar still uses a fixed layout reservation. Cold-launch all three configurable first modes with `AG_PRINT_CYCLES=3`; guard any new layout-derived state writes with equality/tolerance checks. |

For a monitor-only DwC-A failure, inspect `monitor_error_code` before queue
fields. `catalog_contract_missing/archive_cleanup` means production does not
currently expose the required zero-argument cleanup-health RPC; queue values are
deliberately unavailable, not zero. Verify migration history and the routine
signature/grant, refresh the PostgREST schema only after the routine exists, and
rerun the same SHA. Never disable the independent monitor to clear this signal.

### Healthy startup and sync signals

Use nearby application logs to decide whether a framework warning is paired with
a real failure:

- `ModelContainer bootstrap diagnostics` identifies the installed binary with
  `app`, `source`, `sourceFingerprint`, and `sourceState`. TestFlight/release
  evidence must match the intended Git revision and release-source fingerprint
  and report `sourceState=clean`. A familiar app/build number with another
  source value is another binary; `source=unavailable` identifies a build made
  before provenance embedding and cannot verify later remediation.
- `PostHog initialized` followed by `AppTelemetry initialized with PostHog`
  confirms telemetry setup. Identification may happen later after Supabase
  restores the session.
- A successful initial Auth session plus HTTP success entries for feed, Field
  trips, unread count, or species dictionary indicates that the client reached
  Supabase. A tiny response body can be a legitimate zero/empty response; use
  HTTP status and decoded behavior, not byte count alone.
- One empty active-goal refresh can issue two `field-trips` requests by design:
  `capture_context`, followed by `template_detail` for the optional
  introduction. Two repeated response-size pairs during one startup indicate
  duplicate refresh ownership and should be checked against the Capture
  appearance/account paths.
- `syncPendingScans skipped because sync active` is the expected single-flight
  guard. It is not a dropped scan; the existing task owns the work.
- `Received APNs device token from the system` confirms only the Apple callback.
  Server registration is healthy only when no subsequent remote-registration
  error appears. Migration `20260720174209_fix_push_device_token_constraint.sql`
  was applied to the linked hosted project on 2026-07-20. Seeing the invalid
  repetition error after that date usually means the app is pointed at a
  different or stale Supabase project; compare that project's migration history
  before changing the client or Edge Function regex.
- Preferred-name synchronization ending with `0 local, 0 remote, 0 pushed` is a
  healthy no-op. Matching values and matching tombstones should not be
  rewritten.
- One slower request is a sample, not a regression. Compare repeated p50/p95
  timing before assigning endpoint work, and correlate latency with a failed
  status or visible delay.

When reviewing a log bundle, record the app version/build, embedded source
revision/fingerprint/state, simulator versus physical device, OS version,
screen/action, and whether the user observed a failure. Absence from one bundle
means only “not reproduced in this run”; it does not prove an APNs, signing, or
production configuration issue is fixed.

---

## Scan Submission, Field Chat, and Explore Triage

Treat Capture → Identify → Insight → Field Chat / Explore as one joined
durability path. A provider success line does not prove scan success; the shared
HTTP-success boundary begins only after exact-owner scan read-back. A fresh,
provider-owning multimodal success additionally requires complete-last canonical
media finalization. A later same-UUID success marked
`X-Merian-Idempotent-Replay: reconstructed` may be served from that exact owner
row while canonical repair remains retryable, without another provider call.
Compatibility routes attempt the same finalizer synchronously; their additional
immediate fallback leaves a retryable ledger after the exact owner row has
already committed.

Start with one server-generated `X-Request-ID` and keep raw correlation in the
restricted incident view. Never paste Auth/user/scan UUIDs, IP addresses, object
keys, media URLs, filenames, coordinates, request bodies, provider payloads, or
raw database errors into tickets, release artifacts, chat, or aggregate
dashboards.

### Triage sequence

1. **Handler execution:** verify fixed `X-Merian-Handler: 1`. A platform
   `404 NOT_FOUND` without the marker means the function did not execute and is
   not evidence of a missing scan.
2. **Stable generation:** verify the client retained one scan UUID and one
   analysis idempotency key across foreground/background retries.
3. **Media transport:** for inline stills, confirm the durable staged-image key
   set is empty. For queued media, confirm signing returned one exact
   owner-prefixed key and asset/session identity for every requested item.
4. **Profile prerequisite:** inspect `*/scan_user_profile_unavailable`.
   `public_author_name`/username constraint failures after provider work mean
   the Auth-backed profile prerequisite migration or function bundle is stale;
   do not restore the partial users-table upsert.
5. **Provider boundary:** establish whether quota was committed and Gemini was
   dispatched. Never refund committed usage after dispatch.
6. **Ledger stage:** inspect the exact owner `scan_ingestion_jobs` status,
   stage, terminal reason, lease, manifest checksum, and paired sanitized
   intent.
7. **Owner row:** prove the exact `(scan_id, user_id)` row exists or is absent.
   A thrown PostgREST response alone is neither proof.
8. **Canonical media:** verify every genuine claimed source has one compatible
   capture lifecycle row and every promoted retained URL has a ready canonical
   image/video/audio representation. For video, do not classify sampled
   inference-frame URLs in the compatibility image array as missing standalone
   images; require the canonical playback row and only genuine display images
   from `captured_media` or the legacy standalone-image prefix.
9. **Persistence class:** classify committed, definitely rejected, or unknown
   before quota/media cleanup.
10. **Downstream check:** only after owner durability is proven, reproduce Field
    Chat preflight and Explore publication on that same scan.

### Structured events

| Event                                                                                                                                                                                 | Meaning                                                          | Action                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `generate_upload_urls_asset_persistence_failed`                                                                                                                                       | URLs were generated but compatible lifecycle registration failed | Start no PUT; inspect owner/scan/key rows, uniqueness, and six-source cap              |
| `*/scan_ingestion_setup_failed`                                                                                                                                                       | Atomic job+intent setup failed before provider                   | Keep local media; verify migration/schema/grant parity                                 |
| `*/scan_user_profile_unavailable`                                                                                                                                                     | Exact Auth-backed profile prerequisite failed                    | Check Auth identity, retirement/deletion fences, migration, and privileged routine ACL |
| `*/gemini_failed`                                                                                                                                                                     | Provider attempt failed after quota commit                       | Keep retryable ledger; do not refund dispatched usage                                  |
| `identify/parse_failed`, `identify-describe/parse_failed`, or `audio_spec/parse_failed`                                                                                               | Provider JSON was malformed                                      | Expect retryable HTTP 503 and retained offline job                                     |
| `*/wire_contract_failed`                                                                                                                                                              | Final server-enriched response violated the executable contract  | Expect HTTP 502 `identify_response_invalid` and retained retryable ledger              |
| `multimodal/background_ingestion_failed`, `identify-describe/background_ingestion_failed`, `audio_spec/background_ingestion_failed`, or legacy Identify `background_ingestion_failed` | Required persistence/finalization failed                         | Prove owner row and media topology; do not infer rollback from exception               |
| `multimodal/scan_persistence_failed`                                                                                                                                                  | Current durable success boundary did not complete                | Expect 503; poll same UUID and preserve unknown-state resources                        |
| database `canonical_scan_media_incomplete` on a video generation                                                                                                                     | Canonical projection lacks a ready owner media row, or the video projection migration is stale | Verify migration `20260729012153`, ready playback/audio/display rows, and captured timeline; never manufacture inference-frame image rows |
| `multimodal/observation_rejected`                                                                                                                                                     | Terminal media/policy rejection                                  | Confirm no scan and terminal fence; never owner-recover it                             |
| `explore/restored_media_persistence_unconfirmed`                                                                                                                                      | Restored owner-media update may have committed                   | Preserve promoted media; retry exact owner share                                       |
| `explore/restored_media_rollback_partial_failure`                                                                                                                                     | A proven rollback could not remove all known objects             | Immediate storage reconciliation; never blanket-delete prefixes                        |
| `scan_image_repair_persistence_unconfirmed`                                                                                                                                           | Atomic URL repair may have committed                             | Preserve replacement and retry inspect                                                 |
| `scan_image_repair_rollback_failed`                                                                                                                                                   | Definite-rejection cleanup failed                                | Reconcile the exact known replacement only                                             |

Producer namespaces are `multimodal`, `identify`, `identify-describe`, and
`audio_spec`. The compatibility Identify route retains the older unprefixed
`background_ingestion_failed` event, and multimodal emits `wire_contract_failed`
without a separate `parse_failed` event.

### Healthy joined signals

- An inline foreground still has bytes but no staged image source keys.
- A queued generation becomes staged only after callbacks record the exact full
  expected server-key set; task-list disappearance is not counted.
- Identify `200` is followed immediately by `/check-scan-status` `found`.
- A fresh unmarked multimodal success has owner ledger
  `complete / media_finalization_complete`.
- A video success has one ready playback item with its poster; sampled
  inference frames do not appear as standalone display media.
- A marked reconstructed replay has the exact durable owner row and no second
  provider dispatch; its canonical ledger may still be retryable and must drain
  through reconciliation.
- Compatibility success normally has that same completion. A post-row
  `failed_retryable` fallback is recoverable rather than healthy and must drain
  through same-UUID canonical reconciliation without provider redispatch.
- A scanless retryable generation writes one durable latch, may re-stage once,
  and dispatches one delayed Identify; it does not alternate signing, PUT, and
  status indefinitely.
- Simultaneous Library, scheduler, reconnect, and URLSession replay wakes run
  one reconciliation plus at most one trailing pass, never overlapping probes.
- While Scan Library is open, unchanged queue/record snapshots and throttled
  duplicate pipeline kicks emit no refresh diagnostics.
- Repeating an ambiguously delivered UUID returns marked idempotent replay
  without another provider dispatch.
- Field Chat preflight finds the same owner scan before `/insight-chat`.
- Explore share returns a published post with at least one saved eligible
  `explore_post_media` row.

Any current Identify `200` followed by owner `not_found`, Field Chat
`scan_not_ready`, or Explore `Scan not found` is a severity incident even if
guarded recovery later succeeds.

See the
[normative joined reliability contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
and
[production rollout/incident triggers](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout).

---

## Explore Video Playback Triage

Explore feed/detail video playback logs use `MerianLog.exploreVideo`. In
Console.app or Instruments, filter with:

```text
subsystem:com.merian.app category:ExploreVideo
```

Useful event names:

| Event                                                    | Meaning                                                                                                                                    |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `active player=... surface=...`                          | The scoped coordinator selected the only Explore player that should be playing. Other visible players should pause after this.             |
| `overlay began` / `overlay ended`                        | An Explore sheet or UIKit share surface changed the coordinator's overlay depth. Playback should resume only when depth returns to zero.   |
| `pause-overlay` / `schedule-overlay-resume`              | `ExplorePublicMediaView` converted a covering sheet into a recoverable interruption and queued a resume after dismissal.                   |
| `configure-rebuild` / `layer attach` / `layer dismantle` | The player or `AVPlayerLayer` was rebuilt. These should appear after sheet interruption recovery, not during ordinary healthy playback.    |
| `status-change`                                          | The underlying `AVPlayer.timeControlStatus` changed. Pair this with `pause-recoverable`, `unexpected-pause-confirmed`, or watchdog events. |
| `recovery-watchdog-passed` / `recovery-watchdog-failed`  | The recovery attempt either reached `.playing` or left the visible play control as the user-facing recovery path.                          |
| `tap-repair-hidden-control`                              | A hidden, unhealthy video tap repaired/revealed playback instead of routing the feed card to detail.                                       |

Feed audio/video interaction is intentionally split before these recovery paths:
the centered 96-point zone always owns Play/Pause (and center double-tap Like),
while the surrounding media owns detail navigation. If a center tap opens
detail, inspect `ExploreFeedMediaInteractionPolicy`, the playback overlay
`zIndex`, and competing full-media gestures before changing recovery logic.

If a video freezes after a sheet closes, first check that every covering
Explore-hosted sheet owns exactly one
`.exploreVideoOverlayLifecycle(isPresented:reason:)` token, or that a UIKit
presenter ends the token returned by `beginOverlay(reason:)`. Do not reintroduce
global `NotificationCenter` playback notifications; nested sheet depth is what
keeps dismissal order deterministic.

---

## Performance Logging Pattern

Time-sensitive operations log their duration using `CFAbsoluteTimeGetCurrent()`:

```swift
let start = CFAbsoluteTimeGetCurrent()
// ... work ...
MerianLog.general.debug("⏱️ operation completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
```

### Benchmark Timing (`[⏱ BENCH]`)

The inference pipeline emits structured `[⏱ BENCH]` markers at each stage to
make latency breakdowns visible without an attached profiler. These use `.debug`
level and are filtered by the prefix in the Xcode console or Console.app.

**iOS — capture submission, networking, and `InferenceEngine.swift`** (filter in
Xcode console: `⏱ BENCH`):

```
[⏱ BENCH] tap→durable queue: 0.041s
[⏱ BENCH] context grace: 0.150s timed_out=true
[⏱ BENCH] non-visual context wait: 0.482s
[⏱ BENCH] URLSession request_upload=0.082s ttfb_after_upload=4.101s response_transfer=0.022s
[⏱ BENCH] HTTP identify-multimodal auth=0.006s transfer+server=4.205s status=200 requestBytes=183424 responseBytes=7824
[⏱ BENCH] Server-Timing auth;dur=3.1, body_read;dur=11.8, tier;dur=0.4, pre_gemini_db;dur=7.2, gemini;dur=4189.0, dictionary;dur=5.6, post_gemini;dur=8.1, edge_total;dur=4223.4 region=...
[⏱ BENCH] Response parsing: 0.009s bytes=7824
[⏱ BENCH] Result persistence: 0.061s
[⏱ BENCH] response→first-result state: 0.082s
[⏱ BENCH] tap→first rendered frame: 4.478s
```

The first timestamp is taken when Analyze is tapped, before queue persistence or
environmental context. The final value comes from a one-shot UIKit draw probe
after the result view participates in its first display pass; awards and Field
Trips are intentionally outside that boundary. URLSession task metrics separate
request upload, time to first byte, and response transfer.
`X-Merian-Constrained-Network` tags the Edge request, and the response exposes
the privacy-safe `Server-Timing` breakdown plus `X-Merian-Edge-Region`.
The HTTP marker reports request and response byte counts separately. Builds
before this correction emitted one ambiguous `bytes` value that was the request
body size; never use that legacy field as response-shape evidence.

**Edge Function — `identify-multimodal/index.ts`** (Supabase Dashboard → Edge
Functions → identify-multimodal → Logs):

```
{"event":"multimodal/latency","tier":"pro","model":"gemini-2.5-pro","image_count":2,"payload_bytes":312640,"edge_region":"...","constrained_network":false,"auth_ms":3,"pre_gemini_db_ms":8,"gemini_latency_ms":4876,"dictionary_hydration_ms":6,"post_gemini_ms":9,"edge_total_ms":4925}
```

`gemini_latency_ms` stops immediately after the single `generateContent` call.
Do not add database work, candidate hydration, external enrichment, ingestion,
or response serialization to this timer. Tags intentionally omit user ID, scan
ID, species, coordinates, object keys, and media contents. The production
dashboard should segment p50/p95 by tier, model, image count, payload bytes,
Edge region, and constrained-network state.

Idempotent completion uses three structured events:
`multimodal/idempotent_completion_replayed` for a retry that finds completion
immediately, `multimodal/concurrent_completion_replayed` after bounded
coalescing with the winning invocation, and
`multimodal/recovery_completion_replayed` when the ingestion claim reports
already complete. They contain only restricted scan UUID plus replay source
(`stored` or `reconstructed`); keep them in access-controlled Edge logs and use
aggregate counts in dashboards. A current scan-route replay conflict reaching
iOS without one of these events is a release/version-skew signal.

---

## CircuitBreakerManager Logging

`CircuitBreakerManager` logs its state transitions via `MerianLog.general`:

```
CircuitBreakerManager: Circuit Tripped! Routing all network requests to local Field Queue.
CircuitBreakerManager: Circuit Reset. Resuming standard network requests.
```

If you see the "Circuit Tripped" message, it means 2+ consecutive network
failures occurred. The circuit auto-resets after 15 minutes. During the tripped
period, all new captures route directly to the offline queue — no network
attempts are made.

---

## Comment Reply Diagnostics

Comment reply loading intentionally does not log every SwiftUI `.task` start,
guard exit, identifier, reply count, success, or cancellation. Those lifecycle
events are high-volume, cancellation is expected during view replacement, and
raw `print()` tracing can expose public-comment identifiers while polluting test
and release logs.

An unexpected preview or full-thread fetch failure emits one
`MerianLog.network.error` entry. Only the localized failure description is
included and it is marked private; comment IDs, reply payloads, draft text, and
counts are omitted. The view model still records its retry state and presents
the customer-safe `ExploreErrorFormatter` message. Cancellation remains silent
and must not set failure state.

Use `ExploreReplyLoadingStateTests`, the reply-thread render-state tests, and a
debugger breakpoint around `loadReplyPreviewIfNeeded` / `loadReplies` when
investigating lifecycle races. Do not reintroduce `[RepliesDebug]`,
`[UIRepliesDebug]`, or identifier-bearing `print()` calls. Hosted iOS CI obtains
failed names and assertion text from the structured `.xcresult`; raw unified
logs are only a fallback for build failures.
