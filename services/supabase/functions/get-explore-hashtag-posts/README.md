# Get Explore Hashtag Posts

Returns a cursor-paginated Explore post collection for one public hashtag. The
endpoint powers `ExploreHashtagPostsView` after a user taps a tag chip in the
Explore feed or post detail.

## Request

First page:

```json
{
  "hashtag": "#CityBioBlitz",
  "limit": 30
}
```

Follow-up page:

```json
{
  "hashtag": "citybioblitz",
  "limit": 30,
  "before_shared_at": "2026-05-12T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

- `hashtag` is required. The shared normalizer trims leading `#`, lowercases the
  input, and accepts only 2 to 40 letters, digits, or underscores.
- `limit` defaults to `30` and is capped at `100`.
- `before_shared_at` and `before_post_id` must be supplied together.

## Response

The response is the feed-card Explore post projection with
`ranking_value = null` and hydrated hashtags:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "hero_image_url": "https://...",
      "shared_at": "2026-05-12T12:00:00.000Z",
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
      "like_count": 8,
      "comment_count": 1,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false,
      "ranking_value": null
    }
  ]
}
```

The backing RPC is `public.get_explore_hashtag_posts(...)`. The Edge function
hydrates `hashtags` with one batch lookup after the RPC so a row can render the
same chips as feed and author-library cards.

`author_username` is additive beside `author_name` and is stored without `@`.
Clients preserve `author_name` for logged-in display labels and render
`@author_username` for handles/default identities.

Rows may include `pet_identification` for dog/cat scans. Its `label` is a
scan-level display label only; hashtag membership and species navigation still
use the public post and species fields.

## Visibility And Pagination

- Rows order by `(shared_at DESC, post_id DESC)`.
- The RPC excludes unshared posts, tombstoned scans, posts without saved public
  `explore_post_media`, scans without a species key, shadowbanned authors, and
  both directions of user blocking. Audio-only posts remain eligible. Post
  `location_sharing` controls public location fields; it does not hide tagged
  posts.
- The source lookup is `public.explore_post_hashtags(tag, post_id)`. Future
  event and BioBlitz matching should reuse normalized tag edges rather than
  parse public notes.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-hashtag-posts/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreHashtagPostsDb.test.ts
```

The DB integration test skips live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
