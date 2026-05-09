# Profile and Gamification

This document covers the Profile tab architecture, how scan statistics are computed, the `AchievementsCalculator` award system, and how to add new award criteria.

---

## Architecture

| File | Role |
|---|---|
| `ProfileTabView` | Root profile tab view |
| `SettingsTabView` | Settings sub-tab |
| `ProfileViewModel` | `@Observable @MainActor` — cloud preferences (geoprivacy), auth state, sign-in/out |
| `ProfileDatabaseActor` | `@ModelActor` — builds compact SwiftData projections, computes profile stats, heatmap, and awards off-main |
| `AchievementsCalculator` | Pure `struct` with `static func calculate(from:) -> [AwardPayload]` |
| `GamificationManager` | `@MainActor @Observable` singleton — in-memory award cache, notification triggers |
| `GamificationModels` | `AwardPayload`, `AwardState`, and `UserPersona` enumerations |
| `Achievements` component | SwiftUI view rendering the award grid with sort options |
| `UserStats` component | Renders species count and current streak from `LocalScanRecord` |
| `Persona` component | Renders the user's active `UserPersona` tier badge and title |
| `Terrarium` component | Biological 3D hex-grid mapping representation based on the user's active progression tier |
| `PlanCard` component | Dynamic subscription banner reading `isProActive` to serve custom `.xcassets` graphics (`sparkles` vs `compass`) |
| `ScansHeatmap` | Calendar heatmap of scan activity (52-week rolling window) anchored to analysis upload date, bypassing EXIF `captureDate` |

---

## Personas and Terrarium

The `UserPersona` enumeration (defined in `GamificationModels.swift`) replaces legacy arbitrary ranking scales with a strict, 5-tier biological taxonomy path derived mathematically from the user's `uniqueSpeciesCount` (NOT total scans):

| Tier Level | Persona Title | Unique Species Threshold | Asset Identifier |
|---|---|---|---|
| Tier 1 | Observer | 0 | `persona_observer` |
| Tier 2 | Casual Explorer | 10 | `persona_explorer` |
| Tier 3 | Dedicated Naturalist | 50 | `persona_naturalist` |
| Tier 4 | Verified Scholar | 250 | `persona_scholar` |
| Tier 5 | Apex Observer | 1000 | `persona_apex` |

The `Persona` UI component cross-references this enum against the user's live profile statistics to render the appropriate `.imageset` container from the `Profile/Personas/` catalog. It sits adjacent to the `Terrarium` component on the Profile Tab, which loads compounding biological elements based on the same 5-tier logic. 

**Plan Card Integration**: The `PlanCard` dynamic banner also eschews standard SF Symbols in favor of custom vectors. Depending on `RevenueCatManager.shared.isProActive`, it targets `merian/Assets.xcassets/Profile/Plan/sparkles.imageset` for Premium users, falling back to `compass.imageset` for Free-tier users.

---

## ProfileViewModel Responsibility Boundary

`ProfileViewModel` handles **only** cloud-network operations:
- `fetchGeoprivacy()` — reads `default_geoprivacy` from the Supabase `users` table
- `signInWithApple()`, `signInWithGoogle()`, `signOut()` — delegates to `SupabaseManager`
- Auth state computed properties (`isGuestUser`, `userName`, `userEmail`, `userAvatarURL`)

Heavy data operations (fetching all scan records for stats, computing awards) are **firewalled** out of `ProfileViewModel` and into `ProfileDatabaseActor` to avoid locking the `@MainActor`.

---

## Stats Pipeline

```
LocalScanRecord[] (SwiftData)
    → ProfileDatabaseActor.loadStatsProjection()
        → cached ProfileStatsProjection
        → calculateProfileStats()       → (speciesCount: Int, streak: Int)
        → calculateHeatmapData()        → ProfileHeatmapData
        → calculateAwardsProjection()
        → AchievementsCalculator.calculate(from:)
            → [AwardPayload]
    → GamificationManager.evaluateAchievementsForNotifications(awards:)
```

`ProfileDatabaseActor` is instantiated in `ProfileTabView.body` inside a `.task` modifier. `calculateAll()` is the primary profile render entry point: it loads one `ProfileStatsProjection`, derives species count, streak, heatmap, and awards from that projection, then dispatches the flat `Sendable` result back to `@MainActor` in a single `MainActor.run` block.

`ProfileDatabaseActor.calculateAwards()` is also called by `InferenceEngine` after **every** successful inference — not just new discoveries. This is intentional: awards can trigger on conditions unrelated to species novelty (time-of-day, elevation, temperature, IUCN status, etc.).

All `ProfileDatabaseActor` fetches use `propertiesToFetch` projections to minimise the SQLite column surface loaded into memory, preventing JetSam pressure on accounts with large scan histories. The stats projection cache stores only scalar `Sendable` structs, timestamps, and precomputed counts — never live `LocalScanRecord` model objects. Cache reuse is fingerprinted by scan count, latest scan ID, and latest timestamp; call `invalidateCachedProfileProjections()` before reusing a long-lived actor after in-place scan edits.

---

## AchievementsCalculator

`AchievementsCalculator.calculate(from:) -> [AwardPayload]` is a pure, synchronous function with no side effects. It accepts any `AchievementRecordRepresentable`, so profile rendering can pass lightweight projection structs instead of full SwiftData models. It iterates all records once, maintaining running canonical-species accumulators per award criterion:

| Award title | Type key | Criterion | Target |
|---|---|---|---|
| The Observer | `first_scan` | Any scan exists | 1 |
| The Naturalist | `explorer` | Unique species count | 5 |
| The Botanist | `plantae` | Unique Plantae kingdom species | 10 |
| The Zoologist | `insecta` | Unique Insecta or Arachnida class species | 10 |
| The Mycologist | `fungi` | Unique Fungi kingdom species | 10 |
| The Urban Ecologist | `urban` | Unique urban/domesticated ecology scans | 10 |
| The Frost Walker | `frost_walker` | Unique scans at temp < 32°F | 5 |
| The Alpine Naturalist | `alpine` | Unique scans at elevation > 2500m | 5 |
| The Nocturnal Observer | `nocturnal` | Unique scans between hour 22–05 (inclusive) | 10 |
| The Guardian | `guardian` | Unique invasive species scans | 5 |
| The Conservationist | `conservationist` | Any IUCN status that is not LC, NE, or DD | 1 |
| The Toxicologist | `toxicologist` | Unique poisonous species scans | 5 |
| The Perfect Lens | `perfect_lens` | Unique scans with confidence ≥ 0.98 | 25 |

All species-based criteria de-duplicate by canonical species key (`confirmedSpeciesId`, then `speciesId`, then display scientific name) — scanning the same species 10 times counts as 1 toward a species-based award.

The first-scan achievement is resolved by finding the oldest timestamp in the projection, with scan ID as a deterministic tie-breaker. Each accumulator also tracks a `lastInteractionDate` as the most recent qualifying contribution. Note that `timestamp` strictly represents the system upload and processing time, completely decoupled from the original image's EXIF `captureDate`. This ensures that historical backfills from users' photo libraries do not retroactively trigger streaks or skew gamification timing mechanics.

---

## Adding a New Award

1. Add a new `AchievementType` case and definition in `GamificationModels.swift`.
2. Choose a contribution kind (`firstScan` or `uniqueSpecies`) and provide the qualifying closure.
3. Ensure any new fields required by the closure are included in `ProfileAnalyticsProjection.propertiesToFetch`.
4. Add the award's visual representation to the `Achievements` SwiftUI component (and optionally an `AwardCard` difficulty mapping in `GamificationModels`).
5. `ProfileDatabaseActor.calculateAwards()` and `GamificationManager.evaluateAchievementsForNotifications` require no changes — they consume the `[AwardPayload]` array dynamically.

**Do not gate** `calculateAwards()` on `isNewDiscovery`. The full recalculation must run after every scan because award criteria are independent of novelty.

---

## GamificationManager

`GamificationManager.shared` is an `@MainActor @Observable` singleton that persists lightweight gamification state in `UserDefaults`:

- `unlockedSpeciesCount` — incremented each time `recordNewSpeciesDiscovered()` is called
- `hasFireflyBadge` — unlocked when `unlockedSpeciesCount >= 5`
- `unlockedAchievements: Set<String>` — type keys of all completed awards

`recordNewSpeciesDiscovered()` is called by `InferenceEngine` when `isNewDiscovery == true`. It increments `unlockedSpeciesCount`, persists it, and checks the firefly badge threshold.

`evaluateAchievementsForNotifications(awards:)` is called after `calculateAwards()` completes. It iterates `[AwardPayload]`, checks if any award's type is newly absent from `unlockedAchievements` but now `isCompleted`, adds it to the set, persists the set, and queues a local push notification via `PushNotificationManager.shared.sendAchievementUnlockedNotification` if the `isAchievementNotificationsEnabled` `UserDefaults` flag is set.

---

## AwardPayload

`AwardPayload` is a `Sendable` value type defined in `GamificationModels.swift`:

```swift
public struct AwardPayload: Sendable, Identifiable {
    public let id = UUID()
    public let title: String
    public let type: String
    public let currentCount: Int
    public let targetCount: Int
    public let lastInteractionDate: Date?
}
```

Extension properties:
- `isCompleted: Bool` — `currentCount >= targetCount`
- `progressFraction: Double` — clamped `currentCount / targetCount`
- `difficultyLevel: Int` — 0 (Easy), 1 (Medium), 2 (Hard), derived from the `type` key
- `difficultyString: String` — human-readable label

The `Achievements` component sorts awards using a `smartSort` heuristic: recently completed (within 7 days) float to the top, in-progress awards ranked by proximity to completion follow, legacy completions and empty awards sink to the bottom. Additional sort options are available via a menu: completed first, incomplete first, easiest first, hardest first.

---

## ExportScans (DWC-A)

`ExportScans` (Settings) calls `MerianNetworkClient.shared.requestDwcAExport()`, which hits the `/request-export-dwca` Edge function with a 15-second timeout. This enqueues an asynchronous export job server-side rather than blocking on the CPU-intensive archive generation. The user receives a notification or email when the export is ready. See `docs/backend-and-data/05-api-contracts.md` for the full endpoint contract.

## 2026-04 Hardening Updates

- Profile analytics now share a single projection-style fetch for streaks, heatmap construction, and achievement calculation instead of repeatedly scanning the full library through separate fetch paths.
- Achievement calculation is now projection-friendly via `AchievementRecordRepresentable`, so awards can be computed from lightweight analytics payloads without materializing full model objects.
- Offline scan timestamp preservation now directly protects gamification correctness: streaks, monthly heatmaps, and species chronology are computed from the original capture date rather than delayed sync time.
