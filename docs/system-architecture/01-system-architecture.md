# Merian System Architecture

Naturebook is a biological classification and gamification platform built for
iOS and watchOS. The architecture relies on decoupled modules connecting onboard
Apple hardware to a Supabase PostgreSQL backend, bridging LLM inferences via
Cloudflare R2 and Gemini models.

## Architectural Data Flow (Overview)

```mermaid
flowchart TD
    A([📱 Capture]) -->|Builds ordered media timeline + telemetry| B[OfflineQueueManager]
    B -->|Mandatory durable acceptance| C[(SwiftData Native DB)]
    C -->|Online live scan; background upload deferred| D[Inline pinned URLSession request]
    D -->|/identify-multimodal| G([⚡️ Supabase Edge])
    D -->|Body sent; release durable recovery| Q[OfflineJobScheduler]
    C -->|Offline, failure, background, or relaunch| Q

    Q -->|/generate-upload-urls| E[Cloudflare R2 Staging Bucket]
    E -->|URLSession Background PUT (image/audio/video media)| F((Cloudflare R2))
    F -->|Background replay| G

    G -->|Verified claims + atomic ingestion setup| H[🤖 Gemini 2.5 Flash / Pro]
    H -->|Returns structured result JSON| G

    G -->|Upserts biological dictionaries| I[(PostgreSQL `species_dictionary`)]
    G -->|Persists UUID scan constraints| J[(PostgreSQL `scans`)]
    K[Late WeatherKit / geocoding] -->|/update-scan-context; no new AI call| G

    C -->|Writes lightweight extension snapshots| N[(App Group Cache)]
    L([Messages Extension]) -->|Reads scan cache| N
```

Postgres is authoritative for relational ownership, scan/post state, and media
URLs. R2 is authoritative for the object bytes at those URLs. Neither layer is a
backup of the other: a retained row cannot reconstruct a deleted object, and an
orphaned object does not reconstruct its relational context.

## Core Architectural Pillars

### 1. Dependency Injection (`AppDIContainer`)

- To prevent Massive Environment Object pollution and enforce separation of
  concerns, Merian uses a centralized `AppDIContainer`. This singleton holds and
  exposes all core orchestration services to view modifiers (like
  `CameraManager`, `InferenceEngine`, `EnvironmentContextManager`), avoiding
  scattered initializations across the app. To preserve the "Instant-On"
  zero-latency launch requirement, all dependencies are declared as `lazy var`.
  This bypasses eager Main Thread initialization during `MerianApp` boot,
  ensuring heavy hardware layers (`AVCaptureSession`) only spin up when
  requested by foreground SwiftUI `.onAppear` lifecycles.

### 2. Hardened Hardware Interfacing (`HardwareOrchestrator`, `CameraManager`, `EnvironmentContextManager`)

- Direct bindings into `AVCaptureSession`, negotiating
  `isHighResolutionPhotoEnabled` buffers using the ISP (Image Signal Processor)
  and Deep Fusion. The `DiscoverySession` prioritizes `.builtInTripleCamera` on
  Pro devices — exposing the full optical zoom range (0.5×–15×) while retaining
  LiDAR depth delivery via `AVCaptureDepthDataOutput` — before falling back to
  `.builtInLiDARDepthCamera` and single-lens devices. Zoom is surfaced via a
  `ZoomSliderView` on the right edge of the viewfinder and via vertical swipe
  and pinch gestures on the preview; the control hides itself
  (`isZoomSupported = maxZoomFactor >= 2.0`) on hardware without a meaningful
  zoom range.
- Short Pro video capture uses `AVCaptureMovieFileOutput` for bounded clips. The
  movie output may be prepared with the visual camera session for a fast
  hold-to-record path, but AVFoundation video stabilization is enabled only for
  the active recording and reset afterward so still-photo capture does not
  inherit crop, latency, or resolution changes.
- Active thermal monitoring manipulates OS frame rate (`targetFPS`) and renders
  Glassmorphism `.ultraThinMaterial` overlays dynamically to prevent critical
  heat loads in outdoor environments.
- **Native Camera Roll Integration (`PhotoLibraryManager`):** Persists
  unmodified `12MP` output into the user's local iOS `PHPhotoLibrary` on
  capture, avoiding iCloud sync delays.
