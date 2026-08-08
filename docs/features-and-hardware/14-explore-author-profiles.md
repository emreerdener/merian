# Explore Author Profiles

Explore author profiles are public, privacy-preserving profile routes opened
from visible Explore social surfaces. They live inside the current Explore
navigation stack instead of presenting a second sheet over the feed or post
detail, so active video surfaces underneath are not hidden by a separate modal
layer. They let a viewer understand an author's public activity and overall
Merian progress without exposing private scan IDs or opening private
achievement evidence.

## User Experience

- Tapping an author row in the Explore feed, comments, mentions, or `ExplorePostDetailView` pushes `ExploreAuthorProfileSheet` as an author-profile route inside the active Explore stack.
- Tapping the post media still opens `ExplorePostDetailView`; author-profile navigation is intentionally scoped to the header.
- The user's own Profile tab shows a server-authoritative `Published scans`
  preview for currently visible Explore publications. Local files may supply a
  thumbnail fallback for an already-visible server post, but local share cache
  never creates an extra public tile.
- When a publication needs media recovery, the owner sees concise,
  anchored copy showing the unavailable-media count, a `Review scans` link,
  and an account-scoped dismiss action. Dismissal hides only the Profile notice
  for the current published-recovery totals; changed totals show it again, and
  resolving all published incidents clears the saved dismissal.
  The link opens Scan Library, where a matching compact count and refresh action
  remain anchored above the filters. The refresh link becomes an in-line loading
  indicator while the incident request runs. The grid automatically scopes to
  local scans with media issues when their incident IDs are available.
- The user's own Profile tab also shows active and published Field trip modules
  when the Field trips endpoint returns visible summaries, plus lightweight
  Field trip challenge badges when awarded. Automatic Backyard Safari
  enrollment can supply the first active status-only module before any goal is
  completed.
- The profile route shows:
  - public avatar and centered serif author display name
  - `@public_username` underneath when available
  - persona derived from species discovered
  - follower and following counts
  - a `Follow` / `Following` button for non-self profiles
  - a non-self overflow menu with `Report user` when
    `viewer_can_report == true`
  - species discovered
  - current streak
  - 52-week scan heatmap
  - a 3-column preview of up to 9 published Explore scans
  - active Field trip checklist progress, when visible
  - published Field trip cards, when visible
  - up to 3 pinned published Field trips before the general Field trip modules
  - Field trip challenge completion badges, when visible
  - achievements rendered as informational cards only
- The "View all published scans" button side-transitions the profile route into the author's full published scan library. The leading toolbar button reverses the transition back to the profile content.
- Library tiles open `ExplorePostDetailView` inside the same Explore navigation stack. The post detail carries the originating author-profile depth, disables insight presentation, and blocks one more author-profile hop after `profile -> scan` so users cannot recursively build `profile -> scan -> profile -> scan` stacks. Public similar-species cards can still open the species dictionary page.
- `ExploreAuthorProfileNavigationPolicy.maxProfileDepth` is intentionally `1`: root/feed/detail/comment surfaces can open an author profile, and scans opened from that profile can still be viewed, but those nested scan details do not open another author profile.
- Preview grids are thumbnail-first. Visual posts use their saved image/video
  poster; standalone-audio posts prefer the server-projected species reference
  image and add the waveform badge. Species names remain available in Explore
  detail, but they are not overlaid on profile preview thumbnails.
- Follow counts are display-only in v1. They do not open follower/following lists.
- The follow button is asymmetric and does not create friend requests, mutual-only states, DMs, or access to private scans.
- Reporting opens a reason selector plus optional details (maximum 1,000
  characters), shows loading/error/success state, and dismisses after successful
  submission. It does not automatically block, unfollow, hide, or navigate away
  from the profile.
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
| Preview grid, full library, and visible published count | Only the author's currently visible Explore posts from the canonical projection |
| Owner publication/recovery summary | Owner-only preserved publication intent and media-health totals |
| Active Field trips | Profile-visible status-only checklist progress from `user_field_trips`, including automatic Backyard Safari enrollment |
| Published Field trips | Snapshot items from `field_trip_publications` and `field_trip_publication_items` |
| Field trip Challenge Badges | Badge cards from `field_trip_challenge_badges`, without scan evidence |

