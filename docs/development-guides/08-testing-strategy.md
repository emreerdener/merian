# Merian Testing & Quality Assurance Strategy

Merian uses a lightweight, Swift-native testing structure built on the `Testing` framework, isolating offline UI queues and core engine components from Apple lifecycle dependencies.

## In-Memory Database Containers (`SwiftData`)

Test suites must not pollute the local iOS file system or SQLite databases. All unit tests that exercise caching states and soft-deletions must use an isolated, volatile `ModelContext`:

```swift
@MainActor
private func createInMemoryContext() throws -> ModelContext {
    let schema = Schema(MerianSchemaV6.models)
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
    return ModelContext(container)
}
```

This guarantees that:
1. Operations like `context.save()` happen in RAM and resolve immediately, bypassing disk I/O.
2. The user's real `Scans` and `OfflineQueuedScan` records are shielded from test mutations.

## Mocking the App DI Environment (`AppDIContainer`)

When previewing complex SwiftUI trees using `#Preview`, running against `AppDIContainer.shared` will accidentally trigger live production databases, camera hardware allocators, and background network sync loops.

**ALWAYS** use the `#if DEBUG` mock singleton injection when writing canvas boundaries:
```swift
#Preview {
    InsightSheetView()
        .environment(AppDIContainer.preview)
}
```

## Core Suites

Tests are organized under `merianTests/Core` and `merianTests/Features`:

### Analytics & Telemetry
- **`AppTelemetryTests.swift`**: Calls `AppTelemetry.initialize()` in `setUp()` so the `isInitialized` guard passes and `TelemetryDeck.signal()` is actually exercised. `testAllTrackMethodsDoNotCrash` covers every public signal including `trackOfflineQueued` and `trackOnboardingCompleted`. `testIsInitializedAfterSetUp` asserts `isInitialized == true` to catch any future regression where `setUp()` drops the initialization call.
- **`PostHogManagerTests.swift`**: Smoke-tests `identifyUser` and `reset` against the shared singleton to verify the SDK binding does not crash.
- **`GamificationManagerTests.swift`**: Validates persistence, asserting correct math updates against user local scores so UI progression trackers do not skew unexpectedly.
- **`UsageManagerTests.swift`**: Validates daily free quota checks and limits without accessing live API constraints.

### AI & Data Architectures
- **`InferenceEngineTests.swift`**: Asserts decoding of `EdgeResponseWrapper` AI payloads, including metadata fields like `is_poisonous`, `ai_confidence_score`, and `TaxonomyData` via `JSONDecoder`. Asserts inference tier configuration validation (`.pro` vs `.flash`), verifying confidence boundaries dynamically gate correctly.
- **`ViewfinderIntelligenceTests.swift`**: Validates real-time analysis logic, ensuring frames are evaluated correctly before inference is triggered.
- **`ArchiveManagerTests.swift`, `SyncStateManagerTests.swift`, `ScanRepositoryTests.swift`, `BackgroundDatabaseActorTests.swift`**: Verifies bi-directional SwiftData relationship behavior within an isolated in-memory context, without triggering SwiftData loop issues.
- **`CaptureTelemetryTests.swift`**: Directly validates that offline/historic captures explicitly decouple live sensor leakage (like LiDAR distance vectors or view-finder zoom scopes) away from EXIF bounds.
- **`ScansManagerTests.swift`**: Validates local string-index mapping (group name taxonomies, semantic tags, and explicitly added `customTags`). Asserts `NotificationCenter` routing dynamically patches specific payloads (`testCustomTag_DynamicHotSwap`) instantly without OOM-burst re-renders!
- **`LocalImageLoaderTests.swift`**: Explicitly locks concurrent network payload boundaries using overarching `TaskGroup`s. Asserts `fetchNetworkFallback` deduplicates asynchronous URL fetches seamlessly to prevent multi-grid render flooding.
- **`OfflineQueueManagerTests.swift`**: Mocks queue payload insertions.
  - **In-Memory Isolation**: Spins up a `@MainActor ModelContext` with `.isStoredInMemoryOnly = true` to isolate test data from the user's real offline queue.
  - **Core Lifecycles**: Exercises `.enqueueCapture` (asserting SwiftData record counts increment correctly) and `.purgeSoftDeletedRecords()` (asserting soft-deleted items are removed while undeleted items persist).
  - **Disk Teardown**: Confirms that sandbox files in `URL.documentsDirectory` are deleted during purges to prevent storage bloat.
