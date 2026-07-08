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
- Refer to `docs/development-guides/12-in-app-changelog.md` before adding release notes or user-facing changelog entries.
- Refer to `docs/system-architecture/03-image-pipeline.md` for capture → disk → cache → display image flow.
- Refer to `docs/features-and-hardware/17-public-web-share-pages.md` before changing `apps/web/`, `merian.earth` routes, Open Graph metadata, or Explore share URL behavior.

## 1. Project Generation (XcodeGen)
- **NEVER** directly modify `Merian.xcodeproj`.
- **ALWAYS** update `project.yml` when adding new packages, frameworks, scopes, or entitlements.
- Run `xcodegen generate` before attempting to build.
- Do not hardcode a real Apple Developer Team ID in `project.yml` or shared tracked config. Signing must flow through `Signing.xcconfig` -> optional `Signing.local.xcconfig`, with the local file ignored by git.
- **Build Versioning**: `project.yml` owns `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; `Info.plist` files must strictly inherit `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Use `make prepare-ios-release VERSION=x.y.z` before TestFlight archives, and use `agvtool` only as an optional read-only sanity check because XcodeGen overwrites generated-project-only changes. *Never downgrade `MARKETING_VERSION` or reuse a TestFlight build number.*
- API Keys must be injected via `Config.xcconfig` or `MerianEnvironment.swift`. NEVER hardcode `GEMINI_API_KEY` or `SUPABASE_ANON_KEY` inside `.swift` files.

## 2. Directory Structure
The workspace enforces this layout inside `apps/ios/Merian/`:
- `Features/`: Complete user domains (`Capture`, `Explore`, `Insights`, `Onboarding`, `Profile`, `Scans`, `SpeciesDictionary`).
- `Core/`: Foundational logic organized into subdirectories:
  - `AI/`: `InferenceEngine`, `InferenceProcessingActor`
  - `Data/Database/`: `BackgroundDatabaseActor`, `FileIOActor`, `HistoricalDatabaseActor`, `ScanRepository`
  - `Data/Images/`: `MediaPreparationActor`, `LocalImageLoader`, `ImageCache`, `ArchiveManager`, `PhotoLibraryManager`
  - `Data/OfflineSync/`: `OfflineQueueManager`, `SyncStateManager`
  - `Hardware/`: `CameraManager`, `HardwareOrchestrator`, `EnvironmentContextManager`, `AudioCaptureManager`, `SpectrogramActor`
  - `Network/`: `MerianNetworkClient`, `SupabaseManager`
  - `Security/`: `CircuitBreakerManager`, `DeviceIdentityManager`, `RevenueCatManager`, `SocialGuardManager`
  - `Utilities/`: `MerianConfig`, `AppLifecycleManager`, `BackgroundTaskWrapper`, `FieldNotesRepository`, `ImageDownsampler`
  - `Analytics/`, `Intents/`
- `Models/`: Standardized pure Data structures and `SwiftData` logic.
- `Configuration/`: target-owned Info.plist and entitlement files. Repo-level project files such as `project.yml`, `Config.xcconfig`, and signing config remain at the repository root.

The public web app lives outside the iOS source tree in `apps/web/`. It uses Next.js,
React, and Mantine for server-rendered public pages. Keep service-role secrets
server-side only and run the web checks from `docs/development-guides/08-testing-strategy.md`
when changing web routes.
- `MerianLog` lives at `Core/MerianLog.swift`.
- `SearchDatabaseActor` lives with `ScansManager` in `Features/Scans/Library/ViewModels/ScansManager.swift` because it is an implementation detail of the Scans library search index.

## 3. Application State & Dependency Injection
- **DO NOT** use scattered `@EnvironmentObject` implementations or rely heavily on SwiftUI environment scoping for heavy singletons.
- **ALWAYS** use `AppDIContainer.shared` for injecting business logic. This protects the SwiftUI View lifecycle from massive memory redraw loops. Once a view model receives an `AppDIContainer`, read settings/services through that container rather than reaching back to global singletons; previews and tests rely on isolated container instances.
- Pass required core managers (e.g., `let cameraManager: CameraManager`) into `Views` as `@Observable` bindings or `@ObservedObject` properties.
- **iOS 17 `@Observable` Macro Dependency Loss**: Uncontrolled `@escaping` view layout wrappers (e.g. `GeometryReader`) can swallow Swift `@Observable` dependency tracking silently. If a nested `@Bindable` manager changes inside a structure but doesn't trigger UI updates, extract the dependency-reliant structure into a formal `private struct SomeSubcomponent: View`. This isolates the dependency boundary so that Swift invokes a clean dynamic observation connection specifically for that component.
- **Computed `@Observable` Data Trees**: When relying on computed collections derived from `@Observable` managers (e.g., pulling a dynamic `tags` array depending on `activeQuestionIndex`), calculate the property natively **inside** the physical Component's scope that needs it, rather than computing it in the parent and injecting frozen arrays via `let` constants. This guarantees standard real-time UI synchronization between parent indices and structural filters.

