# Get Explore Feed

Returns public Explore post cards for the feed tab. The endpoint accepts one `filter` and routes to a dedicated SQL RPC for that mode.

## Filters

- `recent`: default reverse-chronological feed, backed by `public.get_explore_feed(...)`.
- `following`: reverse-chronological feed of followed authors' visible posts, backed by `public.get_explore_feed_following(...)`.
- `trending`: freshness-biased recent-like ranking, backed by `public.get_explore_feed_trending(...)`.
- `nearby`: location-gated radius feed, backed by `public.get_explore_feed_nearby(...)`.

The iOS filter order is `Recent`, `Following`, `Trending`, `Nearby`.

## Request

Recent and Following:

```json
{
  "limit": 20,
  "filter": "following",
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Trending:

```json
{
  "limit": 20,
  "filter": "trending",
  "before_ranking_value": 12,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Nearby:

```json
{
  "limit": 20,
  "filter": "nearby",
  "latitude": 30.2672,
  "longitude": -97.7431,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

## Pagination

- `recent`, `following`, and `nearby` page on `(shared_at DESC, post_id DESC)`.
- `trending` pages on `(ranking_value DESC, shared_at DESC, post_id DESC)`.
- Cursor fields must be omitted for the first page.
- `nearby` requires both `latitude` and `longitude`.

## Visibility Rules

Every mode excludes:

- unshared posts
- tombstoned scans
- scans with no image media
- private-geoprivacy scans
- scans without a species key
- shadowbanned authors
- both directions of user blocking

`following` additionally requires an active `public.user_follows` row where the requester follows the post author. Following does not reveal hidden profiles or grant access to private scans.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-feed
deno lint services/supabase/functions/get-explore-feed
deno check services/supabase/functions/get-explore-feed/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreFeedDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres instance is not running at `127.0.0.1:54322`.
