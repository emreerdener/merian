# Naturebook Documentation

This directory is the technical master reference for Naturebook's native iOS
application, public web frontend, Supabase PostgreSQL backend, Cloudflare R2
networking, and hardware orchestration logic. The repository, Xcode project,
targets, modules, bundle IDs, persistence, and backend identifiers retain Merian
as their permanent engineering identity.

## Current Snapshot

- **App targets**: iOS app (`apps/ios/Merian/`), watchOS companion
  (`apps/watch/MerianWatch/`), Explore WidgetKit extension
  (`apps/ios/widgets/Explore/`), Messages extension
  (`apps/ios/messages/MerianMessagesExtension/`), unit tests, and UI tests.
- **Web frontend**: Next.js + Mantine app in `apps/web/`, serving public Explore
  share pages and UUID-first readable Species Dictionary pages on the canonical
  `naturebook.earth` origin while retaining `merian.earth` as a legacy redirect
  and AASA compatibility host.
- **Internal admin**: isolated Next.js + Mantine app in `apps/admin/`, intended
  for `admin.naturebook.earth`; Google OAuth + TOTP AAL2 and narrow database
  RPCs only. Its frozen dependency graph, syntax-aware public-environment
  allowlist, required GitHub quality check, and required Vercel Deployment Check
  form an independent production gate. See
  [`backend-and-data/10-internal-admin.md`](./backend-and-data/10-internal-admin.md)
  and the
  [`backend-and-data/11-internal-admin-operations.md`](./backend-and-data/11-internal-admin-operations.md)
  operator runbook.
- **Deployment target**: iOS 17.2 for the app and widget; watchOS 10.0 for the
  companion target.
- **Project source of truth**: `project.yml` via XcodeGen. `Merian.xcodeproj` is
  committed for convenience and should be regenerated after project-structure
  changes.
