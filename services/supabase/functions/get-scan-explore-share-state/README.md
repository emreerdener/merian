# get-scan-explore-share-state

Returns the authoritative Explore share state for one scan owned by the current
viewer. The iOS Insight sheet uses this to reconcile its fast local
`sharedExplorePostId` cache and to hydrate the share/edit composer.

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
    "location_sharing": "open"
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
- For no live shared post, `location_sharing` falls back to the scan's current
  `geoprivacy` so create mode can seed the composer.
- The endpoint does not mutate `scans.geoprivacy`, `users.default_geoprivacy`,
  or `explore_posts.location_sharing`.

## Local Verification

```sh
deno check services/supabase/functions/get-scan-explore-share-state/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreScanShareStateDb.test.ts
```

DB integration tests require a running local Supabase Postgres instance at the
configured test URL.
