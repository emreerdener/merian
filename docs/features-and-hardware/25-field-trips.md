# Field trips

Field trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## Current Scope

- Standard Field trips and Outings are released for every user. Events remain a
  client-gated preview for `erdener.emre@gmail.com` and simulator builds through
  `FieldTripEventsAvailability.isReleased`; enabling that release flag exposes
  Events to everyone. The client gate is not a backend authorization boundary.
- Field trips live under Explore in `apps/ios/Merian/Features/Explore/FieldTrips/`.
- The Field trips surface opens directly to `Outings` for standard outings. When
  Events are enabled, the page header adds an `Outings`/`Events` segmented picker
  and Events lists live and upcoming curated challenges.
- Standard Field trip and Seasonal Challenge detail pages pin `Goals` and
  `Tips` in the sheet toolbar. `Goals` is selected by default and owns the
  trip overview, progress, actions, checklist, and Community content; `Tips`
  shows only the curated guide.
- Standard outing detail places a left-aligned status badge above the title:
  **Private** until an active publication exists and **Published** once
  the owner has created a public outing snapshot.
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
  can surface unfinished goals from every active standard outing.
  Seasonal Challenge labels and challenge-specific progress are intentionally
  excluded from this first capture integration. Joining a challenge does not
  hide the linked standard outing or its normal progress.
- When no active goal exists, the same Scan position can introduce an accessible,
  unstarted Backyard Safari as an outing with four goals. This introduction is
  validated from template detail and remains distinct from progress-bearing goals.
- Users can explicitly start an outing from the template detail page before
  their first matching scan.
- Unfinished active outings expose a trailing ellipsis with **Stop field trip**
  and destructive **Reset field trip**. Stopped outings preserve their visible
  checklist state, show **Resume outing**, and expose Reset without an empty
  menu. Completed and unstarted outings have no lifecycle menu.
- Levels unlock sequentially. Every completion belongs to a started
  `user_field_trips` row. For an eligible unstarted outing, the first matching
  scan starts the outing at that scan's timestamp and can complete its matching
  current-level goal in the same server transaction.
- A checklist item can match by species, scientific name, taxonomy, ecology,
  habitat text, or dictionary group tag.
- AI matches and later user confirmations/corrections both call the progress
  updater.
- Completed standard-outing goals replace their curated artwork with the
  completing scan's device-local photo or video-poster thumbnail in both the
  catalog card and outing detail. They keep the standard neutral tile border;
  blue/accent borders are reserved for an incomplete focused goal.
- The active level header uses the shared circular `GoalProgressRing` at its
  trailing edge, showing completed/total outing progress consistently with
  the Scan target capsule.
- A saved scan that completes at least one current-level goal queues one
  progress toast for every matching standard outing and joined live Seasonal
  Challenge. Each toast shows **Field trip progress**, contextual species/trip
  copy, and the credited level's progress ring. Standard outings are queued
  before Seasonal Challenges, then achievement unlocks, then
  **New to Naturebook** for that scan.
- Tapping a completed goal with locally available evidence opens that scan's
  Insight view in the existing Explore navigation stack. Back returns to the
  outing without presenting another sheet.
- Field trip comments and likes are separate from Explore post comments and
  likes, even though the iOS UI reuses the compact Explore comment presentation.
- V4 supports profile showcase, up to 3 pinned published Field trips, completion
  badges for challenges, published Field trip pages, challenge entry pages,
  template-detail Community previews, and Field trips-native publication APIs.
  It does not create Explore feed posts, map points, public web share pages,
  APNs, widgets, leaderboards, prizes, rankings, contest windows, or
  sponsored-trip eligibility.

## Rollout State and Events Release Checklist

The release state is intentionally split in iOS:

- `FieldTripsAvailability.isEnabled == true` makes Field trips and standard
  Outings public.
- `FieldTripEventsAvailability.isReleased == false` keeps Events staged. The
  allowlisted tester account and simulator builds bypass that flag so UI/UX work
  can continue against the deployed backend.
- This is a client-build flag, not a remotely managed feature flag. Changing it
  requires a new iOS build and release. It does not grant or revoke backend
  authorization.
- DEBUG app startup writes
  `TODO(field-trip-events-release): Outings are public; Events remain staged to the tester allowlist and simulator builds.`
  to `MerianLog.general`. The source flag carries the same named TODO so a repo
  search and the Xcode console both expose the pending state.

