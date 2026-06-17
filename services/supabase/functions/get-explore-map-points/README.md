# get-explore-map-points

Returns privacy-safe Explore map clusters or individual post points for the
currently visible map bounds.

## Request

```json
{
  "north_latitude": 30.489,
  "south_latitude": 30.139,
  "east_longitude": -97.517,
  "west_longitude": -98.001,
  "zoom_level": 10.7,
  "limit": 500
}
```

- Bounds are required and validated as latitude/longitude numbers.
- `zoom_level` controls clustering only.
- `limit` defaults to `500` and is capped at `500`.

## Response

Cluster mode:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 30.267,
      "longitude": -97.743,
      "post_count": 36
    }
  ],
  "posts": []
}
```

Post mode:

```json
{
  "mode": "posts",
  "visible_count": 1,
  "clusters": [],
  "posts": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "latitude": 30.267,
      "longitude": -97.743,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "shared_at": "2026-06-17T19:30:00.000Z",
      "author_user_id": "uuid",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

## Privacy Model

The Edge Function reads `public.get_explore_map_posts(...)`, which uses
post-owned `explore_posts.public_latitude` / `public_longitude` and never
derives map output from raw scan GPS at read time.

Map rows require:

- active shared post;
- non-tombstoned backing scan;
- image media and resolved species;
- non-shadowbanned author;
- no viewer/author block in either direction;
- saved post-level `location_sharing = "open"`;
- non-null post-owned public coordinates.

`obscured` and `private` posts can remain visible in non-map Explore surfaces,
but they stay off the map. Open posts can still return
`coordinate_visibility = "obscured"` when protected-species or uncertainty rules
rounded the stored public coordinate.

## Local Verification

```sh
deno check services/supabase/functions/get-explore-map-points/index.ts
deno test services/supabase/functions/get-explore-map-points/cluster.test.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreMapDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.
