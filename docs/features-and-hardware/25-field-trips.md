# Field Trips

Field Trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## V4 Scope

- Field Trips live under Explore in `apps/ios/Merian/Features/Explore/FieldTrips/`.
- The Field Trips surface has two page-header segments: `Available` first by
  default and `Community` second for Field Trips-native discovery.
- `Available` can show a `Seasonal Challenges` section above the template
  catalog. Challenges are curated/admin-created only, live inside Field Trips,
  and require an explicit Join.
- Challenges link to existing Field Trip templates but keep separate
  participation, item-completion, badge, entry, like, and comment storage so a
  seasonal challenge can repeat without corrupting normal Field Trip progress or
  publications.
- `Community` has filter chips for `For You`, `Following`, and `Recent`.
  `For You` is deterministic bucketed ranking, not ML.
- Templates are curated in Supabase with region, season, habitat, difficulty,
  rotating-free, Pro access tags, cover images, estimated duration, and curated
  guide sections.
- Checklist items can include curated item-level tips. V4 does not generate
  pre-trip guidance with AI.
- Users can explicitly start a Field Trip from the template detail page before
  their first matching scan.
- Levels unlock sequentially. A scan can complete an item only after the user
  has started that Field Trip.
- New scans can auto-start an eligible Field Trip when the scan matches a
  current-level item.
- A checklist item can match by species, scientific name, taxonomy, ecology,
  habitat text, or dictionary group tag.
- AI matches and later user confirmations/corrections both call the progress
  updater.
- Field Trip comments and likes are separate from Explore post comments and
  likes, even though the iOS UI reuses the compact Explore comment presentation.
- V4 supports profile showcase, up to 3 pinned published Field Trips, completion
  badges for challenges, published Field Trip pages, challenge entry pages,
  template-detail Community previews, and a Field Trips-native Community feed.
  It does not create Explore feed posts, map points, public web share pages,
  APNs, widgets, leaderboards, prizes, rankings, contest windows, or
  sponsored-trip eligibility.

## Product Flow

1. A signed-in or ghost user opens Explore -> Field Trips. The `Available` tab
   loads first, with live/upcoming `Seasonal Challenges` above regular Field
   Trip templates when challenge inventory exists.
2. `/field-trips` with `action: "catalog"` returns accessible and locked
   templates, their levels, checklist items, and any existing progress.
3. Opening a catalog card loads `action: "template_detail"` and shows guide
   sections, levels, curated item tips, and the current start/continue/publish
   state.
4. Tapping Start calls `action: "start"`. Auto-start from matching scans remains
   as a fallback.
5. A new scan or later confirmed/corrected identification calls
   `action: "apply_scan_progress"` with the saved scan ID.
6. The backend verifies scan ownership, compares the scan against the current
   unlocked level, writes item completions, advances levels when needed, and
   returns newly completed items.
7. iOS shows a short progress toast and refreshes catalog/profile modules on
   the next load.
8. Once all levels are complete, the user may publish a Field Trip snapshot
   with an editable title and optional description or AI summary.
9. Published Field Trips appear on public profiles and in Field Trips
   `Community` only. They open `FieldTripPublicationDetailView` with item cards,
   likes, comments, and author identity. Author taps open the existing Explore
   author profile sheet.

## Challenge Flow

1. `/field-trips` with `action: "challenges_catalog"` returns live, upcoming,
   and ended curated challenges with schedule, aggregate counts, access state,
   suggested hashtags, and viewer participation summary.
2. Opening a challenge loads `action: "challenge_detail"` with linked template
   guide context, schedule, aggregate counts, viewer progress, completion badge
   state, and initial published entries.
3. Tapping Join calls `action: "join_challenge"`. The backend starts or
   continues the linked Field Trip, then creates or returns the separate
   challenge participation row.
4. New scans after `joined_at` and before `ends_at` can complete items for the
   current challenge level. Normal Field Trip progress continues independently.
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
- Challenge item completions are keyed by participation and checklist item; they
  do not retroactively satisfy or overwrite normal Field Trip item completions.
- Reprocessing the same scan is idempotent.
- The badge award is server-authoritative and occurs only after challenge
  completion.

## Privacy Model

Active Field Trip progress is visible on public profiles by default, but it is
status-only:

- template title
- current level
- completed count
- target count
- checklist item labels

Active profile summaries must not expose scan IDs, media URLs, field notes,
exact coordinates, public location labels, or private evidence details.