Profile aggregates intentionally include private scans because they mirror the
user's own profile stats at a high level. Published grids exclude unshared
posts, tombstoned scans, confirmed-missing media items, all-missing
system-quarantined posts, posts without saved public media, and scans that no
longer resolve to a species-backed row. A private backing scan may support an
explicitly shared post; the post-owned location setting determines whether
public location is withheld. Audio-only posts remain eligible through their
media snapshot plus reference-thumbnail projection.

The backend returns another author's profile only when the target author has at
least one Explore post currently visible to the requesting viewer or at least
one visible Field trip profile surface. This remains the authorization gate,
but automatic profile-visible Backyard Safari enrollment means a known account
normally satisfies it until the unfinished starter is stopped or reset. The
endpoint does not enumerate account IDs. The authenticated owner can retrieve
their own profile with zero visible posts so recovery status remains
explainable.

Backyard Safari enrollment creates its active row with the existing
`is_profile_visible = true` contract. A new or backfilled account can therefore
have a visible Field trip profile surface immediately, even at `0/N` progress.
Stopping or resetting the unfinished outing hides that active row; enrollment
never exposes its scan IDs, media, field notes, coordinates, or location
labels.

The response also includes viewer-scoped `viewer_can_report`. It is false for
self profiles and absent/non-actionable profiles. `/report-user` independently
rechecks the same visibility contract, so the flag is a UI capability hint and
not the security boundary. A hidden last post can make a profile no longer
reportable unless a visible Field trip profile surface still makes that author
discoverable.

The same Explore visibility rules apply to both profile and library reads:

- unshared posts are excluded
- tombstoned scans are excluded
- scans without image media are excluded from published post grids
- non-species-backed scans are excluded from published post grids
- confirmed-missing media items are excluded
- all-missing system-quarantined posts are excluded
- shadowbanned authors are hidden
- both directions of user blocking hide the author and posts

Post-level `location_sharing` controls public location fields but does not hide
published posts from profile grids.

Active Field trip summaries deliberately exclude scan IDs, media URLs, field
notes, exact coordinates, public location labels, and private evidence details.
Field trip challenge badges are also evidence-free: they expose badge title,
challenge title, broad tags, and cover imagery only.
Published Field trip cards link to `FieldTripPublicationDetailView`, not to
normal Explore posts. Field trip Community cards reuse the same author profile
sheet when the author identity is tapped.

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

Publication consistency migration:
`services/supabase/migrations/20260726174555_align_explore_author_publication_contract.sql`

Added follow state:

- `public.user_follows(follower_user_id, followee_user_id, created_at)`
- `public.get_user_follow_state(self_id, target_author_user_id)`
- `public.can_view_explore_author_profile(self_id, target_author_user_id)`

New RPCs:

- `public.get_explore_author_profile(self_id, target_author_user_id, preview_limit)`
- `public.get_explore_author_posts(self_id, target_author_user_id, max_limit, before_shared_at, before_post_id)`
- `public.get_owned_explore_publication_summary(self_id)`
- `public.get_explore_publication_health_summary()`

New Edge Functions:

- `services/supabase/functions/get-explore-author-profile`
- `services/supabase/functions/get-explore-author-posts`
- `services/supabase/functions/set-user-follow`
- `services/supabase/functions/update-public-username`
- `services/supabase/functions/update-public-avatar`
- `services/supabase/functions/check-public-username`
- `services/supabase/functions/report-user`

User-report extension:

- `20260719161112_add_internal_admin_foundation.sql` adds service-owned
  `public.user_reports`, grouped private review cases, and the reversible post
  moderation boundary.
- `get-explore-author-profile` includes `viewer_can_report`.
- `/report-user` accepts only a visible non-self profile, one of the five
  allowed reasons, and optional details capped at 1,000 characters.
