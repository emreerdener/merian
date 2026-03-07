# Gamification and Zero-PII Telemetry

Merian gamifies exploration natively while respecting user privacy intrinsically through decoupled analytics environments physically isolated from physical Apple bounds.

## Gamification Architecture (`GamificationManager`)

Powers the interactive `.riv` Rive model rendered by `TerrariumView`.

- Logs globally passing taxonomy boundaries into `$unlockedSpeciesCount`, persistently updating `.set(unlocked, forKey:)` natively.
- Executes Apple native hardware `HapticManager.shared.triggerSelectionPulse()` the second an achievement (`hasFireflyBadge`) natively triggers over 5 taxonomic finds natively.
- Injects natively via `.environmentObject` into `TerrariumView` passively reacting `.setInput("TotalSpeciesCount")` animating 3D model foliage, fireflies, and natural artifacts instantaneously using `RiveViewModel` states seamlessly.

## Secure Telemetry Ecosystem

### `AppTelemetry` (Telemetrydeck SDK)

Monitors core system stability purely using completely PII-free Apple anonymous strings intelligently.

- Executes `.initialize(config)` explicitly binding the platform key.
- Custom Signals track physical camera bounds (`trackScan`) cleanly.
- Hardware orchestrator executes `.trackThermalThrottling(fpsLimit:)` natively recording extreme heat warnings cleanly providing data on Apple thermal management performance under the sun logically.

### `PostHogManager`

Maps frontend button interactions predictably measuring feature discovery completely anonymously.

- Uses `identify(...)` seamlessly linking Supabase Anonymous UUID strings mirroring RevenueCat limits cleanly.
- Executes `reset()` immediately when `SupabaseManager.shared.signOut()` cleans the state completely erasing session metrics aggressively on demand.
