# Field Trips

Action-based Edge Function for Field Trips. The function is authenticated via
`withEdgeHandler`; request bodies cannot choose `self_id`.

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
  "description": "optional"
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
post likes and comments.

## Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/field-trips/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
```
