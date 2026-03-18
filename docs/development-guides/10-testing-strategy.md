# Merian Testing & Quality Assurance Strategy

Merian employs a lightweight, modern Swift-native testing structure leveraging the `Testing` framework globally, cleanly isolating offline UI queues and core engine components away from the rigid Apple lifecycle loops seamlessly. 

## In-Memory Database Containers (`SwiftData`)

We rigorously prevent test suites from polluting physical local iOS file system directories and SQLite databases natively. All local unit tests physically testing caching states and soft-deletions must explicitly invoke an isolated, volatile `ModelContext`:

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
1. Operations like `context.save()` happen exclusively in RAM and resolve instantly, bypassing native disk IO waits safely.
2. The user's genuine `Scans` and native `OfflineQueuedScan` artifacts are rigidly shielded from testing permutations permanently.

## Core Suites

The testing bounds are mapped physically within `merianTests/Core` and `merianTests/Features`:

### Analytics & Telemetry
- **`AppTelemetryTests.swift`**: Validates structural tracking arrays natively ensuring telemetry identifiers are PII-free.
- **`PostHogManagerTests.swift`**: Securely asserts logical bounds surrounding day-7 tracking funnels and user identification natively.
- **`GamificationManagerTests.swift`**: Validates native persistence bounds asserting proper math updates against user local scores ensuring UI progression trackers never skew bounds unexpectedly.
- **`UsageManagerTests.swift`**: Securely bounds Apple ecosystem checks triggering daily free quotas and limits without accessing native API constraints permanently.

### AI & Data Architectures
- **`InferenceEngineTests.swift`**: Securely asserts logical bounds surrounding decoding the `EdgeResponseWrapper` AI payloads structurally, mapping specific physical metadata like `is_poisonous`, raw numeric `ai_confidence_score` indices and deep structural `TaxonomyData` logic seamlessly across `JSONDecoder`.
- **`ViewfinderIntelligenceTests.swift`**: Validates real-time analysis bounds safely mapping frames before initiating inference triggers.
- **`ArchiveManagerTests.swift`, `SyncStateManagerTests.swift`, `ScanRepositoryTests.swift`, `BackgroundDatabaseActorTests.swift`**: Verifies dynamic bi-directional relationship bounds appending dynamically and structurally inside the isolated local RAM footprint properly without causing SwiftData loop issues safely.
- **`OfflineQueueManagerTests.swift`**: Dynamically mocks native payload insertions efficiently. 
  - **In-Memory Isolation**: It spins up an explicit `@MainActor ModelContext` strictly targeting `.isStoredInMemoryOnly = true` to isolate test data entirely from the user's real offline queue.
  - **Core Lifecycles**: Rigorously exercises `.enqueueCapture` (asserting `SwiftData` arrays increment perfectly) and native `.purgeSoftDeletedRecords()` (asserting soft-deleted items vanish while undeleted items persist securely). 
  - **Disk Teardown**: Explicitly confirms that physical sandbox files in `URL.documentsDirectory` are functionally eradicated during purges to prevent storage bloat.
- **`ImageCacheTests.swift`**: Ensures Swift RAM cache bounds do not aggressively override maximum physical system allocations cleanly natively.

### Hardware & Ecosystem Integrations
- **`CameraManagerTests.swift`, `CameraViewModelTests.swift`**: Validates cross-app UI state routing logic including deep physical Apple lifecycle events like `NSNotification.Name("AppDidEnterInactivePhase")` dropping active testing limits physically avoiding lockouts explicitly. Crucially, asserts that the new "Legacy Viewfinder" toggle (`isLiveInferencePaused`) cleanly disables VUI background thread evaluation dynamically upon setting.
- **`HardwareOrchestratorTests.swift`**: Mocks `ProcessInfo.processInfo.thermalState` boundaries securely guaranteeing the camera dynamically throttles `FPS` dynamically without restarting instances natively. Verifies explicit UserDefaults binding (`isExpeditionModeActive`) securely overriding OS thresholds to aggressively lock to 24fps and remove glass modifiers. To bypass Swift runtime crashes locally across asynchronous CI containers, strictly executes `AppTelemetry.initialize()` at `HardwareOrchestratorTests.init()` utilizing a stub `TEST_MOCK_ID` configuration cleanly.
- **`EnvironmentContextManagerTests.swift`**: Asserts safe async bounding over simulated `CLLocationManager` outputs validating offline contexts.
- **`HapticManagerTests.swift`**: Confirms safe initialization states bridging `UIImpactFeedbackGenerator` buffers without stalling threads. Now structurally asserts that hard-toggling `UserDefaults.standard.set(false, forKey: "isHapticsEnabled")` prevents sequence triggers gracefully avoiding hardware memory faults.
- **`PhotoLibraryManagerTests.swift`**: Validates that toggling `UserDefaults("saveToCameraRoll")` securely drops the payload without triggering fatal explicit Apple `PHPhotoLibrary` memory allocations seamlessly natively.

### Security, Network & Identity
- **`MerianNetworkClientTests.swift`, `SupabaseManagerTests.swift`**: Thoroughly maps API routing bounds testing explicit self-healing `.401` execution cycles for Ghost User retries and JSON body payload serialization natively.
- **`DeviceIdentityManagerTests.swift`, `RevenueCatManagerTests.swift`**: Directly isolates authentication loops binding persistent mock App Store IDs cleanly away from live Production identifiers.
- **`SocialGuardManagerTests.swift`, `CircuitBreakerManagerTests.swift`**: Asserts offline logic guaranteeing blocked users do not re-populate the feed organically.

### UI & Utilities
- **`ImageDownsamplerTests.swift`**: Directly tests pure Core Graphics memory constraint barriers mapping 4000x4000 physical payloads cleanly under safe metric limits natively to prevent Out-Of-Memory JetSam OS crashes structurally.
- **`ScansSearchManagerTests.swift`**: Verifies debounced string bounds extracting correctly locally via SwiftData `@Query` mechanisms safely.

## Mocking Physical Apple Ecosystem Limits natively (`DeviceIdentityManager`)

When testing natively across AI boundaries, it is structurally impermissible to pollute real Ghost Session tracking identities via PostHog telemetry instances. Explicit tests avoid calling `SupabaseManager.shared.initializeGhostSession()` natively, instead strictly executing business logic testing models securely decoupled from Apple ecosystem HTTP constraints completely!
