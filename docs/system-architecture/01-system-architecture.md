# Merian System Architecture

Merian is a biological classification and gamification platform built for iOS and watchOS. The architecture relies on decoupled modules connecting onboard Apple hardware to a Supabase PostgreSQL backend, bridging LLM inferences via Cloudflare R2 and Gemini models.

## Architectural Data Flow (Overview)

```mermaid
flowchart TD
    A([📱 Capture Workspace]) -->|Builds ordered media timeline + telemetry| B[OfflineQueueManager]
    B -->|Persists Locally if Off-grid| C[(SwiftData Native DB)]
    C -->|NWPathMonitor Awoken by Cell Tower| D{Network Status 200 OK}

    D -->|/generate-upload-urls| E[Cloudflare R2 Staging Bucket]
    E -->|URLSession Background PUT (staged images + queued audio)| F((Cloudflare R2))
    F -->|Background replay or live request| G([⚡️ Supabase Edge /identify-multimodal])

    G -->|Resolves mixed media & validates| H[🤖 Gemini 2.5 Flash / Pro]
    H -->|Returns structured result JSON| G

    G -->|Upserts biological dictionaries| I[(PostgreSQL `species_dictionary`)]
    G -->|Persists UUID scan constraints| J[(PostgreSQL `scans`)]

    K([Paused Photos Share Extension]) -. not embedded .-> E
    K -. parked /share-import-scan path .-> M([Supabase Edge /share-import-scan])
    M -->|Background identify dispatch| G
    C -->|Writes lightweight extension snapshots| N[(App Group Cache)]
    L([Messages Extension]) -->|Reads scan cache| N
    K -. parked receipt design .-> N
```

## Core Architectural Pillars

### 1. Dependency Injection (`AppDIContainer`)

- To prevent Massive Environment Object pollution and enforce separation of concerns, Merian uses a centralized `AppDIContainer`. This singleton holds and exposes all core orchestration services to view modifiers (like `CameraManager`, `InferenceEngine`, `EnvironmentContextManager`), avoiding scattered initializations across the app. To preserve the "Instant-On" zero-latency launch requirement, all dependencies are declared as `lazy var`. This bypasses eager Main Thread initialization during `MerianApp` boot, ensuring heavy hardware layers (`AVCaptureSession`) only spin up when requested by foreground SwiftUI `.onAppear` lifecycles.

### 2. Hardened Hardware Interfacing (`HardwareOrchestrator`, `CameraManager`, `EnvironmentContextManager`)

- Direct bindings into `AVCaptureSession`, negotiating `isHighResolutionPhotoEnabled` buffers using the ISP (Image Signal Processor) and Deep Fusion. The `DiscoverySession` prioritizes `.builtInTripleCamera` on Pro devices — exposing the full optical zoom range (0.5×–15×) while retaining LiDAR depth delivery via `AVCaptureDepthDataOutput` — before falling back to `.builtInLiDARDepthCamera` and single-lens devices. Zoom is surfaced via a `ZoomSliderView` on the right edge of the viewfinder and via vertical swipe and pinch gestures on the preview; the control hides itself (`isZoomSupported = maxZoomFactor >= 2.0`) on hardware without a meaningful zoom range.
- Active thermal monitoring manipulates OS frame rate (`targetFPS`) and renders Glassmorphism `.ultraThinMaterial` overlays dynamically to prevent critical heat loads in outdoor environments.
- **Native Camera Roll Integration (`PhotoLibraryManager`):** Persists unmodified `12MP` output into the user's local iOS `PHPhotoLibrary` on capture, avoiding iCloud sync delays.
- **Pre-warmed Tactile Shutter (`HapticManager`):** The app `.prepare()`s Taptic Engine instances (e.g. `UIImpactFeedbackGenerator(style: .medium)`) on app boot inside a global `HapticManager`. Centralizing haptics removes the ~20ms "cold" instantiation lag on physical button triggers. To protect the "Instant-On" launch requirement, these `.prepare()` calls are deferred inside a `Task { @MainActor }` sleeping 300ms, allowing the Main Thread to complete the heavy hardware layers (`AVCaptureSession`) unimpeded.
- **Battery-bounded Context Tracking (`EnvironmentContextManager`):** Manages `CoreLocation` and `WeatherKit` with coarse, pausable location updates while the camera is active, then fires a one-shot high-accuracy `requestLocation()` when the shutter is pressed. Heading updates are not started because compass telemetry is not part of the active inference payload. The shutter location is used for Camera Roll EXIF and deferred weather/geocode context, while stale cached coordinates remain a fallback if GPS cannot settle within the timeout. It also backfills historical edge metadata (GPS and past WeatherKit conditions) by mapping `PHAsset` EXIF data for library imports prior to inference.

