# Merian Testing & Quality Assurance Strategy

Merian uses a lightweight, Swift-native testing structure built on the `Testing`
framework, isolating offline UI queues and core engine components from Apple
lifecycle dependencies.

The public web app in `apps/web/` has its own checks:

```bash
cd apps/web
npm run typecheck
npm run build
npm audit --audit-level=moderate
```

Run these when changing Next.js routes, Mantine UI, public metadata, Supabase
web access, or `merian.earth` share behavior. Open Graph routes should remain
server-rendered so link unfurlers can read metadata without client hydration.

## In-Memory Database Containers (`SwiftData`)

Test suites must not pollute the local iOS file system or SQLite databases. All
unit tests that exercise caching states and soft-deletions must use an isolated,
volatile `ModelContext`:

```swift
@MainActor
private func createIsolatedContext() throws -> ModelContainer {
    let schema = Schema(CurrentSchema.models)
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}
```

Always use `CurrentSchema` (aliased to the latest active `MerianSchemaV{N}`).
Never pin tests to historical versioned schemas — a pinned schema silently drops
new model fields (e.g. `similarSpecies` added in `MerianSchemaV26`), causing
persistence tests to pass against the wrong shape.

> **Primitive Mapping Constraints:** Tests must explicitly apply
> `isStoredInMemoryOnly: true` as the primary isolated context configuration. Do
> **not** bind testing contexts dynamically to disk via `.sqlite` caches. Under
> iOS 17/18 Simulator configurations during concurrent execution paths,
> assigning implicit types like `[String]` primitive arrays to dynamically
> loaded disk caches triggers an unrecoverable `_KKMDBackingData`
> materialization crash. True RAM mappings fundamentally bypass cache
> serialization and safely bridge properties without needing external
> attributes.

This guarantees that:

1. Operations like `context.save()` happen strictly in RAM securely decoupling
   from native schemas mappings.
2. The user's real `Scans` and `OfflineQueuedScan` records are completely
   shielded from parallel mutations.

Fixture setup must fail loudly. Do not use `try? context.save()` or
`try? modelContext.save()` when seeding SwiftData tests; make helpers `throws`
or call `XCTFail` in non-throwing cleanup so persistence failures do not hide
broken test state.

Keep test code warning-clean. Use immutable bindings for class fixtures when the
reference itself is not reassigned, discard intentionally unused intent results
with `_ =`, and avoid redundant `#require` wrappers around non-optional fixture
values so build logs remain useful.

## Mocking the App DI Environment (`AppDIContainer`)

When previewing complex SwiftUI trees using `#Preview`, running against
`AppDIContainer.shared` will accidentally trigger live production databases,
camera hardware allocators, and background network sync loops.

**ALWAYS** use the `#if DEBUG` mock singleton injection when writing canvas
boundaries:

```swift
#Preview {
    InsightSheetView()
        .environment(AppDIContainer.preview)
}
```

## Core Suites

Tests are organized under `apps/ios/MerianTests/Core` and
`apps/ios/MerianTests/Features`:

- `Core/<CoreArea>/` mirrors cross-feature services, managers, actors,
  infrastructure, and shared app policies from `apps/ios/Merian/Core`.
- `Features/<Feature>/<ProductArea>/` mirrors user-facing product areas from
  `apps/ios/Merian/Features`.
- If a test covers a Core manager that happens to surface in a feature screen,
  keep the test under `Core`.
- If a test covers local product-area behavior, view models, display policy, or
  feature-only helpers, keep the test under the matching feature folder.

Example:

```text
MerianTests/
  Core/Data/OfflineSync/
  Features/Capture/Describe/
  Features/Scans/Library/
  Features/Scans/Collections/
  Features/Profile/UserProfile/
  Features/Profile/Settings/Changelog/
```

### Analytics & Telemetry

- **`AppTelemetryTests.swift`**: Calls `AppTelemetry.initialize()` in `setUp()`
  so the `isInitialized` guard passes and `TelemetryDeck.signal()` is actually
  exercised. `testAllTrackMethodsDoNotCrash` covers every public signal
  including `trackOfflineQueued` and `trackOnboardingCompleted`.
  `testIsInitializedAfterSetUp` asserts `isInitialized == true` to catch any
  future regression where `setUp()` drops the initialization call.
- **`PostHogManagerTests.swift`**: Smoke-tests `identifyUser` and `reset`
  against the shared singleton to verify the SDK binding does not crash.
- **`GamificationManagerTests.swift`**: Validates persistence, asserting correct
  math updates against user local scores so UI progression trackers do not skew
  unexpectedly.
- **`UsageManagerTests.swift`**: Validates daily free quota checks and limits
  without accessing live API constraints.

### AI & Data Architectures