- **`ImageCacheTests.swift`**: Ensures the Swift RAM cache does not exceed maximum system allocation limits.

### Hardware & Ecosystem Integrations
- **`CameraManagerTests.swift`, `CameraViewModelTests.swift`**: Validates UI state routing logic including Apple lifecycle events like `NSNotification.Name("AppDidEnterInactivePhase")`. Asserts that the "Legacy Viewfinder" toggle (`isLiveInferencePaused`) disables background thread evaluation when set.
- **`HardwareOrchestratorTests.swift`**: Mocks `ProcessInfo.processInfo.thermalState` boundaries to verify the camera throttles FPS dynamically without restarting instances. Verifies the `UserDefaults` binding (`isExpeditionModeActive`) correctly overrides OS thresholds to lock to 24fps and remove glass modifiers. To avoid Swift runtime crashes in asynchronous CI containers, calls `AppTelemetry.initialize()` at `HardwareOrchestratorTests.init()` using a stub `TEST_MOCK_ID` configuration.
- **`EnvironmentContextManagerTests.swift`**: Asserts safe async handling over simulated `CLLocationManager` outputs for offline contexts.
- **`HapticManagerTests.swift`**: Confirms safe initialization of `UIImpactFeedbackGenerator` buffers without stalling threads. Asserts that setting `UserDefaults.standard.set(false, forKey: "isHapticsEnabled")` prevents sequence triggers without causing hardware memory faults.
- **`PhotoLibraryManagerTests.swift`**: Validates that toggling `UserDefaults("saveToCameraRoll")` drops the payload without triggering `PHPhotoLibrary` memory allocations.

### Security, Network & Identity
- **`MerianNetworkClientTests.swift`, `SupabaseManagerTests.swift`**: Tests API routing, including `.401` retry cycles for Ghost User flows and JSON body payload serialization.
- **`DeviceIdentityManagerTests.swift`, `RevenueCatManagerTests.swift`**: Isolates authentication loops using persistent mock App Store IDs, away from live production identifiers.
- **`SocialGuardManagerTests.swift`, `CircuitBreakerManagerTests.swift`**: Asserts offline logic ensuring blocked users do not re-populate the feed.

### UI & Utilities
- **`ImageDownsamplerTests.swift`**: Tests Core Graphics memory constraints by processing 4000x4000 payloads under safe metric limits, preventing Out-Of-Memory JetSam crashes.
- **`ScansSearchManagerTests.swift`**: Verifies debounced string filtering via SwiftData `@Query` mechanisms.
- **`OnboardingViewModelTests.swift`**: Validates the extracted UI state machine progression, ensuring hardware fallback steps prevent `Int` scalar out-of-bounds crashes. Tests core persistence loops simulating `@AppStorage` routing flags from the `.ready` boundary, fully offline.

## Mocking Apple Ecosystem Limits (`DeviceIdentityManager`)

When testing across AI boundaries, tests must not pollute real Ghost Session tracking identities via PostHog telemetry. Tests avoid calling `SupabaseManager.shared.initializeGhostSession()` and instead test business logic models decoupled from live Apple ecosystem HTTP constraints.

## API & Edge Function Testing (Deno)

Merian relies on Supabase Edge Functions. Due to the rapid iteration cycle of Gemini structures, type safety at the network boundary (Swift → TS) must be guaranteed by AST regression guards.

### `validate_edge_dtos.ts`
- **AST Protection**: Before every production Edge rollout, AI Agents and developers run this script to syntactically trace the Deno `merianResponseSchema` and diff it against the properties in `InferenceEdgeDTOs.swift`. This proactively halts deployments if a UI variable drifts out of sync.

### `export-dwca_test.ts`
- **Global Anonymization**: Evaluates `generateDwcARow` mathematically, ensuring `export_scope: global` safely casts unauthenticated user IDs down to random SHA-256 strings (e.g., `merian_user_...`).
- **Precision Preservation**: Validates that standard queries correctly map highly precise exact string values.
- **Protected Species Truncation**: Validates that matching protected statuses (`endangered`, `vulnerable`) explicitly drops exact map coordinates down to single-digit resolution metrics (`Math.round(lat * 10) / 10`) regardless of the original `gps_lat_exact` fields, completely shielding sensitive flora and fauna!