### 2. Ephemeral Offline-First Sync (`OfflineQueueManager`, `SwiftData`)

- Employs a zero-data-loss queue structure tracking users without cellular data using `SwiftData` inside `MerianApp`. The durable unit is a canonical ordered mixed-media timeline, persisted once at submission time and reused across live inference, offline replay, thumbnails, and result hydration.
- `NWPathMonitor` observes 3G/off-grid boundaries, debouncing signals for 1.0 second when the hiker steps into cell service. It wraps a `UIBackgroundTaskIdentifier` as a 30-second timeout handler before handing payloads to an iOS `.background` `URLSession` daemon. `AppDelegate` hook completions are intercepted to satisfy iOS background Watchdog limits.

### 3. Serverless Edge Verification (`Supabase Edge Functions`, `Gemini 2.5 Flash / Pro`)

- A Cloud-native workflow decoupling Apple users from raw API logic.
- The `identify-multimodal` Deno Edge node accepts pre-signed multi-capture iOS uploads plus inline audio and description payloads. It handles image R2 streams and inline non-visual media under a shared validation path, enforcing a strict cumulative payload cap before evaluating the combined user context.
- `Task.checkCancellation()` boundaries are injected inside `InferenceEngine` before transferring `URLSession` data payloads to Cloudflare R2. If the iOS Watchdog or the user cancels a processing scan, execution aborts immediately to prevent cellular bandwidth leakage.

**Edge Function Map:**
The backend logic is strictly decoupled into modular, single-responsibility functions under `/services/supabase/functions/`.

> [!NOTE]
> All new and existing edge routers explicitly adhere to the **Domain-Driven Modular Architecture** (decoupling `index.ts` origin controllers from their localized `db.ts` PostgreSQL constraints). For formal logic construction rules defining Deno separation of concerns, see [`06-edge-modularization.md`](06-edge-modularization.md).

- **Identity & Analysis**
  - `/identify-multimodal`: The primary shipped inference orchestrator for live and replayed mixed-media captures.
  - `/identify`: Shared still-image entry point that reuses the same identify modules.
  - `/enrich-scan`: On-demand background enrichment for historical "Free" tier scans upgrading to Pro insight depths.
  - `/merge-ghost-profile`: Handles the Anonymous "Ghost" Scan to Authenticated User onboarding transition.
- **Export & Storage Orchestration**
  - `/request-export-dwca`: Client-facing synchronous API controlling 24-hour rate limits for data exports.
  - `/export-dwca`: Heavy background worker (triggered via Service-Role Webhook) that compiles paginated Darwin Core Zip archives and dispatches emails via the Resend Node SDK.
  - `/generate-upload-urls`: Provisions short-lived S3 Pre-signed URLs for direct-to-Cloudflare `PUT` pushes, keeping massive binaries out of the Edge proxy memory.
  - `/share-import-scan`: Parked fast-return queue endpoint for the paused Photos share extension. It validates one staged image key, inserts `scan_import_jobs`, and dispatches `/identify-multimodal` in the background. Current app builds do not embed `MerianShareExtension`, so this path should not receive production iOS client traffic.
- **Data Lifecycle & Offline Sync**
  - `/sync-collections`: Reconciles offline iOS SwiftData modifications with the Postgres single source of truth.
  - `/delete-scan` & `/safe-delete`: Atomic operations cascading Postgres deletions out to Cloudflare R2 blobs to prevent orphaned objects.
  - `/auto-purge-nonbio`: Automated webhook/cron job trimming non-biological captures while preserving biological sighting evidence.
- **Public Species Content**
  - `/species-dictionary`: Public species-level dictionary projection for the in-app species page and future web frontend.
  - `/refresh-species-content`: Internal service-role cron worker that consumes `species_content_provenance`, refreshes GBIF/Wikipedia-backed fields, and synchronizes normalized reference imagery.
  - `/refresh-merian-reference-images`: Internal service-role cron worker that promotes high-quality published Explore media into Merian-sourced species reference images and mirrors source visibility.