## 4. Hardware and Performance Limits
- iOS Background limitations severely constrain API requests. Any heavy file I/O operations must be decoupled via `Task.detached(priority: .background)`.
- Image conversions (e.g. `downsampleImage`) or large JSON parsing must occur off the Main thread to prevent 60FPS UI stutters.
- Avoid forcing `.isHighResolutionCaptureEnabled` without throttling image loads via `ImageIO` `CGImageSourceCreateThumbnailAtIndex` bounded logic. A full 12MP–48MP uncompressed capture will cause iOS Out of Memory (OOM) crashes if repeatedly appended array buffers are allocated without bounds.
- Do not use `UIImage(contentsOfFile:)` or `UIImage(data:)` on user-selected originals, avatar picks, scan media, or share/export flows. Route file-backed still-image staging and avatar previews through `MediaPreparationActor`; use `ImageDownsampler.downsampledUIImage(...)` only for already-bounded crop/display bytes. The full raster must never enter RAM.
- **UI Lifecycle Triggers for Hardware**: Never bind `AVCaptureSession` or heavy hardware drivers to Swift UI sheet closures like `.onAppear` or `.onDismiss`. In iOS 16+, rapid presentation state changes or `.scenePhase` background sweeps can cause these closures to fire out of order, permanently deadlocking the backend AV queue. Always use deterministic `.onChange(of: stateVariable)` observers guarded by `scenePhase == .active`.
- **AVFoundation queue ownership**: Never read `AVCaptureSession.inputs` or configure an `AVCaptureDevice` synchronously on `@MainActor`. Resolve inputs and run `lockForConfiguration()` inside the camera queue, then publish observable state back through `Task { @MainActor in ... }`.
- **Image encoding — WebP first, JPEG fallback only through ImageIO**: Image payloads produced by the app (inference, display, offline queue, manual crop) attempt lossy WebP via `CGImageDestinationCreateWithData` with `UTType.webP.identifier`, using `MerianConfig.imageCompressionQuality`. If ImageIO cannot create a WebP destination in the current runtime, the shared encoder may fall back to `UTType.jpeg` with the same quality setting and the client must label the MIME type from the payload magic bytes. Never introduce `UIImage.jpegData(compressionQuality:)` or ad hoc JPEG branches outside the shared ImageIO encoder.

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
- **Every new Edge Function MUST have a `[functions.<name>]` entry in `services/supabase/config.toml`.** App-facing anonymous-compatible functions should use `verify_jwt = false`; omitting the entry causes Supabase's Kong gateway to default to `verify_jwt = true`, which performs gateway-level JWT validation before the function code runs. This rejects valid ES256 anonymous sessions with `401 Invalid JWT` even though the token is structurally valid. Authenticated endpoints then verify identity inside the function with `withEdgeHandler` / `requireAuth`. Intentional gateway-auth deviations must be documented: `merge-ghost-profile` and `request-export-dwca` use `verify_jwt = true`; `species-dictionary` and `species-observation-stats` use `verify_jwt = false` but intentionally skip `requireAuth` because they return only public species-level data. Internal service-role workers and status endpoints such as species refresh, reference-image refresh, taxonomy import/status/refresh, consensus processing, non-biological purge, scan-media reconciliation, and scan-media health use `verify_jwt = false` so trusted server callers can reach Deno, then require `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` with `timingSafeCompare` or the shared service-role auth helper.
- **Edge runtime imports must be deploy-stable.** New function entrypoints should
  use `Deno.serve(...)` directly, runtime dependencies must be routed through
  `services/supabase/functions/deno.json`, and deployed code should not add
  direct `https://deno.land/std/...` or `https://esm.sh/...` imports. Use local
  helpers such as `_shared/encoding.ts` for base64/hex work and run
  `deno check --config services/supabase/functions/deno.json ...` when touching
  Edge runtime files.