Published Field Trip pages are explicit snapshots stored separately from
Explore posts. Publication items may include species names, taxonomy, reference
images, and selected scan media snapshots, but publishing a Field Trip does not
create Explore feed posts, Explore map points, normal Explore post
notifications, APNs, widgets, or public web pages. Field Trip-only in-app
activity rows for comments, replies, and followed-author publications may
appear in Explore activity and increment the bell, but they never fan out to
push delivery.

Public author profiles can be discoverable through either visible Explore posts
or visible Field Trip surfaces. Field Trip discoverability still respects
shadowbans and mutual blocks.

Challenge participation exposes only aggregate counts unless the user
explicitly publishes a challenge entry or displays a completion badge. Badges do
not expose scan IDs, media URLs, exact locations, field notes, or private
evidence. Challenge entries are public snapshots scoped to Field Trips; they do
not create Explore posts, Explore map rows, APNs, widgets, public web pages, or
automatic Explore hashtags.

## Backend

Field Trip storage is created by
`services/supabase/migrations/20260708021110_field_trips_v1.sql`, extended by
`services/supabase/migrations/20260708033451_field_trips_v2.sql`, and expanded
for Community discovery by
`services/supabase/migrations/20260708042713_field_trips_v3_community.sql`.
Seasonal challenges are added by
`services/supabase/migrations/20260708051414_field_trips_v4_challenges.sql`.

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

- `catalog`: returns active templates, gated access state, levels, checklist
  items, and the viewer's progress.
- `template_detail`: returns one template with guide fields, levels, checklist
  tips, access state, and viewer progress.
- `start`: explicitly starts or unhides the caller's progress row for an
  accessible template.
- `community_publications`: returns visible published completed Field Trips for
  `smart`, `following`, or `recent` mode with optional template filtering and
  stable `(rank_bucket, published_at, publication_id)` pagination.
- `recent_publications`: compatibility alias for `community_publications` with
  `mode: "recent"`.
- `apply_scan_progress`: applies progress for one saved scan owned by the
  caller. V4 keeps the existing `data` payload for normal Field Trip progress
  and adds optional `challenge_updates` for joined live challenges.
- `challenges_catalog`: returns curated seasonal challenges with viewer
  participation summary and aggregate counts.
- `challenge_detail`: returns one challenge, linked template guide context,
  schedule, suggested hashtags, viewer progress, aggregate counts, and initial
  published challenge entries.
- `join_challenge`: explicitly joins a live accessible challenge and
  starts/continues the linked Field Trip.
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
- `set_pinned_publications`: replaces the caller's pinned published Field Trip
  IDs, capped at 3.
- `publish`: snapshots a completed trip into Field Trip publication tables.
- `detail`: returns a visible publication detail page.
- `set_like`: idempotently sets the viewer's Field Trip like state.
- `comments`: returns paginated Field Trip comments.
- `create_comment`: creates a Field Trip comment or one-level reply.

See `services/supabase/functions/field-trips/README.md` and
`docs/backend-and-data/05-api-contracts.md` for payload examples.

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

## Community Ranking

`For You` ranks visible published Field Trips in stable buckets:

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

Field Trip comments, replies, and followed-author publications create rows in
`field_trip_activity_notifications`. These rows are read through
`get_explore_notifications`, counted by `get_unread_explore_notification_count`,
and marked through `mark_explore_notifications_read`. They are not stored in
`explore_post_notifications`, do not call `send-push-notification`, and are
deleted or hidden when relevant comments/publications are removed, authors are
shadowbanned, or either user blocks the other. Field Trip likes intentionally do
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
5. `field-trips` Edge Function
6. `get-explore-author-profile` so public profiles include Field Trip
   summaries and pins
7. `get-explore-notifications`, `get-explore-unread-notification-count`, and
   `mark-explore-notifications-read` Edge Function updates
8. iOS client update

The Edge Function depends on the migration-created tables and RPCs. The profile
function update depends on `public.get_field_trip_profile_summaries(...)`.

Rollback should disable the Explore Field Trips tab before removing backend
state. Existing `user_field_trips` and publication rows are user data and
should not be dropped casually after release.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/get-explore-notifications services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts services/supabase/functions/get-explore-notifications/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
supabase db lint --workdir services
```

iOS:

```sh
make xcodegen
xcodebuild -scheme Merian -project merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Also verify that publishing a Field Trip appears only on profiles and Field
Trips `Community`, and does not create `explore_posts`, Explore feed cards,
Explore map points, normal Explore post notifications, APNs, widgets, or public
web share pages. Comment/reply/followed-publication activity may appear in the
Explore activity sheet and unread count.