- **Photos Document Import (`ExternalImageImportStore`):** The app advertises
  `public.image` as an alternate viewer. `MerianApp.onOpenURL` copies a shared
  Photos file out of its security-scoped or temporary source into an Application
  Support inbox before publishing a typed `AppEvent`. This is an app-owned
  document import, not an extension or App Group handoff, and the pending copy
  survives cold launch and onboarding until Capture stages it or rejects it as
  terminally unreadable.
- **Pre-warmed Tactile Shutter (`HapticManager`):** The app `.prepare()`s Taptic
  Engine instances (e.g. `UIImpactFeedbackGenerator(style: .medium)`) on app
  boot inside a global `HapticManager`. Centralizing haptics removes the ~20ms
  "cold" instantiation lag on physical button triggers. To protect the
  "Instant-On" launch requirement, these `.prepare()` calls are deferred inside
  a `Task { @MainActor }` sleeping 300ms, allowing the Main Thread to complete
  the heavy hardware layers (`AVCaptureSession`) unimpeded.
- **Battery-bounded Context Tracking (`EnvironmentContextManager`):** Manages
  `CoreLocation` and `WeatherKit` with coarse, pausable location updates while
  the camera is active, then fires a one-shot high-accuracy `requestLocation()`
  when the shutter is pressed. Heading updates are not started because compass
  telemetry is not part of the active inference payload. The shutter location is
  used for Camera Roll EXIF and deferred weather/geocode context, while stale
  cached coordinates remain a fallback if GPS cannot settle within the timeout.
  It also backfills historical edge metadata (GPS and past WeatherKit
  conditions) from `PHAsset` context for in-app gallery picks or embedded
  ImageIO metadata for Photos document imports prior to inference. Date-only and
  coordinate-only imports preserve only the fields actually present.

### 3. Ephemeral Offline-First Sync (`OfflineQueueManager`, `OfflineJobScheduler`, `SwiftData`)

- Employs a zero-data-loss queue structure tracking users without cellular data
  using `SwiftData` inside `MerianApp`. The durable unit is a canonical ordered
  mixed-media timeline, persisted once at submission time and reused across live
  inference, offline replay, thumbnails, and result hydration.
- Visual submissions wait for the queue acceptance callback before starting live
  analysis. If the queue cannot durably write the scan, the UI reports the
  failure and discards orphaned source media instead of showing a false queued
  or analyzing state.
- Eligible online live-camera still submissions create the durable row with
  immediate background sync suppressed for that process-local `scan_id`.
  Inference waits no more than 150 ms for shutter-prefetched
  WeatherKit/geocoding, then begins with available coordinates and cached
  telemetry. The inline request's body-upload callback releases the queue row; a
  two-second fail-safe, request failure, connectivity loss, app backgrounding,
  or relaunch also makes it eligible. Late context is merged locally and through
  `/update-scan-context` without another model call. Gallery, audio-bearing, and
  video submissions remain instrumented but retain their prior context wait and
  upload scheduling behavior.
- `NWPathMonitor` observes off-grid boundaries, debouncing signals for 3 seconds
  when connectivity returns. `OfflineJobScheduler` then drains runnable scan
  ingestion, cloud deletion, and collection-sync jobs according to persisted
  retry windows and network policy. Scan media uploads still hand payloads to an
  iOS `.background` `URLSession` daemon wrapped by `BackgroundTaskWrapper`;
  `AppDelegate` hook completions are intercepted to satisfy iOS background
  Watchdog limits.
- V48 queue metadata (`OfflineQueuedScan.queue*`, `OfflineJobRecord`,
  `OfflineQueueEvent`) makes retry state durable across app kills and provides a
  redacted diagnostics export without raw media paths or private media bytes.

### 4. Serverless Edge Verification (`Supabase Edge Functions`, `Gemini 2.5 Flash / Pro`)

