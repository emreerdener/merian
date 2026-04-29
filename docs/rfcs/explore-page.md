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

## Shipped V1 Snapshot (2026-04-28)

The Explore feed and map shell are now live. The current shipped implementation is:

- `ExploreView` uses a segmented `Feed` / `Map` toolbar control plus a horizontally paged shell. While the map tab is active, the outer pager swipe is intentionally disabled so map pans win over parent horizontal gestures.
- `ExploreMapView` and `ExploreMapViewModel` ship a real MapKit-backed surface with clusters, privacy-aware waypoints, `Search This Area`, `Recenter`, an offline banner, a top-banner empty state, and a two-step preview-card-to-detail interaction.
- Publication state still lives on `explore_posts`, but the shipped map does not store coordinates on `explore_posts`. Spatial reads currently project privacy-safe coordinates from `public.scans.gps_lat_public` / `gps_long_public` through `public.get_explore_map_posts(...)` and the `get-explore-map-points` edge function.
- Migration `20260428213000_fix_explore_map_public_coordinate_fallback.sql` added `trg_sync_scan_public_coordinates` and a server-side fallback so newly shared scans with exact coordinates are normalized/backfilled correctly and do not disappear from the map.
- `ExploreFeedViewModel` is the current shared in-memory mutation source across feed and map. There is no separate shipped `ExplorePostStore` yet.
- Feed pagination now uses a `(shared_at, post_id)` cursor as the canonical shipped model.

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

Normalization rule:

- Public author identity should remain normalized on `public.users`.
- Feed, map, and comment payloads should join `public.users` at read time rather than copying `public_author_name` or `public_avatar_url` into `explore_posts`.
- This allows public alias and avatar updates to flow through to historical Explore content automatically.

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

Explore feed and detail surfaces should never expose exact coordinates. The map may expose privacy-safe public coordinates only when the underlying scan is eligible for exact public display.

Location:

- Use the scan's existing semantic location data, but sanitize it down to `City, ST` or just `State`.
- Do not expose exact coordinates, neighborhoods, trails, landmarks, or small-site labels.
- The feed response should omit latitude and longitude entirely.
- The map response may include only privacy-safe public coordinates: exact for eligible `open` scans, obscured for protected or obscured scans, and no coordinates at all for `private` scans.

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

Current shipped note:

- The live Explore map does not currently persist coordinates on `explore_posts`.
- Spatial reads project from the backing `scans.gps_lat_public` / `gps_long_public` fields through `public.get_explore_map_posts(...)`.
- `trg_sync_scan_public_coordinates` keeps those scan-layer public coordinates normalized from exact coordinates, geoprivacy, and uncertainty.

Future map-coordinate extension if Explore needs a dedicated post-owned spatial projection:

- `public_latitude DOUBLE PRECISION NULL`
- `public_longitude DOUBLE PRECISION NULL`
- `public_coordinate_visibility TEXT NULL`
  - Allowed values: `exact`, `obscured`
- `public_coordinate_version SMALLINT NOT NULL DEFAULT 1`

Coordinate rules for that future extension:

- `public_latitude` and `public_longitude` must never store the raw private scan coordinate unless the post is safe to expose as `open`.
- `public_latitude` and `public_longitude` should be computed at share time from the underlying scan's already-enforced geoprivacy result.
- `obscured` posts should store a stable public display coordinate, not a fresh random jitter on every request.
- `private` scans remain ineligible for Explore and therefore never produce map coordinates.
- `public_coordinate_version` gives Merian a forward path to reprocess stored public map coordinates if the obscuring algorithm changes later.

Eligibility synchronization rules:

- Explore visibility must stay synchronized with the underlying scan after share time.
- A trigger on `scans` updates should hide or unshare the related `explore_posts` row if the scan becomes ineligible, including:
  - `geoprivacy` changing to `private`
  - the scan becoming tombstoned
  - the scan losing all publicly available media
- The same trigger path may also refresh stored public coordinates if a scan changes between `open` and `obscured`.

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
- `get-explore-map-points`
  - Returns privacy-safe map clusters or individual map points for the current visible area
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

Pagination:

