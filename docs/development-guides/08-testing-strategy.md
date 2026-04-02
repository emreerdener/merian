# Merian Testing & Quality Assurance Strategy

Merian uses a lightweight, Swift-native testing structure built on the `Testing` framework, isolating offline UI queues and core engine components from Apple lifecycle dependencies.

## In-Memory Database Containers (`SwiftData`)

Test suites must not pollute the local iOS file system or SQLite databases. All unit tests that exercise caching states and soft-deletions must use an isolated, volatile `ModelContext`:

```swift
@MainActor
private func createIsolatedContext() throws -> ModelContainer {
    let schema = Schema(CurrentSchema.models)
    let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}
```

Always use `CurrentSchema` (aliased to the latest active `MerianSchemaV{N}`). Never pin tests to historical versioned schemas — a pinned schema silently drops new model fields (e.g. `similarSpecies` added in `MerianSchemaV26`), causing persistence tests to pass against the wrong shape.

> **Disk-based isolation**: `BackgroundDatabaseActorTests` uses a temp SQLite file on `URL.cachesDirectory` instead of in-memory storage because of a known iOS 18 simulator bug where `NSCache`-backed in-memory containers mishandle `[String]` array appends. The temp file is UUID-named to guarantee zero cross-test contamination.

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
- **`MigrationPlanTests.swift`**: Two-tier structural guard for the SwiftData migration plan.
  - `migrationPlanContainerInitializesWithoutCrash`: mirrors `MerianApp.init()` (in-memory store, no migration). Catches init-time stage validation failures on iOS 26.
  - `migrationFromV30ToV31DoesNotCrash`: creates a real V30 disk store then reopens with the full migration plan targeting V31. On iOS 26+, even a lightweight migration (V30→V31) triggers validation of ALL custom stages in `MerianMigrationPlan.stages` via `NSCustomMigrationStage.init(migratingFrom:to:)`. Two bugs cause equal-model crashes: (1) extension-declared `@Model` classes whose metadata resolves to the global type; (2) `ScanCollection` typealias carrying a relationship to a prior schema's `LocalScanRecord` by Swift type identity. The disk-based test covers this execution path that the in-memory test misses. Update the version pair (V30→V31) to the current pair when a new schema is added. Run both tests on an iOS 26 simulator on every schema bump.
- **`InferenceEngineTests.swift`**: Asserts decoding of `EdgeResponseWrapper` and `EnrichScanResponse` payloads via `JSONDecoder`.
  - **`/identify` response**: Validates `EdgeResponse` fields (`scan_id`, `common_name`, `confidence_score`, `taxonomy`, `insight_data`, `species_insights.habitat_description`). Asserts that `species_insights` is nil on cache-miss responses and non-nil on cache-hit responses. Note: `aiReasoning` is populated from `insight_data.ai_reasoning` (per-scan, always present when `insight_data` exists) — it is **not** a separate `premium_insights` block.
  - **`/enrich-scan` response**: Validates flat `similar_species: [EnrichScanResponse.SimilarSpeciesEntry]` array decoding with all four fields (`scientific_name`, `common_name`, `reference_image_url`, `iucn_red_list_status`). Asserts sparse entries (only `scientific_name`) decode with `nil` optional fields. Asserts absent `similar_species` key decodes as `nil`, not empty array.
  - **`load(from:)` path**: Asserts that `LocalScanRecord.similarSpecies: [String]?` strings are wrapped into `SimilarSpeciesEntry` instances with `nil` enrichment fields (historical record path). Asserts nil `similarSpecies` on the record produces `nil` (not an empty `SimilarSpecies` struct) on `speciesData`.
  - **Inference tier**: Validates Flash vs Pro confidence band thresholds via `MerianConfig.confidenceBands(forInferenceTier:)`. Asserts nil tier resolves to Flash for safety.
  - **Moderation Flagging**: Asserts `flagAIIdentification` seamlessly mutates the offline tracking property `isFlagged` purely natively ahead of networking attempts (`testFlagAIIdentificationMutatesLocalState`), and strictly restores from `LocalScanRecord` on cold boot (`testLoadFromRecordPopulatesIsFlagged`).