- A Cloud-native workflow decoupling Apple users from raw API logic.
- The `identify-multimodal` Deno Edge node accepts pre-signed multi-capture iOS
  uploads plus inline audio and description payloads. It handles image R2
  streams and inline non-visual media under a shared validation path, enforcing
  a strict cumulative payload cap before evaluating the combined user context.
  Video scans send five sampled frames and optional extracted audio as evidence;
  the playback `.mp4` is promoted only as bounded display/share media. Legacy
  scan-producing routes record the same ingestion job/intent ledger before
  returning success so staged image/audio and text-only compatibility rows can
  recover through the multimodal replay worker.
- The latency-sensitive route verifies ES256 JWT claims through cached JWKS,
  combines pre-inference ingestion setup in `begin_scan_ingestion`, and combines
  post-inference cache hydration in `hydrate_identification_dictionary`.
  Ingestion claim and compatibility recovery share a database generation lock.
  Moderation, required media promotion, primary cache-miss species resolution,
  scan insertion, and owner-scoped read-back complete before every HTTP success.
  A fresh provider-owning multimodal success also requires claimed-key and
  canonical-media finalization, with ledger completion last. A marked same-UUID
  replay may reconstruct from the exact durable owner row while canonical repair
  remains retryable, without another provider call; compatibility routes also
  permit a narrow immediate post-row fallback. Analytics, group tags, and
  candidate enrichment remain optional background tasks. Privacy-safe
  `Server-Timing` separates auth, request body, database, Gemini, dictionary,
  and response work; the Gemini timer stops as soon as the single
  `generateContent` call returns.
- Free remains `gemini-2.5-flash` and Pro remains `gemini-2.5-pro`. Thinking,
  prompt/schema, media resolution, output limits, and one-call semantics are not
  latency tuning levers in this work.
- Model choice and provider capacity are server-owned. Before any public paid
  model dispatch, an atomic Postgres reservation resolves the durable
  entitlement, applies the operation's model policy, and consumes idempotent
  UTC-day/user/IP counters. Database errors and missing user rows fail closed;
  the iOS local meter is advisory.
- Privileged database RPCs stay behind the authenticated Edge API; no
  service-role credential ships to Apple clients. Reviewed `SECURITY DEFINER`
  signatures are allowlisted for `service_role`, and their bodies independently
  verify either the legacy JWT role or PostgREST's protected role impersonation
  used by opaque server keys. The two layers prevent a key-format compatibility
  repair from widening direct client execution.
- All Edge server-key selection flows through `serviceRoleAuth.ts`, and all
  privileged supabase-js construction flows through `serviceRoleClient.ts`.
  Opaque keys use `apikey` only; legacy service-role JWTs retain dual
  `apikey`/Bearer transport during migration. The database equivalent is the
  private `internal.server_api_request_headers(text)` helper, applied to both
  installed `pg_net` routines and persisted `pg_cron` command text.
- `Task.checkCancellation()` boundaries are injected inside `InferenceEngine`
  before transferring `URLSession` data payloads to Cloudflare R2. If the iOS
  Watchdog or the user cancels a processing scan, execution aborts immediately
  to prevent cellular bandwidth leakage.

**Edge Function Map:** The backend logic is strictly decoupled into modular,
single-responsibility functions under `/services/supabase/functions/`.

> [!NOTE]
> All new and existing edge routers explicitly adhere to the **Domain-Driven
> Modular Architecture** (decoupling `index.ts` origin controllers from their
> localized `db.ts` PostgreSQL constraints). For formal logic construction rules
> defining Deno separation of concerns, see
> [`06-edge-modularization.md`](06-edge-modularization.md).

- **Identity & Analysis**
  - `/identify-multimodal`: The primary shipped inference orchestrator for live
    and replayed mixed-media captures.
  - `/update-scan-context`: Applies or stages late owner-scoped elevation,
    weather, and semantic location without rerunning inference.
  - `/identify`: Still-image compatibility entry point that reuses the same
    identify modules and writes the shared ingestion ledger before returning
    success.
  - `/enrich-scan`: On-demand background enrichment for historical "Free" tier
    scans upgrading to Pro insight depths.
  - `/merge-ghost-profile`: Handles existing-account OAuth conflicts with a
    source-issued, provider-bound proof, atomic Ghost-to-account data merge, and
    an idempotent cleanup receipt.
  - `/reconcile-ghost-profile-merges`: Five-minute service-role worker that
    leases incomplete receipts and deletes obsolete anonymous Auth shells.
