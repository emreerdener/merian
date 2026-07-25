# Get Explore Feed

Returns public Explore post cards for the feed tab. The endpoint accepts one
`filter` and routes to a dedicated SQL RPC for that mode.

## Filters

- `recent`: default reverse-chronological feed, backed by
  `public.get_explore_feed(...)`.
- `following`: reverse-chronological feed of followed authors' visible posts,
  backed by `public.get_explore_feed_following(...)`.
- `trending`: freshness-biased recent-like ranking, backed by
  `public.get_explore_feed_trending(...)`.
- `nearby`: location-gated radius feed, backed by
  `public.get_explore_feed_nearby(...)`.

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
  "nearby_radius_miles": 25,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Every mode also accepts optional advanced filters:

```json
{
  "filter": "recent",
  "species_categories": ["birds", "insects"],
  "media_types": ["audio", "video"],
  "shared_since": "2026-06-26T12:00:00.000Z"
}
```

- `species_categories` supports the same taxonomy groups as Explore Map:
  `plants`, `fungi`, `birds`, `mammals`, `reptiles`, `amphibians`, `fish`,
  `insects`, `arachnids`, and `other`.
- `media_types` supports `image`, `audio`, and `video`. A mixed-media post
  matches when any saved public media item has a selected kind.
- `shared_since` is an inclusive ISO-8601 cutoff over `shared_at`.
- `nearby_radius_miles` is used only by `nearby`, defaults to `50`, and must be
  between `1` and `100`.

Selections are OR-ed within each group and AND-ed across groups. All advanced
filters execute in SQL before ordering and `LIMIT`, so a page never becomes
sparse because the client discarded non-matching rows after pagination.

## Pagination

- `recent`, `following`, and `nearby` page on `(shared_at DESC, post_id DESC)`.
- `trending` pages on `(ranking_value DESC, shared_at DESC, post_id DESC)`.
- Cursor fields must be omitted for the first page.
- `nearby` requires both `latitude` and `longitude`.
- Clients should keep the same `shared_since` snapshot while paging a date
  window so the result boundary does not drift between pages.
- `nearby` reads post-owned public coordinates from `explore_posts`. For
  non-owned posts, only saved `location_sharing = "open"` posts with stored
  public coordinates can match the radius query.

## Response Hashtags

Every returned card row is hydrated with:

```json
{
  "hashtags": ["citybioblitz", "springcount"]
}
```

Untagged posts return `[]`. The Edge function performs one batched lookup over
the page's `post_id` values in `public.explore_post_hashtags`; feed cards must
not fetch post detail only to render hashtag chips.

## Response Media

Every card includes ordered `media_items` with `kind`, playback `url`, nullable
`thumbnail_url`, `order_index`, `duration_seconds`, and `has_audio`. Approved
standalone WAV posts normally expose their persisted spectrogram PNG through
`thumbnail_url`; non-WAV legacy audio can leave it blank and remains playable.
`hero_image_url` prefers the first saved media thumbnail, so the public web home
grid and metadata can render an audio spectrogram without fetching private scan
state. Compact iOS author/map/profile surfaces may still intentionally prefer
the separately projected species reference thumbnail and waveform badge.

## Response Identity

Every returned card row includes:

```json
{
  "author_name": "Emre E.",
  "author_username": "emre_e",
  "author_avatar_url": "https://..."
}
```

`author_name` is the Explore display label and must keep showing logged-in
display names when present. `author_username` is stored without `@`; clients
render it as `@emre_e` for profile handles and for default/ghost author rows.

## Response Pet Identification

Feed rows may include sanitized dog/cat scan metadata:

```json
{
  "pet_identification": {
    "species_group": "dog",
    "label": "Australian Cattle Dog mix",
    "label_type": "breed_mix",
    "confidence_score": 0.82,
    "evidence": [
      "blue-roan ticking",
      "black saddle patch",
      "compact herding-dog build"
    ]
  }
}
```

Clients may show `pet_identification.label` as the visible card title when
present. `species_common_name` and `species_scientific_name` remain unchanged
for dictionary links, stats, and taxonomy displays.

## Visibility Rules

Every mode excludes:

- unshared posts
- administratively hidden posts (`moderated_at IS NOT NULL`)
- tombstoned scans
- posts with no saved public `explore_post_media` rows
- scans without a species key
- shadowbanned authors
- both directions of user blocking

Post `location_sharing` controls public location fields; it does not hide the
post from non-spatial feed modes. `Nearby` is spatial, so non-owned `obscured`
and `private` posts do not have public coordinates to match.

`following` additionally requires an active `public.user_follows` row where the
requester follows the post author. Following does not reveal hidden profiles or
grant access to private scans.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-feed
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-feed
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-feed/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/_shared/exploreFeedFilters.test.ts services/supabase/functions/get-explore-feed/db.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreFeedDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
