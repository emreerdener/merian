# Gamification and Zero-PII Telemetry

Merian gamifies exploration natively while respecting user privacy intrinsically through decoupled analytics environments physically isolated from physical Apple bounds.

## Gamification Architecture (`GamificationManager`)

Powers the interactive `.riv` Rive model rendered by `Terrarium`.

- Logs globally passing taxonomy boundaries into `$unlockedSpeciesCount`, persistently updating `.set(unlocked, forKey:)` natively.
- Evaluates novel biological insertions natively intercepting `LocalScanRecord` writes; if a species has never been cached locally, routes a strict `isNewDiscovery = true` payload mapping directly to `InsightSheetView`.
- **Targeted Non-Biological Suppression**: Even if `isNewDiscovery = true` is passed downstream natively, the UI layer strictly filters out dead strings (e.g., `not applicable`, `unknown subject`, `inanimate object`) and unconditionally requires `isBiological == true`. This rigidly prevents the app from cheering the user for scanning gravel, car tires, or blurry floors.
- Instantiates `NewDiscoveryCelebrationView.swift` (when biologically validated), enforcing a premium, glassmorphic floating pill-shaped "Toast" notification docked at the top of the interface. It scales natively and tears down automatically via a state-retained `Task.sleep` without blocking user touches (it also supports manual swipe/tap-to-dismiss via `DragGesture`). Generates `HapticManager.shared.triggerSuccessPulse()` callbacks and tracks Apple-native `TelemetryManager.send("NewSpeciesDiscovered")` strictly observing Zero-PII offline rules.
- Executes Apple native hardware `HapticManager.shared.triggerSelectionPulse()` the second an achievement (`hasFireflyBadge`) natively triggers over 5 taxonomic finds natively.
- Injects natively via `.environmentObject` into `Terrarium` passively reacting `.setInput("TotalSpeciesCount")` animating 3D model foliage, fireflies, and natural artifacts instantaneously using `RiveViewModel` states seamlessly.
- **Erasure Mechanics (`decrement_user_species_count`)**: If a user permanently deletes a scan, and that specific scan happens to be their absolute final documented capture of a specific biological species, a strict PostgreSQL PL/pgSQL database trigger will silently intercept the erasure. It will perfectly decrement their unified `users.total_species_discovered` counter seamlessly maintaining accurate gamification counts regardless of offline delay. Locally, the SwiftData boundary instantly recalculates their Scans library natively seamlessly syncing UI states exactly.

## Track B: Achievements

To diversify gamification away from pure numerical counts, the Achievements track unlocks specific progression milestones based on authentic scientific taxonomy, extreme environmental conditions, and citizen science impact:
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
  - **The Guardian**: Tracing scans definitively tagged with `isInvasive`.
  - **The Toxicologist**: Explicitly logging `isPoisonous` plants/fungi safely.
  - **The Conservationist**: Documenting species protected by the IUCN Red List.
  - **The Perfect Lens**: Capturing imagery obtaining `0.98+` Vision Confidence Score.

### Why Achievements are NOT Tracked in the Database

We purposefully **do not** track or store achievement states (like `isCompleted` or progress counts) in the database (either locally in SwiftData via a dedicated model or remotely in PostgreSQL). The reasons for this pure decoupled architecture are:

1. **Calculable State vs. Stored State**: Achievements define a reflection of the user's data, not new intrinsic data. Every achievement metric can be mathematically derived exclusively from the existing `LocalScanRecord` repository. Storing achievement progress creates redundant, overlapping state that inherently risks falling out of sync with the true biological scans table.
2. **Synchronization & Erasure Hazards**: If achievements were stored as dedicated rows, permanently deleting a photo or purging non-biological scans would require massive cascading update chains or remote PostgreSQL trigger synchronizations specifically built to decrement or revoke achievement bounds. This introduces fragile network constraints and logic bugs.
3. **Absolute Source of Truth**: By forcing the source of truth to be the raw scans, the environment natively self-heals. Restoring a user's data from the cloud onto a blank iOS device naturally recreates their exact achievement states automatically through local processing, without needing a secondary "sync achievements" API.
4. **Performance is Solved**: Historically, UI blockers came from synchronously looping arrays. By aggressively isolating the `calculateAchievements()` logic into a dedicated asynchronous `ProfileDatabaseActor`, the application computes the entire visual array securely out of V8 memory bounds without lagging the SwiftUI main thread.

**Zero-OOM Off-Thread Bounds & Chronological Heuristics**: Instead of polluting the `Achievements` renders with synchronous O(N) database arrays natively, the system explicitly pushes `calculateAchievements()` deeply inside an `@ModelActor ProfileDatabaseActor` extension mapped structurally inside the UI component file cleanly. Crucially, it executes a targeted `FetchDescriptor` explicitly forced into a `\LocalScanRecord.timestamp, order: .reverse` chronological array! This allows the pipeline to exclusively fetch taxonomy layers (`\.scientificName`, `\.taxonomyKingdom`), environmental bounds (`\.isPoisonous`, `\.isInvasive`), and offline temporal metadata (`\.gpsElevation`, `\.weatherTemperatureF`). By stepping through the dataset conceptually from newest to oldest, the algorithm organically captures absolute `lastInteractionDate` metadata organically by mapping the timestamp of the exact first iteration a unique biological entity was documented directly into the mathematical tracker! It aggregates bounds purely offline out of V8 memory bounds—specifically utilizing `Set<String>` arrays on `scientificName` to accurately derive unique biological diversity per category—and resolves an entire matrix of lightweight, primitive `Sendable` structs (`AchievementPayload`) to the UI successfully integrating exact chronological context cleanly powering the contextual "Smart sort" UI closures effortlessly natively! To permanently guarantee absolute Domain-Driven separation, these primitives natively live fundamentally disconnected from UI loops exclusively within `Features/Profile/Models/GamificationModels.swift`.

## Secure Telemetry Ecosystem

To guarantee a sub-1-second "Instant-On" camera boot experience, **both Apple TelemetryDeck and PostHog tracking SDKs explicitly initialize off the iOS Main Thread.** The `MerianApp` root strictly delegates their configurations to a `Task.detached(priority: .background)` block with a forced `500ms` sleep, allowing the primary UI render pass undisturbed access to the CPU frame buffer natively.

### `AppTelemetry` (Telemetrydeck SDK)

Monitors core system stability purely using completely PII-free Apple anonymous strings intelligently.

- Executes `.initialize(config)` explicitly binding the platform key.
- **Uninitialized State Protection**: To absolutely prevent the 500ms async `.initialize(config)` boot delay from causing a `fatalError` when early-cycle tracking (or Unit Test mocks lacking `XCODE_RUNNING_FOR_PREVIEWS`) prematurely invoke `.send()`, `AppTelemetry` utilizes an internal thread-safe `NSLock` bounds property (`isInitialized`). This shields all external tracking methods and naturally drops events safely until the SDK securely mounts natively.
- Custom Signals track physical camera bounds (`trackScan`) cleanly.
- Hardware orchestrator executes `.trackThermalThrottling(fpsLimit:)` natively recording extreme heat warnings cleanly providing data on Apple thermal management performance under the sun logically.

### `PostHogManager`

Maps frontend button interactions predictably measuring feature discovery completely anonymously.

- Uses `identify(...)` seamlessly linking Supabase Anonymous UUID strings mirroring RevenueCat limits cleanly.
- Executes `reset()` immediately when `SupabaseManager.shared.signOut()` cleans the state completely erasing session metrics aggressively on demand.