When Events UI/UX is ready for public release:

1. Complete physical-device QA for an allowlisted account, a non-allowlisted
   account, and a signed-out/ghost user. Before the flip, only the allowlisted
   account should see Events on device; simulator builds should always see it.
2. Verify the production Field trips migrations and Edge Function are current,
   then exercise catalog, detail, Join, progress, badge, entry publication,
   comments/likes, and optional Explore hashtag suggestions. The backend is
   already deployed, so do not redeploy it solely because the client flag
   changes.
3. Set `FieldTripEventsAvailability.isReleased` to `true`, remove the tester and
   simulator bypass paths, and update `FieldTripsAvailabilityTests` so the
   public state is locked by tests.
4. Promote the gated `2026-07-19-field-trip-events-preview` bundled changelog
   entry into the public Events release entry. Update `README.md`, `CHANGELOG.md`,
   the Explore RFC and shell README, the Explore/Field trips feature docs,
   profile/gamification docs, testing guidance, logging guidance, and the
   Supabase deployment/function docs.
5. Remove `TODO(field-trip-events-release)` and change the startup notice to the
   released-state message. Run the focused iOS suites, Deno Field trips tests,
   SwiftLint, changelog JSON validation, and an unsigned device build before
   distributing the client.

If release QA finds an Events regression, set the client release flag back to
`false` and issue a replacement build. Because the switch is compiled into the
client, it is not an instantaneous server-side rollback mechanism.

## Product Terminology

These labels are a user-facing contract even though older internal symbols and
migration filenames may still use `objective` or `challenge`:

- **Field trips** is the feature name.
- **Outings** is the standard catalog segment; a standard item is an **outing**.
- **Events** is the seasonal segment. **Challenge** is reserved for seasonal
  challenge data and explanatory copy inside an Event.
- **Goals** is the default detail tab and the user-facing name for checklist
  targets. Never label this tab **Objectives**.
- **Tips** is the curated-guide tab.
- Standard-outing actions are **Start outing**, **Start scanning**,
  **Resume outing**, and **Publish outing**. Never use **Start challenge** or
  **Publish challenge** for a standard outing.
- The active Scan capsule uses **Goal: {target}**. The empty introduction uses
  **Start an outing** with **Backyard Safari · 4 goals**.
- Standard catalog cards show an accent progress ring beside the title and a
  current-level subtitle: **Observe {target count} local species often found in
  your own backyard.** The thumbnail strip remains horizontally scrollable,
  followed by Pro access when locked, difficulty, current level, public/private
  publication status, and an optional privacy-filtered city/state tag.

## Difficulty

Difficulty is manually curated template metadata rather than a value calculated
from duration, checklist size, completion data, user behavior, or access tier:

- `Starter`: onboarding-oriented with familiar, commonly available targets.
- `Easy`: a focused trip reasonably completed in one ordinary field trip.
- `Moderate`: requires a specific habitat, longer effort, or subtler targets.
- `Hard`: specialized, time-dependent, or likely to require multiple field trips.

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
   loads first; when Events are enabled, `Events` separately lists live and
   upcoming challenges.
2. `/field-trips` with `action: "catalog"` returns accessible and locked
   templates, their levels, checklist items, and any existing progress.
3. Opening a catalog card loads `action: "template_detail"` and shows guide
   sections, levels, curated item tips, and the current start/continue/publish
   state.
4. Tapping **Start outing** calls `action: "start"`. Auto-start from matching
   scans remains as a fallback. Standard outings never use Start/Publish
   Challenge copy; that language is reserved for Seasonal Events. An unfinished
   active outing can be stopped after confirmation; the backend saves its
   checklist, closes its activity period, and hides it from Capture and active
   profile summaries. **Resume outing** calls `action: "start"` and opens a new
   period. Destructive Reset clears only unfinished standard outing progress and
   returns the detail to its initial state.
5. The idle visual Scan page loads `action: "capture_context"` without blocking
   the camera. When unfinished standard goals exist, a `Goal: {target}` label is
   shown beneath the capture-mode picker with its outing title and aggregate
   level progress. When the context is successfully empty, iOS loads
   `template_detail` by the `backyard_safari` slug and offers an introduction only
   when that template is accessible and unstarted.
6. Swiping an active indicator cycles through all unfinished targets in server
   order; tapping it opens the owning outing and focuses that goal's guide.
   The introduction has no swipe behavior and opens Backyard Safari detail without
   starting it.
