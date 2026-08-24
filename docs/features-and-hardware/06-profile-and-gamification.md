# Profile and Gamification

This document covers the Profile tab architecture, how scan statistics are
computed, the `AchievementsCalculator` award system, and how to add new award
criteria.

---

## Architecture

Profile is organized by product area under `apps/ios/Merian/Features/Profile/`:
`Shell/` owns the profile/settings pager, `UserProfile/` owns the visible user
profile tab and gamification/statistics surfaces, `Settings/` owns settings rows
and account actions; `Settings/Plan/` owns subscription/paywall surfaces,
`Settings/Notifications/` owns push preferences, `Settings/Changelog/` owns
bundled release notes, `Settings/Feedback/` owns the beta survey, and `Shared/`
owns cross-area profile state.

| File                         | Role                                                                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `ProfileTabView`             | Root profile tab view                                                                                                                     |
| `SettingsTabView`            | Settings sub-tab                                                                                                                          |
| `ProfileViewModel`           | `@Observable @MainActor` — cloud preferences (geoprivacy), auth state, sign-in/out                                                        |
| `ProfileAvatarImagePreparer` | Downsamples, square-crops, and WebP/JPEG encodes selected public profile pictures before R2 staging                                       |
| `ProfileDatabaseActor`       | `@ModelActor` — builds compact SwiftData projections, computes profile stats, heatmap, and awards off-main                                |
| `AchievementsCalculator`     | Pure `struct` with `static func calculate(from:) -> [AwardPayload]`                                                                       |
| `GamificationManager`        | `@MainActor @Observable` singleton — in-memory award cache, notification triggers                                                         |
| `GamificationModels`         | `AwardPayload`, `AwardState`, and `UserPersona` enumerations                                                                              |
| `Achievements` component     | SwiftUI view rendering the award grid with sort options                                                                                   |
| `UserStats` component        | Renders species count and current streak from `LocalScanRecord`                                                                           |
| `Persona` component          | Renders the user's active `UserPersona` tier badge and title                                                                              |
| `Terrarium` component        | Biological 3D hex-grid mapping representation based on the user's active progression tier                                                 |
| `PlanCard` component         | Plan banner distinguishing paid, verified complimentary, exhausted, and free state; detailed counters appear only in Results and Settings |
| `ScansHeatmap`               | Calendar heatmap of scan activity (52-week rolling window) anchored to analysis upload date, bypassing EXIF `captureDate`                 |

---

## Presentation Ownership

Profile keeps navigation pushes separate from UIKit-backed modal ownership.
`ProfileTabView` uses one `ProfileTabPresentation` item for paywall, Insight,
and Field-trip author sheets. `AchievementDetailSheet` uses one
`AchievementDetailPresentation` item for Insight and Field-trip author detail;
its background contribution reload starts only after the exact Insight case has
cleared. A new Profile sheet destination must join the enum owned by its host,
not add a sibling `.sheet` modifier.

`UserProfile` owns a separate `UserProfilePresentation` value for username,
display-name, and avatar-crop destinations. Its item-based sheet and filtered
full-screen cover read the same mutually exclusive value. The system
`PhotosPicker` is not an enum case, but it is treated as occupying the same
local presentation slot: editors and the cropper cannot mount over it, and a
picker request is rejected while an editor, cropper, or upload is active. No
Profile handoff uses a fixed sleep to guess UIKit teardown.

---

## Personas and Terrarium

The `UserPersona` enumeration (defined in `GamificationModels.swift`) replaces
legacy arbitrary ranking scales with a strict, 5-tier biological taxonomy path
derived mathematically from the user's `uniqueSpeciesCount` (NOT total scans):

| Tier Level | Persona Title        | Unique Species Threshold | Asset Identifier        |
| ---------- | -------------------- | ------------------------ | ----------------------- |
| Tier 1     | Observer             | 0                        | `persona-observer`      |
| Tier 2     | Casual Explorer      | 10                       | `persona-explorer`      |
| Tier 3     | Dedicated Naturalist | 50                       | `persona-naturalist`    |
| Tier 4     | Verified Scholar     | 250                      | `persona-scholar`       |
| Tier 5     | Apex Observer        | 1000                     | `persona-apex-observer` |

The `Persona` UI component cross-references this enum against the user's live
profile statistics to render the appropriate `.imageset` container from the
`Personas/` asset catalog group. It sits adjacent to the `Terrarium` component
on the Profile Tab, which loads compounding biological elements based on the
same 5-tier logic.

