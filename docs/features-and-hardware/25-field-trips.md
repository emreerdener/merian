# Field trips

Field trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## Current Scope

- Standard Field trips, Outings, and Events are released for every user. Events
  have no independent client feature flag, account allowlist, or simulator
  bypass. The backend remains authoritative for authentication, challenge
  access, participation, and mutations.
- Field trips live under Explore in
  `apps/ios/Merian/Features/Explore/FieldTrips/`.
- The Field trips surface opens directly to `Outings` for standard outings. The
  page header always includes an `Outings`/`Events` segmented picker, and Events
  lists live and upcoming curated challenges.
- Standard Field trip and Seasonal Challenge details use one continuous page
  without a `Goals`/`Tips` toolbar picker or separate guide page. Standard
  outing detail selects the current level's first incomplete guided goal by
  default. Its tile hides the inline goal name so the artwork can aspect-fit
  across the full square, while the expanded tips begin with that goal name as a
  heading. Tapping the selected goal hides its tips, and tapping another guided
  goal switches the single selection. A refresh does not reopen a goal the user
  collapsed. Completed media continues to open Insight, while completed and
  locked level cards never expose tips. Seasonal Challenge level presentation
  remains unchanged. The unheaded outing-guidance cards follow the level and
  Community/Event-entry content at the bottom of the page. Each keeps its outer
  card surface and places a bare icon at the top-leading edge beside its copy,
  using the same compact icon sizing as goal tips and no separate icon
  container.
- Standard outing detail centers a wrapping metadata row beneath its centered
  serif title and description. The row contains publication visibility when
  enabled, locked Pro access, difficulty, current level, and an optional
  privacy-filtered authorized city/state. Lifecycle status drives catalog CTA
  copy and appears once as a centered, borderless capsule in the detail sheet's
  navigation bar rather than being repeated in metadata or level cards. Its dot
  is green for **Active** and **Completed**, orange for **Stopped**, and neutral
  for **Not started**.
- Seasonal challenges are curated/admin-created only, live inside Field trips,
  and require an explicit Join.
- Challenges link to existing Field trip templates but keep separate
  participation, item-completion, badge, entry, like, and comment storage so a
  seasonal challenge can repeat without corrupting normal Field trip progress or
  publications.
- Templates are curated in Supabase with region, season, habitat, difficulty,
  rotating-free, Pro access tags, cover images, estimated duration, and curated
  guide sections.
- Checklist items can include curated item-level tips. V4 does not generate
  pre-trip guidance with AI.
- While the idle visual Scan page is visible, a compact active-target indicator
  can surface unfinished goals from every active standard outing. Seasonal
  Challenge labels and challenge-specific progress are intentionally excluded
  from this first capture integration. Joining a challenge does not hide the
  linked standard outing or its normal progress.
- Every existing and future account is automatically enrolled into Backyard
  Safari Level 1 with a new activity period. A reset can still return it to the
  validated, unstarted two-goal introduction state. Enrollment keeps the
  existing profile-visible status-only summary, but never publishes the scans,
  media, notes, or location evidence behind progress.
- Users explicitly start other outings from the template detail page before
  their first matching scan.
- Unfinished active outings expose a trailing ellipsis with **Stop field trip**
  and destructive **Reset field trip**. Stopped outings preserve their visible
  checklist state, show **Resume outing**, and expose Reset without an empty
  menu. Completed and unstarted outings have no lifecycle menu.
- Levels unlock sequentially. Every standard completion belongs to a persisted
  `user_field_trips` row and activity period created either by Backyard Safari
  account enrollment or an explicit start. Matching scans never auto-start an
  outing.
- A checklist item can match by species, scientific name, taxonomy, ecology,
  habitat text, or dictionary group tag.
- AI matches and later user confirmations/corrections both call the progress
  updater.
- Completed standard-outing goals replace their curated artwork with the
  completing scan's device-local photo or video-poster thumbnail in both the
  catalog card and outing detail. They keep the standard neutral tile border;
  blue/accent borders are reserved for an incomplete focused goal.
- The standard outing detail places a square, edge-to-edge featured media
  carousel above its overview content whenever at least one curated goal
  reference or completed user visual is loadable. The scrolling overview stack
  orders the centered lifecycle status, title, description, metadata pills, and
  primary action before the levels; the action is not anchored to the bottom
  safe area. Navigation chrome contains only back and eligible options controls.
  Only the current active level contributes pages, in checklist order, capped at
  six. Each slot begins with one illustrative species image, trying Naturebook,
  Wikipedia, then GBIF; the exact goal's device-local photo or video poster
  replaces that reference after completion. Tapping opens the shared full-screen
  zoomable photo/playable-video viewer. Events and public publication pages do
  not show this carousel.
- Every standard outing level leads with a balanced row containing its bundled
  collectible patch, a centered bold title-style level name, and a numeric
  progress ring or matching locked ring. Lifecycle status is not repeated in
  level cards. Zero progress uses a neutral ring, positive progress uses green,
  and completed rings remain numeric rather than replacing the count with a
  checkmark. Tapping a patch opens its full-screen viewer with pinch and
  double-tap zoom.
- Goals follow the identity row without a level-description sentence. One or two
  goals use a two-column, equal-width square layout; levels with more than two
  goals use fixed square slots in a horizontal scroller. Curated 3D artwork
  remains uncarded and current-level goal tiles omit inline titles. Selecting a
  guided goal adds a neutral surface and border for a non-color-only active
  state, keeps the artwork at the full square, and moves that goal's name above
  its revealed tips.
- The authenticated user's profile summary card lists earned standard-outing
  patches beneath the stats and a divider. Tapping any patch opens the same
  zoomable full-screen viewer at that selection; when more patches are earned,
  the viewer supports horizontal paging and shows page dots.
- The authenticated user's active Field trip Profile card shows a leading title
  matching the profile stat-value style, a footnote-sized current-level label,
  and a larger trailing collectible patch in one top-aligned row above the
  existing device-local goal thumbnail strip. It does not show lifecycle status,
  a progress ring, or the former horizontal progress bar, and it does not change
  the public Explore author-profile row.
- Public Explore profiles render active, pinned, and published Field trip row
  titles with the bold headline text style. Active rows use an enlarged numeric
  label in their compact progress rings. Challenge badge titles retain their
  compact presentation.
- A saved scan that completes at least one current-level goal queues one
  progress toast for every credited standard outing and joined live Seasonal
  Challenge. Each toast shows **Field trip progress**, contextual species/trip
  copy, and the credited level's progress ring. Standard outings are queued
  before Seasonal Challenges, then achievement unlocks, then **New to
  Naturebook** for that scan.
- Tapping a completed goal with locally available evidence opens that scan's
  Insight view in the existing Explore navigation stack. Back returns to the
  outing without presenting another sheet.
- Every saved biological Insight that owns Field trip credit shows one
  persistent **Field trips** card after toxicity and identification review
  content. Each undivided row uses an uppercase **GOAL COMPLETE** eyebrow,
  headline-sized goal name, enlarged goal art/check badge, an experience-only
  subtitle, and prominent credited-level ring. Its heading uses the same icon
  and headline sizing as other Insight cards. The card keeps every credited
  outing/Event row visible and routes the full row to the experience's detail
  overview without a redundant chevron. It intentionally drops the credited
  checklist focus so a completed row never auto-expands an inline tip; native
  Back returns to the originating Insight.
- Field trip comments and likes are separate from Explore post comments and
  likes, even though the iOS UI reuses the compact Explore comment presentation.
- V4 supports profile showcase, up to 3 pinned published Field trips, completion
  badges for challenges, published Field trip pages, challenge entry pages,
  template-detail Community previews, and Field trips-native publication APIs.
  It does not create Explore feed posts, map points, public web share pages,
  APNs, widgets, leaderboards, prizes, rankings, contest windows, or
  sponsored-trip eligibility.

## Rollout State

- `FeatureFlag.fieldTrips.defaultValue == true` makes the complete Field trips
  surface public.
- Events were published for every user on 2026-08-07. The former
  `.fieldTripEvents` registry case, tester-email allowlist, simulator bypass,
  debug override, rollout logger, and Events-disabled presentation paths were
  removed.
- Every Field trips client now fetches the Events catalog, exposes the
  `Outings`/`Events` picker, accepts typed Event routes, includes challenge
  badges and progress, loads Event Insight contributions, and requests eligible
  hashtag suggestions.
- This client release did not change the API shape or backend authorization. The
  deployed Edge Function and database continue to enforce verified viewer,
  entitlement, Join, ownership, timing, and publication rules.

Before distributing an Events-capable iOS candidate, exercise catalog, detail,
Join, progress, badge, entry publication, comments/likes, optional Explore
hashtag suggestions, and typed navigation on physical signed-in and ghost
accounts. A rollback requires a reviewed replacement client build; do not weaken
or redeploy the backend solely to hide the Events UI.

## Product Terminology

These labels are a user-facing contract even though older internal symbols and
migration filenames may still use `objective` or `challenge`:

- **Field trips** is the feature name.
- **Outings** is the standard catalog segment; a standard item is an **outing**.
- **Events** is the seasonal segment. **Challenge** is reserved for seasonal
  challenge data and explanatory copy inside an Event.
- **Goals** is the user-facing name for checklist targets. Never label them
  **Objectives**.
- **Tips** describes the curated guidance revealed by selecting a guided goal in
  the current incomplete level card; it is not a page-navigation control.
- Standard-outing actions are **Start outing**, **Start scanning**, **Resume
  outing**, and **Publish outing**. Never use **Start challenge** or **Publish
  challenge** for a standard outing.
- A Not started catalog card uses **Get started**; every other lifecycle state
  uses **View field trip**. Both actions open detail and never start an outing
  directly.
- The active Scan capsule uses **Goal: {target}**. The post-Reset empty
  introduction uses **Start an outing** with **Backyard Safari · 2 goals**.
- Standard catalog cards omit the collectible patch, lifecycle badge, and
  progress ring. Each uses a rounded card surface with 16-point vertical
  separation and the standard 16-point outer horizontal inset. Goal previews
  lead: exactly two goals share the available width as equal square slots, while
  any other count retains the 96-point horizontal strip. The centered bold serif
  large-title name and centered current-level subtitle follow the previews, and
  the status-aware detail action remains last. Access, difficulty, current
  level, location, and future publication metadata appear only in the centered
  detail row.

## Difficulty