- **`MigrationPlanTests.swift`**: Two-tier structural guard for the SwiftData
  migration plan.
  - `migrationPlanContainerInitializesWithoutCrash`: mirrors `MerianApp.init()`
    (in-memory store, no migration). Catches init-time stage validation failures
    on iOS 26.
  - `migrationFromV30ToV33DoesNotCrash`: creates a real V30 disk store then
    reopens with the full migration plan targeting V33 (the current schema). On
    iOS 26+, even a lightweight migration triggers validation of ALL custom
    stages in `MerianMigrationPlan.stages` via
    `NSCustomMigrationStage.init(migratingFrom:to:)`. Two bugs cause equal-model
    crashes: (1) extension-declared `@Model` classes whose metadata resolves to
    the global type; (2) `ScanCollection` typealias carrying a relationship to a
    prior schema's `LocalScanRecord` by Swift type identity. The disk-based test
    covers this execution path that the in-memory test misses. The test
    validates the V31 (`isFlagged`) lightweight addition, the V32 (`isUploaded`)
    lightweight addition, and the V33 custom `migrateV32toV33` stage
    (backfilling `scanStateRaw` from the old booleans) in a single migration
    pass. Update the "from" version and description when a new schema is added.
    Run both tests on an iOS 26 simulator on every schema bump.
  - Media-schema coverage now includes reusable disk-store fixture helpers,
    `testFullMigrationV39ToV40BackfillsMediaJSON()`,
    `testFullMigrationV40ToV41BackfillsCapturedMediaEntries()`, typed
    `StoredMediaReference` round-trips, and
    `testCapturedMediaSnapshotBuildsSharedDerivedViews()`. V47→V48 coverage also
    keeps disk-based queued-scan fixtures for image, video, audio,
    description-only, and mixed-media submissions, with display video media,
    inference-only frame paths, durable retry defaults, and a
    `scan-ingestion:{id}` scheduler row so startup-safe-mode regressions are
    caught before release. This is the preferred place for schema-version
    migration fixtures and SwiftData checksum regressions.
