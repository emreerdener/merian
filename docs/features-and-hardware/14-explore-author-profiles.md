# Explore Author Profiles

Explore author profiles are public, privacy-preserving profile sheets opened from an Explore post's author header. They let a viewer understand an author's public activity and overall Merian progress without exposing private scan IDs or opening private achievement evidence.

## User Experience

- Tapping an author row in the Explore feed opens `ExploreAuthorProfileSheet`.
- Tapping an author row in `ExplorePostDetailView` opens the same sheet unless that detail view is already being presented from a public profile library.
- Tapping the post media still opens `ExplorePostDetailView`; author-profile navigation is intentionally scoped to the header.
- The user's own Profile tab shows an `Explore scans` preview for their currently visible Explore publications. It seeds from locally cached share state when available, then reconciles with the author-post endpoint.
- The profile sheet shows:
  - public avatar and centered serif author display name
  - `@public_username` underneath when available
  - persona derived from species discovered
  - follower and following counts
  - a `Follow` / `Following` button for non-self profiles
  - species discovered
  - current streak
  - 52-week scan heatmap
  - a 3-column preview of up to 9 published Explore scans
  - achievements rendered as informational cards only
- The "View all published scans" button side-transitions the sheet into the author's full published scan library. The leading toolbar button reverses the transition back to the profile content.
- Library tiles open `ExplorePostDetailView` inside the sheet navigation stack. That nested detail disables insight presentation and author-profile presentation to avoid exposing private local state or recursively opening another profile sheet, but public similar-species cards can still open the species dictionary page.
- Preview grids render image-only thumbnails. Species names remain available in Explore detail, but they are not overlaid on profile preview thumbnails.
- Follow counts are display-only in v1. They do not open follower/following lists.
- The follow button is asymmetric and does not create friend requests, mutual-only states, DMs, or access to private scans.
- Logged-in/provider-derived authors keep display names such as `Emre E.` as
  the primary profile/feed label. Default/ghost identities render as
  `@public_username`.
- Author avatars read the resolved `public_avatar_url`. Custom Merian avatars
  under `avatars/{userId}/...` take precedence over OAuth provider avatars.

## Privacy Model

The feature has two separate data scopes:

| Surface | Data scope |
|---|---|
| Profile stats, streak, heatmap, achievements | All of the author's non-tombstoned scans |
| Preview grid and full library | Only the author's currently visible Explore posts |

Profile aggregates intentionally include private scans because they mirror the user's own profile stats at a high level. Published grids never include private scans, unshared posts, tombstoned scans, posts with no image media, or scans that no longer resolve to a species-backed row.

The backend returns a profile only when the target author has at least one Explore post currently visible to the requesting viewer. This prevents the endpoint from becoming a user lookup API.

The same Explore visibility rules apply to both profile and library reads:

- unshared posts are excluded
- tombstoned scans are excluded
- scans without image media are excluded from published post grids
- non-species-backed scans are excluded from published post grids
- shadowbanned authors are hidden
- both directions of user blocking hide the author and posts

Post-level `location_sharing` controls public location fields but does not hide
published posts from profile grids.

Public achievement payloads contain only progress fields:

- `type`
- `current_count`
- `last_interaction_at`

They never include qualifying scan IDs. The iOS `Achievements` component uses `allowsDetailPresentation: false` for public profiles, so tapping an achievement does not open the achievement detail sheet or any qualifying scans.

Follow relationship identities are also private in v1. `get_explore_author_profile` returns aggregate `follower_count`, `following_count`, and the viewer-specific `viewer_is_following` flag, but no endpoint returns browsable follower or following lists.

## Backend

Migration: `services/supabase/migrations/20260511120000_add_explore_author_profiles.sql`

Added database state:

- `public.scans.device_time_zone TEXT`
- `idx_explore_posts_author_shared_at_visible`
- `idx_scans_user_tombstone_timestamp`
- `idx_scans_user_biological_species`

