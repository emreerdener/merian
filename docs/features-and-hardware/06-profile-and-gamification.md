# Profile and Gamification

This document covers the Profile tab architecture, how scan statistics are computed, the `AchievementsCalculator` award system, and how to add new award criteria.

---

## Architecture

Profile is organized by product area under `apps/ios/Merian/Features/Profile/`:
`Shell/` owns the profile/settings pager, `UserProfile/` owns the visible user profile tab
and gamification/statistics surfaces, `Settings/` owns settings rows and account
actions; `Settings/Plan/` owns subscription/paywall surfaces, `Settings/Notifications/` owns push
preferences, `Settings/Changelog/` owns bundled release notes, `Settings/Feedback/` owns the beta
survey, and `Shared/` owns cross-area profile state.

| File                     | Role                                                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `ProfileTabView`         | Root profile tab view                                                                                                     |
| `SettingsTabView`        | Settings sub-tab                                                                                                          |
| `ProfileViewModel`       | `@Observable @MainActor` — cloud preferences (geoprivacy), auth state, sign-in/out                                        |
| `ProfileAvatarImagePreparer` | Downsamples, square-crops, and WebP/JPEG encodes selected public profile pictures before R2 staging                  |
| `ProfileDatabaseActor`   | `@ModelActor` — builds compact SwiftData projections, computes profile stats, heatmap, and awards off-main                |
| `AchievementsCalculator` | Pure `struct` with `static func calculate(from:) -> [AwardPayload]`                                                       |
| `GamificationManager`    | `@MainActor @Observable` singleton — in-memory award cache, notification triggers                                         |
| `GamificationModels`     | `AwardPayload`, `AwardState`, and `UserPersona` enumerations                                                              |
| `Achievements` component | SwiftUI view rendering the award grid with sort options                                                                   |
| `UserStats` component    | Renders species count and current streak from `LocalScanRecord`                                                           |
| `Persona` component      | Renders the user's active `UserPersona` tier badge and title                                                              |
| `Terrarium` component    | Biological 3D hex-grid mapping representation based on the user's active progression tier                                 |
| `PlanCard` component     | Dynamic subscription banner reading `isProActive` to serve custom `.xcassets` graphics (`sparkles` vs `compass`)          |
| `ScansHeatmap`           | Calendar heatmap of scan activity (52-week rolling window) anchored to analysis upload date, bypassing EXIF `captureDate` |

---

## Personas and Terrarium

The `UserPersona` enumeration (defined in `GamificationModels.swift`) replaces legacy arbitrary ranking scales with a strict, 5-tier biological taxonomy path derived mathematically from the user's `uniqueSpeciesCount` (NOT total scans):

| Tier Level | Persona Title        | Unique Species Threshold | Asset Identifier     |
| ---------- | -------------------- | ------------------------ | -------------------- |
| Tier 1     | Observer             | 0                        | `persona-observer`   |
| Tier 2     | Casual Explorer      | 10                       | `persona-explorer`   |
| Tier 3     | Dedicated Naturalist | 50                       | `persona-naturalist` |
| Tier 4     | Verified Scholar     | 250                      | `persona-scholar`    |
| Tier 5     | Apex Observer        | 1000                     | `persona-apex-observer`       |

The `Persona` UI component cross-references this enum against the user's live profile statistics to render the appropriate `.imageset` container from the `Personas/` asset catalog group. It sits adjacent to the `Terrarium` component on the Profile Tab, which loads compounding biological elements based on the same 5-tier logic.

**Plan Card Integration**: The `PlanCard` dynamic banner also eschews standard SF Symbols in favor of reusable 3D artwork. Depending on `RevenueCatManager.shared.isProActive`, it uses `luna-moth` for Premium users and `compass` for Free-tier users from `apps/ios/Merian/Assets.xcassets/Graphics3D/`.

---

## ProfileViewModel Responsibility Boundary

`ProfileViewModel` handles **only** cloud-network operations:

- `fetchGeoprivacy()` — reads `default_geoprivacy` from the Supabase `users` table
- `fetchPublicIdentity()` — reads the public display/handle projection
  (`public_author_name`, `public_username`, `public_avatar_url`) from the
  Supabase `users` table
- `checkPublicUsernameAvailability(_:)` — calls `/check-public-username` for
  inline username uniqueness validation in the edit sheet