- **`ModelStoreRecoveryCoordinatorTests.swift`**: Launch-recovery guard for
  damaged local stores. It verifies corruption-only quarantine, no quarantine
  for generic startup failures, duplicate-checksum detection, store-metadata
  version parsing, store-aware migration selection, sanitized
  `recovery-manifest.json` output, and a source-scan boundary that prevents
  store recovery from referencing `KeychainManager`, `SupabaseManager`, sign-out
  flows, or current-user state. The focused CI lane is
  `.github/workflows/ios-startup-safety.yml`; it runs both
  `ModelStoreRecoveryCoordinatorTests` and `MigrationPlanTests` so startup safe
  mode and schema-upgrade failures are caught together. The cheap
  `.github/workflows/ios-project-guardrails.yml` lane runs
  `make validate-ios-project` and `make validate-ios-migration-guardrails`
  first, so known-bad source shapes fail on Ubuntu before the slower macOS
  simulator job spends time resolving packages, building, or booting a
  simulator. Startup Safety is path-filtered to startup/schema/recovery
  surfaces, manual dispatch, and the daily drift check; broad iOS UI changes do
  not automatically enter the simulator lane. Workflow/tooling-only changes can
  start the Startup Safety workflow to validate cheap guardrails, but the
  simulator steps are skipped unless startup runtime files changed.
  - Source-level migration guardrails fail if `SchemaVersions.swift`
    reintroduces `try? context.save()` / `try? modelContext.save()` in custom
    stages, active/global `FetchDescriptor` types inside `MerianMigrationPlan`,
    active model convenience helpers such as `replaceCapturedMedia(...)`, or
    bare active `CapturedMediaEntry` relationship targets inside retired
    schemas. V40→V41 media-entry backfill coverage also requires new
    relationship rows to be inserted through the migration `ModelContext` before
    assignment. They also keep the duplicate-prone V44/V45/V46 recent cluster
    collapsed out of the full historical runtime migration path so SwiftData
    cannot reject startup with duplicate version checksums. Disk-backed
    migration tests should open `ModelContainer`
    through the Objective-C exception bridge so SwiftData `NSException`s are
    reported as test failures with their original reason instead of aborting the
    whole test runner. V47 must reuse the V45 checksum representative for
    unchanged local-scan, captured-media, and collection models, while V45 and
    V46 recent plans must keep those sources isolated from each other and route
    directly to V48. Disk-backed SwiftData migration tests should use unique
    temporary store URLs and must not unlink the `.sqlite`, `.sqlite-shm`, or
    `.sqlite-wal` files during the test process. Core Data may keep those file
    descriptors alive after the visible `ModelContainer` scope ends; deleting
    them in-process can surface as sqlite `vnode unlinked while in use` traps in
    later tests.
    The workflow's
    Swift package cache key depends on the checked-in
    `merian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
    lockfile and runs with automatic package resolution disabled so startup
    failures are not hidden behind cold dependency resolution or silent package
    upgrades. The workflow also uploads the raw `xcodebuild` log and appends
    build diagnostics to the job summary when Xcode fails before the selected
    startup tests run, because `xcresulttool get test-results summary` reports
    those build-only failures as `unknown` with zero tests.
    The startup-safety workflow also runs on a daily schedule as a drift check,
    but it is separate from the Supabase production deploy gate.
- **`SerializedMediaItemTests.swift`**: Locks the active-schema mixed-media read
  precedence. `localScanRecordPrefersCapturedMediaJSONOverRelationshipMirror`
  and `offlineQueuedScanPrefersCapturedMediaJSONOverRelationshipMirror` seed
  divergent JSON and relationship mirrors and assert
  `serializedCapturedMediaItems` / `capturedMediaSnapshot` return the JSON
  timeline. This guards the May 12, 2026 TestFlight crash class where SwiftUI
  layout faulted `CapturedMediaEntry.kindRaw` through an invalid SwiftData
  future backing object.
- **`InferenceEngineTests.swift`**: Asserts decoding of `EdgeResponseWrapper`
  and `EnrichScanResponse` payloads via `JSONDecoder`. Also covers
  `activeScanId` lifecycle: `testPrepareForNewScanClearsActiveScanId` verifies
  the pre-scan reset clears the stale ID;
  `testActiveScanIdClearedByInferenceTaskDefer` documents the
  `defer { self.activeScanId = nil }` contract at `InferenceEngine.swift:237`;
  `testCancelActiveRequestDoesNotClearActiveScanId` asserts the asymmetry —
  `cancelActiveRequest()` does NOT clear `activeScanId` (the background
  URLSession path uses it to detect a live inference).
  - **`/identify` response**: Validates `EdgeResponse` fields (`scan_id`,
    `common_name`, `confidence_score`, `taxonomy`, `insight_data`,
    `species_insights.habitat_description`). Asserts that `species_insights` is
    nil on cache-miss responses and non-nil on cache-hit responses. Note:
    `aiReasoning` is populated from `insight_data.ai_reasoning` (per-scan,
    always present when `insight_data` exists) — it is **not** a separate
    `premium_insights` block.
  - **`/enrich-scan` response**: Validates flat
    `similar_species: [EnrichScanResponse.SimilarSpeciesEntry]` array decoding
    with all four fields (`scientific_name`, `common_name`,
    `reference_image_url`, `iucn_red_list_status`). Asserts sparse entries (only
    `scientific_name`) decode with `nil` optional fields. Asserts absent
    `similar_species` key decodes as `nil`, not empty array.
  - **`load(from:)` path**: Asserts that
    `LocalScanRecord.similarSpecies: [String]?` strings are wrapped into
    `SimilarSpeciesEntry` instances with `nil` enrichment fields (historical
    record path). Asserts nil `similarSpecies` on the record produces `nil` (not
    an empty `SimilarSpecies` struct) on `speciesData`.
  - **Inference tier**: Validates Flash vs Pro confidence band thresholds via
    `MerianConfig.confidenceBands(forInferenceTier:)`. Asserts nil tier resolves
    to Flash for safety.
  - **Moderation Flagging**: Asserts `flagAIIdentification` seamlessly mutates
    the offline tracking property `isFlagged` purely natively ahead of
    networking attempts (`testFlagAIIdentificationMutatesLocalState`), and
    strictly restores from `LocalScanRecord` on cold boot
    (`testLoadFromRecordPopulatesIsFlagged`).
- **`SpeciesDictionaryTests.swift`**: Validates the public dictionary response
  decoder, additive `content_quality`, legacy no-`schema_version` compatibility,
  client-side quality fallback for old payloads, species-ID-preferred request
  payloads, route entry-point propagation for analytics, view-model
  success/not-found/error states, and the `MerianNetworkClient` 10-minute
  in-memory memoization path for recently opened species pages. Test setup
  resets the singleton cache whenever a mocked `URLSession` is injected so
  serialized network tests do not share stale dictionary entries.
- **`ViewfinderIntelligenceTests.swift`**: Validates real-time analysis logic,
  ensuring frames are evaluated correctly before inference is triggered.
- **`ArchiveManagerTests.swift`, `SyncStateManagerTests.swift`,
  `ScanRepositoryTests.swift`, `BackgroundDatabaseActorTests.swift`**: Verifies
  bi-directional SwiftData relationship behavior within an isolated context,
  without triggering SwiftData loop issues. `ScanRepositoryTests` includes
  `testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps` — verifies the
  `guard let parsedDate = exifDate else { continue }` path in `ingestScans` by
  replicating the exact `flatMap + ISO 8601 formatter` derivation and asserting
  nil/garbage inputs produce nil (not a fabricated `Date()`). Also includes
  `testV26SimilarSpeciesRoundTrip` — inserts a `LocalScanRecord` with
  `similarSpecies: [String]?` and verifies the array round-trips through
  SwiftData without corruption; and `testV27LookalikesDataRoundTrip` — inserts a
  `LocalScanRecord` with `lookalikesData: Data?` (JSON-encoded
  `[SimilarSpeciesEntry]`) and verifies the blob round-trips and decodes
  correctly (covering the `MerianSchemaV27` field added for rich lookalike
  persistence). `BackgroundDatabaseActorTests` uses `CurrentSchema` and a
  disk-isolated container to validate actor-boundary `Sendable` payload
  extraction across a `Task.detached` boundary.
  **`testFetchPendingScansExcludesNonPendingScans`** (V33) seeds scans in all
  five states (`.pending`, `.uploading`, `.staged`, `.inferencing`, `.failed`)
  and asserts `fetchPendingScans` returns only the `.pending` record — directly
  validating the V33 `scanStateRaw == 0` predicate that prevents re-dispatching
  in-flight or tombstoned scans. Also covers `updateScanWithOverride`,
  `updateScanAsFlagged`, and `updateScanAsUnflagged` persistence paths.
- **`FileIOActorTests.swift`**: Covers the audio persistence resolver across the
  current supported path shapes: bare Documents filename, bare temp filename,
  and absolute temp path. This is the regression suite for "audio disappears
  after identification" class bugs.
- **`InsightSheetViewModelTests.swift`**: Verifies carousel handoff integrity
  across queued/analyzing/result states, including mixed media. The key
  regression is that an audio page present during analysis remains present, with
  the same ordering, after `speciesData` arrives.
- **Insights focused model tests**: `CandidateSwipeSessionTests.swift` covers
  skip/reject/confirm/restart/exhausted transitions without SwiftUI animation
  state. `SpeciesObservationStatsViewModelTests.swift` covers actor/reducer
  aggregation plus reducer normalization and empty-bucket behavior.
  `InsightChatTests.swift` covers Field chat request/response decoding,
  feedback/summary/prompt-suggestion DTO decoding, local fallback and
  AI-generated quick prompt merging/filtering, failed outgoing recovery state,
  deterministic unavailable-state hiding, and the 600-character draft cap.
  `UserTagsMutationControllerTests.swift` verifies tag saves commit locally
  before external cloud/search side effects can run.
- **`CaptureTelemetryTests.swift`**: Directly validates that offline/historic
  captures explicitly decouple live sensor leakage (like LiDAR distance vectors
  or view-finder zoom scopes) away from EXIF bounds.
- **`ScansManagerTests.swift`**: Validates local string-index mapping (group
  name taxonomies, semantic tags, explicitly added `customTags`, and
  one-character unigram candidates). Asserts `NotificationCenter` routing
  dynamically patches specific payloads (`testCustomTag_DynamicHotSwap`)
  instantly without OOM-burst re-renders. Search and indexing assertions now
  wait on `ScansManager.SearchDebugEvent` completions instead of fixed
  `Task.sleep` windows, including explicit debounce-cancellation coverage that
  proves a superseded query never emits `searchCompleted`. Also verifies the
  indexed query path preserves substring behavior
  (`testSubstringSearchFilteringPreservesContainsSemantics`) so the candidate
  index does not regress the user-facing `contains` search contract.
- **`LocalImageLoaderTests.swift`**: Explicitly locks concurrent network payload
  boundaries using overarching `TaskGroup`s. Asserts `fetchNetworkFallback`
  deduplicates asynchronous URL fetches seamlessly to prevent multi-grid render
  flooding.
- **`OfflineQueueManagerTests.swift`**: Mocks queue payload insertions.
  - **In-Memory Isolation**: Spins up a `@MainActor ModelContext` with
    `.isStoredInMemoryOnly = true` to isolate test data from the user's real
    offline queue.
  - **Core Lifecycles**: Exercises `.enqueueCapture` / non-visual queue
    insertion (asserting SwiftData record counts increment correctly), canonical
    mixed-media serialization, and `.purgeSoftDeletedRecords()` (asserting
    soft-deleted items are removed while undeleted items persist).
  - **Media staging contract drift**: Loads
    `docs/contracts/media-staging-upload-manifest.json` and asserts
    `MerianConfig` matches the documented file, audio, and video budgets.
    Also covers the canonical video scan upload shape: five sampled inference
    frame files plus one playback video file must fit in one signing batch.
  - **Disk Teardown**: Confirms that sandbox files in `URL.documentsDirectory`
    are deleted during purges to prevent storage bloat.
  - **`isSyncing` Latch Safety
    (`testSyncPendingScansResetsIsSyncingOnEmptyTasks`)**: Seeds a single
    `OfflineQueuedScan` with a non-existent image path, calls
    `syncPendingScans()`, awaits the `syncTask`, and asserts
    `isSyncing == false`. Guards against the background-task expiration or
    zero-task failsafe path leaving the latch permanently locked.
  - **`replayInferenceForUploadedScans` pickup
    (`testReplayInferencePicksUpStagedScans`)** (V33): Inserts a scan with
    `scanState: .staged` and `stagedR2Keys` set, calls
    `replayInferenceForUploadedScans()` with `isOnline=true` and
    `hasReconciledStartupState=true`, then polls a fresh `ModelContext` for up
    to 8 s until the scan's `queueState == .inferencing`. The
    `.staged → .inferencing` transition is performed by `tryClaimForInference`
    before the background download task is dispatched — it is the reliable,
    network-free observable that the pipeline was triggered. Validates the
    happy-path connectivity-restore replay without any in-memory lock set.
  - **`replayInferenceForUploadedScans` skip
    (`testReplayInferenceSkipsAlreadyClaimedScans`)** (V33): Inserts a scan with
    `scanState: .inferencing` (already claimed by another pipeline). Calls
    `replayInferenceForUploadedScans()` and waits 500 ms; asserts the durable
    queue metadata remains unchanged. Guards against dispatching a second
    pipeline for a scan already in `.inferencing` state — the function only
    queries `.staged` scans.
  - **Exponential backoff math (`testUploadRetryDelayExponentialBackoff`)**:
    Replicates the `syncPendingScans` backoff formula inline and asserts the
    full delay sequence (0→1→2→4→8→16→30) and cap behavior. Also asserts
    `maxUploadRetryDelay == 30`.
  - **Durable queue retry policy**: `OfflineQueueRetryPolicy` tests should cover
    transient network/server failures, local-media terminal failures, persisted
    `queueNextRetryAt`, server `retry_after`, and app relaunch behavior. Video
    cases must assert durable playback media remains required while image,
    audio, and description-only scans use the same scheduler.
- **`CompositeLibraryTests.swift`**
  (`apps/ios/MerianTests/Features/Scans/Library/`): Validates the bounding
  behaviors of the composite `ScansGrid` that renders both `OfflineQueuedScan`
  and `LocalScanRecord` items in the same `LazyVGrid`.
  - **Unique ID Guarantee**: Inserts three `OfflineQueuedScan` records and
    asserts all three `id` values are distinct, guarding against accidental
    identifier collisions inside the grid's `ForEach` key space.
  - **Thumbnail fallback safety**: Asserts queued-scan tiles can safely derive
    an empty thumbnail from the canonical media timeline when no image is
    staged, instead of depending on a dedicated `localImagePaths` column.
  - **`queueState` Default (`testQueueStateDefaultsPending`)** (V33): Asserts a
    freshly constructed `OfflineQueuedScan` has `queueState == .pending` (raw
    value 0), so new records are always picked up by the next `syncPendingScans`
    pass.
  - **`.failed` Predicate (`testFailedScansExcludedByPredicate`)** (V33):
    Mirrors the exact `#Predicate<OfflineQueuedScan> { $0.scanStateRaw < 5 }`
    used in `ScansSheetView`'s `@Query` and asserts `.failed` (raw value 5)
    records are excluded while `.pending` records are returned. Guarantees
    tombstoned uploads never resurface in the library.
  - **Selection Engine Decoupling**: Injects an `OfflineQueuedScan` ID directly
    into `ScansManager.selectedScans` (the adversarial case) and confirms
    `getSelectedLocalRecords()` returns nothing for it. Because
    `getSelectedLocalRecords()` filters from `filteredScans: [LocalScanRecord]`,
    the queued scan ID cannot reach the batch-share / batch-delete pipeline
    regardless of what is in `selectedScans`.
