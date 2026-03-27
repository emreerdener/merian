# Profile and Gamification

This document covers the Profile tab architecture, how scan statistics are computed, the `AchievementsCalculator` award system, and how to add new award criteria.

---

## Architecture

| File | Role |
|---|---|
| `ProfileTabView` | Root profile tab view |
| `SettingsTabView` | Settings sub-tab |
| `ProfileViewModel` | `@Observable @MainActor` — cloud preferences (geoprivacy), auth state, sign-in/out |
| `ProfileDatabaseActor` | `@ModelActor` — fetches all `LocalScanRecord` rows, computes profile stats, heatmap, and awards |
| `AchievementsCalculator` | Pure `struct` with `static func calculate(from:) -> [AwardPayload]` |
| `GamificationManager` | `@MainActor @Observable` singleton — in-memory award cache, notification triggers |
| `GamificationModels` | `AwardPayload`, `AwardState` value types |
| `Achievements` component | SwiftUI view rendering the award grid with sort options |
| `UserStats` component | Renders species count and current streak from `LocalScanRecord` |
| `ScansHeatmap` | Calendar heatmap of scan activity (52-week rolling window) |

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
    → ProfileDatabaseActor.calculateProfileStats()   → (speciesCount: Int, streak: Int)
    → ProfileDatabaseActor.calculateHeatmapData()    → ProfileHeatmapData
    → ProfileDatabaseActor.calculateAwards()
        → AchievementsCalculator.calculate(from:)
            → [AwardPayload]
    → GamificationManager.evaluateAchievementsForNotifications(awards:)
```

`ProfileDatabaseActor` is instantiated in `ProfileTabView.body` inside a `.task` modifier. All three calculations run sequentially on the actor, then their results are dispatched back to `@MainActor` in a single `MainActor.run` block.

`ProfileDatabaseActor.calculateAwards()` is also called by `InferenceEngine` after **every** successful inference — not just new discoveries. This is intentional: awards can trigger on conditions unrelated to species novelty (time-of-day, elevation, temperature, IUCN status, etc.).

All `ProfileDatabaseActor` fetches use `propertiesToFetch` projections to minimise the SQLite column surface loaded into memory, preventing JetSam pressure on accounts with large scan histories.

---

## AchievementsCalculator

`AchievementsCalculator.calculate(from: [LocalScanRecord]) -> [AwardPayload]` is a pure, synchronous function with no side effects. It iterates all records once, maintaining running `Set<String>` accumulators keyed on `scientificName` per award criterion:

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

All species-based criteria use `Set<String>` keyed on `scientificName` to de-duplicate — scanning the same species 10 times counts as 1 toward a species-based award.

The `firstScanDate` is taken from `allRecords.first?.timestamp` (the oldest record, since the fetch is sorted `timestamp` descending). Each accumulator also tracks a `lastInteractionDate` as the timestamp of the first qualifying record seen during the iteration.

---

## Adding a New Award

1. Add a new tracking `Set<String>` and `Date?` variable in `AchievementsCalculator.calculate`.
2. Add the accumulation logic inside the `for record in allRecords` loop.
3. Append a new `AwardPayload(title:type:currentCount:targetCount:lastInteractionDate:)` to the return array.
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