- `get-explore-feed` should use cursor pagination, not offset pagination
- The cursor should be `(shared_at, post_id)` so feed paging remains stable while new posts are inserted above the viewer
- Recommended request fields:
  - `before_shared_at`
  - `before_post_id`
  - `limit`
- Current shipped note: this cursor model is now the canonical server and client path.

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

Implementation note:

- Media availability must be cheap to filter.
- If the scan-media visibility check becomes a hot path, prefer a trigger-maintained post-level boolean such as `has_active_media` on `explore_posts`, or at minimum an expression/partial index that prevents repeated full-table scans over media arrays.

`get-explore-feed` should remain card-oriented and reverse-chronological. The map should use a separate endpoint rather than overloading feed pagination with spatial query logic.

## Explore Map Addendum

The Explore map should be a second discovery surface over the same `explore_posts` model, not a separate content system.

Product principle:

- Feed is for passive browsing.
- Map is for spatial browsing.
- Both must open the same public Explore detail page.

Current backend note:

- `explore_posts` remains the publication state model.
- The shipped map projection currently comes from `public.scans.gps_lat_public` / `gps_long_public`, joined through `public.get_explore_map_posts(...)`, rather than stored coordinate fields on `explore_posts`.

### Why Merian Can Beat A Basic Pin Map

The main weakness of competitor-style maps is "pin soup." Once the user zooms out, the product becomes visually dense but informationally weak.

Merian should improve on that by:

- Showing clusters or density at broad zoom levels instead of rendering every post as an equal pin
- Showing individual waypoints only when the camera is close enough for selection to feel intentional
- Using a compact preview card after tap, then opening the full Explore post detail page only on explicit expansion
- Making privacy visible through marker treatment so `obscured` posts look meaningfully different from exact public posts
- Surfacing "what is interesting here?" summaries such as counts, dominant groups, or recent activity rather than only exposing raw coordinates

### Map V1 UX

The Explore sheet already has feed and map tabs. Map V1 should behave like this:

- User opens the `Map` tab.
- The camera starts on either the user's current region or a sensible fallback world/continent view.
- The server returns clusters at broad zoom levels and individual posts at closer zoom levels.
- Panning the map does not immediately destroy the current results. Instead, the UI marks the region as stale and shows a `Search This Area` action.
- Tapping a cluster zooms the camera inward.
- Tapping an individual point selects it and reveals a compact preview card anchored above the bottom tab bar.
- Tapping the preview card opens `ExplorePostDetailView` for the same `post_id`.
- When no results are in view, the shipped empty state uses a top banner only so the map remains fully interactive underneath.

Recommended V1 controls:

- `Nearby`
- `Search This Area`
- `Recenter`
- `Map` or `Hybrid` style toggle if we want a fast-follow visual upgrade

Recommended V1 filters:

- `All`
- `Recent`
- `Nearby`

Taxonomic chips such as `Plants`, `Fungi`, `Birds`, and `Insects` are a good phase-two extension, but the initial map does not need to solve every taxonomy slice on day one.

### Map Selection Model

Map taps should not push full detail immediately.

Recommended interaction sequence:

- First tap selects a point and opens a compact preview card
- Second tap on the selected point, or tap on the preview card, opens `ExplorePostDetailView`
- Deselecting the point collapses the preview card

This keeps the map browsable and prevents the "tap anything, lose your place" problem.

### Map Privacy Model

Explore map coordinates must be stricter than the scan library's private map usage.

Rules:

- `private` scans remain entirely absent from Explore, including the map
- `open` scans may render with exact public coordinates
- `obscured` scans may render only with server-generated public coordinates that represent the obscured area, never the original capture coordinate
- If Merian applies an endangered-species safety offset, the Explore map must use that already-sanitized public coordinate rather than the original point
- The client should never receive raw coordinates for `obscured` posts
- The client should receive a display hint such as `coordinate_visibility: exact|obscured`

Marker treatment:

- `exact` can use a standard pinpoint or image-backed marker
- `obscured` should use a softer glyph or halo so the user understands the location is approximate

### Public Coordinate Strategy

The shipped V1 currently normalizes privacy-safe coordinates at the scan layer.

Current approach:

- `public.scans.gps_lat_public` / `gps_long_public` are the authoritative Explore map coordinates today.
- `trg_sync_scan_public_coordinates` derives them from `gps_lat_exact` / `gps_long_exact`, `geoprivacy`, `coordinate_uncertainty_in_meters`, and species safety context.
- `private` scans produce `NULL` public coordinates and remain absent from the map.
- `obscured` scans are rounded into a stable coarse public cell rather than re-jittered on every request.
- `public.get_explore_map_posts(...)` still derives a privacy-safe fallback server-side if a row has not been normalized yet.

Why this shipped scan-layer approach works:

- Repeated re-jittering creates privacy leakage over multiple requests
- Stable points make the map feel consistent when users pan away and back
- The fallback path fixed the regression where newly shared exact-coordinate scans could exist in Explore but remain invisible on the map

Future refinement:

- If Explore later needs a fully post-owned spatial projection for moderation, archival, or ranking reasons, we can add stored public coordinates to `explore_posts` without changing the current client contract.

### Backend Query Model

The map should not be powered by `get-explore-feed`.

Recommended new endpoint:

- `get-explore-map-points`

Request shape:

```json
{
  "north_latitude": 41.947,
  "south_latitude": 41.748,
  "east_longitude": -87.568,
  "west_longitude": -87.742,
  "zoom_level": 12.3,
  "limit": 300
}
```

