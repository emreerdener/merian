# Get Explore Notifications

Returns the viewer's in-app Explore activity feed. This is the source of truth
for the Explore bell badge and notifications sheet, including Field Trip-only
activity rows that surface inside the same in-app sheet.

## Request

First page:

```json
{
  "limit": 50
}
```

Follow-up page:

```json
{
  "limit": 50,
  "before_updated_at": "2026-05-11T16:10:00.000Z",
  "before_notification_id": "uuid"
}
```

- `limit` is optional and capped server-side.
- Pagination is stable on `(updated_at DESC, notification_id DESC)`.
- Authentication is resolved by `withEdgeHandler`; the request body cannot
  choose `self_id`.

## Notification Types

- `like_aggregated`: post-backed aggregate like row.
- `comment`: post-backed plain comment row.
- `comment_reply`: post-backed reply row.
- `comment_mention`: post-backed mention row.
- `comment_reaction`: post-backed aggregate emoji reaction row for comment
  authors.
- `follow`: postless informational row when another user follows the recipient.
- `field_trip_comment`: Field trip publication comment row.
- `field_trip_reply`: Field trip publication reply row.
- `field_trip_followed_publication`: postless row when a followed author
  publishes a completed Field trip.

Field trip activity types are checked text values on
`public.field_trip_activity_notifications`, not added values on
`public.explore_notification_type`. This keeps the Field trips-only activity
surface deployable independently from the push-backed Explore notification enum.

Follow notifications and Field trip activity have `post_id = null`. Follow rows
are shown in-app, contribute to unread counts, and are marked read by the normal
mark-read endpoint, but tapping them does not navigate to a post. Field trip
rows include `field_trip_publication_id` and route to
`FieldTripPublicationDetailView`.

Mention notifications are created only after `create-explore-comment` resolves
eligible `@username` tokens into `explore_comment_mentions`. They are deduped
against existing comment/reply notifications for the same recipient and comment,
so a post owner or parent commenter does not receive a second activity row when
they are also mentioned in the body.

The mention row retains the historical username token from the comment body and
the durable recipient user ID. A later profile rename or newly reserved old
handle does not rewrite the comment, change notification ownership, or break the
profile route.

## Visibility Rules

The SQL RPC filters hidden activity before returning rows:

- unshared posts are excluded
- administratively hidden posts (`moderated_at IS NOT NULL`) are excluded
- tombstoned scans are excluded
- media-less posts are excluded
- shadowbanned owners or follow actors are excluded
- blocked actors are excluded in both directions
- soft-deleted or moderated comments are excluded
- follow notifications require the active `user_follows` row to still exist
- Field trip activity requires a visible published completed Field trip
- Field trip activity is hidden when the publication, comment, author, actor, or
  follow relationship is no longer visible

Post `location_sharing` controls public location fields; it does not hide
post-backed activity.

Restoring a post can make still-valid activity eligible again. Resolving or
dismissing its review case without a restore does not change visibility.

Follow notifications are removed when the relationship is deleted or either user
blocks the other. Comment mention notifications are removed when the underlying
comment is deleted or moderated.

Field trip activity is removed or hidden when either user blocks the other.
Deleted or moderated Field trip comments no longer appear. Self-actions are
suppressed, and Field trip likes do not create notification rows in V3.

## Push Behavior

Remote APNs push delivery is layered on top of
`public.explore_post_notifications`, but follow notifications and Field trip
activity rows are intentionally in-app only. The push trigger skips
`type = 'follow'`, and `public.field_trip_activity_notifications` has no APNs
trigger, widget fanout, map write, Explore feed card, or Explore post row.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-notifications services/supabase/functions/get-explore-unread-notification-count services/supabase/functions/mark-explore-notifications-read
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-notifications services/supabase/functions/get-explore-unread-notification-count services/supabase/functions/mark-explore-notifications-read
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-notifications/index.ts services/supabase/functions/get-explore-unread-notification-count/index.ts services/supabase/functions/mark-explore-notifications-read/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreNotificationsDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