- **`ViewfinderIntelligenceTests.swift`**: Validates real-time analysis logic, ensuring frames are evaluated correctly before inference is triggered.
- **`ArchiveManagerTests.swift`, `SyncStateManagerTests.swift`, `ScanRepositoryTests.swift`, `BackgroundDatabaseActorTests.swift`**: Verifies bi-directional SwiftData relationship behavior within an isolated context, without triggering SwiftData loop issues. `ScanRepositoryTests` includes `testV26SimilarSpeciesRoundTrip` — inserts a `LocalScanRecord` with `similarSpecies: [String]?` and verifies the array round-trips through SwiftData without corruption; and `testV27LookalikesDataRoundTrip` — inserts a `LocalScanRecord` with `lookalikesData: Data?` (JSON-encoded `[SimilarSpeciesEntry]`) and verifies the blob round-trips and decodes correctly (covering the `MerianSchemaV27` field added for rich lookalike persistence). `BackgroundDatabaseActorTests` uses `CurrentSchema` and a disk-isolated container to validate actor-boundary `Sendable` payload extraction across a `Task.detached` boundary.
- **`CaptureTelemetryTests.swift`**: Directly validates that offline/historic captures explicitly decouple live sensor leakage (like LiDAR distance vectors or view-finder zoom scopes) away from EXIF bounds.
- **`ScansManagerTests.swift`**: Validates local string-index mapping (group name taxonomies, semantic tags, and explicitly added `customTags`). Asserts `NotificationCenter` routing dynamically patches specific payloads (`testCustomTag_DynamicHotSwap`) instantly without OOM-burst re-renders!
- **`LocalImageLoaderTests.swift`**: Explicitly locks concurrent network payload boundaries using overarching `TaskGroup`s. Asserts `fetchNetworkFallback` deduplicates asynchronous URL fetches seamlessly to prevent multi-grid render flooding.
- **`OfflineQueueManagerTests.swift`**: Mocks queue payload insertions.
  - **In-Memory Isolation**: Spins up a `@MainActor ModelContext` with `.isStoredInMemoryOnly = true` to isolate test data from the user's real offline queue.
  - **Core Lifecycles**: Exercises `.enqueueCapture` (asserting SwiftData record counts increment correctly) and `.purgeSoftDeletedRecords()` (asserting soft-deleted items are removed while undeleted items persist).
  - **Disk Teardown**: Confirms that sandbox files in `URL.documentsDirectory` are deleted during purges to prevent storage bloat.
- **`CompositeLibraryTests.swift`** (`merianTests/Features/Scans/`): Validates the bounding behaviors of the composite `ScansGrid` that renders both `OfflineQueuedScan` and `LocalScanRecord` items in the same `LazyVGrid`.
  - **Unique ID Guarantee**: Inserts three `OfflineQueuedScan` records and asserts all three `id` values are distinct, guarding against accidental identifier collisions inside the grid's `ForEach` key space.
  - **`localImagePaths` Default**: Asserts a freshly constructed `OfflineQueuedScan` has `localImagePaths == []`, so `ScanThumbnail(imagePath: queued.localImagePaths.first, ...)` safely receives `nil` rather than an unexpected path.
  - **`isDeleted` Predicate**: Mirrors the exact `#Predicate<OfflineQueuedScan> { !$0.isDeleted }` used in `ScansSheetView`'s `@Query` and asserts soft-deleted records are excluded while active ones are returned, guaranteeing tombstoned uploads never resurface in the library.
  - **Selection Engine Decoupling**: Injects an `OfflineQueuedScan` ID directly into `ScansManager.selectedScans` (the adversarial case) and confirms `getSelectedLocalRecords()` returns nothing for it. Because `getSelectedLocalRecords()` filters from `filteredScans: [LocalScanRecord]`, the queued scan ID cannot reach the batch-share / batch-delete pipeline regardless of what is in `selectedScans`.
- **`ImageCacheTests.swift`**: Ensures the Swift RAM cache does not exceed maximum system allocation limits.

### Hardware & Ecosystem Integrations
- **`CameraManagerTests.swift`, `CameraViewModelTests.swift`**: Validates UI state routing logic. `CameraViewModelTests` sends `AppEventPublisher.shared.send(.appDidEnterInactivePhase)` (not `NotificationCenter`) to trigger the modal-reset path — `CameraViewModel` subscribes to `AppEventPublisher`, not legacy `NSNotification`. Asserts that the "Legacy Viewfinder" toggle (`isLiveInferencePaused`) disables background thread evaluation when set.
- **`HardwareOrchestratorTests.swift`**: Mocks `ProcessInfo.processInfo.thermalState` boundaries to verify the camera throttles FPS dynamically without restarting instances. Verifies the `UserDefaults` binding (`isExpeditionModeActive`) correctly overrides OS thresholds to lock to 24fps and remove glass modifiers. To avoid Swift runtime crashes in asynchronous CI containers, calls `AppTelemetry.initialize()` at `HardwareOrchestratorTests.init()` using a stub `TEST_MOCK_ID` configuration.
- **`EnvironmentContextManagerTests.swift`**: Asserts safe async handling over simulated `CLLocationManager` outputs for offline contexts.
- **`HapticManagerTests.swift`**: Confirms safe initialization of `UIImpactFeedbackGenerator` buffers without stalling threads. Asserts that setting `UserDefaults.standard.set(false, forKey: "isHapticsEnabled")` prevents sequence triggers without causing hardware memory faults.
- **`PhotoLibraryManagerTests.swift`**: Validates that toggling `UserDefaults("saveToCameraRoll")` drops the payload without triggering `PHPhotoLibrary` memory allocations.