Response shape:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 41.873,
      "longitude": -87.632,
      "post_count": 36
    }
  ],
  "posts": []
}
```

```json
{
  "mode": "posts",
  "visible_count": 24,
  "clusters": [],
  "posts": [
    {
      "post_id": "UUID",
      "scan_id": "UUID",
      "latitude": 41.873,
      "longitude": -87.632,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "author_user_id": "UUID",
      "author_name": "Nina P.",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "public_location_label": "Chicago, IL",
      "shared_at": "2026-04-28T21:18:00.000Z",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 72.4,
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false
    }
  ]
}
```

Implementation notes:

- Broad zooms should return cluster rows rather than individual posts
- Close zooms should return individual posts
- The endpoint should keep the same blocking, shadowban, media-availability, and `private` geoprivacy exclusions as `get-explore-feed`
- The endpoint should enforce a hard row cap to prevent pathological city-scale payloads

Clustering strategy:

- V1 does not require PostGIS
- Plain Postgres bounding-box filtering plus zoom-dependent grid bucketing is sufficient
- Bucket coordinates using a zoom-dependent snapped grid such as rounded lat/lon cells or `width_bucket`
- A cluster ID can be derived from the zoom bucket and snapped cell coordinates
- The shipped SQL path already uses a partial public-coordinate index at the scan layer (`idx_scans_public_coordinates_active`); if we ever move to stored post-owned coordinates, add the equivalent index on that projection too

### Map Preview Payload

The map point payload should be rich enough to render a compact card immediately, without an extra round trip.

The preview card needs:

- Hero image
- Common name
- Scientific name
- Public location label
- Author label
- Like/comment counts
- Coordinate visibility

The full detail page can still use the existing `get-explore-post` and `get-explore-post-detail` path after the user commits to the post.

### iOS Client Architecture For Map

Recommended additions:

- `merian/Features/Explore/Views/ExploreMapView.swift`
- `merian/Features/Explore/ViewModels/ExploreMapViewModel.swift`
- `merian/Core/Network/ExploreAPIModels.swift`
- `merian/Features/Explore/ViewModels/ExploreFeedViewModel+Interactions.swift`

Current shipped state on `ExploreMapViewModel`:

- `cameraPosition`
- `visibleRegion`
- `lastCommittedRegion`
- `needsSearchInArea`
- `isLoading`
- `errorMessage`
- `mode`
- `clusters`
- `posts`
- `selectedPostId`
- `visibleCount`
- `isOffline`

State machine:

1. On first appearance, request a starting camera position and perform an initial fetch
2. While the user pans or zooms, update `visibleRegion`
3. Once the camera movement settles, compare `visibleRegion` against `lastCommittedRegion`
4. If the delta is meaningful, set `needsSearchInArea = true`
5. When the user taps `Search This Area`, call `get-explore-map-points`
6. If the response is `clusters`, render clusters and clear any selected post
7. If the response is `posts`, render point annotations
8. On point tap, set `selectedPost`
9. On preview-card tap, route to `ExplorePostDetailView(postId:)`

Technical notes:

- Use SwiftUI `Map` and `MapCameraPosition`
- Debounce camera-driven fetch eligibility rather than firing a network request on every frame
- Reuse the existing Explore detail route already owned by `ExploreView`
- Keep selection state local to the map view model so the feed view model does not absorb spatial UI concerns
- In the shipped V1, feed and map mutations converge through `ExploreFeedViewModel`, which acts as the current shared in-memory mutation source for likes, comment counts, unshares, reports, and blocks

### Search And Caching Behavior

Current shipped V1 behavior:

- Keep the last successful result set on screen while the user pans
- Only replace results after a successful "search this area" fetch
- Cap rendered individual post annotations to a strict upper bound such as 500
- If map fetches fail because the device is offline, show an explicit offline banner rather than silently leaving the map in a stale state

Fast-follow opportunities:

- Cache recent map queries in memory by coarse bounding box plus filter state
- Eagerly evict point annotations that fall outside an expanded region around the last committed viewport to reduce long-distance panning memory growth
- Prefetch `get-explore-post` for the selected marker if we want instant detail transitions later

### Rollout Strategy

Recommended delivery order:

- Phase 1: feed ships first
- Phase 2: map tab placeholder ships
- Phase 3: map endpoint plus static preview card
- Phase 4: clustering and privacy-aware marker system
- Phase 5: map polish such as summaries, taxon chips, and richer nearby UX

This sequencing keeps the map from blocking the already-valuable feed surface.

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
- After a successful report, the client should locally hide the reported post or comment for that reporting user immediately rather than waiting for a full feed refresh.

## iOS Architecture

Recommended feature module:

- `merian/Features/Explore/Views/ExploreView.swift`
- `merian/Features/Explore/Views/ExploreMapView.swift`
- `merian/Features/Explore/ViewModels/ExploreFeedViewModel.swift`
- `merian/Features/Explore/ViewModels/ExploreMapViewModel.swift`
- `merian/Features/Explore/ViewModels/ExploreFeedViewModel+Interactions.swift`
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
- Feed pagination is cursor-based on `(shared_at, post_id)`
- Like and comment counts should update optimistically
- Feed cards can single-tap into detail and double-tap the image to like
- The map should use a dedicated spatial endpoint rather than piggybacking on feed pagination
- The map should keep stale results visible while the user pans and only refetch on an explicit `Search This Area` action
- Marker selection should open a preview card first and only then open full detail
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

### Phase 6: Explore Map

- Add `get-explore-map-points`
- Normalize privacy-safe public coordinates on `scans` through `trg_sync_scan_public_coordinates` and `public.get_explore_map_posts(...)`
- Add cluster and point rendering in `ExploreMapView`
- Add a preview-card selection model that routes into `ExplorePostDetailView`
- Reuse the existing Explore tab shell; while the map tab is active, disable outer pager swipe so map panning wins over parent gestures

### Phase 7: Fast Follow Ups

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
- Feed and detail payloads never include coordinates; map payloads include only privacy-safe public coordinates.
- Users can like and comment on posts.
- Users can externally share posts from the feed.
- Tapping a feed post opens a public post detail page.
- Tapping the feed comment icon opens a bottom-sheet comment view.
- The detail page shows inline comments plus privacy-safe telemetry and public species cards.
- The Explore surface includes a map tab backed by the same `explore_posts` model.
- Broad zoom levels render clusters instead of pin soup.
- Tapping a map point opens a compact preview card before opening full detail.
- Tapping a map preview card opens the same public Explore detail page used by feed posts.
- `obscured` posts render only with privacy-safe public coordinates derived server-side from scan geoprivacy rules.
- The bell icon shows an unread count and opens an in-app notifications sheet for likes and comments on the viewer's posts.
- The bell unread count is refreshed on foreground, on a lightweight fallback poll, and by a Supabase realtime subscription to the viewer's notification rows.
- Users can opt into remote Explore activity pushes separately from discovery-result alerts.
- Users can block and report from Explore surfaces.
- Unsharing removes the post from the public feed without deleting the scan.
- Posts disappear from Explore once their backing scan media is no longer available.