Follow extension migration: `services/supabase/migrations/20260511161000_add_explore_following.sql`

Added follow state:

- `public.user_follows(follower_user_id, followee_user_id, created_at)`
- `public.get_user_follow_state(self_id, target_author_user_id)`
- `public.can_view_explore_author_profile(self_id, target_author_user_id)`

New RPCs:

- `public.get_explore_author_profile(self_id, target_author_user_id, preview_limit)`
- `public.get_explore_author_posts(self_id, target_author_user_id, max_limit, before_shared_at, before_post_id)`

New Edge Functions:

- `services/supabase/functions/get-explore-author-profile`
- `services/supabase/functions/get-explore-author-posts`
- `services/supabase/functions/set-user-follow`
- `services/supabase/functions/update-public-username`
- `services/supabase/functions/update-public-avatar`
- `services/supabase/functions/check-public-username`

The author profile RPC computes species count from distinct biological species-backed scans using `COALESCE(confirmed_species_id, species_id)`. The heatmap and current streak are computed from all non-tombstoned scans and use the author's latest valid persisted `device_time_zone`, falling back to UTC. Current streak accepts today or yesterday as the anchor day, matching local profile grace behavior.

The follow state RPC computes counts from `user_follows` while ignoring shadowbanned counterpart users. The viewer follow flag is computed for the requesting user only. The follow write endpoint requires the target profile to remain visible before inserting, but unfollow deletes the relationship even if visibility later changes.

The author posts RPC returns the same card-shaped `ExplorePost` projection used by the feed, with stable cursor pagination on `(shared_at DESC, post_id DESC)`.

Public username extension:

- `20260526090000_add_public_usernames.sql` adds
  `public.users.public_username` plus validation and backfill helpers.
- Explore Edge DTOs include `author_username` beside `author_name`.
- `author_name` remains the display label; `author_username` is the stable
  handle for profile secondary text and future mentions.

Public avatar extension:

- `20260528120000_add_custom_public_avatars.sql` adds
  `public.users.custom_avatar_url` and `custom_avatar_updated_at`.
- `public.resolve_public_avatar_url(...)` preserves uploaded avatars across
  provider metadata refreshes.
- `update-public-avatar` promotes staged R2 images into
  `avatars/{userId}/...`, updates `public_avatar_url`, and deletes only the
  previous same-user custom avatar.

Ghost-account merge repair:

- `merge-ghost-profile` now re-parents `explore_posts.user_id` along with scans and collections.
- `merge-ghost-profile` also re-parents `explore_community_requests.requested_by` before purging the ghost public user so Ask the Community requests remain visible under Yours and are not removed by `public.users` cascade cleanup.
- `merge-ghost-profile` also calls `reparent_user_follows` before purging the ghost user so anonymous follows survive authentication and duplicate follow rows collapse cleanly.
- `20260511143000_reparent_explore_posts_after_scan_owner_transfer.sql` repairs existing posts whose scan owner changed during an earlier ghost merge.
- `20260622010000_reparent_community_requests_after_identity_merge.sql` repairs existing Community requests whose requester no longer matches the backing scan owner.
- This keeps own-profile Explore previews, author sheets, `is_owned_by_viewer` checks, and Identify's Yours filter aligned with the current Supabase account.

## iOS Implementation

Primary files:

- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`
- `apps/ios/Merian/Features/Explore/Feed/Views/ExplorePostDetailView.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostCard.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Components/ProfilePublicScansPreview.swift`
- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Components/Achievements.swift`

Important model types:

- `ExploreAuthorProfile`
- `ExploreFollowState`
- `ExploreAuthorProfileAward`
- `ExploreAuthorProfileHeatmap`
- `ExploreAuthorProfileHeatmapWeek`
- `ExploreAuthorProfileHeatmapDay`
- `ExploreAuthorPostCursor`
- `ExploreAuthorProfileRoute`
- `PublicUsernameUpdateResponse`

Conversion rules:

- Remote heatmap weeks convert to existing `ProfileHeatmapData`.
- Remote award progress converts to existing `AwardPayload`.
- Remote library rows are registered with `ExploreFeedViewModel.upsertPost(_:)` so detail navigation reuses the shared Explore post store.
- Remote author rows decode optional `authorUsername`. UI renders
  `@authorUsername` under profile display names and uses it as the visible name
  for default/ghost author rows.
- Remote author rows decode `authorAvatarUrl` from the public identity
  projection; the Profile tab updates that projection when a user uploads a
  custom avatar.
- Preferred species names are refreshed for preview/library posts after profile and page loads.
- The local Profile tab preview reads the current Supabase user from the view environment, displays any locally cached published scans immediately, calls `getExploreAuthorPosts(authorUserId:limit:)`, shows a lightweight loading grid while fetching, and renders an empty state when no visible Explore publications are returned.
- Share and unshare flows publish `exploreShareStateChanged` so an already-open Profile tab can refresh its local preview state.

Library pagination behavior:

- The profile response seeds the library with preview posts.
- Additional pages call `getExploreAuthorPosts(authorUserId:limit:cursor:)`.
- Duplicate post IDs are removed after every merge.
- The next cursor is derived from the current last library post's `sharedAt` and `id`.
- Pagination stops when a page is short or the library count reaches `publishedPostCount`.

## API Contract

See `docs/backend-and-data/05-api-contracts.md` for full JSON request and response shapes.

The iOS client methods are:

```swift
MerianNetworkClient.shared.getExploreAuthorProfile(authorUserId:previewLimit:)
MerianNetworkClient.shared.getExploreAuthorPosts(authorUserId:limit:cursor:)
MerianNetworkClient.shared.setUserFollow(authorUserId:isFollowing:)
MerianNetworkClient.shared.updatePublicUsername(_:)
MerianNetworkClient.shared.updatePublicAvatar(r2ObjectKey:mimeType:)
```

## Testing

Backend:

- `services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts`
- `services/supabase/functions/_tests/updatePublicUsername.test.ts`
- Covers aggregate privacy boundaries and cursor pagination.
- Covers username normalization and validation.
- Covers custom-avatar precedence in the public identity DB test.
- Tests skip live assertions when the local Supabase DB is not running at `127.0.0.1:54322`.

iOS:

- `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`
- Covers profile decoding, award/heatmap conversion, and author-post cursor payload construction.
- Covers follow-state decoding and `/set-user-follow` request payload construction.
- Covers `/update-public-avatar` response decoding and request payload
  construction.

Recommended verification:

```sh
deno fmt --check services/supabase/functions/get-explore-author-profile services/supabase/functions/get-explore-author-posts services/supabase/functions/update-public-username services/supabase/functions/update-public-avatar services/supabase/functions/check-public-username services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno lint services/supabase/functions/get-explore-author-profile services/supabase/functions/get-explore-author-posts services/supabase/functions/update-public-username services/supabase/functions/update-public-avatar services/supabase/functions/check-public-username services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno check services/supabase/functions/get-explore-author-profile/index.ts services/supabase/functions/get-explore-author-posts/index.ts services/supabase/functions/update-public-username/index.ts services/supabase/functions/update-public-avatar/index.ts services/supabase/functions/check-public-username/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
deno test services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test services/supabase/functions/update-public-avatar/avatar_test.ts
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

## Deployment Notes

Deploy the migration before deploying the two new Edge Functions. The functions depend on the RPCs and on the `device_time_zone` column existing.

All identify paths now persist `device_time_zone` when the client sends a valid IANA timezone. Existing scans without a timezone continue to compute public profile streaks and heatmaps in UTC.

For custom avatars, deploy
`20260528120000_add_custom_public_avatars.sql` before `update-public-avatar`.
Confirm Cloudflare R2 lifecycle rules do not expire `avatars/`; only
`staging/`, `quarantine/`, and `exports/` should have short expiration rules.
