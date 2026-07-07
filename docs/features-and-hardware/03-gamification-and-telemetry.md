# Gamification and Zero-PII Telemetry

Merian gamifies exploration while respecting user privacy through analytics
environments decoupled from Apple ecosystem identifiers.

## Gamification Architecture (`GamificationManager`)

Powers the interactive `.riv` Rive model rendered by `Terrarium`.

- Logs species discoveries into `$unlockedSpeciesCount`, persistently updating
  `.set(unlocked, forKey:)`.
- Evaluates local biological insertions by intercepting `LocalScanRecord`
  writes; if a species has never been cached locally, routes an
  `isNewDiscovery = true` payload for local stats, persona, firefly progress,
  and achievement recalculation.
- **Local vs. global discovery split**: `isNewDiscovery` means "new to this
  user" and is intentionally not the user-facing celebration signal.
  `is_new_to_merian_dictionary` comes from the identify Edge payload when a
  biological scan adds a species that was not already in Merian's shared
  `species_dictionary`. Non-biological results, including processed-material
  demotions such as wool rugs or leather goods, cannot set this flag.
- Drives the shared `MilestoneToastPresenter` for in-app milestone UX.
  Achievement unlocks enter from
  `GamificationManager.evaluateAchievementsForNotifications(awards:)`.
  `New to Merian` dictionary milestones enter from
  `InsightSheetViewModel.evaluateVoiceOverAndCelebration` only when
  `SpeciesData.isNewToMerianDictionary == true` for a valid biological subject.
  The old local `CelebrationBanner` confetti overlay has been removed.
- Triggers `HapticManager.shared.triggerSelectionPulse()` when an achievement
  (`hasFireflyBadge`) activates after 5 taxonomic finds.
- Consumed via `AppDIContainer.shared.gamificationManager` inside
  `GamificationManager`-aware views (e.g., `Terrarium`), which calls
  `.setInput("TotalSpeciesCount")` to animate 3D model foliage, fireflies, and
  natural artifacts using `RiveViewModel` states.
- **Erasure Mechanics (`decrement_user_species_count`)**: When a user
  permanently deletes a scan that was their last documented capture of a
  specific biological species, a PostgreSQL PL/pgSQL database trigger intercepts
  the deletion and decrements their `users.total_species_discovered` counter,
  keeping gamification counts accurate regardless of offline delay. Locally,
  SwiftData recalculates the Scans library and syncs UI state.

## Track B: Achievements

To diversify gamification beyond pure numerical counts, the Achievements track
unlocks progression milestones based on scientific taxonomy, environmental
conditions, and citizen science impact:

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
  - **The Perfect Lens**: Capturing imagery with a `0.98+` Vision Confidence
    Score.
  - **The Feline Friend**: First domestic cat scan, including accepted
    scientific-name aliases.
  - **The Canine Companion**: First domestic dog scan, including accepted
    scientific-name aliases.

### Why Achievements are NOT Tracked in the Database

Achievement states (like `isCompleted` or progress counts) are not stored in the
database — neither locally in SwiftData via a dedicated model, nor remotely in
PostgreSQL. The reasons for this architecture are:

1. **Calculable State vs. Stored State**: Achievements reflect the user's data,
   not new data in their own right. Every achievement metric can be derived
   mathematically from the existing `LocalScanRecord` repository. Storing
   achievement progress creates redundant, overlapping state that risks falling
   out of sync with the true biological scans table.
2. **Synchronization & Erasure Hazards**: If achievements were stored as
   dedicated rows, permanently deleting a photo or purging non-biological scans
   would require cascading update chains or remote PostgreSQL trigger
   synchronizations to decrement or revoke achievement state. This introduces
   fragile network constraints and logic bugs.
3. **Absolute Source of Truth**: By making raw scans the source of truth, the
   system self-heals. Restoring a user's data from the cloud onto a blank iOS
   device naturally recreates their exact achievement states through local
   processing, without a secondary "sync achievements" API call.
4. **Performance**: UI blockers previously came from synchronously looping
   arrays. By isolating the `calculateAchievements()` logic into a dedicated
   asynchronous `ProfileDatabaseActor`, the application computes the full award
   array off the main thread without lagging the SwiftUI render loop.

**Off-Thread Calculation & Chronological Heuristics**: `calculateAchievements()`
runs inside a `@ModelActor ProfileDatabaseActor` extension. It executes a
targeted `FetchDescriptor` sorted by `\LocalScanRecord.timestamp` in reverse
chronological order. This allows the pipeline to fetch only the taxonomy layers
(`\.scientificName`, `\.taxonomyKingdom`), environmental fields
(`\.isPoisonous`, `\.isInvasive`), and temporal metadata (`\.gpsElevation`,
`\.weatherTemperatureF`) needed for the calculation. Iterating newest-to-oldest,
the algorithm captures `lastInteractionDate` metadata by recording the timestamp
of the first iteration a unique biological entity appears. It aggregates results
using `Set<String>` on `scientificName` to derive unique biological diversity
per category, and resolves a matrix of lightweight `Sendable` structs
(`AchievementPayload`) to the UI with exact chronological context for the "Smart
sort" closures. These primitives are defined in
`Features/Profile/UserProfile/Models/GamificationModels.swift`, isolated from UI loops.

