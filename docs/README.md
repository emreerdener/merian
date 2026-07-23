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
  for `admin.naturebook.earth`; Google OAuth + TOTP AAL2 and narrow database RPCs
  only. See [`backend-and-data/10-internal-admin.md`](./backend-and-data/10-internal-admin.md)
  and the
  [`backend-and-data/11-internal-admin-operations.md`](./backend-and-data/11-internal-admin-operations.md)
  operator runbook.
- **Deployment target**: iOS 17.2 for the app and widget; watchOS 10.0 for the
  companion target.
- **Project source of truth**: `project.yml` via XcodeGen. `Merian.xcodeproj` is
  committed for convenience and should be regenerated after project-structure
  changes.
- **Prelaunch access and purchase QA**: Release and TestFlight use the normal
  free/Pro meter and authoritative server quota; unlimited meter bypasses are
  DEBUG-only. Testers can still open Settings → Plan directly. Debug simulator
  purchase tests use an explicitly selected RevenueCat Test Store or StoreKit
  configuration; TestFlight uses the production iOS key and App Store Connect
  products.
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
  `/identify-multimodal`, capped at 10 server replay claims per sanitized intent,
  while inline media remains client-retry only because raw bytes are never stored
  server-side. The shared identify boundary demotes
  manufactured or processed materials to non-biological before candidates,
  dictionary novelty, or `species_dictionary` writes can run.
- **Image-analysis latency contract**: Durable queue acceptance remains the
  mandatory gate. The eligible live-camera still path waits no more than 150 ms for shutter-prefetched
  weather/geocoding, defers its competing background upload until the inline
  body is sent, and commits parsed/persisted results before awards or Field trips.
  The Edge path uses verified ES256 claims, one atomic pre-inference RPC, at
  most one combined post-inference dictionary RPC, privacy-safe `Server-Timing`, and background
  cache-miss enrichment. `/update-scan-context` applies late owner-scoped
  context without a second AI request. Model IDs and all inference-quality and
  unit-economics settings remain unchanged. Gallery, audio-bearing, and video
  submissions are instrumented but retain their existing behavior in this pass.
- **Photos share import contract**: A single image shared from iOS Photos opens
  the containing app through its alternate `public.image` document association.
  `ExternalImageImportStore` copies the file into a durable Application Support
  inbox before Capture observes it, so cold launch, onboarding, quota, and tray
  capacity cannot lose the receipt. Embedded date/GPS is read before bounded
  preparation; the normal required crop, confirmation preference, inference,
  and offline queue then apply. This path has no Share Extension, App Group
  handoff, backend import endpoint, or new Photo Library permission.
- **Fresh-launch presentation contract**: The Capture workspace remains the app
  root. After onboarding, the default-off **Open Explore on launch** preference
  can present the generic Explore feed once when a new process starts. It is not
  reevaluated on foreground returns. Photos/Files imports, deep links, and
  tapped notification routes always replace the generic feed with the requested
  capture, post, community, scan, or library destination.
- **Media durability safety net**: Backend deploys run a media-ingestion
  contract matrix covering image, audio, text-only, video, status, repair, and
  Explore-share seams. Production scan-media health reports include incident
  actions with owner/runbook/sample hints for each issue code. Canonical scan
  media refresh rebuilds standalone audio rows from `captured_media` and
  `audio_storage_urls`; it never requires replacing the durable R2 recording.
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

### Product

- **[`/product/01-master-product-document.md`](./product/01-master-product-document.md)**
  — Repository-aligned product definition, implementation-status boundaries,
  current release identifiers, and high-impact corrections to the retired
  product document.

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

### Backend & Data

- **[`/backend-and-data/01-offline-sync-pipeline.md`](./backend-and-data/01-offline-sync-pipeline.md)**
  — Zero-data-loss architecture, SwiftData queues, live/background upload
  ownership, and AppDelegate background URLSession mappings.
- **[`/backend-and-data/02-supabase-edge-and-database.md`](./backend-and-data/02-supabase-edge-and-database.md)**
  — Supabase Postgres schemas, Edge Function runtime rules, RLS, public species
  dictionary workers, private Insight and Explore Field chat boundaries, and
  cron/webhook boundaries.
- **[`/backend-and-data/03-database-actors.md`](./backend-and-data/03-database-actors.md)**
  — SwiftData actor model: `BackgroundDatabaseActor`, `HistoricalDatabaseActor`,
  and `FileIOActor`.
- **[`/backend-and-data/04-database-schema.md`](./backend-and-data/04-database-schema.md)**
  — Physical table maps for PostgreSQL and the SwiftData persistent schemas,
  including the V41 `CapturedMediaEntry` mixed-media model, V47 offline video
  inference fields, V48 offline job records/events, V49 startup store repair,
  V50 durable queued Field trip goal hints,
  private Insight and per-viewer Explore Field chat tables, scan media assets,
  and Explore Community Identification versioned taxonomy, consensus jobs,
  projections, and request tables, atomic ingestion setup/dictionary RPCs,
  deferred scan-context staging, and the private admin/review/audit schema plus
  canonical AI usage ledger.