- `updatePublicUsername(_:)` — calls `/update-public-username`, refreshes the
  local handle, and publishes `.publicAuthorIdentityChanged` so Explore/Profile
  surfaces can update
- `updatePublicDisplayName(_:)` — calls `/update-public-display-name`,
  refreshes the public display name, and marks the identity as a user-chosen
  display name
- `updatePublicAvatar(_:)` — stages a prepared square profile picture in R2,
  calls `/update-public-avatar`, refreshes `publicAvatarUrl`, and publishes
  `.publicAuthorIdentityChanged`
- `signInWithApple()`, `signInWithGoogle()`, `signOut()` — delegates to `SupabaseManager`
- Auth state computed properties (`isGuestUser`, `userName`, `userEmail`,
  `userAvatarURL`, `publicUsernameDisplayName`)

Heavy data operations (fetching all scan records for stats, computing awards) are **firewalled** out of `ProfileViewModel` and into `ProfileDatabaseActor` to avoid locking the `@MainActor`.

## Public Username UX

The Profile account card shows the user's public handle (`@public_username`) in
place of the private email line. The handle is available to anonymous and
authenticated sessions and is the future-safe tag/mention identity.

The edit sheet accepts pasted values with or without `@`, shows the normalized
preview inline, and submits through `MerianNetworkClient.updatePublicUsername`.
Logged-in Explore posts continue to render `public_author_name` when the user
has a provider-derived display label; default/ghost identities render
`@public_username`. See
[`21-public-usernames.md`](./21-public-usernames.md) for the full backend and
display contract.

---

## Public Display Name UX

Guest and signed-in users can edit their public display name from the Profile
identity menu. The display-name editor trims/collapses whitespace, rejects empty
or control-character values, and caps names at 40 characters before submitting
through `/update-public-display-name`.

Untouched guest aliases still show as `Explorer` on the local Profile card, with
the stable `@public_username` underneath. Once a guest chooses a display name,
that name becomes the public Explore author label and is preserved when the
guest upgrades to Apple or Google sign-in.

---

## Public Avatar UX

The Profile card lets guest and signed-in users choose a custom public profile
picture with `PhotosPicker`. `UserProfile` loads the selected item as an
`ImageFileWrapper`, then `ProfileAvatarImagePreparer` downsamples, square-crops,
and encodes it as WebP with JPEG fallback. `ProfileViewModel` uploads the
prepared bytes to R2 staging through the same `/generate-upload-urls` manifest
used by scan media, then calls `MerianNetworkClient.updatePublicAvatar(...)`.

The profile screen renders `public_avatar_url` from `public.users` first. If the
user has not uploaded a custom avatar, it falls back to OAuth metadata
(`avatar_url` or `picture`) from the Supabase session. Successful updates change
the local profile avatar immediately and post `.publicAuthorIdentityChanged` so
Explore cards, comments, author sheets, and profile previews can refresh their
public author rows.

Guest custom avatars are preserved when the guest upgrades to Apple or Google
sign-in.

Custom avatars are public by design and live under
`https://media.merian.app/avatars/{userId}/...`. They are durable profile media,
not scan media. Scan purge jobs must never delete them; only
`/update-public-avatar` may delete a previous same-user avatar after a
replacement has been promoted.

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

| Award title            | Type key          | Criterion                                   | Target |
| ---------------------- | ----------------- | ------------------------------------------- | ------ |
| New Observer           | `first_scan`      | Any scan exists                             | 1      |
| The Naturalist         | `explorer`        | Unique species count                        | 5      |
| The Botanist           | `plantae`         | Unique Plantae kingdom species              | 10     |
| The Zoologist          | `insecta`         | Unique Insecta or Arachnida class species   | 10     |
| The Mycologist         | `fungi`           | Unique Fungi kingdom species                | 10     |
| The Urban Ecologist    | `urban`           | Unique urban/domesticated ecology scans     | 10     |
| The Frost Walker       | `frost_walker`    | Unique scans at temp < 32°F                 | 5      |
| The Alpine Naturalist  | `alpine`          | Unique scans at elevation > 2500m           | 5      |
| The Nocturnal Observer | `nocturnal`       | Unique scans between hour 22–05 (inclusive) | 10     |
| The Guardian           | `guardian`        | Unique invasive species scans               | 5      |
| The Conservationist    | `conservationist` | Any IUCN status that is not LC, NE, or DD   | 1      |
| The Toxicologist       | `toxicologist`    | Unique poisonous species scans              | 5      |
| The Perfect Lens       | `perfect_lens`    | Unique scans with confidence ≥ 0.98         | 25     |
| The Feline Friend      | `domestic_cat`    | First domestic cat scan                     | 1      |
| The Canine Companion   | `domestic_dog`    | First domestic dog scan                     | 1      |

