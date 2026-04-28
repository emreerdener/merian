# Explore Page RFC

Merian Explore is a manual-share, image-only public feed of discoveries. V1 is intentionally narrow: users can browse posts, like them, and leave comments, while Merian preserves its privacy-first posture for both authenticated and ghost users.

## Locked Product Decisions

- Sharing is manual per eligible scan. A scan does not become public just because its `geoprivacy` is `open`.
- Explore is image-only in V1. Audio is out of scope.
- Post descriptions/captions are out of scope in V1.
- Explore ships a hybrid notifications model: the in-app feed is the source of truth, and eligible likes/comments can also fan out to APNs pushes for users who opt into Explore activity notifications.
- Explore feed posts open a dedicated public post detail page when the user taps the post body.
- The feed comment icon still opens a bottom-sheet comments view for quick interaction from the main feed.
- Explore does not include public user profile pages in V1.
- Feed cards may show:
  - Hero image
  - Species common name and scientific name
  - Author label
  - General location only, at city or state level
  - Author avatar for authenticated users when a public avatar URL is available
  - Like, comment, and external share actions
- The current V1 card layout is:
  - Author row above the image
  - Full-width square image
  - Species common/scientific name plaque over the bottom-left of the image
  - Action row below the image
- The current V1 detail layout is:
  - Author row
  - Full-width hero image
  - Like, comment, and share actions
  - Species section
  - Public species insight cards
  - Privacy-safe telemetry cards
  - Inline comments with an inline composer
- Broad time context and weather data remain available as optional feed metadata. They are not rendered on the primary feed card UI, but they may appear as sanitized telemetry on the detail page.
- Any imported or captured photo already present in the scan library should be eligible for sharing.
- Future scope: feed cards can open a public species page once that separate species-page project exists.

## Goals

- Give users a lightweight way to publish discoveries to a public Explore feed.
- Preserve strong privacy defaults for ghost users and authenticated users.
- Reuse Merian's existing moderation, geoprivacy, blocking, and feed infrastructure where possible.
- Keep V1 species-first rather than person-first.

## Non-Goals

- Audio posts
- Captions, hashtags, follows, DMs, or profile pages
- Complex ranking beyond reverse chronological order
- Public species pages in this scope

## Recommended Product Model

Explore should be treated as a publishing layer on top of scans, not as a direct view over every public scan.

- A user shares a scan.
- Merian creates a public Explore post for that scan.
- Likes and comments belong to the Explore post.
- Unsharing removes the Explore post without deleting the underlying scan.
- One scan should have at most one active Explore post in V1.

This keeps the private scan record separate from the public publication state and makes manual sharing, unsharing, moderation, and future feed-specific behavior much cleaner.

## Identity Model

Explore should render a dedicated public author label rather than relying on raw auth metadata.

Recommended V1 shape on `public.users`:

- `public_author_name TEXT NOT NULL`
- `public_identity_source TEXT NOT NULL`
  - Allowed values: `alias`, `derived_name`, `display_name`
- `public_avatar_url TEXT NULL`

Rules:

- Ghost users default to a stable alias.
- Authenticated users default to `First L.` derived from auth metadata when available.
- If no safe first-name metadata exists, authenticated users also fall back to the stable alias.
- If auth metadata includes a provider avatar (`avatar_url` or `picture`), Merian may copy it into `public_avatar_url` for Explore rendering.
- Ghost users should leave `public_avatar_url` null.
- If Merian later adds editable public names, that should update `public_author_name` and switch the source to `display_name`.
- Feed and comments should only ever render `public_author_name`, and the feed may optionally render `public_avatar_url`.
- Email and raw auth metadata must never be exposed directly in Explore payloads. Public avatar access should happen only through the copied `public.users.public_avatar_url` field.

This gives us the "show a user if logged in, otherwise show an alias" behavior without coupling Explore to private identity fields.

## Feed Card Anatomy

Each Explore card should contain:

- Primary image
- Common name
- Scientific name
- Author label
- Optional author avatar
- General location label
- Like count
- Comment count
- Like button
- Comment button
- External share button
- Overflow actions for block/report/unshare when appropriate

