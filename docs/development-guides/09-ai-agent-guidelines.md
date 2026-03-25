# Merian AI Code Conventions & Guidelines

When generating or modifying code for Merian, follow these constraints to ensure optimal performance, hardware safety, and architectural consistency.

## 0. The Documentation Directory
The `docs/` folder contains the master reference for the application:
- Refer to `docs/system-architecture/system-overview.md` for overall architecture and pipeline logic.
- Refer to `docs/system-architecture/13-zero-oom-and-concurrency.md` for strict P0 iOS and Deno concurrency/memory safety rules.
- Refer to `docs/features-and-hardware/02-camera-and-hardware.md` for hardware integrations like LiDAR and precise telemetry snapshots.
- Refer to `docs/backend-and-data/07-database-schema.md` for PostgreSQL & SwiftData schemas.
- Refer to `docs/backend-and-data/08-api-contracts.md` for all network request/response shapes.
- Refer to `docs/backend-and-data/03-offline-sync-pipeline.md` for offline queue, sync state machine, and deletion architecture.
- Refer to `docs/development-guides/02-app-lifecycle.md` for `AppLifecycleManager` phase contracts and trigger ordering.
- Refer to `docs/system-architecture/14-image-pipeline.md` for capture → disk → cache → display image flow.

## 1. Project Generation (XcodeGen)
- **NEVER** directly modify `Merian.xcodeproj`.
- **ALWAYS** update `project.yml` when adding new packages, frameworks, scopes, or entitlements.
- Run `xcodegen generate` before attempting to build.
- API Keys must be injected via `Config.xcconfig` or `MerianEnvironment.swift`. NEVER hardcode `GEMINI_API_KEY` or `SUPABASE_ANON_KEY` inside `.swift` files.

## 2. Directory Structure
The workspace enforces this layout inside `merian/`:
- `Features/`: Complete user domains (`Camera`, `Insights`, `Scans`, `Profile`, `Settings`).
- `Core/`: Foundational logic organized into subdirectories:
  - `AI/`: `InferenceEngine`, `InferenceProcessingActor`
  - `Data/Database/`: `BackgroundDatabaseActor`, `FileIOActor`, `HistoricalDatabaseActor`, `ScanRepository`
  - `Data/Images/`: `LocalImageLoader`, `ImageCache`, `ArchiveManager`, `PhotoLibraryManager`
  - `Data/OfflineSync/`: `OfflineQueueManager`, `SyncStateManager`, `CircuitBreakerManager`
  - `Hardware/`: `CameraManager`, `HardwareOrchestrator`, `EnvironmentContextManager`
  - `Network/`: `MerianNetworkClient`, `SupabaseManager`
  - `Security/`: `KeychainManager`, `DeviceIdentityManager`
  - `Utilities/`: `MerianConfig`, `AppLifecycleManager`, `BackgroundTaskWrapper`, `ImageDownsampler`, `MerianLog`
  - `Analytics/`, `Intents/`
- `Models/`: Standardized pure Data structures and `SwiftData` logic.
- `Configuration/`: `project.yml`, `Config.xcconfig`, App Intents, and Entrypoint metadata.

## 3. Application State & Dependency Injection
- **DO NOT** use scattered `@EnvironmentObject` implementations or rely heavily on SwiftUI environment scoping for heavy singletons.
- **ALWAYS** use `AppDIContainer.shared` for injecting business logic. This protects the SwiftUI View lifecycle from massive memory redraw loops.
- Pass required core managers (e.g., `let cameraManager: CameraManager`) into `Views` as `@Observable` bindings or `@ObservedObject` properties.

## 4. Hardware and Performance Limits
- iOS Background limitations severely constrain API requests. Any heavy file I/O operations must be decoupled via `Task.detached(priority: .background)`.
- Image conversions (e.g. `downsampleImage`) or large JSON parsing must occur off the Main thread to prevent 60FPS UI stutters.
- Avoid forcing `.isHighResolutionCaptureEnabled` without throttling image loads via `ImageIO` `CGImageSourceCreateThumbnailAtIndex` bounded logic. A full 12MP–48MP uncompressed capture will cause iOS Out of Memory (OOM) crashes if repeatedly appended array buffers are allocated without bounds.

## 5. UI and Glassmorphism (Aesthetics)
- **Stunning UIs are mandatory**: The user should be wowed at first glance.
- Implement `.ultraThinMaterial` backgrounds to merge UI elements over camera viewfinders.
- Avoid large opaque black or white overlay panes. Make components dynamic, animated with `.spring()` transitions, and highly responsive. Use `RiveRuntime` (`.riv` files) for complex interactive states.
- DO NOT use XIBs or custom rigid Storyboards. Write SwiftUI exclusively.

## 6. Supabase & Deno Edge
- The `identify` Edge node abstracts all `generativelanguage` (Google) calls.
- Never write direct Gemini inference code inside iOS Swift controllers — this leaks API keys and bypasses edge limits.
- Keep the Deno Edge `index.ts` files synchronized with the Swift `IdentifyResponse` API Contract mapped in `08-API-Contracts.md`.
- Ensure all unstructured display text (e.g. `common_name`) is locked via `systemInstruction` rules to format as Title Case, preventing lowercase UI outputs before values are cached to the database.

## 7. Database Safeties
- Anonymous IDs (`DeviceIdentityManager.shared.deviceId`) exist solely to persist `UsageManager` limits locally on iOS across reinstalls. Do not use IDFV (`.deviceId`) for backend user records, analytics identifiers, or constructed S3/R2 storage keys.
- **Strict IDOR Alignment**: When querying Edge Functions (like `/identify`) or formulating Cloudflare R2 staging buckets (`staging/\(userId)/`), **always** use `SupabaseManager.shared.currentUser?.id.uuidString`. Edge functions natively apply IDOR security checks against the active auth JWT. Supplying the local vendor ID instead will trigger `403 Forbidden` pipeline blocks.
- Follow RLS (Row Level Security) schemas by avoiding direct CRUD modifications to PostgreSQL from iOS. POST via Edge REST endpoints protected by JWT verification via `supabaseAdmin.auth.getUser()`.
- **SwiftData Predicate Boolean Mapping Bug**: When creating `@Query(filter:)` definitions with `#Predicate`, NEVER rely on implicit boolean checks (e.g. `$0.isBiological`). Due to iOS 17 compilation faults, SwiftData will ignore the filter and return all rows. **ALWAYS** map operators against booleans explicitly (e.g. `$0.isBiological == true` or `$0.isBiological == false`).
- **SwiftData Predicate `UUID()` Evaluation Fault**: Due to Swift 5.9 macro constraints, passing a raw `UUID` parameter against a persistent `String` column inside a `#Predicate` causes compiler timeouts that hang builds without error logs. **MUST** extract `.uuidString` outside the closure before comparing (e.g., `let stringVal = id.uuidString`, then `#Predicate { $0.id == stringVal }`).

## 8. Documentation Maintenance
- **ALWAYS create and update documentation accordingly.** Whenever you implement a new feature, modify a system's architecture, or alter an API contract, update the corresponding markdown file in the `docs/` folder to reflect reality. Do not wait to be asked. Maintain an accurate, synchronized documentation set that matches the codebase.
