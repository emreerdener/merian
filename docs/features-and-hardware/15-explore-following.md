# Explore Following

Explore Following is an asymmetric public-profile relationship. It is intentionally a lightweight Follow model, not Friend: there are no mutual requests, private scan grants, DMs, or follower/following list browsers.

## Product Scope

Following does three user-visible things:

- Adds a `Following` feed filter between `Recent` and `Trending`.
- Adds public follower/following counts and a `Follow` / `Following` button to visible Explore author profile sheets.
- Adds an informational in-app "followed you" notification row.

Following does not affect `Recent`, `Trending`, `Nearby`, map results, the Home Screen widget, APNs pushes, private scan access, or the Explore author-profile visibility gate. A profile is still discoverable only when the target author has at least one Explore post visible to the requester.

## UX Rules

- The feed filter order is `Recent`, `Following`, `Trending`, `Nearby`.
- `Following` is reverse-chronological and contains only visible posts from authors the viewer follows.
- The empty state tells viewers to follow authors from public profiles.
- Author profile counts are informational only. They do not open lists in v1.
- The follow button is hidden on the viewer's own public author profile.
- Follow taps are optimistic. The client applies the returned server state to correct counts after the request completes.
- Follow notifications render in `ExploreNotificationsSheet`, contribute to unread badge counts, and are marked read through the same mark-read path as other Explore activity.
- Follow notification rows are not post-backed, so tapping them does not navigate.

## Database Model

Migration: `supabase/migrations/20260511161000_add_explore_following.sql`

Supporting enum migration: `supabase/migrations/20260511160000_add_follow_notification_type.sql`

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

- `public.can_view_explore_author_profile(self_id, target_author_user_id)`: validates that the target has a currently visible Explore profile for the requester.
- `public.get_user_follow_state(self_id, target_author_user_id)`: returns `author_user_id`, `follower_count`, `following_count`, and `viewer_is_following`.
- `public.get_explore_feed_following(self_id, max_limit, before_shared_at, before_post_id)`: returns the same card projection as the feed, filtered to followed authors and ordered by `(shared_at DESC, post_id DESC)`.
- `public.get_explore_author_profile(...)`: now includes `follower_count`, `following_count`, and `viewer_is_following`.
- `public.reparent_user_follows(ghost_id, target_user_id)`: reparents ghost follow relationships during account merge and dedupes conflicts.

## Edge Functions

New Edge Function:

- `supabase/functions/set-user-follow`

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

## iOS Implementation

Primary files:

- `merian/Core/Network/ExploreAPIModels.swift`
- `merian/Core/Network/MerianNetworkClient.swift`
- `merian/Features/Explore/Views/ExploreView.swift`
- `merian/Features/Explore/Views/ExploreAuthorProfileSheet.swift`
- `merian/Features/Explore/Models/ExploreNotification.swift`
- `merian/Features/Explore/Components/NotificationRowView.swift`
- `merian/Features/Explore/Views/ExploreNotificationsSheet.swift`

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

- `supabase/functions/_tests/userFollowsDb.test.ts`
- `supabase/functions/_tests/exploreFeedDb.test.ts`
- `supabase/functions/_tests/exploreAuthorProfileDb.test.ts`
- `supabase/functions/_tests/exploreNotificationsDb.test.ts`
- `supabase/functions/_tests/mergeGhostProfile.test.ts`

iOS:

- `merianTests/Core/Network/MerianNetworkClientTests.swift`

Useful verification:

```sh
deno check supabase/functions/get-explore-feed/index.ts supabase/functions/get-explore-author-profile/index.ts supabase/functions/get-explore-notifications/index.ts supabase/functions/set-user-follow/index.ts supabase/functions/block-user/index.ts supabase/functions/merge-ghost-profile/index.ts
deno test --allow-env --allow-net supabase/functions/_tests/exploreFeedDb.test.ts supabase/functions/_tests/exploreAuthorProfileDb.test.ts supabase/functions/_tests/exploreNotificationsDb.test.ts supabase/functions/_tests/mergeGhostProfile.test.ts supabase/functions/_tests/userFollowsDb.test.ts
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

The DB-backed Deno tests skip live assertions when local Supabase Postgres is not running at `127.0.0.1:54322`.
