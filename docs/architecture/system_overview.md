# Merian System Architecture Overview

Merian relies on an aggressive "Zero-OOM" (Out Of Memory) design philosophy targeting seamless, native performance on iOS hardware. The system completely decouples the expensive Machine Learning payload extraction logic to Supabase Serverless Edge infrastructure to protect the physical battery bounds of the device.

## High-Level Pipeline

When the user physically captures an image within the application, the architecture triggers a perfectly synchronized orchestration of singletons:

1. **Physical Hardware Abstraction**: `HardwareOrchestrator` governs the `CameraManager`, locking white balance and grabbing the exact physics coordinates (`CLLocationCoordinate2D`, Elevation, and LiDAR `subjectDistanceInMeters`).
2. **Ephemeral Network Abstraction**: If the `NWPathMonitor` determines the device has active network bounds, `OfflineQueueManager` asks the Supabase Edge (`generate-upload-urls`) for a temporary Cloudflare R2 Upload link and `PUT`s the file automatically in the background.
3. **Biological Inference (`InferenceEngine.swift`)**: Fires the exact R2 key, `subjectDistanceInMeters`, `deviceLocale`, and GPS logic explicitly to the Supabase `/identify` Edge Node, strictly shielding the frontend Swift code from knowing the `GEMINI_API_KEY`.
4. **Offline Resilience (`OfflineQueueManager.swift`)**: Should the user be off-grid on a hike, the binary payload is routed to a `.documentDirectory` caching folder and a `SwiftData` row is marked `isOfflineQueued = true`. Apple's `URLSession` Background protocols passively trigger upload logic directly when OS-level radio arrays regain access.

## Core Decoupling (AppDIContainer)

Merian actively rejects standard `@EnvironmentObject` propagation for complex business logic, to completely shield the `View` lifecycle from triggering recursive structural updates or `EXC_BAD_ACCESS` memory warnings.

Everything is statically bound within `AppDIContainer.swift`:

- A global singleton providing structured `protocol`-free dependency injection precisely.
- Centralizes `.handleActivePhase()`, `.handleBackgroundPhase()`, and `.handleInactivePhase()` application lifecycle handlers to instantly pause expensive components (like AVCaptureSession) and execute `archiveManager.evaluateAndRescueAgingScans()` background tasks silently once a day natively.

## SwiftData & Data Layer

A rigid standard mapped over native native SwiftData migrations:

- Models natively stored inside `LocalScanRecord` directly map one-to-one with Postgres `/scans` rows natively via UUID bounds.
- Schema versioning handles structural modifications cleanly.
- Implements the "Archive Safety Protocol" via `ArchiveManager.swift`, preserving the physics blobs of Free-tier users logically before Cloudflare's 90-day R2 Lifecycle Deletion Rule executes. This protects the native `LifeList` offline caches against sudden Cloud purges.

## Identity Pipeline

Identity mapping completely abandons traditional brittle user authentication screens relying strictly on hardware identity mappings naturally:

- `DeviceIdentityManager` grabs the `identifierForVendor` directly from the OS.
- Bound directly into `SupabaseManager` inside `signInAnonymously()` generating an "Explorer Tier" Ghost identity.
- Authenticated Apple/Google Native OAuth flows merge these `.uuidString` paths precisely securely mapping onto RevenueCat and PostHog funnels securely.

## Privacy & Geoprivacy Focus

GPS and Coordinate logging natively maps out strictly against European GDPR policies cleanly:

- Edge nodes naturally convert "Endangered" species taxonomies implicitly, wiping arrays and reducing exact precision to a 50km offset.
- `user_blocks` SQL mapping executes entirely on Edge nodes securely bypassing native IDOR limits securely.
