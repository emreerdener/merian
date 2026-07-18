# Field trips

Field trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## Current Scope

- Field trips live under Explore in `apps/ios/Merian/Features/Explore/FieldTrips/`.
- The Field trips surface has two page-header segments: `Outings` first by default
  for standard outings and `Events` second for live and upcoming curated
  challenges.
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
- Users can explicitly start an outing from the template detail page before
  their first matching scan.
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
  and **Publish outing**. Never use **Start challenge** or
  **Publish challenge** for a standard outing.
- The Scan capsule remains the action-oriented **Look for: {target}**, not
  **Goal: {target}**. “Goal” names the object; “Look for” tells the user what to
  do while the camera is open.

## Difficulty

Difficulty is manually curated template metadata rather than a value calculated
from duration, checklist size, completion data, user behavior, or access tier:

- `Starter`: onboarding-oriented with familiar, commonly available targets.
- `Easy`: a focused trip reasonably completed in one ordinary field trip.
- `Moderate`: requires a specific habitat, longer effort, or subtler targets.
- `Hard`: specialized, time-dependent, or likely to require multiple field trips.

The standard Field trips catalog shows single-select `All`, `Starter`, `Easy`,
`Moderate`, and `Hard` pills and filters the loaded catalog locally without
changing server ordering or refetching. All levels remain available even when a
level has no current trips. Seasonal Challenges are not difficulty-filtered.
Rotating-free and Pro access rules never affect a template's difficulty.

## Product Flow

1. A signed-in or ghost user opens Explore -> Field trips. The `Outings` segment
   loads first; `Events` separately lists live and upcoming challenges.
2. `/field-trips` with `action: "catalog"` returns accessible and locked
   templates, their levels, checklist items, and any existing progress.
3. Opening a catalog card loads `action: "template_detail"` and shows guide
   sections, levels, curated item tips, and the current start/continue/publish
   state.
4. Tapping **Start outing** calls `action: "start"`. Auto-start from matching
   scans remains as a fallback. Standard outings never use Start/Publish
   Challenge copy; that language is reserved for Seasonal Events.
5. The idle visual Scan page loads `action: "capture_context"` without blocking
   the camera. When unfinished standard goals exist, an instructional
   `Look for: {target}` label is shown beneath the capture-mode picker with its
   outing title and aggregate level progress.
6. Swiping the indicator cycles through all unfinished targets in server order;
   tapping it opens the owning outing and focuses that goal's guide.
7. A new scan or later confirmed/corrected identification calls
   `action: "apply_scan_progress"` with the saved scan ID.
8. The backend verifies scan ownership, compares the scan against the current
   unlocked level, writes item completions, advances levels when needed, and
   returns newly completed items.
9. iOS shows a short progress toast and immediately invalidates the capture
   target context so a completed selection advances naturally.
10. Catalog and detail reloads associate each completed checklist item with the
    exact saved scan that completed it. iOS replaces that item's artwork with
    the scan thumbnail; completion order never determines which slot changes.
11. Tapping a completed goal whose scan still exists on the device pushes the
    existing Insight view inside Explore. The back arrow and swipe-back gesture
    return to the same outing sheet.
12. Once all levels are complete, **Publish outing** creates a Field trip snapshot
   with an editable title and optional description or AI summary.
13. After the detail refreshes, its title badge changes from **Private** to
    **Published**. Deleting the publication returns it to **Private**.
14. Published Field trips appear on public profiles and template Community
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
  target exists, the local `showsCaptureGoalProgress` preference is enabled, the
  staged-capture tray is empty, refinement is inactive, and video is not
  recording.
- Show no loading placeholder when there is no cached context. Camera startup
  and capture remain independent from this request.
- Render beneath `MediaModeToggle` at the same visual width, with a minimum
  56-point height and 36-point bundled goal artwork. On iOS 26 and later
  the untinted capsule uses interactive native Liquid Glass; earlier supported
  versions use a neutral material fallback. Foreground styles remain semantic
  so system contrast adapts to the camera scene and accessibility settings.
  Unknown goals use a neutral binoculars symbol; they must not borrow
  semantically incorrect art.
- Center the instructional `Look for: {target}` prompt and outing title between
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
- Settings > Capture exposes an on-by-default **Field trip goals** toggle. Turning
  it off removes the entire target capsule from Scan without changing outing
  progress, cached goal context, or server state.

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

- force refresh asynchronously when Capture first appears;
- refresh after five stale minutes when the app returns to the foreground or
  the user returns to visual Scan;
- force refresh after outing start/join, standard progress events, account
  changes, and explicit scanner-routing events;
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
- Only scans created at or after `user_field_trips.started_at` can count.
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

Core tables:

- `field_trip_templates`
- `field_trip_levels`
- `field_trip_checklist_items`
- `user_field_trips`
- `user_field_trip_item_completions`
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
- `community_publications`: returns visible published completed Field trips for
  `smart`, `following`, or `recent` mode with optional template filtering and
  stable `(rank_bucket, published_at, publication_id)` pagination.
- `recent_publications`: compatibility alias for `community_publications` with
  `mode: "recent"`.
- `apply_scan_progress`: applies progress for one saved scan owned by the
  caller. V4 keeps the existing `data` payload for normal Field trip progress
  and adds optional `challenge_updates` for joined live challenges.
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
the active standard-outing level header. The level header passes the outing's
completed and total counts; locked and non-active levels do not display the
ring.

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
11. `field-trips` Edge Function
12. `get-explore-author-profile` so public profiles include Field trip
   summaries and pins
13. `get-explore-notifications`, `get-explore-unread-notification-count`, and
   `mark-explore-notifications-read` Edge Function updates
14. iOS client update

The Edge Function depends on the migration-created tables and RPCs. The profile
function update depends on `public.get_field_trip_profile_summaries(...)`.

Rollback should revert the iOS thumbnail route before rolling back the evidence
link migration. Because `completed_scan_id` is optional, older clients tolerate
either database shape, and rolling back the migration does not delete completion
rows. Do not restore direct `PUBLIC`, `anon`, or `authenticated` execution of
the private catalog/detail RPCs. Existing `user_field_trips` and publication
rows are user data and should not be dropped casually after release.
Placeholder field trips should be retired through
`field_trip_templates.is_active`, as Forest Edges is, rather than deleting their
template graph.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts
deno check --config services/supabase/functions/field-trips/deno.json services/supabase/functions/field-trips/index.ts
deno test --allow-read services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
deno test --allow-env --allow-net --allow-read services/supabase/functions/_tests/fieldTripCaptureContextDb.test.ts
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
  -only-testing:merianTests/AppTelemetryTests test
```

The database integration test requires the local Supabase/Postgres stack. It
reports a skip when `127.0.0.1:54322` is unavailable; a skip is not production
database validation.

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