**Plan Card Integration**: `PlanCard` uses paid `isSubscribed` for paid plan
management and the current-launch `EntitlementManager` snapshot for functional
complimentary copy. Detailed remaining/exhausted copy is enabled only by Results
and Settings contexts, never the public profile card. Functional Pro uses
`luna-moth`; free/exhausted uses `compass`, both from
`apps/ios/Merian/Assets.xcassets/Graphics3D/`. Public Profile and Explore Pro
badges use paid status only.

---

## ProfileViewModel Responsibility Boundary

`ProfileViewModel` handles **only** cloud-network operations:

- `fetchGeoprivacy()` — reads `default_geoprivacy` from the Supabase `users`
  table
- `fetchPublicIdentity()` — reads the public display/handle projection
  (`public_author_name`, `public_username`, `public_avatar_url`) from the
  Supabase `users` table
- `checkPublicUsernameAvailability(_:)` — calls `/check-public-username` for
  inline username uniqueness validation in the edit sheet
- `updatePublicUsername(_:)` — calls `/update-public-username`, refreshes the
  local handle, and publishes `.publicAuthorIdentityChanged` so Explore/Profile
  surfaces can update
- `updatePublicDisplayName(_:)` — calls `/update-public-display-name`, refreshes
  the public display name, and marks the identity as a user-chosen display name
- `updatePublicAvatar(_:)` — stages a prepared square profile picture in R2,
  calls `/update-public-avatar`, refreshes `publicAvatarUrl`, and publishes
  `.publicAuthorIdentityChanged`
- `signInWithApple()`, `signInWithGoogle()`, `signOut()` — delegates to
  `SupabaseManager`. User-facing **Sign out** first persists a server-issued
  purchase-continuity proof, then creates one fresh anonymous session, binds its
  uppercase RevenueCat UUID, synchronizes the StoreKit receipt, and waits for
  server entitlement verification. Any incomplete step retains the proof and
  shows a **Finish sign out** recovery control. Promotional/beta access remains
  on the linked source. The anonymous account offers **Continue with Apple** and
  **Continue with Google**. Account deletion uses low-level `signOut()` without
  replacement or purchase transfer.
- Auth state computed properties (`isGuestUser`, `userName`, `userEmail`,
  `userAvatarURL`, `publicUsernameDisplayName`)

Heavy data operations (fetching all scan records for stats, computing awards)
are **firewalled** out of `ProfileViewModel` and into `ProfileDatabaseActor` to
avoid locking the `@MainActor`.

## Public Username UX

The Profile account card shows the user's public handle (`@public_username`) in
place of the private email line. The handle is available to anonymous and
authenticated sessions and is the canonical comment-mention identity.

The edit sheet accepts pasted values with or without `@`, shows the normalized
preview inline, rejects protected brand namespaces, official/system roles, and
exact brand-role combinations before submission, then confirms availability
through the authenticated server boundary. The database CHECK remains
authoritative even when an older client lacks the current early-feedback list.
The sheet submits through `MerianNetworkClient.updatePublicUsername`. Logged-in
Explore posts continue to render `public_author_name` when the user has a
provider-derived display label; default/ghost identities render
`@public_username`. See [`21-public-usernames.md`](./21-public-usernames.md) for
the full backend and display contract, exact reservation groups, and
historical-mention behavior.

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
`ImageFileWrapper`, asks `MediaPreparationActor` for a bounded crop-preview
`CGImage`, then hands the confirmed crop bytes to `ProfileAvatarImagePreparer`
for downsample, square-crop, and WebP/JPEG encoding. `ProfileViewModel` uploads
the prepared bytes to R2 staging through the same `/generate-upload-urls`
manifest used by scan media, then calls
`MerianNetworkClient.updatePublicAvatar(...)`.

Selection preparation is one stored, replaceable task keyed by a request UUID.
Opening another picker or editor, changing accounts, or leaving the view cancels
that task and clears its staged value. Completion may update UI only if the
request is still current, uncancelled, and the typed presentation slot is empty.
If the bounded crop preview is ready before the Photos picker binding dismisses,
exactly one prepared request waits locally and mounts only after the binding is
false. The preview never enters a global event or feedback payload.

Confirmed-crop preparation/upload is stored and serialized. It captures the
current account ID and checks both account and request identity after image
preparation and again after the network update. Account changes and view
teardown cancel it. Failures remain pending while a picker, editor, or cropper
is visible and present only after the slot is clear; an account transition
clears both the pending error and the view model's avatar error so a stale
failure cannot leak into the replacement profile.

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
        → returns typed presentation-eligible awards without invoking UI
        → ScanMilestoneCoordinator batches them after Field trip progress
