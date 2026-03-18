# Merian System Architecture Overview

Merian relies on an aggressive "Zero-OOM" (Out Of Memory) design philosophy targeting seamless, native performance on iOS hardware. The system completely decouples the expensive Machine Learning payload extraction logic to Supabase Serverless Edge infrastructure to protect the physical battery bounds of the device.

## High-Level Pipeline

When the user physically captures an image within the application, the architecture triggers a perfectly synchronized orchestration of singletons:

1. **Physical Hardware Abstraction**: `HardwareOrchestrator` governs the `CameraManager`, locking white balance and grabbing the exact physics coordinates (`CLLocationCoordinate2D`, Elevation, and LiDAR `subjectDistanceInMeters`).
2. **Ephemeral Network Abstraction**: If the `NWPathMonitor` determines the device has active network bounds, `OfflineQueueManager` asks the Supabase Edge (`generate-upload-urls`) for a temporary Cloudflare R2 Upload link and `PUT`s the file automatically in the background.
3. **Biological Inference (`InferenceEngine.swift`)**: Fires the exact R2 key, `subjectDistanceInMeters`, `deviceLocale`, and GPS logic explicitly to the Supabase `/identify` Edge Node, strictly shielding the frontend Swift code from knowing the `GEMINI_API_KEY`.
4. **Offline Resilience (Pro Feature)**: Should a Merian Pro user be off-grid on a hike, the binary payload successfully clears the `RevenueCatManager.shared.isProActive` boundary and is routed to a `.documentDirectory` caching folder and a `SwiftData` row is marked `isOfflineQueued = true`. Apple's `URLSession` Background protocols passively trigger upload logic directly when OS-level radio arrays regain access. Free users actively encounter an `APIError.proRequiredForOfflineTracking` boundary gracefully surfacing a Paywall.

## Core Decoupling (AppDIContainer)

Merian actively rejects standard `@EnvironmentObject` propagation for complex business logic, to completely shield the `View` lifecycle from triggering recursive structural updates or `EXC_BAD_ACCESS` memory warnings.

Everything is statically bound within `AppDIContainer.swift`:

- A global singleton providing structured `protocol`-free dependency injection precisely.
- Centralizes `.handleActivePhase()`, `.handleInactivePhase()`, and `.handleBackgroundPhase()` application lifecycle handlers to manage hardware physics and background tasks (like `archiveManager.evaluateAndRescueAgingScans()`). Crucially, it manages the offline rescue race condition: native UI closures like `CameraViewModel` observe the inactive phase to cleanly reset view bounds but strictly refrain from aggressively nilling out active ML payloads natively. This explicitly allows `AppDIContainer.handleBackgroundPhase()` to safely intercept and gracefully rescue mid-flight native inference captures directly into the `OfflineQueueManager` before securely triggering `inferenceEngine.cancelActiveRequest()`, permanently guaranteeing zero-data loss for off-grid users navigating away from the app constraints.

## SwiftData & Data Layer

A rigid standard mapped over native native SwiftData migrations:

- Models natively stored inside `LocalScanRecord` strictly map their UUIDs **1-to-1 with physical Postgres `/scans` rows**. The platform previously attempted to merge multiple scans of the same species into a hidden `additionalImagePaths` array locally, which caused a race condition where the background `ScanRepository` network synchronizer would spawn a duplicate "ghost" tile because the Cloud ID didn't match the Local random UUID. 
- *Grid Rendering Rule*: Every shutter press now generates a distinct physical tile in the `Scans` exactly mimicking the iOS Photos app, completely preventing cloud duplication loops. Gamification telemetry uniquely hashes against the `scientificName` to prevent giving users multiple "New Discovery" awards for identical subjects.
- Schema versioning handles structural modifications cleanly.
- Implements the "Archive Safety Protocol" via `ArchiveManager.swift`, preserving the physics blobs of Free-tier users logically before Cloudflare's 90-day R2 Lifecycle Deletion Rule executes. This protects the native `Scans` offline caches against sudden Cloud purges.

## Identity Pipeline

Identity mapping completely abandons traditional brittle user authentication screens relying strictly on hardware identity mappings naturally:

- `DeviceIdentityManager` grabs the `identifierForVendor` directly from the OS.
- Bound directly into `SupabaseManager` inside `signInAnonymously()` generating an "Explorer Tier" Ghost identity.
- Authenticated Apple/Google Native OAuth flows merge these `.uuidString` paths precisely securely mapping onto RevenueCat and PostHog funnels securely.

## Privacy & Geoprivacy Focus

GPS and Coordinate logging natively maps out strictly against European GDPR policies cleanly:

- Edge nodes naturally convert "Endangered" species taxonomies implicitly, wiping arrays and reducing exact precision to a 50km offset.
- `user_blocks` SQL mapping executes entirely on Edge nodes securely bypassing native IDOR limits securely.
