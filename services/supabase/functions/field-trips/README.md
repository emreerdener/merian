# Field Trips

Action-based Edge Function for Field Trips. The function is authenticated via
`withEdgeHandler`; request bodies cannot choose `self_id`.

The backing SQL lives in
`services/supabase/migrations/20260708021110_field_trips_v1.sql` and
`services/supabase/migrations/20260708033451_field_trips_v2.sql`, plus
`services/supabase/migrations/20260708042713_field_trips_v3_community.sql`.
Deploy all three migrations before deploying this function.

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
- Field Trip likes do not create notifications in V3.
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

Returns published completed Field Trips for the Field Trips `Community`
segment. `mode` accepts `smart`, `following`, or `recent`. `smart` ranks by
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
current unlocked level.

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
  ]
}
```

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
MerianNetworkClient.shared.getFieldTripCommunityPublications(mode:templateId:userRegion:habitatTags:seasonTags:limit:beforeRankBucket:beforePublishedAt:beforePublicationId:)
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

Scan-progress callers are best effort. A failed Field Trip progress call must
not fail scan persistence.

## Deployment Order

1. Apply `20260708021110_field_trips_v1.sql`.
2. Apply `20260708033451_field_trips_v2.sql`.
3. Apply `20260708042713_field_trips_v3_community.sql`.
4. Deploy this function.
5. Deploy `get-explore-author-profile` so profile responses include
   `field_trips`.
6. Deploy `get-explore-notifications`, `get-explore-unread-notification-count`,
   and `mark-explore-notifications-read` so Field Trip activity appears in the
   in-app activity sheet and bell.
7. Ship the iOS client.

## Verification

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/get-explore-notifications services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts services/supabase/functions/get-explore-notifications/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
supabase db lint --workdir services
```