- **Public Web & Sharing**
  - `apps/web/`: Next.js + Mantine frontend for public Merian pages on `merian.earth`.
  - `/explore/post/[postId]`: Server-rendered public Explore share route. It calls the `get_explore_post` RPC from the Next.js server, emits Open Graph metadata for rich previews, and links back into the native app with `merian://explore/post/{postId}`.
  - `MerianMessagesExtension` reads the App Group scan cache and inserts image, card, or description content into Messages without sending automatically.
  - `MerianShareExtension` is paused and de-shipped as of 2026-05-19. Its source and backend queue path remain in the repo, but current app builds do not embed the extension or advertise Photos share-sheet import.
  - Universal Links should eventually bind `https://merian.earth/explore/post/{postId}` to the same native Explore detail router while preserving the web page as the fallback for users without the app.
- **Moderation & Social**
  - `/get-filtered-discovery-feed`: Paginates public discovery queries from post-owned sharing fields, handles blocking mechanisms, and uses scrubbed or rounded public coordinates when Explore surfaces are allowed to expose location.
  - `/block-user` & `/flag-issue`: Trust and Safety endpoint managers mitigating bad actors on the global feed.
- **Revenue Integration**
  - `/revenuecat-webhook`: Subscribes to realtime Apple/Google subscription transitions, stamping user tiers natively into Postgres bounds without client-side polling.

### 4. Continuous Gamification Ecosystem (`GamificationManager`, `RiveRuntime`)

- Tracks device-native state (`UserDefaults`), tying species identifications into `.riv` visual triggers inside interactive glassmorphic view modifiers (`Terrarium`).
- Binds global haptics to success triggers and interactions.

### 5. Private Analytics (`AppTelemetry`, `PostHog`)

- PII-free tracking mapping OS limits passively via `TelemetryClient`.
- Identifies usage funnels and telemetry across UI interactions with `PostHog`, mapped by UUID and automatically enriched with Email and Name identifiers from authenticated Supabase sessions.

### 6. UI Initialization & Memory Operations

- **Instant Cold Boot:** `AppTelemetry.initialize()` runs synchronously in `MerianApp.init()` (it is just config storage — no I/O). `PostHog.configure()` is idempotent and runs before Supabase auth begins restoring a session, preventing identity-link races. Heavy `CameraManager` hardware initialization (`AVCaptureSession.beginConfiguration`) stays off the critical render path.
- **RAM Image Cache (`ImageCache`):** A thread-safe `@unchecked Sendable` `NSCache` stores downsampled scan thumbnails in RAM, avoiding massive disk I/O thrashing during 120Hz `LazyVGrid` and `TabView` scrolling. This prevents OOM crashes and micro-stutters by capping at ~100 thumbnail entries, with iOS memory pressure controlling eviction.
- **Asynchronous Grid Downsampling:** Image-heavy views (`ScansSheetView`, `ScansGrid`, `InsightSheetView`, and the insight carousel) offload decoding onto a CPU pool using `ImageIO`'s `CGImageSourceCreateThumbnailAtIndex`, bounds-checking 12 MP files without allocating generic `Data` blocks. This keeps scrolling locked to 60fps on edge devices.

### 7. watchOS Extension (`MerianWatch`)

Merian includes a companion watchOS app for acoustic identification. The watch target captures and dispatches audio via WatchConnectivity and does **not** perform independent Supabase or Gemini calls. The iOS `WCSessionDelegate` receiver is not currently implemented, so watch payloads are not yet ingested by the iPhone offline queue.

- **Build Target Nuance**: Relies on the `MerianWatch` target in `project.yml`, explicit watchOS deployment settings, and correctly mapped `Contents.json` icon configurations inside `Assets.xcassets` to avoid watchOS Simulator deployment failures.
- **Acoustic Capture (`WatchAcousticManager`)**: Records a 15-second AAC audio clip via `AVAudioRecorder`. Simultaneously acquires `CLLocation` coordinates and `WeatherKit` context to bundle environmental metadata with the audio payload.
- **WatchConnectivity Bridge**: Once recording completes, the encoded payload (base64 audio + GPS + weather) is dispatched to the companion iPhone via `WCSession.sendMessage` in the foreground, with `transferUserInfo` as the background fallback when the session is unreachable.
- **iPhone-Dependent Inference**: The iPhone receives the WatchConnectivity payload and routes it through `OfflineQueueManager` and the Edge inference pipeline. All AI processing happens server-side — the watch has no direct Supabase or Gemini calls.
- **Storage Safety**: The temporary `.m4a` recording buffer is purged from the watch's `FileManager.temporaryDirectory` immediately after dispatch to prevent watchOS storage bloat.
