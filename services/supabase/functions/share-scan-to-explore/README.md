# share-scan-to-explore

Creates or reactivates the current user's Explore post for one eligible scan.
The endpoint shares the post content; post-level location visibility is stored
separately from the backing scan's `geoprivacy`.

## Request

```json
{
  "scan_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured",
  "media_items": [
    { "kind": "image", "source_media_id": "scan:uuid:image:0", "order_index": 0 },
    {
      "kind": "video",
      "source_media_id": "scan:uuid:video:0",
      "order_index": 1
    }
  ]
}
```

`location_sharing` is optional for backward compatibility. When omitted, the new
or reactivated post uses the scan's current `geoprivacy` as the initial
post-owned value.

`media_items` is optional for legacy clients. When present, it is the ordered
public media selection for this post. New clients should submit
`source_media_id` values returned by `get-explore-composer-media`. Legacy
clients may still submit `source_index` and `thumbnail_source_index` values that
point to the scan's promoted image/video URL arrays; for videos,
`thumbnail_source_index` must resolve to the scan's promoted poster image.
Audio, Describe content, AI/reference images, and Dictionary media are not valid
Explore post media.

For video scans with `scans.captured_media`, `source_media_id` resolves through
the same manifest-aware source list shown by the composer. This keeps the
playback `.mp4` and poster thumbnail paired even when sampled inference frames
also exist in legacy image URL arrays.

Valid location values:

- `open`: project post-owned public coordinates and allow Explore Map and
  non-owned Nearby eligibility when coordinates are safe.
- `obscured`: keep a scrubbed public location label when available, but do not
  expose map coordinates.
- `private`: share the post without public location fields.

Legacy `hidden` input is accepted as `private`.

## Response

```json
{
  "success": true,
  "post_id": "uuid",
  "scan_id": "uuid",
  "shared_at": "2026-06-17T19:30:00.000Z",
  "location_sharing": "obscured"
}
```

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- `scan_id` must belong to the current user.
- Tombstoned scans, media-less scans, and scans without a resolved species are
  not share-eligible.
- Sharing snapshots public image/video URLs into `explore_post_media` for the
  post. Video posts require a public thumbnail image; otherwise the endpoint
  returns `Video thumbnail unavailable.`
- Media selections are validated before the post is reported as shared. Public
  feed/share-state visibility requires at least one saved `explore_post_media`
  row, so a failed media snapshot cannot leave a phantom visible Explore post.
- Describe/observation context is private scan context. It is never copied into
  `field_notes`, hashtags, captions, media metadata, or the public media
  snapshot unless the user manually writes that text into the composer.
- When `media_items` is supplied, only the selected image/video rows are written
  to `explore_post_media`, ordered by `order_index`; the first selected item's
  image URL or video thumbnail becomes the computed `hero_image_url`.
- Empty media selections, non-visual media kinds, invalid source indexes, and
  videos without a thumbnail are rejected.
- If the scan has a resolved Ask the Community request, publishing materializes
  any new GBIF-backed resolved species into `species_dictionary`, sets
  `scans.confirmed_species_id`, and stamps the request's `explore_published_at`
  before the post becomes visible in normal Explore surfaces. Materialization
  also queues species-content provenance rows so normal Dictionary enrichment can
  hydrate the new species over time.
- Private backing scans can be shared; `private` means no public location on the
  post, not blocked sharing.
- The endpoint does not mutate `scans.species_id`, `scans.geoprivacy`, or
  `users.default_geoprivacy`.
- Hashtags are normalized to lowercase text without `#`, capped at five tags,
  and replace the post's existing hashtag edges for this share request.
- `species_common_name` stores the public post common-name snapshot when
  provided; omitted or empty values preserve dictionary fallback behavior.

## Spatial Privacy

The database trigger on `explore_posts` writes post-owned `public_latitude`,
`public_longitude`, `public_coordinate_visibility`, and `public_location_label`
from the saved `location_sharing` value. Even when a post is set to `open`,
protected-species and coordinate-uncertainty rules can store rounded public
coordinates with `coordinate_visibility = "obscured"`.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/share-scan-to-explore/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/communityIdentificationDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.