- **[`/backend-and-data/05-api-contracts.md`](./backend-and-data/05-api-contracts.md)**
  — JSON mapping contracts between the iOS client and Deno Edge functions,
  including `/identify-multimodal`, `/insight-chat`, `/explore-post-chat`,
  `/field-trips` preferred progress and scan contributions,
  `/update-public-avatar`, Community Identification endpoints, `/species-dictionary`,
  `/species-observation-stats`, `/report-user`, the internal admin RPC surface,
  Explore detail similar species, and internal cron workers such as Merian
  reference-image refresh, diagnostic `Server-Timing`, and
  `/update-scan-context`.
- **[`/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md)**
  — CI-first Supabase deployment path, required GitHub secrets, local emergency
  fallback, frozen function-local dependency configs, dependency-aware batched
  deploys, staged identification-latency rollout gates, and post-deploy smoke
  checks.
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
  grouped review and feedback workflows, audit trail, metrics, and AI ledger.
- **[`/backend-and-data/11-internal-admin-operations.md`](./backend-and-data/11-internal-admin-operations.md)**
  — Internal admin setup and operations: environment, owner bootstrap,
  deployment ordering, production smoke tests, price maintenance, recovery,
  incident response, rollback, and troubleshooting.

### Features & Hardware

- **[`/features-and-hardware/01-camera-and-hardware.md`](./features-and-hardware/01-camera-and-hardware.md)**
  — AVFoundation bindings, LiDAR depth logic, Pro video stabilization
  boundaries, and ViewfinderIntelligence constraints.
- **[`/features-and-hardware/02-revenue-and-identity.md`](./features-and-hardware/02-revenue-and-identity.md)**
  — RevenueCat integration, Pro entitlements, and Ghost Session identity model.
- **[`/features-and-hardware/03-gamification-and-telemetry.md`](./features-and-hardware/03-gamification-and-telemetry.md)**
  — Achievement system, scan telemetry capture, and PostHog analytics.
- **[`/features-and-hardware/04-onboarding.md`](./features-and-hardware/04-onboarding.md)**
  — Six-step permission flow, onboarding state machine, and the
  `hasCompletedOnboarding` gate.
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
  UUID-only route compatibility,
  Supabase server reads, media-rights filtering, metadata, privacy boundaries,
  and Universal Links.
- **[`/features-and-hardware/18-species-observation-charts.md`](./features-and-hardware/18-species-observation-charts.md)**
  — Reusable species observation charts, local-on-device aggregation, public
  iNaturalist stats cache, annotation mappings, privacy boundaries, and
  verification.
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
  — Explore launch entry points, root navigation, Observations Feed/Map toggle,
  Community identification queue, author-profile stack routing, Dictionary
  catalog, and Tree of Life canvas routing/data boundaries.
- **[`/features-and-hardware/25-field-trips.md`](./features-and-hardware/25-field-trips.md)**
  — Public Field trips/Outings, the client-staged Events rollout and release
  checklist, guided outing detail, progress
  matching, the account-cached active target indicator on visual Scan, focused
  Tips/Goals routing, active-level progress ring, private completed-scan
  thumbnails and embedded Insight navigation, persistent scan contribution
  cards, one credit per experience with multi-experience eligibility, seasonal
  challenges, challenge badges, publication snapshots,
  profile pins, access gating, in-app activity, and deferred leaderboard/prize
  scope.
- **[`/features-and-hardware/26-photos-share-import.md`](./features-and-hardware/26-photos-share-import.md)**
  — Single-photo document import from the iOS Photos share sheet, including URL
  routing, durable inbox ownership, EXIF context, capture staging, privacy,
  blocking/retry behavior, and physical-device QA.
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
  — Bundled Settings changelog schema, writing rules, asset handling, and update
  workflow.
- **[`/development-guides/13-asset-catalog.md`](./development-guides/13-asset-catalog.md)**
  — Asset catalog grouping and naming rules for reusable 3D graphics, app
  assets, brand marks, and personas.
- **[`/development-guides/14-ios-release-versioning.md`](./development-guides/14-ios-release-versioning.md)**
  — Semantic app versions, TestFlight build-number prep, and Xcode archive
  preflight rules.
- **[`/development-guides/15-naturebook-rebrand-rollout.md`](./development-guides/15-naturebook-rebrand-rollout.md)**
  — Ordered domain, AASA, email, Supabase, App Store, update-continuity, link,
  verification, rollback, and completion checklist for the public rebrand.

## About Naturebook

Naturebook is a native iOS application that identifies plants, animals,
insects, fungi, and indoor ecology with scientific-grade accuracy across visual,
audio, and text-described observations. It uses dynamic routing between the
Gemini 2.5 Flash and Pro APIs via Supabase Edge Functions, with a full
offline-first architecture backed by SwiftData and Cloudflare R2. Merian is the
stable technical identity underneath the Naturebook product.