V1 card behavior:

- Tapping the card body pushes a dedicated Explore post detail page inside the Explore navigation stack.
- Tapping comments from the feed opens a bottom-sheet comment view for that post.
- Tapping the overflow menu exposes actions, not navigation.
- The Explore sheet header includes a bell button with an unread badge that opens the in-app notifications/activity view.

## Post Detail Page

The Explore detail page is a fuller public reading surface for a shared post.

It should contain:

- The same privacy-safe author identity used on the feed
- A full-width hero image
- Like, comment, and external share actions
- Common and scientific names
- Public species insight cards backed by `species_dictionary`
- Privacy-safe telemetry such as general location, broad time context, weather, and shared date
- An inline comment thread with an inline composer

Interaction model:

- Feed comment taps intentionally stay in a bottom sheet for quick engagement without leaving the feed.
- Detail-page comment taps should scroll/focus the inline composer rather than opening another modal.
- The detail page should not mount private `InferenceEngine` state. It should use a public Explore detail payload.

## Public Metadata Rules

Explore should never expose exact coordinates.

Location:

- Use the scan's existing semantic location data, but sanitize it down to `City, ST` or just `State`.
- Do not expose exact coordinates, neighborhoods, trails, landmarks, or small-site labels.
- The feed response should omit latitude and longitude entirely.

Time:

- Render broad buckets such as `Morning`, `Afternoon`, `Evening`, or `Night`.
- A month or season can be included if useful, but V1 should avoid minute-level or exact timestamp display.
- The current V1 feed card does not render time metadata, but the feed contract may still return it for detail-page telemetry use.

Weather:

- Show only if already available on the scan.
- Use lightweight display such as `Rainy`, `Clear`, or `68F`.
- The current V1 feed card does not render weather metadata, but the feed contract may still return it for detail-page telemetry use.

## Eligibility Rules

An eligible Explore share in V1 must be:

- An image-backed scan
- Present in the user's scan library
- Biological and safe for public distribution
- Not currently tombstoned or deleted
- Not already represented by another active Explore post

Imported historical photos and in-app captured photos should both be eligible.

## V1 Media Lifecycle

V1 Explore is explicitly ephemeral.

- Explore posts reuse the underlying scan's existing `image_storage_urls`.
- Explore does not create a dedicated durable media copy in V1.
- If a shared scan's backing media is later purged or expires, the Explore post should disappear from the feed.
- Explore payloads should only include posts whose scan still has at least one active image URL.

This keeps the initial implementation smaller and allows us to defer the durable-media decision until later.

Implications:

- Shared Explore posts are not guaranteed to live forever.
- Free-tier posts may naturally age out when the underlying scan media expires.
- Likes and comments can remain attached to the post record, but the post should be hidden whenever media is no longer available.
- "Any imported or captured photo in the scan library is shareable" in V1 means any eligible image-backed scan whose media is currently available.

Future upgrade path:

- If Explore later needs durable public permanence, we can add a dedicated Explore media path without replacing the `explore_posts` wrapper model.

## Data Model Recommendation

Use a thin Explore wrapper around scans.

### `explore_posts`

Suggested fields:

- `id UUID PRIMARY KEY`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE`
- `shared_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `unshared_at TIMESTAMPTZ`
- `like_count INTEGER NOT NULL DEFAULT 0`
- `comment_count INTEGER NOT NULL DEFAULT 0`

Suggested constraints:

- Unique active share per scan in V1
- Query only rows where `unshared_at IS NULL`

### `explore_post_likes`

Suggested fields:

- `post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Suggested constraints:

- `UNIQUE(post_id, user_id)`

### `explore_post_comments`

Suggested fields:

- `id UUID PRIMARY KEY`
- `post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE`
- `user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE`
- `body TEXT NOT NULL`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `deleted_at TIMESTAMPTZ`

Suggested rules:

- No editing in V1
- Soft delete is acceptable if we want moderation history
- Comment text length should be capped server-side

### Counter Strategy

The feed should not compute like/comment aggregates expensively on every page load.

Recommended V1 approach:

- Keep `like_count` and `comment_count` on `explore_posts`
- Update them transactionally in edge functions or via triggers

## Why Not Put Sharing Directly On `scans`

Adding `is_shared_to_explore` directly to `scans` is the fastest-looking option, but it creates long-term coupling:

- Manual share state gets mixed into the private scan record
- Likes/comments would attach to a scan rather than a publication
- Explore-specific storage needs become awkward
- Unshare and moderation logic become harder to reason about
- Future public-feed features will likely need post-specific fields anyway

The `explore_posts` wrapper is the cleaner foundation.

## Backend Surface

Recommended V1 endpoints:

- `share-scan-to-explore`
  - Creates or re-activates an Explore post for a scan
- `unshare-explore-post`
  - Removes the post from the feed
- `get-explore-feed`
  - Returns reverse-chronological Explore cards
- `get-explore-post`
  - Returns a single Explore card projection for notification routing and deep links
- `get-explore-post-detail`
  - Returns public species-detail data for a single Explore post, including conditional per-scan `ai_reasoning` when the underlying identification has not been flagged or overridden
- `get-explore-comments`
  - Returns paginated comments for a post
- `get-explore-notifications`
  - Returns the viewer's Explore activity feed
- `get-explore-unread-notification-count`
  - Returns the unread badge count for the bell icon
- `mark-explore-notifications-read`
  - Marks the viewer's Explore notifications as read
- `set-explore-post-like`
  - Idempotently sets liked state for the viewer
- `create-explore-comment`
  - Creates a comment
- `delete-explore-comment`
  - Deletes a comment if permitted
- `report-explore-comment`
  - Reports a comment for trust-and-safety review

Existing endpoint reuse:

- Reuse `/block-user` for author and commenter blocking.

The in-app notifications feed is the Explore source of truth. Remote APNs fan-out layers on top of that same notification row model through push-device registration plus a server-side webhook trigger.

## Feed Query Rules

`get-explore-feed` should:

- Return only active Explore posts
- Exclude blocked users
- Exclude shadowbanned users
- Exclude unshared posts
- Exclude posts whose scan no longer has active image media
- Order by `shared_at DESC`
- Return only the fields the Explore UI needs

Recommended response fields:

- `post_id`
- `scan_id`
- `hero_image_url`
- `shared_at`
- `author_name`
- `author_avatar_url`
- `species_common_name`
- `species_scientific_name`
- `public_location_label`
- `time_of_day`
- `current_month`
- `weather_condition`
- `weather_temperature_f`
- `like_count`
- `comment_count`
- `viewer_has_liked`
- `is_owned_by_viewer`

The Explore payload should not include:

- Exact coordinates
- Email
- Raw auth metadata
- Full telemetry columns

## Interaction Rules

Likes:

- Likes should be idempotent.
- Users can like their own posts unless product later decides otherwise.
- The feed should return `viewer_has_liked` to support optimistic UI.

Comments:

- Plain text only
- No editing in V1
- Server-side length cap
- Comment author can delete their own comment
- Post owner should also be allowed to remove comments on their own post
- Feed comment entry uses a bottom sheet; detail-page commenting is inline

Notifications:

- The in-app notifications feed is the source of truth for Explore activity.
- Like notifications should aggregate to one row per owner/post, maintain the latest actor names, and reset `is_read` whenever a new like arrives.
- Comment notifications should create one row per visible comment.
- Self-likes and self-comments should never create notifications.
- Opening the notifications sheet should mark the fetched rows as read only after the initial fetch succeeds.
- Users can independently opt into remote Explore activity pushes without enabling discovery-result alerts.

Blocking:

- If user A blocks user B, B's Explore posts and comments should disappear for A.
- Interaction endpoints should reject likes/comments when either direction of blocking should disallow the relationship.

Reporting:

- V1 should support reporting both posts and comments for safety review.

## iOS Architecture

Recommended feature module:

- `merian/Features/Explore/Views/ExploreView.swift`
- `merian/Features/Explore/ViewModels/ExploreFeedViewModel.swift`
- `merian/Features/Explore/ViewModels/ExploreFeedViewModel+Notifications.swift`
- `merian/Features/Explore/ViewModels/ExploreNotificationsViewModel.swift`
- `merian/Features/Explore/Models/ExploreNotification.swift`
- `merian/Core/Network/ExploreAPIModels.swift`
- `merian/Features/Explore/Components/ExplorePostCard.swift`
- `merian/Features/Explore/Components/ExploreCommentsSheet.swift`
- `merian/Features/Explore/Components/NotificationRowView.swift`
- `merian/Features/Explore/Views/ExploreNotificationsSheet.swift`

Routing changes:

- Add `.explore` to `CaptureWorkspaceViewModel.ActiveSheet`
- Route the Explore tab through `CameraSheetRouter`
- Open Explore directly from `MainTabBar`

Share entry points:

- Scan-library context menu
- Insight sheet action menu

Client behavior:

- Explore is online-only in V1
- Likes/comments/shares do not use the offline queue
- Feed pagination should be incremental
- Like and comment counts should update optimistically
- Feed cards can single-tap into detail and double-tap the image to like
- Feed comment taps present `ExploreCommentsSheet`; detail-page comments render inline with the thread
- Explore feed share uses the system share sheet with species text plus the current hero image URL
- The detail page uses a separate public species payload so it can render safe `Taxonomy` and `Habitat & distribution` cards without loading private scan state
- The sheet toolbar bell shows an unread badge, opens the in-app notifications sheet, and uses `get-explore-post` so notification taps can route into posts that are not already present in the loaded feed page

## Implementation Phases

### Phase 1: Schema and API Foundation

- Add Explore tables and public author fields
- Add feed, share, unshare, like, comment, and report endpoints
- Add unit tests for blocking, share eligibility, and idempotency

### Phase 2: Explore Client Foundation

- Add Explore routing and feature module
- Add feed loading, pagination, and empty/error states
- Render V1 cards with privacy-safe metadata

### Phase 3: Share Flow

- Add share/unshare actions to scan-library and insight entry points
- Gate sharing to scans whose image media is currently available
- Prevent duplicate active posts for the same scan

### Phase 4: Interaction and Moderation Polish

- Add comment sheet
- Add optimistic likes and comments
- Add block/report action flows
- Add telemetry for share, like, comment, block, and report events

### Phase 5: Public Post Detail

- Add pushed Explore detail navigation from the feed
- Add privacy-safe telemetry cards on the detail page
- Add inline detail-page comments and composer
- Add a public species-detail payload for safe card reuse
- Reuse public-safe Insight visuals such as `TaxonomyCard`
- Add the in-app notifications sheet, unread badge, and single-post fetch path used by notification taps

### Phase 6: Fast Follow Ups

- Public species page route from Explore cards
- Public user profile pages
- Audio Explore posts
- Ranking and recommendation logic

## Future Species Page Integration

When the public species-page project exists:

- The Explore detail page can route from its species section into `species_dictionary`'s future public page
- Feed cards can either continue opening detail first or optionally deep-link through the same route later
- The Explore data model does not need to change
- The feed can keep reading species metadata from the underlying scan and species join

## Acceptance Criteria For V1

- A user can manually share an eligible image scan to Explore.
- A shared post appears in a reverse-chronological public feed.
- The feed shows privacy-safe author identity and general location.
- Authenticated authors can show a public avatar when a provider avatar URL is available.
- Ghost users can participate with stable aliases.
- Authenticated users show a safe public author label.
- Exact coordinates never appear in Explore payloads.
- Users can like and comment on posts.
- Users can externally share posts from the feed.
- Tapping a feed post opens a public post detail page.
- Tapping the feed comment icon opens a bottom-sheet comment view.
- The detail page shows inline comments plus privacy-safe telemetry and public species cards.
- The bell icon shows an unread count and opens an in-app notifications sheet for likes and comments on the viewer's posts.
- The bell unread count is refreshed on foreground, on a lightweight fallback poll, and by a Supabase realtime subscription to the viewer's notification rows.
- Users can opt into remote Explore activity pushes separately from discovery-result alerts.
- Users can block and report from Explore surfaces.
- Unsharing removes the post from the public feed without deleting the scan.
- Posts disappear from Explore once their backing scan media is no longer available.