### Security, Network & Identity
- **`MerianNetworkClientTests.swift`, `SupabaseManagerTests.swift`**: Tests API routing, including `.401` retry cycles for Ghost User flows and JSON body payload serialization.
- **`DeviceIdentityManagerTests.swift`, `RevenueCatManagerTests.swift`**: Isolates authentication loops away from live production identifiers. `DeviceIdentityManagerTests` reads `DeviceIdentityManager.shared.deviceId` (the public `@Observable` property) — it does **not** call the private `getOrGeneratePersistentIDFV()` method directly. The test wipes the relevant Keychain item via `SecItemDelete` before and after the assertion to prevent cross-run contamination.
- **`SocialGuardManagerTests.swift`, `CircuitBreakerManagerTests.swift`**: Asserts offline logic ensuring blocked users do not re-populate the feed.

### UI & Utilities
- **`ImageDownsamplerTests.swift`**: Tests Core Graphics memory constraints by processing 4000x4000 payloads under safe metric limits, preventing Out-Of-Memory JetSam crashes.
- **`ScansSearchManagerTests.swift`**: Verifies debounced string filtering via SwiftData `@Query` mechanisms.
- **`OnboardingViewModelTests.swift`**: Validates the extracted UI state machine progression, ensuring hardware fallback steps prevent `Int` scalar out-of-bounds crashes. Tests core persistence loops simulating `@AppStorage` routing flags from the `.ready` boundary, fully offline.

## Testing the Species Lookalike Pipeline

The `SimilarSpecies` / `SimilarSpeciesEntry` domain model has two distinct data paths that require separate coverage:

### 1. Rich path (live scan + `enrich-scan` response)

`EnrichScanResponse.SimilarSpeciesEntry` (Codable DTO, snake_case) is decoded from the `/enrich-scan` JSON payload and mapped to the domain `SimilarSpeciesEntry` (camelCase) by `InferenceEngine.fetchAndApplyEnrichment`. Tests:

```swift
// Verify flat array decodes with all four optional fields
@Test func testEnrichScanResponseDecodesRichLookalikes() throws {
    let json = """{ "data": { "similar_species": [
        { "scientific_name": "Procyon cancrivorus", "common_name": "Crab-eating Raccoon",
          "reference_image_url": "https://...", "iucn_red_list_status": "LC" }
    ]}}"""
    let response = try JSONDecoder().decode(EnrichScanResponse.self, from: json.data(using: .utf8)!)
    // assert entries[0] fields ...
}
```

Key assertions: absent key decodes as `nil` (not `[]`); sparse entries (only `scientific_name`) decode with `nil` optionals without crashing.

### 2. Historical path (`load(from:)`)

When opening a scan from the library, `InferenceEngine.load(from:)` reads `LocalScanRecord.similarSpecies: [String]?` (bare scientific name strings) and wraps each into a `SimilarSpeciesEntry` with `nil` enrichment fields:

```swift
// LocalScanRecord.similarSpecies = ["Procyon cancrivorus", "Bassariscus astutus"]
// → SimilarSpecies(entries: [
//     SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, ...),
//     SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, ...)
//   ])
```

`SimilarSpeciesGallery` falls back to `SimilarSpeciesImageFetcher` for image lookup when `referenceImageUrl == nil`.

### Backwards-compat accessor

`SimilarSpecies.lookalikes: [String]` (computed) maps entries to their scientific names. Any code that previously consumed `[String]` arrays from the old `SimilarSpeciesData.lookalike_species` DTO uses this accessor — it must continue returning names in the same order as `entries`.

## Mocking Apple Ecosystem Limits (`DeviceIdentityManager`)

When testing across AI boundaries, tests must not pollute real Ghost Session tracking identities via PostHog telemetry. Tests avoid calling `SupabaseManager.shared.initializeGhostSession()` and instead test business logic models decoupled from live Apple ecosystem HTTP constraints.

## API & Edge Function Testing (Deno)

Merian relies on Supabase Edge Functions. Due to the rapid iteration cycle of Gemini structures, type safety at the network boundary (Swift → TS) must be guaranteed by AST regression guards.

### `validate_edge_dtos.ts`
- **AST Protection**: Before every production Edge rollout, AI Agents and developers run this script to syntactically trace the Deno `merianResponseSchema` and diff it against the properties in `InferenceEdgeDTOs.swift`. This proactively halts deployments if a UI variable drifts out of sync.
- **`LookalikeSummary` shape check**: The script must assert that `EnrichData.similar_species` is typed as `LookalikeSummary[]` and that `LookalikeSummary` exposes all four fields: `scientific_name`, `common_name`, `reference_image_url`, `iucn_red_list_status`. This guards against the response schema accidentally reverting to the legacy `{ lookalike_species: string[] }` wrapper shape.

### `export-dwca_test.ts`
- **Global Anonymization**: Evaluates `generateDwcARow` mathematically, ensuring `export_scope: global` safely casts unauthenticated user IDs down to random SHA-256 strings (e.g., `merian_user_...`).
- **Precision Preservation**: Validates that standard queries correctly map highly precise exact string values.
- **Protected Species Truncation**: Validates that matching protected statuses (`endangered`, `vulnerable`) explicitly drops exact map coordinates down to single-digit resolution metrics (`Math.round(lat * 10) / 10`) regardless of the original `gps_lat_exact` fields, completely shielding sensitive flora and fauna!