## Secure Telemetry Ecosystem

Merian uses PostHog as its single product analytics system with a strict privacy
boundary:

- **iOS app analytics (`AppTelemetry`)** — PII-free product metrics routed to
  PostHog with preserved event names and `event_source = "ios_client"`.
- **PostHog identity (`PostHogManager`)** — user-identified session and
  lifecycle tracking, linked to the Supabase UUID and dynamically upgraded to
  include authenticated metadata (email and name) via backend `$set` properties.

### Initialization

`AppTelemetry.initialize()` is called synchronously in `MerianApp.init()` after
the dependency container has invoked `SupabaseManager.shared`, whose initializer
configures PostHog before auth listening begins.

`PostHogManager.configure()` remains idempotent, so both `SupabaseManager` and
`AppTelemetry` can safely call it without double setup. Restored-session
identity can be linked without the cold-start race where auth emits before
PostHog exists.

### `AppTelemetry` (PostHog Facade)

Thin enum wrapper around app product events. All sends go through a private
`send(_:with:)` helper that checks `isInitialized`, adds
`event_source = "ios_client"`, and captures through `PostHogManager`. The
`isInitialized` flag is protected by `NSLock` for thread safety.

**Signal inventory:**

| Signal                           | Method                                                     | Payload                                                                                     | Trigger                                                                                          |
| -------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `ClientScanCompleted`            | `trackScan(isPro:isSubscribed:inferenceTier:)`             | `tier: "Pro"/"Free"`, `plan: "pro_paid"/"pro_trial"/"free"`, `inferenceTier: "pro"/"flash"` | Successful client-side parse/save after inference                                                |
| `NewSpeciesDiscovered`           | `trackNewDiscovery(isPro:)`                                | `tier: "Pro"/"Free"`                                                                        | `NewDiscoveryCelebrationView.onAppear` (guarded by `hasFiredDiscoveryEvent` to prevent re-fires) |
| `PaywallViewed`                  | `trackPaywallImpression()`                                 | —                                                                                           | Camera shutter or gallery picker hits free scan cap                                              |
| `CaptureThermalThrottled`        | `trackThermalThrottling(fpsLimit:)`                        | `targetFPS: "15"`                                                                           | Capture throttles frame rate after device thermal state reaches critical                         |
| `ScanQueuedForSync`              | `trackOfflineQueued()`                                     | —                                                                                           | Scan successfully written to offline queue after `context.save()`                                |
| `OnboardingCompleted`            | `trackOnboardingCompleted()`                               | —                                                                                           | User taps Continue on the `.ready` onboarding step                                               |
| `SpeciesDictionaryOpened`        | `trackSpeciesDictionaryOpened(entryPoint:)`                | `entryPoint`                                                                                | Species dictionary sheet opens                                                                   |
| `SpeciesDictionaryPageLoaded`    | `trackSpeciesDictionaryLoaded(entryPoint:contentQuality:)` | `entryPoint`, `contentQuality: "complete"/"sparse"/"needs_enrichment"`                      | Species dictionary page loads a public dictionary row                                            |
| `SpeciesDictionaryNotFound`      | `trackSpeciesDictionaryNotFound(entryPoint:)`              | `entryPoint`                                                                                | Species dictionary lookup returns no public row                                                  |
| `SpeciesDictionaryRetry`         | `trackSpeciesDictionaryRetry(entryPoint:)`                 | `entryPoint`                                                                                | User taps retry from a dictionary error/not-found state                                          |
| `SpeciesDictionaryReferenceImageFallback` | `trackSpeciesDictionaryImageFallback(entryPoint:source:)`  | `entryPoint`, `source: "wikipedia"/"gbif"`                                                  | Species dictionary reference image fails to load and falls back to placeholder UI                |
| `APIDecodingFailure`             | `trackError("APIDecodingFailure")`                         | `domain: "APIDecodingFailure"`                                                              | Gemini response fails schema decoding                                                            |
| `InferenceNetworkFailure`        | `trackError("InferenceNetworkFailure")`                    | `domain: "InferenceNetworkFailure"`                                                         | Network error on live inference (non-cancellation path)                                          |
| `ClientErrorCaptured`            | `trackError(_:)`                                           | `domain: <errorDomain>`                                                                     | Available for future client error domains                                                        |
| `StartupStoreRecovery`           | `trackStartupStoreRecovery(outcome:reason:)`               | `outcome`, `reason`                                                                         | App startup enters local store recovery, safe mode, or startup-blocked fallback                   |