Difficulty is manually curated template metadata rather than a value calculated
from duration, checklist size, completion data, user behavior, or access tier:

- `Starter`: onboarding-oriented with familiar, commonly available targets.
- `Easy`: a focused trip reasonably completed in one ordinary field trip.
- `Moderate`: requires a specific habitat, longer effort, or subtler targets.
- `Hard`: specialized, time-dependent, or likely to require multiple field
  trips.

The standard Field trips catalog shows single-select `All`, `Starter`, `Easy`,
`Moderate`, and `Hard` pills after a leading `Filters` pill. The filter sheet
mirrors those difficulty choices and adds a single-select status group:
`Completed` for outings with completed progress, `In progress` for every started
but unfinished outing (including `0/N` progress), and `Incomplete` for unstarted
outings. Difficulty and status combine with AND semantics, and the pill counts
each non-default group once. Filtering remains local, preserves server ordering,
and never refetches. Reset returns both groups to `All`. All levels remain
available even when a level has no current trips. Seasonal Challenges are not
filtered. Rotating-free and Pro access rules never affect a template's
difficulty.

## Product Flow

1. A signed-in or ghost user opens Explore -> Field trips. The `Outings` segment
   loads first, and `Events` separately lists live and upcoming challenges.
2. `/field-trips` with `action: "catalog"` returns accessible and locked
   templates, their levels, checklist items, and any existing progress.
3. Opening a catalog card loads `action: "template_detail"` and shows one
   continuous detail page: overview, levels with goal-selected curated tips in
   the current incomplete level, the current start/continue/publish state,
   Community content, and unheaded outing-guidance cards at the bottom.
4. Backyard Safari Level 1 is already active from account enrollment. For other
   unstarted outings, tapping **Start outing** calls `action: "start"`. Matching
   scans never auto-start an outing. Standard outings never use Start/Publish
   Challenge copy; that language is reserved for Seasonal Events. An unfinished
   active outing can be stopped after confirmation; the backend saves its
   checklist, closes its activity period, and hides it from Capture and active
   profile summaries. **Resume outing** calls `action: "start"` and opens a new
   period. Destructive Reset clears only unfinished standard outing progress and
   returns the detail to its initial state.
5. The idle visual Scan page loads `action: "capture_context"` without blocking
   the camera. A new account receives Backyard Safari's unfinished Level 1
   goals; when unfinished standard goals exist, a `Goal: {target}` label is
   shown beneath the capture-mode picker with its outing title and aggregate
   level progress. When the context is successfully empty, iOS loads
   `template_detail` by the `backyard_safari` slug and offers an introduction
   only when that template is accessible and unstarted, such as after Reset.
6. Swiping an active indicator cycles through all unfinished targets in server
   order; tapping it opens the owning outing and focuses that goal's inline tip.
   The introduction has no swipe behavior and opens Backyard Safari detail
   without starting it.
7. An eligible live Capture includes the visibly selected standard goal as an
   optional `preferred_goal` in the scan-ingestion request. The ingestion intent
   stores the validated pair before model work begins. A database trigger then
   applies progress inside the scan insert transaction; a later
   confirmed/corrected identification re-enters the same transaction boundary.
   iOS still calls `action: "apply_scan_progress"` after persistence to obtain
   the stored result and support older ingestion paths.
8. The backend verifies scan ownership and requires the scan's capture timestamp
   to fall within one of the outing's activity periods before comparing it
   against the current unlocked level. One atomic RPC persists the preference,
   chooses at most one match per standard outing/Event, writes both progress
   families, evaluates the first-outing achievement, and saves an idempotency
   receipt. A failure rolls back the whole mutation. A later retry for the same
   scan revision returns the receipt, including the original unlock metadata.
9. The shared `ScanMilestoneCoordinator` waits for that progress attempt, sends
   typed, ID-bounded `AppEvent` invalidations, evaluates newly unlocked
   achievements without presenting them early, and batches the scan's
   notifications in strict order: standard outings in server order, Seasonal
   Challenges in server order, achievements in their existing order, then **New
   to Naturebook**. A progress failure or no-match response still releases later
   milestones after the attempt finishes.
10. iOS shows each qualifying progress toast for 3.5 seconds with the credited
    level's ring. Tapping a standard toast opens its outing focused on the first
    credited goal; tapping a challenge toast opens that challenge detail. The
    tap requests `AppRoute.captureGoal`; the root coordinator serializes it
    against any active sheet. The same progress events immediately invalidate
    affected Field trips data and the standard capture target context without
    creating a second plain toast. The banner is an alignment-scoped overlay, so
    interaction outside its visible bounds continues to reach the underlying UI.
11. Catalog and detail reloads associate each completed checklist item with the
    exact saved scan that completed it. iOS replaces that item's artwork with
    the scan thumbnail; completion order never determines which slot changes.
    Standard outing detail keeps one stable featured slot per selected goal.
    Before completion it uses that goal's curated illustrative species; after
    completion the exact item-to-scan link replaces the reference with the
    user's local visual. Selection takes up to six goals from the current active
    level in checklist order. A failed user source falls back to Naturebook,
    Wikipedia, then GBIF; a goal with no remaining source is removed and a
    same-level reserve goal refills it.
12. Tapping a completed goal whose scan still exists on the device pushes the
    existing Insight view inside Explore. The back arrow and swipe-back gesture
    return to the same outing sheet.
13. Reopening a saved biological Insight loads `action: "scan_contributions"`. A
    nonempty result renders the persistent progress card; failures and empty
    results stay silent.
14. Once all levels are complete, **Publish outing** creates a Field trip
    snapshot with an editable title and optional description or AI summary.
15. After the detail refreshes, its title badge changes from **Private** to
    **Published**. Deleting the publication returns it to **Private**.
16. Published Field trips appear on public profiles and template Community
    previews. They open `FieldTripPublicationDetailView` with item cards, likes,
    comments, and author identity. Author taps open the existing Explore
    author-profile route.

## Active Target on Scan

The capture indicator is orientation and motivation, not a scan requirement. It
never changes which experiences are eligible. For an eligible live visual
Capture, however, its selected standard goal wins ties inside that outing; all
other experiences still use deterministic specificity and checklist ranking.

The canonical source-agnostic ownership, caching, navigation, security, and
future-source decision is
[`active-capture-goal-context.md`](../rfcs/active-capture-goal-context.md).

The selected goal is captured when eligible camera media is staged and survives
both foreground and background completion. Active V50 keeps the two IDs in a
scan-keyed `OfflineQueuedScanGoalHint` companion rather than changing the
released V49 queue entity. V49→V50 migration creates no hint for an existing
queue row because V49 persisted no selected-goal source value; only a qualifying
capture running V50 or later may insert the companion. Successful queue
finalization preserves the hint as a durable progress outbox until a successful
or terminal acknowledgement; explicit cancellation and terminal orphan cleanup
remove it. Insight contributions are not cached in SwiftData; reopening the
saved biological scan always reads the private server projection.

Presentation contract:

- Show only when Field trips are enabled, Scan/visual mode is selected, a real
  target or validated introduction exists, the local `showsCaptureGoalProgress`
  preference is enabled, the staged-capture tray is empty, refinement is
  inactive, and video is not recording.
- Show no loading placeholder when there is no complete cached context. Camera
  startup and capture remain independent from both requests. A template-detail
  failure preserves the last complete snapshot and never fabricates an
  introduction.
- Render compact beside `MediaModeToggle`: the 50-point artwork circle shares
  its vertical centerline on the right while the 200-point selector remains
  centered on screen. Use the established 32-point trailing workspace margin
  when space permits and reduce it only enough to maintain an 8-point
  inter-control gap on narrow phones. Use 42-point bundled goal artwork in the
  compact circle and the neutral binoculars symbol for unknown goals. The
  50-point surface remains above the 44-point minimum touch target. Tapping
  artwork moves and expands one continuous surface to the full goal row beneath
  the selector; its leading control returns to 56 points with 36-point artwork.
  iOS 26 and later use untinted interactive native Liquid Glass, while earlier
  supported versions use a neutral material fallback. Foreground styles remain
  semantic.
- In expanded form, center the `Goal: {target}` prompt and outing title between
  equal 56-point artwork and up-chevron slots. Preserve the curated target text
  exactly; the colon avoids article and plurality errors for composite or
  mass-noun prompts. Compact form contains artwork only, without a progress rim,
  count badge, or disclosure glyph.
- Tapping compact artwork expands beneath the selector; tapping expanded artwork
  or the trailing up-chevron collapses it back onto the selector row. Tapping
  the centered expanded region opens the outing. The expansion choice lasts
  through goal changes, root sheets, foregrounding, and temporary Capture
  suppression. Leaving visual Scan, changing or signing out of an account, or
  disabling the setting resets it to compact.
- Swipe left for the next unfinished target and right for the previous target on
  either compact or expanded surfaces. Selection wraps across every active
  standard outing. The gesture commits only after 36 points of translation and
  only when horizontal movement is at least 1.25 times vertical movement,
  preserving camera and capture-page gestures.
- Opening uses a light sheet haptic; expansion, collapse, and selection use
  selection haptics. All respect the global haptics and Expedition mode gates.
  Reduced Motion makes the size transition immediate. Compact VoiceOver exposes
  goal, outing, progress, Expand, and adjustable previous/next actions. Expanded
  artwork and the trailing chevron expose Collapse; the centered region exposes
  Open and the adjustable actions.
- Settings > Workspace exposes an on-by-default **Field trip goals** toggle with
  the `binoculars.fill` symbol. Turning it off removes the entire target capsule
  from Scan without changing outing progress, cached goal context, or server
  state.
- For the validated unstarted Backyard Safari zero state after Reset, use the
  same compact/expanded treatment. Rotate Bird and Dog artwork by cross-fade
  every three seconds in either size; Reduce Motion keeps the first static.
  Expanded content shows **Start an outing**, **Backyard Safari · 2 goals**, and
  the trailing collapse chevron. The introduction never changes goals by swipe
  or VoiceOver adjustment; artwork and the chevron collapse it, while its
  centered content opens outing detail.

Capture uses a source-agnostic domain boundary. `FieldTripCaptureGoalProvider`
flattens the server-ordered outing response into `CaptureGoal` values containing
only prompt, source label, aggregate progress, safe artwork, and a typed
destination. `ActiveCaptureGoalStore` is app-injected observable state; it
preserves a surviving selection after refresh, chooses the next surviving goal
when the current item completes, and wraps in both directions. The last
successful generic payload, selection, and refresh date are stored in a
versioned `UserDefaults` cache under an account-specific key. Switching Supabase
accounts clears the in-memory state before reading that account's cache.

