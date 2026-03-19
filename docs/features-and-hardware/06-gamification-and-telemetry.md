# Gamification and Zero-PII Telemetry

Merian gamifies exploration natively while respecting user privacy intrinsically through decoupled analytics environments physically isolated from physical Apple bounds.

## Gamification Architecture (`GamificationManager`)

Powers the interactive `.riv` Rive model rendered by `TerrariumView`.

- Logs globally passing taxonomy boundaries into `$unlockedSpeciesCount`, persistently updating `.set(unlocked, forKey:)` natively.
- Evaluates novel biological insertions natively intercepting `LocalScanRecord` writes; if a species has never been cached locally, routes a strict `isNewDiscovery = true` payload mapping directly to `InsightSheetView`.
- **Targeted Non-Biological Suppression**: Even if `isNewDiscovery = true` is passed downstream natively, the UI layer strictly filters out dead strings (e.g., `not applicable`, `unknown subject`, `inanimate object`) and unconditionally requires `isBiological == true`. This rigidly prevents the app from cheering the user for scanning gravel, car tires, or blurry floors.
- Instantiates `NewDiscoveryCelebrationView.swift` (when biologically validated), enforcing a premium, glassmorphic floating pill-shaped "Toast" notification docked at the top of the interface. It scales natively and tears down automatically via a state-retained `Task.sleep` without blocking user touches (it also supports manual swipe/tap-to-dismiss via `DragGesture`). Generates `HapticManager.shared.triggerSuccessPulse()` callbacks and tracks Apple-native `TelemetryManager.send("NewSpeciesDiscovered")` strictly observing Zero-PII offline rules.
- Executes Apple native hardware `HapticManager.shared.triggerSelectionPulse()` the second an achievement (`hasFireflyBadge`) natively triggers over 5 taxonomic finds natively.
- Injects natively via `.environmentObject` into `TerrariumView` passively reacting `.setInput("TotalSpeciesCount")` animating 3D model foliage, fireflies, and natural artifacts instantaneously using `RiveViewModel` states seamlessly.
- **Erasure Mechanics (`decrement_user_species_count`)**: If a user permanently deletes a scan, and that specific scan happens to be their absolute final documented capture of a specific biological species, a strict PostgreSQL PL/pgSQL database trigger will silently intercept the erasure. It will perfectly decrement their unified `users.total_species_discovered` counter seamlessly maintaining accurate gamification counts regardless of offline delay. Locally, the SwiftData boundary instantly recalculates their Scans library natively seamlessly syncing UI states exactly.

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