7. A new scan or later confirmed/corrected identification calls
   `action: "apply_scan_progress"` with the saved scan ID.
8. The backend verifies scan ownership and requires the scan's capture timestamp
   to fall within one of the outing's activity periods before comparing it
   against the current unlocked level, writing item completions, advancing
   levels when needed, and returning newly completed items.
9. The shared `ScanMilestoneCoordinator` waits for that progress attempt,
   publishes refresh events, evaluates newly unlocked achievements without
   presenting them early, and batches the scan's notifications in strict order:
   standard outings in server order, Seasonal Challenges in server order,
   achievements in their existing order, then **New to Naturebook**. A progress
   failure or no-match response still releases later milestones after the
   attempt finishes.
10. iOS shows each qualifying progress toast for 3.5 seconds with the credited
    level's ring. Tapping a standard toast opens its outing focused on the first
    credited goal; tapping a challenge toast opens that challenge detail. The
    same progress events immediately invalidate affected Field trips data and
    the standard capture target context without creating a second plain toast.
11. Catalog and detail reloads associate each completed checklist item with the
    exact saved scan that completed it. iOS replaces that item's artwork with
    the scan thumbnail; completion order never determines which slot changes.
12. Tapping a completed goal whose scan still exists on the device pushes the
    existing Insight view inside Explore. The back arrow and swipe-back gesture
    return to the same outing sheet.
13. Once all levels are complete, **Publish outing** creates a Field trip snapshot
   with an editable title and optional description or AI summary.
14. After the detail refreshes, its title badge changes from **Private** to
    **Published**. Deleting the publication returns it to **Private**.
15. Published Field trips appear on public profiles and template Community
   previews. They open `FieldTripPublicationDetailView` with item cards,
   likes, comments, and author identity. Author taps open the existing Explore
   author-profile route.

## Active Target on Scan

The capture indicator is orientation and motivation, not a scan requirement.
It never changes which outing receives progress; the backend still matches
every saved scan against eligible active trips.

The canonical source-agnostic ownership, caching, navigation, security, and
future-source decision is
[`active-capture-goal-context.md`](../rfcs/active-capture-goal-context.md).

Presentation contract:

- Show only when Field trips are enabled, Scan/visual mode is selected, a real
  target or validated introduction exists, the local `showsCaptureGoalProgress` preference is enabled, the
  staged-capture tray is empty, refinement is inactive, and video is not
  recording.
- Show no loading placeholder when there is no complete cached context. Camera
  startup and capture remain independent from both requests. A template-detail
  failure preserves the last complete snapshot and never fabricates an introduction.
- Render beneath `MediaModeToggle` at the same visual width, with a minimum
  56-point height and 36-point bundled goal artwork. On iOS 26 and later
  the untinted capsule uses interactive native Liquid Glass; earlier supported
  versions use a neutral material fallback. Foreground styles remain semantic
  so system contrast adapts to the camera scene and accessibility settings.
  Unknown goals use a neutral binoculars symbol; they must not borrow
  semantically incorrect art.
- Center the `Goal: {target}` prompt and outing title between
  equal 40-point edge slots. Preserve the curated target text exactly; the
  colon avoids article and plurality errors for composite or mass-noun prompts.
  The leading slot contains the artwork; the trailing slot contains a circular
  `completed/target` progress ring. This keeps the text optically centered while
  making progress changes understandable when the selection crosses outing
  boundaries.
- Swipe left for the next unfinished target and right for the previous target.
  Selection wraps across every active standard outing. The gesture commits only
  after 36 points of translation and only when horizontal movement is at least
  1.25 times vertical movement, preserving camera and capture-page gestures.
- Tapping the capsule uses a light sheet-opening haptic; selection changes use
  selection haptics. Both respect the global haptics and Expedition mode gates.
  Reduced Motion removes the selection animation, and VoiceOver exposes
  `Outing target. Look for {target}.`, the outing title and progress, plus
  adjustable previous/next actions.
- Settings > Workspace exposes an on-by-default **Field trip goals** toggle with
  the `binoculars.fill` symbol. Turning
  it off removes the entire target capsule from Scan without changing outing
  progress, cached goal context, or server state.