- One intake row is upserted per reporter/target without resetting terminal
  moderator state. The action does not call `/block-user`.

The author profile RPC computes species count from distinct biological species-backed scans using `COALESCE(confirmed_species_id, species_id)`. The heatmap and current streak are computed from all non-tombstoned scans and use the author's latest valid persisted `device_time_zone`, falling back to UTC. Current streak accepts today or yesterday as the anchor day, matching local profile grace behavior.

The follow state RPC computes counts from `user_follows` while ignoring shadowbanned counterpart users. The viewer follow flag is computed for the requesting user only. The follow write endpoint requires the target profile to remain visible before inserting, but unfollow deletes the relationship even if visibility later changes.

The profile count, preview, and author-post grid all derive from
`explore_projected_post_cards(self_id)`. The owner-only publication summary
separates author intent from visible posts and active media-recovery totals. The
service-only health summary exposes aggregate affected-author and post counts
without owner identifiers or object keys.

The author posts RPC returns the same card-shaped `ExplorePost` projection used
by the feed, with stable cursor pagination on
`(shared_at DESC, post_id DESC)`. The Edge response fetches `limit + 1` and
returns explicit `next_cursor` metadata.

Public username extension:

- `20260526090000_add_public_usernames.sql` adds
  `public.users.public_username` plus validation and backfill helpers.
- Explore Edge DTOs include `author_username` beside `author_name`.
- `author_name` remains the display label; `author_username` is the stable
  handle for profile secondary text and current comment mentions. Historical
  comment rows retain the token snapshot that appeared in their plain-text body
  while routing profile taps by the durable user ID.

Public avatar extension:

- `20260528120000_add_custom_public_avatars.sql` adds
  `public.users.custom_avatar_url` and `custom_avatar_updated_at`.
- `public.resolve_public_avatar_url(...)` preserves uploaded avatars across
  provider metadata refreshes.
- `update-public-avatar` promotes staged R2 images into
  `avatars/{userId}/...`, updates `public_avatar_url`, and deletes only the
  previous same-user custom avatar.

Ghost-account merge repair:

- The pending schema-aware `merge-ghost-profile` hardening defines explicit,
  source-controlled policies for Explore ownership, Community requests, follows,
  and every other eligible user foreign key inside one transaction. It must
  resolve reviewed duplicate relationships before deleting the Ghost profile,
  so public identity and the Yours filters remain aligned without cascade loss.
  The source-issued proof remains provider-bound and the scheduled cleanup
  worker removes only the now-empty anonymous Auth shell after commit.
- `20260511143000_reparent_explore_posts_after_scan_owner_transfer.sql` repairs existing posts whose scan owner changed during an earlier ghost merge.
- `20260622010000_reparent_community_requests_after_identity_merge.sql` repairs existing Community requests whose requester no longer matches the backing scan owner.
- This keeps own-profile Explore previews, author sheets, `is_owned_by_viewer` checks, and Identify's Yours filter aligned with the current Supabase account.

Field trips extension:

- `20260708021110_field_trips_v1.sql` adds Field trip template, progress,
  publication, like, and comment storage.
- `20260708033451_field_trips_v2.sql` adds template guide fields, item tips,
  starts for other outings and resumes, Recent compatibility support, and
  pinned profile publication metadata.
- `20260708042713_field_trips_v3_community.sql` adds the Field trips Community
  feed RPC, following-weighted ranking metadata, template-filtered Community
  previews, and Field trip-only in-app activity rows.
- `20260708051414_field_trips_v4_challenges.sql` adds curated seasonal
  challenge storage, explicit participation, challenge-specific item
  completions, completion badges, challenge entry snapshots, and challenge entry
  likes/comments.
- `20260730023042_gate_field_trip_progress_by_confidence.sql` can reopen weakly
  supported outing/Event progress and remove invalid profile publications or
  badges after an evidence downgrade.
- `20260802053044_simplify_backyard_and_pollinator_levels.sql` moves both
  starter outings to their current 2/4/4 progression without replacing
  checklist identities.