- **`ImageCacheTests.swift`**: Ensures the Swift RAM cache does not exceed
  maximum system allocation limits.

### Hardware & Ecosystem Integrations

- **`CameraManagerTests.swift`, `CaptureWorkspaceViewModelRefinementTests`**:
  Validates UI state routing logic. `CaptureWorkspaceViewModelRefinementTests`
  drives `startRefinementScan(from:)` through the injected
  `PreparedStagedImageLoader` seam, asserting both the success path
  (memory-mapped refinement request is committed into `stagedCapture.images`)
  and the failure path (`isStagingRefinement` drops back to `false` without
  appending a stale image). This gives deterministic coverage over refinement
  staging behavior without simulator-driven UI automation.
- **`HardwareOrchestratorTests.swift`**: Mocks
  `ProcessInfo.processInfo.thermalState` boundaries to verify the camera
  throttles FPS dynamically without restarting instances. Verifies the
  `UserDefaults` binding (`isExpeditionModeActive`) correctly overrides OS
  thresholds to lock to 24fps and remove glass modifiers. To avoid Swift runtime
  crashes in asynchronous CI containers, calls `AppTelemetry.initialize()` at
  `HardwareOrchestratorTests.init()` using a stub `TEST_MOCK_ID` configuration.
- **`EnvironmentContextManagerTests.swift`**: Asserts safe async handling over
  simulated `CLLocationManager` outputs for offline contexts.
