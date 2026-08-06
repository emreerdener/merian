# Gamification and Privacy-Bounded Telemetry

Naturebook gamifies exploration while keeping telemetry payloads behind a
narrow, allowlisted privacy boundary. “Zero PII” in older telemetry notes means
that event properties and logs must not contain direct personal or free-form
content; it is not a claim that the product processes no user data. Consented
PostHog sessions use a pseudonymous Supabase account identifier and are declared
as linked analytics in the app privacy manifest.

## Gamification Architecture (`GamificationManager`)

Tracks device-local discovery milestones and achievement notification state.

- Logs species discoveries into `$unlockedSpeciesCount`, persistently updating
  `.set(unlocked, forKey:)`.
- Evaluates local biological insertions by intercepting `LocalScanRecord`
  writes; if a species has never been cached locally, routes an
  `isNewDiscovery = true` payload for local stats, persona, firefly progress,
  and achievement recalculation.
- **Local vs. global discovery split**: `isNewDiscovery` means "new to this
  user" and is intentionally not the user-facing celebration signal.
  `is_new_to_merian_dictionary` comes from the identify Edge payload when a
  biological scan adds a species that was not already in Naturebook's shared
  `species_dictionary`. Non-biological results, including processed-material
  demotions such as wool rugs or leather goods, cannot set this flag.
- Drives the shared `MilestoneToastPresenter` for in-app milestone UX.
  `ScanMilestoneCoordinator` waits for the scan's Field trip progress attempt,
  asks `GamificationManager.evaluateAchievementsForNotifications` for newly
  eligible awards without presenting them early, evaluates
  `SpeciesData.isNewToMerianDictionary`, and batches standard outing progress,
  visible Seasonal Challenge progress, achievements, then `New to Naturebook`.
  `FieldTripEventsAvailability` removes challenge progress before caching,
  routing, refresh publication, or presentation when Events are staged off. Both
  foreground and background scan completion use this boundary and deduplicate
  by final scan ID. The old local `CelebrationBanner` confetti overlay has been
  removed. A scan may enqueue progress for several eligible experiences, with
  at most one credited goal in each. The persistent Insight contribution card
  reloads from server-backed completion rows and does not enqueue another
  milestone, haptic, or celebration.
- Triggers `HapticManager.shared.triggerSelectionPulse()` when an achievement
  (`hasFireflyBadge`) activates after 5 taxonomic finds.
- The profile `Terrarium` presents bundled asset-catalog artwork selected by
  `UserPersona` for the user's current unique-species count.
- **Erasure mechanics**: PostgreSQL stores one private
  `internal.user_species_scan_counts` row per user/species pair, including a
  positive count of matching scans. Statement-level transition-table triggers
  aggregate bulk changes. Permanently deleting the final matching scan removes
  that ledger row and decrements `users.total_species_discovered`; deleting one
  of several duplicates changes only `scan_count`. Owner transfers debit the
  previous user and credit the new user in the same transaction. Locally,
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

Merian uses PostHog as its optional product analytics system with an explicit,
account-wide permission boundary:

> [!WARNING]
> The architecture below is the required release invariant. The current
> source closes the reset-time transport leak and crash-safe ghost evidence
> migration tracked as `CONSENT-001` and `CONSENT-002`, plus the final
> synchronization identity fence, target-account restoration, Realtime, and
> OAuth account-replacement findings tracked as `CONSENT-004` through
> `CONSENT-007`, plus the verified local-ledger and withdrawal-journal boundary
> tracked as `CONSENT-010` and the causal cross-device ordering boundary tracked
> as `CONSENT-011`. All findings through `CONSENT-011` are closed in source.
> Internal test builds may continue. Public production remains blocked by
> same-SHA hosted iOS/Supabase validation and the external controls in the
> [consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

- **iOS app analytics (`AppTelemetry`)** — pseudonymous product metrics routed
  to PostHog only after permission, with preserved event names and
  `event_source = "ios_client"`.
- **PostHog identity (`PostHogManager`)** — user-identified session and
  lifecycle tracking linked only to the Supabase UUID. Edge capture does not
  send auth email or name.

### Privacy Manifest Classification

The main app manifest declares analytics-related coarse location, user ID, and
product interaction for both their applicable product purposes and Analytics;
other usage, performance, and diagnostic data are declared for Analytics. All
are conservatively linked to the user or device, none is declared for tracking,
and optional collection remains off until the current account grants it.

The declaration describes potential collection and does not open the PostHog
transport or replace consent. Any new event or property must be evaluated both
against the allowlist below and the
[iOS App Privacy Manifest Contract](../development-guides/16-ios-privacy-manifest.md).
If it changes an Apple data type, purpose, linking, tracking, recipient, or
public-policy fact, update all affected artifacts before merge.

### Initialization

`AppTelemetry.initialize()` prepares only the first-party facade during app
startup; it does not configure PostHog. `ConsentManager` resolves the active
account's highest accepted `consent_revision` in
`user_analytics_consent_events` and is the sole SDK
lifecycle authority. Only a current grant configures and identifies PostHog.
Absence, revocation, account change, or unresolved account state must disable
the facade, clear identity, opt out, and close the SDK without starting a new
PostHog request. A restored or changed authenticated session enters a distinct
remote-authority wait state before cached consent can reach the SDK. It resolves
to enabled only after the current account's authoritative grant is written to
the local ledger successfully; a missing grant, revocation, fetch failure, or
write failure remains disabled. Repeated same-account auth notifications retain
an already resolved state instead of needlessly cycling PostHog. The
source-complete lifecycle implementation and remaining hosted verification are
recorded in the readiness record. An account sync may apply a grant only after
its final merge rechecks cancellation, observed user, the Supabase SDK session,
and synchronization generation inside the mutation boundary.

Withdrawal also closes the in-process gate before storage, writes the exact
revocation to an independent Keychain journal, and only then atomically replaces
the append-only ledger. A failed primary write therefore remains off across
restart and replays the original event; the versioned journal retains distinct
pending actions for multiple accounts.

### `AppTelemetry` (PostHog Facade)

Thin enum wrapper around app product events. All sends go through a private
`send(_:with:)` helper that checks `isInitialized`, adds
`event_source = "ios_client"`, and captures through `PostHogManager`. The
`isInitialized` flag is protected by `NSLock` for thread safety and stays false
without account permission.

**Signal inventory:**

| Signal                           | Method                                                     | Payload                                                                                     | Trigger                                                                                          |
| -------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `ClientScanCompleted`            | `trackScan(isPro:isSubscribed:inferenceTier:)`             | `tier: "Pro"/"Free"`, server plan (`pro_paid`/`pro_complimentary`/historical `pro_trial`/`free`), `inferenceTier: "pro"/"flash"` | Successful client-side parse/save after inference                                                |
| `NewSpeciesDiscovered`           | `trackNewDiscovery(isPro:)`                                | `tier: "Pro"/"Free"`                                                                        | `NewDiscoveryCelebrationView.onAppear` (guarded by `hasFiredDiscoveryEvent` to prevent re-fires) |
| `PaywallViewed`                  | `trackPaywallImpression()`                                 | —                                                                                           | Camera shutter, gallery picker, or pending Photos import hits the free scan cap                   |
| `CaptureThermalThrottled`        | `trackThermalThrottling(fpsLimit:)`                        | `targetFPS: "15"`                                                                           | Capture throttles frame rate after device thermal state reaches critical                         |
| `ScanQueuedForSync`              | `trackOfflineQueued()`                                     | —                                                                                           | Scan successfully written to offline queue after `context.save()`                                |
| `ExternalImageImport`            | `trackExternalImageImport(outcome:)`                       | `outcome`, `event_source`                                                                   | Photos document import is received, staged, temporarily blocked, or terminally rejected           |
| `CaptureGoalIndicator`           | `trackCaptureGoalIndicator(action:source:)`                | `action: "shown"/"opened"/"next"/"previous"`, `source: "field_trip"`                  | Active capture goal is presented, opened, or changed                                              |
| `OnboardingCompleted`            | `trackOnboardingCompleted()`                               | —                                                                                           | User taps **Start scanning** on `.ready`; emitted only when optional analytics is enabled         |
| `SpeciesDictionaryOpened`        | `trackSpeciesDictionaryOpened(entryPoint:)`                | `entryPoint`                                                                                | Species dictionary sheet opens                                                                   |
| `SpeciesDictionaryPageLoaded`    | `trackSpeciesDictionaryLoaded(entryPoint:contentQuality:)` | `entryPoint`, `contentQuality: "complete"/"sparse"/"needs_enrichment"`                      | Species dictionary page loads a public dictionary row                                            |
| `SpeciesDictionaryNotFound`      | `trackSpeciesDictionaryNotFound(entryPoint:)`              | `entryPoint`                                                                                | Species dictionary lookup returns no public row                                                  |
| `SpeciesDictionaryRetry`         | `trackSpeciesDictionaryRetry(entryPoint:)`                 | `entryPoint`                                                                                | User taps retry from a dictionary error/not-found state                                          |
| `SpeciesDictionaryReferenceImageFallback` | `trackSpeciesDictionaryImageFallback(entryPoint:source:)`  | `entryPoint`, `source: "wikipedia"/"gbif"`                                                  | Species dictionary reference image fails to load and falls back to placeholder UI                |
| `APIDecodingFailure`             | `trackError("APIDecodingFailure")`                         | `domain: "APIDecodingFailure"`                                                              | Gemini response fails schema decoding                                                            |
| `InferenceNetworkFailure`        | `trackError("InferenceNetworkFailure")`                    | `domain: "InferenceNetworkFailure"`                                                         | Network error on live inference (non-cancellation path)                                          |
| `ClientErrorCaptured`            | `trackError(_:)`                                           | `domain: <errorDomain>`                                                                     | Available for future client error domains                                                        |
| `StartupStoreRecovery`           | `trackStartupStoreRecovery(outcome:reason:)`               | See startup recovery telemetry below                                                       | App startup enters local store recovery, legacy rescue, safe mode, or startup-blocked fallback    |

Species dictionary telemetry must remain free of direct personal and free-form
content. `entryPoint` may be
`insight_similar_species`, `explore_detail_similar_species`, `search`,
`deep_link`, `web`, or `unknown`; events must not attach species names, species
IDs, scan IDs, Explore post IDs, user locations, field notes, comments, image
URLs, or user review state.

Startup recovery telemetry follows the same privacy boundary. `outcome` and
`reason` are coarse enums, while diagnostic properties are redacted strings used
to distinguish corruption quarantine, legacy-store rescue, safe mode, and
startup-blocked outcomes. Do not attach exception text, local file paths, user
IDs, scan IDs, account state, recovery manifest contents, or raw store metadata.
Allowed diagnostic keys are `diagnostic_schema`, `selected_strategy`,
`current_schema_major`, `stored_schema_major`, `attempt_count`, `attempts`,
`final_outcome`, `final_reason`, `quarantine_attempted`,
`quarantine_performed`, `rescue_attempted`, and `rescue_performed`.

External image-import telemetry is intentionally receipt-level and coarse.
Allowed outcomes describe received, staged, quota-blocked,
staging-capacity-blocked, unsupported, missing-file, inbox-copy, or preparation
failure states. Never attach filenames, paths, image bytes, `UTType` strings,
EXIF dictionaries, coordinates, capture dates, Photos asset identifiers, scan
IDs, or user IDs.

Capture-goal telemetry measures the usefulness of the source-agnostic Scan
indicator without identifying its content. Its only feature properties are the
coarse action and goal source kind. Never attach target prompts, goal IDs,
source instance IDs/titles, completion counts, route identifiers, or account
identifiers.

### Pro Paywall Feature Copy

The Pro paywall comparison table is backed by
`ProPlanValueProps.comparisons` in `PaywallView.swift`. Keep docs, release
notes, and Profile plan-card summaries aligned with that source. Current
high-level Pro benefits are high-volume field scans, Gemini Pro model access,
video scans, AI chat, multi-capture, Apple Watch logging, group-event hosting,
and expedition mode.

### `PostHogManager` & Edge Telemetry

Tracks session lifecycle, feature interactions, and backend AI token usage.

**iOS Client (`PostHogManager`)**:

- Not `@MainActor` — thread-safe wrapper around `PostHogSDK.shared`.
- Rejects configuration, identity, and capture before permission. The required
  withdrawal/direct-wrapper account-change path closes a per-SDK-session
  transport gate before preserving `reset → optOut → close`; delayed requests
  from an old transport remain blocked after a new grant opens. This closes
  `CONSENT-001`. The outer OAuth boundary also closes analytics and consent
  Realtime before a true account replacement, reconciles the actual SDK session
  on success or failure, and generation-fences overlapping logins; this closes
  `CONSENT-007` in source.
- Tracks an `isConfigured` flag set after `setup()` completes. `identifyUser()`
  guards on this flag and buffers the latest user ID if a future call races
  configuration.
- `captureApplicationLifecycleEvents = true` for automatic foreground/background
  tracking after permission. Replay, screen views, element interactions,
  surveys, swizzling, and push-notification capture are explicitly disabled.
  `captureScreenViews` and `captureElementInteractions` are disabled —
  the former causes iOS 18 layout constraint warnings by inserting
  `UIKitToolbar` into SwiftUI `UIHostingController` hierarchies.
- Uses `identify(userId:)` to link the Supabase Auth UUID alongside RevenueCat's
  App User ID. RevenueCat receives matching subscriber attributes for
  support-friendly customer lookup.
- Employs `#if targetEnvironment(simulator)` to alias all development sessions
  as a static `"simulator"` identifier, aggressively decoupling test telemetry
  from live production metrics.
- `reset()` routes sign-out through the same transport-blocked withdrawal
  sequence. True-account OAuth replacement suppresses capture and closes
  consent Realtime before installing another session, then reconciles the
  SDK's actual account on success or failure. An older overlapping transition
  cannot reopen capture.

**Edge Functions (`_shared/posthog.ts`)**:

- Uses the standard PostHog HTTP `/capture/` API to dispatch `ScanCompleted`,
  `EnrichmentCompleted`, `EncyclopedicLLMCompleted`, `DiagnosticLLMCompleted`,
  and `GroupTagsLLMCompleted` events from the Supabase backend only after a
  current account grant. Every call first checks the greatest server-issued
  PostHog `consent_revision` and performs no PostHog request on absence,
  revocation, or lookup failure. Upload receipt time and device time never
  determine authority.
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
  plus `effective_tier`, `plan`, `subscription_tier`, `trial_active`, and
  `entitlement_version` from the atomic quota reservation:
  - paid Pro: `effective_tier = "pro"`, `plan = "pro_paid"`,
    `subscription_tier = "pro"`, `trial_active = false`; this includes active
    standard Pro subscriptions and active paid 7-day passes
  - complimentary Pro: `effective_tier = "pro"`,
    `plan = "pro_complimentary"`, `subscription_tier = "free"`,
    `trial_active = false`; balance, in-flight holds, settlement reason, Flash
    fallback, and exhaustion are server-owned telemetry dimensions
  - historical trial Pro rows remain queryable as `plan = "pro_trial"` and
    `trial_active = true`, but no post-cutover resolver emits new rows
  - free: `effective_tier = "free"`, `plan = "free"`,
    `subscription_tier = "free"`, `trial_active = false`; an expired timed pass
    first loses paid precedence, then resolves here only if no complimentary
    credit or hold remains before the expiry worker clears the stored tier
- Missing user rows or entitlement query failures emit no scan-completion tier
  event because provider work fails closed.
- Cost dashboards should prefer `llm_model` and `effective_tier` for model
  spend, and use `plan` to distinguish paid Pro, complimentary Pro, and
  historical trial Pro. The raw
  `subscription_tier` remains useful for debugging RevenueCat webhook state but
  is not sufficient to classify complimentary model usage.
- Safely runs inside Deno's async background tasks (using `.waitUntil` /
  promises) to never block the inference response to the client.
