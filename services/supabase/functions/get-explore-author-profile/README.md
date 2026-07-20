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
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "species_count": 42,
    "current_streak": 5,
    "published_post_count": 19,
    "follower_count": 124,
    "following_count": 17,
    "viewer_is_following": true,
    "viewer_can_report": true,
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
    "preview_posts": [],
    "field_trips": {
      "pinned": [],
      "active": [],
      "published": []
    }
  }
}
```

The backing RPC is `public.get_explore_author_profile(self_id, target_author_user_id, preview_limit)`.

`author_name` is the primary public display label. `author_username` is the
stable handle stored without `@`; iOS renders it beneath the display name as
`@river_w` and uses it for default/ghost author labels.

`follower_count` and `following_count` are public aggregate counts for visible profiles only. They are not list affordances. `viewer_is_following` is specific to the requesting viewer and drives the iOS `Follow` / `Following` button.

`viewer_can_report` is true for a returned non-self profile and controls the
iOS overflow action. It is only a capability hint: `/report-user` independently
re-runs this endpoint's profile visibility contract before accepting a report.

## Privacy Rules

The endpoint returns `404` unless the target author has at least one Explore post currently visible to the requester or at least one visible Field trip profile surface. This prevents arbitrary user UUID lookups from surfacing profile state while allowing active or published Field trips to make an author discoverable.

Profile aggregates use all non-tombstoned scans owned by the target author:

- species count
- current streak
- heatmap
- achievement progress

Preview posts use stricter Explore visibility rules:

- unshared posts excluded
- administratively hidden posts (`moderated_at IS NOT NULL`) excluded
- tombstoned scans excluded
- scans without image media excluded
- scans without a species key excluded
- shadowbanned authors excluded
- both directions of user blocking excluded

Field trip summaries use separate storage from Explore posts:

- active Field trips show template title, level number, and checklist progress only
- active summaries never return scan IDs, media URLs, field notes, or location details
- pinned published Field trips are capped at 3 and are returned before the
  general active/published modules on iOS
- published Field trips return publication IDs and snapshot media from
  `field_trip_publication_items`
- publishing a Field trip does not create Explore feed posts, map points,
  normal Explore post notifications, APNs, widgets, or public web share pages
- Field trip comments, replies, and followed-author publications may appear as
  Field trip-only rows in the in-app Explore activity sheet; they remain
  separate from Explore post notifications and never fan out to APNs
- shadowbanned authors and mutual blocks are excluded

Post `location_sharing` controls public location fields; it does not hide
published posts from profile eligibility.

Follow state:

- Counts are computed from `public.user_follows`.
- Shadowbanned counterpart users are ignored in counts.
- No follower or following identities are returned.
- The profile remains undiscoverable unless the author has at least one visible Explore post or visible Field trip surface for the requester.

Achievement progress returns only `type`, `current_count`, and `last_interaction_at`. It must never return qualifying scan IDs or contribution details.

## Timezone Behavior

The RPC uses the author's latest valid persisted `scans.device_time_zone` for current-streak and heatmap day-boundary calculations. Missing or invalid values fall back to UTC.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-author-profile
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-profile
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-profile/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres instance is not running at `127.0.0.1:54322`.