- **`HapticManagerTests.swift`**: Confirms safe initialization of
  `UIImpactFeedbackGenerator` buffers without stalling threads. Asserts that
  setting `UserDefaults.standard.set(false, forKey: "isHapticsEnabled")`
  prevents sequence triggers without causing hardware memory faults.
- **`PhotoLibraryManagerTests.swift`**: Validates that toggling
  `UserDefaults("saveToCameraRoll")` drops the payload without triggering
  `PHPhotoLibrary` memory allocations.

### Security, Network & Identity

- **`MerianNetworkClientTests.swift`, `SupabaseManagerTests.swift`**: Tests API
  routing, including `.401` retry cycles for Ghost User flows and JSON body
  payload serialization.
  - **MockURLProtocol Contamination & `.serialized`:** Because XCTest routines
    process entirely concurrently natively inside Xcode 16+, using generic
    static closures (like `MockURLProtocol.requestHandler`) generates race
    conditions during intercept evaluations natively returning expectations
    completely malformed. You MUST rigidly prefix global Network suites heavily
    utilizing mock singletons with `@Suite(.serialized)` assuring clean
    serial-execution pathways.
  - **`testEndpointURLPathContainsFunctionsV1Segment`**: Verifies
    `endpointURL(_:)` produces the full `/functions/v1/<endpoint>` path
    structure by capturing the outbound URL in a mock handler. Guards against
    `supabaseUrl` misconfiguration producing a silent wrong-URL path.
  - **TLS chain-walking tests
    (`testTLSChainWalkingAcceptsIntermediateCertWhenLeafIsUnknown`,
    `testTLSChainWalkingRejectsUnknownChain`)**: Documents and validates the
    `certChain.contains { ... }` refactor that replaced `certChain.first`. The
    intermediate-CA test is the key regression guard: if someone reverts to
    `certChain.first`, the intermediate CA backup hash becomes dead code and
    this test fails. `testPinnedHashesAreNonEmptyValidBase64` guards against the
    `pinnedCertHashes` set accidentally being cleared (which would silently
    disable pinning in Release builds).