Species dictionary telemetry must remain zero-PII. `entryPoint` may be
`insight_similar_species`, `explore_detail_similar_species`, `search`,
`deep_link`, `web`, or `unknown`; events must not attach species names, species
IDs, scan IDs, Explore post IDs, user locations, field notes, comments, image
URLs, or user review state.

Startup recovery telemetry follows the same privacy boundary. `outcome` and
`reason` are coarse enums only; do not attach exception text, local file paths,
user IDs, scan IDs, account state, or quarantine manifest contents.

### Pro Paywall Feature Copy

The Pro paywall comparison table is backed by
`ProPlanValueProps.comparisons` in `PaywallView.swift`. Keep docs, release
notes, and Profile plan-card summaries aligned with that source. Current
high-level Pro benefits are unlimited field scans, Gemini Pro model access,
video scans, AI chat, multi-capture, Apple Watch logging, group-event hosting,
and expedition mode.

### `PostHogManager` & Edge Telemetry

Tracks session lifecycle, feature interactions, and backend AI token usage.

**iOS Client (`PostHogManager`)**:

- Not `@MainActor` — thread-safe wrapper around `PostHogSDK.shared`.
- Tracks an `isConfigured` flag set after `setup()` completes. `identifyUser()`
  guards on this flag and buffers the latest user ID if a future call races
  configuration.
- `captureApplicationLifecycleEvents = true` for automatic foreground/background
  tracking. `captureScreenViews` and `captureElementInteractions` are disabled —
  the former causes iOS 18 layout constraint warnings by inserting
  `UIKitToolbar` into SwiftUI `UIHostingController` hierarchies.
- Uses `identify(userId:)` to link the Supabase Anonymous UUID alongside
  RevenueCat identifiers.
- Employs `#if targetEnvironment(simulator)` to alias all development sessions
  as a static `"simulator"` identifier, aggressively decoupling test telemetry
  from live production metrics.
- Calls `reset()` when `SupabaseManager.shared.signOut()` clears session state.

**Edge Functions (`_shared/posthog.ts`)**:

- Uses the standard PostHog HTTP `/capture/` API to dispatch `ScanCompleted`,
  `EnrichmentCompleted`, `EncyclopedicLLMCompleted`, `DiagnosticLLMCompleted`,
  and `GroupTagsLLMCompleted` events directly from the Supabase backend.
- Scan completion events attach AI metrics including `llm_model`,
  `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens`, and where
  available `llm_thinking_tokens` / `llm_cached_tokens` to `user.id` to provide
  visibility into Flash vs Pro token usage across both primary vision routing
  and background classification tasks.
- Multimodal scan completion events also attach media-shape properties:
  `media_type` (`image`, `video`, `image_video`, or `none`), `media_kinds`,
  `has_image`, `has_video`, `image_count`, `video_clip_count`,
  `video_frame_count`, and `video_inference_frame_count`. For video-backed
  scans, `video_llm_prompt_tokens`, `video_llm_candidate_tokens`,
  `video_llm_thinking_tokens`, and `video_llm_total_tokens` mirror the full
  Gemini request usage under `video_token_accounting = "full_multimodal_request"`
  because Gemini does not split token usage by sampled frame versus text or
  still-image inputs.
- Plan telemetry is intentionally split from the raw database subscription
  value. Edge scan events include `tier` for backward-compatible dashboards,
  plus `effective_tier`, `plan`, `subscription_tier`, and `trial_active` from
  `_shared/tierCache.ts`:
  - paid Pro: `effective_tier = "pro"`, `plan = "pro_paid"`,
    `subscription_tier = "pro"`, `trial_active = false`; this includes active
    standard Pro subscriptions and active paid 7-day passes
  - trial Pro: `effective_tier = "pro"`, `plan = "pro_trial"`,
    `subscription_tier = "free"` or `null` for a first-scan ghost user,
    `trial_active = true`
  - free: `effective_tier = "free"`, `plan = "free"`,
    `subscription_tier = "free"`, `trial_active = false`; expired timed-pass
    rows also resolve here as a safety fallback before the expiry worker clears
    the stored tier
- Cost dashboards should prefer `llm_model` and `effective_tier` for model
  spend, and use `plan` to distinguish paid Pro from trial Pro. The raw
  `subscription_tier` remains useful for debugging RevenueCat webhook state but
  is not sufficient to classify free-trial model usage.
- Safely runs inside Deno's async background tasks (using `.waitUntil` /
  promises) to never block the inference response to the client.