- For the validated unstarted Backyard Safari zero state, show **Start an outing**
  over **Backyard Safari · 4 goals**, rotate the first-level artwork by cross-fade
  every three seconds, and show `0/4` in the shared progress ring. Reduce Motion
  keeps the first artwork static. VoiceOver announces “Start an outing. Backyard
  Safari, 4 goals.”, “0 of 4 goals complete.”, and “Opens outing details.”

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
- refresh after five stale minutes when the app returns to the foreground or
  the user returns to visual Scan;
- force refresh after outing start/join, standard progress events, and explicit
  scanner-routing events;
- share one provider fetch when appearance, account restoration, and scene
  activation overlap at startup;
- coalesce overlapping invalidations into one follow-up refresh; and
- retain cached content without surfacing an error if refresh fails.

Tapping the indicator passes its typed `CaptureGoalDestination` into Explore.
Explore presents the Field trips tab, opens the owning standard outing, selects
Tips, expands the matching goal, scrolls it into view, and briefly
highlights it. A future goal without guide content falls back to the
highlighted Goals tile. The destination is converted at the Explore
boundary into `FieldTripTemplateRoute`, whose focused checklist-item identifier
remains optional for ordinary outing navigation.

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
- A standard scan counts only when its capture timestamp falls within one of
  the outing's `user_field_trip_active_periods`. Pre-stop scans can receive late
  approval; scans captured during stopped gaps stay excluded after Resume.
- Reset removes all prior periods and moves the automatic-start boundary to the
  reset timestamp, preventing historical scans from rebuilding cleared progress.
- Matching is limited to the current unlocked level. Later levels cannot fill
  early.
- Eligibility is media-kind agnostic after a scan is saved and has a resolved
  biological identification. A qualifying photo or video can count; the
  camera-only active-target capsule does not restrict progress eligibility.
- One scan is evaluated against every matching item in the current unlocked
  level and every eligible active standard outing. The same scan may therefore
  complete more than one `Bird` goal at the same time, and each completion row
  links back to that same scan ID.
- A checklist item can complete once. Reprocessing the same scan is idempotent.
- A level unlocks only when all items in the current level are complete.
- A trip completes when all levels and checklist items are complete.
- Progress responses retain the existing current-level fields and add optional
  `credited_*` fields for the level changed by the scan. When completion advances
  to another level, the credited counts describe the just-completed level so
  scan feedback shows a full ring rather than the next level's `0/N`.
- A progress toast requires a nonempty `newly_completed_items` array. The first
  item in curated checklist order supplies its common name, with the checklist
  prompt as the empty/missing-name fallback and as the focused standard route.
- The progress updater is best effort from iOS. If the toast fails, the scan
  still saves; catalog reloads can reconcile server progress.

## Challenge Progress Rules

- Challenge participation is explicit and private by default.
- Only scans owned by the requesting user can count.
- Only scans created at or after `field_trip_challenge_participants.joined_at`
  and at or before `field_trip_challenges.ends_at` can count.
- Matching is limited to the participant's current challenge level. Later
  challenge levels cannot fill early.
- One qualifying scan can complete every matching item in that current
  challenge level. The same saved scan may also satisfy matching items in
  eligible standard outings; challenge and standard completion rows remain
  separate even when they reference the same scan.
- Challenge item completions are keyed by participation and checklist item; they
  do not retroactively satisfy or overwrite normal Field trip item completions.
- Reprocessing the same scan is idempotent.
- The badge award is server-authoritative and occurs only after challenge
  completion.

## Privacy Model

Active Field trip progress is visible on public profiles by default, but it is
status-only:

- template title
- current level
- completed count
- target count
- checklist item labels

Active profile summaries must not expose scan IDs, media URLs, field notes,
exact coordinates, public location labels, or private evidence details.

The authenticated `catalog` and `template_detail` responses are a separate,
private viewer-specific read model. A completed standard checklist item may
include `completed_scan_id`, but it never includes a media URL. iOS uses the ID
only to find the caller's device-local `LocalScanRecord` and render the same
`ScanThumbnail` used elsewhere. If that record is unavailable on the device,
the curated artwork remains and the app must not construct a remote or public
evidence URL. `completed_scan_id` must not appear in public profile summaries,
publication snapshots, challenge badges or entries, Explore feed/map payloads,
or the capture-context response.

The detail-only publication status is also private viewer metadata.
`active_progress.publication_id` and `published_at` identify the owner's active,
non-deleted public snapshot; missing values mean the detail badge is **Private**.
The badge describes publication state, not whether the status-only active
progress summary is allowed on a public profile. It never makes completion
evidence public.

