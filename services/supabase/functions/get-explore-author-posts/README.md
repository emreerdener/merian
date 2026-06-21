# Get Explore Author Posts

Returns the paginated published-scan library for one Explore author. This
endpoint powers the full library mode inside `ExploreAuthorProfileSheet`.

## Request

First page:

```json
{
  "author_user_id": "uuid",
  "limit": 30
}
```

Follow-up page:

```json
{
  "author_user_id": "uuid",
  "limit": 30,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

- `author_user_id` is required and must be a UUID.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Authentication is resolved by `withEdgeHandler`; the request body cannot
  choose `self_id`.

## Response

The response is the same card-shaped Explore post projection used by the feed:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "hero_image_url": "https://...",
      "shared_at": "2026-05-03T12:00:00.000Z",
      "author_user_id": "uuid",
      "author_name": "River W.",
      "author_username": "river_w",
      "author_avatar_url": "https://...",
      "hashtags": ["citybioblitz", "springcount"],
      "species_common_name": "River Birch",
      "species_scientific_name": "Betula nigra",
      "pet_identification": null,
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "day",
      "current_month": 5,
      "weather_condition": "clear",
      "weather_temperature_f": 74.0,
      "like_count": 8,
      "comment_count": 1,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false,
      "ranking_value": null
    }
  ]
}
```

The backing RPC is
`public.get_explore_author_posts(self_id, target_author_user_id, max_limit, before_shared_at, before_post_id)`.
The Edge function then batches `public.explore_post_hashtags` by the returned
post IDs so library cards keep the same `hashtags` array as feed cards.

`author_name` remains the display label. `author_username` is the stable handle
stored without `@` and should render as `@river_w` only where a handle is
needed, or when a default/ghost identity has no separate display label.

Rows may include `pet_identification` for dog/cat scans. Its `label` can be used
as the visible card title, but the species common/scientific names remain the
taxonomy source for dictionary links and stats.

## Pagination

Rows are ordered by:

```sql
shared_at DESC, post_id DESC
```

The iOS cursor stores the last row's `shared_at` and `post_id` as:

- `before_shared_at`
- `before_post_id`

This keeps pagination stable when newer posts are inserted above the current
window.

## Visibility Rules

The endpoint returns only posts currently visible to the requester:

- unshared posts excluded
- tombstoned scans excluded
- scans without image media excluded
- scans without a species key excluded
- shadowbanned authors excluded
- both directions of user blocking excluded

Post `location_sharing` controls public location fields; it does not hide
published posts from the author's grid.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-author-posts
deno lint services/supabase/functions/get-explore-author-posts
deno check services/supabase/functions/get-explore-author-posts/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
