# Merian System Architecture Overview

Merian is a biological field identification app for iOS. Point the camera at any plant, insect, fungus, or animal — or describe a subject by voice in the Describe mode — and Merian identifies it using Gemini AI, records GPS telemetry and weather context, and builds a personal species journal that works fully offline.

Merian is built around a "Zero-OOM" (Out Of Memory) design philosophy targeting stable, native performance on iOS hardware. Expensive machine learning work is offloaded to Supabase Serverless Edge infrastructure to protect device battery and memory.

## High-Level Pipeline

When the user captures an image, the architecture triggers a coordinated sequence of singletons:

1. **Hardware Abstraction**: `HardwareOrchestrator` governs `CameraManager`, locking white balance and reading the exact location coordinates (`CLLocationCoordinate2D`, elevation, and LiDAR `subjectDistanceInMeters`).
2. **Network Abstraction**: If `NWPathMonitor` reports an active connection, `OfflineQueueManager` asks the Supabase Edge (`generate-upload-urls`) for a temporary Cloudflare R2 upload URL and `PUT`s the file in the background.
3. **Biological Inference (`InferenceEngine.swift`)**: Fires the R2 key and `CaptureTelemetry` to the Supabase `/identify` Edge Node, keeping the `GEMINI_API_KEY` off the client.
4. **Offline Resilience**: If a user is off-grid, the payload is written to `.documentDirectory` and a `SwiftData` row is inserted with `scanStateRaw = 0` (`.pending`). Apple's background `URLSession` triggers upload when connectivity returns. Offline queuing is gated by the daily scan quota (`UsageManager.canPerformScan`) — free users who have exhausted their 2-scan-per-day limit hit the paywall at capture time rather than at sync time. Every scan that enters the queue is already paid for and uploads unconditionally.

Photos share-sheet imports use a lighter variant of the same staging/inference
architecture. `MerianShareExtension` receives one `public.image`, downsamples it,
extracts EXIF timestamp/GPS when present, requests `/generate-upload-urls`,
uploads the image to R2, calls `/share-import-scan`, writes an App Group receipt,
and exits. The containing app later reconciles that receipt through historical
scan sync. The SwiftData store remains app-owned and is not opened by the share
extension.

The species dictionary is the reusable public content layer that sits beside scan-specific inference. Insight similar-species cards and Explore post detail similar-species cards route into `/species-dictionary`; the scheduled `/refresh-species-content` worker keeps GBIF/Wikipedia-backed dictionary fields fresh, while `/refresh-merian-reference-images` promotes high-quality published Explore media into Merian-sourced reference images without exposing scan/post/user provenance through public species APIs.

Merian also has a small public web frontend in `apps/web/`. The first route, `https://merian.earth/explore/post/{postId}`, server-renders a public Explore post from the `get_explore_post` RPC and emits Open Graph metadata for share previews. This web surface is a public projection only: it may show public species, image, author, count, and privacy-filtered location fields, but it must never expose exact coordinates, private notes, raw scan telemetry, or server credentials.

## Core Decoupling (AppDIContainer)

Merian does not use `@EnvironmentObject` for its core architectural engines. All complex business logic is bound using `@Observable` macros and `@Environment()` injection to keep the `View` lifecycle free from recursive updates or `EXC_BAD_ACCESS` warnings.

Everything is wired in `AppDIContainer.swift`:

- A global singleton providing protocol-free dependency injection.
- Centralizes `.handleActivePhase()`, `.handleInactivePhase()`, and `.handleBackgroundPhase()` lifecycle handlers to manage hardware state and background tasks (such as `archiveManager.evaluateAndRescueAgingScans()`). It also manages the background inference race: `CaptureWorkspaceViewModel` observes the inactive phase to reset view state but does not nil out active ML payloads — that is reserved for `handleBackgroundPhase()`. When the app backgrounds mid-inference, Pro users have their capture enqueued to `OfflineQueueManager` (resuming via background URLSession) and the live request is cancelled. Free users have their in-flight request left running within iOS's ~30-second background window; on completion, `InferenceEngine.analyze()` dispatches a push notification.

## SwiftData & Data Layer

A structured schema built on native SwiftData migrations:

- `LocalScanRecord` models map their UUIDs **1-to-1 with Postgres `/scans` rows**. An earlier architecture attempted to merge multiple scans of the same species into an `additionalImagePaths` array locally, which caused the background `ScanRepository` synchronizer to spawn duplicate tiles because the cloud ID didn't match the local random UUID.
- *Grid Rendering Rule*: Every shutter press generates a distinct tile in the `Scans` view, matching the iOS Photos app pattern and preventing cloud duplication. Gamification telemetry hashes against `scientificName` to prevent multiple "New Discovery" awards for the same subject.
- Schema versioning handles migrations cleanly.
- `#Predicate` constraints use `.localizedStandardContains()` for robust case-insensitive SQLite matches across `ScanRepository`.
- Implements the "Archive Safety Protocol" via `ArchiveManager.swift`, preserving Free-tier user data before the targeted 90-day domesticated edge function deletion executes.
- **Transactional Deletions**: `ScanRepository.eradicateScan` commits SwiftData changes first (delete record, insert cloud task, save) and only purges local image files via `FileIOActor` after the save succeeds. A save failure rolls back pending context changes and leaves state fully consistent — no orphaned database records with missing images.
- **Historical Sync**: `syncHistoricalScansDown` paginates both scans and collections cloud fetches (via `.range(from:to:)`), then reconciles data dynamically via `HistoricalDatabaseActor.reconcileScanPage`, avoiding memory accumulation of the entire scan library.
- **Centralized Policy (`MerianConfig`)**: All batch sizes, page sizes, storage thresholds, and retention window constants are defined in `MerianConfig.swift`. Tuning any policy constant requires exactly one change.

## Identity Pipeline

- `DeviceIdentityManager` reads `identifierForVendor` from the OS.
- Passed into `SupabaseManager.signInAnonymously()` to generate an "Explorer Tier" Ghost identity.
- Authenticated Apple/Google OAuth flows merge these `.uuidString` paths onto RevenueCat and PostHog funnels.

## Privacy & Geoprivacy Focus

GPS and coordinate logging complies with European GDPR policies:

- Edge nodes convert "Endangered" species taxonomies, wiping exact coordinates and reducing precision to a 50km offset.
- `user_blocks` SQL logic executes on Edge nodes to prevent IDOR vulnerabilities.