The Scan capture-context payload is even narrower: it contains only field trip and
template identifiers, title/slug, current-level metadata, aggregate counts, and
unfinished item identifiers/prompts/order/guide availability. It must never
return scan IDs, media, coordinates, location labels, field notes, completed
species names, or completion evidence. Seasonal Challenge-specific progress is
excluded; the shared underlying standard field trip remains eligible.

Published Field trip pages are explicit snapshots stored separately from
Explore posts. Publication items may include species names, taxonomy, reference
images, and selected scan media snapshots, but publishing a Field trip does not
create Explore feed posts, Explore map points, normal Explore post
notifications, APNs, widgets, or public web pages. Field trip-only in-app
activity rows for comments, replies, and followed-author publications may
appear in Explore activity and increment the bell, but they never fan out to
push delivery.

Public author profiles can be discoverable through either visible Explore posts
or visible Field trip surfaces. Field trip discoverability still respects
shadowbans and mutual blocks.

Challenge participation exposes only aggregate counts unless the user
explicitly publishes a challenge entry or displays a completion badge. Badges do
not expose scan IDs, media URLs, exact locations, field notes, or private
evidence. Challenge entries are public snapshots scoped to Field trips; they do
not create Explore posts, Explore map rows, APNs, widgets, public web pages, or
automatic Explore hashtags.

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
clients continue to access them only through `/field-trips`.
Private detail publication status is added by
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

Core tables:

- `field_trip_templates`
- `field_trip_levels`
- `field_trip_checklist_items`
- `user_field_trips`
- `user_field_trip_item_completions`
- `user_field_trip_active_periods`
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
  standard field trips and unfinished current-level targets. Field trips order by most
  recent start or item completion; targets retain curated checklist order. The
  RPC is revoked from `PUBLIC`, `anon`, and `authenticated`, and granted only to
  `service_role`; the authenticated Edge Function supplies the verified user
  ID.
- `catalog`: returns active templates, gated access state, levels, checklist
  items, and the viewer's progress. Completed standard items may include the
  private `completed_scan_id` needed for device-local evidence thumbnails.
- `template_detail`: returns one template with guide fields, levels, checklist
  tips, access state, viewer progress, and the same optional private completion
  scan ID. Its `active_progress` also includes the owner's optional active
  `publication_id` and `published_at` for the title badge.
- `start`: explicitly starts or unhides the caller's progress row for an
  accessible template.
- `stop`: closes an unfinished outing's open period and returns its saved
  stopped detail.
- `reset`: clears unfinished, unpublished standard progress without deleting
  the shared outing row or Seasonal Challenge data.
- `community_publications`: returns visible published completed Field trips for
  `smart`, `following`, or `recent` mode with optional template filtering and
  stable `(rank_bucket, published_at, publication_id)` pagination.
- `recent_publications`: compatibility alias for `community_publications` with
  `mode: "recent"`.
- `apply_scan_progress`: applies progress for one saved scan owned by the
  caller. V4 keeps the existing `data` payload for normal Field trip progress
  and adds optional `challenge_updates` for joined live challenges. Both update
  arrays may include optional `credited_level_number`, `credited_level_title`,
  `credited_completed_count`, and `credited_target_count`; the request shape is
  unchanged.
- `challenges_catalog`: returns curated seasonal challenges with viewer
  participation summary and aggregate counts.
- `challenge_detail`: returns one challenge, linked template guide context,
  schedule, suggested hashtags, viewer progress, aggregate counts, and initial
  published challenge entries.
- `join_challenge`: explicitly joins a live accessible challenge and
  starts/continues the linked Field trip.
- `challenge_publications`: paginates visible published challenge entries by
  `(published_at DESC, entry_id DESC)`.
- `scan_challenge_hashtags`: returns normalized suggested challenge hashtags
  for a scan that completed joined live challenge items.
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

The database RPCs behind `catalog` and `template_detail` are revoked from
`PUBLIC`, `anon`, and `authenticated` and granted only to `service_role`. The
authenticated Edge Function supplies the verified user ID, so callers cannot
request another user's completion evidence.

## Access

Free users see starter and rotating-free trips. Pro users can access the full
active catalog. Locked Pro trips may still appear in the catalog so the UI can
show the available upgrade path without starting progress.

