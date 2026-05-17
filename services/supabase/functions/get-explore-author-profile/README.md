# Get Explore Author Profile

Returns a privacy-scoped public profile for an Explore author. This endpoint powers `ExploreAuthorProfileSheet` on iOS.

## Request

```json
{
  "author_user_id": "uuid",
  "preview_limit": 9
}
```

- `author_user_id` is required and must be a UUID.
- `preview_limit` is optional, defaults to `9`, and is capped at `30`.
- Authentication is resolved by `withEdgeHandler`; the request body cannot choose `self_id`.

## Response

```json
{
  "data": {
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_avatar_url": "https://...",
    "species_count": 42,
    "current_streak": 5,
    "published_post_count": 19,
    "follower_count": 124,
    "following_count": 17,
    "viewer_is_following": true,
    "heatmap": {
      "total_captures": 124,
      "current_month_captures": 8,
      "year_string": "2026",
      "weeks": []
    },
    "awards": [
      {
        "type": "explorer",
        "current_count": 5,
        "last_interaction_at": "2026-05-03T12:00:00.000Z"
      }
    ],
    "preview_posts": []
  }
}
```

The backing RPC is `public.get_explore_author_profile(self_id, target_author_user_id, preview_limit)`.

`follower_count` and `following_count` are public aggregate counts for visible profiles only. They are not list affordances. `viewer_is_following` is specific to the requesting viewer and drives the iOS `Follow` / `Following` button.

## Privacy Rules

The endpoint returns `404` unless the target author has at least one Explore post currently visible to the requester. This prevents arbitrary user UUID lookups from surfacing profile state.

Profile aggregates use all non-tombstoned scans owned by the target author:

- species count
- current streak
- heatmap
- achievement progress

Preview posts use stricter Explore visibility rules:

- unshared posts excluded
- tombstoned scans excluded
- private-geoprivacy scans excluded
- scans without image media excluded
- scans without a species key excluded
- shadowbanned authors excluded
- both directions of user blocking excluded

Follow state:

- Counts are computed from `public.user_follows`.
- Shadowbanned counterpart users are ignored in counts.
- No follower or following identities are returned.
- The profile remains undiscoverable unless the author has at least one visible Explore post for the requester.

Achievement progress returns only `type`, `current_count`, and `last_interaction_at`. It must never return qualifying scan IDs or contribution details.

## Timezone Behavior

The RPC uses the author's latest valid persisted `scans.device_time_zone` for current-streak and heatmap day-boundary calculations. Missing or invalid values fall back to UTC.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-author-profile
deno lint services/supabase/functions/get-explore-author-profile
deno check services/supabase/functions/get-explore-author-profile/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres instance is not running at `127.0.0.1:54322`.