Capture must not import Field trip response DTOs, reconstruct access/unlock
rules, or know Explore's internal route fields. New goal-producing features add
an explicit `CaptureGoalSourceKind`, a `CaptureGoalContextProviding` adapter,
and a compiler-checked `CaptureGoalDestination` case. The backend or provider
continues to own eligibility and presentation order.

Indicator impressions, opens, and previous/next actions are measured with a
single `CaptureGoalIndicator` telemetry event. Its only feature properties are
the coarse `action` and `source` kind. It must never include prompts, goal or
outing IDs/titles, progress values, route IDs, or account identifiers.

Refresh behavior:

- refresh through the five-minute freshness gate when Capture first appears or
  the Supabase account is restored/changed;
- refresh after five stale minutes when the app returns to the foreground or the
  user returns to visual Scan;
- force refresh after outing start/join, standard progress events, and explicit
  scanner-routing events;
- share one provider fetch when appearance, account restoration, and scene
  activation overlap at startup;
- coalesce overlapping invalidations into one follow-up refresh; and
- retain cached content without surfacing an error if refresh fails.

Tapping the indicator passes its typed `CaptureGoalDestination` into Explore.
Explore presents the Field trips tab, opens the owning standard outing, selects
the matching goal tile, and reveals and scrolls to its tips without adding
separate tip-container highlight chrome. A future goal without guide content
falls back to its highlighted goal tile. The destination is converted at the
Explore boundary by `ExploreFieldTripNavigationPolicy` into
`FieldTripTemplateRoute`, whose declaration lives with Field Trips in
`Models/FieldTripRoutes.swift` and whose focused checklist-item identifier
remains optional for ordinary outing navigation. Guide, goal, and Event
highlight timers are stored per detail view, cancelled when replaced, and
released on disappearance. Their delayed fade cannot retain a dismissed scroll
proxy or clear a newer highlight.

## Challenge Flow

1. `/field-trips` with `action: "challenges_catalog"` returns live, upcoming,
   and ended curated challenges with schedule, aggregate counts, access state,
   suggested hashtags, and viewer participation summary.
2. Opening a challenge loads `action: "challenge_detail"` with linked template
   guide context, schedule, aggregate counts, viewer progress, completion badge
   state, and initial published entries.
3. Tapping Join calls `action: "join_challenge"`. The backend starts or
   continues the linked Field trip, then creates or returns the separate
   challenge participation row.
4. New scans after `joined_at` and before `ends_at` can complete items for the
   current challenge level. Normal Field trip progress continues independently.
5. Completing all challenge levels awards a profile-visible badge that exposes
   no private evidence.
6. A completed participant may publish a challenge entry snapshot. Challenge
   entries have their own detail page, item cards, likes, and comments, and are
   distinct from normal `field_trip_publications`.
7. When a scan completes a live joined challenge item, the Explore composer may
   suggest the challenge's normalized hashtags through `eventHashtags`. Tags are
   never preselected, required, persisted as private evidence, or auto-posted.

## Progress Rules

- Progress is server-authoritative.
- Only scans owned by the requesting user can count.
- Backyard Safari's first eligible activity window begins at account enrollment
  (or migration-time enrollment for an existing account), so earlier scans are
  never credited retroactively.
- A standard scan counts only when its capture timestamp falls within one of the
  outing's `user_field_trip_active_periods`. Pre-stop scans can receive late
  approval; scans captured during stopped gaps stay excluded after Resume.
- A delayed first upload uses that scan timestamp even if the activity period
  has since closed. Existing credit in an unfinished outing remains
  correctable/removable after the template or outing is hidden or deactivated;
  that does not authorize new credit outside the original scan-time period.
- Reset removes all prior periods, preventing historical scans from rebuilding
  cleared progress until the outing is explicitly started again.
- Matching is limited to the current unlocked level. Later levels cannot fill
  early.
- Eligibility is media-kind agnostic after a scan is saved and has a resolved
  biological identification. An unreviewed AI identification must be at least a
  `Possible match` for the exact inference tier (`Flash >= 0.75`,
  `Pro >= 0.65`). A weaker identification remains uncredited until the user
  confirms it or a correction/community resolution supplies a confirmed species.
  A qualifying photo or video can count; the camera-only active-target capsule
  does not restrict progress eligibility.
- One scan is evaluated against every eligible active standard outing, but it
  receives at most one checklist credit per outing. It may still advance several
  eligible active outings and a joined live Event.
- Within an experience the selected live-Capture goal wins when valid. Fallback
  order is exact species, scientific name, taxonomy from genus through kingdom,
  taxonomy with an excluded family, conjunctive taxonomy-plus-signal, semantic
  tag, ecology, habitat, then curated checklist order and item ID.
- A checklist item can complete once. Reprocessing the same scan is idempotent.
- A level unlocks only when all items in the current level are complete.
- A trip completes when all levels and checklist items are complete.
- Progress responses retain the existing current-level fields and add optional
  `credited_*` fields for the level changed by the scan. When completion
  advances to another level, the credited counts describe the just-completed
  level so scan feedback shows a full ring rather than the next level's `0/N`.
- A progress toast requires a nonempty `newly_completed_items` array. The first
  item in curated checklist order supplies its common name, with the checklist
  prompt as the empty/missing-name fallback and as the focused standard route.
- Progress is server-owned, not best effort from iOS. New ingestion applies it
  in the scan transaction, and the post-persistence Edge call retrieves the
  durable receipt for UI feedback. The client retains its queued Capture hint
  until success or a terminal server response and replays orphaned hints after
  relaunch. Catalog reloads remain a read-side reconciliation path.
- Corrections may move or remove the scan's credit within its original credited
  level while the outing remains unfinished, then reset the outing to its
  earliest incomplete level. Completed outings are immutable for normal
  identification corrections. Evidence-policy invalidation is stricter: if a
  confidence, inference-tier, or review revision makes the contributing scan
  weak and unconfirmed, its credit is removed even from a completed outing.

### Identification Evidence Policy

The database applies this policy before standard-outing or Event goal matching.
The boundaries are inclusive and mirror the tier-specific **Possible match**
presentation thresholds:

| Inference tier     | Automatic-credit minimum | Below the boundary                     |
| ------------------ | -----------------------: | -------------------------------------- |
| Flash              |             `0.75` (75%) | Pending review; no automatic credit    |
| Pro                |             `0.65` (65%) | Pending review; no automatic credit    |
| Missing or unknown |             `0.75` (75%) | Fail closed to the stricter Flash rule |

A null or out-of-range model score never auto-qualifies. The score is bypassed
only when `user_confirmed_identification` is true or `confirmed_species_id` is
populated by a correction or community resolution. The scan must still be
caller-owned, saved, biological, not tombstoned, and match all timing,
current-level, and checklist criteria.

`preferred_goal` is only a ranking hint. For a weak unreviewed scan, the atomic
receipt retains the complete hint but returns empty standard/Event updates. A
later confirmation changes the scan revision, validates the pending hint, and
can credit the original selected goal without another model request.

If qualifying evidence is later downgraded below the boundary and has no
confirmation/resolution override, the evidence-change trigger removes its
standard and Event completions, reopens the earliest incomplete level, clears
derived Event badges, and soft-deletes completion publications/entries. The
selected-goal preference remains pending. This reconciliation returns no
`newly_completed_items`, so it cannot produce a progress celebration.

### Active Objective Matching Contract

This table is the canonical review surface for the two active standard outings.
The retired Forest Edges placeholder is not returned by active-template or
Capture RPCs and is intentionally excluded. A populated taxonomy rank is an
exact, case-insensitive constraint. `taxonomy_and_signal` requires at least one
taxonomy constraint, at least one signal constraint, and every populated
constraint to match; missing required evidence fails closed.

| Outing           | Level | Goal                   | Server-required match                                                            |
| ---------------- | ----: | ---------------------- | -------------------------------------------------------------------------------- |
| Backyard Safari  |     1 | Bird                   | Class `Aves`                                                                     |
| Backyard Safari  |     1 | Dog                    | Exact scientific name `Canis lupus familiaris`                                   |
| Backyard Safari  |     2 | Butterfly              | Class `Insecta` + order `Lepidoptera` + semantic category `butterfly`            |
| Backyard Safari  |     2 | Cat                    | Exact scientific name `Felis catus`                                              |
| Backyard Safari  |     2 | Spider                 | Class `Arachnida` + order `Araneae`                                              |
| Backyard Safari  |     2 | Flowering plant        | Kingdom `Plantae` + semantic category `flower`                                   |
| Backyard Safari  |     3 | Fungus                 | Kingdom `Fungi`                                                                  |
| Backyard Safari  |     3 | Insect                 | Class `Insecta`                                                                  |
| Backyard Safari  |     3 | Urban wild animal      | Kingdom `Animalia` + scan ecology `urban`                                        |
| Backyard Safari  |     3 | Moss or lichen         | Semantic category `moss` only; there is no broad taxonomy fallback               |
| Park Pollinators |     1 | Flowering plant        | Kingdom `Plantae` + semantic category `flower`                                   |
| Park Pollinators |     1 | Butterfly or moth      | Class `Insecta` + order `Lepidoptera`                                            |
| Park Pollinators |     2 | Bee or wasp            | Class `Insecta` + order `Hymenoptera` + either semantic category `bee` or `wasp` |
| Park Pollinators |     2 | Fly                    | Class `Insecta` + order `Diptera`                                                |
| Park Pollinators |     2 | Beetle                 | Class `Insecta` + order `Coleoptera`                                             |
| Park Pollinators |     2 | Spider                 | Class `Arachnida` + order `Araneae`                                              |
| Park Pollinators |     3 | Seed or fruiting plant | Kingdom `Plantae` + semantic category `fruit`                                    |
| Park Pollinators |     3 | Bird                   | Class `Aves`                                                                     |
| Park Pollinators |     3 | Wild plant             | Kingdom `Plantae` + scan ecology `wild`                                          |
| Park Pollinators |     3 | Meadow plant           | Kingdom `Plantae` + habitat token/category `meadow`                              |