All species-based criteria de-duplicate by canonical species key (`confirmedSpeciesId`, then `speciesId`, then display scientific name) — scanning the same species 10 times counts as 1 toward a species-based award.

The first-scan achievement is resolved by finding the oldest timestamp in the projection, with scan ID as a deterministic tie-breaker. Each accumulator also tracks a `lastInteractionDate` as the most recent qualifying contribution. `currentCount` reflects the full de-duplicated qualifying count, even after an award is unlocked; `progressFraction` clamps the visual progress against `targetCount`, and the detail sheet can show every qualifying contribution. Note that `timestamp` strictly represents the system upload and processing time, completely decoupled from the original image's EXIF `captureDate`. This ensures that historical backfills from users' photo libraries do not retroactively trigger streaks or skew gamification timing mechanics.

## Public Explore Profile Achievements

Explore author profiles reuse the same `AchievementType`, `AchievementDefinition`, `AwardPayload`, and `AchievementCard` rendering system, but they do not reuse local qualifying-scan detail presentation.

The backend endpoint `get-explore-author-profile` returns achievement progress as remote JSON:

```json
{
  "type": "explorer",
  "current_count": 5,
  "last_interaction_at": "2026-05-03T12:00:00.000Z"
}
```

The response intentionally omits scan IDs and contribution metadata. iOS converts each remote item to `AwardPayload` in `ExploreAuthorProfileAward.awardPayload`, then renders:

```swift
Achievements(
    awards: profile.awardPayloads,
    allowsDetailPresentation: false
)
```

`allowsDetailPresentation: false` makes each `AchievementCard` non-interactive and replaces the accessibility hint with a public-profile privacy hint. The local Profile tab continues to use the default interactive mode, so local achievements still open `AchievementDetailSheet` and qualifying local scans.

When adding a new achievement, update both:

- the local Swift definition in `AchievementType.definition`
- the SQL progress projection in `public.get_explore_author_profile(...)`

The public SQL projection must return progress only. Do not add qualifying scan IDs, scan URLs, exact locations, or private notes to the public achievement payload.

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

`evaluateAchievementsForNotifications(awards:)` is called after `calculateAwards()` completes. It iterates `[AwardPayload]`, checks if any award's type is newly absent from `unlockedAchievements` but now `isCompleted`, adds it to the set, persists the set, enqueues the shared in-app achievement milestone toast through `MilestoneToastPresenter`, and queues a native local push notification via `PushNotificationManager.shared.sendAchievementUnlockedNotification` if the `isAchievementNotificationsEnabled` `UserDefaults` flag is set.

Achievements introduced after users already have local scan history can define a notification cutoff in `GamificationManager`. The domestic cat and dog achievements use the July 4, 2026 rollout cutoff so qualifying legacy scans are persisted as unlocked without showing a retroactive toast, while fresh qualifying scans still notify normally.

## Milestone Toasts

`MilestoneToastPresenter` owns the shared bottom in-app milestone notification queue used by achievement unlocks and the Insight `New to Merian` dictionary-contribution banner. Achievement payloads enter from `GamificationManager`; dictionary milestones enter from `InsightSheetViewModel` when `SpeciesData.isNewToMerianDictionary` is true. The presenter controls only visual presentation, haptics, timeout, swipe/close dismissal, VoiceOver announcements, and achievement detail routing. It does not mutate achievement progress, analytics, scan data, dictionary state, or native iOS notification authorization.

DEBUG Settings includes preview controls for achievement toasts and `Preview New to Merian notification` (`Settings_PreviewNewToMerianNotification`). These controls enqueue representative payloads through the same presenter path so styling can be tested without completing a scan or unlocking an award.

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
- `progressFraction: Double` — clamped `currentCount / targetCount`; `currentCount` itself is never truncated to the target
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