Access is evaluated from server-side user state. The iOS catalog should treat
`viewerHasAccess` / `accessKind` as display and start eligibility hints, not as
authorization.

Challenge access is server-authoritative and independent from the linked
template's normal catalog access. A challenge can be free, Pro-only, or
temporarily free during its challenge window.

## iOS Implementation

Primary files:

- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripsView.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripsViewModel.swift`
- `apps/ios/Merian/Features/Capture/Shell/Views/CaptureWorkspaceView.swift`
- `apps/ios/Merian/Features/Capture/Shell/ViewModels/CaptureWorkspaceViewModel.swift`
- `apps/ios/Merian/Features/Capture/Shell/Modifiers/CameraSheetRouter.swift`
- `apps/ios/Merian/Core/AppDIContainer.swift`
- `apps/ios/Merian/Core/Models/CaptureGoalContext.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripPublicationDetailView.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripProfileModules.swift`
- `apps/ios/Merian/Core/Network/FieldTripAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Core/UI/Feedback/AchievementToastPresenter.swift`
- `apps/ios/Merian/Core/UI/Feedback/AchievementToastBanner.swift`
- `apps/ios/Merian/Core/Utilities/AppEventPublisher.swift`
- `apps/ios/Merian/Core/AI/InferenceEngine.swift`
- `apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+URLSession.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Views/ProfileTabView.swift`
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`

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
MerianNetworkClient.shared.applyFieldTripProgress(scanId:)
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

`GoalProgressRing` is a Core UI primitive shared by the Scan target capsule and
the active standard-outing level header and scan-progress milestone banner. The
level header passes the outing's current counts; a progress toast prefers the
optional credited counts and falls back to current counts while older backend
responses remain in circulation. Locked and non-active detail levels do not
display the ring.

`ScanMilestoneCoordinator` is the single scan-completion notification boundary
for both `InferenceEngine` foreground completion and
`OfflineQueueManager` background completion. It is main-actor isolated and
keys in-flight/recently completed work by the final saved scan ID so live and
background races cannot enqueue the same batch twice. It intentionally waits
through the existing remote-persistence retry window before resolving progress,
then collects achievement unlock payloads with
`enqueueToasts: false`, evaluates the dictionary-contribution flag, and makes
one synchronous presenter enqueue pass. An unrelated banner already on screen
is not preempted; strict ordering applies only within milestones from the same
scan.

`FieldTripMilestonePayload` stores the display title, the first newly completed
item's label, credited counts, and a typed destination. Standard destinations
use `.fieldTrip(templateId:checklistItemId:)`; Seasonal Challenge destinations
use `.fieldTripChallenge(challengeId:)`. `MilestoneToastBanner` renders
**Field trip progress** and `{species} counts toward {trip}` above a compact
linear progress indicator, preserves the shared 3.5-second timeout, haptics,
manual dismissal, queue transition, and VoiceOver announcement, and publishes
`requestOpenCaptureGoal` when tapped. Explore converts the destination into the
standard focused outing route or Seasonal Challenge detail route.

Completed goal tiles render the captured scan full-bleed with a bottom metadata
overlay and the ordinary neutral one-point border. Incomplete focused goals may
still use the accent highlight. Tapping either completed thumbnail routes
through `ExploreView` to `ScanInsightRoute`, loads the saved inference, and
renders `InsightSheetView` with
`InsightPresentationStyle.embeddedInScansLibrary`. The route stays in the
existing Explore `NavigationStack`, exposing a back arrow and interactive back
gesture instead of a nested sheet. If the local record is missing, the
placeholder remains and the shell presents a non-destructive unavailable
message rather than an empty Insight view.

`FieldTripProgress.publicationId` and `publishedAt` are optional for staged
backend/client rollout. `FieldTripPublicationStatusBadge` derives Published
only from a non-null publication ID; completion alone and Community results are
not publication-state signals. The badge uses a green globe for **Published**
and a neutral lock for **Private**, remains fixed-size in its own left-aligned
row above the wrapping title, and exposes explicit VoiceOver labels and
explanations. The active-level progress ring uses a larger 52-point treatment
in outing detail while the camera component retains its compact size.

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
16. `field-trips` Edge Function
17. `get-explore-author-profile` so public profiles include Field trip
   summaries and pins
18. `get-explore-notifications`, `get-explore-unread-notification-count`, and
   `mark-explore-notifications-read` Edge Function updates
