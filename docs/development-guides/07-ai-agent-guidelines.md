# Merian AI Code Conventions & Guidelines

When generating or modifying code for Merian, follow these constraints to ensure optimal performance, hardware safety, and architectural consistency.

## 0. The Documentation Directory
The `docs/` folder contains the master reference for the application:
- Refer to `docs/system-architecture/01-system-architecture.md` for overall architecture and pipeline logic.
- Refer to `docs/system-architecture/02-zero-oom-and-concurrency.md` for strict P0 iOS and Deno concurrency/memory safety rules.
- Refer to `docs/features-and-hardware/01-camera-and-hardware.md` for hardware integrations like LiDAR and precise telemetry snapshots.
- Refer to `docs/backend-and-data/04-database-schema.md` for PostgreSQL & SwiftData schemas.
- Refer to `docs/backend-and-data/05-api-contracts.md` for all network request/response shapes.
- Refer to `docs/backend-and-data/01-offline-sync-pipeline.md` for offline queue, sync state machine, and deletion architecture.
- Refer to `docs/development-guides/02-app-lifecycle.md` for `AppLifecycleManager` phase contracts and trigger ordering.
- Refer to `docs/system-architecture/03-image-pipeline.md` for capture → disk → cache → display image flow.

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
  - `Data/Database/`: `BackgroundDatabaseActor`, `FileIOActor`, `HistoricalDatabaseActor`, `ScanRepository`, `SearchDatabaseActor`
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
- **UI Lifecycle Triggers for Hardware**: Never bind `AVCaptureSession` or heavy hardware drivers to Swift UI sheet closures like `.onAppear` or `.onDismiss`. In iOS 16+, rapid presentation state changes or `.scenePhase` background sweeps can cause these closures to fire out of order, permanently deadlocking the backend AV queue. Always use deterministic `.onChange(of: stateVariable)` observers guarded by `scenePhase == .active`.
- **Image encoding — always WebP**: All image payloads produced by the app (inference, display, offline queue, manual crop) are encoded as lossy WebP using `CGImageDestinationCreateWithData` with `UTType.webP.identifier`. **Never** introduce `UIImage.jpegData(compressionQuality:)` or `UTType.jpeg` into the encoding path. WebP reduces byte payload sizes by ~30–50% over JPEG at equivalent quality and is fully accepted by the Gemini API (`image/webp`). Always pass `kCGImageDestinationLossyCompressionQuality: MerianConfig.imageCompressionQuality` in the options dictionary. All temp and persisted filenames use `.webp`, and all `Content-Type` headers in `URLRequest` PUT operations and Cloudflare R2 pre-signed URLs must be `image/webp`.

## 5. UI and Glassmorphism (Aesthetics)
- **Stunning UIs are mandatory**: The user should be wowed at first glance.
- Implement `.ultraThinMaterial` backgrounds to merge UI elements over camera viewfinders.
- Avoid large opaque black or white overlay panes. Make components dynamic, animated with `.spring()` transitions, and highly responsive. Use `RiveRuntime` (`.riv` files) for complex interactive states.
- DO NOT use XIBs or custom rigid Storyboards. Write SwiftUI exclusively.

## 6. Supabase & Deno Edge
- The `identify` Edge node abstracts all `generativelanguage` (Google) calls.
- Never write direct Gemini inference code inside iOS Swift controllers — this leaks API keys and bypasses edge limits.
- Keep the Deno Edge `index.ts` files synchronized with the Swift `IdentifyResponse` API Contract mapped in `docs/backend-and-data/05-api-contracts.md`.
- Ensure all unstructured display text (e.g. `common_name`) is locked via `systemInstruction` rules to format as Title Case, preventing lowercase UI outputs before values are cached to the database.
- **Every new Edge Function MUST have a `[functions.<name>]` entry with `verify_jwt = false` in `supabase/config.toml`.** Omitting this entry causes Supabase's Kong gateway to default to `verify_jwt = true`, which performs gateway-level JWT validation before the function code runs. This rejects valid ES256 anonymous sessions with `401 Invalid JWT` even though the token is structurally valid. The function's own `requireAuth` inside `withEdgeHandler` never gets a chance to run. The sole intentional exception is `merge-ghost-profile` (`verify_jwt = true`), which is invoked via the Supabase Swift SDK rather than `MerianNetworkClient`.

## 7. Database Safeties
- Anonymous IDs (`DeviceIdentityManager.shared.deviceId`) exist solely to persist `UsageManager` limits locally on iOS across reinstalls. Do not use IDFV (`.deviceId`) for backend user records, analytics identifiers, or constructed S3/R2 storage keys.
- **Strict IDOR Alignment**: When querying Edge Functions (like `/identify`) or formulating Cloudflare R2 staging buckets (`staging/\(userId)/`), **always** use `SupabaseManager.shared.currentUser?.id.uuidString`. Edge functions natively apply IDOR security checks against the active auth JWT. Supplying the local vendor ID instead will trigger `403 Forbidden` pipeline blocks.
- Follow RLS (Row Level Security) schemas by avoiding direct CRUD modifications to PostgreSQL from iOS. POST via Edge REST endpoints protected by JWT verification via `supabaseAdmin.auth.getUser()`.
- **SwiftData Predicate Boolean Mapping Bug**: When creating `@Query(filter:)` definitions with `#Predicate`, NEVER rely on implicit boolean checks (e.g. `$0.isBiological`). Due to iOS 17 compilation faults, SwiftData will ignore the filter and return all rows. **ALWAYS** map operators against booleans explicitly (e.g. `$0.isBiological == true` or `$0.isBiological == false`).
- **SwiftData Predicate `UUID()` Evaluation Fault**: Due to Swift 5.9 macro constraints, passing a raw `UUID` parameter against a persistent `String` column inside a `#Predicate` causes compiler timeouts that hang builds without error logs. **MUST** extract `.uuidString` outside the closure before comparing (e.g., `let stringVal = id.uuidString`, then `#Predicate { $0.id == stringVal }`).
- **SwiftData Optional Array Mutation Bug**: When appending to an optional SwiftData relationship array (e.g. `record.collections?.append(newCollection)`), SwiftData often fails to trigger its internal `didSet` observers. This leaves the `ModelContext` unaware of the mutation, preventing inverse relationships from updating correctly. **ALWAYS** explicitly reassign the array instead: `var updated = record.collections ?? []; updated.append(newCollection); record.collections = updated`.

## 8. Documentation Maintenance
- **ALWAYS create and update documentation accordingly.** Whenever you implement a new feature, modify a system's architecture, or alter an API contract, update the corresponding markdown file in the `docs/` folder to reflect reality. Do not wait to be asked. Maintain an accurate, synchronized documentation set that matches the codebase.

## 9. Agent Workflows
Merian maintains reproducible, automated workflows inside the `.agents/workflows/` directory. AI Agents **MUST** execute these runbooks (e.g. via slash commands or manually reading and running) for critical operations instead of guessing:
- `schema_update.md`: Bumping SwiftData schema versions and snapshotting global active models.
- `deploy_edge_functions.md`: Deploying TypeScript Supabase modifications and executing type checks.
- `revenuecat_entitlements.md`: Adding/Modifying in-app purchases and localized StoreKit files.
- `mock_camera_inference.md`: Faking `AVCapturePhoto` hardware feeds via `InferenceEngine` to test caching lines on the simulator.