- **Export & Storage Orchestration**
  - Initial launch posture: Release iOS hides DwC-A; a private default-off
    PostgreSQL singleton and first insert trigger reject old/direct intake;
    processing cron is stopped and capabilities are revoked, while durable
    archive cleanup remains active.
  - `/request-export-dwca`: Stable fail-closed client boundary. When enabled, a
    per-user transaction lock atomically controls release state and the rolling
    24-hour window for personal exports; global scope is internal-only.
  - `/export-dwca`: Currently disabled resumable service-role worker. When
    enabled, its individual claims perform one bounded row-and-byte-aware keyset
    page, archive assembly, or delivery phase. A minute invocation sequentially
    deadline-drains oldest-due waves with a 40-step ceiling; lease fencing still
    permits safe overlap and fair rotation. Both CSV passes share bounded
    immutable creation-time DTOs, with confirmed species identity applied once;
    later scans and edits cannot produce mixed output. Page hashes and a shared
    full-member predicate revalidate privacy eligibility before assembly,
    staging, email, and completion; scan/taxonomy triggers durably invalidate
    affected work. Personal geoprivacy is irrelevant, while protected-species
    coordinate policy is revalidated for both scopes. Cardinality/UTF-8 source
    constraints, row-at-a-time aggregate source enforcement, 256 KiB claimed
    database pages, a fixed 512 KiB incremental CSV encoder, durable cursors,
    and claim-fenced byte-count/CRC manifests enforce canonical budgets before
    streaming the Darwin Core ZIP to R2. Processing application capabilities
    stay in private work state until final fenced completion. Every capability
    click reruns the full-source privacy fence before a 30-second read-only
    redirect; revocation feeds a durable leased archive-cleanup outbox. Checksum
    assembly composes bounded chunk CRCs instead of scanning the full archive in
    JavaScript, then dispatches an idempotent Resend request. Aggregate queue
    and cleanup oldest-due/backlog telemetry feed production monitoring.
    Exact-SHA promotion evidence is tracked in
    `docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`.
  - `/generate-upload-urls`: Provisions short-lived S3 Pre-signed URLs for
    direct-to-Cloudflare `PUT` pushes, keeping massive binaries out of the Edge
    proxy memory.
- **Data Lifecycle & Offline Sync**
  - `/sync-collections`: Reconciles offline iOS SwiftData modifications with the
    Postgres single source of truth.
  - `/delete-scan`: Owner-bound fast path that fences the scan generation before
    Cloudflare R2 and database erasure. Storage signing additionally requires
    the canonical owner UUID in a flat free/Pro object key; prefix-only
    nomination is forbidden.
  - `/reconcile-scan-deletions`: Service-only leased reaper that independently
    resumes interrupted scan erasure and emits aggregate SLA health.
  - `/safe-delete`: Persists a private deletion job, atomically tombstones and
    clears ownership/personal fields from retained observations, verifies
    relational data, then cursor-sweeps every canonical R2 prefix and performs a
    delayed empty verification pass before removing Auth. The database claim
    requires the matching cleaned-up `storage_pending` job and rejects live
    profiles or owned scans; the storage outbox is never sufficient authority.
  - `/reconcile-account-deletions`: Five-minute service-role reaper with
    claim-token fencing, persisted storage cursors, backoff, and idempotent
    Auth-not-found recovery. An offset GitHub schedule independently reads an
    aggregate service-only health RPC and alerts on missing cron/credentials,
    overdue work, retries, expired leases, orphaned storage rows, and SLA
    age/backlog breaches. Its Management-API-resolved server key is independent
    of the reaper's Vault credential, so a broken worker configuration cannot
    also hide the alert. An orphan critical is a provenance incident, not
    deletion authority or permission to clear metadata; restricted review
    precedes any durable request or forward repair.
  - `/repair-scan-image`: Owner-authenticated inspection and recovery for a
    verified-missing durable scan image. It promotes a surviving local copy and
    atomically updates scan, normalized-media, captured-media, and matching
    Explore metadata.
  - `/reconcile-explore-media-health`: Five-minute service-role verifier that
    uses bucket-scoped read-only credentials and two spaced direct R2-origin
    `404` responses before marking primary media missing. Confirmed-missing
    items leave public projections; all-missing posts are reversibly quarantined
    without changing author intent or engagement.
  - `/get-explore-media-incidents`: Owner-authenticated recovery queue for
    degraded and quarantined published posts.
  - `/ingest-r2-media-events`: Optional dedicated-secret event accelerator;
    create/delete events only make rows due and never establish object state.
  - `/auto-purge-nonbio`: Service-only cron selector that generation-locks and
    revalidates expired non-biological captures, then enqueues them for the
    durable independent scan-erasure reaper.
