# Explore Following

Explore Following is an asymmetric public-profile relationship. It is intentionally a lightweight Follow model, not Friend: there are no mutual requests, private scan grants, DMs, or follower/following list browsers.

## Product Scope

Following does three user-visible things:

- Adds a `Following` feed filter between `Recent` and `Trending`.
- Adds public follower/following counts and a `Follow` / `Following` button to visible Explore author profile sheets.
- Adds an informational in-app "followed you" notification row.

Following does not affect `Recent`, `Trending`, `Nearby`, map results, the
Home Screen widget, APNs pushes, private scan access, or the Explore
author-profile visibility gate. A profile is discoverable only when the target
author has at least one Explore post visible to the requester or at least one
visible Field Trip profile surface.

## UX Rules

- The feed filter order is `Recent`, `Following`, `Trending`, `Nearby`.
- `Following` is reverse-chronological and contains only visible posts from authors the viewer follows.
- The empty state tells viewers to follow authors from public profiles.
- Author profile counts are informational only. They do not open lists in v1.
- Author profile headers show the display name as the primary label and the
  stable `@public_username` handle underneath when available.
- The follow button is hidden on the viewer's own public author profile.
- Follow taps are optimistic. The client applies the returned server state to correct counts after the request completes.
- Follow notifications render in `ExploreNotificationsSheet`, contribute to unread badge counts, and are marked read through the same mark-read path as other Explore activity.
- Follow notification rows are not post-backed, so tapping them does not navigate.

## Database Model

Migration: `services/supabase/migrations/20260511161000_add_explore_following.sql`

Supporting enum migration: `services/supabase/migrations/20260511160000_add_follow_notification_type.sql`

New table:

- `public.user_follows(follower_user_id, followee_user_id, created_at)`

Constraints and privacy:

- Composite primary key: `(follower_user_id, followee_user_id)` for idempotency.
- `CHECK (follower_user_id <> followee_user_id)` rejects self-follows.
- Both foreign keys cascade to `public.users(id)`.
- RLS permits users to insert/delete their own follow rows and read only their own following rows.
- Counts are public on visible profiles, but follower/following identities are not exposed.

Indexes:

- `idx_user_follows_follower_created_at` supports the Following feed and viewer follow-state lookups.
- `idx_user_follows_followee_created_at` supports follower-count lookups.

New and extended RPCs:

- `public.can_view_explore_author_profile(self_id, target_author_user_id)`:
  validates that the target has a currently visible Explore post or Field Trip
  profile surface for the requester.
- `public.get_user_follow_state(self_id, target_author_user_id)`: returns `author_user_id`, `follower_count`, `following_count`, and `viewer_is_following`.
- `public.get_explore_feed_following(self_id, max_limit, before_shared_at, before_post_id)`: returns the same card projection as the feed, filtered to followed authors and ordered by `(shared_at DESC, post_id DESC)`.
- `public.get_explore_author_profile(...)`: now includes `follower_count`, `following_count`, and `viewer_is_following`.
- `public.reparent_user_follows(ghost_id, target_user_id)`: reparents ghost follow relationships during account merge and dedupes conflicts.

## Edge Functions

New Edge Function:

- `services/supabase/functions/set-user-follow`

Request:

```json
{
  "author_user_id": "uuid",
  "is_following": true
}
```

Response:

```json
{
  "success": true,
  "author_user_id": "uuid",
  "follower_count": 12,
  "following_count": 4,
  "viewer_is_following": true
}
```

Follow validation:

- Rejects self-follow before DB writes.
- Rejects mutual blocks.
- Rejects shadowbanned or non-discoverable targets by requiring `can_view_explore_author_profile(...)`.
- Inserts with `ON CONFLICT DO NOTHING`.

Unfollow validation:

- Deletes the row by `(follower_user_id, followee_user_id)`.
- Does not require the target profile to remain visible, so a viewer can always remove a stale follow.

Other Edge Function changes:

- `/get-explore-feed` accepts `filter: "following"` and routes to `public.get_explore_feed_following(...)`.
- `/get-explore-author-profile` returns the new count/state fields.
- `/get-explore-author-profile` can now return visible Field Trip summaries in
  addition to Explore post previews. Follow counts and buttons use the same
  profile visibility gate, so Field Trips can make a followable public profile
  discoverable without exposing scan evidence.
- `/get-explore-notifications` decodes `post_id` as nullable and includes `type: "follow"`.
- `/block-user` removes follow rows in both directions after an idempotent block request.
- `/merge-ghost-profile` calls `reparent_user_follows` before purging the ghost public user row.

## Notification Lifecycle

Follow notifications use `public.explore_post_notifications` with:

- `type = 'follow'`
- `post_id = NULL`
- `triggering_user_id = follower_user_id`
- `user_id = followee_user_id`
- `action_count = 1`
- no `comment_id`, `reaction_emoji`, or `recent_actor_ids`

Follow notifications are created by an `AFTER INSERT` trigger on `user_follows` when the follower is not shadowbanned and neither user blocks the other. They are removed when the follow row is deleted or when either user blocks the other.

The push-delivery trigger intentionally skips `type = 'follow'`. Follow activity is in-app only.

Field Trips V3 reuses this same `user_follows` graph. The Field Trips
`Community` feed uses followed authors for its `For You` buckets and
`Following` filter, and published Field Trips can create
`field_trip_followed_publication` in-app activity for current followers. V3
does not add trip follows, follower-list browsers, friend states, DMs, or
private scan access.

## iOS Implementation

Primary files:

- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Models/ExploreNotification.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Components/NotificationRowView.swift`
- `apps/ios/Merian/Features/Explore/Notifications/Views/ExploreNotificationsSheet.swift`

Important model changes:

- `ExploreFeedFilter.following`
- `ExploreFollowState`
- `ExploreAuthorProfile.followerCount`
- `ExploreAuthorProfile.followingCount`
- `ExploreAuthorProfile.viewerIsFollowing`
- `ExploreNotificationType.follow`
- `ExploreNotification.postId: String?`

Client method:

```swift
MerianNetworkClient.shared.setUserFollow(authorUserId:isFollowing:)
```

## Testing

Backend:

- `services/supabase/functions/_tests/userFollowsDb.test.ts`
- `services/supabase/functions/_tests/exploreFeedDb.test.ts`
- `services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts`
- `services/supabase/functions/_tests/exploreNotificationsDb.test.ts`
- `services/supabase/functions/_tests/mergeGhostProfile.test.ts`

iOS:

- `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`

Useful verification:

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-feed/index.ts services/supabase/functions/get-explore-author-profile/index.ts services/supabase/functions/get-explore-notifications/index.ts services/supabase/functions/set-user-follow/index.ts services/supabase/functions/block-user/index.ts services/supabase/functions/merge-ghost-profile/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreFeedDb.test.ts services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts services/supabase/functions/_tests/exploreNotificationsDb.test.ts services/supabase/functions/_tests/mergeGhostProfile.test.ts services/supabase/functions/_tests/userFollowsDb.test.ts
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

The DB-backed Deno tests skip live assertions when local Supabase Postgres is not running at `127.0.0.1:54322`.
