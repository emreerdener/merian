# Naturebook System Architecture Overview

Naturebook is a biological field identification app for iOS. Point the camera at any plant, insect, fungus, or animal — or describe a subject by voice in the Describe mode — and Naturebook identifies it using Gemini AI, records GPS telemetry and weather context, and builds a personal species journal that works fully offline. The repository, Xcode project, targets, modules, and stable service identifiers retain the Merian engineering identity.

Naturebook is built around a "Zero-OOM" (Out Of Memory) design philosophy targeting stable, native performance on iOS hardware. Expensive machine learning work is offloaded to Supabase Serverless Edge infrastructure to protect device battery and memory.

## High-Level Pipeline

When the user captures an image or imports one from Photos, the architecture
triggers a coordinated sequence of singletons. A shared Photos image first
passes through `MerianApp.onOpenURL` and `ExternalImageImportStore`, which owns a
durable app-sandbox copy before Capture begins this pipeline:

1. **Capture Context**: Live camera input uses `HardwareOrchestrator` and
   `CameraManager` to lock white balance and read shutter-time coordinates,
   elevation, and LiDAR distance while WeatherKit and reverse geocoding are
   prefetched. PhotosPicker and shared-file imports use their embedded historical
   context instead; shared files preserve only valid EXIF date/GPS values and do
   not invent missing metadata.
2. **Durable Acceptance**: `OfflineQueueManager` persists the ordered media timeline and one stable `scan_id` before live inference. An eligible live-camera still scan is temporarily excluded from background upload so it does not compete with the inline request.
3. **Biological Inference (`InferenceEngine.swift`)**: For that live-camera still path, after at most 150 ms of environmental-context grace, the pinned network client sends inline media and `CaptureTelemetry` to `/identify-multimodal`, keeping `GEMINI_API_KEY` off the client. The request-body completion callback then releases the durable queue for R2/background recovery. Late context is applied through `/update-scan-context` without a second model call. Gallery, audio-bearing, and video submissions retain their existing behavior while receiving pipeline instrumentation.
4. **First Result**: The Edge route verifies cached ES256 claims, performs one atomic ingestion-setup RPC, calls the unchanged tier model once, and uses at most one combined cached dictionary-hydration RPC for eligible biological results. Parsed and locally persisted `speciesData` renders before awards, Field trips, and cache-miss enrichment.
5. **Offline Resilience**: If a user is off-grid, the payload is written to `.documentDirectory` and a `SwiftData` row is inserted with `scanStateRaw = 0` (`.pending`). Apple's background `URLSession` triggers upload when connectivity returns. Offline queuing is gated by the daily scan quota (`UsageManager.canPerformScan`) — free users who have exhausted their 1-scan-per-day limit hit the paywall at capture time rather than at sync time. Every scan that enters the queue is already paid for and uploads unconditionally. Successful non-biological results count as scan attempts; the scoped non-biological correction reanalysis bypasses only the Pro feature gate, not daily scan accounting.

Free inference remains `gemini-2.5-flash` and Pro remains
`gemini-2.5-pro`. The latency path does not change prompts, schema, thinking
budgets, image resolution, output limits, or the one-model-call contract.

The species dictionary is the reusable public content layer that sits beside scan-specific inference. Insight similar-species cards and Explore post detail similar-species cards route into `/species-dictionary`; the scheduled `/refresh-species-content` worker keeps GBIF/Wikipedia-backed dictionary fields fresh, `/refresh-species-model-content` fills queued habitat, lookalikes, and group tags, and `/refresh-merian-reference-images` promotes high-quality published Explore media into Merian-sourced reference images. The public species payload never exposes source scan/post/location provenance; for a currently promoted Naturebook image it purposefully resolves only the contributor's public user ID and current public username so iOS can link the photo badge to the existing public profile sheet.

Naturebook also has a small public web frontend in `apps/web/`.
`https://naturebook.earth/explore/post/{postId}` server-renders a public Explore
post from the `get_explore_post` RPC, emits Open Graph metadata, and hydrates a
square ordered image/video/audio carousel. Public video autoplays muted and
loops only while selected; audio uses the persisted spectrogram, native
controls, and an optional browser-local Boost Audio graph. The allowlisted
`/api/explore/audio` route exists only to provide same-origin public WAV bytes
for that graph.

`https://naturebook.earth/species/{speciesId}/{slug}` server-renders the
versioned public `/species-dictionary` Edge response. The UUID is authoritative;
the lowercase ASCII slug is derived from public names, is never used for lookup,
and UUID-only or stale-slug browser requests permanently redirect to the current
canonical path. The page exposes species reference data only, audits image
license and attribution before page or metadata use, omits lookalike thumbnails
without rights fields, and offers a `naturebook://species/{speciesId}` native
CTA. Invalid/missing species are non-indexable 404s; transient Edge failures
remain server errors.