Semantic categories come from the resolved species' enriched `group_tags`, with
the existing exact scientific/common-name fallback. Compound semantic criteria
may use `|` for accepted alternatives; **Bee or wasp** uses `bee|wasp`. Ecology
is observation-level `scans.ecology_type`. Habitat is species-level
`species_dictionary.habitat_description` or an exact group category, not proof
of scene composition in the captured image. For that reason, Park's former
**Spider near flowers** and **Bird near flowers** labels are now **Spider** and
**Bird**, and the former scene-based **Pollinator habitat** objective is the
verifiable **Meadow plant** objective.

The `Moss or lichen` row deliberately documents the current conservative legacy
rule: moss can complete it, while an otherwise unmatched lichen cannot. That is
a false-negative limitation, not a broad-completion path; widening it requires
an explicit reviewed alternative and positive/negative database cases.

### Featured Reference Species Catalog

These species are visual examples only. They never narrow or otherwise alter the
matching criteria above. `field-trips/referenceMedia.ts` is the executable
source of truth and must change with this table.

| Outing           | Goal                   | Illustrative species                                    |
| ---------------- | ---------------------- | ------------------------------------------------------- |
| Backyard Safari  | Bird                   | House Sparrow (`Passer domesticus`)                     |
| Backyard Safari  | Dog                    | Domestic Dog (`Canis lupus familiaris`)                 |
| Backyard Safari  | Butterfly              | Monarch (`Danaus plexippus`)                            |
| Backyard Safari  | Cat                    | Domestic Cat (`Felis catus`)                            |
| Backyard Safari  | Spider                 | Cross Orbweaver (`Araneus diadematus`)                  |
| Backyard Safari  | Flowering plant        | Common Daisy (`Bellis perennis`)                        |
| Backyard Safari  | Fungus                 | Turkey Tail (`Trametes versicolor`)                     |
| Backyard Safari  | Insect                 | Seven-spotted Lady Beetle (`Coccinella septempunctata`) |
| Backyard Safari  | Urban wild animal      | Eastern Gray Squirrel (`Sciurus carolinensis`)          |
| Backyard Safari  | Moss or lichen         | Silvergreen Bryum Moss (`Bryum argenteum`)              |
| Park Pollinators | Flowering plant        | Common Dandelion (`Taraxacum officinale`)               |
| Park Pollinators | Butterfly or moth      | Monarch (`Danaus plexippus`)                            |
| Park Pollinators | Bee or wasp            | Western Honey Bee (`Apis mellifera`)                    |
| Park Pollinators | Fly                    | Common Drone Fly (`Eristalis tenax`)                    |
| Park Pollinators | Beetle                 | Seven-spotted Lady Beetle (`Coccinella septempunctata`) |
| Park Pollinators | Spider                 | Cross Orbweaver (`Araneus diadematus`)                  |
| Park Pollinators | Seed or fruiting plant | Wild Strawberry (`Fragaria vesca`)                      |
| Park Pollinators | Bird                   | House Sparrow (`Passer domesticus`)                     |
| Park Pollinators | Wild plant             | Common Yarrow (`Achillea millefolium`)                  |
| Park Pollinators | Meadow plant           | Red Clover (`Trifolium pratense`)                       |

Template detail batches these scientific names through the normalized public
species layer and returns at most one image for each provider in Naturebook,
Wikipedia, then GBIF order. When that cache has no usable image for a goal in
the current level, the Field trips data layer calls the shared bounded external
enrichment helper and adds its public Wikipedia/GBIF candidates. Runtime
fallback is capped at the six carousel-eligible active goals and three
concurrent provider lookups; a provider outage never fails the otherwise valid
detail response. Release content QA should still keep normalized candidates warm
so the fallback remains exceptional rather than adding routine latency.

## Challenge Progress Rules

- Challenge participation is explicit and private by default.
- Only scans owned by the requesting user can count.
- Only scans created at or after `field_trip_challenge_participants.joined_at`
  and at or before `field_trip_challenges.ends_at` can count.
- A delayed upload captured inside that window may receive its first credit
  after the Event ends. Existing credit in an unfinished participation remains
  correctable/removable after the challenge or participation is hidden or
  deactivated.
- Matching is limited to the participant's current challenge level. Later
  challenge levels cannot fill early.
- One qualifying scan can complete at most one matching item in that current
  challenge level. The same saved scan may also satisfy one item in each
  eligible standard outing; challenge and standard completion rows remain
  separate even when they reference the same scan.
- Challenge item completions are keyed by participation and checklist item; they
  do not retroactively satisfy or overwrite normal Field trip item completions.
- Reprocessing the same scan is idempotent.
- Corrections may move or remove credit from an unfinished Event's original
  credited level. Completed Events are immutable.
- The badge award is server-authoritative and occurs only after challenge
  completion.

## Privacy Model

Active Field trip progress is visible on public profiles by default, but it is
status-only:

- template title
- current level
- completed count
- target count

Automatic Backyard Safari enrollment creates this profile-visible active status
immediately, including at `0/N` progress. A known account ID therefore normally
satisfies the author-profile visibility gate until the unfinished starter is
stopped or reset; the profile endpoint does not enumerate account IDs.

Active profile summaries must not expose scan IDs, media URLs, field notes,
exact coordinates, public location labels, or private evidence details.

The authenticated `catalog` and `template_detail` responses are a separate,
private viewer-specific read model. A completed standard checklist item may
include `completed_scan_id`, but it never includes a media URL. iOS uses the ID
only to find the caller's device-local `LocalScanRecord` and render the same
`ScanThumbnail` used elsewhere. If that record is unavailable on the device, the
curated artwork remains and the app must not construct a remote or public
evidence URL. `completed_scan_id` must not appear in public profile summaries,
publication snapshots, challenge badges or entries, Explore feed/map payloads,
or the capture-context response. The private outing-detail carousel uses this
same local-record boundary for user evidence, but it may also render the goal's
reusable public species-reference projection. Reference rows contain only an
illustrative scientific/common name, sanitized URL, source, rights metadata,
optional public attribution, and image dimensions. They never contain the
completing scan ID, scan media URL, user notes, or location provenance. When a
goal completes, only a matching device-local `LocalScanRecord` can replace its
reference; the app never constructs a remote evidence URL.

The detail-only publication status is also private viewer metadata.
`active_progress.publication_id` and `published_at` identify the owner's active,
non-deleted public snapshot; missing values mean the detail badge is
**Private**. The badge describes publication state, not whether the status-only
active progress summary is allowed on a public profile. It never makes
completion evidence public.

The Scan capture-context payload is even narrower: it contains only field trip
and template identifiers, title/slug, current-level metadata, aggregate counts,
and unfinished item identifiers/prompts/order/guide availability. It must never
return scan IDs, media, coordinates, location labels, field notes, completed
species names, or completion evidence. Seasonal Challenge-specific progress is
excluded; the shared underlying standard field trip remains eligible.

Published Field trip pages are explicit snapshots stored separately from Explore
posts. Publication items may include species names, taxonomy, reference images,
and selected scan media snapshots, but publishing a Field trip does not create
Explore feed posts, Explore map points, normal Explore post notifications, APNs,
widgets, or public web pages. Field trip-only in-app activity rows for comments,
replies, and followed-author publications may appear in Explore activity and
increment the bell, but they never fan out to push delivery.

Public author profiles can be discoverable through either visible Explore posts
or visible Field trip surfaces. Field trip discoverability still respects
shadowbans and mutual blocks. Because the starter enrollment is profile-visible,
most known accounts have a visible Field trip surface by default.

Challenge participation exposes only aggregate counts unless the user explicitly
publishes a challenge entry or displays a completion badge. Badges do not expose
scan IDs, media URLs, exact locations, field notes, or private evidence.
Challenge entries are public snapshots scoped to Field trips; they do not create
Explore posts, Explore map rows, APNs, widgets, public web pages, or automatic
Explore hashtags.

## Backend

Field trip storage is created by
`services/supabase/migrations/20260708021110_field_trips_v1.sql`, extended by
`services/supabase/migrations/20260708033451_field_trips_v2.sql`, and expanded
for Community discovery by
`services/supabase/migrations/20260708042713_field_trips_v3_community.sql`.
Seasonal challenges are added by
`services/supabase/migrations/20260708051414_field_trips_v4_challenges.sql`.
Structured objective guidance is added by
`services/supabase/migrations/20260717150222_contextual_outing_objective_guides.sql`.
The private capture read model is added by
`services/supabase/migrations/20260717195751_active_outing_capture_context.sql`,
and its standard-field trip behavior after a challenge join is finalized by
`services/supabase/migrations/20260717213641_preserve_standard_outings_in_capture_context.sql`.
The Forest Edges placeholder is retired without deleting historical data by
`services/supabase/migrations/20260717224544_retire_forest_edges_outing.sql`.
Private catalog/detail completion evidence links are added by
`services/supabase/migrations/20260718043218_expose_field_trip_completion_scan_ids.sql`.
That migration also restricts both RPCs to `service_role`; authenticated iOS
clients continue to access them only through `/field-trips`. Private detail
publication status is added by
`services/supabase/migrations/20260718051748_expose_field_trip_publication_status.sql`.
Credited-level scan progress for standard outings and Seasonal Challenges is
added by
`services/supabase/migrations/20260718150932_add_credited_field_trip_progress.sql`.
It replaces the two progress RPC bodies without changing their signatures,
security-definer/search-path contract, or existing execute permissions.
`services/supabase/migrations/20260718162409_scope_credited_progress_to_current_attempt.sql`
then scopes the credited level to checklist items matched by the current
application attempt, including re-identification after level advancement.
`services/supabase/migrations/20260719160750_field_trip_lifecycle_controls.sql`
adds private activity periods, Stop/Reset lifecycle RPCs, stopped-progress
projection, Resume period creation, and capture-time progress gating.
`services/supabase/migrations/20260722025411_persistent_field_trip_scan_contributions.sql`
adds one-credit-per-scan uniqueness, deterministic selection, private Capture
preferences, correction invalidation, and the scan-specific contribution read
model. Its guarded data migration deduplicates only existing credit and aborts
when completed or published artifacts exist.
`services/supabase/migrations/20260722064704_harden_atomic_field_trip_progress.sql`
adds a private scan-revision receipt, the atomic standard/Event/preference/
achievement mutation, ingestion/correction triggers, and a publication runtime
repair. It also replaces profile pinning's temporary-table implementation with
an ordered UUID-array mutation and revokes every Field trip/Event
`SECURITY DEFINER` function from `PUBLIC`, `anon`, and `authenticated`, granting
execution only to `service_role`.
`services/supabase/migrations/20260722195453_exclude_ants_from_bee_wasp_goal.sql`
excludes the ant family from Park Pollinators' Hymenoptera objective and repairs
earlier ant-backed credit.
`services/supabase/migrations/20260722211636_tighten_field_trip_goal_matching.sql`
adds conjunctive taxonomy-plus-signal rules for active objectives, requires
`Araneae` for Spider goals and a butterfly tag for Backyard Butterfly, aligns
contextual Park labels with evidence the scan contract can verify, and repairs
credit that no longer matches.
`services/supabase/migrations/20260730023042_gate_field_trip_progress_by_confidence.sql`
adds the tier-specific Possible-match evidence policy to standard outings and
Events, includes confidence/confirmation fields in scan receipt revisions,
re-evaluates confirmation-only updates, removes credit previously issued to weak
unreviewed identifications, and reconciles future confidence downgrades even
after completion. Selected Capture-goal preferences remain pending so later
confirmation can still honor the user's intent.

