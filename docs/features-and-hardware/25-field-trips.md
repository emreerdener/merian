# Field Trips

Field Trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## V2 Scope

- Field Trips live under Explore in `apps/ios/Merian/Features/Explore/FieldTrips/`.
- The Field Trips surface has two tabs: `Available` first by default and
  `Recent Trips` second for region-aware published completed trips.
- Templates are curated in Supabase with region, season, habitat, difficulty,
  rotating-free, Pro access tags, cover images, estimated duration, and curated
  guide sections.
- Checklist items can include curated item-level tips. V2 does not generate
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
- V2 supports profile showcase, up to 3 pinned published Field Trips, published
  Field Trip pages, and a Field Trips-native `Recent Trips` tab. It does not
  create Explore feed posts, map points, public web share pages, push
  notifications, widgets, leaderboards, prizes, rankings, or sponsored-trip
  eligibility.

## Product Flow

1. A signed-in or ghost user opens Explore -> Field Trips. The `Available` tab
   loads first.
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
9. Published Field Trips appear on public profiles and in the Field Trips
   `Recent Trips` tab only. They open `FieldTripPublicationDetailView` with item
   cards, likes, comments, and author identity.

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
create Explore feed posts, Explore map points, normal Explore notifications,
APNs, widgets, or unread badges.

Public author profiles can be discoverable through either visible Explore posts
or visible Field Trip surfaces. Field Trip discoverability still respects
shadowbans and mutual blocks.

## Backend

Field Trip storage is created by
`services/supabase/migrations/20260708021110_field_trips_v1.sql` and extended
by `services/supabase/migrations/20260708033451_field_trips_v2.sql`.

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

Core RPCs and helpers:

- `public.get_field_trip_catalog(...)`
- `public.get_field_trip_template_detail(...)`
- `public.start_field_trip(...)`
- `public.get_recent_field_trip_publications(...)`
- `public.apply_field_trip_scan_progress(...)`
- `public.get_field_trip_profile_summaries(...)`
- `public.set_field_trip_pinned_publications(...)`
- `public.publish_field_trip(...)`
- `public.get_field_trip_publication_detail(...)`
- `public.get_field_trip_comments(...)`
- `public.can_view_field_trip_publication(...)`
- `public.user_has_visible_field_trip_profile(...)`

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
- `recent_publications`: returns region-aware published completed Field Trips
  with stable `(published_at, publication_id)` pagination.
- `apply_scan_progress`: applies progress for one saved scan owned by the
  caller.
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

Client methods:

```swift
MerianNetworkClient.shared.getFieldTrips(userRegion:limit:)
MerianNetworkClient.shared.getFieldTripTemplate(templateId:)
MerianNetworkClient.shared.startFieldTrip(templateId:)
MerianNetworkClient.shared.getRecentFieldTripPublications(userRegion:habitatTags:limit:beforePublishedAt:beforePublicationId:)
MerianNetworkClient.shared.applyFieldTripProgress(scanId:)
MerianNetworkClient.shared.getFieldTripProfileSummaries(authorUserId:limit:)
MerianNetworkClient.shared.setPinnedFieldTripPublications(publicationIds:)
MerianNetworkClient.shared.publishFieldTrip(userFieldTripId:title:description:aiSummary:)
MerianNetworkClient.shared.getFieldTripPublication(publicationId:)
MerianNetworkClient.shared.setFieldTripLike(publicationId:liked:)
MerianNetworkClient.shared.getFieldTripComments(publicationId:limit:afterCreatedAt:afterCommentId:)
MerianNetworkClient.shared.createFieldTripComment(publicationId:body:parentCommentId:)
```

## Deferred

V2 intentionally excludes leaderboards, prizes, sponsored trips, regional
rankings, and reward eligibility. Those require stronger verification, abuse
controls, moderation policy, and legal/eligibility rules.

## Deployment Notes

Deploy in this order:

1. `20260708021110_field_trips_v1.sql`
2. `20260708033451_field_trips_v2.sql`
3. `field-trips` Edge Function
4. `get-explore-author-profile` Edge Function update
5. iOS client update

The Edge Function depends on the migration-created tables and RPCs. The profile
function update depends on `public.get_field_trip_profile_summaries(...)`.

Rollback should disable the Explore Field Trips tab before removing backend
state. Existing `user_field_trips` and publication rows are user data and
should not be dropped casually after release.

## Verification

Backend:

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts services/supabase/functions/get-explore-author-profile/index.ts services/supabase/functions/get-explore-author-profile/db.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts services/supabase/functions/get-explore-author-profile/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
supabase db lint --workdir services
```

iOS:

```sh
make xcodegen
xcodebuild -scheme Merian -project merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Also verify that publishing a Field Trip appears only on profiles and Field
Trips `Recent Trips`, and does not create `explore_posts`, Explore feed cards,
Explore map points, Explore notifications, APNs, widgets, or unread badges.