- `20260803015025_auto_enroll_backyard_safari_level_one.sql` backfills the
  profile-visible starter status for accounts without prior state and installs
  the deny-by-default future-profile trigger.
- `public.user_has_visible_field_trip_profile(...)` extends author-profile
  discoverability.
- `public.get_field_trip_profile_summaries(...)` returns active status-only,
  pinned published, general published Field trip summaries, and V4 challenge
  badges.
- `get-explore-author-profile` includes a `field_trips` object in the profile
  response.
- `field-trips` owns Field trip catalog, template detail, start, Community
  publication feed, Recent compatibility, profile pin, progress, publication,
  like/comment actions, plus V4 challenge catalog/detail/join/progress,
  challenge entry publication/detail/like/comment, and challenge hashtag
  suggestion actions.

## iOS Implementation

Primary files:

- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
- `apps/ios/Merian/Features/Explore/Shell/ExploreView.swift`
- `apps/ios/Merian/Features/Explore/Feed/Views/ExplorePostDetailView.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentsSheet.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostDetailCommentsSection.swift`
- `apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostCard.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Components/ProfilePublicScansPreview.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripProfileModules.swift`
- `apps/ios/Merian/Features/Explore/FieldTrips/FieldTripPublicationDetailView.swift`
- `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
- `apps/ios/Merian/Core/Network/FieldTripAPIModels.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Features/Profile/UserProfile/Components/Achievements.swift`

Important model types:

- `ExploreAuthorProfile`
- `ExploreUserReportReason`
- `ExploreFollowState`
- `ExploreAuthorProfileAward`
- `ExploreAuthorProfileHeatmap`
- `ExploreAuthorProfileHeatmapWeek`
- `ExploreAuthorProfileHeatmapDay`
- `ExploreAuthorPostCursor`
- `ExploreAuthorProfileRoute`
- `ExploreAuthorProfileNavigationPolicy`
- `PublicUsernameUpdateResponse`
- `FieldTripProfileSummaries`
- `FieldTripProfileActiveSummary`
- `FieldTripProfilePublishedSummary`

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
- Remote author rows decode optional `fieldTrips`. The public profile route and
  the local Profile tab render active status-only progress and published cards
  through `FieldTripProfilePreview` / `CurrentUserFieldTripProfilePreview`.
- Remote author rows decode `viewerCanReport`. The profile overflow action calls
  `MerianNetworkClient.reportUser(reportedUserId:reason:details:)`; the server
  remains authoritative if visibility changes after the profile loaded.
- `ExploreAuthorProfileRoute.navigationDepth` and
  `ExplorePostRoute.authorProfileDepth` carry profile nesting depth through the
  Explore stack. `ExploreAuthorProfileNavigationPolicy` gates profile opens at
  the root Explore router, post detail, comments sheet, and inline detail
  comments so blocked taps never create another profile surface.
- Preferred species names are refreshed for preview/library posts after profile and page loads.
- The local Profile tab preview reads the current Supabase user from the view
  environment, calls `getExploreAuthorPosts(authorUserId:limit:)`, and renders
  only server-visible rows. It may use a matching local scan's reference image
  as a thumbnail fallback for that row, but never promotes local share cache
  into the public grid.
- Owner profile stats decode `owner_publication_summary`. A dismissible recovery
  explanation appears above both the preview and full grid when
  `recovery_needed_post_count > 0`; its recovery-specific Scan Library route
  preserves those totals, fetches scan IDs with unavailable media, and enables
  the media-issue scope by default.
- Share and unshare flows publish `exploreShareStateChanged` so an already-open Profile tab can refresh its local preview state.

Library pagination behavior:

- The profile response seeds the library with preview posts.
- Additional pages call `getExploreAuthorPosts(authorUserId:limit:cursor:)`.
- Duplicate post IDs are removed after every merge.
- The next cursor is taken directly from the Edge response's `next_cursor`.
- Pagination stops only when `next_cursor` is `null`; it does not infer
  completion from a separate count or short page.

## API Contract

See `docs/backend-and-data/05-api-contracts.md` for full JSON request and response shapes.

The iOS client methods are:

```swift
MerianNetworkClient.shared.getExploreAuthorProfile(authorUserId:previewLimit:)
MerianNetworkClient.shared.getExploreAuthorPosts(authorUserId:limit:cursor:)
MerianNetworkClient.shared.setUserFollow(authorUserId:isFollowing:)
MerianNetworkClient.shared.reportUser(reportedUserId:reason:details:)
MerianNetworkClient.shared.updatePublicUsername(_:)
MerianNetworkClient.shared.updatePublicAvatar(r2ObjectKey:mimeType:)
MerianNetworkClient.shared.getFieldTripProfileSummaries(authorUserId:limit:)
MerianNetworkClient.shared.getFieldTripPublication(publicationId:)
```

## Testing

Backend:

- `services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts`
- `services/supabase/functions/_tests/updatePublicUsername.test.ts`
- Covers aggregate privacy boundaries and cursor pagination.
- Covers username normalization and validation.
- Covers custom-avatar precedence in the public identity DB test.
- Field trips profile privacy contracts live in
  `services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts`.
- Tests skip live assertions when the local Supabase DB is not running at `127.0.0.1:54322`.

iOS:

- `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`
- Covers profile decoding, award/heatmap conversion, and author-post cursor payload construction.
- Covers follow-state decoding and `/set-user-follow` request payload construction.
- Covers `/update-public-avatar` response decoding and request payload
  construction.
- `apps/ios/MerianTests/Core/Network/FieldTripAPIModelsTests.swift` covers
  Field trip DTO decoding used by profile modules and publication detail.

Recommended verification:

```sh
deno fmt --check services/supabase/functions/get-explore-author-profile services/supabase/functions/get-explore-author-posts services/supabase/functions/update-public-username services/supabase/functions/update-public-avatar services/supabase/functions/check-public-username services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-profile services/supabase/functions/get-explore-author-posts services/supabase/functions/update-public-username services/supabase/functions/update-public-avatar services/supabase/functions/check-public-username services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-author-profile/index.ts services/supabase/functions/get-explore-author-posts/index.ts services/supabase/functions/update-public-username/index.ts services/supabase/functions/update-public-avatar/index.ts services/supabase/functions/check-public-username/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreAuthorProfileDb.test.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/update-public-avatar/avatar_test.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase/migrations services/supabase/functions/_tests/fieldTripsMigrationContract.test.ts
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