## 7. Database Safeties
- Anonymous IDs (`DeviceIdentityManager.shared.deviceId`) exist solely to persist `UsageManager` limits locally on iOS across reinstalls. Do not use IDFV (`.deviceId`) for backend user records, analytics identifiers, or constructed S3/R2 storage keys.
- **Strict IDOR Alignment**: When querying Edge Functions (like `/identify`) or formulating Cloudflare R2 staging buckets (`staging/\(userId)/`), **always** use `SupabaseManager.shared.currentUser?.id.uuidString`. Edge functions natively apply IDOR security checks against the active auth JWT. Supplying the local vendor ID instead will trigger `403 Forbidden` pipeline blocks.
- Follow RLS (Row Level Security) schemas by avoiding direct CRUD modifications to PostgreSQL from iOS. POST via Edge REST endpoints protected by JWT verification via `supabaseAdmin.auth.getUser()`.
- **SwiftData Predicate Boolean Mapping Bug**: When creating `@Query(filter:)` definitions with `#Predicate`, NEVER rely on implicit boolean checks (e.g. `$0.isBiological`). Due to iOS 17 compilation faults, SwiftData will ignore the filter and return all rows. **ALWAYS** map operators against booleans explicitly (e.g. `$0.isBiological == true` or `$0.isBiological == false`).
- **SwiftData Predicate `UUID()` Evaluation Fault**: Due to Swift 5.9 macro constraints, passing a raw `UUID` parameter against a persistent `String` column inside a `#Predicate` causes compiler timeouts that hang builds without error logs. **MUST** extract `.uuidString` outside the closure before comparing (e.g., `let stringVal = id.uuidString`, then `#Predicate { $0.id == stringVal }`).
- **SwiftData Optional Array Mutation Bug**: When mutating an optional SwiftData relationship array (e.g. `record.collections?.append(newCollection)` or `record.collections?.removeAll(where: ...)`), SwiftData often fails to trigger its internal `didSet` observers. This leaves the `ModelContext` unaware of the mutation, preventing inverse relationships from updating correctly. **ALWAYS** explicitly reassign the array instead: `var updated = record.collections ?? []; updated.append(newCollection); record.collections = updated` or `var updated = record.collections ?? []; updated.removeAll(where: ...); record.collections = updated`.
- **SwiftData Relationship Mirror Read Faults**: When a scalar mirror and relationship mirror carry equivalent data, hot SwiftUI read paths must prefer the scalar mirror. For mixed media, `serializedCapturedMediaItems` decodes `capturedMediaJSON` before lazily faulting `capturedMediaEntries`; reversing this can crash on `_InvalidFutureBackingData` while layout faults `CapturedMediaEntry.kindRaw`.
- **Snapshot SwiftData models before async work.** Never capture a live `@Model` in a `Task`, `Task.detached`, modal callback, share/export path, or delete confirmation that can outlive the view. Copy IDs and scalar fields first, then re-fetch by ID when mutation is required.
- **Scan Finalization Lock**: Any new path that creates or replaces a completed `LocalScanRecord` for an inference result must acquire `ScanFinalizationCoordinator` for the stable scan ID before checking/inserting/replacing. This includes visual live saves, non-visual live saves, and background URLSession completion. Bypassing the lock can make two SwiftData contexts race on `LocalScanRecord.id`; Core Data may then invoke unique-constraint merge logic and abort while merging no-inverse `capturedMediaEntries`.

## 8. Test Infrastructure Rules

- **Always use `CurrentSchema` in tests.** Never pin test containers to a historical `MerianSchemaV{N}`. A pinned schema silently drops all fields added in later versions (e.g., `MerianSchemaV26` adds `similarSpecies`), so tests pass against the wrong model shape and produce false confidence:
  ```swift
  // CORRECT
  let schema = Schema(CurrentSchema.models)
  // WRONG — silently drops similarSpecies, zoomFactor, etc.
  let schema = Schema(MerianSchemaV9.models)
  ```
- **Use `AppEventPublisher`, not `NotificationCenter`, for internal events.** `CaptureWorkspaceViewModel` and other components subscribe to `AppEventPublisher.shared.publisher` (a Combine `PassthroughSubject<AppEvent, Never>`). Tests that trigger foreground timeout behavior must use `AppEventPublisher.shared.send(.appDidResumeAfterTimeout)` — posting to `NotificationCenter` with a fabricated name has no effect. Sheet cleanup is timeout-driven from the foreground path, while `.inactive` only pauses hardware so system overlays such as the iOS limited photo library access prompt do not close the insight sheet.
- **Do not call private methods via `@testable import`.** Swift allows calling internal-level methods from test targets, but `private` members are inaccessible. Always test behavior through public/internal interfaces (e.g., `DeviceIdentityManager.shared.deviceId` instead of the private `getOrGeneratePersistentIDFV()`).
- **Do not assert `validHistoricImagePaths` synchronously in unit tests.** `InferenceEngine.load(from:)` populates this property inside a `Task { ... }` that calls `FileIOActor.shared.validPaths(from:)`, which filters out non-existent disk paths. Paths that don't exist in the simulator sandbox return empty — assert `speciesData` properties instead.
- **No `await` needed for `ImageDownsampler` in tests.** `ImageDownsampler` is a `public enum` with static methods. Call `ImageDownsampler.downsample(data:maxSize:)` directly — no actor isolation, no `await`.

