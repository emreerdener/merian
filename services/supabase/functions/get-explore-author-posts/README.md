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
      "reference_thumbnail_url": "https://.../species-reference.jpg",
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
      "ranking_value": null,
      "media_items": [
        {
          "kind": "audio",
          "url": "https://.../recording.wav",
          "thumbnail_url": null,
          "order_index": 0,
          "duration_seconds": 15.0,
          "has_audio": true
        }
      ]
    }
  ],
  "next_cursor": {
    "before_shared_at": "2026-05-03T12:00:00.000Z",
    "before_post_id": "uuid"
  }
}
```

The backing RPC is
`public.get_explore_author_posts(self_id, target_author_user_id, max_limit, before_shared_at, before_post_id)`.
The Edge function then batches `public.explore_post_hashtags` and
`public.explore_post_media` by the returned post IDs so library cards keep the
same hashtag and ordered-media contracts as feed cards.

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

The Edge function fetches `limit + 1` rows. When another page exists,
`next_cursor` contains the last returned row's:

- `before_shared_at`
- `before_post_id`

At the end, `next_cursor` is `null`. Clients must use this metadata rather than
guessing from a short page or a separately fetched profile count. This keeps
pagination stable when newer posts are inserted above the current window and
prevents count/projection drift from truncating the grid.

## Visibility Rules

The endpoint returns only posts currently visible to the requester:

- unshared posts excluded
- administratively hidden posts (`moderated_at IS NOT NULL`) excluded
- tombstoned scans excluded
- scans without public post-owned media excluded
- scans without a species key excluded
- confirmed-missing media items excluded
- all-missing, system-quarantined posts excluded
- shadowbanned authors excluded
- both directions of user blocking excluded

Post `location_sharing` controls public location fields; it does not hide
published posts from the author's grid.

## Thumbnail Contract

Each author-post row includes both `hero_image_url` and optional
`reference_thumbnail_url`. The latter resolves through
`public_species_first_reference_image_url(scan.species_id,
species_dictionary.reference_image_url)`,
preferring normalized `species_reference_images` and retaining the legacy
dictionary URL fallback. The Edge function adds ordered `media_items`
separately, so clients can detect audio without losing the durable recording
URL.

Compact clients should prefer `reference_thumbnail_url` when `media_items`
contains audio, add an audio indicator, and use `hero_image_url` otherwise.
Feed/detail playback remains media-item-driven and is not replaced by the
reference image. A missing reference URL is valid and should fall through to the
client's normal unavailable/pending thumbnail state. The current user's iOS
Profile grids may use the matching local scan's `referenceImageUrl` as a
compatibility fallback while older deployed RPC payloads remain in circulation.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-author-posts
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-posts
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-posts/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