- **`DeviceIdentityManagerTests.swift`, `RevenueCatManagerTests.swift`**:
  Isolates authentication loops away from live production identifiers.
  `DeviceIdentityManagerTests` reads `DeviceIdentityManager.shared.deviceId`
  (the public `@Observable` property) — it does **not** call the private
  `getOrGeneratePersistentIDFV()` method directly. The test wipes the relevant
  Keychain item via `SecItemDelete` before and after the assertion to prevent
  cross-run contamination.
- **`SocialGuardManagerTests.swift`, `CircuitBreakerManagerTests.swift`**:
  Asserts offline logic ensuring blocked users do not re-populate the feed.

### UI & Utilities

- **`ImageDownsamplerTests.swift`**: Tests Core Graphics memory constraints by
  processing 4000x4000 payloads under safe metric limits, preventing
  Out-Of-Memory JetSam crashes.
- **`MessageScanShareCacheTests.swift`**: Verifies the Messages App Group cache,
  generated description text, field-notes opt-in behavior, public Explore URL
  inclusion, and `merian://scan/{id}` / `merian://scans` deep-link parsing.
- **`ExploreHashtagSuggestionTests.swift`**: Covers the share composer's
  AI-assisted hashtag suggestions, including
  species/taxonomy/location/field-note ranking, selected-tag exclusion, five-tag
  slot handling, and normalization of typed hashtag input before publishing.
- **`ScansManagerTests.swift`**: Verifies search-index construction, incremental
  reindexing, sort behavior, and selection limits for the Scans library.
- **`OnboardingViewModelTests.swift`**: Validates the extracted UI state machine
  progression, ensuring hardware fallback steps prevent `Int` scalar
  out-of-bounds crashes. Tests core persistence loops simulating `@AppStorage`
  routing flags from the `.ready` boundary, fully offline.

## Testing the Species Lookalike Pipeline

The `SimilarSpecies` / `SimilarSpeciesEntry` domain model has two distinct data
paths that require separate coverage:

### 1. Rich path (live scan + `enrich-scan` response)

