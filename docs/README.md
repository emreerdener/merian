# Naturebook Documentation

This directory is the technical master reference for Naturebook's native iOS
application, public web frontend, Supabase PostgreSQL backend, Cloudflare R2
networking, and hardware orchestration logic. The repository, Xcode project,
targets, modules, bundle IDs, persistence, and backend identifiers retain Merian
as their permanent engineering identity.

## Current Snapshot

Use this page to find the owning document. Current contracts describe intended
behavior; incidents and release records retain dated evidence. The
[contributor guide](./CONTRIBUTING.md#documentation-ownership) defines those
boundaries, and the [codebase map](./codebase-map.md) inventories source owners.

| Surface                                 | Source and entry point                                                                                    |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| iOS app, widget, and Messages extension | [`apps/ios`](../apps/ios/README.md); `project.yml` is the source of truth for the generated Xcode project |
| watchOS companion                       | [`apps/watch`](../apps/watch/README.md); see the documented iOS receiver status                           |
| Public web                              | [`apps/web`](../apps/web/README.md); public Explore and Species Dictionary pages                          |
| Internal admin                          | [`apps/admin`](../apps/admin/README.md); separate Google OAuth/TOTP AAL2 and narrow RPC boundary          |
| Database and Edge Functions             | [`services/supabase`](../services/supabase/README.md)                                                     |

The app and widget target iOS 17.2; the companion targets watchOS 10.0. The
active SwiftData schema is `MerianSchemaV51`. The
[schema contract](./backend-and-data/04-database-schema.md) and
[startup recovery guide](./backend-and-data/08-startup-store-recovery.md) own
migration and install-over requirements.

The tracked iOS defaults point to production Supabase. Debug simulator warnings
do not prevent real authentication, reads, or writes. Use matching local/staging
URL and client-key overrides for routine development; see
[environment setup](./CONTRIBUTING.md#setting-up-the-development-environment).

### Release and Verification

Normal development is commit → push to `main` → exact-SHA checks → release.
Branches and PRs are optional. The
[direct-main policy](./release-evidence/README.md#direct-main-development-policy--september-22-2026)
owns branch settings and the boundary between validation and production.

**Public production remains blocked on exact-SHA evidence and external
controls.** The
[consent readiness record](./legal/production-consent-readiness-2026-08-03.md)
owns the verdict. Internal test builds may continue; that does not authorize
production submission or public release.

- [Testing strategy](./development-guides/08-testing-strategy.md) owns the
  compiled **iOS Build and Test** gate and **Supabase Candidate Validation**.
  Candidate validation uses a disposable database without production secrets or
  mutation.
- [Release evidence operations](./release-evidence/README.md) owns hold-exit
  evidence and automatic deployment controls. A green held run is not deployment
  evidence.
- [iOS publishing](./development-guides/14-ios-release-versioning.md) and
  [Supabase deployment](./backend-and-data/06-supabase-deployment-runbook.md)
  own separately authorized operations, rollout order, and recovery.
- [DwC-A release assurance](./backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md)
  keeps exports default-off for initial launch; feature-enable evidence remains
  separate from base-release acceptance.
- [Privacy manifest](./development-guides/16-ios-privacy-manifest.md) and
  [transport security](./development-guides/17-ios-transport-security.md) define
  archive, App Store, ATS, and credential-free HTTPS requirements.

### Cross-Surface Contracts

- [Scan ingestion and recovery](./backend-and-data/16-scan-ingestion-reliability-and-recovery.md):
  fresh multimodal success awaits moderation, required media promotion, primary
  species resolution, scan creation, owner read-back, and canonical media
  verification. Marked same-UUID replay may reconstruct from the exact owner row
  while reconciliation remains retryable, without a second provider call.
- [Server credentials and database safety](./backend-and-data/13-server-credentials-and-database-release-safety.md):
  header classification, RLS/grants, migration ownership, and replay safety.
- [Scientific-observation retention](./backend-and-data/17-scientific-observation-retention.md):
  the exact ownerless-retention, erasure, and public-projection boundaries.
- [Apple account deletion](./backend-and-data/20-sign-in-with-apple-account-deletion.md):
  provider revocation precedes Auth deletion; credential-revocation signals are
  fenced after lookup and again after account-work quiescence. Production
  verification and legacy-client fallback remain explicit release requirements.
- [Typed event and presentation routing](./system-architecture/10-event-and-presentation-routing.md):
  event ownership, account/session fences, serialized presentation, and
  feedback.
- [Revenue and identity](./features-and-hardware/02-revenue-and-identity.md) and
  [complimentary Pro scans](./backend-and-data/18-complimentary-pro-scans.md):
  entitlement, purchase identity, reservations, and rollout controls.
- [Code ownership and refactoring](./development-guides/19-code-ownership-and-refactoring.md):
  responsibility boundaries, parity checks, and cleanup stop conditions. The
  [completed cleanup RFC](./rfcs/codebase-cleanup.md) preserves implementation
  history.

## Directory Structure

### Current Codebase Map

- **[`/codebase-map.md`](./codebase-map.md)** — Current target, folder, schema,
  SwiftData actor, feature, Edge Function, and testing inventory for this repo
  state.

### Incidents

- **[Simulator signing and startup recovery loop](./incidents/2026-09-simulator-signing-recovery-loop.md)**
  — Unsigned local simulator builds, missing runtime Keychain entitlements, and
  verification of recovery through a corrected build.
- **[First photo import session readiness](./incidents/2026-09-first-import-session-readiness.md)**
  — First-launch admission before account setup, source mitigation, simulator
  regressions, and remaining device verification; the reported cause is
  unconfirmed.
- **[Beta reconciliation and system analytics log errors](./incidents/2026-09-beta-reconciliation-and-system-analytics.md)**
  — Repeated free-account reconciliation and non-UUID system telemetry,
  repository repairs, and pending production verification.
- **[Video recording microphone admission regression](./incidents/2026-09-video-recording-microphone-admission.md)**
  — Pre-start recording failure, unintended microphone attachment, source
  mitigation, and outstanding physical-device verification.
- **[Identification notification gaps](./incidents/2026-09-identification-notification-gaps.md)**
  — Post-result permission-prompt dismissal and recovered-result alert/badge
  omissions, source mitigation, and remaining candidate/device checks.
- **[`/incidents/README.md`](./incidents/README.md)** — Incident authority,
  privacy, status, naming, and maintenance rules, plus the canonical new-record
  template.
- **[`/incidents/2026-08-live-scan-connectivity-handoff-gap.md`](./incidents/2026-08-live-scan-connectivity-handoff-gap.md)**
  — Bounded pre-queue admission fallback, required first-failure **Queued for
  later** behavior, the durable-owner versus local-presentation ownership
  repair, scoped transport-replay policy, **Analysis delayed** placeholder
  routing, protected URLSession race matrix, and remaining exact-SHA/device
  closure gates.
- **[`/incidents/2026-08-first-scan-auth-refresh-gap.md`](./incidents/2026-08-first-scan-auth-refresh-gap.md)**
  — Sanitized Edge-origin Auth evidence, the `invalid_session_token`
  refresh-classification gap, refresh-first account preservation, and
  exact-session closure gates for first-scan recovery.
- **[`/incidents/2026-08-first-scan-consent-policy-retry-loop.md`](./incidents/2026-08-first-scan-consent-policy-retry-loop.md)**
  — Sanitized first-user evidence, consent-versus-quota classification, stale
  cloud-proof root cause, durable account-scoped disclosure recovery, and
  exact-SHA closure gates for the scanning plus **Retry now** loop.
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
- **[`/product/03-identification-foundation-prd.md`](./product/03-identification-foundation-prd.md)**
  — Active provider-flexibility infrastructure plan: Gemini remains on all
  identification and supporting content tasks while shared interfaces, explicit
  bindings, and parity tests prepare for a later provider change. Video capture
  supplies sampled images and any included companion audio to inference.
- **[`/rfcs/identification-foundation-srd.md`](./rfcs/identification-foundation-srd.md)**
  — Companion system requirements for the Gemini adapter, actual-input
  capability checks, existing consent/confidence and recovery behavior, and a
  separate future-provider integration and qualification procedure. Includes the
  six-slice implementation tracker and its
  [21 September source/test baseline](./rfcs/identification-foundation-baseline.md).
  The
  [Slice 6 verification record](./rfcs/identification-foundation-verification.md)
  covers the final dispatch boundary, local overhead, disposable database
  evidence, and the gates remaining at that checkpoint. The
  [deployment record](./release-evidence/provider-flexibility-deployment-2026-09-21.md)
  adds the successful Gemini-only rollout, owner verification, and remaining CI
  observation. The
  [provider onboarding guide](../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
  explains the work needed before assigning another service.
- **Identification evaluation readiness:**
  [PRD](./product/04-identification-evaluation-prd.md) and
  [SRD](./rfcs/identification-evaluation-srd.md) plan the next milestone: an
  independently reviewed corpus, shared result normalization, and a repeatable
  Gemini quality/time/cost baseline. Includes five implementation slices; Slices
  1–3 now supply offline contracts, shared production request/normalization
  rules, a guarded runner, durable attempts and reproducible reports; the
  [Slice 4 collection packet](./development-guides/20-identification-evaluation-pilot.md)
  supplies a solo phone/computer workflow, automated exploratory preflight and
  provisional reporting, proposed formal coverage and blank intake/reviewer
  forms. The formal corpus and direct evaluator's live run remain pending; the
  [exploratory experiment record](./rfcs/identification-exploratory-benchmark-2026-09-22.md)
  distinguishes offline mechanics from the completed
  [two-photo production-app benchmark](./rfcs/identification-production-app-benchmark-2026-09-22.md),
  which records visible outcomes and app timings without claiming verified
  accuracy, exact model identity or provider cost. A later
  [measurement checkpoint](./rfcs/identification-measured-app-benchmark-2026-09-22.md)
  records one live Gemini model/usage/source observation and explicitly retains
  recorder failures and missing server timings. The
  [recorder repair checkpoint](./rfcs/identification-recorder-repair-2026-09-22.md)
  records the synthetic reproduction, bounded shutdown repair and live-repeat
  verification status. The
  [live capture verification](./rfcs/identification-timing-capture-verification-2026-09-22.md)
  subsequently completed both recorder windows and verified provider/Edge timing
  on the cat after a native parser fix, preserving the flower's missing spans.
- **Deferred family and prior combined planning:**
  [PRD](./product/02-family-plans-and-ai-platform-prd.md) and
  [SRD](./rfcs/family-plans-and-ai-platform-srd.md). Family plans are deferred;
  their earlier AI proposals are superseded by the provider-flexibility plan.

### Legal & Release Readiness

- **[`/release-evidence/README.md`](./release-evidence/README.md)** — Canonical
  evidence-authoring, redaction, freshness, artifact audits, and automatic
  deployment controls for machine-held releases.
- **[`/legal/production-consent-readiness-2026-08-03.md`](./legal/production-consent-readiness-2026-08-03.md)**
  — Canonical release hold, source status, same-SHA hosted evidence table,
  rollout order, and external App Store/Gemini/counsel exit evidence.
- **[`/legal/terms-counsel-review.md`](./legal/terms-counsel-review.md)** —
  Internal legal working memo covering public Terms alignment, unresolved
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
  latency instrumentation, progressive on-device analyzing context, stable
  Foundation Models activation controls, `maxOutputTokens` limits, and API
  throttling.
- **[`/system-architecture/06-edge-modularization.md`](./system-architecture/06-edge-modularization.md)**
  — Domain-driven modular architecture for Supabase Edge Functions: `index.ts` /
  `db.ts` / `types.ts` separation rules and shared utility conventions.
- **[Function directory guide](../services/supabase/functions/README.md)** —
  Endpoint and shared-owner navigation by product area; the
  [organization audit](./rfcs/supabase-functions-organization.md) records the
  dependency baseline, AI validation handoff, and proposed organization slices.
- **[`/system-architecture/08-public-brand-compatibility.md`](./system-architecture/08-public-brand-compatibility.md)**
  — Canonical Naturebook public values, permanent Merian technical identifiers,
  link/domain compatibility, AASA exceptions, and the allowed-branding audit
  classification.
- **[`/system-architecture/09-ios-release-publisher.md`](./system-architecture/09-ios-release-publisher.md)**
  — Xcode Organizer distribution decision, CI boundary, build-number ownership,
  automatic-signing model, source identity, and promotion invariants.
- **[`/system-architecture/10-event-and-presentation-routing.md`](./system-architecture/10-event-and-presentation-routing.md)**
  — Canonical typed event/route matrices, queue and session semantics,
  framework-notification allowlist, single-sheet host, and nonblocking feedback
  contract.

### Backend & Data

- **[`/backend-and-data/01-offline-sync-pipeline.md`](./backend-and-data/01-offline-sync-pipeline.md)**
  — Zero-data-loss architecture, SwiftData queues, live/background upload
  ownership, layered historical hydration, V51 collection tombstone
  synchronization, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/02-supabase-edge-and-database.md`](./backend-and-data/02-supabase-edge-and-database.md)**
  — Supabase Postgres schemas, Edge Function runtime rules, RLS, public species
  dictionary workers, private Insight, Explore, and in-app Dictionary Field chat
  boundaries, service-only Identify Activity projection/read boundaries, and
  cron/webhook boundaries.
- **[`/backend-and-data/03-database-actors.md`](./backend-and-data/03-database-actors.md)**
  — SwiftData actor model: the declaration-only `BackgroundDatabaseActor` and
  its focused persistence extensions, the layered Historical Sync models,
  decoder, cloud adapter, and `HistoricalDatabaseActor`, plus `FileIOActor`,
  including scan finalization, collection projection, and tombstone boundaries
  with fail-closed historical reads, saves, and cancellation-safe collection
  pruning.
- **[`/backend-and-data/04-database-schema.md`](./backend-and-data/04-database-schema.md)**
  — Physical table maps for PostgreSQL and the SwiftData persistent schemas,
  including the V41 `CapturedMediaEntry` mixed-media model, V47 offline video
  inference fields, V48 offline job records/events, V49 startup store repair,
  V50 durable queued Field trip goal hints and source-only
  `ScanCollection.isPendingDeletion` rename, V51 account-scoped species
  preferences, private Insight and per-viewer Explore/Dictionary Field chat
  tables, scan media assets, and Explore Community Identification versioned
  taxonomy, consensus jobs, requests, public projections, and internal grouped
  Activity projection, atomic ingestion setup/dictionary RPCs, deferred
  scan-context staging, and the private admin/review/audit schema plus canonical
  AI usage ledger, storage-erasure claim fencing, atomic owned scan-image
  reference repair, and the database-only Backyard Safari enrollment
  trigger/backfill.
- **[`/backend-and-data/05-api-contracts.md`](./backend-and-data/05-api-contracts.md)**
  — JSON mapping contracts between the iOS client and Deno Edge functions,
  including `/identify-multimodal`, `/insight-chat`, `/explore-post-chat`,
  `/species-dictionary-chat`, `/field-trips` starter enrollment, preferred
  progress, and scan contributions, `/update-public-avatar`, Community
  Identification request/detail and grouped Activity endpoints,
  `/species-dictionary`, authenticated `/resolve-species-dictionary`,
  `/species-discovery-search`, `/species-observation-stats`,
  `/sync-collections`, `/report-user`, the internal admin RPC surface, Explore
  detail similar species, and internal cron workers such as Merian
  reference-image refresh, diagnostic `Server-Timing`, and
  `/update-scan-context`, plus the owner-authenticated `/repair-scan-image`
  inspection and recovery contract.
- **[`/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md)**
  — Validation-only Supabase candidate gate, separately authorized production
  deployment path, required GitHub secrets, local emergency fallback, frozen
  function-local dependency configs, dependency-aware batched deploys, staged
  identification-latency and Identify Activity rollout gates, and post-deploy
  smoke checks.
- **[`/backend-and-data/07-community-taxonomy-import-checklist.md`](./backend-and-data/07-community-taxonomy-import-checklist.md)**
  — Running checklist for bounded GBIF Community Taxonomy imports, completed
  Birds batches, next offsets, and operational follow-ups.
- **[`/backend-and-data/08-startup-store-recovery.md`](./backend-and-data/08-startup-store-recovery.md)**
  — Launch-time SwiftData store recovery contract: exception bridge, store-aware
  migration selection, duplicate-checksum fallbacks, corruption-gated
  quarantine, rollback-protected legacy-store rescue, privacy-safe diagnostics,
  manifest-gated success, safe mode, auth isolation, telemetry, verification,
  and genuine-store physical-device release acceptance.
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
  — Complete 91-function inventory, corrected cross-cutting findings, boundary
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
  — Normative contract for the staged replacement of the introductory trial with
  three lifetime complimentary Pro scans, including the private ledger, derived
  balances, user-first reservation and settlement, separate Flash and provider
  quotas, protocol 3, iOS reservation safety, Ghost merge, admin telemetry,
  security, rollout, and executable verification map.
- **[`/backend-and-data/19-security-and-reliability-remediation-2026-08-03.md`](./backend-and-data/19-security-and-reliability-remediation-2026-08-03.md)**
  — Joined implementation and release record for collection ownership,
  exact-size staging uploads, serialized complimentary funding, redirect origin
  safety, taxonomy checkpointing, rollout dependencies, and production evidence.
- **[`/backend-and-data/20-sign-in-with-apple-account-deletion.md`](./backend-and-data/20-sign-in-with-apple-account-deletion.md)**
  — Normative authorization-code capture, Vault token storage, durable provider
  revocation, legacy manual fallback, key rotation, rollout, and verification
  contract for Sign in with Apple account deletion.

### Features & Hardware

- **[`/features-and-hardware/01-camera-and-hardware.md`](./features-and-hardware/01-camera-and-hardware.md)**
  — AVFoundation bindings, LiDAR depth logic, Pro video stabilization
  boundaries, identity-fenced haptic feedback ownership, and
  ViewfinderIntelligence constraints.
- **[`/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md)**
  — RevenueCat products/offerings, Test Store/StoreKit/TestFlight purchase
  matrix, stable purchase principals, protocol-3 server-authorized sign-out
  rotation, durable webhook access, paid and complimentary Pro entitlements, and
  signed-out session identity.
- **[`/features-and-hardware/03-gamification-and-telemetry.md`](./features-and-hardware/03-gamification-and-telemetry.md)**
  — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/04-onboarding.md`](./features-and-hardware/04-onboarding.md)**
  — Four-step permission flow, final adult/Terms/Gemini/analytics consent
  surface, versioned evidence, and the combined onboarding/current-consent
  workspace gate.
- **[`/features-and-hardware/05-insight-sheet.md`](./features-and-hardware/05-insight-sheet.md)**
  — InsightSheet view architecture, mixed-media carousel handoff, species data
  rendering, progressive analyzing-pill UX, persistent Field trip progress,
  typed routing, Field chat, and graceful degradation states.
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
  — Describe capture mode: product-area ownership, `ObservationContext` state,
  deterministic prompt/text policy, generation-fenced subject and dictation
  lifecycle, serialized startup cancellation, Core `SpeechManager` AVAudioEngine
  and SFSpeechRecognizer pipeline, and Swift 6 concurrency guarantees. Also owns
  reanalysis's supplementary description allowance, automatic Analyze inclusion,
  tray-edit/removal precedence, replacement cleanup, and late-transcript
  handling; runtime acceptance is tracked in the
  [reanalysis verification matrix](development-guides/08-testing-strategy.md#reanalysis-description-verification).
- **[`/features-and-hardware/12-audio-listen-mode.md`](./features-and-hardware/12-audio-listen-mode.md)**
  — Audio Listen Mode: `SpectrogramActor` FFT/mel-scale DSP,
  `AudioCaptureManager` 15-second recording facade,
  `AudioRecordingEngineController` engine/tap/WAV lifetime,
  `AudioReviewPlaybackController` player/task lifetime, shared raster-backed
  spectrogram, ambient-noise guidance, generation-fenced record and review
  lifecycle, token-aware audio-session leases, coordinated camera-to-microphone
  hardware handoff, and the shared non-visual durability path.
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
  Function detail/catalog/overview contracts, similar-species entry points from
  Insight and Explore detail, verified resolution of name-only reference pages,
  conversational Species/Sightings search, release-held in-app private Field
  Chat, cache rules, content quality, media attribution, enrichment
  queue/backfill, and refresh provenance. Search's
  [verification matrix](./development-guides/08-testing-strategy.md#species-discovery-search-verification)
  distinguishes automated coverage from device and live-provider checks.
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
  protected-name policy, Edge update/check contracts, deterministic repair, and
  implemented mention boundary.
- **[`/features-and-hardware/22-geoprivacy.md`](./features-and-hardware/22-geoprivacy.md)**
  — Geoprivacy modes, backend projection triggers, local UI privacy gates,
  public Explore/export boundaries, and verification checklist.
- **[`/features-and-hardware/23-explore-comment-mentions.md`](./features-and-hardware/23-explore-comment-mentions.md)**
  — Explore comment `@username` mention eligibility, suggestion endpoint,
  historical token snapshots, notification behavior, iOS composer/link
  rendering, and verification.
- **[`/features-and-hardware/24-explore-bottom-menu.md`](./features-and-hardware/24-explore-bottom-menu.md)**
  — Explore launch entry points, exactly-three-item root navigation,
  Observations Feed/Map, Field trips, Identify Species/Community, filtered
  request and Activity previews/full feeds, deep-link mode policy, stack chrome,
  Species catalog ownership, and the absence of a separate taxonomy browser.
- **[`/features-and-hardware/25-field-trips.md`](./features-and-hardware/25-field-trips.md)**
  — Public Field trips, Outings, and Events, automatic Backyard Safari Level 1
  enrollment, guided outing detail, progress matching, the account-cached active
  target indicator on visual Scan, focused Tips/Goals routing, active-level
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
  lifetime, file-backed cloud downloads, approved-host policy, cleanup, feedback
  counts, and physical-device QA.
- **[`/features-and-hardware/28-private-scan-map.md`](./features-and-hardware/28-private-scan-map.md)**
  — Owner-only Scan library map, including eligible local-record projection,
  complete-extent Collections preview, current-location fallback, filters,
  clustering, private Insight routing, exact-coordinate privacy boundaries,
  sensitive-reset and stale-completion fencing, accessibility, verification, and
  candidate release status.
- **[`/rfcs/explore-page.md`](./rfcs/explore-page.md)** — Explore feed and map
  product/RPC architecture, including the shipped V1 map implementation and
  follow-up recommendations.
- **[`/rfcs/active-capture-goal-context.md`](./rfcs/active-capture-goal-context.md)**
  — Accepted long-term architecture for source-agnostic goals on Capture,
  account-scoped stale-data retention, typed navigation, private source reads,
  and adding future goal providers without coupling them to the camera.
- **[`/rfcs/codebase-cleanup.md`](./rfcs/codebase-cleanup.md)** — Completed
  historical implementation record; current policy lives in the Code Ownership
  and Refactoring guide.
- **[`/rfcs/species-dictionary-long-term-todo.md`](./rfcs/species-dictionary-long-term-todo.md)**
  — Long-term species dictionary TODO covering canonical identity, reference
  media normalization, public projections, enrichment queues, provenance and
  refresh, caching, licensing, and analytics.
- **[`/rfcs/geological-expansions.md`](./rfcs/geological-expansions.md)** —
  Roadmap for extending inference to rocks, minerals, and fossils.
- **[`/rfcs/purchase-principal-auth-separation.md`](./rfcs/purchase-principal-auth-separation.md)**
  — Accepted separation of Supabase authentication, stable StoreKit purchase
  principals, and account-owned grants, including protocol-3 sign-out
  reservations, compatibility/rollback, monitoring, and production release
  gates.

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
  — Cross-platform test commands, disposable-database and compiled-iOS gates,
  SwiftData isolation and disk-backed migration fixtures, privacy/ATS checks,
  and release-evidence requirements.
- **[`/development-guides/09-core-managers.md`](./development-guides/09-core-managers.md)**
  — Deep dive into singleton instances across Merian (e.g.
  `HardwareOrchestrator`).
- **[`/development-guides/10-safety-and-moderation.md`](./development-guides/10-safety-and-moderation.md)**
  — Gemini safety rating evaluation, abuse strike system, shadowban logic, and
  R2 media promotion pipeline, plus fail-closed Explore speech/non-speech audio
  moderation and the post-publication local playback-boost boundary.
- **[`/development-guides/11-swiftdata-and-api-gotchas.md`](./development-guides/11-swiftdata-and-api-gotchas.md)**
  — SwiftData background synchronization drops, relationship fault boundaries,
  reserved `PersistentModel.isDeleted` state, and API envelope parsing
  constraints.
- **[`/development-guides/12-in-app-changelog.md`](./development-guides/12-in-app-changelog.md)**
  — Root release history, per-train App Store note source, bundled Settings
  changelog schema, writing rules, asset handling, and update workflow.
- **[`/development-guides/13-asset-catalog.md`](./development-guides/13-asset-catalog.md)**
  — Asset catalog grouping and naming rules for reusable 3D graphics, app
  assets, brand marks, and personas.
- **[`/development-guides/14-ios-release-versioning.md`](./development-guides/14-ios-release-versioning.md)**
  — Complete iOS operator runbook: repository and Apple setup, Xcode
  Organizer-only distribution, exact-SHA archive/IPA evidence, physical-device
  schema-upgrade acceptance, TestFlight promotion, and release records.
- **[`/development-guides/15-naturebook-rebrand-rollout.md`](./development-guides/15-naturebook-rebrand-rollout.md)**
  — Ordered domain, AASA, email, Supabase, App Store, update-continuity, link,
  verification, rollback, and completion checklist for the public rebrand.
- **[`/development-guides/16-ios-privacy-manifest.md`](./development-guides/16-ios-privacy-manifest.md)**
  — Main-app privacy declarations, required-reason API and collected-data
  inventories, contributor change rules, archive/IPA validation, and App Store
  evidence requirements.
- **[`/development-guides/17-ios-transport-security.md`](./development-guides/17-ios-transport-security.md)**
  — ATS-default and HTTPS-only URL boundary, source/archive/IPA validation,
  contributor rules, and release evidence requirements.
- **[`/development-guides/18-ios-runtime-quality-and-benchmarking.md`](./development-guides/18-ios-runtime-quality-and-benchmarking.md)**
  — Executable iOS acceptance/UI/performance audit ownership, XCResult evidence,
  baseline policy, report-only metrics, and device/provider boundaries.
- **[`/development-guides/19-code-ownership-and-refactoring.md`](./development-guides/19-code-ownership-and-refactoring.md)**
  — Durable ownership, extraction, parity, affected-delta, integration-audit,
  and stop-condition rules for future hygiene work.
- **[`/development-guides/20-identification-evaluation-pilot.md`](./development-guides/20-identification-evaluation-pilot.md)**
  — Solo phone/computer checks and automated exploratory testing, proposed
  60-example formal pilot coverage and blank intake/reference-review forms; paid
  evaluator measurement remains pending. The first two normal production-app
  submissions are recorded in the
  [live benchmark](./rfcs/identification-production-app-benchmark-2026-09-22.md).
- **[`/development-guides/21-identification-app-measurement.md`](./development-guides/21-identification-app-measurement.md)**
  — Passive app measurement of provider/model, app and Function source identity,
  provider/Edge timing, token usage and optional conservative primary-call cost.
  Records unknowns explicitly and submits no identifications.

## About Naturebook

Naturebook is a native iOS application that identifies plants, animals, insects,
fungi, and indoor ecology with scientific-grade accuracy across visual, audio,
and text-described observations. It uses dynamic routing between the Gemini 2.5
Flash and Pro APIs via Supabase Edge Functions, with a full offline-first
architecture backed by SwiftData and Cloudflare R2. Merian is the stable
technical identity underneath the Naturebook product.

## Explore emoji reactions

The
[dated Explore product contract](./rfcs/explore-page.md#emoji-reactions-update-2026-09-18)
owns native post/comment reaction behavior. The
[API contract](./backend-and-data/05-api-contracts.md#explore-emoji-reactions-2026-09-18)
defines additive payloads, capability-aware notification reads/pushes, and
backend-before-app delivery; the
[verification matrix](./development-guides/08-testing-strategy.md#explore-emoji-reaction-verification)
separates automated gates from manual device checks. These describe current
source, not evidence of deployment or app distribution.