- **Public Species Content**
  - `/species-dictionary`: Public species-level dictionary projection for the
    in-app species page and server-rendered web species route.
  - `/refresh-species-content`: Internal service-role cron worker that consumes
    `species_enrichment_jobs` plus legacy `species_content_provenance`,
    refreshes GBIF/Wikipedia-backed fields, and synchronizes normalized
    reference imagery.
  - `/refresh-species-model-content`: Internal service-role cron worker that
    fills queued Species Dictionary habitat, lookalikes, and group tags through
    the same species-level biology primitives behind `enrich-scan`.
  - `/refresh-merian-reference-images`: Internal service-role cron worker that
    promotes high-quality published Explore media into Merian-sourced species
    reference images and mirrors source visibility.
- **Public Web & Sharing**
  - `apps/web/`: Next.js + Mantine frontend for public Naturebook pages on the
    canonical `naturebook.earth` origin.
  - `/explore/post/[postId]`: Server-rendered public Explore share route. It
    calls the `get_explore_post` RPC from the Next.js server, renders the square
    ordered image/video/audio carousel, emits Open Graph metadata, and links
    back into the native app with `naturebook://explore/post/{postId}` while the
    app continues accepting `merian://` as a legacy alias.
  - `/species/[speciesId]/[slug]`: Server-rendered public Species Dictionary
    route. It invokes `/species-dictionary` with the canonical UUID, treats the
    readable slug as presentation-only, publishes only attribution-approved
    reference imagery, emits canonical/Open Graph/Twitter metadata, and links
    back with `naturebook://species/{speciesId}`. `/species/[speciesId]` and
    stale slugs permanently redirect to the current canonical path after a
    successful UUID lookup.
  - `/api/explore/audio`: Exact-host/public-path WAV stream used only for
    browser-local Boost Audio. Web Audio applies gain, a 35 Hz high-pass filter,
    and peak limiting without storing or uploading a derived recording.
  - `MerianMessagesExtension` reads the App Group scan cache and inserts image,
    card, or description content into Messages without sending automatically.
  - Universal Links bind both `https://naturebook.earth/explore/post/{postId}`
    and `https://naturebook.earth/species/{speciesId}/{slug}` to their native
    Explore routes while preserving web fallbacks for users without the app.
    `https://merian.earth` remains a legacy redirect and associated-domain
    compatibility host. AASA routes exactly `/explore/post/*` and `/species/*`.
- **Moderation & Social**
  - `/get-filtered-discovery-feed`: Paginates public discovery queries from
    post-owned sharing fields, handles blocking mechanisms, and uses scrubbed or
    rounded public coordinates when Explore surfaces are allowed to expose
    location.
  - `/block-user`: Removes blocked-user content and interactions from the
    requesting user's Explore surfaces.
  - `/report-explore-post`: Authenticated public-content moderation ingress. It
    writes `explore_post_reports` and never changes the underlying scan's
    identification-review state.
  - `/flag-issue`: Identification-review ingress for disputed scan inference. It
    writes `flagged_reviews` and sets `scans.is_flagged`; it is not used for
    reports about Explore post content.
- **Revenue Integration**
  - `/revenuecat-webhook`: Subscribes to realtime Apple/Google subscription
    transitions, verifies RevenueCat's timestamped raw-body HMAC, fetches
    authoritative CustomerInfo, and commits each unique event through a
    snapshot-primary per-user database watermark. Recurring/grace expiration is
    persisted, so timed access can fail closed without a final webhook. User
    tiers and entitlement versions therefore cannot be rolled back by duplicate
    or delayed delivery; transfer source and destination projections share one
    atomic transaction.
  - `/reconcile-revenuecat-subscribers`: Fifteen-minute service-role repair
    worker that deadline-drains small leased `SKIP LOCKED` waves, bounds
    CustomerInfo concurrency, and applies only a newer authoritative snapshot
    after a missed delivery. An indexed service-only health RPC plus independent
    scheduled monitor alerts on expired leases and oldest due age.