## Deployment Notes

Deploy the migrations before deploying the profile and Field trips Edge
Functions. The functions depend on the RPCs and on the `device_time_zone`
column existing.

Deploy `20260719161112_add_internal_admin_foundation.sql` before `/report-user`
or the iOS report action. Reverify author-profile visibility after the migration
because moderated posts must no longer make a profile reportable/public unless
another visible profile surface remains.

For Field trips, apply the complete ordered migration chain through
`20260803015025_auto_enroll_backyard_safari_level_one.sql`; the canonical
sequence is maintained in
[`25-field-trips.md`](25-field-trips.md#deployment-notes). Then deploy the
scan-ingestion functions, `field-trips`, `get-explore-author-profile`, and the
Explore activity functions in that order. The profile endpoint depends on the
Field trip summary RPC when returning `field_trips`, and the Field trips
endpoint depends on the challenge and confidence-policy RPCs when returning
profile challenge badges. Evidence repair can reopen a completed experience,
remove its badge, and hide an invalid publication or entry, so refresh both
owner and public profile modules during release smoke testing.

All identify paths now persist `device_time_zone` when the client sends a valid IANA timezone. Existing scans without a timezone continue to compute public profile streaks and heatmaps in UTC.

For custom avatars, deploy
`20260528120000_add_custom_public_avatars.sql` before `update-public-avatar`.
Confirm Cloudflare R2 lifecycle rules do not expire `avatars/`; only
`staging/`, `quarantine/`, and `exports/` should have short expiration rules.