19. iOS client update

The Edge Function depends on the migration-created tables and RPCs. The profile
function update depends on `public.get_field_trip_profile_summaries(...)`.
The credited-progress migration must precede the new iOS client so completed
levels can render a full ring, although optional decoding allows the client to
operate safely against the legacy response during a staged rollout. No
`field-trips` Edge Function request-shape change is required for this migration.
When steps 1-10 and the current V4 function are already live, the incremental
toast release requires steps 11-12 before the iOS update; do not redeploy the
function solely for the credited response fields.

Rollback should revert the iOS thumbnail route before rolling back the evidence
link migration. Because `completed_scan_id` is optional, older clients tolerate
either database shape, and rolling back the migration does not delete completion
rows. Do not restore direct `PUBLIC`, `anon`, or `authenticated` execution of
the private catalog/detail RPCs. Existing `user_field_trips` and publication
rows are user data and should not be dropped casually after release.
Placeholder field trips should be retired through
`field_trip_templates.is_active`, as Forest Edges is, rather than deleting their
template graph.

Rolling back credited progress is response-compatible: older fields remain the
source of truth and the iOS fallback continues to render them. Preserve both
progress functions' existing execute permissions and security contract during
any rollback; do not drop completion rows or rewrite scan history.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts services/supabase/functions/_tests/fieldTripProgressDb.test.ts services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts
deno check --config services/supabase/functions/field-trips/deno.json services/supabase/functions/field-trips/index.ts
deno test --config services/supabase/functions/field-trips/deno.json --allow-read services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/field-trips/db_test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/fieldTripProgressDb.test.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/fieldTripLifecycleDb.test.ts
supabase db lint --workdir services
```

iOS:

```sh
make xcodegen
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:merianTests/FieldTripAPIModelsTests \
  -only-testing:merianTests/FieldTripCaptureContextModelsTests \
  -only-testing:merianTests/ActiveCaptureGoalStoreTests \
  -only-testing:merianTests/AchievementToastPresenterTests \
  -only-testing:merianTests/InsightSheetViewModelTests \
  -only-testing:merianTests/AppTelemetryTests test
```

The database integration tests require the local Supabase/Postgres stack. They
report a skip when `127.0.0.1:54322` is unavailable; a skip is not production
database validation. The progress test covers standard and challenge level
advancement, re-identification of the same scan, and idempotent reapplication.

For progress-toast QA, cover partial progress, level advancement, final
completion, multiple standard/challenge matches, re-identification after level
advancement, and idempotent reapplication.
Confirm the response exposes credited counts for the changed level and that
legacy responses still decode through the current-count fallback. For one scan,
verify the visible order is standard outings, Events-visible Seasonal
Challenges, achievements, then **New to Naturebook**; a failed/no-match progress attempt
must release the later milestones only after it finishes, and foreground plus
background completion must enqueue once. Tap a standard toast to open its
focused first credited goal and a challenge toast to open challenge detail.
Use DEBUG Settings -> **Preview Field trip progress toast** for compact and
large-width, long-name, timeout, swipe/close, haptic, and VoiceOver inspection.

For completion-evidence QA, complete a non-leading goal such as Cat and confirm
that only Cat changes in both the catalog card and detail grid. Test both photo
and video completions, confirm the captured thumbnail has the standard neutral
border with no blue completion outline, and tap both surfaces to open the same
embedded Insight view. Back must return to the current outing. A missing local
record must leave the placeholder usable and must not show a blank Insight.
At the database boundary, confirm catalog/detail return the completion row's
exact `scan_id`, only `service_role` can execute their RPCs, and no public or
capture-context payload contains `completed_scan_id`.

For publication-state QA, verify an unstarted, active, completed-but-unpublished,
and deleted-publication outing all show **Private**. Publishing must change the
badge to **Published** after refresh and expose a VoiceOver value that says the
snapshot is public. Confirm template detail returns only the requesting user's
active non-deleted publication ID and that catalog, capture context, public
profile summaries, and completion evidence contracts are unchanged.

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
identity, and deletion semantics are not duplicated into `explore_posts`.
Field trips are intentionally absent from `Trending` and `Nearby` until those
ranking and geoprivacy contracts are designed. Seasonal entry aggregation,
cross-type cursor pagination, widget/APNs, and public-web presentation remain
future work.