`EnrichScanResponse.SimilarSpeciesEntry` (Codable DTO, snake_case) is decoded
from the `/enrich-scan` JSON payload and mapped to the domain
`SimilarSpeciesEntry` (camelCase) by `InferenceEngine.fetchAndApplyEnrichment`.
Tests:

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

Key assertions: absent key decodes as `nil` (not `[]`); sparse entries (only
`scientific_name`) decode with `nil` optionals without crashing.

### 2. Historical path (`load(from:)`)

When opening a scan from the library, `InferenceEngine.load(from:)` reads
`LocalScanRecord.similarSpecies: [String]?` (bare scientific name strings) and
wraps each into a `SimilarSpeciesEntry` with `nil` enrichment fields:

```swift
// LocalScanRecord.similarSpecies = ["Procyon cancrivorus", "Bassariscus astutus"]
// → SimilarSpecies(entries: [
//     SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, ...),
//     SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, ...)
//   ])
```

`SimilarSpeciesGallery` falls back to `SimilarSpeciesImageFetcher` for image
lookup when `referenceImageUrl == nil`.

### Backwards-compat accessor

`SimilarSpecies.lookalikes: [String]` (computed) maps entries to their
scientific names. Any code that previously consumed `[String]` arrays from the
old `SimilarSpeciesData.lookalike_species` DTO uses this accessor — it must
continue returning names in the same order as `entries`.

## Mocking Apple Ecosystem Limits (`DeviceIdentityManager`)

When testing across AI boundaries, tests must not pollute real Ghost Session
tracking identities via PostHog telemetry. Tests avoid calling
`SupabaseManager.shared.initializeGhostSession()` and instead test business
logic models decoupled from live Apple ecosystem HTTP constraints.

## API & Edge Function Testing (Deno)

Merian relies on Supabase Edge Functions. Due to the rapid iteration cycle of
Gemini structures, type safety at the network boundary (Swift → TS) must be
guaranteed by AST regression guards.

Function-local tests under `services/supabase/functions/insight-chat/` verify
the expanded text-only prompt context, raw image URL/storage-key/coordinate
exclusion, raw-image-access system instruction, supported action parsing,
message caps, deterministic safety refusals, and the `suggest_prompts` action's
safe three-prompt JSON contract.

Media-ingestion durability has focused Deno coverage as well:
`_shared/scanIngestionJobs_test.ts` locks client-safe job-state projection and
the deterministic manifest checksum; `_shared/scanIngestionIntents_test.ts`
locks sanitized replay-intent construction and inline-media redaction;
`_shared/scanIngestionCompatibility_test.ts` locks the legacy
identify/describe/audio compatibility bridge so staged media and text-only
requests replay through `/identify-multimodal` while inline media stays redacted
and non-resumable; `replay-scan-ingestion/worker_test.ts` covers staged payload
reconstruction, existing complete scan short-circuiting, and incomplete video
rows being left for repair instead of duplicate AI replay;
`reconcile-scan-media-assets/worker_test.ts` covers video repair, abandoned
media cleanup, active-job waiting, ownership matching by user plus scan id, and
job completion/failure feedback; `_tests/scanMediaIngestionContract.test.ts` is
the media-type matrix that keeps image, audio, text-only, and video replay,
status, repair, and Explore-share contracts aligned;
`_shared/mediaBudgets_test.ts` and `generate-upload-urls/storage_test.ts` keep
the staged signing limits, allowed content types, and six-file video batch in
sync with the documented contract; and `_tests/migrationMediaContract.test.ts`
checks the scan-media, reconciliation, scanless staged-row repair,
ingestion-job, manifest-checksum, intent-outbox, and replay-worker migrations.
Run the migration contract test with `--allow-read=services/supabase/migrations`
because it reads SQL files directly.

### `validate_edge_dtos.ts`

- **AST Protection**: Before every production Edge rollout, AI Agents and
  developers run this script to syntactically trace the Deno
  `merianResponseSchema` and diff it against the properties in
  `InferenceEdgeDTOs.swift`. This proactively halts deployments if a UI variable
  drifts out of sync.
- **`LookalikeSummary` shape check**: The script must assert that
  `EnrichData.similar_species` is typed as `LookalikeSummary[]` and that
  `LookalikeSummary` exposes all four fields: `scientific_name`, `common_name`,
  `reference_image_url`, `iucn_red_list_status`. This guards against the
  response schema accidentally reverting to the legacy
  `{ lookalike_species: string[] }` wrapper shape.
- **Lookalike relation metadata**: Swift and Deno tests cover the additive
  `reason`, `visual_traits`, `confidence`, source/review, direction, and order
  fields. Older payloads and cached `lookalikesData` blobs without those keys
  must still decode successfully with empty/default metadata.
