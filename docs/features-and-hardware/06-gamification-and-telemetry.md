# Gamification and Zero-PII Telemetry

Merian gamifies exploration while respecting user privacy through analytics environments decoupled from Apple ecosystem identifiers.

## Gamification Architecture (`GamificationManager`)

Powers the interactive `.riv` Rive model rendered by `Terrarium`.

- Logs species discoveries into `$unlockedSpeciesCount`, persistently updating `.set(unlocked, forKey:)`.
- Evaluates novel biological insertions by intercepting `LocalScanRecord` writes; if a species has never been cached locally, routes an `isNewDiscovery = true` payload to `InsightSheetView`.
- **Non-Biological Suppression**: Even when `isNewDiscovery = true` is passed downstream, the UI layer filters out non-biological results (e.g., `not applicable`, `unknown subject`, `inanimate object`) and requires `isBiological == true`. This prevents the app from triggering a discovery celebration for scans of gravel, car tires, or blurry floors.
- Presents `NewDiscoveryCelebrationView.swift` (when biologically validated) as a glassmorphic floating pill-shaped toast notification docked at the top of the interface. It dismisses automatically via a state-retained `Task.sleep` without blocking user touches, and supports manual swipe/tap-to-dismiss via `DragGesture`. Triggers `HapticManager.shared.triggerSuccessPulse()` and tracks `TelemetryManager.send("NewSpeciesDiscovered")` under Zero-PII offline rules.
- Triggers `HapticManager.shared.triggerSelectionPulse()` when an achievement (`hasFireflyBadge`) activates after 5 taxonomic finds.
- Injected via `.environmentObject` into `Terrarium`, which reacts by calling `.setInput("TotalSpeciesCount")` to animate 3D model foliage, fireflies, and natural artifacts using `RiveViewModel` states.
- **Erasure Mechanics (`decrement_user_species_count`)**: When a user permanently deletes a scan that was their last documented capture of a specific biological species, a PostgreSQL PL/pgSQL database trigger intercepts the deletion and decrements their `users.total_species_discovered` counter, keeping gamification counts accurate regardless of offline delay. Locally, SwiftData recalculates the Scans library and syncs UI state.

## Track B: Achievements

To diversify gamification beyond pure numerical counts, the Achievements track unlocks progression milestones based on scientific taxonomy, environmental conditions, and citizen science impact:
- **The Observer**: Complete your first nature scan (1 Scan).
- **The Naturalist**: Scan 5 different unique species.
- **The Botanist**: Scan 10 different plant species.
- **The Zoologist**: Scan 10 different animal (insect/arachnid) species.
- **The Mycologist**: Scan 10 different fungi species.
- **The Urban Ecologist**: Scan 10 species in urban environments.
- **Environmental & Impact Tracking**:
  - **The Frost Walker**: Scans recorded where `weatherTemperatureF < 32°`.
  - **The Alpine Naturalist**: Scans recorded where `gpsElevation > 2500m`.
  - **The Nocturnal Observer**: Scans taken strictly between 22:00 and 05:00.
  - **The Guardian**: Scans tagged with `isInvasive`.
  - **The Toxicologist**: Logging `isPoisonous` plants/fungi.
  - **The Conservationist**: Documenting species protected by the IUCN Red List.
  - **The Perfect Lens**: Capturing imagery with a `0.98+` Vision Confidence Score.

### Why Achievements are NOT Tracked in the Database

Achievement states (like `isCompleted` or progress counts) are not stored in the database — neither locally in SwiftData via a dedicated model, nor remotely in PostgreSQL. The reasons for this architecture are:

1. **Calculable State vs. Stored State**: Achievements reflect the user's data, not new data in their own right. Every achievement metric can be derived mathematically from the existing `LocalScanRecord` repository. Storing achievement progress creates redundant, overlapping state that risks falling out of sync with the true biological scans table.
2. **Synchronization & Erasure Hazards**: If achievements were stored as dedicated rows, permanently deleting a photo or purging non-biological scans would require cascading update chains or remote PostgreSQL trigger synchronizations to decrement or revoke achievement state. This introduces fragile network constraints and logic bugs.
3. **Absolute Source of Truth**: By making raw scans the source of truth, the system self-heals. Restoring a user's data from the cloud onto a blank iOS device naturally recreates their exact achievement states through local processing, without a secondary "sync achievements" API call.
4. **Performance**: UI blockers previously came from synchronously looping arrays. By isolating the `calculateAchievements()` logic into a dedicated asynchronous `ProfileDatabaseActor`, the application computes the full award array off the main thread without lagging the SwiftUI render loop.

**Off-Thread Calculation & Chronological Heuristics**: `calculateAchievements()` runs inside a `@ModelActor ProfileDatabaseActor` extension. It executes a targeted `FetchDescriptor` sorted by `\LocalScanRecord.timestamp` in reverse chronological order. This allows the pipeline to fetch only the taxonomy layers (`\.scientificName`, `\.taxonomyKingdom`), environmental fields (`\.isPoisonous`, `\.isInvasive`), and temporal metadata (`\.gpsElevation`, `\.weatherTemperatureF`) needed for the calculation. Iterating newest-to-oldest, the algorithm captures `lastInteractionDate` metadata by recording the timestamp of the first iteration a unique biological entity appears. It aggregates results using `Set<String>` on `scientificName` to derive unique biological diversity per category, and resolves a matrix of lightweight `Sendable` structs (`AchievementPayload`) to the UI with exact chronological context for the "Smart sort" closures. These primitives are defined in `Features/Profile/Models/GamificationModels.swift`, isolated from UI loops.

## Secure Telemetry Ecosystem

To preserve a sub-1-second camera boot experience, both Apple TelemetryDeck and PostHog SDKs initialize off the main thread. `MerianApp` delegates their configurations to a `Task.detached(priority: .background)` block with a 500ms delay, keeping the primary UI render pass uncontested on the CPU.

### `AppTelemetry` (Telemetrydeck SDK)

Monitors core system stability using PII-free Apple anonymous strings.

- Calls `.initialize(config)` to bind the platform key.
- **Synchronous initialization**: `AppTelemetry.initialize()` is called directly in `MerianApp.init()` before any view is constructed. `TelemetryManager.initialize(with:)` is purely synchronous config storage — safe on the main thread. The previous pattern of deferring initialization inside a `Task.detached` with a 500ms sleep caused a `fatalError` whenever anything accessed `TelemetryManager.shared` during that window. The internal `isInitialized` NSLock guard is still present to protect unit-test contexts (e.g. `HardwareOrchestratorTests` which initializes the SDK with a stub ID) from calling `.send()` before `.initialize()`.
- Custom signals track camera activity (`trackScan`).
- The hardware orchestrator calls `.trackThermalThrottling(fpsLimit:)` to record heat warnings and provide data on Apple thermal management performance.

### `PostHogManager`

Tracks frontend button interactions to measure feature discovery, anonymously.

- Uses `identify(...)` to link Supabase Anonymous UUID strings alongside RevenueCat identifiers.
- Calls `reset()` when `SupabaseManager.shared.signOut()` clears session state, erasing session metrics on demand.