Core tables:

- `field_trip_templates`
- `field_trip_levels`
- `field_trip_checklist_items`
- `user_field_trips`
- `user_field_trip_item_completions`
- `user_field_trip_active_periods`
- `field_trip_scan_goal_preferences`
- `field_trip_scan_progress_receipts`
- `field_trip_publications`
- `field_trip_publication_items`
- `field_trip_publication_likes`
- `field_trip_publication_comments`
- `field_trip_activity_notifications`
- `field_trip_challenges`
- `field_trip_challenge_participants`
- `field_trip_challenge_item_completions`
- `field_trip_challenge_badges`
- `field_trip_challenge_entries`
- `field_trip_challenge_entry_items`
- `field_trip_challenge_entry_likes`
- `field_trip_challenge_entry_comments`

Core RPCs and helpers:

- `public.get_field_trip_catalog(...)`
- `public.get_field_trip_template_detail(...)`
- `public.get_field_trip_capture_context(...)`
- `public.start_field_trip(...)`
- `public.stop_field_trip(...)`
- `public.reset_field_trip(...)`
- `public.get_stopped_field_trip_progress(...)`
- `public.get_field_trip_community_publications(...)`
- `public.get_recent_field_trip_publications(...)`
- `public.apply_field_trip_scan_progress(...)`
- `public.apply_field_trip_scan_progress_v2(...)`
- `public.apply_field_trip_scan_progress_atomic(...)`
- `public.get_field_trip_scan_contributions(...)`
- `public.get_field_trip_profile_summaries(...)`
- `public.set_field_trip_pinned_publications(...)`
- `public.publish_field_trip(...)`
- `public.get_field_trip_publication_detail(...)`
- `public.get_field_trip_comments(...)`
- `public.can_view_field_trip_publication(...)`
- `public.user_has_visible_field_trip_profile(...)`
- `public.get_field_trip_challenges_catalog(...)`
- `public.get_field_trip_challenge_detail(...)`
- `public.join_field_trip_challenge(...)`
- `public.apply_field_trip_challenge_scan_progress(...)`
- `public.get_field_trip_challenge_hashtags_for_scan(...)`
- `public.get_field_trip_challenge_publications(...)`
- `public.publish_field_trip_challenge_entry(...)`
- `public.get_field_trip_challenge_entry_detail(...)`
- `public.get_field_trip_challenge_entry_comments(...)`
- `public.get_field_trip_challenge_badges(...)`

The migration also extends `public.get_explore_author_profile(...)` so Field
Trips can participate in public-profile discoverability without exposing raw
scan evidence.

## Edge API

`services/supabase/functions/field-trips` is an action-based Edge Function. It
uses `withEdgeHandler` for user identity and rejects caller-supplied ownership
fields.

Actions:

- `capture_context`: returns the caller's incomplete, non-hidden, accessible
  standard field trips and unfinished current-level targets. Field trips order
  by most recent start or item completion; targets retain curated checklist
  order. The RPC is revoked from `PUBLIC`, `anon`, and `authenticated`, and
  granted only to `service_role`; the authenticated Edge Function supplies the
  verified user ID.
- `catalog`: returns active templates, gated access state, levels, checklist
  items, and the viewer's progress. Completed standard items may include the
  private `completed_scan_id` needed for device-local evidence thumbnails.
- `template_detail`: returns one template with guide fields, levels, checklist
  tips, access state, viewer progress, and the same optional private completion
  scan ID. Its `active_progress` also includes the owner's optional active
  `publication_id` and `published_at` for the title badge.
- `start`: starts another accessible outing, or unhides/resumes an existing
  stopped or reset progress row. New accounts already have Backyard Safari Level
  1 active.
- `stop`: closes an unfinished outing's open period and returns its saved
  stopped detail.
- `reset`: clears unfinished, unpublished standard progress without deleting the
  shared outing row or Seasonal Challenge data.
- `community_publications`: returns visible published completed Field trips for
  `smart`, `following`, or `recent` mode with optional template filtering and
  stable `(rank_bucket, published_at, publication_id)` pagination.
- `recent_publications`: compatibility alias for `community_publications` with
  `mode: "recent"`.
- `apply_scan_progress`: applies progress for one saved scan owned by the caller
  through one transactional database RPC. V4 keeps the existing `data` payload
  for normal Field trip progress and adds optional `challenge_updates` for
  joined live challenges. Both update arrays may include optional
  `credited_level_number`, `credited_level_title`, `credited_completed_count`,
  `credited_target_count`, and `removed_item_ids`. The request may include an
  optional validated `preferred_goal` with `user_field_trip_id` and `item_id`.
  New scan ingestion may already have applied the mutation; in that case this
  action returns the scan-revision receipt rather than re-announcing or
  partially reapplying it.
- `scan_contributions`: returns one private, evidence-minimal row for every
  standard outing or Event credit owned by the supplied saved biological scan.
- `challenges_catalog`: returns curated seasonal challenges with viewer
  participation summary and aggregate counts.
- `challenge_detail`: returns one challenge, linked template guide context,
  schedule, suggested hashtags, viewer progress, aggregate counts, and initial
  published challenge entries.
- `join_challenge`: explicitly joins a live accessible challenge and
  starts/continues the linked Field trip.
- `challenge_publications`: paginates visible published challenge entries by
  `(published_at DESC, entry_id DESC)`.
- `scan_challenge_hashtags`: returns normalized suggested challenge hashtags for
  a scan that completed joined live challenge items.
- `publish_challenge_entry`: snapshots a completed challenge participation into
  challenge entry tables.
- `challenge_entry_detail`: returns a visible challenge entry detail page.
- `set_challenge_entry_like`: idempotently sets the viewer's challenge entry
  like state.
- `challenge_entry_comments`: returns paginated challenge entry comments.
- `create_challenge_entry_comment`: creates a challenge entry comment or
  one-level reply.
- `profile_summaries`: returns active status-only and published summaries for a
  public profile, including a separate `pinned` list.
- `set_pinned_publications`: replaces the caller's pinned published Field trip
  IDs, capped at 3.
- `publish`: snapshots a completed trip into Field trip publication tables.
- `detail`: returns a visible publication detail page.
- `set_like`: idempotently sets the viewer's Field trip like state.
- `comments`: returns paginated Field trip comments.
- `create_comment`: creates a Field trip comment or one-level reply.

See `services/supabase/functions/field-trips/README.md` and
`docs/backend-and-data/05-api-contracts.md` for payload examples.

Every Field trip/Event `SECURITY DEFINER` database function is revoked from
`PUBLIC`, `anon`, and `authenticated` and granted only to `service_role`. The
authenticated Edge Function supplies the verified user ID, so callers cannot
invoke ownership-bearing RPCs directly or request another user's progress,
publication, or completion evidence.

## Access

Free users see starter and rotating-free trips. Functional Pro users—paid Pro or
an online-verified complimentary account with at least one credit or active
hold—can access the full active catalog. Locked Pro trips may still appear in
the catalog so the UI can show the available upgrade path without starting
progress. Exhausted complimentary access falls back to the free catalog; public
Profile and Explore Pro badges remain paid-only.

Access is evaluated from server-side user state. The iOS catalog should treat
`viewerHasAccess` / `accessKind` as display and start eligibility hints, not as
authorization.

Challenge access is server-authoritative and independent from the linked
template's normal catalog access. A challenge can be free, Pro-only, or
temporarily free during its challenge window.

Database gates resolve effective entitlement rather than reading raw
`subscription_tier` as the complete access decision. `pro_trial` remains
historical after the atomic cutover. See
[Three Complimentary Pro Scans](../backend-and-data/18-complimentary-pro-scans.md).

## iOS Implementation

The feature-local ownership contract lives in
`apps/ios/Merian/Features/Explore/FieldTrips/README.md`. Production code is
split by responsibility:

- `Models/` owns UI-only catalog, detail, date, artwork, featured-media,
  publication, and profile presentation policy. Codable Field trip DTOs and wire
  compatibility remain in `Core/Network/FieldTripAPIModels.swift`.
- `Services/` is the only feature layer that creates live `MerianNetworkClient`
  closures. It also owns the capture-goal adapter and the typed outing/Event
  publication and publish endpoints.
- `ViewModels/` owns main-actor observable catalog, outing-detail, Event-detail,
  active-profile, publish-form, and published-content interaction state through
  initializer-injected dependency values.
- `Views/` owns screens, route-compatible wrappers, and animation-sensitive
  selection, gallery, focus, scroll-proxy, and highlight state.
- `Components/` owns catalog, detail, media, publication, profile, and shared UI
  without calling the network client directly.

`FieldTripPublishedContent` normalizes outing publications and Event entries for
one detail renderer and interaction view model while
`FieldTripPublishedContentEndpoint` preserves their distinct network actions.
`FieldTripPublishForm` and `FieldTripPublishViewModel` similarly share form
behavior through typed `FieldTripPublishEndpoint` values. The existing
`FieldTripPublicationDetailView` and `FieldTripChallengeEntryDetailView`
initializers remain thin compatibility wrappers.

This organization is an iOS-only parity boundary. It does not change JSON
payloads, Edge actions, wire DTOs, SwiftData or persistence schemas, feature
flags, routes, lifecycle behavior, or Outings/Events semantics. Production Field
Trips Swift files remain below 600 lines.

Primary files:

- `apps/ios/Merian/Features/Explore/FieldTrips/README.md`
- `apps/ios/Merian/Features/Explore/FieldTrips/Models/`
- `apps/ios/Merian/Features/Explore/FieldTrips/Services/`
- `apps/ios/Merian/Features/Explore/FieldTrips/ViewModels/`
- `apps/ios/Merian/Features/Explore/FieldTrips/Views/`
- `apps/ios/Merian/Features/Explore/FieldTrips/Components/`
- `apps/ios/Merian/Features/Capture/Shell/Views/CaptureWorkspaceView.swift`
- `apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel+Routing.swift`
- `apps/ios/Merian/Features/Capture/Shell/Modifiers/CameraSheetRouter.swift`
- `apps/ios/Merian/Core/AppDIContainer.swift`
- `apps/ios/Merian/Core/Models/CaptureGoalContext.swift`
- `apps/ios/Merian/Core/Network/FieldTripAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Core/UI/Feedback/AchievementToastPresenter.swift`
- `apps/ios/Merian/Core/UI/Feedback/AchievementToastBanner.swift`
- `apps/ios/Merian/Core/Utilities/AppEventPublisher.swift`
- `apps/ios/Merian/Core/Utilities/AppRouteCoordinator.swift`
- `apps/ios/Merian/Core/AI/InferenceEngine.swift`
- `apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+URLSession.swift`
- `apps/ios/Merian/Features/Explore/Shell/Views/ExploreView.swift`
- `apps/ios/Merian/Features/Explore/Shell/Models/ExploreShellNavigationModels.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripRoutes.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Views/ProfileTabView.swift`
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileContent.swift`

Important model types:

- `FieldTripTemplate`
- `FieldTripCaptureContextResponse`
- `FieldTripCaptureOuting`
- `FieldTripCaptureTarget`
- `FieldTripCaptureGoalProvider`
- `CaptureGoal`
- `CaptureGoalDestination`
- `ActiveCaptureGoalStore`
- `FieldTripLevel`
- `FieldTripChecklistItem`
- `FieldTripProgress`
- `FieldTripProgressUpdate`
- `FieldTripMilestonePayload`
- `ScanMilestoneCoordinator`
- `FieldTripProfileSummaries`
- `FieldTripPublicationDetail`
- `FieldTripPublicationItem`
- `FieldTripChallenge`
- `FieldTripChallengeParticipation`
- `FieldTripChallengeProgressUpdate`
- `FieldTripChallengeBadge`
- `FieldTripChallengeEntry`
- `FieldTripChallengeEntryDetail`
- `FieldTripChallengeEntryItem`
- `FieldTripGoalArtwork`
- `FieldTripDisplayDate`
- `FieldTripPublishedContent`
- `FieldTripPublishedContentEndpoint`
- `FieldTripPublishedContentViewModel`
- `FieldTripPublishEndpoint`
- `FieldTripPublishViewModel`

The live feature service adapters use the existing client methods below. Views
and components do not call them directly.

Client methods:

```swift
MerianNetworkClient.shared.getFieldTripCaptureContext()
MerianNetworkClient.shared.getFieldTrips(userRegion:limit:)
MerianNetworkClient.shared.getFieldTripTemplate(templateId:)
MerianNetworkClient.shared.startFieldTrip(templateId:)
MerianNetworkClient.shared.stopFieldTrip(userFieldTripId:)
MerianNetworkClient.shared.resetFieldTrip(userFieldTripId:)
MerianNetworkClient.shared.getFieldTripChallenges(userRegion:limit:)
MerianNetworkClient.shared.getFieldTripChallenge(challengeId:entriesLimit:)
MerianNetworkClient.shared.joinFieldTripChallenge(challengeId:)
MerianNetworkClient.shared.getFieldTripCommunityPublications(mode:templateId:userRegion:habitatTags:seasonTags:limit:beforeRankBucket:beforePublishedAt:beforePublicationId:)
MerianNetworkClient.shared.getRecentFieldTripPublications(userRegion:habitatTags:limit:beforePublishedAt:beforePublicationId:)
MerianNetworkClient.shared.applyFieldTripProgress(scanId:preferredGoal:)
MerianNetworkClient.shared.getFieldTripScanContributions(scanId:)
MerianNetworkClient.shared.getFieldTripChallengeHashtags(scanId:)
MerianNetworkClient.shared.getFieldTripProfileSummaries(authorUserId:limit:)
MerianNetworkClient.shared.setPinnedFieldTripPublications(publicationIds:)
MerianNetworkClient.shared.publishFieldTrip(userFieldTripId:title:description:aiSummary:)
MerianNetworkClient.shared.getFieldTripChallengePublications(challengeId:limit:beforePublishedAt:beforeEntryId:)
MerianNetworkClient.shared.publishFieldTripChallengeEntry(participationId:title:description:)
MerianNetworkClient.shared.getFieldTripChallengeEntry(entryId:)
MerianNetworkClient.shared.getFieldTripPublication(publicationId:)
MerianNetworkClient.shared.setFieldTripLike(publicationId:liked:)
MerianNetworkClient.shared.setFieldTripChallengeEntryLike(entryId:liked:)
MerianNetworkClient.shared.getFieldTripComments(publicationId:limit:afterCreatedAt:afterCommentId:)
MerianNetworkClient.shared.getFieldTripChallengeEntryComments(entryId:limit:afterCreatedAt:afterCommentId:)
MerianNetworkClient.shared.createFieldTripComment(publicationId:body:parentCommentId:)
MerianNetworkClient.shared.createFieldTripChallengeEntryComment(entryId:body:parentCommentId:)
```

`FieldTripChecklistItem.completedScanId` is optional for backward-compatible
decoding. The catalog and detail surfaces resolve it to a caller-owned
`LocalScanRecord`; they do not download media from the Field trips API. The
outer catalog card and inner goal grid both use item-specific completion state,
so a completed third slot replaces only the third slot rather than the first
`completed_count` slots.

The shared catalog and authenticated active-profile goal preview renderer has
two explicit layouts. A current level with exactly two goals removes scrolling
and divides the width after 16-point side insets and the existing 10-point gap
into two equal square slots on either surface. Every other count retains the
96-point square layout and tap frame used by multi-goal catalog cards. Bundled
3D goal artwork in either layout and in the current or locked outing-detail
levels aspect-fits directly on the containing surface without a tile fill,
neutral border, clipping, or inner padding. A locally available completion photo
or video poster participates in either layout while retaining its full-bleed
rounded tile, media badge, neutral border, and Insight route. Completed items
without local media fall back to the uncarded curated artwork.

Standard outing level cards use their own responsive goal renderer. One or two
goals occupy equal-width square columns; more than two use fixed 120-point
square slots in a horizontal scroller. A locally available completion photo or
video poster stays full bleed with its media badge and opens Insight. Incomplete
guided art toggles the level's single selected goal with a selection haptic:
select, repeat-tap collapse, and cross-goal replacement all respect the global
haptics and Expedition mode gates. The selected tile gains a neutral surface and
border, and its name plus tip rows render directly below the collection without
the former per-goal accordion card. Current-level tiles otherwise remain
image-only. Ordinary detail entry starts with no selected goal; typed Capture
routing may preselect and highlight its exact guided goal.

`FieldTripChecklistItem.referenceSpecies` is also optional so an older Edge
deployment remains decodable. Template detail supplies a reviewed illustrative
species and up to one sanitized image per Naturebook, Wikipedia, and GBIF
source; catalog cards do not carry this media payload. Missing normalized media
for a current-level goal is filled by the Edge layer's bounded public
Wikipedia/GBIF fallback before iOS builds the carousel.

`FieldTripFeaturedMediaBuilder` creates one candidate per goal rather than per
scan. Its stable ID is derived from the checklist item, so the selected page
survives reference-to-user replacement. The preferred source is one canonical
photo, video poster, or legacy captured cover from the exact completed scan; a
missing, archived, nonvisual, posterless, unloadable, duplicated, or
reference-only local record falls through to the goal's ordered reference
candidates. `FieldTripFeaturedMediaSelection` keeps only candidates belonging to
the current active level, sorts them by checklist order and stable ID, then
takes up to six. Completed earlier levels and locked later levels never enter
the carousel. Failed source identifiers advance within the same goal before a
source-exhausted goal is removed and a same-level reserve candidate refills the
selection; reconnecting clears transient failures. Rendering reuses Insight's
`NativePageCarousel`, `CarouselPageItem`, `ZoomPageViewController`, and shared
pagination treatment, and the hero takes the full scroll-container width without
horizontal content insets. It also extends to the sheet's top edge beneath
transparent navigation chrome; the toolbar floats over the image just as it does
in Insight. No-media states retain the normal navigation-bar inset and
background. All selected posters begin resolving immediately, horizontal paging
cooperates with sheet dismissal, controller identity survives progress-driven
updates, and photo pages inherit the same pinch-and-snap-back behavior. The
inline carousel remains poster-only for video; tapping any page opens a
full-screen presentation containing exactly the currently featured order with
video muted initially. Reference pages use the shared reference gallery source,
display their provider badge against the visible bottom edge, and retain
license/attribution text in the full-screen viewer. Every source badge uses the
bottom-trailing corner. A Naturebook reference with a public author username
also displays `@username` in the bottom-leading corner; the Naturebook source
badge remains bottom-trailing. VoiceOver distinguishes an illustrative reference
and its provider from the user's own photo or video.

While standard outing detail is loading, its skeleton preserves the same visual
hierarchy: a square edge-to-edge media placeholder under transparent toolbar
chrome, pagination treatment, then an inset centered status placeholder, title,
description, metadata pills, primary action, and level cards whose
patch/level-name/accessory row precedes square goals. The current-level skeleton
shows the first goal selected without an inline label, followed by the goal
heading and four tip rows; later levels retain compact square strips. The
borderless About-outing guide rows also receive matching placeholders. Catalog
skeletons mirror the centered title/description, common two-up square goals, and
action order without patch, lifecycle, or progress placeholders. Active-profile
and published-entry loading cards expose their real header, goal-grid,
item-grid, and comment hierarchy instead of undifferentiated blocks. All
placeholders are inert and hidden from assistive technologies. Event loading
states retain their normal inset presentation without the featured-media hero or
selected-goal tips.

`GoalProgressRing` is a Core UI primitive shared by active Field-trip profile
cards, standard-outing level headers, and persistent Insight contribution rows.
The current level passes the outing's current counts, completed levels resolve
to their numeric target counts, and unstarted levels resolve to `0/N`. Locked
levels substitute the matching lock ring. Ephemeral milestone banners and the
Scan target capsule use their own compact treatments instead of another progress
ring.

`ScanMilestoneCoordinator` is the single scan-completion notification boundary
for both `InferenceEngine` foreground completion and `OfflineQueueManager`
background completion. It is main-actor isolated and derives a trimmed,
lowercase key from the final saved scan ID, then keys in-flight/recently
resolved work by that value while preserving the trimmed caller ID for network
and durable-store calls. Live and background races cannot enqueue the same batch
twice even if a framework or server bridge changes UUID casing. Capture queues
generate lowercase UUIDs while preserving an explicit caller-supplied stable ID.
Progress resolution has three explicit outcomes: success, retryable failure, and
terminal ingestion failure. Only success or a terminal failure finalizes Field
trip processing and discards the preferred Capture goal. A retryable persistence
timeout, network failure, or cancellation preserves that goal, remains eligible
for a later foreground/background callback, and schedules bounded automatic
retries after 2, 5, and 15 seconds. At most 16 retry sleepers exist across
scans; oldest overflow is cancelled because the SwiftData hint remains the
durable progress outbox: queue finalization preserves it, startup/network
recovery replays orphaned hints whose scan queue row is already gone, and only
server acknowledgement or a terminal outcome deletes it. Ordinary achievement
and dictionary milestones have a separate per-scan delivery guard, so they can
appear during an outage without being duplicated when Field trip progress later
succeeds. The coordinator waits through the existing remote-persistence polling
window on every attempt, then collects achievement unlock payloads with the
domain-only `GamificationManager` return value, evaluates the
dictionary-contribution flag, and makes one synchronous presenter enqueue pass.
An unrelated banner already on screen is not preempted; strict ordering applies
only within milestones from the same scan. The container-owned presenter
coalesces equivalent queued payloads, enforces a 32-item visual bound, and
rejects callbacks whose captured account/session token is stale. Its
foreground-host registry and injected clock preserve remaining lifetime and
one-time haptic/VoiceOver effects when nested Explore, Insight, Scans, or
Settings surfaces mount and unmount. Authentication and five-minute session
transitions also cancel coordinator retry tasks and release their captured model
container/preferred-goal context plus bounded in-flight state. Account changes
also clear recent-scan history, while a same-account session transition retains
completed/released deduplication. In-flight ownership includes the captured
account/session generation, so old deferred cleanup cannot remove or block a
current session's same-scan work; every suspended progress or achievement result
is re-fenced before it may schedule work or enqueue feedback.

`FieldTripMilestonePayload` stores the outing title, the first newly completed
item's label, lightweight goal artwork, and a typed destination. Standard
destinations use `.fieldTrip(templateId:checklistItemId:)`; Seasonal Challenge
destinations use `.fieldTripChallenge(challengeId:)`. `MilestoneToastBanner`
renders **Field trip progress**, `{goal} goal complete`, and the outing title
beside the goal artwork. It preserves the shared 3.5-second timeout, haptics,
horizontal/vertical swipe and close-button dismissal, queue transition, and
VoiceOver announcement, and requests `AppRoute.captureGoal` when tapped. The
root coordinator serializes the sheet handoff, then Explore converts the typed
destination into the standard focused outing route or Seasonal Challenge detail
route.

Completed goal tiles render the captured scan full-bleed with a bottom metadata
overlay and the ordinary neutral one-point border. Ordinary incomplete and
locked bundled artwork has no neutral tile chrome; incomplete focused goals may
still use the transient accent highlight. Tapping either completed thumbnail
routes through `ExploreView` to `ScanInsightRoute`, loads the saved inference,
and renders `InsightSheetView` with
`InsightPresentationStyle.embeddedInScansLibrary`. The route stays in the
existing Explore `NavigationStack`, exposing a back arrow and interactive back
gesture instead of a nested sheet. If the local record is missing, the
placeholder remains and the shell presents a non-destructive unavailable message
rather than an empty Insight view.

`FieldTripProgress.publicationId` and `publishedAt` are optional for staged
backend/client rollout. The detail metadata presentation derives **Published**
only from a non-null publication ID; completion alone and Community results are
not publication-state signals. Its green **Published** or neutral **Private**
pill joins the centered wrapping metadata row beneath the description and
exposes an explicit VoiceOver label. The active-level progress ring uses a
larger 64-point treatment in outing detail while other ring-owning cards retain
their compact sizes.

## Community Ranking

`For You` ranks visible published Field trips in stable buckets:

1. followed author plus local/template relevance
2. followed author
3. local, habitat, season, or template match
4. global or no-region fallback
5. other visible fallback

Within each bucket, results order by `published_at DESC, publication_id DESC`.
`Following` filters to followed authors. `Recent` uses reverse chronology with
all visible published trips. Template detail pages request the same Community
feed with `template_id` and a small limit for their preview section.

## Activity

Field trip comments, replies, and followed-author publications create rows in
`field_trip_activity_notifications`. These rows are read through
`get_explore_notifications`, counted by `get_unread_explore_notification_count`,
and marked through `mark_explore_notifications_read`. They are not stored in
`explore_post_notifications`, do not call `send-push-notification`, and are
deleted or hidden when relevant comments/publications are removed, authors are
shadowbanned, or either user blocks the other. Field trip likes intentionally do
not notify in V3/V4. Challenge joins, challenge entry likes, badges, and
challenge progress updates do not notify other users in V4.

## Deferred

V4 intentionally excludes leaderboards, prizes, sponsored trips, regional
rankings, contest eligibility, GPS check-ins, routes, and park boundary
verification. Those require stronger verification, abuse controls, moderation
policy, and legal/eligibility rules.

## Deployment Notes

Deploy in this order:

1. `20260708021110_field_trips_v1.sql`
2. `20260708033451_field_trips_v2.sql`
3. `20260708042713_field_trips_v3_community.sql`
4. `20260708051414_field_trips_v4_challenges.sql`
5. `20260717150222_contextual_outing_objective_guides.sql`
6. `20260717195751_active_outing_capture_context.sql`
7. `20260717213641_preserve_standard_outings_in_capture_context.sql`
8. `20260717224544_retire_forest_edges_outing.sql`
9. `20260718043218_expose_field_trip_completion_scan_ids.sql`
10. `20260718051748_expose_field_trip_publication_status.sql`
11. `20260718150932_add_credited_field_trip_progress.sql`
12. `20260718162409_scope_credited_progress_to_current_attempt.sql`
13. `20260719045306_first_field_trip_achievement.sql`
14. `20260719160750_field_trip_lifecycle_controls.sql`
15. `20260720014446_update_backyard_safari_copy.sql`
16. `20260722025411_persistent_field_trip_scan_contributions.sql`
17. `20260722064704_harden_atomic_field_trip_progress.sql`
18. `20260722195453_exclude_ants_from_bee_wasp_goal.sql`
19. `20260722211636_tighten_field_trip_goal_matching.sql`
20. `20260730023042_gate_field_trip_progress_by_confidence.sql`
21. `20260802053044_simplify_backyard_and_pollinator_levels.sql`
22. `20260803015025_auto_enroll_backyard_safari_level_one.sql`
23. scan-ingestion Edge Functions (`identify-multimodal`, `identify`,
    `identify-describe`, `audio-spec`, and `replay-scan-ingestion`)
24. `field-trips` Edge Function
25. `get-explore-author-profile` so public profiles include Field trip summaries
    and pins
26. `get-explore-notifications`, `get-explore-unread-notification-count`, and
    `mark-explore-notifications-read` Edge Function updates
27. iOS client update

The Edge Function depends on the migration-created tables and RPCs. The profile
function update depends on `public.get_field_trip_profile_summaries(...)`. The
persistent contribution and atomic-hardening migrations plus the ingestion and
`field-trips` Edge Functions must precede the new iOS client. Older clients omit
`preferred_goal` and receive deterministic fallback; the new client silently
hides its Insight card until `scan_contributions` is deployed.

Rollback should revert the iOS thumbnail route before rolling back the evidence
link migration. Because `completed_scan_id` is optional, older clients tolerate
either database shape, and rolling back the migration does not delete completion
rows. Do not restore direct `PUBLIC`, `anon`, or `authenticated` execution of
the private catalog/detail RPCs. Existing `user_field_trips` and publication
rows are user data and should not be dropped casually after release. Placeholder
field trips should be retired through `field_trip_templates.is_active`, as
Forest Edges is, rather than deleting their template graph.

If automatic Backyard Safari enrollment must be disabled, ship a forward
migration that drops `auto_enroll_backyard_safari_level_one_on_user_insert` from
`public.users`, then drops `internal.auto_enroll_backyard_safari_level_one()`.
Preserve all backfilled `user_field_trips` rows and activity periods: they are
now normal user progress, and deleting them would erase credit or reopen
historical eligibility choices.

Rolling back credited progress is response-compatible: older fields remain the
source of truth and the iOS fallback continues to render them. Preserve both
progress functions' service-role-only execute contract during any rollback; do
not drop completion rows or rewrite scan history.

For the persistent-card release, roll back the iOS client surface first and the
Edge action second while leaving the migration in place. The database remains
compatible with clients that omit `preferred_goal`, and an unavailable
`scan_contributions` action is already a silent client state. Do not reverse the
deduplication or drop preferences/contribution functions after new credits
exist. The forward migration is transactional and intentionally aborts before
changing data when completed trips, publications, Event badges, or entries are
present; treat that guard as a release blocker requiring product/data review,
not something to bypass in production.

The confidence-gate migration is forward-only because its repair deletes invalid
completion rows and Event badges and soft-deletes invalid completion
publications or entries. Retain a production backup and record the affected-row
counts before deployment. During an incident, roll back the client or Edge
surface, or ship a forward database fix, while leaving the evidence gate and
repaired data in place. Do not recreate weak credit or restore direct client
execution of the private progress RPCs.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts services/supabase/functions/_tests/fieldTripProgressDb.test.ts services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts services/supabase/functions/_tests/fieldTripAtomicProgressDb.test.ts services/supabase/functions/_tests/fieldTripSecurityDb.test.ts services/supabase/functions/_tests/fieldTripPublicationDb.test.ts
deno check --config services/supabase/functions/field-trips/deno.json services/supabase/functions/field-trips/index.ts
deno test --config services/supabase/functions/field-trips/deno.json --allow-read services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/field-trips/referenceMedia_test.ts services/supabase/functions/field-trips/db_test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripProgressDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripAtomicProgressDb.test.ts services/supabase/functions/_tests/fieldTripSecurityDb.test.ts services/supabase/functions/_tests/fieldTripPublicationDb.test.ts
supabase db lint --workdir services
supabase db advisors --local --workdir services --type all --level warn --fail-on none
```

