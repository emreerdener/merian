# Merian Testing & Quality Assurance Strategy

Merian employs a lightweight, modern Swift-native testing structure leveraging the `Testing` framework globally, cleanly isolating offline UI queues and core engine components away from the rigid Apple lifecycle loops seamlessly. 

## In-Memory Database Containers (`SwiftData`)

We rigorously prevent test suites from polluting physical local iOS file system directories and SQLite databases natively. All local unit tests physically testing caching states and soft-deletions must explicitly invoke an isolated, volatile `ModelContext`:

```swift
@MainActor
private func createInMemoryContext() throws -> ModelContext {
    let schema = Schema(MerianSchemaV3.models)
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
    return ModelContext(container)
}
```

This guarantees that:
1. Operations like `context.save()` happen exclusively in RAM and resolve instantly, bypassing native disk IO waits safely.
2. The user's genuine `Life List` and native `OfflineQueuedScan` artifacts are rigidly shielded from testing permutations permanently.

## Core Suites

The testing bounds are mapped physically within `merianTests`:

- **`InferenceEngineTests.swift`**: Securely asserts logical bounds surrounding decoding the `EdgeResponseWrapper` AI payloads structurally, mapping specific physical metadata like `is_poisonous`, raw numeric `ai_confidence_score` indices and deep structural `TaxonomyData` logic seamlessly across `JSONDecoder`.
- **`OfflineQueueManagerTests.swift`**: Dynamically mocks native payload insertions safely. Rigorously exercises `.enqueueCapture` and native `.purgeSoftDeletedRecords()`, strictly asserting local counts inside the testing execution loops and explicitly confirming the `URL.documentsDirectory` physical teardowns resolve successfully.
- **`GamificationManagerTests.swift`**: Validates native persistence bounds asserting proper math updates against user local scores ensuring UI progression trackers never skew bounds unexpectedly.
- **`SpeciesDataTests.swift`**: Ensures native semantic `Tag` array extraction architectures behave structurally identically inside testing arrays.

## Mocking Physical Apple Ecosystem Limits natively (`DeviceIdentityManager`)

When testing natively across AI boundaries, it is structurally impermissible to pollute real Ghost Session tracking identities via PostHog telemetry instances. Explicit tests avoid calling `SupabaseManager.shared.initializeGhostSession()` natively, instead strictly executing business logic testing models securely decoupled from Apple ecosystem HTTP constraints completely!
