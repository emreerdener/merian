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

## Track B: The Awards & Milestones

To diversify gamification away from pure numerical counts, the Awards track unlocks specific progression milestones based on authentic scientific taxonomy, extreme environmental conditions, and citizen science impact:
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

**Zero-OOM Off-Thread Bounds**: Instead of polluting the `AwardsAndMilestones` renders with synchronous O(N) database arrays natively, the system explicitly pushes `calculateAwards()` deeply inside an `@ModelActor ProfileDatabaseActor` extension mapped structurally inside the UI component file cleanly. It executes a targeted `FetchDescriptor` exclusively fetching taxonomy layers (`\.scientificName`, `\.taxonomyKingdom`), environmental bounds (`\.isPoisonous`, `\.isInvasive`), and offline temporal metadata (`\.gpsElevation`, `\.weatherTemperatureF`). It aggregates bounds purely offline out of V8 memory bounds—specifically utilizing `Set<String>` arrays on `scientificName` to accurately derive unique biological diversity per category—and resolves an entire matrix of lightweight, primitive `Sendable` structs (`AwardPayload`) to the UI successfully. To permanently guarantee absolute Domain-Driven separation, these primitives natively live fundamentally disconnected from UI loops exclusively within `Features/Profile/Models/GamificationModels.swift`.

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
