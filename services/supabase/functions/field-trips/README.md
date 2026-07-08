# Field Trips

Action-based Edge Function for Field Trips. The function is authenticated via
`withEdgeHandler`; request bodies cannot choose `self_id`.

The backing SQL lives in
`services/supabase/migrations/20260708021110_field_trips_v1.sql` and
`services/supabase/migrations/20260708033451_field_trips_v2.sql`, plus
`services/supabase/migrations/20260708042713_field_trips_v3_community.sql` and
`services/supabase/migrations/20260708051414_field_trips_v4_challenges.sql`.
Deploy all four migrations before deploying this function.

## Privacy Contract

- Active profile summaries are checklist-status only.
- Active summaries must not return scan IDs, media URLs, field notes, exact
  coordinates, public location labels, or private evidence.
- Published Field Trips are snapshots in Field Trip tables, not Explore posts.
- Publishing a Field Trip must not create Explore feed posts, Explore map
  points, normal Explore post notifications, APNs, widgets, or public web share
  pages.
- Published Field Trips appear on public profiles and the Field Trips
  `Community` segment only, not in Explore Recent, Following, Trending, Nearby,
  map, APNs, or widgets.
- Field Trip comments, replies, and followed-author publications can create
  Field Trip-only in-app activity rows. They appear in Explore activity and may
  increment the bell, but never fan out to push delivery.
- Field Trip comments and likes use Field Trip publication tables, not Explore
  post interaction tables.
- Field Trip likes do not create notifications in V3/V4.
- Seasonal challenges are Field Trips-native. Challenge participation, badges,
  entries, likes, and comments are stored separately from normal Field Trip
  progress/publications.
- Publishing a challenge entry must not create Explore posts, Explore map
  points, APNs, widgets, public web share pages, prizes, leaderboards, or
  automatic Explore hashtags.
- Challenge joins, likes, badges, and progress updates do not notify other users
  in V4.
- Challenge suggested hashtags are optional Explore composer suggestions only;
  this function never auto-posts or auto-tags scans.
- Visibility checks must reject shadowbanned authors and mutual blocks.

## Actions

```json
{ "action": "catalog", "user_region": "optional", "limit": 40 }
```

Returns active templates, access state, levels, checklist items, and the
requesting user's active progress. V2 catalog rows may include
`cover_image_url`, `estimated_duration_minutes`, `guide_where_to_look`,
`guide_why_it_matters`, `guide_safety_ethics`, and item-level `guide_tip`
values.

```json
{ "action": "template_detail", "template_id": "uuid" }
```

Returns one template detail payload with guide fields, levels, checklist tips,
access state, and viewer progress. `slug` may be supplied instead of
`template_id`.

```json
{ "action": "start", "template_id": "uuid" }
```

Explicitly starts or unhides the caller's progress for an accessible template
and returns the refreshed template detail. Matching scans can still auto-start
eligible trips as a fallback.

