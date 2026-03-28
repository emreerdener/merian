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

Merian uses two analytics systems with a strict privacy boundary:

- **TelemetryDeck (`AppTelemetry`)** — anonymous, PII-free product metrics. No user identity is ever attached.
- **PostHog (`PostHogManager`)** — user-identified session and lifecycle tracking, linked to the Supabase UUID and dynamically upgraded to include authenticated metadata (email and name) via backend `$set` properties.

### Initialization

`AppTelemetry.initialize()` is called synchronously in `MerianApp.init()` — `TelemetryManager.initialize(with:)` is pure config storage with no I/O, safe on the main thread.

`PostHogManager.configure()` is dispatched via `Task.detached(priority: .background)`. `PostHogManager` is not `@MainActor`, so the work actually runs on the background thread pool rather than hopping back to the main actor. This keeps the primary UI render pass uncontested on launch.

### `AppTelemetry` (TelemetryDeck SDK)

Thin enum wrapper around `TelemetryManager`. All sends go through a private `send(_:with:)` helper that checks `isInitialized` and logs a warning (rather than silently no-oping) if called before `initialize()`. The `isInitialized` flag is protected by `NSLock` for thread safety.

**Signal inventory:**

| Signal | Method | Payload | Trigger |
|---|---|---|---|
| `ScanCompleted` | `trackScan(isPro:)` | `tier: "Pro"/"Free"` | Successful inference result |
| `NewSpeciesDiscovered` | `trackNewDiscovery(isPro:)` | `tier: "Pro"/"Free"` | `NewDiscoveryCelebrationView.onAppear` (guarded by `hasFiredDiscoveryEvent` to prevent re-fires) |
| `PaywallViewed` | `trackPaywallImpression()` | — | Camera shutter or gallery picker hits free scan cap |
| `ThermalThrottled` | `trackThermalThrottling(fpsLimit:)` | `targetFPS: "15"` | Device thermal state reaches critical |
| `OfflineQueuedScan` | `trackOfflineQueued()` | — | Scan successfully written to offline queue after `context.save()` |
| `OnboardingCompleted` | `trackOnboardingCompleted()` | — | User taps Continue on the `.ready` onboarding step |
| `APIDecodingFailure` | `trackError("APIDecodingFailure")` | `domain: "APIDecodingFailure"` | Gemini response fails schema decoding |
| `InferenceNetworkFailure` | `trackError("InferenceNetworkFailure")` | `domain: "InferenceNetworkFailure"` | Network error on live inference (non-cancellation path) |
| `SystemError` | `trackError(_:)` | `domain: <errorDomain>` | Available for future error domains |

### `PostHogManager` & Edge Telemetry

Tracks session lifecycle, feature interactions, and backend AI token usage, linked anonymously.

**iOS Client (`PostHogManager`)**:
- Not `@MainActor` — thread-safe wrapper around `PostHogSDK.shared`.
- Tracks an `isConfigured` flag set after `setup()` completes. `identifyUser()` guards on this flag and logs a warning if called before `configure()` finishes (race condition on fast auth restore at launch).
- `captureApplicationLifecycleEvents = true` for automatic foreground/background tracking. `captureScreenViews` and `captureElementInteractions` are disabled — the former causes iOS 18 layout constraint warnings by inserting `UIKitToolbar` into SwiftUI `UIHostingController` hierarchies.
- Uses `identify(userId:)` to link the Supabase Anonymous UUID alongside RevenueCat identifiers.
- Employs `#if targetEnvironment(simulator)` to alias all development sessions as a static `"simulator"` identifier, aggressively decoupling test telemetry from live production metrics.
- Calls `reset()` when `SupabaseManager.shared.signOut()` clears session state.

**Edge Functions (`_shared/posthog.ts`)**:
- Uses the standard PostHog HTTP `/capture/` API to dispatch `ScanCompleted` and `EnrichmentCompleted` events directly from the Supabase backend.
- Attaches AI metrics including `llm_prompt_tokens`, `llm_candidate_tokens`, and `llm_total_tokens` to `user.id`.
- Safely runs inside Deno's async background tasks (using `.waitUntil` / promises) to never block the inference response to the client.
