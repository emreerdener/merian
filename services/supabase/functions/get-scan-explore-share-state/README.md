# get-scan-explore-share-state

Returns the authoritative Explore share state for one scan owned by the current
viewer. The iOS Insight sheet uses this to reconcile its fast local
`sharedExplorePostId` cache and to hydrate the share/edit composer.

The Edge handler validates the user JWT and supplies both the authenticated
owner UUID and requested scan UUID to a `SECURITY INVOKER` database routine.
That routine is executable only by `service_role`; `PUBLIC`, `anon`, and
`authenticated` have no direct execute grant and cannot substitute another
`self_id`.

`is_explore_feed_visible` is required authoritative state, not a rolling
optional hint. Clients must not infer it when the field is absent. Location
sharing must also be a known server value; an unknown value makes the response
unconfirmed instead of silently changing its privacy meaning.

## Request

```json
{
  "scan_id": "uuid"
}
```

## Response

Live shared post:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-06-17T19:30:00.000Z",
    "community_request_id": null,
    "community_request_status": null,
    "is_explore_feed_visible": true,
    "location_sharing": "open"
  }
}
```

Pending Identify request:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-06-17T19:30:00.000Z",
    "community_request_id": "uuid",
    "community_request_status": "needs_id",
    "is_explore_feed_visible": false,
    "location_sharing": "obscured"
  }
}
```

Resolved Identify request not yet shared to Explore:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-06-17T19:30:00.000Z",
    "community_request_id": "uuid",
    "community_request_status": "resolved",
    "is_explore_feed_visible": false,
    "location_sharing": "open"
  }
}
```

Media-quarantined or moderated publication intent:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-06-17T19:30:00.000Z",
    "community_request_id": null,
    "community_request_status": null,
    "is_explore_feed_visible": false,
    "location_sharing": "private"
  }
}
```

No live shared post:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": null,
    "shared_at": null,
    "community_request_id": null,
    "community_request_status": null,
    "is_explore_feed_visible": false,
    "location_sharing": "obscured"
  }
}
```

## Rules

- Requires an authenticated user through `withEdgeHandler`.
- The lookup is owner-only; it reads only scans where `scans.user_id` is the
  current user.
- For a live shared post, `location_sharing` is the post-owned value saved on
  `explore_posts`.
- For Identify requests, `post_id` remains available for restoration, while
  `is_explore_feed_visible` says whether the post belongs in normal Explore
  feed/map/author/hashtag surfaces.
- Fully media-quarantined and moderated posts likewise preserve their owner-only
  post identity while returning `is_explore_feed_visible = false`. A degraded
  post remains visible when at least one non-missing media item is eligible.
  This matches the canonical public projection instead of confusing publication
  intent with visibility.
- A post is considered live only when it has at least one saved
  `explore_post_media` row. Media-less post rows left by failed snapshot writes
  are treated like no live shared post, so local Share-sheet caches can clear
  phantom Explore posts.
- Resolved Identify requests remain hidden from normal Explore until the owner
  publishes them. That publish action now applies the owner-approved species
  consensus by setting `scans.confirmed_species_id` after materializing any new
  GBIF-backed species, while preserving the original AI `scans.species_id`.
- Pending Identify requests and resolved-but-unpublished Identify requests are
  not feed-visible. A resolved request becomes feed-visible only after the owner
  explicitly publishes it to Explore.
- For no live shared post, `location_sharing` falls back to the scan's current
  `geoprivacy` so create mode can seed the composer.
- The endpoint does not mutate `scans.geoprivacy`, `users.default_geoprivacy`,
  or `explore_posts.location_sharing`.
- Current iOS only applies an HTTP-successful response when it echoes the exact
  requested scan ID and has a coherent topology: UUID post/request IDs,
  parseable share time, paired Community ID/status, a location choice, and no
  feed-visible claim without a post. A hidden post does not require a Community
  request because media quarantine and moderation are independent visibility
  boundaries. A mismatched or partial response preserves the optimistic local
  cache instead of mapping another scan or phantom post onto the open Insight.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-scan-explore-share-state/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreScanShareStateDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.
