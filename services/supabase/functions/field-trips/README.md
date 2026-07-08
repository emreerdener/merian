# Field Trips

Action-based Edge Function for Field Trips. The function is authenticated via
`withEdgeHandler`; request bodies cannot choose `self_id`.

The backing SQL lives in
`services/supabase/migrations/20260708021110_field_trips_v1.sql`. Deploy that
migration before deploying this function.

## Privacy Contract

- Active profile summaries are checklist-status only.
- Active summaries must not return scan IDs, media URLs, field notes, exact
  coordinates, public location labels, or private evidence.
- Published Field Trips are snapshots in Field Trip tables, not Explore posts.
- Publishing a Field Trip must not create Explore feed posts, Explore map
  points, or Explore notifications.
- Field Trip comments and likes use Field Trip publication tables, not Explore
  post interaction tables.
- Visibility checks must reject shadowbanned authors and mutual blocks.

## Actions

```json
{ "action": "catalog", "user_region": "optional", "limit": 40 }
```

Returns active templates, access state, levels, checklist items, and the
requesting user's active progress.

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

Returns active and published Field Trip summaries visible to the requester.
Active summaries are checklist-status only and must not include scan IDs, media,
field notes, or location details.

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
write `explore_posts`, Explore map points, or Explore notifications.

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
MerianNetworkClient.shared.applyFieldTripProgress(scanId:)
MerianNetworkClient.shared.getFieldTripProfileSummaries(authorUserId:limit:)
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
2. Deploy this function.
3. Deploy `get-explore-author-profile` so profile responses include
   `field_trips`.
4. Ship the iOS client.

## Verification

```sh
deno fmt --check services/supabase/functions/field-trips services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
supabase db lint --workdir services
```