iOS:

```sh
make xcodegen
make validate-ios-project
bash scripts/test-ios-project-source-membership.sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:merianTests/FieldTripAPIModelsTests \
  -only-testing:merianTests/FieldTripCaptureContextModelsTests \
  -only-testing:merianTests/FieldTripPresentationTests \
  -only-testing:merianTests/ActiveFieldTripProfilePresentationTests \
  -only-testing:merianTests/EarnedFieldTripPatchPresentationTests \
  -only-testing:merianTests/FieldTripsViewModelTests \
  -only-testing:merianTests/FieldTripTemplateDetailViewModelTests \
  -only-testing:merianTests/FieldTripChallengeDetailViewModelTests \
  -only-testing:merianTests/ActiveFieldTripsProfileViewModelTests \
  -only-testing:merianTests/FieldTripPublishedContentViewModelTests \
  -only-testing:merianTests/ActiveCaptureGoalStoreTests \
  -only-testing:merianTests/ExploreShellNavigationPolicyTests \
  -only-testing:merianTests/CaptureSubmissionPolicyTests \
  -only-testing:merianTests/OfflineQueuedScanDeletionTests \
  -only-testing:merianTests/AchievementToastPresenterTests \
  -only-testing:merianTests/FieldTripFeaturedMediaTests \
  -only-testing:merianTests/InsightFieldTripContributionTests \
  -only-testing:merianTests/MigrationPlanTests \
  -only-testing:merianTests/AppTelemetryTests test
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:merianTests test
swiftlint lint --strict \
  apps/ios/Merian/Features/Explore/FieldTrips \
  apps/ios/MerianTests/Features/Explore/FieldTrips \
  apps/ios/Merian/Core/Network/FieldTripAPIModels.swift \
  apps/ios/Merian/Core/UI/Feedback/AchievementToastPresenter.swift
make validate-markdown-format
git diff --check
```