These web surfaces are public projections only. They must never expose exact
coordinates, private notes, raw scan telemetry, authenticated Community
sightings, local observation aggregates, user media, or server credentials.

## Core Decoupling (AppDIContainer)

The Merian app module does not use `@EnvironmentObject` for its core architectural engines. All complex business logic is bound using `@Observable` macros and `@Environment()` injection to keep the `View` lifecycle free from recursive updates or `EXC_BAD_ACCESS` warnings.

Everything is wired in `AppDIContainer.swift`:

- A global singleton providing protocol-free dependency injection.
- Centralizes `.handleActivePhase()`, `.handleInactivePhase()`, and `.handleBackgroundPhase()` lifecycle handlers to manage hardware state, historical sync, non-biological cleanup, and queue recovery. It also manages the background inference race: `CaptureWorkspaceViewModel` observes the inactive phase to reset view state but does not nil out active ML payloads — that is reserved for `handleBackgroundPhase()`. When the app backgrounds mid-inference, Pro users have their capture enqueued to `OfflineQueueManager` (resuming via background URLSession) and the live request is cancelled. Free users have their in-flight request left running within iOS's ~30-second background window; on completion, `InferenceEngine.analyze()` dispatches a push notification.
- App backgrounding also releases any process-local live-upload suppression so
  the already-durable queue row becomes eligible for background recovery. App
  termination cannot strand a row because the suppression set is not persisted.

## SwiftData & Data Layer

A structured schema built on native SwiftData migrations:

- `LocalScanRecord` models map their UUIDs **1-to-1 with Postgres `/scans` rows**. An earlier architecture attempted to merge multiple scans of the same species into an `additionalImagePaths` array locally, which caused the background `ScanRepository` synchronizer to spawn duplicate tiles because the cloud ID didn't match the local random UUID.
- *Grid Rendering Rule*: Every shutter press generates a distinct tile in the `Scans` view, matching the iOS Photos app pattern and preventing cloud duplication. Gamification telemetry hashes against `scientificName` to prevent duplicate local unique-species progress for the same biological subject, while global "New to Naturebook" milestones use the technically stable `is_new_to_merian_dictionary` identify response flag and are suppressed for non-biological or processed-material results.
- *Scan Milestone Boundary*: `ScanMilestoneCoordinator` is the shared
  foreground/background completion boundary keyed by the final Postgres scan
  UUID. It waits for server persistence and Field trip progress, then batches
  standard outings, Events-visible Seasonal Challenges, achievements, and
  **New to Naturebook** in that order. This prevents the live inference task and
  background URLSession completion from presenting duplicate notifications.
- Schema versioning handles migrations cleanly.
- `#Predicate` constraints use `.localizedStandardContains()` for robust case-insensitive SQLite matches across `ScanRepository`.
- Keeps biological scan media durable in cloud storage; `ArchiveManager.swift` is limited to generated dataset archive downloads rather than timed scan-media rescue.
- **Transactional Deletions**: `ScanRepository.eradicateScan` commits SwiftData changes first (delete record, insert cloud task, save) and only purges local scan media via `FileIOActor` after the save succeeds. A save failure rolls back pending context changes and leaves state fully consistent — no orphaned database records with missing media.
- **Historical Sync**: `syncHistoricalScansDown` paginates both scans and collections cloud fetches (via `.range(from:to:)`), then reconciles data dynamically via `HistoricalDatabaseActor.reconcileScanPage`, avoiding memory accumulation of the entire scan library.
- **Centralized Policy (`MerianConfig`)**: All batch sizes, page sizes, and retention window constants are defined in `MerianConfig.swift`. Tuning any policy constant requires exactly one change.

## Identity Pipeline

- `DeviceIdentityManager` reads `identifierForVendor` from the OS.
- Passed into `SupabaseManager.signInAnonymously()` to generate an "Explorer Tier" Ghost identity.
- Authenticated Apple/Google OAuth flows merge Ghost rows into the permanent
  Supabase Auth UUID. That UUID becomes the RevenueCat App User ID and PostHog
  distinct ID; RevenueCat subscriber attributes carry auth email and public
  identity fields for dashboard support lookups.

## Privacy & Geoprivacy Focus

GPS and coordinate logging complies with European GDPR policies:

- Edge nodes convert "Endangered" species taxonomies, wiping exact coordinates and reducing precision to a 50km offset.
- `user_blocks` SQL logic executes on Edge nodes to prevent IDOR vulnerabilities.