### 5. Continuous Gamification Ecosystem (`GamificationManager`)

- Tracks device-native state (`UserDefaults`), tying species identifications to
  profile persona progression and achievement milestones.
- Binds global haptics to success triggers and interactions.

### 6. Private Analytics (`AppTelemetry`, `PostHog`)

- PII-free app analytics flow through `AppTelemetry` into `PostHog`, preserving
  the existing client event names and marking iOS-emitted events with
  `event_source = "ios_client"`.
- PostHog identifies usage funnels and telemetry across UI interactions, mapped
  by UUID and automatically enriched with Email and Name identifiers from
  authenticated Supabase sessions.

### 6. UI Initialization & Memory Operations

- **Instant Cold Boot:** `AppTelemetry.initialize()` runs synchronously in
  `MerianApp.init()` after `PostHogManager.configure()` has been invoked by
  `SupabaseManager`. PostHog configuration is idempotent, preventing
  identity-link races. Heavy `CameraManager` hardware initialization
  (`AVCaptureSession.beginConfiguration`) stays off the critical render path.
- **RAM Image Cache (`ImageCache`):** A thread-safe `@unchecked Sendable`
  `NSCache` stores downsampled scan thumbnails in RAM, avoiding massive disk I/O
  thrashing during 120Hz `LazyVGrid` and `TabView` scrolling. This prevents OOM
  crashes and micro-stutters by capping at ~100 thumbnail entries, with iOS
  memory pressure controlling eviction.
- **Still-Image Preparation (`MediaPreparationActor`):** File-backed gallery,
  Photos document imports, refinement, and avatar imports enter a dedicated
  actor before UI staging. The actor owns bounded ImageIO downsampling,
  WebP/JPEG encoding, and payload metrics so SwiftUI never retains full original
  PhotosPicker or shared files.
- **Asynchronous Grid Downsampling:** Image-heavy views (`ScansSheetView`,
  `ScansGrid`, `InsightSheetView`, and the insight carousel) offload decoding
  onto a CPU pool using `ImageIO`'s `CGImageSourceCreateThumbnailAtIndex`,
  bounds-checking 12 MP files without allocating generic `Data` blocks. This
  keeps scrolling locked to 60fps on edge devices.

### 7. watchOS Extension (`MerianWatch`)

Merian includes a companion watchOS app for acoustic identification. The watch
target captures and dispatches audio via WatchConnectivity and does **not**
perform independent Supabase or Gemini calls. The iOS `WCSessionDelegate`
receiver is not currently implemented, so watch payloads are not yet ingested by
the iPhone offline queue.

- **Build Target Nuance**: Relies on the `MerianWatch` target in `project.yml`,
  explicit watchOS deployment settings, and correctly mapped `Contents.json`
  icon configurations inside `Assets.xcassets` to avoid watchOS Simulator
  deployment failures.
- **Acoustic Capture (`WatchAcousticManager`)**: Records a 15-second AAC audio
  clip via `AVAudioRecorder`. Simultaneously acquires `CLLocation` coordinates
  and `WeatherKit` context to bundle environmental metadata with the audio
  payload.
- **WatchConnectivity Bridge**: Once recording completes, the encoded payload
  (base64 audio + GPS + weather) is dispatched to the companion iPhone via
  `WCSession.sendMessage` in the foreground, with `transferUserInfo` as the
  background fallback when the session is unreachable.
- **iPhone-Dependent Inference**: The iPhone receives the WatchConnectivity
  payload and routes it through `OfflineQueueManager` and the Edge inference
  pipeline. All AI processing happens server-side — the watch has no direct
  Supabase or Gemini calls.
- **Storage Safety**: The temporary `.m4a` recording buffer is purged from the
  watch's `FileManager.temporaryDirectory` immediately after dispatch to prevent
  watchOS storage bloat.