## 9. Documentation Maintenance
- **ALWAYS create and update documentation accordingly.** Whenever you implement a new feature, modify a system's architecture, or alter an API contract, update the corresponding markdown file in the `docs/` folder to reflect reality. Do not wait to be asked. Maintain an accurate, synchronized documentation set that matches the codebase.
- Architecture and stability changes must update the specific domain guide, not just this checklist. For zero-OOM/concurrency work, synchronize `docs/system-architecture/02-zero-oom-and-concurrency.md`, `docs/system-architecture/03-image-pipeline.md`, and the relevant feature/backend guide in the same change set.
- **User-facing changes must consider release notes.** For features, fixes, UX changes, or deployment notes that users or testers should see, update root `CHANGELOG.md` and, when appropriate, `apps/ios/Merian/Resources/Changelog/changelog.json`. Follow `docs/development-guides/12-in-app-changelog.md`.
- **In-app changelog entries are curated.** Do not dump commit history into the app. Add concise user-facing entries only for releases or in-progress feature notes the team chooses to expose.

## 10. Agent Workflows
Merian maintains reproducible, automated workflows inside the `.agents/workflows/` directory. AI Agents **MUST** execute these runbooks (e.g. via slash commands or manually reading and running) for critical operations instead of guessing:
- `schema_update.md`: Bumping SwiftData schema versions and snapshotting global active models.

No `freeze_schema.py` helper is currently checked in. When bumping schemas,
follow `.agents/workflows/schema_update.md` manually and freeze the outgoing
schema before changing any global model in `ActiveSchema/`.

## 11. SwiftData Schema Migration Safety

**CRITICAL — read `.agents/workflows/schema_update.md` before touching any schema.**

Two invariants govern every schema file:

| Schema state | `models` array must reference | Reason |
|---|---|---|
| Retired (V1 … V(N-1)) | Frozen snapshot types: `MerianSchemaV{K}.LocalScanRecord.self` | Stable checksum forever — never drifts with global model changes |
| Current (V(N)) | Global types: `LocalScanRecord.self` | App code (`@Query`, `context.insert`, etc.) must operate on the same entity as the container |

**The single rule that prevents `NSStagedMigrationManager` crashes:**
> Freeze the outgoing schema (V(N)) manually **BEFORE** modifying any global model in `ActiveSchema/`. Never add fields to a global model first.

**Compile-time enforcement**: Retired schemas MUST use fully-qualified type names in their `models` array (e.g., `MerianSchemaV26.LocalScanRecord.self`). A missing snapshot causes a build error rather than a runtime crash at a user's device.

**iOS 26 additional constraint — custom stages must have distinct model references**: On iOS 26+, when ANY migration runs (even a lightweight one), SwiftData iterates ALL custom stages in the migration plan and calls `NSCustomMigrationStage.init(migratingFrom:to:)` for each. If any stage's `fromVersion` and `toVersion` resolve to the same `NSManagedObjectModelReference`, the app crashes:
```
'NSInvalidArgumentException', reason: 'The current model reference and the next model reference cannot be equal.'
```
This means a user upgrading from V26 (lightweight migration V26→V27) will still crash if V24→V25 or any other custom stage has equal model references.

**Two root causes of equal model references (both have been fixed as of V24–V26):**

1. **Extension-pattern name resolution**: When `@Model` inner classes are declared via `extension MerianSchemaV{K}` (not directly in the enum body), the Swift compiler may silently resolve `LocalScanRecord.self` in the generated `@Model` metadata to the global `ActiveSchema` type, causing all extension-declared frozen snapshots to produce the same entity shape. Fix: declare all frozen `@Model` classes in the enum body (not extensions).