```

`ProfileDatabaseActor` is instantiated in `ProfileTabView.body` inside a `.task`
modifier. `calculateAll()` is the primary profile render entry point: it loads
one `ProfileStatsProjection`, derives species count, streak, heatmap, and awards
from that projection, then dispatches the flat `Sendable` result back to
`@MainActor` in a single `MainActor.run` block.

`ProfileDatabaseActor.calculateAwards()` is also called by the shared scan
milestone coordinator after **every** successful inference — not just new
discoveries. The call runs in follow-up work after parsed/persisted
`speciesData` is committed and the Field trip progress attempt finishes, so
award projection and notification evaluation cannot delay the first result frame
or overtake progress notifications from the same scan. This is intentional:
awards can trigger on conditions unrelated to species novelty (time-of-day,
elevation, temperature, IUCN status, etc.).

All `ProfileDatabaseActor` fetches use `propertiesToFetch` projections to
minimise the SQLite column surface loaded into memory, preventing JetSam
pressure on accounts with large scan histories. The stats projection cache
stores only scalar `Sendable` structs, timestamps, and precomputed counts —
never live `LocalScanRecord` model objects. Cache reuse is fingerprinted by scan
count, latest scan ID, and latest timestamp; call
`invalidateCachedProfileProjections()` before reusing a long-lived actor after
in-place scan edits.

---

## Achievements vs Field trip Challenge Badges

Most achievements are always-on account awards computed from the local scan
history projection. They can progress without joining anything, and they are
recalculated after successful inference so long-running milestones stay current.

**The Field Naturalist** (`first_field_trip`) is server-authoritative. Standard
outing and Seasonal Challenge evidence are both public with Field trips. The
account-scoped offline cache stores the server-authoritative earliest result and
its typed destination. The local calculator emits the locked/default state so
profiles remain complete without pretending scan history can resolve Field trip
completion.

Automatic Backyard Safari Level 1 enrollment follows that existing public status
contract. A new or backfilled account may show an active `0/N` starter on its
Explore author profile before earning Field Naturalist; enrollment does not
publish the scans or evidence used for later progress.

Field trip Challenge badges are seasonal, curated, server-authoritative, and
shown with the public Events experience. They require an explicit challenge
join, count only scans made after `joined_at` and before the challenge ends, and
are awarded through Supabase challenge participation tables. Challenge badges
can appear near Field trip profile modules as lightweight public reward cards,
but they do not expose scan IDs, media, exact locations, notes, or private
evidence, and they are not prizes, rankings, or contest eligibility markers.
Only scans that satisfy the
[Field Trip identification-evidence policy](25-field-trips.md#identification-evidence-policy)
count. A later downgrade to weak unreviewed evidence removes the contribution,
reopens affected challenge progress, and clears a badge that is no longer
earned.

---

## AchievementsCalculator

`AchievementsCalculator.calculate(from:) -> [AwardPayload]` is a pure,
synchronous function with no side effects. It accepts any
`AchievementRecordRepresentable`, so profile rendering can pass lightweight
projection structs instead of full SwiftData models. It iterates all records
once, maintaining running canonical-species accumulators per award criterion:

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

All species-based criteria de-duplicate by canonical species key
(`confirmedSpeciesId`, then `speciesId`, then display scientific name) —
scanning the same species 10 times counts as 1 toward a species-based award.

The first-scan achievement is resolved by finding the oldest timestamp in the
projection, with scan ID as a deterministic tie-breaker. Species-based
accumulators likewise retain the earliest qualifying scan for every canonical
species while independently tracking `lastInteractionDate` from the newest
qualifying scan. A repeat observation can therefore update recency without
moving an award's original `unlockedAt` timestamp or changing the contribution
that earned it. `currentCount` reflects the full de-duplicated qualifying count,
even after an award is unlocked; `progressFraction` clamps the visual progress
against `targetCount`, and the detail sheet can show every qualifying
contribution. Note that `timestamp` strictly represents the system upload and
processing time, completely decoupled from the original image's EXIF
`captureDate`. This ensures that historical backfills from users' photo
libraries do not retroactively trigger streaks or skew gamification timing
mechanics.

## Public Explore Profile Achievements

Explore author profiles reuse the same `AchievementType`,
`AchievementDefinition`, `AwardPayload`, and `AchievementCard` rendering system,
but they do not reuse local qualifying-scan detail presentation.

The backend endpoint `get-explore-author-profile` returns achievement progress
as remote JSON:

```json
{
  "type": "explorer",
  "current_count": 5,
  "last_interaction_at": "2026-05-03T12:00:00.000Z"
}
```

The response intentionally omits scan IDs and contribution metadata. iOS
converts each remote item to `AwardPayload` in
`ExploreAuthorProfileAward.awardPayload`, then renders:

```swift
Achievements(
    awards: profile.awardPayloads,
    allowsDetailPresentation: false
)
```

`allowsDetailPresentation: false` makes each `AchievementCard` non-interactive
and replaces the accessibility hint with a public-profile privacy hint. The
local Profile tab continues to use the default interactive mode, so local
achievements still open `AchievementDetailSheet` and qualifying local scans.

When adding a new achievement, update both:

- the local Swift definition in `AchievementType.definition`
- the SQL progress projection in `public.get_explore_author_profile(...)`

The public SQL projection must return progress only. Do not add qualifying scan
IDs, scan URLs, exact locations, private notes, Field trip template slugs, or
Seasonal Challenge IDs to the public achievement payload.

---

## Adding a New Award

1. Add a new `AchievementType` case and definition in
   `GamificationModels.swift`.
2. Choose a contribution kind (`firstScan` or `uniqueSpecies`) and provide the
   qualifying closure.
3. Ensure any new fields required by the closure are included in
   `ProfileAnalyticsProjection.propertiesToFetch`.
4. Add the award's visual representation to the `Achievements` SwiftUI component
   (and optionally an `AwardCard` difficulty mapping in `GamificationModels`).
5. `ProfileDatabaseActor.calculateAwards()` and
   `GamificationManager.evaluateAchievementsForNotifications` require no changes
   — they consume the `[AwardPayload]` array dynamically.

**Do not gate** `calculateAwards()` on `isNewDiscovery`. The full recalculation
must run after every scan because award criteria are independent of novelty.

---

## GamificationManager

`GamificationManager.shared` is an `@MainActor @Observable` singleton that
persists lightweight gamification state in `UserDefaults`:

- `unlockedSpeciesCount` — incremented each time `recordNewSpeciesDiscovered()`
  is called
- `hasFireflyBadge` — unlocked when `unlockedSpeciesCount >= 5`
- `unlockedAchievements: Set<String>` — type keys of all completed awards

`recordNewSpeciesDiscovered()` is called by `InferenceEngine` when
`isNewDiscovery == true`. It increments `unlockedSpeciesCount`, persists it, and
checks the firefly badge threshold.

`evaluateAchievementsForNotifications(awards:)` is called after
`calculateAwards()` completes. It iterates `[AwardPayload]`, checks if any
award's type is newly absent from `unlockedAchievements` but now `isCompleted`,
adds it to the set, persists the set, returns the presentation-eligible awards,
and queues a native local push notification via
`PushNotificationManager.shared.sendAchievementUnlockedNotification` if the
`isAchievementNotificationsEnabled` `UserDefaults` flag is set. The domain
manager never invokes an in-app presenter. `ScanMilestoneCoordinator` owns the
visual handoff and places the returned awards after Field trip progress without
delaying persistence or push behavior.

Achievements introduced after users already have local scan history can define a
notification cutoff in `GamificationManager`. The domestic cat and dog
achievements use the July 4, 2026 rollout cutoff so qualifying legacy scans are
persisted as unlocked without showing a retroactive toast, while fresh
qualifying scans still notify normally.

## Milestone Toasts

`AppDIContainer` owns the production `MilestoneToastPresenter`,
`ScanMilestoneCoordinator`, injectable clock, and foreground-host registry used
by Field trip progress, achievement unlocks, and the `New to Naturebook`
dictionary-contribution banner. There is no separate presenter or coordinator
singleton. The container injects its producer-only `AppEventSending` capability
into the scan coordinator; the coordinator never reaches back through
`AppDIContainer.shared`, so previews and tests retain isolated invalidation
graphs. The process-local visual queue is capped at 32 lightweight items;
overflow may omit ephemeral feedback but cannot lose already-durable progress or
achievement state, while equivalent typed payloads coalesce onto a stable item
ID. `ScanMilestoneCoordinator` owns the per-scan business ordering: standard
outings in server order, Seasonal Challenges in server order, achievements in
their existing order, then the dictionary milestone. Foreground and background
completion paths share the coordinator and are deduplicated by final saved scan
ID. Retryable Field trip failures do not finalize that key or discard the
selected goal; they use bounded retries while an independent milestone-delivery
key prevents ordinary achievements and dictionary feedback from replaying after
recovery. Runtime auth changes and foreground session timeouts clear queued
visual items and fence late async callbacks with captured generation tokens.

The latest mounted feedback host renders exclusively and restores its parent
when it disappears. Presentation start time, haptics, and VoiceOver are claimed
once by the presenter, so moving the same active item between hosts preserves
its remaining 3.5-second lifetime without repeating effects. Banner taps request
typed `AppRoute.achievement` or `AppRoute.captureGoal` values; achievement
detail then uses the single root sheet host. The milestone overlay and ordinary
typed `ToastPayload` do not mount concurrently when they target the same
alignment; independent top/bottom feedback may coexist. Only the visible front
milestone banner receives hit testing. The presenter does not mutate achievement
progress, Field trip progress, analytics, scan data, dictionary state, or native
iOS notification authorization.

`ProfileTabView` keys its statistics task by both the ordinary refresh token and
the current authentication/account identity. On cold launch it can render local
awards immediately while signed out, then automatically fetch and merge the
server-backed first-Field-trip achievement as soon as session restoration
completes. Sign-out and account changes also produce a fresh key, preventing one
account's cached Field trip award from remaining in another account's Profile.

DEBUG Settings includes preview controls for achievement toasts,
`Preview New to Naturebook notification`
(`Settings_PreviewNewToMerianNotification`), and
`Preview Field trip progress toast` (`Settings_PreviewFieldTripProgressToast`).
These controls enqueue representative payloads through the same presenter path
so styling can be tested without completing a scan, changing outing progress,
contributing a dictionary species, or unlocking an award.

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
- `progressFraction: Double` — clamped `currentCount / targetCount`;
  `currentCount` itself is never truncated to the target
- `difficultyLevel: Int` — 0 (Easy), 1 (Medium), 2 (Hard), derived from the
  `type` key
- `difficultyString: String` — human-readable label

The `Achievements` component sorts awards using a `smartSort` heuristic:
recently completed (within 7 days) float to the top, in-progress awards ranked
by proximity to completion follow, legacy completions and empty awards sink to
the bottom. Additional sort options are available via a menu: completed first,
incomplete first, easiest first, hardest first.

---

## ExportScans (DwC-A)

`ExportScans` is staged and does not appear in an initial-launch Release build:
`FeatureFlag.dwcaExports` defaults to `false`. Debug-only overrides can expose
the UI for development, but cannot override the canonical PostgreSQL release
gate. Migration `20260728133835_disable_dwca_exports_for_launch.sql` also makes
old builds and direct authenticated requests fail closed.

`ExportScans` (Settings) calls `MerianNetworkClient.shared.requestDwcAExport()`,
which hits the `/request-export-dwca` Edge Function with a 15-second timeout.
The authenticated route queues personal exports only. Its insertion trigger
first counts bounded eligible IDs, then materializes one bounded occurrence and
multimedia DTO per member from the same creation-statement MVCC snapshot.
Oversized sources stop at the first per-row or cumulative byte violation without
retaining partial DTOs.

Server-side work advances through claim-fenced, cursor-persisted 100-row/256 KiB
pages over that immutable source, bounded streaming assembly, and idempotent
delivery rather than blocking the client or one Edge invocation. A full-member
privacy fence runs before assembly, staging, email, and completion. A later
tombstone or privacy/protection change terminates the job, revokes its
application capability, and enqueues the archive for durable cleanup; each
download click reruns that fence before a 30-second read-only redirect. Once the
feature passes its separate enable gate, the user receives an email when the
export is ready. See
[API Contracts](../backend-and-data/05-api-contracts.md#deno-request-export-dwca-edge-node)
and the
[release assurance record](../backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

## 2026-04 Hardening Updates

- Profile analytics now share a single projection-style fetch for streaks,
  heatmap construction, and achievement calculation instead of repeatedly
  scanning the full library through separate fetch paths.
- Achievement calculation is now projection-friendly via
  `AchievementRecordRepresentable`, so awards can be computed from lightweight
  analytics payloads without materializing full model objects.
- Offline scan timestamp preservation now directly protects gamification
  correctness: streaks, monthly heatmaps, and species chronology are computed
  from the original capture date rather than delayed sync time.
