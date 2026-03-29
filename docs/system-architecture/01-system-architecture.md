# Merian System Architecture

Merian is a biological classification and gamification platform built for iOS and watchOS. The architecture relies on decoupled modules connecting onboard Apple hardware to a Supabase PostgreSQL backend, bridging LLM inferences via Cloudflare R2 and Gemini models.

## Architectural Data Flow (Overview)

```mermaid
flowchart TD
    A([📱 iPhone Lens / CameraManager]) -->|Snaps high-res JPEG & Sensors| B[OfflineQueueManager]
    B -->|Persists Locally if Off-grid| C[(SwiftData Native DB)]
    C -->|NWPathMonitor Awoken by Cell Tower| D{Network Status 200 OK}

    D -->|/generate-upload-urls| E[Cloudflare R2 Staging Bucket]
    E -->|URLSession Background PUT (Concurrent Arrays)| F((Cloudflare R2))
    F -->|Supabase Storage Webhook| G([⚡️ Supabase Edge /identify])

    G -->|Fetches ArrayBuffers concurrently & Validates| H[🤖 Gemini 2.5 Flash / Pro]
    H -->|Combines Visual Context & Extracts Strict JSON| G

    G -->|Upserts biological dictionaries| I[(PostgreSQL `species_dictionary`)]
    G -->|Persists UUID scan constraints| J[(PostgreSQL `scans`)]
```

## Core Architectural Pillars

### 1. Dependency Injection (`AppDIContainer`)

- To prevent Massive Environment Object pollution and enforce separation of concerns, Merian uses a centralized `AppDIContainer`. This singleton holds and exposes all core orchestration services to view modifiers (like `CameraManager`, `InferenceEngine`, `EnvironmentContextManager`), avoiding scattered initializations across the app. To preserve the "Instant-On" zero-latency launch requirement, all dependencies are declared as `lazy var`. This bypasses eager Main Thread initialization during `MerianApp` boot, ensuring heavy hardware layers (`AVCaptureSession`) only spin up when requested by foreground SwiftUI `.onAppear` lifecycles.

### 2. Hardened Hardware Interfacing (`HardwareOrchestrator`, `CameraManager`, `EnvironmentContextManager`)

- Direct bindings into `AVCaptureSession`, negotiating `isHighResolutionPhotoEnabled` buffers using the ISP (Image Signal Processor) and Deep Fusion. The `DiscoverySession` prioritizes `.builtInTripleCamera` on Pro devices — exposing the full optical zoom range (0.5×–15×) while retaining LiDAR depth delivery via `AVCaptureDepthDataOutput` — before falling back to `.builtInLiDARDepthCamera` and single-lens devices. Zoom is surfaced via a `ZoomSliderView` on the right edge of the viewfinder and via vertical swipe and pinch gestures on the preview; the control hides itself (`isZoomSupported = maxZoomFactor >= 2.0`) on hardware without a meaningful zoom range.
- Active thermal monitoring manipulates OS frame rate (`targetFPS`) and renders Glassmorphism `.ultraThinMaterial` overlays dynamically to prevent critical heat loads in outdoor environments.
- **Native Camera Roll Integration (`PhotoLibraryManager`):** Persists unmodified `12MP` output into the user's local iOS `PHPhotoLibrary` on capture, avoiding iCloud sync delays.
- **Pre-warmed Tactile Shutter (`HapticManager`):** The app `.prepare()`s Taptic Engine instances (e.g. `UIImpactFeedbackGenerator(style: .medium)`) on app boot inside a global `HapticManager`. Centralizing haptics removes the ~20ms "cold" instantiation lag on physical button triggers. To protect the "Instant-On" launch requirement, these `.prepare()` calls are deferred inside a `Task { @MainActor }` sleeping 300ms, allowing the Main Thread to complete the heavy hardware layers (`AVCaptureSession`) unimpeded.
- **Live Context Tracking & Zero-Latency Capture (`EnvironmentContextManager`):** Manages `CoreLocation` and `WeatherKit` by continuously tracking coordinates (`cachedLocation`) in the background while the camera is active. On any shutter trigger (UI or hardware button), it snapshots the coordinates with zero latency and stamps them inside the `PHAssetCreationRequest`, writing GPS bounds directly into the EXIF output of the locally saved 12 MP photo. It runs a concurrent `MKReverseGeocodingRequest` to map semantic location names (e.g. `San Francisco, CA`) via MapKit into the local SwiftData `MerianSchemaV6` database for UI display. It also backfills historical edge metadata (GPS and past WeatherKit conditions) by mapping `PHAsset` EXIF data for library imports prior to inference.

### 2. Ephemeral Offline-First Sync (`OfflineQueueManager`, `SwiftData`)