2. **ScanCollection typealias carries relationship by type identity**: If schema V(N) uses `typealias ScanCollection = MerianSchemaV{N-1}.ScanCollection`, the aliased class has a `@Relationship(inverse: \LocalScanRecord.collections)` that was compiled pointing to `MerianSchemaV{N-1}.LocalScanRecord` by Swift type identity. When SwiftData builds the V(N) schema, it may resolve the relationship's destination by Swift class type rather than entity name — auto-including `V{N-1}.LocalScanRecord` and making V(N) schema identical to V(N-1). Fix: always redeclare `ScanCollection` in the enum body for each schema version that changes `LocalScanRecord`, so the relationship key path `\LocalScanRecord.collections` captures the current schema's `LocalScanRecord`.

**Preferred frozen snapshot pattern — always declare in enum body:**
```swift
// SchemaV{N}.swift — CORRECT (retired schema)
enum MerianSchemaV26: VersionedSchema {
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV26.LocalScanRecord.self, MerianSchemaV26.ScanCollection.self, ...]
    }
    typealias PendingCloudDeletionTask = MerianSchemaV25.PendingCloudDeletionTask
    typealias OfflineQueuedScan        = MerianSchemaV25.OfflineQueuedScan

    // ScanCollection redeclared (not typealias) so relationship captures V26.LocalScanRecord
    @Model final class ScanCollection {
        @Relationship(inverse: \LocalScanRecord.collections) var scans: [LocalScanRecord]? = []
        // ...
    }
    @Model final class LocalScanRecord { /* frozen snapshot */ }
}
```

Only use `typealias` for models that are **unchanged AND not referenced by any relationship inside the schema** (e.g., `OfflineQueuedScan`, `PendingCloudDeletionTask`). Any model with a relationship to `LocalScanRecord` must be redeclared in each schema's enum body.

**Migration regression tests**:
`apps/ios/MerianTests/Models/MigrationPlanTests.swift` must pass on an iOS 26
simulator on every schema bump. It covers fresh-store initialization, historical
disk-store migrations, V44/V45/V46/V47 source-isolated recent plans, V47→V48,
V46→V48, and V45→V48 offline queue media fixtures, and source scans for migration safety invariants:
no silent custom-stage saves, no active/global fetch descriptors or active model
convenience helpers in `MerianMigrationPlan`, and no bare active
`CapturedMediaEntry` relationship targets in retired schemas. The full
historical plan must skip the duplicate-prone V44/V45/V46 recent cluster by
jumping V43→V47; the source-isolated V44/V45/V46 recent plans handle already
stamped recent stores. Because V46 is a no-op checksum twin of V45, the V45 and
V46 recent plans must keep those sources isolated from each other and jump
directly to V48 rather than routing through V47. V47 still reuses the V45
representative for unchanged local-scan, captured-media, and collection models on
the V43/V44→V47 paths.

**Custom migration save rule**: Never use `try? context.save()` inside `MerianMigrationPlan` custom stages. Every custom `didMigrate` save must call the shared migration save helper, rollback on failure, and rethrow so SwiftData aborts the migration rather than opening a store with missing backfilled fields. Scratchpad namespaces are cleared only after the save succeeds, and migration fetch failures must propagate instead of being logged and ignored. Migration-stage fetches must use the concrete source/target schema type for that stage, never `CurrentSchema`, active global model classes, or active-only convenience helpers, because SwiftData can trap while casting historical migration objects. Any relationship model introduced in a retired schema must be frozen in that schema too, even if the active model has the same fields. When a source schema uses the same entity name with a distinct Swift type, follow the V47 queued-scan pattern: snapshot the source IDs and timestamps in `willMigrate`, then create target-side scheduler rows from those snapshots instead of fetching the just-migrated rows as the target type. Custom migrations that create relationship rows must insert those rows into the migration `ModelContext` before assigning the relationship; relying on relationship assignment alone can crash during SwiftData store migration.

**Startup recovery rule**: `ModelContainer` creation may raise Objective-C
`NSException`s before Swift can throw. Merian routes those exceptions through
`MerianObjCExceptionBridge`, but startup first asks
`ModelStoreRecoveryCoordinator` for a store-aware migration hint so fresh/current
stores open without a migration plan and known recent stores use a
source-isolated V47/V46/V45/V44 plan; the V45 and V46 plans use one matching
source representative each with a direct V48 target internally. Quarantine remains corruption-gated: only
verified SQLite/Core Data corruption signatures may move `default.store`
artifacts, each quarantine writes a sanitized `recovery-manifest.json`, and
recovery must not clear Keychain, Supabase auth state, or device identity.
`ModelStoreRecoveryCoordinatorTests` source-scan this isolation rule and cover
the metadata parser.