- **Compiled iOS release assurance**: Build-relevant pull requests and pushes to
  `main`, plus every merge-queue commit and manual dispatch, use Xcode 26.6 to
  execute the complete unit-test target and deterministic queued-scan completion
  UI smoke, then independently inspect an unsigned Release archive from the
  exact workflow SHA. Repository rules must require the stable
  `iOS Build and Test / Production readiness` result; the focused Startup Safety
  lane is supplementary. See the
  [`testing strategy`](./development-guides/08-testing-strategy.md#compiled-ios-ci-gate)
  and
  [`release runbook`](./development-guides/14-ios-release-versioning.md#daily-development-and-ci).
- **Prelaunch access and purchase QA**: Release and TestFlight use the normal
  free/Pro meter and authoritative server quota; unlimited meter bypasses are
  DEBUG-only. Testers can still open Settings → Plan directly. Debug simulator
  purchase tests use an explicitly selected RevenueCat Test Store or StoreKit
  configuration; TestFlight uses the production iOS key and App Store Connect
  products.
- **Backend subscription integrity**: RevenueCat webhook delivery requires a
  configured bearer credential, raw-body HMAC, and server API key. Supabase
  reconciles authoritative CustomerInfo through a durable event ledger and
  per-user ordering watermark; duplicate, delayed, or partially failed transfer
  delivery cannot directly rewrite access. The scheduled repair worker drains
  small leased waves against a runtime cutoff, with indexed lease recovery and
  an independent oldest-due-age alert. The production deploy workflow validates
  and synchronizes all three backend credentials before function deployment.
- **Server credential and database safety**: Current opaque project keys use
  only Supabase's standard `apikey` header; only user JWTs and the temporary
  legacy service-role JWT use Bearer transport. Exposed tables require RLS,
  reviewed direct grants, and deny-by-default future ACLs. New migrations rely
  on the pinned CLI to own transaction and history boundaries rather than
  embedding transaction controls; timeout guards use session settings with
  matching resets so they remain effective during fresh replay. See
  [`backend-and-data/13-server-credentials-and-database-release-safety.md`](./backend-and-data/13-server-credentials-and-database-release-safety.md).
- **Security and reliability remediation (2026-08-03)**: Collection sync now
  admits only owner-safe IDs, staging PUTs bind exact type and size, protocol-3
  iOS serializes complimentary funding admission, redirects stay on configured
  origins, and taxonomy imports checkpoint every successfully fetched raw page.
  Production promotion remains an ordered, evidence-backed operation. See the
  [`joined remediation record`](./backend-and-data/19-security-and-reliability-remediation-2026-08-03.md).
- **Consent production readiness (2026-08-03)**: The final adult, Terms,
  third-party Google Gemini, and optional PostHog consent design is present, but
  the candidate is **blocked** by consent synchronization, analytics-withdrawal,
  and iOS test defects found in the second-pass review. App Store 18+ and paid
  Gemini billing/DPA evidence also remain operator-owned blockers. See the
  [`canonical consent readiness record`](./legal/production-consent-readiness-2026-08-03.md).
- **Current backend release verdict**: DwC-A exports are default-off for the
  initial launch at both the iOS presentation boundary and the canonical
  PostgreSQL intake/processing/download boundary. Existing nonterminal work is
  terminal, capabilities are revoked, processing cron is stopped, and durable
  archive cleanup remains active. The privacy, snapshot, public-web visibility,
  and atomic scan-finalization repairs remain installed. Base production
  promotion is still **blocked on exact-SHA evidence**, including fresh-catalog
  pgTAP, the hosted full iOS unit-test/unsigned Release-archive result, the
  frozen public-web gate, and production catalog/credential smokes. Hosted
  maximum-shape export and delivery measurements are deferred to the separate
  feature-enable gate. See
  [`backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`](./backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).
- **Development backend safety**: The tracked iOS defaults currently point to
  production Supabase. A Debug simulator emits a conspicuous warning but still
  performs real auth, reads, and writes. Routine simulator work should override
  both URL and client key to a matching local/staging project.
- **Active SwiftData schema**: `MerianSchemaV50` via
  `typealias CurrentSchema = MerianSchemaV50` in
  `apps/ios/Merian/Models/Aliases.swift`. V50 preserves the released V49 queue
  entity and adds a scan-keyed `OfflineQueuedScanGoalHint` companion through a
  lightweight migration. V49 remains the startup-repair target for older
  source-specific recovery lanes before they advance to V50.
- **Primary inference endpoint**: `/identify-multimodal` for visual, audio,
  describe, and mixed-media submissions. It owns staged media durability through
  `scan_ingestion_jobs`, sanitized `scan_ingestion_intents`, scheduled
  `replay-scan-ingestion`, and playback-video promotion gates. `/identify`,
  `/identify-describe`, and `/audio-spec` remain documented for compatibility,
  but scan-producing compatibility requests now write the same ingestion ledger;
  staged media and text-only intents can be replayed through
  `/identify-multimodal`, capped at 10 server replay claims per sanitized
  intent, while inline media remains client-retry only because raw bytes are
  never stored server-side. The shared identify boundary demotes manufactured or
  processed materials to non-biological before candidates, dictionary novelty,
  or `species_dictionary` writes can run. The active route does not return `200`
  until moderation, required media promotion, primary species resolution, scan
  insertion, and an authenticated-owner read-back all succeed. Every
  scan-producing route also coalesces the same `client_scan_id` after ambiguous
  delivery: it replays a bounded owner-scoped canonical response as `200`
  without a second provider call instead of exposing quota/ingestion `409`.
- **Scan owner-row durability and repair**: A successful current multimodal
  response guarantees that its `scan_id` is immediately usable by Field Chat,
  Explore sharing, and owner sync. A fresh request whose finalization fails
  returns retryable `503 scan_persistence_failed`; a later same-UUID marked
  replay may reconstruct from the exact owner row while repair continues,
  without another provider call. Terminal media-policy rejection returns
  customer-safe `400 observation_rejected`. For older or interrupted local/cloud
  drift, single `/check-scan-status` requests and `/share-scan-to-explore`
  accept a bounded non-media `recovery_scan`. The server defers to
  active/retryable ingestion, permits exact structured `replay_exhausted`, and
  admits `media_reconciliation_abandoned` only with matching composite
  dead-letter/quota/media-lifecycle proof. It never overwrites an existing or
  cross-owner row and restores media only through owner-scoped staging keys.
  Current/later policy, unproven abandonment, deletion, and unknown terminal
  state remains closed. A first `failed_retryable` status observation writes one
  durable local retry latch; after its delay and any required media re-stage,
  that exact latch lets the next generation-fenced preflight send Identify
  instead of blocking itself in a status/upload loop. Retry counts survive
  re-upload, use committed fresh-context reads, and stop at retained
  needs-attention state. The repository fix is not a production fix until all
  affected Edge Functions and the matching iOS build are promoted. See the
  [joined reliability contract](./backend-and-data/16-scan-ingestion-reliability-and-recovery.md),
  [failed-retryable deadlock incident](./incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md),
  [media-abandoned share incident](./incidents/2026-07-media-abandoned-explore-share-recovery.md),
  [owner-row incident report](./incidents/2026-07-scan-owner-row-durability-gap.md),
  [inline staging-manifest incident](./incidents/2026-07-inline-scan-staging-manifest-regression.md),
  [queued Insight same-ID handoff incident](./incidents/2026-07-queued-insight-same-id-handoff-regression.md),
  [video finalization incident](./incidents/2026-07-video-scan-canonical-finalization-regression.md),
  and
  [Identify idempotency incident](./incidents/2026-07-identify-idempotency-conflict.md).
- **Image-analysis latency contract**: Durable queue acceptance remains the
  mandatory gate. The eligible live-camera still path waits no more than 150 ms
  for shutter-prefetched weather/geocoding, defers its competing background
  upload until the inline body is sent, and commits parsed/persisted results
  before awards or Field trips. The Edge path uses verified ES256 claims, one
  atomic pre-inference RPC, at most one combined post-inference dictionary RPC,
  privacy-safe `Server-Timing`, and awaited durable finalization. A primary
  cache miss may require bounded Wikipedia/GBIF species resolution before
  success; analytics, group tags, and candidate enrichment remain optional
  background work. `/update-scan-context` applies late owner-scoped context
  without a second AI request. Model IDs and all inference-quality and
  unit-economics settings remain unchanged.
- **Photos share import contract**: A single image shared from iOS Photos opens
  the containing app through its alternate `public.image` document association.
  `ExternalImageImportStore` copies the file into a durable Application Support
  inbox before Capture observes it, so cold launch, onboarding, quota, and tray
  capacity cannot lose the receipt. Embedded date/GPS is read before bounded
  preparation; the normal required crop, confirmation preference, inference, and
  offline queue then apply. This path has no Share Extension, App Group handoff,
  backend import endpoint, or new Photo Library permission.
- **Camera-roll media export contract**: The default-off **Save to camera roll**
  preference automatically writes camera photos and original video recordings
  through add-only PhotoKit access. Explicit single and batch Downloads work
  independently of that preference, include retained local or approved
  `media.merian.app` video clips, and keep remote work file-backed. See the
  [canonical export contract](./features-and-hardware/27-camera-roll-media-export.md).
- **Fresh-launch presentation contract**: The Capture workspace remains the app
  root. After onboarding, the default-off **Open Explore on launch** preference
  can present the generic Explore feed once when a new process starts. It is not
  reevaluated on foreground returns. Photos/Files imports, deep links, and
  tapped notification routes always replace the generic feed with the requested
  capture, post, community, scan, or library destination.
- **Explore root-navigation contract**: Explore has exactly three bottom items:
  Observations, Field trips, and Identify. Identify owns Requests/Index.
  Requests concurrently previews 12 open cards and 10 grouped Activity rows
  under shared filters, then pushes complete **Identify requests** and
  **Identify activity** feeds. Index renders the Species Dictionary overview.
  Species and request deep links select the corresponding Identify mode before
  push. Tree/galaxy visualization remains default-off and has no MVP entry
  point.
- **Media durability safety net**: Backend deploys run a media-ingestion
  contract matrix covering image, audio, text-only, video, status, repair, and
  Explore-share seams. Production scan-media health reports include incident
  actions with owner/runbook/sample hints for each issue code. Canonical scan
  media refresh rebuilds standalone audio rows from `captured_media` and
  `audio_storage_urls`; it never requires replacing the durable R2 recording.
- **Cloud media ownership and deletion safety**: Supabase Postgres stores scan,
  post, and media-reference metadata; Cloudflare R2 stores the referenced image
  bytes. A database URL is not an object backup. Account-prefix erasure is
  claimable only from a matching `storage_pending` private deletion job after
  relational cleanup, with live profiles and owned scans acting as hard vetoes.
  The July 2026 account-scoped image-loss mitigation is present in the
  repository, but production verification and device-assisted recovery remain
  incomplete. See the
  [incident report](./incidents/2026-07-account-scoped-r2-image-loss.md).
- **Mandatory scientific-observation retention**: Every submitted scan
  contributes Scientific Data. Account deletion removes authentication,
  profile, attribution, community content, media, free-form private notes,
  semantic/public location labels, device context, and custom tags. The scan
  remains as an ownerless tombstone with exact coordinates/elevation, time,
  taxonomy, identification, environmental, quality, and provenance facts
  unchanged. Tombstones are excluded from personal and broad anonymous scan
  access; public and export projections retain geoprivacy and sensitive-taxon
  controls. This is a condition of submission without a separate opt-in or
  opt-out. See the
  [canonical retention contract](./backend-and-data/17-scientific-observation-retention.md),
  [schema contract](./backend-and-data/04-database-schema.md),
  [API contract](./backend-and-data/05-api-contracts.md), and
  [counsel review memo](./legal/terms-counsel-review.md).
- **Explore media-loss contract**: An unavailable object never auto-deletes or
  auto-unpublishes a post. Two spaced direct R2-origin `404` checks confirm
  loss; bad items are omitted, all-missing posts are reversibly quarantined,
  engagement is preserved, owners receive a recovery queue, and verified repair
  automatically restores ordinary public visibility. See
  [`backend-and-data/12-explore-media-health-and-quarantine.md`](./backend-and-data/12-explore-media-health-and-quarantine.md).
- **Public audio poster contract**: Approved standalone WAV shares generate a
  deterministic spectrogram PNG beside the durable R2 recording. The URL is
  saved in both normalized scan media and the post-owned Explore snapshot, so
  public web detail pages and social metadata reuse one cached asset. Compact
  public web grids use the species reference thumbnail instead. A bounded
  service-role worker repairs historical blanks; non-WAV legacy media remains
  playable with the speaker fallback.
- **Video media contract**: Pro video remains a short capture surface, not
  arbitrary gallery import. The app submits five sampled frames plus optional
  extracted WAV audio for inference, stages one upload-bounded playback `.mp4`
  for storage/sharing, and treats `captured_media` plus ready
  `scan_media_assets` rows as the canonical playback timeline. The client uses
  native AVFoundation stabilization only while the recording is active, then
  resets the prepared movie connection so still-photo capture retains normal
  resolution and latency. Public `has_audio` metadata is true only when
  captured-media or normalized media rows prove that an audio companion exists.
- **Moderation routing contract**: Native Explore post-content reports write the
  service-only `explore_post_reports` queue through `/report-explore-post`.
  Identification disputes alone use `/flag-issue`, `flagged_reviews`, and
  `scans.is_flagged`. Visible non-self author reports use `/report-user` and
  `user_reports` without automatically blocking the target. Identification,
  post, comment, and user sources are grouped into private review cases;
  hide/restore remains separate from explicit resolution. Anonymous public-web
  reports remain support emails with the immutable post id rather than
  authenticated database writes.

## Directory Structure

### Current Codebase Map

- **[`/codebase-map.md`](./codebase-map.md)** — Current target, folder, schema,
  SwiftData actor, feature, Edge Function, and testing inventory for this repo
  state.

### Incidents

- **[`/incidents/2026-08-ghost-merge-species-ledger-underflow.md`](./incidents/2026-08-ghost-merge-species-ledger-underflow.md)**
  — Sanitized 12-hour log evidence, semantic root cause, schema-aware ownership
  correction, four post-review release blockers, exact-version validation
  status, and closure gates for repeated Ghost-merge species-ledger underflow.
- **[`/incidents/2026-07-xcode-export-build-number-rewrite.md`](./incidents/2026-07-xcode-export-build-number-rewrite.md)**
  — Root cause and fail-closed remediation for Xcode changing a reviewed
  `1.0.2 (236)` archive into uploaded IPA build `272`, including exact artifact
  provenance, confirmed Content Delivery acceptance, the superseded command-line
  remediation, and the later Xcode-only distribution decision.
- **[`/incidents/2026-07-queued-insight-same-id-handoff-regression.md`](./incidents/2026-07-queued-insight-same-id-handoff-regression.md)**
  — Hosted Runs 100–103, same-ID route and SwiftUI task root cause, secure
  child-before-parent promotion ordering, scanning-badge accessibility-frame
  correction, complete-result toolbar recovery, and exact closure gates for
  queued Insight → Field Chat / Share handoff.
- **[`/incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md`](./incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md)**
  — TestFlight evidence, state-machine root cause, dual-copy durable retry
  authority, migrated-store mirror repair, bounded retry behavior, and release
  closure gates for the status/re-upload loop that sent no Identify request.
- **[`/incidents/2026-07-media-abandoned-explore-share-recovery.md`](./incidents/2026-07-media-abandoned-explore-share-recovery.md)**
  — New-versus-existing scan evidence, the recovery-capable status 503 boundary,
  and the composite service-only proof that reconnects eligible surviving local
  media to guarded owner-row repair and atomic Explore publication without
  reopening later policy state.
- **[`/incidents/2026-07-inline-scan-staging-manifest-regression.md`](./incidents/2026-07-inline-scan-staging-manifest-regression.md)**
  — Joined iOS/Edge/catalog root cause and fail-closed remediation for inline
  scans rejected by a phantom staged-upload manifest, including offline, Field
  Chat, Explore, and Ask the Community consequences.
- **[`/incidents/2026-07-video-scan-canonical-finalization-regression.md`](./incidents/2026-07-video-scan-canonical-finalization-regression.md)**
  — Hosted-test isolation, canonical-media projection fix, security invariants,
  and production closure gates for valid video scans rejected because sampled
  inference frames were mistaken for standalone images.
- **[`/incidents/2026-07-identify-idempotency-conflict.md`](./incidents/2026-07-identify-idempotency-conflict.md)**
  — Root cause, server response replay, exact queued-presentation recovery, and
  production exit criteria for handler-owned Identify 409 conflicts.
- **[`/incidents/2026-07-scan-owner-row-durability-gap.md`](./incidents/2026-07-scan-owner-row-durability-gap.md)**
  — Root cause, atomic compatibility recovery, customer-facing behavior, and
  production exit criteria for scans that returned identify success without a
  durable authenticated owner row.
- **[`/incidents/2026-07-supabase-edge-route-not-found.md`](./incidents/2026-07-supabase-edge-route-not-found.md)**
  — Evidence, gateway/handler classification, client resilience, rollout gate,
  and production exit criteria for the July 2026 platform route failure.
- **[`/incidents/2026-07-server-key-authorization-mismatch.md`](./incidents/2026-07-server-key-authorization-mismatch.md)**
  — Root cause, fleet-wide credential boundary remediation, watch surfaces, and
  production exit criteria for the July 2026 opaque-key authorization failure.
- **[`/incidents/2026-07-account-scoped-r2-image-loss.md`](./incidents/2026-07-account-scoped-r2-image-loss.md)**
  — Confirmed evidence, leading cause, containment, device-assisted recovery,
  unresolved scope, and production exit criteria for the July 2026
  account-scoped R2 image-loss incident.

### Product

- **[`/product/01-master-product-document.md`](./product/01-master-product-document.md)**
  — Repository-aligned product definition, implementation-status boundaries,
  current release identifiers, and high-impact corrections to the retired
  product document.

### Legal & Release Readiness

- **[`/legal/production-consent-readiness-2026-08-03.md`](./legal/production-consent-readiness-2026-08-03.md)**
  — Canonical release hold, internal consent findings, verification snapshot,
  rollout order, and external App Store/Gemini/counsel exit evidence.
- **[`/legal/terms-counsel-review.md`](./legal/terms-counsel-review.md)**
  — Internal legal working memo covering public Terms alignment, unresolved
  operator facts, provider contracts, and counsel evidence requirements.

### System Architecture

- **[`/system-architecture/01-system-architecture.md`](./system-architecture/01-system-architecture.md)**
  — Master architecture: zero-OOM infrastructure strategy and lazy-loading UX
  principles.
- **[`/system-architecture/system-overview.md`](./system-architecture/system-overview.md)**
  — High-level structural decoupling overview.
- **[`/system-architecture/02-zero-oom-and-concurrency.md`](./system-architecture/02-zero-oom-and-concurrency.md)**
  — iOS memory ceiling rules, Swift 6 concurrency constraints, and Supabase Edge
  optimizations.
- **[`/system-architecture/03-image-pipeline.md`](./system-architecture/03-image-pipeline.md)**
  — Capture → disk → cache → display image flow.
- **[`/system-architecture/04-ai-engineering.md`](./system-architecture/04-ai-engineering.md)**
  — LLMOps edge deployment constraints, inference invariants, full-pipeline
  latency instrumentation, `maxOutputTokens` limits, and API throttling.
- **[`/system-architecture/06-edge-modularization.md`](./system-architecture/06-edge-modularization.md)**
  — Domain-driven modular architecture for Supabase Edge Functions: `index.ts` /
  `db.ts` / `types.ts` separation rules and shared utility conventions.
- **[`/system-architecture/08-public-brand-compatibility.md`](./system-architecture/08-public-brand-compatibility.md)**
  — Canonical Naturebook public values, permanent Merian technical identifiers,
  link/domain compatibility, AASA exceptions, and the allowed-branding audit
  classification.
- **[`/system-architecture/09-ios-release-publisher.md`](./system-architecture/09-ios-release-publisher.md)**
  — Xcode Organizer distribution decision, CI boundary, build-number ownership,
  automatic-signing model, source identity, and promotion invariants.

### Backend & Data

- **[`/backend-and-data/01-offline-sync-pipeline.md`](./backend-and-data/01-offline-sync-pipeline.md)**
  — Zero-data-loss architecture, SwiftData queues, live/background upload
  ownership, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/02-supabase-edge-and-database.md`](./backend-and-data/02-supabase-edge-and-database.md)**
  — Supabase Postgres schemas, Edge Function runtime rules, RLS, public species
  dictionary workers, private Insight and Explore Field chat boundaries,
  service-only Identify Activity projection/read boundaries, and cron/webhook
  boundaries.
- **[`/backend-and-data/03-database-actors.md`](./backend-and-data/03-database-actors.md)**
  — SwiftData actor model: `BackgroundDatabaseActor`, `HistoricalDatabaseActor`,
  and `FileIOActor`.
- **[`/backend-and-data/04-database-schema.md`](./backend-and-data/04-database-schema.md)**
  — Physical table maps for PostgreSQL and the SwiftData persistent schemas,
  including the V41 `CapturedMediaEntry` mixed-media model, V47 offline video
  inference fields, V48 offline job records/events, V49 startup store repair,
  V50 durable queued Field trip goal hints, private Insight and per-viewer
  Explore Field chat tables, scan media assets, and Explore Community
  Identification versioned taxonomy, consensus jobs, requests, public
  projections, and internal grouped Activity projection, atomic ingestion
  setup/dictionary RPCs, deferred scan-context staging, and the private
  admin/review/audit schema plus canonical AI usage ledger, storage-erasure
  claim fencing, atomic owned scan-image reference repair, and the database-only
  Backyard Safari enrollment trigger/backfill.
- **[`/backend-and-data/05-api-contracts.md`](./backend-and-data/05-api-contracts.md)**
  — JSON mapping contracts between the iOS client and Deno Edge functions,
  including `/identify-multimodal`, `/insight-chat`, `/explore-post-chat`,
  `/field-trips` starter enrollment, preferred progress, and scan contributions,
  `/update-public-avatar`, Community Identification request/detail and grouped
  Activity endpoints,
  `/species-dictionary`, `/species-observation-stats`, `/report-user`, the
  internal admin RPC surface, Explore detail similar species, and internal cron
  workers such as Merian reference-image refresh, diagnostic `Server-Timing`,
  and `/update-scan-context`, plus the owner-authenticated `/repair-scan-image`
  inspection and recovery contract.
- **[`/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md)**
  — CI-first Supabase deployment path, required GitHub secrets, local emergency
  fallback, frozen function-local dependency configs, dependency-aware batched
  deploys, staged identification-latency and Identify Activity rollout gates,
  and post-deploy smoke checks.
- **[`/backend-and-data/07-community-taxonomy-import-checklist.md`](./backend-and-data/07-community-taxonomy-import-checklist.md)**
  — Running checklist for bounded GBIF Community Taxonomy imports, completed
  Birds batches, next offsets, and operational follow-ups.
- **[`/backend-and-data/08-startup-store-recovery.md`](./backend-and-data/08-startup-store-recovery.md)**
  — Launch-time SwiftData store recovery contract: exception bridge, store-aware
  migration selection, duplicate-checksum fallbacks, corruption-gated
  quarantine, legacy-store rescue, safe mode, auth isolation, manifest,
  telemetry, and verification.
- **[`/backend-and-data/10-internal-admin.md`](./backend-and-data/10-internal-admin.md)**
  — Private admin architecture: Google/TOTP session boundary, RBAC, admin RPCs,
  grouped review and feedback workflows, audit trail, metrics, AI ledger,
  browser hardening, and dependency/CI invariants.
- **[`/backend-and-data/11-internal-admin-operations.md`](./backend-and-data/11-internal-admin-operations.md)**
  — Internal admin setup and operations: environment, owner bootstrap,
  dependency upgrades, required GitHub/Vercel checks, deployment ordering,
  production smoke tests, price maintenance, recovery, incident response,
  rollback, and troubleshooting.
- **[`/backend-and-data/12-explore-media-health-and-quarantine.md`](./backend-and-data/12-explore-media-health-and-quarantine.md)**
  — Canonical product and engineering contract for direct-origin media health,
  reversible public quarantine, owner notification, automatic recovery, explicit
  deletion, monitoring, and production rollout.
- **[`/backend-and-data/13-server-credentials-and-database-release-safety.md`](./backend-and-data/13-server-credentials-and-database-release-safety.md)**
  — Canonical server-key/header matrix, environment resolution, internal worker
  auth, exposed-schema RLS/default ACLs, migration execution/replay safety,
  supervised index construction, orphan triage, and production exit gate.
- **[`/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`](./backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md)**
  — Implemented repairs, evidence limits, regression coverage, and exact-SHA
  promotion criteria for DwC-A version 2, revocable archive delivery, atomic
  scan finalization, and the public-web Explore boundary.
- **[`/backend-and-data/15-edge-function-fleet-review-2026-07-28.md`](./backend-and-data/15-edge-function-fleet-review-2026-07-28.md)**
  — Complete 90-function inventory, corrected cross-cutting findings, boundary
  classification, and required production evidence for the fleet-wide review.
- **[`/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](./backend-and-data/16-scan-ingestion-reliability-and-recovery.md)**
  — Normative joined contract for durable scan success, inline and staged media
  manifests, profile and identity fences, foreground/offline retry behavior,
  persistence ambiguity, guarded recovery, Field Chat readiness, Explore
  publication, security, deployment order, monitoring, and regression gates.
- **[`/backend-and-data/17-scientific-observation-retention.md`](./backend-and-data/17-scientific-observation-retention.md)**
  — Normative product and engineering contract for mandatory ownerless
  scientific-observation retention after account deletion, including the exact
  clearing boundary, durable sequence, authorization, visibility, race fencing,
  change procedure, and verification gates.
- **[`/backend-and-data/18-complimentary-pro-scans.md`](./backend-and-data/18-complimentary-pro-scans.md)**
  — Normative contract for the staged replacement of the introductory trial
  with three lifetime complimentary Pro scans, including the private ledger,
  derived balances, user-first reservation and settlement, separate Flash and
  provider quotas, protocol 3, iOS reservation safety, Ghost merge, admin telemetry,
  security, rollout, and executable verification map.
- **[`/backend-and-data/19-security-and-reliability-remediation-2026-08-03.md`](./backend-and-data/19-security-and-reliability-remediation-2026-08-03.md)**
  — Joined implementation and release record for collection ownership,
  exact-size staging uploads, serialized complimentary funding, redirect origin
  safety, taxonomy checkpointing, rollout dependencies, and production evidence.

### Features & Hardware

- **[`/features-and-hardware/01-camera-and-hardware.md`](./features-and-hardware/01-camera-and-hardware.md)**
  — AVFoundation bindings, LiDAR depth logic, Pro video stabilization
  boundaries, and ViewfinderIntelligence constraints.
- **[`/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md)**
  — RevenueCat products/offerings, Test Store/StoreKit/TestFlight purchase
  matrix, durable webhook access, paid and complimentary Pro entitlements, and
  Ghost Session identity.
- **[`/features-and-hardware/03-gamification-and-telemetry.md`](./features-and-hardware/03-gamification-and-telemetry.md)**
  — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/04-onboarding.md`](./features-and-hardware/04-onboarding.md)**
  — Four-step permission flow, final adult/Terms/Gemini/analytics consent
  surface, versioned evidence, and the combined onboarding/current-consent
  workspace gate.
- **[`/features-and-hardware/05-insight-sheet.md`](./features-and-hardware/05-insight-sheet.md)**
  — InsightSheet view architecture, mixed-media carousel handoff, species data
  rendering, persistent Field trip progress, typed routing, Field chat, and
  graceful degradation states.
- **[`/features-and-hardware/06-profile-and-gamification.md`](./features-and-hardware/06-profile-and-gamification.md)**
  — Profile public avatars, heatmap, collections, and gamification award
  calculations.
- **[`/features-and-hardware/07-feature-modules-and-ui.md`](./features-and-hardware/07-feature-modules-and-ui.md)**
  — SwiftUI architectural views and modular extraction blocks.
- **[`/features-and-hardware/08-app-intents.md`](./features-and-hardware/08-app-intents.md)**
  — App Intents integration for Siri and Shortcuts.
- **[`/features-and-hardware/09-components-guide.md`](./features-and-hardware/09-components-guide.md)**
  — Shared UI components and design system primitives.
- **[`/features-and-hardware/10-watchos-integration.md`](./features-and-hardware/10-watchos-integration.md)**
  — watchOS companion target: acoustic capture pipeline, WatchConnectivity
  delivery, and iOS receiver status.
- **[`/features-and-hardware/11-describe-and-voice-dictation.md`](./features-and-hardware/11-describe-and-voice-dictation.md)**
  — Describe capture mode: `ObservationContext` state ownership, `SpeechManager`
  AVAudioEngine + SFSpeechRecognizer pipeline, dictation task lifecycle, and
  Swift 6 concurrency guarantees.
- **[`/features-and-hardware/12-audio-listen-mode.md`](./features-and-hardware/12-audio-listen-mode.md)**
  — Audio Listen Mode: `SpectrogramActor` FFT/mel-scale DSP,
  `AudioCaptureManager` 15-second recording pipeline, live `SpectrogramView`
  Canvas UI, SNR gauge, coordinated camera-to-microphone hardware handoff, and
  the shared non-visual durability path.
- **[`/features-and-hardware/13-explore-home-screen-widget.md`](./features-and-hardware/13-explore-home-screen-widget.md)**
  — Explore Home Screen widget: image-only WidgetKit extension, App Group cache
  contract, timeline carousel behavior, and deep-link routing.
- **[`/features-and-hardware/14-explore-author-profiles.md`](./features-and-hardware/14-explore-author-profiles.md)**
  — Public Explore author profile navigation, privacy-scoped profile stats,
  non-opening public achievements, capped profile-to-scan nesting, and the
  paginated published-scan library.
- **[`/features-and-hardware/15-explore-following.md`](./features-and-hardware/15-explore-following.md)**
  — Explore Follow relationships: Following feed filter, public profile counts,
  follow notifications, block cleanup, and ghost-merge repair.
- **[`/features-and-hardware/16-species-dictionary.md`](./features-and-hardware/16-species-dictionary.md)**
  — Standalone public species dictionary page, `species-dictionary` Edge
  Function detail/catalog/user-scanned tree contracts, similar-species entry
  points from Insight and Explore detail, cache rules, content quality, media
  attribution, enrichment queue/backfill, and refresh provenance.
- **[`/features-and-hardware/17-public-web-share-pages.md`](./features-and-hardware/17-public-web-share-pages.md)**
  — Next.js public web share pages for `naturebook.earth`, including Explore
  posts, UUID-first readable Species Dictionary references, legacy-domain and
  UUID-only route compatibility, Supabase server reads, media-rights filtering,
  metadata, privacy boundaries, and Universal Links.
- **[`/features-and-hardware/18-species-observation-charts.md`](./features-and-hardware/18-species-observation-charts.md)**
  — Reusable species observation charts, local-on-device aggregation, public
  iNaturalist stats cache, canonical dictionary binding, negative caching,
  rate/deadline budgets, fenced cold population, annotation mappings, privacy
  boundaries, and verification.
- **[`/features-and-hardware/19-native-share-extensions.md`](./features-and-hardware/19-native-share-extensions.md)**
  — Native iOS extensions: shipped Messages scan library, Explore widget cache
  ownership, App Group boundaries, privacy rules, QA, and the boundary between
  extensions and the app-owned Photos document import.
- **[`/features-and-hardware/20-explore-hashtags.md`](./features-and-hardware/20-explore-hashtags.md)**
  — Explore hashtag publishing, composer suggestions, feed/detail chip behavior,
  tagged-post collections, API paths, event/BioBlitz groundwork, and Field trip
  Challenge suggestion boundaries.
- **[`/features-and-hardware/21-public-usernames.md`](./features-and-hardware/21-public-usernames.md)**
  — Canonical public username handles, edit UX, Explore display-name behavior,
  Edge update contract, and future mention boundary.
- **[`/features-and-hardware/22-geoprivacy.md`](./features-and-hardware/22-geoprivacy.md)**
  — Geoprivacy modes, backend projection triggers, local UI privacy gates,
  public Explore/export boundaries, and verification checklist.
- **[`/features-and-hardware/23-explore-comment-mentions.md`](./features-and-hardware/23-explore-comment-mentions.md)**
  — Explore comment `@username` mention eligibility, suggestion endpoint,
  notification behavior, iOS composer/link rendering, and verification.
- **[`/features-and-hardware/24-explore-bottom-menu.md`](./features-and-hardware/24-explore-bottom-menu.md)**
  — Explore launch entry points, exactly-three-item root navigation,
  Observations Feed/Map, Field trips, Identify Requests/Index, filtered request
  and Activity previews/full feeds, deep-link mode policy, stack chrome, Index
  catalog ownership, and deferred Tree/galaxy scope.
- **[`/features-and-hardware/25-field-trips.md`](./features-and-hardware/25-field-trips.md)**
  — Public Field trips/Outings, the client-staged Events rollout and release
  checklist, automatic Backyard Safari Level 1 enrollment, guided outing
  detail, progress matching, the account-cached active target indicator on
  visual Scan, focused Tips/Goals routing, active-level
  progress ring, private completed-scan thumbnails and embedded Insight
  navigation, persistent scan contribution cards, one credit per experience with
  multi-experience eligibility, tier-specific Possible-match evidence gating,
  weak-match confirmation and repair, seasonal challenges, challenge badges,
  publication snapshots, profile pins, access gating, in-app activity, and
  deferred leaderboard/prize scope.
- **[`/features-and-hardware/26-photos-share-import.md`](./features-and-hardware/26-photos-share-import.md)**
  — Single-photo document import from the iOS Photos share sheet, including URL
  routing, durable inbox ownership, EXIF context, capture staging, privacy,
  blocking/retry behavior, and physical-device QA.
- **[`/features-and-hardware/27-camera-roll-media-export.md`](./features-and-hardware/27-camera-roll-media-export.md)**
  — Automatic and explicit photo/video writes to iOS Photos, including
  default-off preference semantics, add-only permission, original-recording
  lifetime, file-backed cloud downloads, approved-host policy, cleanup,
  feedback counts, and physical-device QA.
- **[`/rfcs/explore-page.md`](./rfcs/explore-page.md)** — Explore feed and map
  product/RPC architecture, including the shipped V1 map implementation and
  follow-up recommendations.
- **[`/rfcs/active-capture-goal-context.md`](./rfcs/active-capture-goal-context.md)**
  — Accepted long-term architecture for source-agnostic goals on Capture,
  account-scoped stale-data retention, typed navigation, private source reads,
  and adding future goal providers without coupling them to the camera.
- **[`/rfcs/codebase-cleanup.md`](./rfcs/codebase-cleanup.md)** — Phased cleanup
  plan for repo hygiene, behavior-preserving file splits, and ownership cleanup.
- **[`/rfcs/species-dictionary-long-term-todo.md`](./rfcs/species-dictionary-long-term-todo.md)**
  — Long-term species dictionary TODO covering canonical identity, reference
  media normalization, public projections, enrichment queues, provenance and
  refresh, caching, licensing, and analytics.
- **[`/rfcs/geological-expansions.md`](./rfcs/geological-expansions.md)** —
  Roadmap for extending inference to rocks, minerals, and fossils.

### Development Guides

- **[`/development-guides/01-zero-oom-onboarding.md`](./development-guides/01-zero-oom-onboarding.md)**
  — Banned APIs, approved patterns, and memory debugging guide for new
  contributors.
- **[`/development-guides/02-app-lifecycle.md`](./development-guides/02-app-lifecycle.md)**
  — `AppLifecycleManager` phase contracts, fresh-launch presentation policy,
  explicit-route precedence, and trigger ordering.
- **[`/development-guides/03-feature-architecture.md`](./development-guides/03-feature-architecture.md)**
  — Feature module structure and ViewModel conventions.
- **[`/development-guides/04-logging-and-debugging.md`](./development-guides/04-logging-and-debugging.md)**
  — `MerianLog` structured logging and Xcode debugging workflows.
- **[`/development-guides/05-keychain-and-secrets.md`](./development-guides/05-keychain-and-secrets.md)**
  — Storage decision matrix, API key rules, `KeychainManager`, and
  `DeviceIdentityManager`.
- **[`/development-guides/06-error-handling.md`](./development-guides/06-error-handling.md)**
  — `NetworkError` and `APIError` cases, offline fallback patterns, and UI error
  surface mapping.
- **[`/development-guides/07-ai-agent-guidelines.md`](./development-guides/07-ai-agent-guidelines.md)**
  — Architecture constraints and conventions for AI coding agents working on
  this codebase.
- **[`/development-guides/08-testing-strategy.md`](./development-guides/08-testing-strategy.md)**
  — Swift testing isolation using in-memory SwiftData and local context mocks.
- **[`/development-guides/09-core-managers.md`](./development-guides/09-core-managers.md)**
  — Deep dive into singleton instances across Merian (e.g.
  `HardwareOrchestrator`).
- **[`/development-guides/10-safety-and-moderation.md`](./development-guides/10-safety-and-moderation.md)**
  — Gemini safety rating evaluation, abuse strike system, shadowban logic, and
  R2 media promotion pipeline, plus fail-closed Explore speech/non-speech audio
  moderation and the post-publication local playback-boost boundary.
- **[`/development-guides/11-swiftdata-and-api-gotchas.md`](./development-guides/11-swiftdata-and-api-gotchas.md)**
  — SwiftData background synchronization drops, relationship fault boundaries,
  and API envelope parsing constraints.
- **[`/development-guides/12-in-app-changelog.md`](./development-guides/12-in-app-changelog.md)**
  — Root release history, per-train App Store note source, bundled Settings
  changelog schema, writing rules, asset handling, and update workflow.
- **[`/development-guides/13-asset-catalog.md`](./development-guides/13-asset-catalog.md)**
  — Asset catalog grouping and naming rules for reusable 3D graphics, app
  assets, brand marks, and personas.
- **[`/development-guides/14-ios-release-versioning.md`](./development-guides/14-ios-release-versioning.md)**
  — Complete iOS operator runbook: repository and Apple setup, tracked release
  trains, serialized global allocation, dispatch inputs, archive/IPA evidence,
  retries, TestFlight promotion, triage, and emergency recovery.
- **[`/development-guides/15-naturebook-rebrand-rollout.md`](./development-guides/15-naturebook-rebrand-rollout.md)**
  — Ordered domain, AASA, email, Supabase, App Store, update-continuity, link,
  verification, rollback, and completion checklist for the public rebrand.

## About Naturebook

Naturebook is a native iOS application that identifies plants, animals, insects,
fungi, and indoor ecology with scientific-grade accuracy across visual, audio,
and text-described observations. It uses dynamic routing between the Gemini 2.5
Flash and Pro APIs via Supabase Edge Functions, with a full offline-first
architecture backed by SwiftData and Cloudflare R2. Merian is the stable
technical identity underneath the Naturebook product.
