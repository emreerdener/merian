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
  "location_sharing": "obscured"
}
```

`location_sharing` is optional for backward compatibility. When omitted, the new
or reactivated post uses the scan's current `geoprivacy` as the initial
post-owned value.

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