- **Public species projection privacy contract**:
  `_shared/publicSpeciesProjection_test.ts` builds a dictionary payload from a
  row fixture that includes scan/user/private fields and asserts those fields
  are not projected. It also verifies
  `publicSpeciesProjectionForbiddenKeys(...)` catches explicit leaks such as
  `scan_id`, `field_notes`, coordinates, and per-scan AI reasoning. This
  protects `/species-dictionary`, Explore detail similar species, and the future
  web species endpoint from mixing species-level dictionary data with
  scan-specific content.
- **Public species content quality**: `_shared/publicSpeciesProjection_test.ts`
  classifies dictionary rows as `complete`, `sparse`, or `needs_enrichment` from
  public reference-image, overview, habitat/distribution, and taxonomy signals.
  This keeps sparse-page UI behavior deterministic across iOS and the future web
  frontend.
- **Public web media attribution audit**:
  `_shared/publicSpeciesProjection_test.ts` covers
  `publicWebReferenceImageAttributionIssues(...)`, which future web species
  pages must run before rendering reference images. The audit flags every public
  image missing `license` or `attribution`.
- **Species content provenance contract**:
  `_shared/speciesContentProvenance_test.ts` verifies source assignment and
  refresh windows for dictionary fields, group tags, and lookalikes. It should
  be updated whenever `species_content_provenance.content_key`, source defaults,
  or refresh scheduling rules change.
- **Scheduled species content refresh worker**:
  `refresh-species-content/db.test.ts` verifies request validation, queue
  grouping/skipping, selective GBIF/Wikipedia field updates, reference-image RPC
  payload mapping, and provenance writes with a mocked Supabase client. It
  should be updated whenever the worker supports a new `content_key` or changes
  refresh safety rules.
- **Scheduled Merian reference-image worker**:
  `refresh-merian-reference-images/db.test.ts` verifies request validation and
  RPC invocation; `_tests/merianReferenceImagesDb.test.ts` verifies threshold
  filtering for both image quality and species confidence, all-photo candidate
  expansion, per-species caps, confirmed-species resolution, Merian-first
  ordering, source visibility removal, and preservation across external
  GBIF/Wikipedia refreshes.
- **Public dictionary cache headers**: `_shared/http_test.ts` verifies
  `jsonResponse(...)` can merge endpoint-specific cache headers without dropping
  standard JSON/CORS headers. `/species-dictionary` uses this path for cacheable
  `200 OK` public dictionary responses; error responses stay uncached.

### `export-dwca/index_test.ts`

- **Global Anonymization**: Evaluates `generateDwcARow` mathematically, ensuring
  `export_scope: global` safely casts unauthenticated user IDs down to random
  SHA-256 strings (e.g., `merian_user_...`).
- **Precision Preservation**: Validates that standard queries correctly map
  highly precise exact string values.
- **Protected Species Truncation**: Validates that matching protected statuses
  (`endangered`, `vulnerable`) explicitly drops exact map coordinates down to
  single-digit resolution metrics (`Math.round(lat * 10) / 10`) regardless of
  the original `gps_lat_exact` fields, completely shielding sensitive flora and
  fauna.
- **Null `species_dictionary` handling**:
  `generateDwcARow handles null species_dictionary without throwing` and
  `produces an empty scientific_name field` — guards against the pre-fix `|| {}`
  pattern that caused `deno check` failures when `scan.species_dictionary` was
  null. Verifies the optional-chaining fix (`species?.scientific_name`) produces
  a valid CSV row (not a JS runtime error string) for scans ingested before the
  species enrichment pipeline ran.

### `revenuecat-webhook/index_test.ts`

- **UUID regex validation**: Tests the `UUID_REGEX` guard that blocks
  `$RCAnonymousID:xxx` anonymous IDs and other non-UUID strings before any DB
  access. Verifies rejection of `null`, empty strings, numeric types, and
  malformed UUIDs; acceptance of lowercase, uppercase, and `crypto.randomUUID()`
  output.

### `sync-collections/db_test.ts`

- **`syncMembershipDelta` error propagation**: Verifies the function throws (not
  `console.error`-swallows) when the scan validation query fails, when a
  membership delete operation is rejected, and resolves cleanly on success. Also
  asserts the early-return path for empty `ownedIds` makes no DB calls.

### `_shared/tierCache_test.ts`

- **Basic set/get contract**: Verifies `setTierCache` + `hasTierCached`
  round-trip correctly and unknown users return false.
- **Capacity eviction (pass 2 — oldest-25% path)**: Seeds 1000 entries, triggers
  the 1001st insert, and asserts: the triggering entry IS in cache; early
  entries (0–249) were evicted by the oldest-25% sweep; tail entries (750+)
  survive.
- **Idempotent update guard**: Verifies that overwriting an existing key at
  capacity does NOT trigger eviction — the `!_tierCache.has(userId)` guard
  prevents the eviction block from firing on an update.