- Employs a zero-data-loss queue structure tracking users without cellular data using `SwiftData` inside `MerianApp`. It intercepts `URLError` network timeouts from the live `InferenceEngine`, capturing the unified `CaptureTelemetry` hardware context and writing images to the documents directory.
- `NWPathMonitor` observes 3G/off-grid boundaries, debouncing signals for 1.0 second when the hiker steps into cell service. It wraps a `UIBackgroundTaskIdentifier` as a 30-second timeout handler before handing payloads to an iOS `.background` `URLSession` daemon. `AppDelegate` hook completions are intercepted to satisfy iOS background Watchdog limits.

### 3. Serverless Edge Verification (`Supabase Edge Functions`, `Gemini 2.5 Flash / Pro`)

- A Cloud-native workflow decoupling Apple users from raw API logic.
- The `identify` Deno Edge node accepts pre-signed multi-capture iOS uploads. It handles concurrent R2 array streams via `Promise.allSettled`, enforcing a strict 5 MB cumulative buffer size constraint to shield the Deno V8 engine from OOM heap crashes before evaluating the combined visual context across all images.
- `Task.checkCancellation()` boundaries are injected inside `InferenceEngine` before transferring `URLSession` data payloads to Cloudflare R2. If the iOS Watchdog or the user cancels a processing scan, execution aborts immediately to prevent cellular bandwidth leakage.

**Edge Function Map:**
The backend logic is strictly decoupled into modular, single-responsibility functions under `/supabase/functions/`:

- **Identity & Analysis**
  - `/identify`: The primary vision orchestrator ensuring sub-4s TTFM.
  - `/enrich-scan`: On-demand background enrichment for historical "Free" tier scans upgrading to Pro insight depths.
  - `/merge-ghost-profile`: Handles the Anonymous "Ghost" Scan to Authenticated User onboarding transition.
- **Export & Storage Orchestration**
  - `/request-export-dwca`: Client-facing synchronous API controlling 24-hour rate limits for data exports.
  - `/export-dwca`: Heavy background worker (triggered via Service-Role Webhook) that compiles paginated Darwin Core Zip archives and dispatches Resend emails.
  - `/generate-upload-urls`: Provisions short-lived S3 Pre-signed URLs for direct-to-Cloudflare `PUT` pushes, keeping massive binaries out of the Edge proxy memory.
- **Data Lifecycle & Offline Sync**
  - `/sync-collections`: Reconciles offline iOS SwiftData modifications with the Postgres single source of truth.
  - `/delete-scan` & `/safe-delete`: Atomic operations cascading Postgres deletions out to Cloudflare R2 blobs to prevent orphaned objects.
  - `/auto-purge-domesticated` & `/auto-purge-nonbio`: Automated webhook/cron jobs actively trimming non-wildlife data to maintain taxonomic dataset integrity.
- **Moderation & Social**
  - `/get-filtered-discovery-feed`: Paginates heavy spatial queries (abstracting global `geoprivacy = 'open'` filtering away from the mobile client), handles blocking mechanisms, and destructively rounds coordinates natively via the IUCN Red List index to protect vulnerable species from poachers.
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

- **Instant Cold Boot:** `AppTelemetry.initialize()` runs synchronously in `MerianApp.init()` (it is just config storage — no I/O). `PostHog.configure()` and heavy `CameraManager` hardware initialization (`AVCaptureSession.beginConfiguration`) are deferred onto a `Task.detached(priority: .background)` executor, preventing the Main Actor from blocking and ensuring a sub-1-second boot for the Camera pipeline.
- **RAM Image Cache (`ImageCache`):** A thread-safe `@unchecked Sendable` `NSCache` stores downsampled scan thumbnails in RAM, avoiding massive disk I/O thrashing during 120Hz `LazyVGrid` and `TabView` scrolling. This prevents OOM crashes and micro-stutters by capping at ~100 thumbnail entries, with iOS memory pressure controlling eviction.
- **Asynchronous Grid Downsampling:** Image-heavy views (`ScansSearchView`, `InsightSheetView`, `InsightCarousel`) offload decoding onto a CPU pool using `ImageIO`'s `CGImageSourceCreateThumbnailAtIndex`, bounds-checking 12 MP files without allocating generic `Data` blocks. This keeps scrolling locked to 60fps on edge devices.

### 7. watchOS Extension (`MerianWatch`)

Merian functions as a standalone watchOS executable, decoupled from the host iPhone:
- **Build Target Nuance**: Relies on explicit `project.yml` product type declarations (`watch2-app`) and correctly mapped `Contents.json` icon configurations inside `Assets.xcassets` to avoid watchOS Simulator deployment failures.
- **`WKInterfaceDevice.current().identifierForVendor` Execution**: Mimics iOS bindings, syncing the anonymous user UUID via `WatchConnectivity.WCSession` to iOS Core boundaries.
- Uses `Network.framework` hooks and `URLSession` to hit Supabase Edge from the wrist, supporting independent inferences when the iPhone is unavailable.
- Shares the core `InsightSheetView` logic and data models to provide biological readouts without the parent app in range.