```json
{
  "action": "community_publications",
  "mode": "smart",
  "template_id": "optional-template-uuid",
  "user_region": "us-ca",
  "habitat_tags": ["neighborhood"],
  "season_tags": ["spring"],
  "limit": 20,
  "before_rank_bucket": 2,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

Returns published completed Field Trips for the Field Trips `Community` segment.
`mode` accepts `smart`, `following`, or `recent`. `smart` ranks by
followed-author plus local/template relevance, followed author, local/habitat/
season match, global fallback, then other visible fallback. Within each bucket,
pagination is stable on
`(rank_bucket ASC, published_at DESC, publication_id DESC)`. `template_id`
filters results for template-detail Community previews.

```json
{
  "action": "recent_publications",
  "user_region": "us-ca",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

`recent_publications` remains as a compatibility alias for
`community_publications` with `mode: "recent"`.

```json
{ "action": "apply_scan_progress", "scan_id": "uuid" }
```

Applies the Field Trip progress rules for one saved scan. The backing RPC only
counts scans owned by the caller, only after a trip starts, and only for the
current unlocked level. V4 also updates joined live challenge progress for the
same scan when the scan was created after `joined_at` and before `ends_at`.

Returns:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "current_level_number": 1,
      "current_level_title": "Level 1",
      "completed_count": 3,
      "target_count": 4,
      "is_complete": false,
      "newly_completed_items": []
    }
  ],
  "challenge_updates": []
}
```

```json
{ "action": "challenges_catalog", "user_region": "optional", "limit": 20 }
```

Returns live/upcoming/ended curated seasonal challenges with schedule, aggregate
counts, access state, suggested hashtags, and the viewer's participation
summary.

```json
{ "action": "challenge_detail", "challenge_id": "uuid", "entries_limit": 12 }
{ "action": "join_challenge", "challenge_id": "uuid" }
```

`challenge_detail` returns one challenge with linked template guide context,
viewer progress, aggregate counts, badge state, and initial published entries.
`join_challenge` is explicit and idempotent for a live accessible challenge; it
starts or continues the linked Field Trip and creates/returns separate challenge
participation.

```json
{ "action": "scan_challenge_hashtags", "scan_id": "uuid" }
```

Returns normalized suggested hashtags for challenge items completed by that
scan, for optional Explore composer suggestions only.

```json
{
  "action": "challenge_publications",
  "challenge_id": "uuid",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_entry_id": "uuid"
}
```

Paginates visible published challenge entries by
`(published_at DESC, entry_id DESC)`.

```json
{ "action": "publish_challenge_entry", "participation_id": "uuid", "title": "optional", "description": "optional" }
{ "action": "challenge_entry_detail", "entry_id": "uuid" }
{ "action": "set_challenge_entry_like", "entry_id": "uuid", "liked": true }
{ "action": "challenge_entry_comments", "entry_id": "uuid", "limit": 50 }
{ "action": "create_challenge_entry_comment", "entry_id": "uuid", "body": "Nice finds!" }
```

Challenge entries are separate snapshots from normal Field Trip publications.
Their likes and comments use challenge-specific tables and never write Explore
post interaction tables.

```json
{ "action": "profile_summaries", "author_user_id": "uuid", "limit": 6 }
```

Returns active, pinned, and published Field Trip summaries visible to the
requester. Active summaries are checklist-status only and must not include scan
IDs, media, field notes, or location details. Pinned summaries are capped at 3
and are omitted from the general `published` list.

```json
{ "action": "set_pinned_publications", "publication_ids": ["uuid"] }
```

Replaces the caller's profile-pinned published Field Trips and returns refreshed
profile summaries. The list is capped at 3 publication IDs.

```json
{
  "action": "publish",
  "user_field_trip_id": "uuid",
  "title": "optional",
  "description": "optional",
  "ai_summary": "optional"
}
```

Publishes a completed Field Trip into Field Trip snapshot tables. This does not
write `explore_posts`, Explore map points, normal Explore post notifications,
APNs, widgets, or public web share pages.

```json
{ "action": "detail", "publication_id": "uuid" }
{ "action": "set_like", "publication_id": "uuid", "liked": true }
{ "action": "comments", "publication_id": "uuid", "limit": 50 }
{ "action": "create_comment", "publication_id": "uuid", "body": "Nice finds!" }
```

Published pages use Field Trip likes and comments stored separately from Explore
post likes and comments. `comments` also accepts the paired cursor fields
`after_created_at` and `after_comment_id`; both must be supplied together.
`create_comment` accepts an optional `parent_comment_id` for one-level replies
and limits body text to 500 characters.

## iOS Callers

The iOS client maps this endpoint through:

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

Scan-progress callers are best effort. A failed Field Trip progress call must
not fail scan persistence.

## Deployment Order

1. Apply `20260708021110_field_trips_v1.sql`.
2. Apply `20260708033451_field_trips_v2.sql`.
3. Apply `20260708042713_field_trips_v3_community.sql`.
4. Apply `20260708051414_field_trips_v4_challenges.sql`.
5. Deploy this function.
6. Deploy `get-explore-author-profile` so profile responses include
   `field_trips`.
7. Deploy `get-explore-notifications`, `get-explore-unread-notification-count`,
   and `mark-explore-notifications-read` so Field Trip activity appears in the
   in-app activity sheet and bell.
8. Ship the iOS client.

## Verification

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/get-explore-notifications services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts services/supabase/functions/get-explore-notifications/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
supabase db lint --workdir services
```