The focused selector matrix and complete `merianTests` target are both required;
one does not replace the other. Run the SwiftLint command only when the local
SourceKitten installation is functional, and report the limitation if it cannot
run.

Manual iOS parity matrix:

| Surface                    | Required regression coverage                                                                                                                                                                                     |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Catalog                    | Switch Outings/Events repeatedly; exercise independent loading, error, retry, pull-to-refresh, difficulty/status filters, Reset, and server-order preservation.                                                  |
| Standard outing detail     | Goal focus/collapse/tips, featured-media fallback and viewer, Start/Resume/Stop/Reset/Publish, progress refresh, lifecycle menu, selection continuity, and typed Back navigation.                                |
| Event detail               | Join, Continue, badge/progress, independent loading/error, reverse-chronological entry pagination, and typed entry publication completion.                                                                       |
| Published content          | Open both thin wrapper routes; load items/comments, optimistic like and rollback, 500-character validation, trimmed comment/reply submission, draft restoration, pagination, author routing, and error feedback. |
| Profile and shared artwork | Authenticated active cards, public active/pinned/published rows, earned-patch paging, patch gallery, cover/image fallback, and completed local-media previews.                                                   |
| Accessibility and layout   | Preserve visible copy and identifiers; inspect VoiceOver actions/labels, large Dynamic Type, compact and large phones, light/dark appearance, Reduce Motion, focus timing, and scroll/highlight behavior.        |

The database integration tests require the local Supabase/Postgres stack. They
report a skip when `127.0.0.1:54322` is unavailable; a skip is not production
database validation. The progress test covers standard and challenge level
advancement, Backyard enrollment plus explicit eligibility for other outings,
one credit per experience, multi-experience credit, selected-goal and fallback
ranking, delayed upload, correction move/removal, confidence boundaries,
weak-match confirmation, normal correction freeze, confidence-downgrade
reopening, pending-goal retention, ownership, concurrency, and idempotent
reapplication. The atomic test injects an Event-side exception and proves
standard progress, preference, achievement/receipt state, and Event progress all
roll back. The security test enumerates every matching `SECURITY DEFINER`
function and requires `anon`/`authenticated` execute to be false and
`service_role` execute to be true. The publication test executes the
completed-outing publish path and asserts that snapshot items use the created
publication ID.

The capture-context test creates an otherwise empty user and requires the
database trigger to produce exactly one Backyard Safari Level 1 row and one open
activity period. The static contract separately locks the active-template
preflight, insert-only backfill, trigger name, empty search path, and denied
execute privileges for every API role.

For progress-toast QA, cover partial progress, level advancement, final
completion, multiple standard/challenge experiences, re-identification after
level advancement, the Flash `0.75` and Pro `0.65` inclusive boundaries, a weak
scan that becomes eligible through confirmation, a confirmed weak scan
downgraded back to unreviewed evidence, and idempotent reapplication. Confirm
the response exposes credited counts for the changed level and that legacy
responses still decode through the current-count fallback. For one scan, verify
the visible order is standard outings, Seasonal Challenges, achievements, then
**New to Naturebook**; a failed/no-match progress attempt must release the later
milestones only after it finishes, and foreground plus background completion
must enqueue once. Tap a standard toast to open its focused first credited goal
and a challenge toast to open challenge detail. Use DEBUG Settings -> **Preview
Field trip progress toast** for compact and large-width, long-name, timeout,
swipe/close, haptic, and VoiceOver inspection.

For the persistent Insight card, reopen a historical saved biological scan with
one and then several standard/Event credits. Confirm every row remains visible,
shows the **Field trips** header, an uppercase **GOAL COMPLETE** eyebrow above
the headline-sized goal name, enlarged goal art/check badge, an experience-only
subtitle with no level, and a prominent credited-level ring without separators
or chevrons. Confirm the heading matches other Insight card headers and the card
reloads after that scan's progress/evidence invalidation. Every standard row
must open at the top of the outing detail with no focused item; every Event row
must open challenge overview. Root modal, Scans-embedded, Explore-embedded, and
modal-from-Explore paths must retain the originating Insight beneath the detail
so native Back returns to it. Also exercise
queued/unauthenticated/non-biological gates, no-match and network failure, long
goal/experience names, compact and large widths, dark mode, accessibility
Dynamic Type, VoiceOver, and Reduce Motion. The card must add no haptic or
confetti. Verify V49→V50 migration and both foreground/background queue paths
preserve the eligible camera-only hint, while gallery, mixed camera/gallery,
Describe, Record, audio, video, refinement, and deletion/orphan cleanup do not
leak it. Also verify migrated V49 queue rows receive no synthesized hint, then
create fresh V50 queue rows for the foreground/background persistence checks.

For completion-evidence QA, complete a non-leading goal such as Cat and confirm
that only Cat changes in both the catalog card and detail grid. Test both photo
and video completions, confirm the captured thumbnail has the standard neutral
border with no blue completion outline, and tap both surfaces to open the same
embedded Insight view. Verify an exact two-goal catalog row gives both curated
and completed-media slots equal square widths, while three or more goals retain
the 96-point scroller. Back must return to the current outing. A missing local
record must leave the placeholder usable and must not show a blank Insight. On
standard outing detail, confirm an unstarted outing begins with reference pages
and one loadable goal produces a dot-free square hero. The carousel must include
only the current active level's goals, with no completed earlier-level or locked
later-level pages, and must cap that level at six in checklist order. Advancing
the outing must replace the carousel contents with the new active level. Verify
each reference tries Naturebook, Wikipedia, then GBIF; source badges and
full-screen rights attribution remain legible; completing that exact goal
replaces the same stable page with the user's visual; video pages show a
poster/play badge and open muted playable video; and photos open the swipe/zoom
viewer. Failed user media must fall back to the goal reference, a
source-exhausted goal must refill from a reserve, and exhausting every
user/reference source must collapse the hero without affecting the title layout.
Confirm there is no segmented detail picker and the first incomplete guided goal
begins selected with a full-square image, no inline name, and its name above the
visible tips. Repeat-tap must collapse it without an automatic reopen, selecting
another goal must replace it, and every transition must respect the haptics
setting. Verify the borderless centered navigation badge tracks **Not started**,
green **Active**, orange **Stopped**, and green **Completed** while remaining
between the back and options controls. Completed local media must still open
Insight, completed and locked cards must expose no tips, and the outing-guidance
cards must follow all levels and Community/Event-entry content at the bottom
without a separate section heading. Exercise compact and large iPhones,
light/dark appearance, Dynamic Type, VoiceOver, Reduce Motion, offline-to-online
retry, progress refresh, and Reset/removal while preserving a still-valid
selected goal page. At the database boundary, confirm catalog/detail return the
completion row's exact `scan_id`, only `service_role` can execute their RPCs,
and no public or capture-context payload contains `completed_scan_id`. Confirm
`reference_species` appears only on authenticated template/lifecycle detail and
contains no private scan, owner, note, or location provenance.

For publication-state QA, verify an unstarted, active,
completed-but-unpublished, and deleted-publication outing all show **Private**.
Publishing must change the centered detail pill to **Published** after refresh
and expose a VoiceOver value that says the snapshot is public. Confirm template
detail returns only the requesting user's active non-deleted publication ID and
that catalog, capture context, public profile summaries, and completion evidence
contracts are unchanged.

Also verify that publishing a Field trip appears on profiles, Field trip-native
preview/detail surfaces, and typed Observations Recent/Following cards without
creating an `explore_posts` row. It must not create Explore map points, normal
Explore post notifications, APNs, widgets, or public web share pages.
Comment/reply/followed-publication activity may appear in the Explore activity
sheet and unread count.

## Explore Feed Presentation

Published base Field trips are mixed into the Observations feed as typed Field
Trip cards for `Recent` and `Following`. They keep their Field trip publication
identity and open `FieldTripPublicationDetailView`, so likes, comments, author
identity, and deletion semantics are not duplicated into `explore_posts`. Field
trips are intentionally absent from `Trending` and `Nearby` until those ranking
and geoprivacy contracts are designed. Seasonal entry aggregation, cross-type
cursor pagination, widget/APNs, and public-web presentation remain future work.
