# Get Explore Notifications

Returns the viewer's in-app Explore activity feed. This is the source of truth
for the Explore bell badge and notifications sheet.

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

Follow notifications have `post_id = null`. They are shown in-app, contribute to
unread counts, and are marked read by the normal mark-read endpoint, but tapping
them does not navigate to a post.

Mention notifications are created only after `create-explore-comment` resolves
eligible `@username` tokens into `explore_comment_mentions`. They are deduped
against existing comment/reply notifications for the same recipient and comment,
so a post owner or parent commenter does not receive a second activity row when
they are also mentioned in the body.

## Visibility Rules

The SQL RPC filters hidden activity before returning rows:

- unshared posts are excluded
- tombstoned scans are excluded
- media-less posts are excluded
- shadowbanned owners or follow actors are excluded
- blocked actors are excluded in both directions
- soft-deleted or moderated comments are excluded
- follow notifications require the active `user_follows` row to still exist

Post `location_sharing` controls public location fields; it does not hide
post-backed activity.

Follow notifications are removed when the relationship is deleted or either user
blocks the other. Comment mention notifications are removed when the underlying
comment is deleted or moderated.

## Push Behavior

Remote APNs push delivery is layered on top of
`public.explore_post_notifications`, but follow notifications are intentionally
in-app only. The push trigger skips `type = 'follow'`.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-notifications
deno lint services/supabase/functions/get-explore-notifications
deno check services/supabase/functions/get-explore-notifications/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreNotificationsDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
