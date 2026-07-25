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
  "limit": 500,
  "species_categories": ["birds"],
  "media_types": ["image", "audio"]
}
```

- Bounds are required and validated as latitude/longitude numbers.
- `zoom_level` controls clustering only.
- `limit` defaults to `500` and is capped at `500`.
- `species_categories` and `media_types` are optional multi-select filters.
  Species values are `plants`, `fungi`, `birds`, `mammals`, `reptiles`,
  `amphibians`, `fish`, `insects`, `arachnids`, and `other`. Media values are
  `image`, `video`, and `audio`. Unknown, duplicate, and non-string values are
  ignored; omitting a group means all values in that group.

## Response

Cluster mode:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "category_counts": [],
  "media_type_counts": [
    { "media_type": "image", "count": 198 },
    { "media_type": "audio", "count": 45 }
  ],
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
  "category_counts": [
    { "category": "birds", "count": 1 }
  ],
  "media_type_counts": [
    { "media_type": "audio", "count": 1 }
  ],
  "clusters": [],
  "posts": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "latitude": 30.267,
      "longitude": -97.743,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "reference_thumbnail_url": "https://.../species-reference.webp",
      "shared_at": "2026-06-17T19:30:00.000Z",
      "author_user_id": "uuid",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
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
- no internal-admin moderation hide (`moderated_at IS NULL`);
- non-tombstoned backing scan;
- published image, video, or audio media and resolved species;
- non-shadowbanned author;
- no viewer/author block in either direction;
- saved post-level `location_sharing = "open"`;
- non-null post-owned public coordinates.

`obscured` and `private` posts can remain visible in non-map Explore surfaces,
but they stay off the map. Open posts can still return
`coordinate_visibility = "obscured"` when protected-species or uncertainty rules
rounded the stored public coordinate.

`pet_identification`, when non-null, is display-only dog/cat metadata copied
from the backing scan. Map previews may show its label, but species routing
continues to use `species_scientific_name`.

## Media Compatibility

`hero_image_url` is always a JSON string for compatibility with deployed
clients. For media-only posts, the response prefers a visual-media poster and
then the normalized species `reference_thumbnail_url`; if neither exists it uses
an empty string so one post cannot invalidate the complete map response. Ordered
`media_items` remain authoritative for playback, media badges, and media-type
filter matching.

Media filtering matches any selected attached kind. Species and media filter
groups intersect, and each group’s counts reflect the active filters in the
other group. A legacy row without `media_items` is treated as an image only when
it still has a non-empty hero image. Facet values with no matching rows are
omitted from the response; the iOS client supplies zero-count rows for its fixed
Images, Videos, and Audio controls.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-map-points/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/get-explore-map-points/contract.test.ts services/supabase/functions/get-explore-map-points/cluster.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreMapDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.

## Deployment

The repository keeps `config.toml` and Functions under `services/supabase`, so
the CLI workdir must be its parent:

```sh
supabase functions deploy get-explore-map-points --workdir services --project-ref <project-ref>
```

Deploy this backward-compatible endpoint addition before distributing an iOS
build that sends `media_types`.
