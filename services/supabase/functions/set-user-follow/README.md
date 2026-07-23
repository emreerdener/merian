# Set User Follow

Idempotently follows or unfollows a visible Explore author profile. This endpoint backs the `Follow` / `Following` button in `ExploreAuthorProfileSheet`.

## Request

```json
{
  "author_user_id": "uuid",
  "is_following": true
}
```

- `author_user_id` is required and must be a UUID.
- `is_following` is required and must be a boolean. `false` is valid and means unfollow.
- Authentication is resolved by `withEdgeHandler`; the request body cannot choose the follower user ID.

## Response

```json
{
  "success": true,
  "author_user_id": "uuid",
  "follower_count": 12,
  "following_count": 4,
  "viewer_is_following": true
}
```

The response is the authoritative state the client should apply after any optimistic UI update.

## Follow Rules

Follow requests are accepted only when all of these are true:

- the target is not the current user
- neither user blocks the other
- the target is not shadowbanned
- the target has a currently visible Explore author profile for the requester

That final visibility check is handled by `public.can_view_explore_author_profile(...)` so the endpoint cannot be used as a general user lookup surface.

The insert path writes to `public.user_follows` with `ON CONFLICT DO NOTHING`, making repeated follow requests safe.

## Unfollow Rules

Unfollow deletes the `(follower_user_id, followee_user_id)` row. It does not require the target profile to still be visible, so a viewer can always remove a stale follow relationship after a block, shadowban, or profile visibility change.

## Side Effects

- Follow creates an in-app `type = 'follow'` notification for the followed user.
- Unfollow deletes that notification.
- Follow notifications are postless (`post_id = NULL`) and never trigger APNs push delivery.
- Blocking either direction removes follow rows and follow notifications.
- Ghost-account merge reparents and deduplicates follow rows inside its private
  atomic transaction.

## Local Verification

```sh
deno fmt --check services/supabase/functions/set-user-follow
deno lint --config services/supabase/functions/deno.json services/supabase/functions/set-user-follow
deno check --config services/supabase/functions/deno.json services/supabase/functions/set-user-follow/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/userFollowsDb.test.ts services/supabase/functions/_tests/exploreNotificationsDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres instance is not running at `127.0.0.1:54322`.
